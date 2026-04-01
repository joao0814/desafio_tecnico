#!/bin/sh
set -eu

: "${DATABASE_PATH:=/data/w_core.db}"
: "${PHX_SERVER:=true}"
: "${PORT:=4000}"
: "${RUN_MIGRATIONS:=true}"

export DATABASE_PATH PHX_SERVER PORT RUN_MIGRATIONS

mkdir -p "$(dirname "$DATABASE_PATH")"

if [ "$RUN_MIGRATIONS" = "true" ]; then
  /app/bin/w_core eval "WCore.Release.migrate"
fi

exec /app/bin/w_core "$@"
