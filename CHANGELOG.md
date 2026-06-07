# Changelog

All notable changes to the Contextual project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-06-07

### Added
- **iOS App** — SwiftUI application with location-aware reminders, task management, and trip optimization
- **Android App** — Kotlin application with geofencing, notifications, and route optimization
- **FastAPI Proxy** — Thin proxy with Redis caching, Mapbox integration, and Prometheus metrics
- **Rate limiting** — Sliding-window per-device rate limiting with atomic Lua scripts
- **API key auth** — Optional `x-api-key` header enforcement (required in production)
- **Certificate pinning** — SPKI hash verification on both iOS and Android
- **CI/CD pipelines** — GitHub Actions for proxy (lint, test, Docker, Trivy), iOS (build, TestFlight), Android (build, Play Store)
- **Security audit** — Full security review with remediation of critical and high findings
- **Release documentation** — `RELEASING.md` runbook and `docs/DEPLOYMENT.md` guide

### Security
- CORS wildcard bypass fixed — `*` forces `allow_credentials=False`
- Prometheus label cardinality safe — `endpoint` label instead of `device_id`
- Sensitive parameter redaction in logs (`token`, `key`, `password`, `secret`)
- Trivy action pinned to `@0.28.0`

[Unreleased]: https://github.com/innozensystems/contextual/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/innozensystems/contextual/releases/tag/v1.0.0
