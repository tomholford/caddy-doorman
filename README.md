# caddy-doorman

[![License](https://img.shields.io/github/license/tomholford/caddy-doorman)](LICENSE)
[![Build & Publish](https://img.shields.io/github/actions/workflow/status/tomholford/caddy-doorman/build.yml)](https://github.com/tomholford/caddy-doorman/actions)

A batteries-included Docker image of [Caddy](https://caddyserver.com/) preloaded with useful plugins for running a secure, production-ready reverse proxy.

Think of it as your site's **doorman** — it stands at the door, checks IDs (defender), enforces the rules (rate limiting), and handles the paperwork (automatic HTTPS via DNS-01).

## Why caddy-doorman?

Building custom Caddy images with `xcaddy` every time a new version drops (or a plugin updates) is annoying. This image gives you a curated, opinionated set of plugins that most self-hosters actually need for public-facing services:

- Strong bot/scraper protection
- Abuse prevention via rate limiting
- Reliable wildcard / multi-domain HTTPS using DNS challenges

## Included Plugins

| Plugin | Purpose |
|--------|---------|
| [caddy-defender](https://github.com/jasonlovesdoggo/caddy-defender) | Block or tarpit requests from AI scrapers, cloud providers (AWS, GCP, Azure, etc.), and custom IP ranges. Great for protecting your content from being used to train models. |
| [caddy-ratelimit](https://github.com/mholt/caddy-ratelimit) | Flexible, high-performance HTTP rate limiting (including distributed via Redis if you need it). |
| [caddy-dns/namecheap](https://github.com/caddy-dns/namecheap) | Namecheap DNS provider for ACME DNS-01 challenges (Let's Encrypt / ZeroSSL). Use this when you manage DNS at Namecheap. |
| [caddy-dns/cloudflare](https://github.com/caddy-dns/cloudflare) | Cloudflare DNS provider for ACME DNS-01 challenges. The most common choice for wildcard / multi-domain certificates. |
| [caddy-ip-list](https://github.com/monobilisim/caddy-ip-list) | Dynamic IP-range source for `trusted_proxies`. Fetches and refreshes Cloudflare's edge ranges so `{client_ip}` resolves to the real visitor IP behind the proxy. |

The image is rebuilt automatically every month (to refresh plugins) and whenever the Caddy base version changes.

## Quick Start

### Pull the image

```bash
docker pull ghcr.io/tomholford/caddy-doorman:latest
```

### Basic docker run

```bash
docker run -d \
  --name caddy-doorman \
  -p 80:80 -p 443:443 -p 443:443/udp \
  -v $PWD/Caddyfile:/etc/caddy/Caddyfile \
  -v caddy-data:/data \
  -v caddy-config:/config \
  -e NAMECHEAP_API_KEY=your_key \
  -e NAMECHEAP_API_USER=your_username \
  ghcr.io/tomholford/caddy-doorman:latest
```

### docker-compose example

```yaml
version: "3.8"

services:
  caddy:
    image: ghcr.io/tomholford/caddy-doorman:latest
    container_name: caddy-doorman
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy-data:/data
      - caddy-config:/config
    environment:
      - NAMECHEAP_API_KEY=${NAMECHEAP_API_KEY}
      - NAMECHEAP_API_USER=${NAMECHEAP_API_USER}
    # Optional: if you want to use defender's real client IP detection
    # extra_hosts:
    #   - "host.docker.internal:host-gateway"

volumes:
  caddy-data:
  caddy-config:
```

## Configuration Examples

### Namecheap DNS-01 for certificates

```caddyfile
{
    # Global options
    email you@example.com
}

example.com {
    # Use Namecheap for DNS challenges
    tls {
        dns namecheap {
            api_key {env.NAMECHEAP_API_KEY}
            user {env.NAMECHEAP_API_USER}
        }
    }

    reverse_proxy backend:8080
}
```

**Required environment variables for Namecheap:**

- `NAMECHEAP_API_KEY`
- `NAMECHEAP_API_USER`

Get them from your Namecheap account → Domain List → Advanced DNS → Dynamic DNS.

### Cloudflare DNS-01 for certificates

```caddyfile
example.com {
    tls {
        dns cloudflare {env.CF_API_TOKEN}
    }

    reverse_proxy backend:8080
}
```

**Required environment variable for Cloudflare:**

- `CF_API_TOKEN` — a Cloudflare API token with `Zone:DNS:Edit` permission for the zone.

### Real client IP behind Cloudflare

If you run behind Cloudflare's proxy, declare it as a trusted proxy so `{client_ip}` (used by rate limiting and defender) resolves to the real visitor IP rather than Cloudflare's edge. The bundled `caddy-ip-list` plugin fetches and refreshes Cloudflare's ranges automatically:

```caddyfile
{
    servers {
        trusted_proxies list {
            url https://www.cloudflare.com/ips-v4
            url https://www.cloudflare.com/ips-v6
            interval 12h
            timeout 15s
        }
        client_ip_headers CF-Connecting-IP
    }
}
```

### caddy-defender (basic protection)

```caddyfile
{
    order defender before reverse_proxy
}

example.com {
    # The first token is the responder: block | tarpit | garbage | drop |
    # redirect | custom | ratelimit. Mix predefined range keys with your own CIDRs.
    defender block {
        ranges openai aws gcloud azurepubliccloud githubcopilot deepseek 203.0.113.0/24
    }

    reverse_proxy backend:8080
}
```

See the [caddy-defender documentation](https://github.com/jasonlovesdoggo/caddy-defender) for all available ranges and responder options.

### Rate limiting

```caddyfile
{
    order rate_limit before reverse_proxy
}

example.com {
    rate_limit {
        zone perip {
            key {client_ip}
            events 100
            window 1m
        }
    }

    reverse_proxy backend:8080
}
```

Full options in the [caddy-ratelimit docs](https://github.com/mholt/caddy-ratelimit). Zones can also `match` on path/method for finer-grained limits.

> See [`examples/Caddyfile`](examples/Caddyfile) for one config that combines DNS certs, defender, rate limiting, and Cloudflare real-IP — it's validated in CI.

## Image Tags

- `latest` — newest build (latest stable Caddy + current plugins)
- `2` — latest 2.x build
- `2.11` — latest 2.11.x build
- `2.11.4` — a specific Caddy version (plugins as of that build)

Plugins are unpinned, so the monthly rebuild refreshes them under the same tags. All images are multi-arch (`linux/amd64`, `linux/arm64`).

## Building Locally

Clone and build the image (it's a thin `xcaddy` wrapper — see [`Dockerfile`](Dockerfile)):

```bash
git clone https://github.com/tomholford/caddy-doorman
cd caddy-doorman
docker build -t caddy-doorman .
```

Or build just the binary with `xcaddy`. Note caddy-defender's module path is the vanity import `pkg.jsn.cam/caddy-defender`:

```bash
xcaddy build \
    --with pkg.jsn.cam/caddy-defender \
    --with github.com/mholt/caddy-ratelimit \
    --with github.com/caddy-dns/namecheap \
    --with github.com/caddy-dns/cloudflare \
    --with github.com/monobilisim/caddy-ip-list
```

## Roadmap / Future Ideas

- Pin plugin versions for fully reproducible builds (Renovate Go-module manager)
- Publish to additional registries (Docker Hub, Quay)
- More pre-baked example Caddyfiles for common stacks (Nextcloud, *arr, etc.)
- Prometheus metrics + health check examples

## Contributing

Issues and PRs welcome! This project aims to stay small and opinionated — the goal is "the plugins most people need for a secure public reverse proxy" rather than "everything."

## License

Apache 2.0 (same as Caddy).

---

**caddy-doorman** — your site's friendly but firm doorman. 🛡️

*Not affiliated with the official Caddy project.*