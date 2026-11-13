-- Migration 0007 — diagnose & rebuild the RLS policies cleanly.
--
-- Symptom: creating an event fails with
--   42501 "new row violates row-level security policy for table \"events\""
-- even for a correctly signed-in owner (auth.uid() is fine, other tables insert
-- fine). That means the INSERT policy on `events` is not the one we expect
-- (a stale/duplicate/restrictive policy, or one with an extra condition).
--
-- This migration:
--   1) prints the current policies (paste this output if it still fails)
--   2) drops EVERY policy on the four tables and recreates a known-good set
--   3) prints the result
--
-- Safe to run multiple times.

-- ============ 1) DIAGNOSTIC (before) ============
select 'events policies (before)' as section, policyname, cmd, permissive, roles, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'events'
order by policyname;

select 'events columns' as section, column_name, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'events'
order by ordinal_position;

-- ============ 2) remove every policy on our tables ============
do $$
declare r record;
begin
  for r in
    select c.relname as tbl, p.polname as pol
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname in ('events', 'guest_entries', 'gifts', 'event_members')
  loop
    execute format('drop policy if exists %I on public.%I', r.pol, r.tbl);
  end loop;
end $$;

-- ============ 3) recreate the known-good policies ============

-- EVENTS -------------------------------------------------------------
create policy "events_select_member" on public.events
  for select to authenticated
  using (public.is_event_member(id));

create policy "events_insert_own" on public.events
  for insert to authenticated
  with check (owner_id = auth.uid());

create policy "events_update_own" on public.events
  for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy "events_delete_own" on public.events
  for delete to authenticated
  using (owner_id = auth.uid());

-- EVENT MEMBERS ------------------------------------------------------
create policy "event_members_select" on public.event_members
  for select to authenticated
  using (user_id = auth.uid() or public.is_event_owner(event_id));

create policy "event_members_insert_self" on public.event_members
  for insert to authenticated
  with check (user_id = auth.uid());

create policy "event_members_delete" on public.event_members
  for delete to authenticated
  using (user_id = auth.uid() or public.is_event_owner(event_id));

-- GUEST ENTRIES ------------------------------------------------------
create policy "entries_select_member" on public.guest_entries
  for select to authenticated
  using (public.is_event_member(event_id));

create policy "entries_insert_member" on public.guest_entries
  for insert to authenticated
  with check (
    owner_id = auth.uid()
    and public.is_event_member(event_id)
  );

create policy "entries_update_member" on public.guest_entries
  for update to authenticated
  using (public.is_event_member(event_id))
  with check (
    owner_id = auth.uid()
    and public.is_event_member(event_id)
  );

create policy "entries_delete_member" on public.guest_entries
  for delete to authenticated
  using (public.is_event_member(event_id));

-- GIFTS ---------------------------------------------------------------
create policy "gifts_select_member" on public.gifts
  for select to authenticated
  using (exists (
    select 1 from public.guest_entries ge
    where ge.id = entry_id and public.is_event_member(ge.event_id)
  ));

create policy "gifts_insert_member" on public.gifts
  for insert to authenticated
  with check (
    owner_id = auth.uid()
    and exists (
      select 1 from public.guest_entries ge
      where ge.id = entry_id and public.is_event_member(ge.event_id)
    )
  );

create policy "gifts_update_member" on public.gifts
  for update to authenticated
  using (exists (
    select 1 from public.guest_entries ge
    where ge.id = entry_id and public.is_event_member(ge.event_id)
  ))
  with check (
    owner_id = auth.uid()
    and exists (
      select 1 from public.guest_entries ge
      where ge.id = entry_id and public.is_event_member(ge.event_id)
    )
  );

create policy "gifts_delete_member" on public.gifts
  for delete to authenticated
  using (exists (
    select 1 from public.guest_entries ge
    where ge.id = entry_id and public.is_event_member(ge.event_id)
  ));

-- ============ 4) make sure the join_code machinery is intact ============
alter table public.events add column if not exists join_code text;

create or replace function public.generate_join_code ()
returns text
language plpgsql
as $$
declare
  chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  result text := '';
  i int;
begin
  for i in 1..8 loop
    result := result || substr(chars, floor(random() * length(chars) + 1)::int, 1);
  end loop;
  return result;
end;
$$;

create or replace function public.ensure_event_join_code ()
returns trigger
language plpgsql
as $$
declare c text;
begin
  if new.join_code is null or btrim(new.join_code) = '' then
    loop
      c := public.generate_join_code();
      exit when not exists (select 1 from public.events where join_code = c);
    end loop;
    new.join_code := c;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_events_join_code on public.events;
create trigger trg_events_join_code
before insert on public.events
for each row execute function public.ensure_event_join_code ();

alter table public.events alter column join_code set default public.generate_join_code();

do $$
declare r record; c text;
begin
  for r in select id from public.events where join_code is null or btrim(join_code) = '' loop
    loop
      c := public.generate_join_code();
      exit when not exists (select 1 from public.events where join_code = c);
    end loop;
    update public.events set join_code = c where id = r.id;
  end loop;
end $$;

alter table public.events alter column join_code set not null;
create unique index if not exists events_join_code_idx on public.events (join_code);

-- ============ 5) DIAGNOSTIC (after) ============
select 'events policies (after)' as section, policyname, cmd, permissive, roles, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'events'
order by policyname;

select 'all policies' as section, tablename, policyname, cmd, permissive
from pg_policies
where schemaname = 'public'
  and tablename in ('events', 'event_members', 'guest_entries', 'gifts')
order by tablename, policyname;

select 'events rows' as section, count(*)::text as value from public.events;
