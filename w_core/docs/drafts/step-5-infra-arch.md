# Passo 5: Empacotamento para o Edge (Infraestrutura)

## Objetivo
Empacotar o sistema para execucao em edge com release OTP e container Docker, mantendo persistencia SQLite em volume.

## Entregas da Sprint

1. Release de producao
- Comando: `MIX_ENV=prod mix release`
- Artefato: `_build/prod/rel/w_core`
- Runtime independente de Mix no container

2. Dockerfile multi-stage
- Build stage compila deps, assets e release
- Runner stage enxuto, com libs necessarias para OTP + SQLite
- Boot com entrypoint que roda migracoes e sobe app

3. Volume para SQLite
- `DATABASE_PATH=/data/w_core.db`
- `VOLUME ["/data"]`
- Persistencia mantida entre reinicios do container

## Diagrama Final

```text
                   +---------------------------------------+
                   |           Edge Device / VM            |
                   +---------------------------------------+
                                   |
                                   v
                     +-----------------------------+
                     | Docker Container (w_core)   |
                     |-----------------------------|
                     | Release OTP (bin/w_core)    |
                     | Phoenix + LiveView + ETS    |
                     | FlushWorker + Repo (SQLite) |
                     +-----------------------------+
                                   |
                                   v
                      +---------------------------+
                      | Volume /data              |
                      |---------------------------|
                      | w_core.db (SQLite file)   |
                      +---------------------------+
```

## Fluxo Completo (Boot ate Runtime)

1. Build da imagem
- Docker executa `mix deps.get`, `mix assets.deploy`, `mix release`
- Release final copiado para imagem runner

2. Start do container
- `entrypoint.sh` define envs (`PHX_SERVER`, `PORT`, `DATABASE_PATH`)
- Garante pasta do banco (`/data`)
- Executa migracoes com `bin/w_core eval "WCore.Release.migrate"`
- Sobe app com `bin/w_core start`

3. Runtime de dados
- Ingestao entra no `Telemetry.Ingestor` (compat: `Telemetry.Server`) (ETS, hot path)
- `FlushWorker` persiste em batch para SQLite (cold path)
- Dashboard recebe updates por PubSub (tempo real)

4. Persistencia
- Arquivo SQLite fica no volume `/data`
- Troca de container sem perda de dados

## Arquivos de Infra Criados

- `Dockerfile`
- `.dockerignore`
- `docker/entrypoint.sh`
- `lib/w_core/release.ex`

## Como Gerar Release Local

```bash
cd w_core
MIX_ENV=prod mix deps.get
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
```

## Como Rodar em Docker

```bash
docker build -t w_core:edge .

docker run --rm \
  -p 4000:4000 \
  -e SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  -e PHX_HOST=localhost \
  -e PORT=4000 \
  -e DATABASE_PATH=/data/w_core.db \
  -v w_core_data:/data \
  w_core:edge
```

## Variaveis de Ambiente (Producao)

- `SECRET_KEY_BASE` (obrigatoria)
- `PHX_HOST` (ex.: localhost, edge-gateway.local)
- `PORT` (padrao: 4000)
- `DATABASE_PATH` (padrao no container: /data/w_core.db)
- `RUN_MIGRATIONS` (padrao: true)

## Observacoes de Producao Edge

- SQLite em volume local reduz dependencia de rede.
- Batching no flush reduz lock contention no SQLite.
- Release OTP simplifica start/stop e reduz superficie de runtime.
