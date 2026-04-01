# Passo 1: Fundação e Perímetro de Segurança

## O que foi implementado

- Inicialização do projeto Phoenix com SQLite3 para Edge Computing.
- Sistema de autenticação LiveView via `phx.gen.auth`.
- Modelagem de dados para Telemetria (`Nodes` e `NodeMetrics`).

## Decisões Arquiteturais

- **Contextos Isolados:** `Accounts` lida com operadores; `Telemetry` lida com os dados da planta.
- **SQLite:** Escolhido por ser a diretriz para rodar localmente no servidor da Planta 42 (Edge), garantindo persistência sem dependência de rede externa.

## Por Que NÃO Usar Banco Como Source de Ingestão?

**Cenário tentador:** "Vou mandar cada evento direto para o SQLite"

```elixir
# ❌ NÃO FAZER ISSO
def ingest(node_id, status, payload) do
  %NodeMetric{}
  |> NodeMetric.changeset(%{...})
  |> Repo.insert()  # WRITE direto no disco a cada evento!
end
```

**Problemas:**

1. **Gargalo de Disco:** SQLite usa mutex para escrita. 1000 eventos/seg = 1000 tentativas de lock. O disco fica saturado a ~100 IO/sec max.
2. **Latência Inaceitável:** Cada ingestão espera 10-50ms pelo Repo.insert. Sensor fica bloqueado. Timeout!
3. **Contention:** Múltiplos sensores trancam a DB um esperando o outro. Banco vira ponto único de falha.
4. **Batidas na Aplicação:** Se DB cai, toda ingestão para.

**Solução correta: Camadas de Persistência**

```
Sensor → ETS (RAM, ~1μs) ──┐
                           ├→ FlushWorker (a cada 5s) → SQLite (durável)
                          ↓ PubSub (LiveView quente)
```

1. **ETS = Hot Buffer:** Escreve em RAM com `read_concurrency: true`, O(1)
2. **FlushWorker = Batch Persistence:** A cada 5 segundos, joga tudo no SQLite de uma vez
3. **Broadcast = Real-time UI:** PubSub notifica LiveView sem esperar DB

**Resultado:**

- Ingestão: O(1), non-blocking
- Durabilidade: Garantida em batch a cada 5s
- Real-time: WebSocket já traz dados da ETS

## Próximos Passos

Preparar a tabela ETS para absorver o tráfego de sensores em memória antes de persistir no SQLite.
