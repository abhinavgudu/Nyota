-- Repair migration: make sure the whole "event sharing" machinery exists and is
-- consistent, even if 0004 was only partially applied.
--
-- Common symptom this fixes: "Couldn't create event" — the events table has
-- join_code as NOT NULL but the trigger that fills it was never created
-- (so every insert fails with a NOT NULL violation), or the column / table /
-- RPC is missing entirely.
--
-- Safe to run multiple times.

-- ============ 1) join_code column ============
alter table public.events add column if not exists join_code text;

-- ============ 2) code generator ============
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

-- ============ 3) trigger function ============
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

-- ============ 4) trigger (re-created every time) ============
drop trigger if exists trg_events_join_code on public.events;
create trigger trg_events_join_code
before insert on public.events
for each row execute function public.ensure_event_join_code ();

-- ============ 5) safety-net default (inserts work even without the trigger) ============
alter table public.events alter column join_code set default public.generate_join_code();

-- ============ 6) backfill anything still empty ============
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

-- ============ 7) NOT NULL + unique index ============
alter table public.events alter column join_code set not null;
create unique index if not exists events_join_code_idx on public.events (join_code);

-- ============ 8) membership table ============
create table if not exists public.event_members (
  event_id uuid not null references public.events (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

create index if not exists event_members_user_idx on public.event_members (user_id);

alter table public.event_members enable row level security;

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

-- ============ 9) helper functions (RLS-safe, no recursion) ============
create or replace function public.is_event_owner (p_event_id uuid)
returns boolean
language sql
stable
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
stable
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

-- ============ 10) join RPC ============
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

-- ============ 11) policies on events / entries / gifts ============
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

drop policy if exists "entries_select_own" on public.guest_entries;
drop policy if exists "entries_select_member" on public.guest_entries;
create policy "entries_select_member" on public.guest_entries
  for select to authenticated
  using (public.is_event_member(event_id));

drop policy if exists "entries_insert_own" on public.guest_entries;
drop policy if exists "entries_insert_member" on public.guest_entries;
create policy "entries_insert_member" on public.guest_entries
  for insert to authenticated
  with check (owner_id = auth.uid() and public.is_event_member(event_id));

drop policy if exists "entries_update_own" on public.guest_entries;
drop policy if exists "entries_update_member" on public.guest_entries;
create policy "entries_update_member" on public.guest_entries
  for update to authenticated
  using (public.is_event_member(event_id))
  with check (owner_id = auth.uid() and public.is_event_member(event_id));

drop policy if exists "entries_delete_own" on public.guest_entries;
drop policy if exists "entries_delete_member" on public.guest_entries;
create policy "entries_delete_member" on public.guest_entries
  for delete to authenticated
  using (public.is_event_member(event_id));

drop policy if exists "gifts_select_own" on public.gifts;
drop policy if exists "gifts_select_member" on public.gifts;
create policy "gifts_select_member" on public.gifts
  for select to authenticated
  using (exists (
    select 1 from public.guest_entries ge
    where ge.id = entry_id and public.is_event_member(ge.event_id)
  ));

drop policy if exists "gifts_insert_own" on public.gifts;
drop policy if exists "gifts_insert_member" on public.gifts;
create policy "gifts_insert_member" on public.gifts
  for insert to authenticated
  with check (owner_id = auth.uid() and exists (
    select 1 from public.guest_entries ge
    where ge.id = entry_id and public.is_event_member(ge.event_id)
  ));

drop policy if exists "gifts_update_own" on public.gifts;
drop policy if exists "gifts_update_member" on public.gifts;
create policy "gifts_update_member" on public.gifts
  for update to authenticated
  using (exists (
    select 1 from public.guest_entries ge
    where ge.id = entry_id and public.is_event_member(ge.event_id)
  ))
  with check (owner_id = auth.uid() and exists (
    select 1 from public.guest_entries ge
    where ge.id = entry_id and public.is_event_member(ge.event_id)
  ));

drop policy if exists "gifts_delete_own" on public.gifts;
drop policy if exists "gifts_delete_member" on public.gifts;
create policy "gifts_delete_member" on public.gifts
  for delete to authenticated
  using (exists (
    select 1 from public.guest_entries ge
    where ge.id = entry_id and public.is_event_member(ge.event_id)
  ));

-- ============ 12) dashboard totals ============
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

-- ============ 13) diagnostics — paste this output if something still fails ============
select 'events columns' as what, column_name, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'events'
order by ordinal_position;

select 'events triggers' as what, tgname
from pg_trigger
where tgrelid = 'public.events'::regclass and not tgisinternal;

select 'rows' as what, count(*)::text as value from public.events;
