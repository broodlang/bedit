# syntax=docker/dockerfile:1
# ^^^^^^^^^^^^^^^^^^^^^^^^^^ comment
FROM rust:1.80 AS build
# ^^ keyword   ^^ keyword
ARG PROFILE=release
# ^ keyword
WORKDIR /src
COPY . .
RUN cargo build --profile "$PROFILE" \
    && strip target/release/counter

FROM debian:bookworm-slim
LABEL org.opencontainers.image.title="counter"
ENV RUST_LOG=info PORT=8080
# ^ keyword
COPY --from=build /src/target/release/counter /usr/local/bin/counter
RUN <<EOT
apt-get update
apt-get install -y ca-certificates
EOT
EXPOSE 8080
# ^^^^ keyword
USER nobody
# ^^ keyword
HEALTHCHECK CMD ["counter", "--check"]
ENTRYPOINT ["counter"]
CMD ["--port", "8080"]
