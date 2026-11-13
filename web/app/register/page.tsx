'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import Shell from '@/components/Shell';
import { VoiceMic } from '@/components/VoiceMic';
import { confirmSave } from '@/lib/sound';
import { exportRegisterPdf } from '@/lib/pdf';
import {
  Category,
  DashboardTotals,
  GuestEntry,
  NyotaEvent,
  dashboardTotals,
  deleteEntry,
  fetchEntries,
  fmtDate,
  giftImageUrl,
  latestEvent,
  money,
  updateEntry,
  uploadGiftImage,
} from '@/lib/supabase';

const PAGE_SIZE = 50;

export default function RegisterPage() {
  const [event, setEvent] = useState<NyotaEvent | null>(null);
  const [entries, setEntries] = useState<GuestEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [hasMore, setHasMore] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<GuestEntry | null>(null);
  const [toast, setToast] = useState<{ msg: string; error?: boolean } | null>(null);
  const debounce = useRef<ReturnType<typeof setTimeout> | null>(null);

  const showToast = (msg: string, error = false) => {
    setToast({ msg, error });
    window.setTimeout(() => setToast(null), 2200);
  };

  const load = useCallback(
    async (searchTerm: string, silent = false) => {
      if (!silent) setLoading(true);
      try {
        const ev = await latestEvent();
        setEvent(ev);
        if (!ev) {
          setEntries([]);
          setHasMore(false);
          return;
        }
        const rows = await fetchEntries(ev.id, { search: searchTerm, limit: PAGE_SIZE, offset: 0 });
        setEntries(rows);
        setHasMore(rows.length >= PAGE_SIZE);
      } catch {
        if (!silent) showToast('Could not load entries.', true);
      } finally {
        if (!silent) setLoading(false);
      }
    },
    []
  );

  useEffect(() => {
    load('');
    // Live refresh every 2 seconds (paused while a modal is open so an open
    // edit form is never overwritten).
    const id = setInterval(() => {
      if (!selected) load(search, true);
    }, 2000);
    return () => clearInterval(id);
  }, [load, search, selected]);

  function onSearch(v: string) {
    setSearch(v);
    if (debounce.current) clearTimeout(debounce.current);
    debounce.current = setTimeout(() => load(v), 350);
  }

  async function loadMore() {
    if (loadingMore || !hasMore || !event) return;
    setLoadingMore(true);
    try {
      const more = await fetchEntries(event.id, { search, limit: PAGE_SIZE, offset: entries.length });
      setEntries([...entries, ...more]);
      setHasMore(more.length >= PAGE_SIZE);
    } catch {
      showToast('Could not load more entries.', true);
    } finally {
      setLoadingMore(false);
    }
  }

  async function exportPdf() {
    if (!event) return;
    try {
      showToast('Preparing PDF…');
      const totals = await dashboardTotals(event.id);
      const all: GuestEntry[] = [];
      let offset = 0;
      while (true) {
        const page = await fetchEntries(event.id, { limit: 200, offset });
        all.push(...page);
        if (page.length < 200) break;
        offset += 200;
      }
      await exportRegisterPdf(event, totals, all, (status) => showToast(status));
      showToast('PDF downloaded!');
    } catch {
      showToast('Could not generate PDF.', true);
    }
  }

  return (
    <Shell>
      <div className="container">
        <div style={{ display: 'flex', gap: 10, marginBottom: 12, flexWrap: 'wrap', alignItems: 'center' }}>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center', flex: 1, minWidth: 220 }}>
            <input
              className="search-bar"
              style={{ flex: 1, marginBottom: 0 }}
              placeholder="Search name, father or village… (or speak)"
              value={search}
              onChange={(e) => onSearch(e.target.value)}
            />
            <VoiceMic onResult={(t) => onSearch(t)} />
          </div>
          <button className="btn danger" onClick={exportPdf} disabled={!event}>
            Export PDF
          </button>
          <span
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: 6,
              fontSize: 12,
              fontWeight: 700,
              color: 'var(--muted)',
            }}
          >
            <span
              style={{
                width: 8,
                height: 8,
                borderRadius: '50%',
                background: 'var(--success)',
                display: 'inline-block',
              }}
            />
            Live • auto-refresh 2s
          </span>
        </div>

        {loading ? (
          <p style={{ color: 'var(--muted)', textAlign: 'center' }}>Loading entries…</p>
        ) : entries.length === 0 ? (
          <div className="card" style={{ textAlign: 'center', padding: 32 }}>
            <div style={{ fontSize: 40 }}>👥</div>
            <p style={{ color: 'var(--muted)' }}>
              {search ? `No guests match "${search}".` : 'No entries yet. Add your first guest from the Add Entry page.'}
            </p>
          </div>
        ) : (
          entries.map((e) => <EntryRow key={e.id} entry={e} onOpen={() => setSelected(e)} />)
        )}

        {hasMore && (
          <div style={{ textAlign: 'center', marginTop: 12 }}>
            <button className="btn secondary" onClick={loadMore} disabled={loadingMore}>
              {loadingMore ? 'Loading…' : 'Load more'}
            </button>
          </div>
        )}
      </div>

      {selected && (
        <EntryModal
          entry={selected}
          onClose={() => setSelected(null)}
          onChanged={() => {
            setSelected(null);
            load(search);
          }}
          showToast={showToast}
        />
      )}
      {toast && <div className={`toast${toast.error ? ' error' : ''}`}>{toast.msg}</div>}
    </Shell>
  );
}

