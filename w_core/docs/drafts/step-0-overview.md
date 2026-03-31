# Passo 0: Visão Geral e Decisões Arquiteturais

## Objetivo
Preparar o terreno correto para um sistema de telemetria em Edge Computing com alta concorrência e durabilidade.

## Stack Escolhido
- **Framework:** Phoenix 1.8 com LiveView (real-time UI)
- **Banco:** SQLite3 (persistência local, sem rede externa)
- **Armazenamento Quente:** ETS (Erlang Term Storage)
- **OTP:** GenServer + Supervisor + PubSub
- **Linguagem:** Elixir 1.19

## Arquitetura Mental

```
┌─────────────────────────────────────────────────────────────┐
│ INGESTÃO (Hot Path) → ETS (Ram, write_concurrency: true)    │
│                      ↓ Flush periodicamente                  │
│                      ↓ Pula para SQLite                      │
│              Telemetry.Server (GenServer)                    │
│              + FlushWorker (GenServer)                       │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ PERSISTÊNCIA (Cold Path) → SQLite3 (durabilidade)            │
│                           Backup de sensores                 │
│                           Queries históricas                 │
│                           Relatórios batch                   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ BROADCAST (Real-time) → Phoenix.PubSub                       │
│                        LiveView updates                      │
│                        WebSocket subscriptions               │
└─────────────────────────────────────────────────────────────┘
```

## Decisões Críticas

### 1. **Por que ETS e não GenServer state?**
- **ETS** oferece escrita O(1) com `read_concurrency: true` + `write_concurrency: true`
- **GenServer state** seria serializado por um único processo, criando gargalo
- ETS permite centenas de sensores em paralelo sem lock contention

### 2. **Por que não usar Banco como source de ingestão?**
- **Problema:** Escrever direto no SQLite para cada evento (1000 eventos/seg) mataria o disco e lockaria a DB
- **Solução:** ETS absorve o tráfego em memória, flushando em batches a cada 5 segundos
- **Resultado:** Banco fica para durabilidade e historical queries, não hot path

### 3. **Por que Flush Worker separado?**
- GenServer de ingestão fica "clean" e responsável só por ETS
- Worker de flush lida com DB, retry, erro handling sem bloquear ingestão
- Se DB cair, ingestão continua — dados na ETS

### 4. **Autenticação LiveView (phx.gen.auth)**
- Cada user tem seu próprio `Scope`, isolando nodes e métricas
- PubSub usa `user:#{user_id}:nodes` como topic para multi-tenant safety

## Dependências Críticas

```elixir
{:phoenix, "~> 1.8.5"}          # Web framework
{:phoenix_live_view, "~> 1.1.0"} # Real-time UI
{:ecto_sqlite3, ">= 0.0.0"}       # Persistência
{:pbkdf2_elixir, "~> 2.0"}        # Hash de senha
```

## Próximos Passos
1. **Sprint 1:** Autenticação + Contexto Telemetry
2. **Sprint 2:** ETS + GenServer de ingestão
3. **Sprint 3:** Dashboard LiveView
4. **Sprint 4:** API JSON + Edge sync
