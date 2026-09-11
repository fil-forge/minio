# Build MinIO from the source in this repository.
#
# WHAT THIS REPLACED, AND WHY
#
# Upstream's Dockerfile was `FROM minio/minio:latest` plus a copy of a
# prebuilt binary -- a release-packaging file, not a build. On 2026-09-11
# minio/minio was withdrawn from Docker Hub, every tag with it, so that base
# image no longer exists and the file was both circular and dead. The same
# applies to Dockerfile.cicd (`FROM minio/minio:edge`). Dockerfile.hotfix
# still works in principle but fetches its binaries from dl.min.io, which is
# another artifact host we do not control.
#
# None of upstream's six Dockerfiles builds from source: they all package a
# binary produced elsewhere, by a pipeline that was never in this repository.
# Upstream is archived (2026-04-25), so that pipeline is not coming back.
# This builds the binary here instead. Git history has the original.
#
# The runtime below is deliberately NOT upstream's ubi-micro: this exact
# combination (bookworm build, bookworm-slim runtime, upstream's entrypoint)
# was validated against the full Forge stack e2e suite, and ubi-micro was
# not. Their hotfix image targets RedHat certification, which is not our
# requirement.

FROM --platform=$BUILDPLATFORM golang:1.27-bookworm AS build
ARG TARGETARCH
ARG TARGETOS=linux
WORKDIR /src
COPY . .
# Upstream's own build line, from the Makefile `build` target: -tags kqueue
# and -trimpath are theirs. Their version ldflags are omitted, so
# `minio --version` reports a dev build.
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -tags kqueue -trimpath -o /minio .

FROM debian:bookworm-slim AS prod

# Corresponding Source for the AGPLv3 binary in this image is this
# repository at the built ref, which includes the build recipe. Stated here
# so it travels with the image rather than only in a registry description.
LABEL org.opencontainers.image.source="https://github.com/fil-forge/minio" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.title="MinIO" \
      org.opencontainers.image.description="MinIO built from source. Corresponding Source: https://github.com/fil-forge/minio at the tag matching this image's tag."

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /minio /usr/bin/minio
# Upstream's entrypoint, unmodified: it prepends `minio` to a bare
# subcommand, which is the image contract callers rely on
# (`command: server /data ...`).
COPY dockerscripts/docker-entrypoint.sh /usr/bin/docker-entrypoint.sh
RUN chmod +x /usr/bin/docker-entrypoint.sh
# Same paths upstream's hotfix image uses.
COPY LICENSE /licenses/LICENSE
COPY CREDITS /licenses/CREDITS
COPY NOTICE  /licenses/NOTICE

# 9000 S3 API, 9001 console.
EXPOSE 9000 9001
VOLUME ["/data"]
ENTRYPOINT ["/usr/bin/docker-entrypoint.sh"]
CMD ["minio"]
