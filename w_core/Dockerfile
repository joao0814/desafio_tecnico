# syntax=docker/dockerfile:1.7

ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28
ARG DEBIAN_VERSION=trixie

FROM elixir:${ELIXIR_VERSION}-otp-${OTP_VERSION} AS builder

ENV MIX_ENV=prod
WORKDIR /app

RUN apt-get update && \
  apt-get install -y --no-install-recommends build-essential git curl ca-certificates && \
  rm -rf /var/lib/apt/lists/*

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only ${MIX_ENV}
RUN mix deps.compile

COPY lib lib
COPY priv priv
COPY assets assets

RUN mix compile
RUN mix assets.deploy
RUN mix release

FROM debian:${DEBIAN_VERSION}-slim AS runner

RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  ca-certificates \
  openssl \
  libstdc++6 \
  libncurses6 \
  sqlite3 \
  libsqlite3-0 && \
  rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN useradd --system --create-home --home-dir /app app

COPY --from=builder /app/_build/prod/rel/w_core ./
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && chown -R app:app /app

ENV HOME=/app \
  PHX_SERVER=true \
  PORT=4000 \
  DATABASE_PATH=/data/w_core.db \
  RUN_MIGRATIONS=true \
  ELIXIR_ERL_OPTIONS=+fnu

VOLUME ["/data"]
EXPOSE 4000

ENTRYPOINT ["/entrypoint.sh"]
CMD ["start"]
