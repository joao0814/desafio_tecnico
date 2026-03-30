# Passo 1: Fundação e Perímetro de Segurança

## O que foi implementado
- Inicialização do projeto Phoenix com SQLite3 para Edge Computing.
- Sistema de autenticação LiveView via `phx.gen.auth`.
- Modelagem de dados para Telemetria (`Nodes` e `NodeMetrics`).

## Decisões Arquiteturais
- **Contextos Isolados:** `Accounts` lida com operadores; `Telemetry` lida com os dados da planta.
- **SQLite:** Escolhido por ser a diretriz para rodar localmente no servidor da Planta 42 (Edge), garantindo persistência sem dependência de rede externa.

## Próximos Passos
Preparar a tabela ETS para absorver o tráfego de sensores em memória antes de persistir no SQLite.