# The Fluid Ledger

Flutter expense tracker with:

- phone OTP auth via Supabase
- local-first transaction caching in SQLite
- SMS-based expense detection and manual review
- monthly budgeting, goals, and weekly targets
- Splitwise-style shared groups and settlements

## Run

```bash
flutter pub get
flutter run
```

## Verify

```bash
flutter analyze
flutter test
```

## Architecture

- `lib/core`: routing, theme, SQLite, notifications, SMS utilities
- `lib/features/auth`: OTP login and signup
- `lib/features/dashboard`: home analytics and Smart Sync entry
- `lib/features/expense`: manual expenses, history, categories, SMS import
- `lib/features/goals`: goals and weekly targets
- `lib/features/profile`: profile setup and settings
- `lib/features/splitwise`: groups, members, shared expenses, settlements

## Notes

- Dashboard analytics use full current-month data; the recent activity feed remains capped separately for performance.
- SQLite migrations are additive so app upgrades do not wipe cached preferences.
- Smart Sync explains SMS access before prompting for permission.
