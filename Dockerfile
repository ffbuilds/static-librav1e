
# bump: rav1e /RAV1E_VERSION=([\d.]+)/ https://github.com/xiph/rav1e.git|/\d+\./|*
# bump: rav1e after ./hashupdate Dockerfile RAV1E $LATEST
# bump: rav1e link "Release notes" https://github.com/xiph/rav1e/releases/tag/v$LATEST
ARG RAV1E_VERSION=0.5.1
ARG RAV1E_URL="https://github.com/xiph/rav1e/archive/v$RAV1E_VERSION.tar.gz"
ARG RAV1E_SHA256=7b3060e8305e47f10b79f3a3b3b6adc3a56d7a58b2cb14e86951cc28e1b089fd

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
  case ${ALPINE_VERSION} in \
    edge) \
      apk_pkgs="cargo-c" \
    ;; \
  esac && \
  apk add --no-cache --virtual build \
    rust cargo git pkgconf openssl-dev nasm ${apk_pkgs} && \
  if [ "${ALPINE_VERSION}" != "edge" ]; then \
    # debug builds a bit faster and we don't care about runtime speed
    cargo install --debug --version 0.9.5 cargo-c; \
  fi && \
  cargo cinstall --release && \
  # cargo-c/alpine rustc results in Libs.private depend on gcc_s
  # https://gitlab.alpinelinux.org/alpine/aports/-/issues/11806
  sed -i 's/-lgcc_s//' /usr/local/lib/pkgconfig/rav1e.pc && \
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
