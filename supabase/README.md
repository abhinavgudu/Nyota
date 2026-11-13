# Supabase setup — ek hi file

## Sirf ye karo (ek baar)

Supabase → **SQL Editor** → New query → `FIX_ALL.sql` ka poora content paste karo → **Run**.

Bas. Iske baad app me event create, entry save, gift image upload, totals, PDF aur
event join (code / QR / share link) — sab kaam karega.

`FIX_ALL.sql` apne aap me poora schema, functions, triggers, RLS policies aur
storage bucket set karta hai. Ye **baar-baar run karne ke liye safe** hai aur
koi purana/adhura state chhodta nahi.

Run karne ke baad SQL Editor me ek notice aayega:

- `SELF TEST PASSED ...` → sab theek hai ✅
- `SELF TEST FAILED ...` → us message ka screenshot bhej do

## `migrations/` folder kya hai?

Woh development history hai (schema → RLS → storage → event sharing → fixes).
Ab aapko inhe alag-alag run karne ki **zaroorat nahi** — `FIX_ALL.sql` in sab
ko ek me merge kar chuka hai. Sirf tab chahiye jab aap koi specific change
test karna chahein.

| File | Kya karta hai |
|---|---|
| `0001_schema.sql` | tables, indexes, triggers, dashboard RPC |
| `0002_rls.sql` | original RLS policies |
| `0003_storage.sql` | `gift-images` bucket + storage policies |
| `0004_event_sharing.sql` | join code, members, collaborative access |
| `0005_fix_policy_recursion.sql` | `42P17 infinite recursion` fix |
| `0006_repair_event_join_code.sql` | join-code machinery repair |
| `0007_rebuild_policies.sql` | policy diagnostic + rebuild |
| **`FIX_ALL.sql`** | **sab ka final, safe, self-testing version — yahi chalao** |
