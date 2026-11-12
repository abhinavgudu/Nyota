-- Row Level Security: each user can only touch their own data
alter table public.profiles enable row level security;
alter table public.events enable row level security;
alter table public.guest_entries enable row level security;
alter table public.gifts enable row level security;

-- PROFILES
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select to authenticated using (id = auth.uid ());

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update to authenticated using (id = auth.uid ()) with check (id = auth.uid ());

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated with check (id = auth.uid ());

-- EVENTS
drop policy if exists "events_select_own" on public.events;
create policy "events_select_own" on public.events
  for select to authenticated using (owner_id = auth.uid ());

drop policy if exists "events_insert_own" on public.events;
create policy "events_insert_own" on public.events
  for insert to authenticated with check (owner_id = auth.uid ());

drop policy if exists "events_update_own" on public.events;
create policy "events_update_own" on public.events
  for update to authenticated using (owner_id = auth.uid ()) with check (owner_id = auth.uid ());

drop policy if exists "events_delete_own" on public.events;
create policy "events_delete_own" on public.events
  for delete to authenticated using (owner_id = auth.uid ());

-- GUEST ENTRIES
drop policy if exists "entries_select_own" on public.guest_entries;
create policy "entries_select_own" on public.guest_entries
  for select to authenticated using (owner_id = auth.uid ());

drop policy if exists "entries_insert_own" on public.guest_entries;
create policy "entries_insert_own" on public.guest_entries
  for insert to authenticated with check (
    owner_id = auth.uid ()
    and exists (
      select 1 from public.events ev
      where ev.id = event_id and ev.owner_id = auth.uid ()
    )
  );

drop policy if exists "entries_update_own" on public.guest_entries;
create policy "entries_update_own" on public.guest_entries
  for update to authenticated
  using (owner_id = auth.uid ())
  with check (
    owner_id = auth.uid ()
    and exists (
      select 1 from public.events ev
      where ev.id = event_id and ev.owner_id = auth.uid ()
    )
  );

drop policy if exists "entries_delete_own" on public.guest_entries;
create policy "entries_delete_own" on public.guest_entries
  for delete to authenticated using (owner_id = auth.uid ());

-- GIFTS
drop policy if exists "gifts_select_own" on public.gifts;
create policy "gifts_select_own" on public.gifts
  for select to authenticated using (owner_id = auth.uid ());

drop policy if exists "gifts_insert_own" on public.gifts;
create policy "gifts_insert_own" on public.gifts
  for insert to authenticated with check (
    owner_id = auth.uid ()
    and exists (
      select 1 from public.guest_entries e
      where e.id = entry_id and e.owner_id = auth.uid ()
    )
  );

drop policy if exists "gifts_update_own" on public.gifts;
create policy "gifts_update_own" on public.gifts
  for update to authenticated
  using (owner_id = auth.uid ())
  with check (
    owner_id = auth.uid ()
    and exists (
      select 1 from public.guest_entries e
      where e.id = entry_id and e.owner_id = auth.uid ()
    )
  );

drop policy if exists "gifts_delete_own" on public.gifts;
create policy "gifts_delete_own" on public.gifts
  for delete to authenticated using (owner_id = auth.uid ());
