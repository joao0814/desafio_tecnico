# Passo 4: LiveView em Tempo Real

## Objetivo

Entregar visualizacao instantanea da telemetria sem polling, com dashboard protegido por autenticacao.

## O Que Foi Entregue

- Dashboard protegido em rota autenticada: `/dashboard`
- LiveView com subscribe no PubSub por node
- Leitura inicial direta da ETS no mount
- Update incremental por eventos de ingestao

## Fluxo

1. Usuario autenticado abre `/dashboard`
2. LiveView carrega os nodes do usuario
3. LiveView assina topicos `telemetry:node:<node_id>`
4. LiveView busca estado inicial na ETS (`:w_core_telemetry_cache`)
5. A cada ingestao, evento PubSub chega no LiveView
6. UI atualiza em lote com janela curta (debounce), evitando flood visual

## Conceitos Aplicados

### UI reativa

A tela reage aos eventos do sistema, sem refresh manual e sem polling.

### Evitar polling

Nao fazemos consultas periodicas no browser para buscar dados.
O servidor empurra os eventos via PubSub e o LiveView atualiza.

### Leitura direta da memoria

O render inicial le a ETS diretamente. Isso reduz latencia e evita sobrecarga de disco.

## Como evitamos flood no PubSub

Aplicamos duas estrategias:

1. Assinatura seletiva por node

- O dashboard assina apenas topicos dos nodes do usuario.
- Nao usa o topico global para todos os eventos.
- Resultado: menos mensagens por cliente.

2. Coalescencia de render (janela de 400ms)

- Ao receber eventos, o LiveView agenda um unico refresh curto.
- Eventos que chegam nessa janela sao consolidados.
- Resultado: evita re-render por evento e reduz carga da UI.

## Por que nao usar DB no render

Render com SQLite no hot path traz custo de lock e I/O de disco.
Em telemetria, a prioridade e latencia baixa e experiencia em tempo real.

Ao ler da ETS no render:

- Menor latencia
- Sem lock de escrita no banco
- Menor risco de gargalo sob pico

O banco continua como camada de durabilidade (write-behind), nao como fonte imediata de tela.

## Arquivos principais

- `lib/w_core_web/live/telemetry_live/dashboard.ex`
- `lib/w_core_web/router.ex`
- `test/w_core_web/live/telemetry_live/dashboard_test.exs`

## Resultado

Dashboard em tempo real, protegido, sem polling, usando memoria como fonte quente e com controle de flood de eventos.
