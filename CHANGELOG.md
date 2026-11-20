# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) · Versioning: [SemVer](https://semver.org/).

## [Unreleased]

## [0.9.0] - 2026-11-20

### Added
- **Design token system** (`lib/src/app/design/tokens.dart`): dual-theme colors, type scale, spacing, radii, shadows, subject/difficulty maps.
- **Component layer**: `AppCard`, `AppButton`, `AppChip`, `AppTag`, `AppStatHero/Mini`, `AppFab`, `AppBottomFade`.
- **UI beautify** across Home / Notebook / Detail / Review / Settings, plus tokenization of Analysis, Exercise, Split-confirmation and chart widgets.
- **Page backgrounds**: 6 curated gradients, per-brightness selection, stored separately for light/dark.
- **Vision quota card**: tokenized and dark-mode ready.
- **Liquid-glass navigation**: glass top bar with scroll-reactive blur, floating glass dock, glass sheets/dialogs, glass search & chips, swipe actions, pull-to-refresh.
- **Dynamic backend resolution** from config repo (Gitee → GitHub → bundled default).

### Changed
- Dark cards use `#1E293B` + 1px `#334155` border (no shadows).
- Page transitions: fade on Android, native Cupertino on iOS (keeps swipe-back).
- Guest-mode entry: instant loading state, glass shader warm-up before navigation.

### Removed
- Guest "please sign in" glass dialog on first home visit.
- Knowledge-point tag tap-to-filter on notebook cards.
- Glass page transition on high-tier devices (kept as option in code history).

## [0.8.0] - 2026-11-18

### Added
- Cloud deployment (Tencent Cloud → self-hosted Ubuntu), systemd service, Caddy reverse proxy.
- Per-request quota accounting fix (one image = one charge), OCR-reuse on retry.
- iOS build guide + ATS configuration.

## [0.1.0] - 2026-10-17

### Added
- Initial public skeleton: Flutter app + FastAPI backend, photo → OCR → AI analysis → notebook.
