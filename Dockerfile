# Build: doge transpileert naar Rust, dus de build-stage heeft de Rust-toolchain nodig.
FROM rust:slim AS build
RUN cargo install dogelang --version 0.3.6
WORKDIR /app
COPY doge.toml main.doge ./
COPY lib/ lib/
COPY web/ web/
COPY app/ app/
RUN doge build

FROM node:22-slim AS assets
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY build-js.mjs ./
COPY static/ static/
RUN npm run build

FROM debian:stable-slim
# Vaste UID/GID zodat data/ op de host van een gewone gebruiker is (zie README).
ARG UID=1000
ARG GID=1000
RUN groupadd --gid "$GID" boekhond && useradd --uid "$UID" --gid "$GID" --no-create-home --shell /usr/sbin/nologin boekhond
WORKDIR /app
COPY --from=build /app/boekhond /usr/local/bin/boekhond
COPY static/ static/
# static/js/ is gitignored; de gecompileerde JS komt uit de assets-stage.
COPY --from=assets /app/static/js static/js
RUN mkdir -p /app/data && chown "$UID:$GID" /app/data
USER boekhond
VOLUME /app/data
EXPOSE 8085
# Het slim-image heeft geen curl; bash /dev/tcp volstaat. Host 127.0.0.1 is altijd toegestaan.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/${POORT:-8085} && printf 'GET /health HTTP/1.1\\r\\nHost: 127.0.0.1\\r\\n\\r\\n' >&3 && read -r regel <&3 && [[ $regel == *' 200 '* ]]"]
CMD ["boekhond"]