function EntryRow({ entry, onOpen }: { entry: GuestEntry; onOpen: () => void }) {
  const isNyota = entry.category === 'nyota_gifts';
  const thumbs = (entry.gifts ?? []).filter((g) => g.image_path).slice(0, 4);
  return (
    <div className="entry-card" onClick={onOpen} role="button">
      <div style={{ display: 'flex', gap: 10, alignItems: 'center', flexWrap: 'wrap' }}>
        <span className="name">{entry.guest_name || 'Guest'}</span>
        <span className={`chip ${isNyota ? 'nyota' : 'food'}`}>{isNyota ? 'Nyota with Gifts' : 'Food Only'}</span>
      </div>
      {entry.father_name && <div className="meta">S/o {entry.father_name}</div>}
      {entry.village && <div className="meta">📍 {entry.village}</div>}
      <div className="row2">
        <span className="cash">{money(entry.cash_amount)}</span>
        {entry.gifts && entry.gifts.length > 0 && (
          <span style={{ color: 'var(--muted)', fontWeight: 600 }}>
            🎁 {entry.gifts.length} gift{entry.gifts.length > 1 ? 's' : ''}
          </span>
        )}
        <span className="thumbs">
          {thumbs.map((g) => (
            // eslint-disable-next-line @next/next/no-img-element
            <img key={g.id} src={giftImageUrl(g.image_path!)} alt={g.name} />
          ))}
        </span>
      </div>
    </div>
  );
}

// ---------------- Detail / Edit modal ----------------

interface GiftDraft {
  name: string;
  description: string;
  imagePath: string | null;
  file: File | null;
  progress: number;
  status: 'idle' | 'uploading' | 'done' | 'error';
}

