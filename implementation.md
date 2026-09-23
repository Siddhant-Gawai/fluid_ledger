# Current Implementation Notes

## Core decisions

- `Supabase` is the source of truth for auth and synced data.
- `SQLite` is used as a local-first cache for transactions, profile data, goals, weekly targets, and split-group data.
- `VersionSync` and `SyncService` keep the local cache aligned with remote state.
- `Riverpod` owns app wiring; `GoRouter` handles navigation.

## Recent hardening

- Dashboard analytics now use full current-month data instead of a paged recent list.
- SQLite upgrades are additive and preserve local-only preferences like pinned items and archived groups.
- Notification scheduling now resolves the device timezone before creating recurring reminders.
- Smart Sync shows a permission explainer before requesting SMS access.
- Splitwise member hydration avoids per-member write-backs and removes noisy PII logging.
- The starter Flutter smoke test has been replaced with app-safe widget and parser tests.

## Remaining gaps worth extending later

- more repository-level tests with fake Supabase clients
- end-to-end emulator coverage for OTP, SMS permission flows, and notifications
- batching or server-side hydration for Splitwise member/profile lookups
