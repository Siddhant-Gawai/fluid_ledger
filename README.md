# The Fluid Ledger

A Flutter expense tracker with personal budgeting, SMS import, savings goals, and shared expenses.

## Features

- Phone OTP login and signup through Supabase.
- Manual expense entry, editing, deletion, categories, and transaction history.
- SQLite caching for local-first transaction reads and pending transaction writes.
- SMS debit detection, merchant categorization, duplicate filtering, and manual import review.
- Monthly spending summaries and budget tracking.
- Savings goals, weekly category targets, and manual weekly spend logs.
- Shared groups, expense splits, settlements, and group activity history.
- Notification preferences, spending alerts, and scheduled reminders.
- Transaction search and saved searches.

SMS categorization uses parsing rules and merchant mappings. Offline behavior and platform support vary by feature; see the limitations below.

## Recent patches

Transaction history now includes:

- Pull-to-refresh for short or empty transaction lists.

- A clear-search button that resets the query and search results.
- Protection against older asynchronous searches overwriting newer results.
- Normal history display when a query contains only whitespace.
- Keyboard dismissal when dragging the transaction list.
- A Search keyboard action that dismisses the keyboard when submitted.
- A disabled Save search button for empty or whitespace-only queries, with the theme's disabled appearance.

## Requirements

- Flutter with a bundled Dart SDK compatible with `^3.11.4` (see `pubspec.yaml`).
- Android SDK and an Android device or emulator for the Android app. The current minimum Android SDK is 24.
- An Android device with suitable inbox messages and SMS permission to exercise SMS import.
- Access to a configured Supabase backend for authentication and cloud data.

## Local setup

```bash
git clone https://github.com/Siddhant-Gawai/fluid_ledger.git
cd fluid_ledger
flutter doctor
flutter pub get
flutter devices
flutter run
```

Use `flutter run -d <device-id>` to select a device. Configure your own Flutter and Android SDK paths; `android/local.properties` is machine-specific and excluded from Git.

### Backend configuration

The app currently reads its Supabase URL and publishable key from `lib/core/supabase/supabase_config.dart`. Point these values at your own project when setting up a separate environment. Never put a service-role or secret key in the client.

Phone OTP requires a configured phone authentication provider. The app also expects existing tables, access policies, and RPC functions for profiles, transactions, goals, weekly targets, and shared expenses.

The root-level `supabase_*.sql` files are supplemental scripts, **not a complete, ordered bootstrap migration set**. A fresh Supabase project will need the base schema and policies in addition to these files. Review the scripts before applying them, particularly the membership-claim and lookup functions noted below.

## Verification

```bash
flutter analyze
flutter test
```

Existing tests cover SMS parsing, merchant categorization, realtime event mapping, and basic widget behavior. They do not provide full coverage of synchronization, database migrations, or shared-expense calculations.

The recent search patches passed Dart syntax/format parsing and Git whitespace checks. They have not been verified in a running app, and the full analyzer and test suite were not run for those patches.

## Architecture

| Directory | Purpose |
| --- | --- |
| `lib/core` | Routing, theme, SQLite, synchronization, notifications, SMS utilities, and settings |
| `lib/features/auth` | OTP login and signup |
| `lib/features/dashboard` | Home analytics and Smart Sync entry |
| `lib/features/expense` | Manual expenses, history, search, categories, summaries, and SMS import |
| `lib/features/goals` | Savings goals and weekly targets |
| `lib/features/profile` | Profile setup and settings |
| `lib/features/splitwise` | Groups, members, shared expenses, settlements, and activity |
| `test` | Unit and widget tests |

State management uses Riverpod, navigation uses GoRouter, local storage uses SQLite, and cloud services use Supabase.

## Platform and release status

Android is the primary target for SMS import. The repository also contains iOS, web, Windows, macOS, and Linux scaffolding; this does not mean all features are implemented or verified on those platforms. Notification initialization currently supplies Android settings only.

Android release builds currently use debug signing. Configure release signing and verify the merged release manifest and required permissions before distribution. Privacy & Security, Help & Support, and About entries in profile settings are currently placeholders.

## Known issues and follow-up work

The initial source review identified the following issues. The small search patches above do **not** resolve them:

- Membership-claim SQL functions trust caller-supplied identity and phone values; authorization and execution permissions need review before deployment. Live backend permissions have not been audited.
- Full/version sync can replace cached transactions containing unsynced local changes.
- Shared-expense and split updates use separate requests rather than one atomic operation.
- SMS ledger duplicate matching can hide separate purchases with the same amount within 12 hours.
- Monthly aggregate caches can become stale after edits, deletion, or synchronization.
- Some cloud reads lack pagination, which can produce incomplete history and totals for larger accounts.
- UTC timestamps and local calendar filtering can disagree around day/month boundaries.
- Manual weekly spending is capped at the remaining target instead of recording the full overspend.
- Logout cleanup and account isolation need further work for cached data and in-flight operations.

Prioritize these reliability and authorization fixes before treating the app as production-ready. This repository update documents current behavior; it does not apply backend changes.
