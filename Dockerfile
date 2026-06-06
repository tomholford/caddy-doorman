# syntax=docker/dockerfile:1
#
# caddy-doorman — a batteries-included Caddy image.
#
# Built with xcaddy as a two-stage build: the builder stage compiles a custom
# Caddy binary with the plugin stack, then the binary is overlaid onto the
# slim official runtime image.
#
# Keep the base tag pinned (caddy:X.Y.Z) so the CI workflow can derive semver
# image tags from it, and so Renovate can open a PR when Caddy releases.
FROM caddy:2.11.4-builder AS builder

# CACHEBUST lets the monthly CI rebuild force a fresh plugin fetch (plugins are
# referenced unpinned, so they only move when this RUN layer is rebuilt). It is
# left at the default for dispatch/push builds so the layer stays cached.
ARG CACHEBUST=static

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    echo "cachebust=${CACHEBUST}" && xcaddy build \
        --with pkg.jsn.cam/caddy-defender \
        --with github.com/mholt/caddy-ratelimit \
        --with github.com/caddy-dns/namecheap \
        --with github.com/caddy-dns/cloudflare \
        --with github.com/monobilisim/caddy-ip-list

FROM caddy:2.11.4

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
