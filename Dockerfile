# Build: doge transpileert naar Rust, dus de build-stage heeft de Rust-toolchain nodig.
FROM rust:slim AS build
RUN cargo install dogelang
WORKDIR /app
COPY doge.toml main.doge ./
COPY lib/ lib/
COPY app/ app/
RUN doge build

# Vanaf fase 2 komt hier een node-stage bij die static/djs/ (Dogescript) naar static/js/ compileert.

FROM debian:stable-slim
WORKDIR /app
COPY --from=build /app/grootboek /usr/local/bin/grootboek
COPY static/ static/
VOLUME /app/data
EXPOSE 8085
CMD ["grootboek"]
