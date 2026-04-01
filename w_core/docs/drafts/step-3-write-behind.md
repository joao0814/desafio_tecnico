# Passo 3: Write-Behind — Persistência sem Gargalo

## Objetivo

Escrever eventos no SQLite em batch, evitando lock contention e mantendo ingestão fluida.

## Arquitetura

```
┌─────────────────────────────────────────────────────┐
│ Telemetry.Ingestor (compat: Telemetry.Server)      │
│ • Recebe ingest via cast                            │
│ • ETS.insert (O(1), non-blocking)                   │
│ • ETS.update_counter (atomic count)                 │
│ • PubSub.broadcast (real-time)                      │
└────────────┬────────────────────────────────────────┘
             │ HOT PATH (microseconds)
             ↓
        ETS TABLE
    :w_core_telemetry_cache
             │
             ↓ (every 5 seconds)
┌─────────────────────────────────────────────────────┐
│ Telemetry.FlushWorker                               │
│ • ETS.tab2list (snapshot)                           │
│ • Repo.insert/update_all (batch)                    │
│ • Error handling (FK, constraint)                   │
│ • Logging (success count)                           │
└─────────────────────────────────────────────────────┘
             │ COLD PATH (milliseconds)
             ↓
        SQLite Database
       (durable storage)
```

## Por Que Write-Behind > Direct Writes

### Cenário ❌: Direct Insert (sem batching)

```elixir
def ingest(node_id, status, payload) do
  # Cada ingestão = lock + disk I/O
  %NodeMetric{}
  |> NodeMetric.changeset(...)
  |> Repo.insert()  # WRITES direto
end

# Com 1000 eventos/seg:
# 1000 locks
# 1000 disk I/O ops
# Contention massiva
```

**Problema:**

```
Time →
Lock 1  Lock 2  Lock 3  ... Lock 1000  (serializado, gargalo)
```

SQLite usa mutex global para writes. Uma thread aguarda a anterior terminar.

- **Latência:** 10-50ms por write
- **Throughput:** ~100 writes/sec max
- **Ingestão:** Sensors ficam bloqueados esperando DB

### Cenário ✅: Write-Behind (batching)

```elixir
# Ingestão: ETS (RAM)
def ingest(node_id, status, payload) do
  :ets.insert(@table, {...})
  :ets.update_counter(...)
  # Return immediately (1μs)
end

# Flush: Um batch grande a cada 5s
def handle_info(:flush, state) do
  all_events = :ets.tab2list(@table)
  # Repo.insert_all with on_conflict (uma única transação)
end

# Com 1000 eventos em 5s:
# 1 lock (batch)
# 1 disk I/O op
# Massivo throughput
```

**Benefício:**

```
ETS: {1000 inserts} → One DB lock (batch)
```

- **Latência ETS:** 1μs
- **Latência DB write:** ~100ms (para 1000 eventos juntos)
- **Throughput:** 200+ events/sec (sem contention)

## Trade-off: Eventual Consistency

### Garantias

**Imediato (Hot Path):**

- ✅ Evento está na memória
- ✅ Pode ser lido/queryado
- ✅ Broadcast vai para UI
- ✅ PubSub subscribers veem em tempo real

**Eventual (5 segundos):**

- ✅ Evento foi para SQLite
- ✅ Durável (survived crash)
- ✅ Pode rodar batch reports

### Você aceita perder dados?

**Cenário:** VM crash → ETS volatiliza → eventos perdidos.

**Resposta:** Depende do SLA:

- **Telemetria de sensores:** Sim, aceitável perder alguns eventos
- **Pagamento:** Não, precisa durabilidade imediata
- **Edge computing:** Sim (é o modelo padrão)

## Batching Evita Lock

### Analogia Real

**❌ Sem batching — Banco com 1 caixa:**

```
Cliente 1 → (10min) → Sai
Cliente 2 → aguarda → (10min) → Sai
Cliente 3 → aguarda → (10min) → Sai
...
```

Throughput: 6 clientes/hora

**✅ Com batching — Banco com 1 caixa BUT lotes:**

```
10 clientes chegam → caixa processa todos juntos (15min)
       ↓
10 clientes saem
10 clientes chegam → caixa processa (15min)
```

Throughput: 40 clientes/hora (7x melhor!)

### SQL Perspective

**❌ Sem batching:**

```sql
INSERT INTO node_metrics (...) VALUES (...) -- Lock, Disk I/O
INSERT INTO node_metrics (...) VALUES (...) -- Lock, Disk I/O
INSERT INTO node_metrics (...) VALUES (...) -- Lock, Disk I/O
```

3 transações = 3 commits

**✅ Com batching:**

```sql
INSERT INTO node_metrics (...) VALUES (...)
     UNION
INSERT INTO node_metrics (...) VALUES (...)
     UNION
INSERT INTO node_metrics (...) VALUES (...) -- 1 Lock, 1 Disk I/O, 1 Commit
```

1 transação = 1 commit

## Resiliência do Flush Worker

### Isolamento: Server vs FlushWorker

```
        Ingestão (não bloqueia)
        Telemetry.Ingestor        (GenServer 1)
              ↓
         ETS writes (non-blocking)
              ↓
        FlushWorker                (GenServer 2)
              ↓
         DB writes (blocking, mas isolado)
```

**Cenário 1:** DB cai durante flush

- ✅ Ingestão continua (eventos na ETS)
- ✅ FlushWorker loga erro, reschedule
- ✅ Próximo flush pega tudo novamente

**Cenário 2:** Flush trava (DB locked)

- ✅ Ingestão continua (ETS é fast)
- ✅ FlushWorker fica aguardando sua vez
- ✅ Sem starvation de ingestão

### Error Handling

```elixir
# Se FK constraint falha (node_id inexistente)
try do
  Repo.insert(...)
rescue
  Ecto.ConstraintError ->
    Logger.debug("Skipping #{node_id} — node doesn't exist")
    :error
end

# Worker continua, não morre
# Próximo evento do mesmo node_id vai novamente tentar
```

## Frequência de Flush

### Parâmetro: @interval = 5_000 (5 segundos)

**Mais frequente (1s):**

- ✅ Durabilidade melhor
- ❌ Mais DB load
- ❌ Mais lock contention

**Menos frequente (30s):**

- ✅ Menos DB load
- ❌ Maior janela de loss (ETS só)
- ❌ Latência histórica: 30s até aparecer em reports

**5s (sweet spot):**

- ✅ Cobre ~5000 eventos (1000/sec × 5s)
- ✅ DB write é single-digit millisecond
- ✅ RTO (Recovery Time Objective): ~5s
- ✅ RPO (Recovery Point Objective): ~5s

## Observabilidade

### Logs Produzidos

```
[info] Telemetry.Ingestor started — ETS cache initialized
[info] Telemetry.FlushWorker started — flush interval: 5000ms
[info] Telemetry.FlushWorker flushed 42/42 metrics in 23ms
[info] Telemetry.FlushWorker flushed 128/128 metrics in 45ms
[debug] Skipping node_metric:999 flush — node doesn't exist
```

### Métricas para Monitorar

1. **Flush latency:** Quanto tempo leva escrever no DB
2. **ETS size at flush:** Quantos eventos acumulam entre flushes
3. **Error rate:** % de eventos que falharam (FK, constraint)
4. **Flush frequency:** Vezes/min que o worker executa

## Próximos Passos

1. Dashboard LiveView subscrevendo "telemetry:metrics"
2. Gráficos em tempo real dos eventos mais recentes
3. Persistência de histórico > 24h em columnar DB (parquet/arrow)
4. Cleanup: remover eventos antigos de ETS periodicamente
