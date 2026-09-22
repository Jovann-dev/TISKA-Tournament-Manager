-- Create the tournament credentials table used by the access screen.
create table if not exists public.tournament_credentials (
  id text primary key,
  password text not null,
  created_at timestamptz not null default now()
);

-- Create the shared tournament snapshot table used by the app.
create table if not exists public.tournaments (
  id text primary key,
  snapshot jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.tournament_credentials enable row level security;
alter table public.tournaments enable row level security;

-- For this simple tournament-based app, allow the anonymous role to manage data.
-- In production, replace this with stricter policies tied to a proper auth model.
drop policy if exists "anon_tournament_credentials_all" on public.tournament_credentials;
create policy "anon_tournament_credentials_all"
on public.tournament_credentials
for all
to anon
using (true)
with check (true);

drop policy if exists "anon_tournaments_all" on public.tournaments;
create policy "anon_tournaments_all"
on public.tournaments
for all
to anon
using (true)
with check (true);

-- Optional: allow logged-in users the same permissions.
drop policy if exists "authenticated_tournament_credentials_all" on public.tournament_credentials;
create policy "authenticated_tournament_credentials_all"
on public.tournament_credentials
for all
to authenticated
using (true)
with check (true);

drop policy if exists "authenticated_tournaments_all" on public.tournaments;
create policy "authenticated_tournaments_all"
on public.tournaments
for all
to authenticated
using (true)
with check (true);
