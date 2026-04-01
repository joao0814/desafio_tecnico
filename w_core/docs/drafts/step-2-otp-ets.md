# Passo 2: Core de Ingestão — ETS + GenServer

## Objetivo

Absorver eventos de sensores sem gargalo, usando ETS como buffer quente antes de persistência.

## O Que Foi Implementado

### 1. Tabela ETS

```elixir
:ets.new(:w_core_telemetry_cache, [
  :set,
  :public,
  :named_table,
  read_concurrency: true,   # Múltiplas leituras paralelas
  write_concurrency: true   # Múltiplas escritas paralelas
])
```

**Formato na memória:**

```
{node_id, status, payload, timestamp}
```

Exemplo: `{1, "ativo", %{pressao: 100}, ~U[2026-03-31 14:00:00Z]}`

### 2. Telemetry.Ingestor (GenServer de Ingestão)

`WCore.Telemetry.Ingestor` é o GenServer oficial da ingestão.
`WCore.Telemetry.Server` foi mantido como fachada de compatibilidade para chamadas legadas.

**Responsabilidades:**

- Criar tabela ETS no `init/1`
- Receber eventos via `GenServer.cast/2`
- Inserir na ETS com `:ets.insert/2` (O(1))
- Incrementar contador com `:ets.update_counter/3`
- Broadcast via PubSub para LiveView subscritos

**Interface:**

```elixir
WCore.Telemetry.Ingestor.ingest(node_id, status, payload)
# Compatível também via WCore.Telemetry.Server.ingest/3
```

### 3. Fluxo de Ingestão (Cast)

```
Sensor → ingest/3 → GenServer.cast → handle_cast → ETS.insert
                                   → ETS.update_counter
                                   → PubSub.broadcast
```

**Por que Cast (async)?**

- Não bloqueia o caller (sensor)
- GenServer processa em ordem (FIFO)
- Permite "fire-and-forget" semantics

### 4. FlushWorker (GenServer de Persistência)

**Responsabilidades:**

- Scheduler que roda a cada 5 segundos (`:flush` message)
- Extrai todos os dados da ETS com `:ets.tab2list/1`
- Batch insert no SQLite via Ecto (upsert com ON CONFLICT)
- Resíliente a erro de FK — não mata o worker

**Separação clara:**

- Server = hot path (ETS)
- FlushWorker = cold path (DB)

## Conceitos Críticos

### ETS > GenServer State

**GenServer State:**

```elixir
def handle_cast({:ingest, ...}, %{events: events}) do
  # Serializado — um evento por vez
  # Lock implícito = gargalo
  {:noreply, %{events: [new_event | events]}}
end
```

❌ **Problema:** Cada write aguarda a anterior

**ETS:**

```elixir
:ets.insert(:table, {node_id, status, payload, ts})
```

✅ **Benefício:** Múltiplas writers em paralelo com `write_concurrency: true`

### Read Concurrency

Com `read_concurrency: true`:

- Leitura em ETS não bloqueia escrita
- FlushWorker pode fazer `ets.tab2list` enquanto `ingest` insere
- Sem contention de lock

**Impacto:**

- Servidor com 100 sensores: ~100 ops/sec → 0 starvation
- Sem read_concurrency: read bloqueia, ingestão tranca

### O(1) Insertion

`:ets.insert/2` é O(1) (hash table).
**vs** Banco de dados:

- SQLite write = disk I/O = ~1-10ms por inserção
- ETS = RAM = ~1-10μs (1000x mais rápido)

### Update Counter (Atomicidade)

```elixir
:ets.update_counter(:table, node_id, {5, 1})
```

**O que faz:**

- Busca o tuple em position 5 (total_events_processed)
- Incrementa atomicamente em 1
- Sem race conditions

**Alternativa errada:**

```elixir
{_, _, _, count} = :ets.lookup(:table, node_id)
:ets.insert(:table, {node_id, ..., count + 1})  # RACE CONDITION!
```

## Padrão broadcast_metric

```elixir
Phoenix.PubSub.broadcast(WCore.PubSub, "telemetry:node:#{node_id}",
  {:metric_ingested, node_id, status, payload})
```

**Subscribers:**

```elixir
Phoenix.PubSub.subscribe(WCore.PubSub, "telemetry:node:#{node.id}")
```

Isso permite LiveView em tempo real sem polling.

## Migration de Índice Único

Para upsert via `ON CONFLICT (node_id)` funcionar em SQLite, precisa de constraint único:

```elixir
create unique_index(:node_metrics, [:node_id])
```

**Sem isso:**

```
[error] ON CONFLICT clause does not match any PRIMARY KEY or UNIQUE constraint
```

## Próximos Passos

1. Dashboard LiveView subscrevendo ao broadcast
2. Gráficos em tempo real (Apexcharts ou similar)
3. API JSON para consumo mobile/desktop
