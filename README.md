# tiska_tournament_manager

Flutter tournament management with local persistence and revision-checked Supabase synchronization.

## Required Database Migration

Run `supabase/schema.sql` in the Supabase SQL editor before deploying this version.
It adds a revision column, optional user passwords, the atomic
`save_tournament_snapshot` and `delete_tournament` RPCs, and database guards for
protected brackets, registered competitors, and one running division per tatami.
Existing tournament data is preserved. Close older clients before migration:
their unversioned writes will be rejected after the migration.

Admin/user password selection only hides or shows controls in the app; the
existing anonymous access policies still permit direct API access. This is
intended to prevent casual or accidental use, not to provide security against a
technical user. Authentication hardening is a separate requirement before
production use.

## Synchronization and Recovery

Pending changes and their last synchronized baseline are saved locally before
upload. Network failures retry with bounded exponential backoff and survive an
app restart. The home screen reports local, pending, synchronized, and conflict
states and provides a retry action. Independent entity changes are merged;
conflicting changes to the same division are not silently overwritten.
Conflicts retain local data and block upload until the conflicting edits are
resolved. A legacy local cache with no synchronization baseline is treated as
pending, not discarded in favor of the server.

Do not clear application/browser storage while changes are pending. If operators
are offline, occupancy checks can only use their local view; conflicting starts
are detected and retained for resolution when they reconnect.

Started or completed divisions must be explicitly redone before changing their
entrants, draw order, competition criteria, or competitor registrations. Redo
clears results and unfinished match state. Import replaces registrations only
after confirmation and rejects removals that invalidate divisions.

## Toolchain

Use Flutter **3.47.4**, which includes Dart **3.13.3**. Both GitHub Actions and
the Netlify build script pin this version and run analysis and tests before
building. Clear a Netlify Flutter SDK cache if it contains another version.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
