# syntax=docker/dockerfile:1

ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27.3.4.9
ARG BUILDER_DEBIAN_VERSION=bookworm-20260316-slim
ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${BUILDER_DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:bookworm-slim"

FROM node:20-bookworm-slim AS assets

WORKDIR /app/assets

COPY assets/package.json assets/package-lock.json ./

RUN npm ci

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod
ENV ERL_FLAGS="+JPperf true"

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only ${MIX_ENV}
RUN mkdir config

COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets
COPY --from=assets /app/assets/node_modules assets/node_modules

RUN mix assets.deploy

COPY config/runtime.exs config/
COPY rel rel

RUN mix release

FROM ${RUNNER_IMAGE} AS runner

RUN apt-get update -y && apt-get install -y \
    libncurses6 \
    libsqlite3-0 \
    libstdc++6 \
    locales \
    openssl \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

ENV MIX_ENV=prod

COPY --from=builder /app/_build/${MIX_ENV}/rel/jido_codemode ./
COPY --chown=nobody:root northwind.sqlite ./northwind.sqlite

EXPOSE 4000

USER nobody

CMD ["/app/bin/server"]
