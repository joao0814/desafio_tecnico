# Passo 4: Simulacao de Caos (Testes Rigorosos)

## Objetivo
Provar, com evidencias automatizadas, que o sistema suporta pancada de concorrencia real sem perder contagem no hot path (ETS) e sem divergir no cold path (SQLite).

## Cenario de Caos
- Volume: 10_000 eventos concorrentes
- Topologia: 10 nodes (1_000 eventos por node)
- Ingestao: `Task.async_stream/3` com alta concorrencia
- Hot path: `WCore.Telemetry.Ingestor.ingest/3` (compat: `WCore.Telemetry.Server.ingest/3`) -> ETS
- Cold path: `WCore.Telemetry.FlushWorker` -> upsert em SQLite

Arquivo de teste:
- [test/w_core/telemetry_chaos_test.exs](test/w_core/telemetry_chaos_test.exs)

## Asserts Fortes (Evidencia)

### 1. Integridade da contagem no ETS
Depois de enviar 10_000 eventos concorrentes, o teste exige:
- soma global no ETS == 10_000
- cada node com exatamente 1_000 eventos

Trecho validado:
```elixir
assert ets_total_count() == 10_000
assert Enum.all?(node_ids, fn id -> ets_count_for_node(id) == 1_000 end)
```

### 2. Integridade da persistencia no SQLite
Apos disparar flush manual (`send(flush_pid, :flush)`), o teste exige:
- soma persistida no banco == 10_000
- cada node persistido com 1_000

Trecho validado:
```elixir
assert persisted_total_count(node_ids) == 10_000
assert Enum.all?(node_ids, fn id -> persisted_count_for_node(id) == 1_000 end)
```

## Metricas Coletadas
O teste mede tempos de ponta a ponta para evidencia de robustez:
- `ingest_elapsed_ms`: tempo total para publicar 10_000 eventos concorrentes
- `flush_elapsed_ms`: tempo para o write-behind refletir no SQLite

No teste, ambos sao obrigatoriamente positivos:
```elixir
assert ingest_elapsed_ms > 0
assert flush_elapsed_ms > 0
```

## Race Conditions Cobertas
- concorrencia massiva no envio de eventos (10_000 tarefas)
- consistencia do contador por node no ETS
- consistencia eventual apos flush
- verificacao ativa com polling e timeout para detectar atrasos ou perdas

## Ajuste Tecnico Necessario
Para manter consistencia entre ETS e SQLite no cenario de caos, o flush foi ajustado para persistir `event_count` acumulado do ETS (set), em vez de incrementar `+1` por ciclo de flush.

Arquivo ajustado:
- [lib/w_core/telemetry/flush_worker.ex](lib/w_core/telemetry/flush_worker.ex)

Isso evita subcontagem em lotes grandes e garante que o valor persistido reflita exatamente o contador em memoria para cada node.
