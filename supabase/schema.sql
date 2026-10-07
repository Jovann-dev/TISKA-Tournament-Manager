-- Create the tournament credentials table used by the access screen.
create table if not exists public.tournament_credentials (
  id text primary key,
  password text not null,
  user_password text,
  created_at timestamptz not null default now()
);

alter table public.tournament_credentials
  add column if not exists user_password text;

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

alter table public.tournaments
  add column if not exists revision bigint not null default 0;

create or replace function public.validate_tournament_snapshot()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  division_row jsonb;
  previous_row jsonb;
  replacement jsonb;
  participant jsonb;
  previous_data jsonb;
  current_data jsonb;
  explicitly_reset boolean;
  category_row jsonb;
  category_id text;
  category_template text;
begin
  if tg_op = 'UPDATE' and new.revision <> old.revision + 1 then
    raise exception 'Revision-checked tournament writes are required';
  end if;

  if tg_op = 'UPDATE' and old.snapshot ? 'competitionCategories'
    and not (new.snapshot ? 'competitionCategories') then
    raise exception 'Competition category catalog is required; update the client';
  end if;

  if new.snapshot ? 'competitionCategories' then
    if exists (
      select 1 from jsonb_array_elements(new.snapshot->'competitionCategories') as item
      group by item->>'id' having count(*) > 1
    ) or exists (
      select 1 from jsonb_array_elements(new.snapshot->'competitionCategories') as item
      group by lower(trim(item->>'name')) having count(*) > 1
    ) then
      raise exception 'Competition category IDs and names must be unique';
    end if;
    for category_row in select value from jsonb_array_elements(new.snapshot->'competitionCategories')
    loop
      if coalesce(trim(category_row->>'id'), '') = ''
        or coalesce(trim(category_row->>'name'), '') = ''
        or coalesce(category_row->>'template', '') not in ('flagVoting', 'points')
        or jsonb_typeof(category_row->'enabled') is distinct from 'boolean' then
        raise exception 'Invalid competition category';
      end if;
    end loop;
    if tg_op = 'UPDATE' and old.snapshot ? 'competitionCategories' then
      for category_row in select value from jsonb_array_elements(old.snapshot->'competitionCategories')
      loop
        if exists (
          select 1 from jsonb_array_elements(new.snapshot->'competitionCategories') as item
          where item->>'id' = category_row->>'id'
            and (item->>'name' is distinct from category_row->>'name'
              or item->>'template' is distinct from category_row->>'template')
        ) then
          raise exception 'Existing competition category names and templates cannot be changed';
        end if;
      end loop;
    end if;
  end if;

  if exists (
    select 1 from jsonb_array_elements(coalesce(new.snapshot->'divisions', '[]')) as item
    where item->'data'->>'progress' = 'running'
    group by item->'data'->>'assignedTatamiName'
    having count(*) > 1
  ) then
    raise exception 'Only one division can run on each tatami';
  end if;

  if exists (
    select 1 from jsonb_array_elements(coalesce(new.snapshot->'competitors', '[]')) as item
    group by item->'data'->>'number' having count(*) > 1
  ) or exists (
    select 1 from jsonb_array_elements(coalesce(new.snapshot->'competitors', '[]')) as item
    group by item->>'id' having count(*) > 1
  ) or exists (
    select 1 from jsonb_array_elements(coalesce(new.snapshot->'divisions', '[]')) as item
    group by item->>'id' having count(*) > 1
  ) then
    raise exception 'Division IDs, competitor IDs and competitor numbers must be unique';
  end if;

  for division_row in
    select value from jsonb_array_elements(coalesce(new.snapshot->'divisions', '[]'))
  loop
    current_data := division_row->'data';
    category_id := coalesce(current_data->>'competitionCategoryId', current_data->>'competitionType');
    if new.snapshot ? 'competitionCategories' then
      select item into category_row
        from jsonb_array_elements(new.snapshot->'competitionCategories') as item
        where item->>'id' = category_id;
      if category_row is null then
        raise exception 'Division competition category does not exist';
      end if;
      category_template := coalesce(current_data->>'competitionTemplate',
        case when current_data->>'competitionType' = 'jiyuKumite' then 'points' else 'flagVoting' end);
      if category_template is distinct from category_row->>'template'
        or (current_data ? 'competitionCategoryName'
          and current_data->>'competitionCategoryName' is distinct from category_row->>'name') then
        raise exception 'Division competition category or template does not match the catalog';
      end if;
    end if;
    if jsonb_array_length(coalesce(current_data->'competitorIds', '[]')) not between 2 and 16
      or (select count(distinct value) from jsonb_array_elements(current_data->'competitorIds'))
        <> jsonb_array_length(current_data->'competitorIds') then
      raise exception 'Divisions require 2-16 unique competitors';
    end if;
    if not exists (
      select 1 from jsonb_array_elements(coalesce(new.snapshot->'tatamiDefinitions', '[]')) as item
      where item->>'name' = current_data->>'assignedTatamiName'
    ) then
      raise exception 'Division tatami does not exist';
    end if;
    for participant in select value from jsonb_array_elements(current_data->'competitorIds')
    loop
      if not exists (
        select 1 from jsonb_array_elements(coalesce(new.snapshot->'competitors', '[]')) as item
        where item->'id' = participant
      ) then
        raise exception 'Division competitor does not exist';
      end if;
    end loop;
  end loop;

  if tg_op = 'UPDATE' then
    for previous_row in
      select value from jsonb_array_elements(coalesce(old.snapshot->'divisions', '[]'))
    loop
      previous_data := previous_row->'data';
      select item into replacement
        from jsonb_array_elements(coalesce(new.snapshot->'divisions', '[]')) as item
        where item->>'id' = previous_row->>'id';
      current_data := replacement->'data';
      if (coalesce(previous_data->>'progress', 'queued') = 'queued'
          and current_data->>'progress' = 'completed')
        or (previous_data->>'progress' = 'completed' and current_data->>'progress' = 'running') then
        raise exception 'Invalid division lifecycle transition';
      end if;
      if coalesce(previous_data->>'progress', 'queued') = 'queued'
        and jsonb_array_length(coalesce(previous_data->'matchRecords', '[]')) = 0
        and jsonb_array_length(coalesce(previous_data->'placements', '[]')) = 0
        and coalesce(previous_data->'inProgressMatch', 'null') = 'null'::jsonb then
        continue;
      end if;
      select item into replacement
        from jsonb_array_elements(coalesce(new.snapshot->'divisions', '[]')) as item
        where item->>'id' = previous_row->>'id';
      if replacement is null then
        raise exception 'Redo the division before deleting it';
      end if;
      current_data := replacement->'data';
      explicitly_reset := current_data->>'progress' = 'queued'
        and jsonb_array_length(coalesce(current_data->'matchRecords', '[]')) = 0
        and jsonb_array_length(coalesce(current_data->'placements', '[]')) = 0
        and coalesce(current_data->'inProgressMatch', 'null') = 'null'::jsonb
        and coalesce(current_data->'startedAt', 'null') = 'null'::jsonb
        and coalesce(current_data->'completedAt', 'null') = 'null'::jsonb;
      if explicitly_reset then continue; end if;
      if current_data->>'progress' = 'queued' and previous_data->>'progress' <> 'queued' then
        raise exception 'Redo must clear all results and unfinished match state';
      end if;
      if (select jsonb_object_agg(key, value) from jsonb_each(previous_data)
          where key in ('competitorIds','competitionType','competitionCategoryId','competitionCategoryName','competitionTemplate','minAge','maxAge','minBeltRank','maxBeltRank','gender'))
        is distinct from
        (select jsonb_object_agg(key, value) from jsonb_each(current_data)
          where key in ('competitorIds','competitionType','competitionCategoryId','competitionCategoryName','competitionTemplate','minAge','maxAge','minBeltRank','maxBeltRank','gender')) then
        raise exception 'Redo the division before changing its bracket';
      end if;
      for participant in select value from jsonb_array_elements(previous_data->'competitorIds')
      loop
        if (select item->'data' from jsonb_array_elements(coalesce(old.snapshot->'competitors', '[]')) as item
            where item->'id' = participant)
          is distinct from
          (select item->'data' from jsonb_array_elements(coalesce(new.snapshot->'competitors', '[]')) as item
            where item->'id' = participant) then
          raise exception 'Competitors in started divisions cannot be edited or removed';
        end if;
      end loop;
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists tournament_snapshot_invariants on public.tournaments;
create trigger tournament_snapshot_invariants
before insert or update on public.tournaments
for each row execute function public.validate_tournament_snapshot();

create or replace function public.save_tournament_snapshot(
  p_id text, p_expected_revision bigint, p_snapshot jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  current_revision bigint;
  saved jsonb;
begin
  insert into public.tournaments (id) values (p_id) on conflict (id) do nothing;
  select revision into current_revision from public.tournaments where id = p_id for update;
  if current_revision is distinct from p_expected_revision then return null; end if;
  saved := (p_snapshot - '_syncBase' - '_syncPending') || jsonb_build_object(
    'revision', current_revision + 1,
    'updated_at', to_char(clock_timestamp() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  );
  update public.tournaments set snapshot = saved, revision = current_revision + 1,
    updated_at = clock_timestamp() where id = p_id;
  return saved;
end;
$$;

revoke all on function public.save_tournament_snapshot(text, bigint, jsonb) from public;
grant execute on function public.save_tournament_snapshot(text, bigint, jsonb) to anon, authenticated;

create or replace function public.delete_tournament(p_id text)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
begin
  delete from public.tournaments where id = p_id;
  delete from public.tournament_credentials where id = p_id;
  return true;
end;
$$;

revoke all on function public.delete_tournament(text) from public;
grant execute on function public.delete_tournament(text) to anon, authenticated;

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