function EntryModal({
  entry,
  onClose,
  onChanged,
  showToast,
}: {
  entry: GuestEntry;
  onClose: () => void;
  onChanged: () => void;
  showToast: (msg: string, error?: boolean) => void;
}) {
  const [mode, setMode] = useState<'view' | 'edit'>('view');
  const [guestName, setGuestName] = useState(entry.guest_name ?? '');
  const [fatherName, setFatherName] = useState(entry.father_name ?? '');
  const [village, setVillage] = useState(entry.village ?? '');
  const [cash, setCash] = useState(String(Number(entry.cash_amount)));
  const [gifts, setGifts] = useState<GiftDraft[]>(
    (entry.gifts ?? []).map((g) => ({
      name: g.name,
      description: g.description ?? '',
      imagePath: g.image_path,
      file: null,
      progress: 0,
      status: 'idle' as const,
    }))
  );
  const [busy, setBusy] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);

  async function save() {
    const cashNum = parseFloat(cash) || 0;
    if (cashNum <= 0) {
      showToast('Amount must be more than zero', true);
      return;
    }
    if (gifts.some((g) => !g.name.trim())) {
      showToast('Every gift needs a name', true);
      return;
    }
    setBusy(true);
    try {
      // Upload new images first.
      const payloads = [];
      for (let i = 0; i < gifts.length; i++) {
        const g = gifts[i];
        let imagePath = g.imagePath;
        if (g.file) {
          setGifts(gifts.map((x, j) => (j === i ? { ...x, status: 'uploading' } : x)));
          try {
            imagePath = await uploadGiftImage(entry.id, g.file, (r) =>
              setGifts(gifts.map((x, j) => (j === i ? { ...x, progress: r } : x)))
            );
          } catch {
            showToast('One image failed to upload.', true);
          }
        }
        payloads.push({ name: g.name.trim(), description: g.description || null, image_path: imagePath });
      }

      await updateEntry(entry, {
        cashAmount: cashNum,
        guestName,
        fatherName,
        village,
        gifts: payloads,
      });
      confirmSave();
      showToast('Entry updated.');
      onChanged();
    } catch {
      showToast('Could not update entry.', true);
    } finally {
      setBusy(false);
    }
  }

  async function remove() {
    setBusy(true);
    try {
      await deleteEntry(entry.id);
      confirmSave();
      showToast('Entry deleted.');
      onChanged();
    } catch {
      showToast('Could not delete entry.', true);
      setBusy(false);
    }
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        {mode === 'view' ? (
          <>
            <h2>{entry.guest_name || 'Guest'}</h2>
            <div style={{ marginBottom: 12 }}>
              <span className={`chip ${entry.category === 'nyota_gifts' ? 'nyota' : 'food'}`}>
                {entry.category === 'nyota_gifts' ? 'Nyota with Gifts' : 'Food Only'}
              </span>
            </div>
            <ViewRow label="Father's name" value={entry.father_name} />
            <ViewRow label="Village / City" value={entry.village} />
            <ViewRow label="Cash / Lifafa" value={money(entry.cash_amount)} strong />
            <ViewRow label="Recorded at" value={fmtDate(entry.created_at)} />
            <h3 style={{ margin: '16px 0 8px', fontSize: 15 }}>Gifts ({(entry.gifts ?? []).length})</h3>
            {(entry.gifts ?? []).length === 0 ? (
              <p style={{ color: 'var(--muted)' }}>No gifts recorded for this entry.</p>
            ) : (
              (entry.gifts ?? []).map((g) => (
                <div key={g.id} className="card" style={{ marginBottom: 8, boxShadow: 'none', border: '1px solid var(--border)', display: 'flex', gap: 12, alignItems: 'center' }}>
                  {g.image_path ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={giftImageUrl(g.image_path)} alt={g.name} style={{ width: 64, height: 64, borderRadius: 10, objectFit: 'cover' }} />
                  ) : (
                    <div style={{ width: 64, height: 64, borderRadius: 10, background: '#f3f0fa', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                      🎁
                    </div>
                  )}
                  <div>
                    <div style={{ fontWeight: 800 }}>{g.name}</div>
                    {g.description && <div style={{ color: 'var(--muted)', fontSize: 13 }}>{g.description}</div>}
                  </div>
                </div>
              ))
            )}
            <div className="actions">
              <button className="btn secondary" onClick={() => setMode('edit')}>
                ✏️ Edit
              </button>
              <button className="btn danger" onClick={() => setConfirmDelete(true)} disabled={busy}>
                🗑 Delete
              </button>
              <button className="btn secondary" style={{ background: '#fff' }} onClick={onClose}>
                Close
              </button>
            </div>
            {confirmDelete && (
              <div className="modal-backdrop" style={{ zIndex: 60 }}>
                <div className="modal" onClick={(e) => e.stopPropagation()}>
                  <h2>Delete this entry?</h2>
                  <p style={{ color: 'var(--muted)' }}>
                    This will permanently remove the guest entry and its gifts. Totals will update.
                  </p>
                  <div className="actions">
                    <button className="btn secondary" onClick={() => setConfirmDelete(false)}>
                      Cancel
                    </button>
                    <button className="btn danger" onClick={remove} disabled={busy}>
                      {busy ? 'Deleting…' : 'Delete'}
                    </button>
                  </div>
                </div>
              </div>
            )}
          </>
        ) : (
          <>
            <h2>Edit Entry</h2>
            <div className="field">
              <label>Guest name</label>
              <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                <input value={guestName} onChange={(e) => setGuestName(e.target.value)} style={{ flex: 1 }} />
                <VoiceMic onResult={(t) => setGuestName((p) => (p ? p + ' ' + t : t))} />
              </div>
            </div>
            <div className="field">
              <label>Father&apos;s name</label>
              <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                <input value={fatherName} onChange={(e) => setFatherName(e.target.value)} style={{ flex: 1 }} />
                <VoiceMic onResult={(t) => setFatherName((p) => (p ? p + ' ' + t : t))} />
              </div>
            </div>
            <div className="field">
              <label>Village / City</label>
              <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                <input value={village} onChange={(e) => setVillage(e.target.value)} style={{ flex: 1 }} />
                <VoiceMic onResult={(t) => setVillage((p) => (p ? p + ' ' + t : t))} />
              </div>
            </div>
            <div className="field">
              <label>Cash / Lifafa amount ₹</label>
              <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                <input type="number" min="0" step="0.01" value={cash} onChange={(e) => setCash(e.target.value)} style={{ flex: 1 }} />
                <VoiceMic numeric onResult={(t) => setCash(t.replace(/[^0-9.]/g, ''))} />
              </div>
            </div>
            <h3 style={{ fontSize: 15, margin: '12px 0 8px' }}>Gifts</h3>
            {gifts.map((g, i) => (
              <div key={i} className="card" style={{ boxShadow: 'none', border: '1px solid var(--border)', marginBottom: 8 }}>
                <div className="field" style={{ marginBottom: 8 }}>
                  <label>Gift name *</label>
                  <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                    <input value={g.name} onChange={(e) => setGifts(gifts.map((x, j) => (j === i ? { ...x, name: e.target.value } : x)))} style={{ flex: 1 }} />
                    <VoiceMic onResult={(t) => setGifts(gifts.map((x, j) => (j === i ? { ...x, name: x.name ? x.name + ' ' + t : t } : x)))} />
                  </div>
                </div>
                <div className="field" style={{ marginBottom: 8 }}>
                  <label>Description (optional)</label>
                  <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                    <input value={g.description} onChange={(e) => setGifts(gifts.map((x, j) => (j === i ? { ...x, description: e.target.value } : x)))} style={{ flex: 1 }} />
                    <VoiceMic onResult={(t) => setGifts(gifts.map((x, j) => (j === i ? { ...x, description: x.description ? x.description + ' ' + t : t } : x)))} />
                  </div>
                </div>
                <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
                  {g.file ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={URL.createObjectURL(g.file)} alt="preview" style={{ width: 52, height: 52, borderRadius: 8, objectFit: 'cover' }} />
                  ) : g.imagePath ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={giftImageUrl(g.imagePath)} alt="current" style={{ width: 52, height: 52, borderRadius: 8, objectFit: 'cover' }} />
                  ) : (
                    <div style={{ width: 52, height: 52, borderRadius: 8, background: '#f3f0fa', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>🖼️</div>
                  )}
                  <label className="btn secondary small" style={{ cursor: 'pointer' }}>
                    Change photo
                    <input
                      type="file"
                      accept="image/*"
                      hidden
                      onChange={(e) =>
                        setGifts(gifts.map((x, j) => (j === i ? { ...x, file: e.target.files?.[0] ?? null } : x)))
                      }
                    />
                  </label>
                  <span style={{ flex: 1 }} />
                  <button
                    className="btn small danger"
                    onClick={() => setGifts(gifts.filter((_, j) => j !== i))}
                  >
                    Remove
                  </button>
                </div>
                {g.status === 'uploading' && (
                  <div className="progress-bar">
                    <div style={{ width: `${Math.round(g.progress * 100)}%` }} />
                  </div>
                )}
              </div>
            ))}
            <button
              className="btn secondary small"
              onClick={() =>
                setGifts([...gifts, { name: '', description: '', imagePath: null, file: null, progress: 0, status: 'idle' }])
              }
            >
              + Add gift
            </button>
            <div className="actions">
              <button className="btn" onClick={save} disabled={busy}>
                {busy ? 'Saving…' : 'Save Changes'}
              </button>
              <button className="btn secondary" onClick={() => setMode('view')} disabled={busy}>
                Cancel
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

function ViewRow({ label, value, strong }: { label: string; value?: string | null; strong?: boolean }) {
  return (
    <div style={{ display: 'flex', gap: 10, padding: '5px 0' }}>
      <div style={{ width: 110, color: 'var(--muted)', fontWeight: 600, fontSize: 13.5 }}>{label}</div>
      <div style={{ fontWeight: strong ? 800 : 600 }}>{value || '—'}</div>
    </div>
  );
}
