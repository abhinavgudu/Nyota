-- Migration 0008 — fix "42501 new row violates row-level security policy" on
-- INSERT ... RETURNING (event creation failed for every user).
--
-- Root cause:
--   `is_event_owner` / `is_event_member` were declared STABLE. A STABLE
--   function uses the snapshot taken at the start of the statement, in which
--   the row that was JUST inserted is not visible yet. The SELECT policy on
--   `events` is evaluated for the returned row of `INSERT ... RETURNING`, so
--   the owner check returned false -> Postgres rejected the insert with 42501.
--   (A plain INSERT without RETURNING succeeded, which is why the symptom was
--   confusing.)
--
-- Fix:
--   1) make both helpers VOLATILE so they see the current transaction state
--   2) check the owner inline in the SELECT policies (direct column compare,
--      no snapshot involved) and use the helper only for joined members
--
-- Safe to run multiple times.

create or replace function public.is_event_owner (p_event_id uuid)
returns boolean
language sql
volatile
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.events e
    where e.id = p_event_id and e.owner_id = auth.uid()
  );
$$;

create or replace function public.is_event_member (p_event_id uuid)
returns boolean
language sql
volatile
security definer
set search_path = public
as $$
  select public.is_event_owner(p_event_id)
      or exists (
        select 1 from public.event_members m
        where m.event_id = p_event_id and m.user_id = auth.uid()
      );
$$;

grant execute on function public.is_event_owner (uuid) to authenticated;
grant execute on function public.is_event_member (uuid) to authenticated;

drop policy if exists "events_select_member" on public.events;
create policy "events_select_member" on public.events
  for select to authenticated
  using (owner_id = auth.uid() or public.is_event_member(id));

drop policy if exists "entries_select_member" on public.guest_entries;
create policy "entries_select_member" on public.guest_entries
  for select to authenticated
  using (owner_id = auth.uid() or public.is_event_member(event_id));

drop policy if exists "gifts_select_member" on public.gifts;
create policy "gifts_select_member" on public.gifts
  for select to authenticated
  using (exists (
    select 1 from public.guest_entries ge
    where ge.id = entry_id
      and (ge.owner_id = auth.uid() or public.is_event_member(ge.event_id))
  ));
