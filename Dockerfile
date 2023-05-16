# syntax=docker/dockerfile:1

# bump: rav1e /RAV1E_VERSION=([\d.]+)/ https://github.com/xiph/rav1e.git|/\d+\./|*
# bump: rav1e after ./hashupdate Dockerfile RAV1E $LATEST
# bump: rav1e link "Release notes" https://github.com/xiph/rav1e/releases/tag/v$LATEST
ARG RAV1E_VERSION=0.6.6
ARG RAV1E_URL="https://github.com/xiph/rav1e/archive/v$RAV1E_VERSION.tar.gz"
ARG RAV1E_SHA256=723696e93acbe03666213fbc559044f3cae5b8b888b2ddae667402403cff51e5

# Must be specified
ARG ALPINE_VERSION

FROM alpine:${ALPINE_VERSION} AS base

FROM base AS download
ARG RAV1E_URL
ARG RAV1E_SHA256
ARG WGET_OPTS="--retry-on-host-error --retry-on-http-error=429,500,502,503 -nv"
WORKDIR /tmp
RUN \
  apk add --no-cache --virtual download \
    coreutils wget tar && \
  wget $WGET_OPTS -O rav1e.tar.gz "$RAV1E_URL" && \
  echo "$RAV1E_SHA256  rav1e.tar.gz" | sha256sum --status -c - && \
  mkdir rav1e && \
  tar xf rav1e.tar.gz -C rav1e --strip-components=1 && \
  rm rav1e.tar.gz && \
  apk del download

FROM base AS build
COPY --from=download /tmp/rav1e/ /tmp/rav1e/
WORKDIR /tmp/rav1e
ARG ALPINE_VERSION
# Fails on fetch without CARGO_NET_GIT_FETCH_WITH_CLI=true and git installed
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true
RUN \
  apk add --no-cache --virtual build \
    rust cargo git pkgconf openssl-dev nasm cargo-c && \
  # RUSTFLAGS need to fix gcc_s
  # https://gitlab.alpinelinux.org/alpine/aports/-/issues/11806
  RUSTFLAGS="-C target-feature=+crt-static" cargo cinstall --release && \
  # Sanity tests
  pkg-config --exists --modversion --path rav1e && \
  ar -t /usr/local/lib/librav1e.a && \
  readelf -h /usr/local/lib/librav1e.a && \
  # Cleanup
  apk del build

FROM scratch
ARG RAV1E_VERSION
COPY --from=build /usr/local/lib/pkgconfig/rav1e.pc /usr/local/lib/pkgconfig/rav1e.pc
COPY --from=build /usr/local/lib/librav1e.a /usr/local/lib/librav1e.a
COPY --from=build /usr/local/include/rav1e/ /usr/local/include/rav1e/
