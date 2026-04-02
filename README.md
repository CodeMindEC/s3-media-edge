# s3-media-edge

Self-hosted media CDN stack — on-the-fly image resizing, video streaming, and document serving with aggressive disk caching. One `docker compose up` to replace a cloud CDN.

```
┌─────────────────────────────────────────────────────────────┐
│                     Docker Network                          │
│                                                             │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐  │
│  │   CDN   │───▶│ Imagor  │───▶│         │    │  WebUI  │  │
│  │ (Nginx) │    │ (resize)│    │ Garage  │◀───│ (admin) │  │
│  │         │──────────────────▶│  (S3)   │    │         │  │
│  └────┬────┘    └─────────┘    └─────────┘    └────┬────┘  │
│       │          PRIVATE        PRIVATE            │        │
│       │ PUBLIC                              PUBLIC │        │
└───────┼────────────────────────────────────────────┼────────┘
        ▼                                            ▼
   cdn.example.com                          admin.example.com
```

## Features

- **Image resizing** — `/img/800/photo.jpg` resizes on-the-fly via [Imagor](https://github.com/cshum/imagor), auto-converts to WebP/AVIF
- **Original images** — `/img/original/logo.svg` serves unmodified files through Imagor's pipeline
- **Video streaming** — `/raw/video.mp4` with [slice caching](https://nginx.org/en/docs/http/ngx_http_slice_module.html) (1MB segments) for efficient seeking
- **Document serving** — `/doc/report.pdf` proxied from S3 with cache
- **Aggressive disk cache** — Nginx caches responses for 30 days, configurable max size
- **Cache purge API** — `curl http://cdn/purge/img/800/photo.jpg` from internal network
- **CORS validation** — Regex-based origin allowlist
- **Rate limiting** — Per-route limits (30r/s images, 10r/s video/docs)
- **Security headers** — `X-Content-Type-Options`, `X-Frame-Options`, file extension whitelist
- **S3-compatible** — Built for [Garage](https://garagehq.deuxfleurs.fr/) but works with any S3-compatible storage
- **Admin UI** — [Garage WebUI](https://github.com/khairul169/garage-webui) for bucket/key management
- **Multi-arch** — Runs on AMD64 and ARM64

## Quick Start

```bash
git clone https://github.com/CodeMindEC/s3-media-edge.git
cd s3-media-edge

cp .env.example .env
# Edit .env with your secrets

cp garage.toml.example garage.toml
# Edit garage.toml with your RPC secret

docker compose up -d
```

Then configure your Garage cluster:

```bash
# Get the node ID
docker compose exec garage /garage node id -q

# Assign storage capacity
docker compose exec garage /garage layout assign -z dc1 -c 50GB <NODE_ID>
docker compose exec garage /garage layout apply --version 1

# Create a bucket
docker compose exec garage /garage bucket create my-media

# Create an API key
docker compose exec garage /garage key create my-app-key

# Grant access
docker compose exec garage /garage bucket allow --read --write my-media --key my-app-key
```

Update `S3_BUCKET` in `.env` to match your bucket name. Restart:

```bash
docker compose up -d
```

## Usage

### Images (resized)

```
GET /img/{width}/{path}
```

```bash
# Resize to 800px wide, auto WebP
curl https://cdn.example.com/img/800/products/photo.jpg

# Resize to 400px
curl https://cdn.example.com/img/400/products/photo.jpg
```

### Images (original)

```
GET /img/original/{path}
```

```bash
curl https://cdn.example.com/img/original/branding/logo.svg
```

### Video streaming

```
GET /raw/{path}
```

```bash
# Supports Range requests for seeking
curl https://cdn.example.com/raw/promo.mp4
```

### Documents

```
GET /doc/{path}
```

```bash
curl https://cdn.example.com/doc/catalog.pdf
```

### Cache purge (internal only)

```bash
# Purge a specific image
curl http://cdn/purge/img/800/products/photo.jpg

# Purge video (slice cache — append *)
curl http://cdn/purge/raw/promo.mp4*
```

## Configuration

### Required Environment Variables

| Variable | Description |
|---|---|
| `GARAGE_RPC_SECRET` | Garage RPC secret (64-char hex) |
| `GARAGE_ADMIN_TOKEN` | Garage admin API token |
| `GARAGE_METRICS_TOKEN` | Garage metrics endpoint token |
| `AWS_ACCESS_KEY_ID` | S3 access key for Imagor |
| `AWS_SECRET_ACCESS_KEY` | S3 secret key for Imagor |
| `S3_BUCKET` | Bucket name to serve from |

### Optional Environment Variables

| Variable | Default | Description |
|---|---|---|
| `GARAGE_VERSION` | `v2.1.0` | Garage Docker image tag |
| `IMAGOR_VERSION` | `latest` | Imagor Docker image tag |
| `WEBUI_VERSION` | `1.1.0` | Garage WebUI image tag |
| `AWS_REGION` | `garage` | S3 region |
| `CDN_PORT` | `8080` | CDN exposed port |
| `WEBUI_PORT` | `3909` | WebUI exposed port |
| `CDN_DOMAIN` | `localhost` | CDN server name |
| `ALLOWED_ORIGINS_REGEX` | `localhost` | CORS allowed origins (regex, `\|` separated) |
| `CACHE_MAX_SIZE` | `10g` | Max disk cache size |
| `MAX_VIDEO_SIZE` | `50m` | Max video body size |
| `MAX_IMG_SIZE` | `5m` | Max image body size |
| `IMAGOR_AUTO_WEBP` | `1` | Auto-convert to WebP |
| `IMAGOR_AUTO_AVIF` | `0` | Auto-convert to AVIF |
| `IMAGOR_PROCESS_CONCURRENCY` | `10` | Max concurrent image processes |
| `IMAGOR_REQUEST_TIMEOUT` | `30s` | Overall request timeout |
| `IMAGOR_RESULT_STORAGE_EXPIRATION` | `720h` | Processed image cache TTL |
| `AUTH_USER_PASS` | *(empty)* | WebUI auth (`user:bcrypt_hash`) |
| `RUST_LOG` | `garage=info` | Garage log level |

### Allowed File Extensions

| Route | Extensions |
|---|---|
| `/img/` | `.jpg` `.jpeg` `.png` `.webp` `.avif` `.svg` `.gif` |
| `/raw/` | `.mp4` `.webm` |
| `/doc/` | `.pdf` `.doc` `.docx` `.xls` `.xlsx` `.csv` `.pptx` `.ppt` `.odt` `.ods` `.txt` |

## Architecture

### Request Flow

```
Client → CDN (Nginx) → Cache Hit?
                         ├─ YES → Serve from disk cache
                         └─ NO  → /img/ → Imagor → Garage S3
                                  /raw/ → Garage S3 (slice)
                                  /doc/ → Garage S3
```

### Components

| Service | Image | Role | Exposed |
|---|---|---|---|
| `cdn` | Custom (nginx:stable-alpine) | Caching reverse proxy | Yes |
| `webui` | khairul169/garage-webui | S3 admin panel | Yes |
| `garage` | dxflrs/garage | S3-compatible storage | No |
| `imagor` | shumc/imagor | Image processing | No |

### Ports (internal)

| Service | Port | Protocol |
|---|---|---|
| Garage S3 API | 3900 | HTTP |
| Garage RPC | 3901 | TCP |
| Garage Web | 3902 | HTTP |
| Garage Admin | 3903 | HTTP |
| Imagor | 8000 | HTTP |
| WebUI | 3909 | HTTP |
| CDN | 80 | HTTP |

## Deployment

### With Coolify

1. Create a new Docker Compose service pointing to this repo
2. Set required env vars in the Coolify UI
3. Assign domains to `cdn` and `webui` services only
4. Garage and Imagor stay internal (no domain needed)
5. Mount `garage.toml` as a file volume

### With Traefik

Add labels to `cdn` and `webui` in your override:

```yaml
# docker-compose.override.yml
services:
    cdn:
        labels:
            - "traefik.enable=true"
            - "traefik.http.routers.cdn.rule=Host(`cdn.example.com`)"
            - "traefik.http.routers.cdn.tls.certresolver=letsencrypt"
    webui:
        labels:
            - "traefik.enable=true"
            - "traefik.http.routers.webui.rule=Host(`admin.example.com`)"
            - "traefik.http.routers.webui.tls.certresolver=letsencrypt"
```

### Connecting from External Services

If other Docker services need to reach this stack (e.g., a backend that uploads to S3), add them to the same network:

```yaml
# In your app's docker-compose.yml
networks:
    media:
        external: true
        name: s3-media-edge_internal
```

Then use `garage:3900` as the S3 endpoint.

## Cache Behavior

| Route | Cache Key | TTL | Strategy |
|---|---|---|---|
| `/img/{w}/{file}` | URI | 30 days | Full response |
| `/img/original/{file}` | URI | 30 days | Full response |
| `/raw/{file}` | URI + slice range | 30 days | 1MB segments |
| `/doc/{file}` | URI | 30 days | Full response |

Stale content is served on upstream errors (`500`, `502`, `503`, `504`).

## License

MIT — see [LICENSE](LICENSE).
