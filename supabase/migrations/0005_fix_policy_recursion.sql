-- Fix: RLS infinite recursion (42P17) on relation "events"
--
-- Why this happens:
--   events_select_member policy  -> reads public.event_members
--   event_members_select policy  -> reads public.events
--   => Postgres sees a cycle between the two policies and refuses to run
--      ("infinite recursion detected in policy for relation \"events\"").
--
-- Fix: never let a policy read the other table directly. Both checks move into
-- SECURITY DEFINER helper functions, which bypass RLS for their internal reads,
-- so the cycle is broken and the rules still hold:
--   - event owners can read/update/delete their own events and entries
--   - joined members can read and add entries to the event
--
-- Safe to run multiple times.

-- ============ 1) Helpers (SECURITY DEFINER -> bypass RLS internally) ============

create or replace function public.is_event_owner (p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.events e
    where e.id = p_event_id
      and e.owner_id = auth.uid()
  );
$$;

create or replace function public.is_event_member (p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_event_owner(p_event_id)
      or exists (
        select 1
        from public.event_members m
        where m.event_id = p_event_id
          and m.user_id = auth.uid()
      );
$$;

grant execute on function public.is_event_owner (uuid) to authenticated;
grant execute on function public.is_event_member (uuid) to authenticated;

-- ============ 2) EVENTS ============

drop policy if exists "events_select_own" on public.events;
drop policy if exists "events_select_member" on public.events;
create policy "events_select_member" on public.events
  for select to authenticated
  using (public.is_event_member(id));

drop policy if exists "events_insert_own" on public.events;
create policy "events_insert_own" on public.events
  for insert to authenticated
  with check (owner_id = auth.uid());

drop policy if exists "events_update_own" on public.events;
create policy "events_update_own" on public.events
  for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists "events_delete_own" on public.events;
create policy "events_delete_own" on public.events
  for delete to authenticated
  using (owner_id = auth.uid());

-- ============ 3) EVENT MEMBERS ============

drop policy if exists "event_members_select" on public.event_members;
create policy "event_members_select" on public.event_members
  for select to authenticated
  using (user_id = auth.uid() or public.is_event_owner(event_id));

drop policy if exists "event_members_insert_self" on public.event_members;
create policy "event_members_insert_self" on public.event_members
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "event_members_delete" on public.event_members;
create policy "event_members_delete" on public.event_members
  for delete to authenticated
  using (user_id = auth.uid() or public.is_event_owner(event_id));

-- ============ 4) GUEST ENTRIES ============

drop policy if exists "entries_select_own" on public.guest_entries;
drop policy if exists "entries_select_member" on public.guest_entries;
create policy "entries_select_member" on public.guest_entries
  for select to authenticated
  using (public.is_event_member(event_id));

drop policy if exists "entries_insert_own" on public.guest_entries;
drop policy if exists "entries_insert_member" on public.guest_entries;
create policy "entries_insert_member" on public.guest_entries
  for insert to authenticated
  with check (
    owner_id = auth.uid()
    and public.is_event_member(event_id)
  );

drop policy if exists "entries_update_own" on public.guest_entries;
drop policy if exists "entries_update_member" on public.guest_entries;
create policy "entries_update_member" on public.guest_entries
  for update to authenticated
  using (public.is_event_member(event_id))
  with check (
    owner_id = auth.uid()
    and public.is_event_member(event_id)
  );

drop policy if exists "entries_delete_own" on public.guest_entries;
drop policy if exists "entries_delete_member" on public.guest_entries;
create policy "entries_delete_member" on public.guest_entries
  for delete to authenticated
  using (public.is_event_member(event_id));

-- ============ 5) GIFTS ============

drop policy if exists "gifts_select_own" on public.gifts;
drop policy if exists "gifts_select_member" on public.gifts;
create policy "gifts_select_member" on public.gifts
  for select to authenticated
  using (
    exists (
      select 1
      from public.guest_entries ge
      where ge.id = entry_id
        and public.is_event_member(ge.event_id)
    )
  );

drop policy if exists "gifts_insert_own" on public.gifts;
drop policy if exists "gifts_insert_member" on public.gifts;
create policy "gifts_insert_member" on public.gifts
  for insert to authenticated
  with check (
    owner_id = auth.uid()
    and exists (
      select 1
      from public.guest_entries ge
      where ge.id = entry_id
        and public.is_event_member(ge.event_id)
    )
  );

drop policy if exists "gifts_update_own" on public.gifts;
drop policy if exists "gifts_update_member" on public.gifts;
create policy "gifts_update_member" on public.gifts
  for update to authenticated
  using (
    exists (
      select 1
      from public.guest_entries ge
      where ge.id = entry_id
        and public.is_event_member(ge.event_id)
    )
  )
  with check (
    owner_id = auth.uid()
    and exists (
      select 1
      from public.guest_entries ge
      where ge.id = entry_id
        and public.is_event_member(ge.event_id)
    )
  );

drop policy if exists "gifts_delete_own" on public.gifts;
drop policy if exists "gifts_delete_member" on public.gifts;
create policy "gifts_delete_member" on public.gifts
  for delete to authenticated
  using (
    exists (
      select 1
      from public.guest_entries ge
      where ge.id = entry_id
        and public.is_event_member(ge.event_id)
    )
  );

-- ============ 6) Dashboard totals (member aware) ============

create or replace function public.get_dashboard_totals (p_event_id uuid)
returns table (
  total_guests bigint,
  total_nyota_cash numeric,
  total_food_only numeric,
  total_cash numeric,
  total_gifts bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    count(distinct e.id)::bigint as total_guests,
    coalesce(sum(case when e.category = 'nyota_gifts' then e.cash_amount else 0 end), 0) as total_nyota_cash,
    coalesce(sum(case when e.category = 'food_only' then e.cash_amount else 0 end), 0) as total_food_only,
    coalesce(sum(e.cash_amount), 0) as total_cash,
    (select count(*) from public.gifts g where g.entry_id in (
       select id from public.guest_entries where event_id = p_event_id))::bigint as total_gifts
  from public.guest_entries e
  where e.event_id = p_event_id
    and public.is_event_member(p_event_id);
$$;

grant execute on function public.get_dashboard_totals (uuid) to authenticated;

-- ============ 7) Quick check (should list the policies, no errors) ============
select tablename, policyname from pg_policies
where schemaname = 'public' and tablename in ('events', 'event_members', 'guest_entries', 'gifts')
order by tablename, policyname;
