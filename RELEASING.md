# Releasing Contextual

This document describes the end-to-end release process for the Contextual mobile apps and proxy.

## Release Cadence

- **Patch** (1.0.x) — bug fixes, dependency updates, security patches
- **Minor** (1.x.0) — new features, UI improvements, API additions
- **Major** (x.0.0) — breaking changes, architecture shifts

## Pre-Release Checklist

Before cutting any release, verify:

- [ ] All CI pipelines green on `main`
- [ ] Proxy tests pass with `--cov-fail-under=95`
- [ ] Android `./gradlew :app:build` succeeds (debug + release)
- [ ] iOS builds cleanly in Xcode (or `xcodebuild` on CI)
- [ ] Security audit reviewed (see `SECURITY_AUDIT.md`)
- [ ] `CHANGELOG.md` updated with version and date
- [ ] `VERSION` file bumped at repo root

## Versioning

The single `VERSION` file at repo root drives all artifacts:

```
1.0.0
```

This is read by:
- GitHub Actions `proxy.yml` — Docker image tag (`ghcr.io/.../contextual-proxy:v1.0.0`)
- iOS `Info.plist` — `CFBundleShortVersionString` (via Fastlane)
- Android `build.gradle.kts` — `versionName` (via Gradle or Fastlane)

## Release Steps

### 1. Prepare Release Branch

```bash
VERSION=1.1.0

# Create release branch
git checkout -b release/v$VERSION

# Bump VERSION
echo "$VERSION" > VERSION

# Update CHANGELOG.md — move Unreleased items to new section
# ... edit manually ...

git add VERSION CHANGELOG.md
git commit -m "chore(release): bump version to $VERSION"
```

### 2. Proxy Release

```bash
cd proxy

# Verify tests
pytest tests/ -v --cov=app --cov-branch --cov-fail-under=95

# Build and smoke-test Docker image
docker build -t contextual-proxy:v$VERSION .
docker run -d -p 18000:8000 --env-file .env contextual-proxy:v$VERSION
curl -sf http://localhost:18000/health | grep '"status":"ok"'

# Deploy to Fly.io (production)
fly deploy --dockerfile Dockerfile --config fly.toml
```

### 3. iOS Release

```bash
cd ios

# Inject production secrets into Info.plist
plutil -replace PROXY_BASE_URL -string "https://contextual-proxy.fly.dev" Contextual/Info.plist
plutil -replace PROXY_API_KEY -string "$PROXY_API_KEY" Contextual/Info.plist
plutil -replace PROXY_CERTIFICATE_PINS -string "$PINS" Contextual/Info.plist

# Build and upload to TestFlight
bundle exec fastlane beta
```

### 4. Android Release

```bash
cd android

# Build release APK/AAB with production secrets
SUPABASE_URL=$SUPABASE_URL \
SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
PROXY_BASE_URL=$PROXY_BASE_URL \
PROXY_CERTIFICATE_PINS=$PINS \
PROXY_API_KEY=$PROXY_API_KEY \
CI_RELEASE=true \
  ./gradlew assembleRelease bundleRelease

# Deploy to Play Store Internal track
bundle exec fastlane deploy_internal
```

### 5. Tag and Merge

```bash
git tag -a v$VERSION -m "Release $VERSION"
git push origin v$VERSION

# Open PR from release/v$VERSION → main
gh pr create --title "Release $VERSION" --body "See CHANGELOG.md"
```

## Post-Release

- [ ] Verify proxy health endpoint in production
- [ ] Smoke-test iOS TestFlight build
- [ ] Smoke-test Android Internal track build
- [ ] Monitor error rates (proxy metrics, Sentry/Crashlytics)
- [ ] Announce release in team channel

## Rollback

### Proxy
```bash
fly deploy --image ghcr.io/innozensystems/contextual/contextual-proxy:vPREVIOUS_VERSION
```

### iOS
Reject build in App Store Connect; previous version remains available.

### Android
Promote previous release in Play Console.

## Secrets Reference

| Secret | Used By | Source |
|--------|---------|--------|
| `MAPBOX_TOKEN` | Proxy | Mapbox account |
| `PROXY_API_KEY` | Proxy, iOS, Android | Generate with `openssl rand -hex 32` |
| `REDIS_URL` | Proxy | Upstash dashboard |
| `SUPABASE_URL` | iOS, Android | Supabase project settings |
| `SUPABASE_ANON_KEY` | iOS, Android | Supabase project settings |
| `PROXY_CERTIFICATE_PINS` | iOS, Android | `openssl s_client -connect host:443 ...` |
