# Contextual — Context-Aware Reminder App

A greenfield native mobile app that uses GPS to surface tasks when users are near relevant locations. Built with native Swift (iOS) + Kotlin (Android), Supabase for backend, and a thin Python proxy for Mapbox.

## Architecture

```
┌─ Native iOS (Swift) / Android (Kotlin)
├─ Supabase SDK (auth + sync + local DB + realtime)
├─ Platform APIs (geofencing, speech, notifications)
└─ Thin Python Proxy (FastAPI: Mapbox proxy + cache only)
```

## Quick Start

### 1. Supabase Setup

```bash
cd supabase/migrations
# Run 001_initial_schema.sql in your Supabase SQL Editor
# Enable PostGIS extension first
```

### 2. Proxy Setup

```bash
cd proxy
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
export MAPBOX_TOKEN=your_mapbox_token
uvicorn app.main:app --reload
```

### 3. iOS Setup

```bash
cd ios/Contextual
# Open Package.swift in Xcode or use xcodegen
# Update Info.plist with your Supabase URL and anon key
# Build and run on device (simulator lacks geofencing)
```

### 4. Android Setup

```bash
cd android
./gradlew assembleDebug
# Update app/build.gradle.kts BuildConfig fields with your keys
# Run on device (emulator supports geofencing with mock locations)
```

## Key Features Implemented

- **Dynamic geofence swapping** — Monitors nearest 20 locations on iOS, swaps as user moves
- **Smart notification batching** — One expandable notification per location
- **Voice-first task entry** — iOS Speech framework + Android SpeechRecognizer
- **Instant complete + 10s undo** — Frictionless lock-screen completion with safety net
- **Trip threading** — Auto-suggest inline banner for nearby task clusters
- **Offline-first** — Supabase client SDK with local SQLite replica
- **Partner invites** — Deep link invitations via SMS/email
- **Rule-based habits** — SQL queries on Supabase (v1, ML deferred)

## Project Structure

```
contextual/
├── ios/                    # Swift + SwiftUI iOS app
│   ├── Contextual/
│   │   ├── Sources/
│   │   │   ├── App/        # App entry, auth
│   │   │   ├── Models/     # Task, Location, List
│   │   │   ├── Services/   # Supabase, Geofence, Notification, Proxy
│   │   │   ├── Views/      # Home, AddTask, TaskDetail, Trip, Onboarding, Settings
│   │   │   └── ViewModels/  # (inline in Views for v1)
│   │   └── Resources/
│   └── fastlane/
├── android/                # Kotlin + Jetpack Android app
│   ├── app/src/main/
│   │   ├── java/com/contextual/
│   │   │   ├── app/        # MainActivity, Application
│   │   │   ├── data/       # Models, SupabaseClient
│   │   │   ├── ui/         # Fragments, ViewModels, Adapters
│   │   │   └── service/    # Geofence, Notification, Proxy
│   │   └── res/            # Layouts, values, navigation
│   └── fastlane/
├── proxy/                  # FastAPI thin proxy
│   ├── app/main.py         # Geocode, reverse-geocode, route
│   ├── Dockerfile
│   └── requirements.txt
├── supabase/migrations/    # Database schema + RLS policies
│   └── 001_initial_schema.sql
├── .github/workflows/     # CI/CD for iOS, Android, Proxy
└── docs/                  # (empty — add API docs here)
```

## Environment Variables

### Proxy
- `MAPBOX_TOKEN` — Mapbox public token (server-side only)
- `REDIS_URL` — Redis connection string (default: `redis://localhost:6379/0`)
- `RATE_LIMIT_PER_MINUTE` — Default: 60

### Mobile
- `SUPABASE_URL` — Your Supabase project URL
- `SUPABASE_ANON_KEY` — Supabase anon/public key
- `PROXY_BASE_URL` — Thin proxy URL (e.g., `https://proxy.yourdomain.com`)

## CI/CD

GitHub Actions + Fastlane:
- **iOS:** Build, test, and deploy to TestFlight on every `main` push
- **Android:** Build, test, and deploy to Play Store Internal Testing
- **Proxy:** Build Docker image and push to registry

Configure secrets:
- `APP_STORE_CONNECT_API_KEY_*` — For iOS TestFlight
- `PLAY_STORE_JSON_KEY` — For Play Store upload
- `MATCH_PASSWORD` — For iOS code signing

## Design System

See `~/.gstack/projects/contextual_done/DESIGN.md` for:
- Typography tokens (SF Pro / Roboto)
- Color system (one accent only, no gradients)
- Spacing scale (8pt grid)
- Component specs (task row, context header, FAB, modal)
- Accessibility baseline (44pt touch targets, Dynamic Type, Reduce Motion)

## License

MIT
