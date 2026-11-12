-- Nyota schema: profiles, events, guest entries, gifts
create extension if not exists "pgcrypto";

-- ============ PROFILES ============
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  created_at timestamptz not null default now()
);

-- ============ EVENTS ============
create table if not exists public.events (
  id uuid primary key default gen_random_uuid (),
  owner_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  event_date date,
  created_at timestamptz not null default now ()
);

create index if not exists events_owner_idx on public.events (owner_id, created_at desc);

-- ============ GUEST ENTRIES ============
-- One row per contribution. category: 'nyota_gifts' | 'food_only'
create table if not exists public.guest_entries (
  id uuid primary key default gen_random_uuid (),
  -- client-generated id so a retried save cannot create a duplicate row
  client_id uuid not null default gen_random_uuid () unique,
  event_id uuid not null references public.events (id) on delete cascade,
  owner_id uuid not null references auth.users (id) on delete cascade,
  category text not null check (category in ('nyota_gifts', 'food_only')),
  guest_name text,
  father_name text,
  village text,
  cash_amount numeric (12, 2) not null default 0 check (cash_amount >= 0),
  created_at timestamptz not null default now (),
  updated_at timestamptz not null default now ()
);

create index if not exists guest_entries_event_idx on public.guest_entries (event_id, created_at desc);
create index if not exists guest_entries_owner_idx on public.guest_entries (owner_id);
create index if not exists guest_entries_category_idx on public.guest_entries (event_id, category);
create index if not exists guest_entries_name_idx on public.guest_entries (event_id, lower(coalesce(guest_name, '')));

-- ============ GIFTS ============
create table if not exists public.gifts (
  id uuid primary key default gen_random_uuid (),
  client_id uuid not null default gen_random_uuid () unique,
  entry_id uuid not null references public.guest_entries (id) on delete cascade,
  owner_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  description text,
  -- Supabase Storage path, e.g. '<uid>/<entryId>/<uuid>.jpg'
  image_path text,
  created_at timestamptz not null default now ()
);

create index if not exists gifts_entry_idx on public.gifts (entry_id);
create index if not exists gifts_owner_idx on public.gifts (owner_id);

-- ============ updated_at trigger ============
create or replace function public.set_updated_at ()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now ();
  return new;
end;
$$;

drop trigger if exists trg_guest_entries_updated on public.guest_entries;
create trigger trg_guest_entries_updated
before update on public.guest_entries
for each row execute function public.set_updated_at ();

-- ============ new user -> profile ============
create or replace function public.handle_new_user ()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_on_auth_user_created on auth.users;
create trigger trg_on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user ();

-- ============ DASHBOARD TOTALS (single query, no double counting) ============
-- Returns all dashboard numbers for one event in one round-trip.
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
security invoker
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
  where e.event_id = p_event_id;
$$;
