-- Event sharing: join codes, members, and collaborative access
-- Run this AFTER 0001/0002/0003 on existing projects.

-- 1) Join code on events (short, human-friendly, shareable)
alter table public.events add column if not exists join_code text;

-- Generate a random 8-char uppercase alphanumeric code.
create or replace function public.generate_join_code ()
returns text
language plpgsql
as $$
declare
  chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- no confusing 0/O/1/I
  result text := '';
  i int;
begin
  for i in 1..8 loop
    result := result || substr(chars, floor(random() * length(chars) + 1)::int, 1);
  end loop;
  return result;
end;
$$;

-- Backfill existing events that have no code yet.
do $$
declare r record; c text;
begin
  for r in select id from public.events where join_code is null or join_code = '' loop
    loop
      c := public.generate_join_code();
      exit when not exists (select 1 from public.events where join_code = c);
    end loop;
    update public.events set join_code = c where id = r.id;
  end loop;
end $$;

-- Ensure every future event gets a unique join code automatically.
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

alter table public.events alter column join_code set not null;
create unique index if not exists events_join_code_idx on public.events (join_code);

-- 2) Event members (users who joined via code)
create table if not exists public.event_members (
  event_id uuid not null references public.events (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

create index if not exists event_members_user_idx on public.event_members (user_id);

alter table public.event_members enable row level security;

-- Members can see their own membership rows; owners can see members of their events.
drop policy if exists "event_members_select" on public.event_members;
create policy "event_members_select" on public.event_members
  for select to authenticated
  using (
    user_id = auth.uid()
    or exists (select 1 from public.events e where e.id = event_id and e.owner_id = auth.uid())
  );

-- Users can add themselves as members (join); actual code validation is done by RPC.
drop policy if exists "event_members_insert_self" on public.event_members;
create policy "event_members_insert_self" on public.event_members
  for insert to authenticated
  with check (user_id = auth.uid());

-- Users can leave events they joined; owners can remove members.
drop policy if exists "event_members_delete" on public.event_members;
create policy "event_members_delete" on public.event_members
  for delete to authenticated
  using (
    user_id = auth.uid()
    or exists (select 1 from public.events e where e.id = event_id and e.owner_id = auth.uid())
  );

-- 3) Helper: is the current user owner or member of this event?
create or replace function public.is_event_member (p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.events e
    where e.id = p_event_id and e.owner_id = auth.uid()
  ) or exists (
    select 1 from public.event_members m
    where m.event_id = p_event_id and m.user_id = auth.uid()
  );
$$;

-- 4) Join an event by its share code (returns the event)
create or replace function public.join_event_by_code (p_code text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  ev record;
  uid uuid;
  normalized text;
begin
  uid := auth.uid();
  if uid is null then
    raise exception 'Not authenticated';
  end if;
  normalized := upper(btrim(p_code));
  select id, name, event_date, join_code, owner_id into ev
  from public.events where upper(join_code) = normalized;
  if ev.id is null then
    raise exception 'Invalid event code';
  end if;
  insert into public.event_members (event_id, user_id)
  values (ev.id, uid)
  on conflict (event_id, user_id) do nothing;
  return json_build_object(
    'id', ev.id,
    'name', ev.name,
    'event_date', ev.event_date,
    'join_code', ev.join_code,
    'owner_id', ev.owner_id
  );
end;
$$;

grant execute on function public.join_event_by_code (text) to authenticated;
grant execute on function public.is_event_member (uuid) to authenticated;

-- 5) Update RLS policies to allow collaborative access (owner OR member)

-- EVENTS: members can read events they joined (not just owner)
drop policy if exists "events_select_own" on public.events;
drop policy if exists "events_select_member" on public.events;
create policy "events_select_member" on public.events
  for select to authenticated
  using (
    owner_id = auth.uid()
    or exists (select 1 from public.event_members m where m.event_id = id and m.user_id = auth.uid())
  );

-- Only owner can update/delete their event (keep strict)
-- events_insert_own, events_update_own, events_delete_own remain as-is.

-- GUEST ENTRIES: any event member can CRUD entries in the event
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

-- GIFTS: any event member can CRUD gifts for entries in the event
drop policy if exists "gifts_select_own" on public.gifts;
drop policy if exists "gifts_select_member" on public.gifts;
create policy "gifts_select_member" on public.gifts
  for select to authenticated
  using (
    exists (
      select 1 from public.guest_entries ge
      where ge.id = entry_id and public.is_event_member(ge.event_id)
    )
  );

drop policy if exists "gifts_insert_own" on public.gifts;
drop policy if exists "gifts_insert_member" on public.gifts;
create policy "gifts_insert_member" on public.gifts
  for insert to authenticated
  with check (
    owner_id = auth.uid()
    and exists (
      select 1 from public.guest_entries ge
      where ge.id = entry_id and public.is_event_member(ge.event_id)
    )
  );

drop policy if exists "gifts_update_own" on public.gifts;
drop policy if exists "gifts_update_member" on public.gifts;
create policy "gifts_update_member" on public.gifts
  for update to authenticated
  using (
    exists (
      select 1 from public.guest_entries ge
      where ge.id = entry_id and public.is_event_member(ge.event_id)
    )
  )
  with check (
    owner_id = auth.uid()
    and exists (
      select 1 from public.guest_entries ge
      where ge.id = entry_id and public.is_event_member(ge.event_id)
    )
  );

drop policy if exists "gifts_delete_own" on public.gifts;
drop policy if exists "gifts_delete_member" on public.gifts;
create policy "gifts_delete_member" on public.gifts
  for delete to authenticated
  using (
    exists (
      select 1 from public.guest_entries ge
      where ge.id = entry_id and public.is_event_member(ge.event_id)
    )
  );

-- 6) Make dashboard totals accessible to members (security definer so it can read)
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

-- 7) Storage: allow members to upload images to event entries they can access
-- Images are stored as <uploader-uid>/<entryId>/... so uploader folder policy still works.
-- Read access is already public. No storage policy change needed for basic collaboration.
