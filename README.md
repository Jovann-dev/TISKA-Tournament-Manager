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

## Competition Categories and Templates

Admins can use the Competition Categories button in the home toolbar to create
named categories from Flag-Based Scoring or Points-Based Scoring templates.
The availability checkboxes control the division choices for both admins and
users. A category referenced by an existing division cannot be deleted; disable
it instead. Saved divisions retain their category name and scoring template,
and started divisions must be redone before changing these fields.

Category catalogs synchronize between devices and are included in backups.
Existing tournaments and old backups default to the original built-in categories.
Run the updated `supabase/schema.sql` before deploying, and close older clients:
the migration extends snapshot guards for category/template integrity without
deleting tournament data. Template IDs are stable; adding future scoring engines
requires extending the template implementation and its database validation.

## Scoring and Placements

All points-based warning symbols are selectable from the start. Warning
severity and warning count are independent. The third warning in a period,
and each later warning for that competitor, asks whether to disqualify them
and award the match to their opponent. Continue Match retains the warning
without ending the match. Reopening and Undo use the saved event history.

Repechage qualifiers receive joint third place, not joint fourth. Older saved
joint-fourth labels are displayed and exported as joint third. Short repechage
finalist blocks are centered against their feeder matches in screen and print
draw sheets.

## Flag-Based Team Scoring

Create a category using Flag-Based Team Scoring in the admin category screen.
Its rules default to a minimum of one member, no maximum, permission for the
same competitor to join multiple teams in one division, and no team names.
Admins can change the minimum/maximum, shared-membership permission, and
optional naming for a category. Existing divisions retain their saved rules.

In Register Division, select the team category and add numbered teams. Search
registered competitors by name or number to build each roster, optionally name
teams if permitted, and use the arrow controls to change team draw order.
The bracket accepts 2-16 teams, regardless of the total number of individuals.
Teams use the existing flag-voting, advancement, result-reuse and repechage
mechanisms. Opposing teams sharing members show a warning without blocking
the match. Started rosters and rules are locked until an explicit Redo.

Results list member names for teams of up to three people. Larger teams show a
circled member count with a roster reference. The full Team Rosters panel is
below repechage in the draw sheet, including its exported image. Backups and
cross-device synchronization preserve team numbers, names, order, rules and
rosters. Remove affected people from queued team rosters before deleting their
registrations or replacing them through import.

Run the updated `supabase/schema.sql` before deploying this version and close
older clients. Team rule and roster validation is also enforced in PostgreSQL;
the migration preserves existing individual tournament data.

## Competitor Spreadsheets

Exports include `kiddies_belt_color` alongside the existing belt text. Imports
accept that column or the legacy `Kiddies - Purple` style; a plain Kiddies belt
without a color becomes `Kiddies - None`. Missing gender becomes Not Specified.
Male/Female values and M/F abbreviations remain supported. Unknown genders are
not silently treated as male or female.

## Tournament Backups

Save Data captures one detached tournament snapshot for draw-sheet images,
division logs, and `tournament_backup.json`, including unfinished match state.
On the web these files are downloaded in a ZIP; desktop exports save them into
the selected folder. Backups also work before any divisions have been created.
Credentials and synchronization metadata are not included.

Open the same tournament and use Restore tournament backup to select the JSON
file (extract it from the ZIP first). Restore validates the file and requires
confirmation. It rejects changes to started or completed divisions; explicitly
redo affected divisions first only if discarding their results is intentional.
Offline restores are saved locally and queued for synchronization. Close other
editing sessions during restore, and keep backups secure because they contain
competitor personal data.

## Spectator Displays

Open the same tournament on another device or browser tab, choose Tatami
Display, and select the tatami. Live competitors, scores, warnings, and timer
deadlines are shared through tournament-scoped Supabase Realtime Broadcast.
No database migration or table-replication configuration is required.

Late viewers request the current state. Connections replay state after
reconnecting, and active execution screens send a heartbeat every five seconds.
Disconnected or stale remote state expires after about twenty seconds; the
display waits for fresh updates rather than keeping old scores on screen.
Leaving the execution screen stops its broadcast. Live messages are ephemeral,
do not write tournament snapshots, and omit competitor ages, birth dates,
belts, clubs, and passwords. Channels use the existing public access model;
this is not a replacement for the authentication hardening described above.

An opt-in two-client network smoke test uses a unique synthetic topic without
reading or writing tournament rows:

```bash
flutter test --dart-define=TISKA_LIVE_SMOKE_TEST=true test/tournament_repository_test.dart --plain-name "Supabase live broadcast reaches a separate client"
```

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
