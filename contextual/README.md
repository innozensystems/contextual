# Contextual

A context-aware reminder app that knows where you are and what you're doing, so it reminds you at the right place and time.

## Architecture

| Layer | Tech |
|-------|------|
| **iOS App** | SwiftUI |
| **Android App** | Kotlin |
| **API Proxy** | FastAPI (Python) |
| **Backend / DB** | Supabase (PostgreSQL) |
| **Cache** | Redis |
| **Geocoding / Routing** | Mapbox |

## Repository Layout

```
.
├── ios/          # SwiftUI iOS application
├── android/      # Kotlin Android application
├── proxy/        # FastAPI thin proxy
│   ├── app/      # Application code
│   └── tests/    # Test suite
└── .github/
    └── workflows/
        ├── ios.yml       # iOS CI
        ├── android.yml   # Android CI
        └── proxy.yml     # Proxy CI (lint, test, Docker smoke)
```

## Proxy (FastAPI)

The proxy sits between the mobile clients and Supabase, adding:

- **Redis-backed rate limiting** — sliding-window per IP with atomic Lua scripts
- **Request/response caching** — configurable TTL per endpoint
- **Mapbox integration** — geocoding and routing for location-aware reminders
- **Prometheus metrics** — cardinality-safe instrumentation (no unbounded labels)
- **Certificate pinning** — SPKI hash verification on both iOS and Android
- **CORS** — origin allowlist with wildcard safety (credentials disabled when `*` present)

### Running Locally

```bash
cd proxy
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

### Testing

```bash
cd proxy
pytest -q --cov=app --cov-report=term-missing
```

Current coverage: **~98%** (89 tests).

### Docker

```bash
cd proxy
docker build -t contextual-proxy .
docker run -p 8000:8000 --env-file .env contextual-proxy
```

## CI / CD

| Workflow | Trigger | Jobs |
|----------|---------|------|
| `proxy.yml` | `proxy/**` changes | ruff lint/format, pytest, Docker smoke, Trivy scan |
| `ios.yml` | `ios/**` changes | build, test, archive |
| `android.yml` | `android/**` changes | build, test, APK artifact |

## Security Checklist

- [x] Rate limiting with Redis atomic Lua scripts (with fakeredis fallback for tests)
- [x] CORS wildcard bypass fixed — `*` in comma-separated list forces `allow_credentials=False`
- [x] Prometheus label cardinality safe — `endpoint` label instead of `device_id`
- [x] Certificate pinning via SPKI hash on iOS and Android
- [x] Sensitive parameter redaction in logs (`token`, `key`, `password`, `secret`)
- [x] CI path filters fixed to match repo root layout (`proxy/**`, not `contextual/proxy/**`)
- [x] Trivy action pinned to `@0.28.0` (not floating `@master`)

## License

MIT
