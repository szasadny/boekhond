# Build: doge transpileert naar Rust, dus de build-stage heeft de Rust-toolchain nodig.
FROM rust:slim AS build
RUN cargo install dogelang
WORKDIR /app
COPY doge.toml main.doge ./
COPY lib/ lib/
COPY web/ web/
COPY app/ app/
RUN doge build

# Assets: Dogescript (static/djs/) -> JS (static/js/) via de npm-toolchain.
FROM node:22-slim AS assets
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY build-js.mjs ./
COPY static/ static/
RUN npm run build

FROM debian:stable-slim
WORKDIR /app
COPY --from=build /app/boekhond /usr/local/bin/boekhond
COPY static/ static/
# Overlay de gecompileerde JS uit de assets-stage (static/js/ is gitignored, wordt hier gebouwd).
COPY --from=assets /app/static/js static/js
VOLUME /app/data
EXPOSE 8085
CMD ["boekhond"]
