# Deployment Guide

This guide covers deploying the Contextual proxy to production.

## Infrastructure

| Component | Provider | Tier |
|-----------|----------|------|
| Proxy | Fly.io | shared-cpu-1x, 512MB |
| Redis | Upstash | Free / Pay-as-you-go |
| Database | Supabase | Free / Pro |
| Container Registry | GitHub Container Registry | Free for public repos |

## Prerequisites

- [Fly.io CLI](https://fly.io/docs/flyctl/installing/) installed and authenticated
- [Upstash](https://upstash.com/) account with Redis database created
- Mapbox account with public access token

## Step 1: Provision Upstash Redis

1. Create a database in Upstash dashboard
2. Copy the **Redis URL** (must start with `rediss://` for TLS)
3. Set `REQUIRE_REDIS_TLS=true` in your environment

## Step 2: Configure Environment

```bash
cd contextual/proxy
cp .env.example .env
```

Edit `.env`:

```
MAPBOX_TOKEN=pk.XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
REDIS_URL=rediss://default:XXXX@XXXX.upstash.io:6379
REQUIRE_REDIS_TLS=true
CORS_ORIGINS=*
RATE_LIMIT_PER_MINUTE=60
MAX_CACHE_SECONDS=86400
PROXY_API_KEY=<generate with openssl rand -hex 32>
```

## Step 3: Deploy to Fly.io

```bash
# Launch (first time only)
fly launch --name contextual-proxy --region sjc

# Deploy subsequent updates
fly deploy
```

## Step 4: Verify Deployment

```bash
# Health check
curl https://contextual-proxy.fly.dev/health

# Metrics (if enabled)
curl https://contextual-proxy.fly.dev/metrics
```

## Step 5: Update Mobile Apps

Use the deployed URL and `PROXY_API_KEY` in mobile builds:

**iOS:**
```bash
cd contextual/ios
plutil -replace PROXY_BASE_URL -string "https://contextual-proxy.fly.dev" Contextual/Info.plist
plutil -replace PROXY_API_KEY -string "<proxy-api-key>" Contextual/Info.plist
```

**Android:**
```bash
cd contextual/android
export PROXY_BASE_URL="https://contextual-proxy.fly.dev"
export PROXY_API_KEY="<proxy-api-key>"
./gradlew assembleRelease
```

## Monitoring

| Metric | Endpoint | Alert Condition |
|--------|----------|----------------|
| Health | `/health` | Status != `ok` |
| Rate limit hits | `/metrics` | `rate_limit_hits_total` spike |
| Mapbox errors | `/metrics` | `mapbox_errors_total` spike |
| Response time | Fly.io dashboard | P95 > 500ms |

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| 502 errors | Mapbox timeout | Check `mapbox_errors_total`; verify token |
| 429 errors | Rate limit exceeded | Increase `RATE_LIMIT_PER_MINUTE` or check Redis |
| 503 errors | Missing config | Verify `MAPBOX_TOKEN` and `REDIS_URL` |
| High latency | Cache miss | Verify Redis connection; check `cache_hits_total` |
