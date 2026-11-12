import { createClient, type SupabaseClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabasePublishableKey =
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

export const supabaseConfigured = Boolean(supabaseUrl && supabasePublishableKey);

function makeClient(): SupabaseClient {
  if (supabaseUrl && supabasePublishableKey) {
    return createClient(supabaseUrl, supabasePublishableKey);
  }
  // Stub that fails loudly only when actually used — keeps SSR builds happy
  // when env vars are not set yet.
  return new Proxy({} as SupabaseClient, {
    get() {
      throw new Error(
        'Missing Supabase configuration. Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY in web/.env.local'
      );
    },
  });
}

export const supabase = makeClient();

// ---------- Types ----------

export interface NyotaEvent {
  id: string;
  name: string;
  event_date: string | null;
}

export interface Gift {
  id: string;
  name: string;
  description: string | null;
  image_path: string | null;
}

export type Category = 'nyota_gifts' | 'food_only';

export interface GuestEntry {
  id: string;
  event_id: string;
  category: Category;
  guest_name: string | null;
  father_name: string | null;
  village: string | null;
  cash_amount: number | string;
  created_at: string;
  gifts: Gift[];
}

export interface DashboardTotals {
  total_guests: number;
  total_nyota_cash: number;
  total_food_only: number;
  total_cash: number;
  total_gifts: number;
}

export interface GiftPayload {
  name: string;
  description?: string | null;
  image_path?: string | null;
}

// ---------- Helpers ----------

export function money(value: number | string): string {
  const n = typeof value === 'string' ? parseFloat(value) : value;
  return `₹${(isFinite(n) ? n : 0).toLocaleString('en-IN', { maximumFractionDigits: 2 })}`;
}

export function fmtDate(iso: string | null | undefined): string {
  if (!iso) return '';
  return new Date(iso).toLocaleDateString('en-IN', { day: 'numeric', month: 'long', year: 'numeric' });
}

export function giftImageUrl(path: string): string {
  return supabase.storage.from('gift-images').getPublicUrl(path).data.publicUrl;
}

// ---------- Auth ----------

export async function signIn(email: string, password: string) {
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
}

export async function signUp(email: string, password: string, fullName: string) {
  const { error } = await supabase.auth.signUp({
    email,
    password,
    options: { data: { full_name: fullName } },
  });
  if (error) throw error;
}

export async function signOut() {
  await supabase.auth.signOut();
}

// ---------- Events ----------

export async function latestEvent(): Promise<NyotaEvent | null> {
  const { data, error } = await supabase
    .from('events')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(1);
  if (error) throw error;
  return (data?.[0] as NyotaEvent) ?? null;
}

export async function listEvents(): Promise<NyotaEvent[]> {
  const { data, error } = await supabase
    .from('events')
    .select('*')
    .order('created_at', { ascending: false });
  if (error) throw error;
  return (data ?? []) as NyotaEvent[];
}

export async function createEvent(name: string, eventDate: string | null): Promise<NyotaEvent> {
  const { data, error } = await supabase
    .from('events')
    .insert({ name, event_date: eventDate })
    .select('*')
    .single();
  if (error) throw error;
  return data as NyotaEvent;
}

// ---------- Dashboard ----------

export async function dashboardTotals(eventId: string): Promise<DashboardTotals> {
  const { data, error } = await supabase.rpc('get_dashboard_totals', { p_event_id: eventId });
  if (error) throw error;
  const row = Array.isArray(data) ? data[0] : data;
  return {
    total_guests: Number(row?.total_guests ?? 0),
    total_nyota_cash: Number(row?.total_nyota_cash ?? 0),
    total_food_only: Number(row?.total_food_only ?? 0),
    total_cash: Number(row?.total_cash ?? 0),
    total_gifts: Number(row?.total_gifts ?? 0),
  };
}

// ---------- Entries ----------

export async function fetchEntries(
  eventId: string,
  opts: { search?: string; limit?: number; offset?: number } = {}
): Promise<GuestEntry[]> {
  const { search = '', limit = 50, offset = 0 } = opts;
  let q = supabase
    .from('guest_entries')
    .select('*, gifts(*)')
    .eq('event_id', eventId)
    .order('created_at', { ascending: false })
    .order('id', { ascending: false })
    .range(offset, offset + limit - 1);
  if (search.trim()) {
    const s = search.trim();
    q = q.or(`guest_name.ilike.%${s}%,father_name.ilike.%${s}%,village.ilike.%${s}%`);
  }
  const { data, error } = await q;
  if (error) throw error;
  return (data ?? []) as unknown as GuestEntry[];
}

export async function saveFoodOnly(
  eventId: string,
  amount: number,
  guestName?: string
): Promise<string> {
  const clientId = crypto.randomUUID();
  const { data, error } = await supabase
    .from('guest_entries')
    .upsert(
      {
        client_id: clientId,
        event_id: eventId,
        category: 'food_only',
        guest_name: guestName?.trim() ? guestName.trim() : null,
        cash_amount: amount,
      },
      { onConflict: 'client_id', ignoreDuplicates: true }
    )
    .select('id')
    .single();
  if (error) throw error;
  return data.id as string;
}

export async function saveNyotaEntry(
  eventId: string,
  input: {
    cashAmount: number;
    guestName?: string;
    fatherName?: string;
    village?: string;
    gifts: GiftPayload[];
  }
): Promise<string> {
  const clientId = crypto.randomUUID();
  const { data, error } = await supabase
    .from('guest_entries')
    .upsert(
      {
        client_id: clientId,
        event_id: eventId,
        category: 'nyota_gifts',
        guest_name: input.guestName?.trim() ? input.guestName.trim() : null,
        father_name: input.fatherName?.trim() ? input.fatherName.trim() : null,
        village: input.village?.trim() ? input.village.trim() : null,
        cash_amount: input.cashAmount,
      },
      { onConflict: 'client_id', ignoreDuplicates: true }
    )
    .select('id')
    .single();
  if (error) throw error;
  const entryId = data.id as string;
  if (input.gifts.length > 0) {
    await addGiftsToEntry(entryId, input.gifts);
  }
  return entryId;
}

export async function addGiftsToEntry(entryId: string, gifts: GiftPayload[]) {
  const { error } = await supabase.from('gifts').insert(
    gifts.map((g) => ({
      entry_id: entryId,
      name: g.name,
      description: g.description ?? null,
      image_path: g.image_path ?? null,
    }))
  );
  if (error) throw error;
}

export async function updateEntry(
  entry: GuestEntry,
  input: {
    cashAmount: number;
    guestName?: string;
    fatherName?: string;
    village?: string;
    gifts: GiftPayload[];
  }
) {
  const { error } = await supabase
    .from('guest_entries')
    .update({
      guest_name: input.guestName?.trim() ? input.guestName.trim() : null,
      father_name: input.fatherName?.trim() ? input.fatherName.trim() : null,
      village: input.village?.trim() ? input.village.trim() : null,
      cash_amount: input.cashAmount,
    })
    .eq('id', entry.id);
  if (error) throw error;

  await supabase.from('gifts').delete().eq('entry_id', entry.id);
  if (input.gifts.length > 0) {
    await addGiftsToEntry(entry.id, input.gifts);
  }
}

export async function deleteEntry(entryId: string) {
  const { error } = await supabase.from('guest_entries').delete().eq('id', entryId);
  if (error) throw error;
}

// ---------- Storage ----------

export async function uploadGiftImage(entryId: string, file: File, onProgress?: (r: number) => void): Promise<string> {
  const { data: userData } = await supabase.auth.getUser();
  const uid = userData.user?.id ?? 'anon';
  const path = `${uid}/${entryId}/${crypto.randomUUID()}.jpg`;

  // Downscale/compress client-side via canvas before upload.
  const bytes = await compressImage(file);

  // XHR upload so we can report real progress.
  const token = (await supabase.auth.getSession()).data.session?.access_token ?? '';
  return new Promise<string>((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('POST', `${supabaseUrl}/storage/v1/gift-images/object/${path}`);
    xhr.setRequestHeader('authorization', `Bearer ${token}`);
    xhr.setRequestHeader('content-type', 'image/jpeg');
    xhr.setRequestHeader('cache-control', '3600');
    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable && onProgress) onProgress(e.loaded / e.total);
    };
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) resolve(path);
      else reject(new Error(`Upload failed (${xhr.status})`));
    };
    xhr.onerror = () => reject(new Error('Upload failed'));
    xhr.send(bytes);
  });
}

export async function deleteGiftImage(path: string) {
  try {
    await supabase.storage.from('gift-images').remove([path]);
  } catch {
    // best effort
  }
}

async function compressImage(file: File, maxEdge = 1024, quality = 0.7): Promise<Blob> {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, maxEdge / Math.max(bitmap.width, bitmap.height));
  const w = Math.round(bitmap.width * scale);
  const h = Math.round(bitmap.height * scale);
  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  canvas.getContext('2d')!.drawImage(bitmap, 0, 0, w, h);
  const blob = await new Promise<Blob | null>((resolve) =>
    canvas.toBlob(resolve, 'image/jpeg', quality)
  );
  bitmap.close();
  if (!blob) return file; // fall back to original only if encoding fails
  return blob.size < file.size ? blob : file;
}
