# Nyota — Guest & Gift Management App

A simple, modern, fast guest & gift manager for Indian events. One Supabase project powers both the mobile app (Flutter) and the website (Next.js).

- **Mobile:** Flutter (`mobile/`)
- **Website:** Next.js + TypeScript (`web/`)
- **Backend / DB:** Supabase (Postgres + Auth + Storage) (`supabase/migrations/`)

Sections: Login / Sign Up · Dashboard · Add Entry (Nyota with Gifts + Food Only quick entry) · Guest Register (search, edit, delete, PDF export).

---

## Repository structure

```
Nyota/
├── mobile/                    # Flutter app
│   ├── lib/
│   │   ├── main.dart          # entry point (reads SUPABASE_URL / SUPABASE_ANON_KEY via --dart-define)
│   │   ├── theme.dart         # brand colors & styles
│   │   ├── models.dart
│   │   ├── services/nyota_service.dart
│   │   ├── utils/image_compressor.dart
│   │   └── screens/           # auth, dashboard, entry forms, register, PDF
│   ├── assets/logo.png
│   └── test/widget_test.dart  # financial-parsing unit tests
├── web/                       # Next.js (App Router, TypeScript)
│   ├── app/                   # /login /dashboard /add /register
│   ├── components/Shell.tsx
│   └── lib/supabase.ts        # all Supabase calls + image compression/upload
│   └── lib/pdf.ts             # jsPDF register export
└── supabase/
    └── migrations/
        ├── 0001_schema.sql    # tables, indexes, triggers, dashboard RPC
        ├── 0002_rls.sql       # row level security policies
        └── 0003_storage.sql   # gift-images bucket + storage policies
```

## 1. Set up Supabase

1. Create a project at [supabase.com](https://supabase.com).
2. Open **SQL Editor** and run the three migration files in order:
   `0001_schema.sql` → `0002_rls.sql` → `0003_storage.sql`.
   (Or use the Supabase CLI: `supabase db push` with these files in `supabase/migrations/`.)
3. From **Project Settings → API** copy:
   - `Project URL`  → this is `SUPABASE_URL`
   - `anon / public` key → this is the anon key. **Never use the service-role key in the app or website.**

Note: users sign up through the app; email confirmation can be enabled/disabled under **Authentication → Providers**.

### Database model

- `profiles` — mirrors `auth.users` (auto-created by trigger).
- `events` — one owner has many events.
- `guest_entries` — every contribution row. `category` is `nyota_gifts` or `food_only`. Money is stored as `NUMERIC(12,2)`.
- `gifts` — physical gifts linked to an entry, each with an optional Storage `image_path`.
- `client_id` (uuid, unique) on entries/gifts lets a retried save never create duplicates.
- `get_dashboard_totals(event_id)` — a single SQL RPC that computes every dashboard number server-side (no double counting, no float drift). Editing/deleting rows automatically updates totals because totals are always computed from the table.
- RLS: every table is restricted to `owner_id = auth.uid()`; entries must belong to your event; storage objects are scoped to your own folder (images under `<uid>/…` are publicly readable via the public bucket for thumbnails).

## 2. Website (Next.js)

```bash
cd web
cp .env.example .env.local      # then fill in the two values
npm install
npm run dev                     # http://localhost:3000
```

Environment variables (`web/.env.local`):

```
NEXT_PUBLIC_SUPABASE_URL=https://<project-ref>.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon-public-key>
```

Production build: `npm run build && npm start`.

### Deploy on Vercel (GitHub)

1. Push this repo to GitHub (see commands below).
2. In Vercel, **Import** the repo.
3. Set **Root Directory** to `web` (important — this is a monorepo).
4. Add Environment Variables in Vercel project settings:
   - `NEXT_PUBLIC_SUPABASE_URL`
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
5. Deploy. Vercel will run `npm install` and `npm run build` inside `web/`.

Push to GitHub (replace `<your-github-username>` / repo name as you like):

```bash
git remote add origin https://github.com/<your-github-username>/nyota.git
git branch -M main
git push -u origin main
```

## 3. Mobile app (Flutter)

```bash
cd mobile
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-public-key>
```

Release build:

```bash
flutter build apk \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=...
```

The `--dart-define` values are compiled into the app; use the **anon key only** — RLS on every table + storage bucket policies is what protects the data.

## Design system

Royal Purple `#6C3CE9` · Deep Indigo `#4338CA` · Saffron/Gold `#F59E0B` · Soft Cream `#FFF9EF` · white cards with subtle shadows. The provided Nyota logo is used on the login screen, app bar, top bar and as the favicon/app label.

## Financial correctness (why totals are right)

- All amounts live in Postgres `NUMERIC(12,2)` — never floats.
- Dashboard numbers come from **one SQL RPC** (`get_dashboard_totals`) that runs inside the database; the client never sums money.
- `Total cash = Nyota cash + Food only`, physical gifts are counted, never valued into cash.
- Editing or deleting an entry updates totals automatically (recomputed from rows).
- Duplicate protection: the client generates a UUID per save and uses upsert-with-ignore (`client_id`), plus the Save button disables while in flight.

## Testing

```bash
cd mobile && flutter test     # unit tests for money/category parsing
cd web && npm run build       # type-checks + production build
```
