-- =============================================================================
--  Nyota — ONE FILE FIX (run this in Supabase → SQL Editor → Run)
-- =============================================================================
--  Ye file poori database ko ek hi baar me sahi state me set karta hai:
--    • tables + columns + indexes
--    • triggers (updated_at, new-user profile, event join code)
--    • helper functions (is_event_owner / is_event_member / join_event_by_code
--      / get_dashboard_totals)
--    • RLS policies (saari purani policies hata kar nayi, verified wali)
--    • storage bucket 'gift-images' + uski policies
--  End me ek SELF-TEST chalta hai jo (a) event insert (b) entry insert
--  (c) totals — sab verify karta hai aur ROLLBACK kar deta hai (koi test data
--  nahi chhota).
--
--  Safe to run any number of times.
-- =============================================================================

-- ============================ 1) EXTENSIONS ================================
create extension if not exists "pgcrypto";

-- ============================ 2) TABLES ====================================
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  created_at timestamptz not null default now()
);

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  event_date date,
  join_code text,
  created_at timestamptz not null default now()
);

create table if not exists public.guest_entries (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null default gen_random_uuid() unique,
  event_id uuid not null references public.events (id) on delete cascade,
  owner_id uuid not null references auth.users (id) on delete cascade,
  category text not null check (category in ('nyota_gifts', 'food_only')),
  guest_name text,
  father_name text,
  village text,
  cash_amount numeric(12, 2) not null default 0 check (cash_amount >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.gifts (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null default gen_random_uuid() unique,
  entry_id uuid not null references public.guest_entries (id) on delete cascade,
  owner_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  description text,
  image_path text,
  created_at timestamptz not null default now()
);

create table if not exists public.event_members (
  event_id uuid not null references public.events (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

-- ============================ 3) INDEXES ===================================
create index if not exists events_owner_idx on public.events (owner_id, created_at desc);
create index if not exists guest_entries_event_idx on public.guest_entries (event_id, created_at desc);
create index if not exists guest_entries_owner_idx on public.guest_entries (owner_id);
create index if not exists guest_entries_category_idx on public.guest_entries (event_id, category);
create index if not exists guest_entries_name_idx on public.guest_entries (event_id, lower(coalesce(guest_name, '')));
create index if not exists gifts_entry_idx on public.gifts (entry_id);
create index if not exists gifts_owner_idx on public.gifts (owner_id);
create index if not exists event_members_user_idx on public.event_members (user_id);

-- ============================ 4) FUNCTIONS =================================
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists trg_guest_entries_updated on public.guest_entries;
create trigger trg_guest_entries_updated
before update on public.guest_entries
for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists trg_on_auth_user_created on auth.users;
create trigger trg_on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- join code generator -------------------------------------------------------
create or replace function public.generate_join_code()
returns text language plpgsql as $$
declare
  chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  result text := '';
  i int;
begin
  for i in 1..8 loop
    result := result || substr(chars, floor(random() * length(chars) + 1)::int, 1);
  end loop;
  return result;
end $$;

create or replace function public.ensure_event_join_code()
returns trigger language plpgsql as $$
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
end $$;

-- owner / member checks (SECURITY DEFINER so RLS policies never recurse) -----
create or replace function public.is_event_owner(p_event_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.events e
    where e.id = p_event_id and e.owner_id = auth.uid()
  );
$$;

create or replace function public.is_event_member(p_event_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_event_owner(p_event_id)
      or exists (
        select 1 from public.event_members m
        where m.event_id = p_event_id and m.user_id = auth.uid()
      );
$$;

-- join an event by code -----------------------------------------------------
create or replace function public.join_event_by_code(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare
  ev record; uid uuid; normalized text;
begin
  uid := auth.uid();
  if uid is null then raise exception 'Not authenticated'; end if;
  normalized := upper(btrim(p_code));
  select id, name, event_date, join_code, owner_id into ev
  from public.events where upper(join_code) = normalized;
  if ev.id is null then raise exception 'Invalid event code'; end if;
  insert into public.event_members (event_id, user_id)
  values (ev.id, uid) on conflict (event_id, user_id) do nothing;
  return json_build_object('id', ev.id, 'name', ev.name, 'event_date', ev.event_date,
                           'join_code', ev.join_code, 'owner_id', ev.owner_id);
end $$;

-- dashboard totals ----------------------------------------------------------
create or replace function public.get_dashboard_totals(p_event_id uuid)
returns table (
  total_guests bigint, total_nyota_cash numeric, total_food_only numeric,
  total_cash numeric, total_gifts bigint
)
language sql stable security definer set search_path = public as $$
  select
    count(distinct e.id)::bigint,
    coalesce(sum(case when e.category = 'nyota_gifts' then e.cash_amount else 0 end), 0),
    coalesce(sum(case when e.category = 'food_only' then e.cash_amount else 0 end), 0),
    coalesce(sum(e.cash_amount), 0),
    (select count(*) from public.gifts g where g.entry_id in (
       select id from public.guest_entries where event_id = p_event_id))::bigint
  from public.guest_entries e
  where e.event_id = p_event_id and public.is_event_member(p_event_id);
$$;

grant execute on function public.is_event_owner (uuid) to authenticated;
grant execute on function public.is_event_member (uuid) to authenticated;
grant execute on function public.join_event_by_code (text) to authenticated;
grant execute on function public.get_dashboard_totals (uuid) to authenticated;

-- ============================ 5) JOIN CODE COLUMN ==========================
alter table public.events add column if not exists join_code text;

drop trigger if exists trg_events_join_code on public.events;
create trigger trg_events_join_code
before insert on public.events
for each row execute function public.ensure_event_join_code();

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

update public.events set join_code = public.generate_join_code()
where join_code is null or btrim(join_code) = '';

alter table public.events alter column join_code set not null;
create unique index if not exists events_join_code_idx on public.events (join_code);

-- ============================ 6) RLS: RESET ALL POLICIES ===================
alter table public.profiles enable row level security;
alter table public.events enable row level security;
alter table public.guest_entries enable row level security;
alter table public.gifts enable row level security;
alter table public.event_members enable row level security;

-- remove EVERY policy on our tables (clean slate, no leftovers)
do $$
declare r record;
begin
  for r in
    select c.relname as tbl, p.polname as pol
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname in ('profiles','events','guest_entries','gifts','event_members')
  loop
    execute format('drop policy if exists %I on public.%I', r.pol, r.tbl);
  end loop;
end $$;

-- PROFILES ------------------------------------------------------------------
create policy "profiles_select_own" on public.profiles
  for select to authenticated using (id = auth.uid());
create policy "profiles_update_own" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated with check (id = auth.uid());

-- EVENTS --------------------------------------------------------------------
create policy "events_select_member" on public.events
  for select to authenticated using (public.is_event_member(id));
create policy "events_insert_own" on public.events
  for insert to authenticated with check (owner_id = auth.uid());
create policy "events_update_own" on public.events
  for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "events_delete_own" on public.events
  for delete to authenticated using (owner_id = auth.uid());

-- EVENT MEMBERS -------------------------------------------------------------
create policy "event_members_select" on public.event_members
  for select to authenticated using (user_id = auth.uid() or public.is_event_owner(event_id));
create policy "event_members_insert_self" on public.event_members
  for insert to authenticated with check (user_id = auth.uid());
create policy "event_members_delete" on public.event_members
  for delete to authenticated using (user_id = auth.uid() or public.is_event_owner(event_id));

-- GUEST ENTRIES -------------------------------------------------------------
create policy "entries_select_member" on public.guest_entries
  for select to authenticated using (public.is_event_member(event_id));
create policy "entries_insert_member" on public.guest_entries
  for insert to authenticated with check (owner_id = auth.uid() and public.is_event_member(event_id));
create policy "entries_update_member" on public.guest_entries
  for update to authenticated using (public.is_event_member(event_id))
  with check (owner_id = auth.uid() and public.is_event_member(event_id));
create policy "entries_delete_member" on public.guest_entries
  for delete to authenticated using (public.is_event_member(event_id));

-- GIFTS ---------------------------------------------------------------------
create policy "gifts_select_member" on public.gifts
  for select to authenticated using (exists (
    select 1 from public.guest_entries ge
    where ge.id = entry_id and public.is_event_member(ge.event_id)));
create policy "gifts_insert_member" on public.gifts
  for insert to authenticated with check (owner_id = auth.uid() and exists (
    select 1 from public.guest_entries ge
    where ge.id = entry_id and public.is_event_member(ge.event_id)));
create policy "gifts_update_member" on public.gifts
  for update to authenticated using (exists (
    select 1 from public.guest_entries ge
    where ge.id = entry_id and public.is_event_member(ge.event_id)))
  with check (owner_id = auth.uid() and exists (
    select 1 from public.guest_entries ge
    where ge.id = entry_id and public.is_event_member(ge.event_id)));
create policy "gifts_delete_member" on public.gifts
  for delete to authenticated using (exists (
    select 1 from public.guest_entries ge
    where ge.id = entry_id and public.is_event_member(ge.event_id)));

-- ============================ 7) STORAGE ===================================
insert into storage.buckets (id, name, public)
values ('gift-images', 'gift-images', true)
on conflict (id) do update set public = true;

drop policy if exists "gift_images_insert_own_folder" on storage.objects;
create policy "gift_images_insert_own_folder" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'gift-images' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "gift_images_select_public" on storage.objects;
create policy "gift_images_select_public" on storage.objects
  for select using (bucket_id = 'gift-images');

drop policy if exists "gift_images_update_own_folder" on storage.objects;
create policy "gift_images_update_own_folder" on storage.objects
  for update to authenticated
  using (bucket_id = 'gift-images' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'gift-images' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "gift_images_delete_own_folder" on storage.objects;
create policy "gift_images_delete_own_folder" on storage.objects
  for delete to authenticated
  using (bucket_id = 'gift-images' and (storage.foldername(name))[1] = auth.uid()::text);

-- ============================ 8) SELF-TEST (rollback safe) =================
-- Ye andar hi test karta hai ki RLS policies kaam kar rahi hain ya nahi.
-- Test rows rollback ho jate hain — database me koi test data nahi rahega.
do $$
declare
  v_uid uuid := '11111111-2222-3333-4444-555555555555';
  v_event uuid;
  v_entry uuid;
  v_code text;
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_uid::text, 'role', 'authenticated')::text, true);
  begin
    -- act as the app user (RLS on)
    execute 'set local role authenticated';

    insert into public.events (owner_id, name)
    values (v_uid, 'SELF TEST EVENT')
    returning id, join_code into v_event, v_code;

    insert into public.guest_entries (event_id, owner_id, category, guest_name, cash_amount)
    values (v_event, v_uid, 'food_only', 'SELF TEST GUEST', 501)
    returning id into v_entry;

    insert into public.gifts (entry_id, owner_id, name)
    values (v_entry, v_uid, 'SELF TEST GIFT');

    if (select count(*) from public.get_dashboard_totals(v_event)) <> 1 then
      raise exception 'totals not readable';
    end if;

    raise notice 'SELF TEST PASSED - event insert, entry insert, gift insert and totals all OK (join_code=%)', v_code;
  exception when others then
    raise notice 'SELF TEST FAILED - %', sqlerrm;
  end;
  execute 'reset role';
end $$;

-- ============================ 9) FINAL REPORT ===============================
select 'policies' as section, tablename, policyname, cmd, permissive
from pg_policies
where schemaname = 'public'
  and tablename in ('profiles','events','event_members','guest_entries','gifts')
order by tablename, policyname;

select 'events' as section, count(*)::text as rows from public.events
union all select 'guest_entries', count(*)::text from public.guest_entries
union all select 'gifts', count(*)::text from public.gifts;
