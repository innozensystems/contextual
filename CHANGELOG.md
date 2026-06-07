# Changelog

## [1.0.0.1] - 2026-06-07

### Added
- Project README with architecture overview, layout, and security checklist

## [1.0.0.0] - 2026-06-06

### Added
- Initial release of Contextual — context-aware reminder app
- Native iOS app (Swift + SwiftUI) with context-grouped task list, voice entry, geofencing, notifications
- Native Android app (Kotlin + Jetpack) with RecyclerView, bottom sheets, Google Maps integration
- Supabase backend with Postgres + PostGIS, RLS policies, RPC functions for nearby tasks
- FastAPI thin proxy for Mapbox geocoding, reverse geocoding, and route optimization
- GitHub Actions CI/CD pipelines for iOS (TestFlight), Android (Play Store Internal), and proxy (Docker)
- Dynamic geofence swapping (20-region limit on iOS)
- Smart notification batching with instant complete + 10-second undo
- Trip threading with inline auto-suggest banner
- Partner invite flow with deep link support
- Onboarding flow with permission requests
- Design system with 8pt grid, system typography, single-accent color palette
