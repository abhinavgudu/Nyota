'use client';

import { useRef, useState } from 'react';
import Shell from '@/components/Shell';
import {
  GiftPayload,
  NyotaEvent,
  addGiftsToEntry,
  latestEvent,
  saveFoodOnly,
  saveNyotaEntry,
  uploadGiftImage,
} from '@/lib/supabase';

const QUICK_AMOUNTS = [51, 101, 500, 501, 1001, 1000];

export default function AddEntryPage() {
  return (
    <Shell>
      <div className="container" style={{ maxWidth: 760 }}>
        <AddEntryTabs />
      </div>
    </Shell>
  );
}

function AddEntryTabs() {
  const [tab, setTab] = useState<'nyota' | 'food'>('food');

  return (
    <>
      <div className="tabs">
        <button className={`tab${tab === 'nyota' ? ' active' : ''}`} onClick={() => setTab('nyota')}>
          🎁 Nyota with Gifts
        </button>
        <button className={`tab${tab === 'food' ? ' active' : ''}`} onClick={() => setTab('food')}>
          🍛 Food Only
        </button>
      </div>
      {tab === 'nyota' ? <NyotaForm /> : <FoodOnlyForm />}
    </>
  );
}

// ---------------- Food Only quick entry ----------------

function FoodOnlyForm() {
  const [name, setName] = useState('');
  const [amount, setAmount] = useState('');
  const [extra, setExtra] = useState('');
  const [saving, setSaving] = useState(false);
  const [toast, setToast] = useState<{ msg: string; error?: boolean } | null>(null);
  const [savedCount, setSavedCount] = useState(0);
  const amountRef = useRef<HTMLInputElement>(null);
  const nameRef = useRef<HTMLInputElement>(null);

  const base = parseInt(amount || '0', 10) || 0;
  const additional = parseInt(extra || '0', 10) || 0;
  const total = base + additional;

  function showToast(msg: string, error = false) {
    setToast({ msg, error });
    window.setTimeout(() => setToast(null), 1800);
  }

  async function saveAndNext() {
    if (total <= 0 || saving) return;
    setSaving(true);
    try {
      const event = await latestEvent();
      if (!event) {
        showToast('Create an event first (Dashboard → Create Event)', true);
        return;
      }
      await saveFoodOnly(event.id, total, name);
      setSavedCount((c) => c + 1);
      setName('');
      setAmount('');
      setExtra('');
      // Prepare instantly for the next guest.
      nameRef.current?.focus();
      showToast(`Saved ₹${total} — entry #${savedCount + 1}. Ready for next guest!`);
    } catch {
      showToast('Could not save entry. Check connection and try again.', true);
    } finally {
      setSaving(false);
    }
  }

  return (
    <>
      <div className="card">
        <div className="field">
          <label>Guest name (optional)</label>
          <input
            ref={nameRef}
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Skip if the queue is too fast"
          />
        </div>
        <div className="field">
          <label>Amount ₹ *</label>
          <input
            ref={amountRef}
            type="number"
            inputMode="numeric"
            autoFocus
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="Tap a quick amount or type"
            style={{ fontSize: 22, fontWeight: 800 }}
          />
        </div>

        <div className="quick-amounts">
          {QUICK_AMOUNTS.map((v) => (
            <button
              key={v}
              className={amount === `${v}` ? 'active' : ''}
              onClick={() => setAmount(`${v}`)}
            >
              ₹{v}
            </button>
          ))}
        </div>

        <div className="field" style={{ marginTop: 14 }}>
          <label>Additional amount (optional)</label>
          <input
            type="number"
            inputMode="numeric"
            value={extra}
            onChange={(e) => setExtra(e.target.value)}
            placeholder="e.g. ₹500 + ₹2 → ₹502"
          />
        </div>

        <div className={`total-row${total > 0 ? ' hot' : ''}`}>
          <span style={{ color: 'var(--muted)', fontWeight: 700 }}>Saving</span>
          <span className="amount">₹{total}</span>
        </div>

        <button
          className="btn gold"
          style={{ width: '100%', fontSize: 17 }}
          disabled={total <= 0 || saving}
          onClick={saveAndNext}
        >
          {saving ? 'SAVING…' : 'SAVE & NEXT'}
        </button>
        {savedCount > 0 && (
          <p style={{ textAlign: 'center', color: 'var(--muted)', fontWeight: 600 }}>
            {savedCount} entries saved in this session
          </p>
        )}
      </div>
      {toast && <div className={`toast${toast.error ? ' error' : ''}`}>{toast.msg}</div>}
    </>
  );
}

// ---------------- Nyota with Gifts ----------------

interface GiftDraft {
  name: string;
  description: string;
  file: File | null;
  imagePath: string | null;
  progress: number;
  status: 'idle' | 'compressing' | 'uploading' | 'done' | 'error';
}

function NyotaForm() {
  const [guestName, setGuestName] = useState('');
  const [fatherName, setFatherName] = useState('');
  const [village, setVillage] = useState('');
  const [cash, setCash] = useState('');
  const [gifts, setGifts] = useState<GiftDraft[]>([]);
  const [saving, setSaving] = useState(false);
  const [toast, setToast] = useState<{ msg: string; error?: boolean } | null>(null);

  function showToast(msg: string, error = false) {
    setToast({ msg, error });
    window.setTimeout(() => setToast(null), 2200);
  }

  const cashNum = parseFloat(cash) || 0;
  const canSave = !saving && cashNum > 0 && gifts.every((g) => g.name.trim() !== '');

  function addGift() {
    setGifts([...gifts, { name: '', description: '', file: null, imagePath: null, progress: 0, status: 'idle' }]);
  }

  function updateGift(i: number, patch: Partial<GiftDraft>) {
    setGifts(gifts.map((g, j) => (j === i ? { ...g, ...patch } : g)));
  }

  function removeGift(i: number) {
    setGifts(gifts.filter((_, j) => j !== i));
  }

  async function pickImage(i: number, file: File | null) {
    if (!file) return;
    // Real compression happens inside uploadGiftImage (canvas, before upload);
    // here we just show the preview.
    updateGift(i, { file, status: 'idle' });
  }

  async function save() {
    if (!canSave) return;
    setSaving(true);
    let uploadFailed = false;
    try {
      const event: NyotaEvent | null = await latestEvent();
      if (!event) {
        showToast('Create an event first (Dashboard → Create Event)', true);
        return;
      }

      // Save the cash entry FIRST — money is never lost to image issues.
      const entryId = await saveNyotaEntry(event.id, {
        cashAmount: cashNum,
        guestName,
        fatherName,
        village,
        gifts: [],
      });

      // Then upload gift images and attach gifts.
      const payloads: GiftPayload[] = [];
      for (let idx = 0; idx < gifts.length; idx++) {
        const g = gifts[idx];
        let imagePath = g.imagePath;
        if (g.file) {
          updateGift(idx, { status: 'uploading' });
          try {
            imagePath = await uploadGiftImage(entryId, g.file, (r) => updateGift(idx, { progress: r }));
            updateGift(idx, { status: 'done', imagePath });
          } catch {
            uploadFailed = true;
            updateGift(idx, { status: 'error' });
          }
        }
        payloads.push({ name: g.name.trim(), description: g.description || null, image_path: imagePath });
      }

      if (payloads.length > 0) {
        await addGiftsToEntry(entryId, payloads);
      }

      setGuestName('');
      setFatherName('');
      setVillage('');
      setCash('');
      setGifts([]);
      showToast(uploadFailed ? 'Entry saved, but one gift image failed to upload.' : 'Entry saved!');
    } catch {
      showToast('Could not save entry. Please try again.', true);
    } finally {
      setSaving(false);
    }
  }

  return (
    <>
      <div className="card">
        <div className="field">
          <label>Guest name</label>
          <input value={guestName} onChange={(e) => setGuestName(e.target.value)} />
        </div>
        <div className="field">
          <label>Father&apos;s name</label>
          <input value={fatherName} onChange={(e) => setFatherName(e.target.value)} />
        </div>
        <div className="field">
          <label>Village / City</label>
          <input value={village} onChange={(e) => setVillage(e.target.value)} />
        </div>
        <div className="field">
          <label>Cash / Lifafa amount ₹</label>
          <input
            type="number"
            min="0"
            step="0.01"
            inputMode="decimal"
            value={cash}
            onChange={(e) => setCash(e.target.value)}
            style={{ fontSize: 20, fontWeight: 800 }}
          />
        </div>

        <div style={{ display: 'flex', alignItems: 'center', margin: '18px 0 8px' }}>
          <strong>Gifts</strong>
          <span style={{ flex: 1 }} />
          <button className="btn secondary small" onClick={addGift}>
            + Add gift
          </button>
        </div>

        {gifts.length === 0 && (
          <p style={{ color: 'var(--muted)' }}>No gifts added. Tap &quot;Add gift&quot; for each physical gift (optional).</p>
        )}

        {gifts.map((g, i) => (
          <div key={i} className="card" style={{ marginBottom: 10, boxShadow: 'none', border: '1px solid var(--border)' }}>
            <div style={{ display: 'flex', alignItems: 'center' }}>
              <strong style={{ color: 'var(--purple)' }}>Gift {i + 1}</strong>
              <span style={{ flex: 1 }} />
              <button className="btn small danger" onClick={() => removeGift(i)}>
                Remove
              </button>
            </div>
            <div className="field" style={{ marginTop: 8 }}>
              <label>Gift name *</label>
              <input value={g.name} onChange={(e) => updateGift(i, { name: e.target.value })} placeholder="e.g. Brass Diya Set" />
            </div>
            <div className="field">
              <label>Description (optional)</label>
              <input value={g.description} onChange={(e) => updateGift(i, { description: e.target.value })} placeholder='e.g. Pair of 6" brass diyas' />
            </div>
            <div style={{ display: 'flex', gap: 10, alignItems: 'flex-start' }}>
              {g.file ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={URL.createObjectURL(g.file)}
                  alt="gift preview"
                  style={{ width: 72, height: 72, borderRadius: 10, objectFit: 'cover', border: '1px solid var(--border)' }}
                />
              ) : (
                <div
                  style={{
                    width: 72,
                    height: 72,
                    borderRadius: 10,
                    border: '1px solid var(--border)',
                    background: '#f3f0fa',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                  }}
                >
                  🖼️
                </div>
              )}
              <div style={{ flex: 1 }}>
                <label className="btn secondary small" style={{ cursor: 'pointer' }}>
                  {g.file ? 'Change photo' : 'Add photo'}
                  <input
                    type="file"
                    accept="image/*"
                    hidden
                    onChange={(e) => pickImage(i, e.target.files?.[0] ?? null)}
                  />
                </label>
                {g.status === 'compressing' && <div style={{ color: 'var(--muted)', fontSize: 12.5, marginTop: 6 }}>Compressing image…</div>}
                {g.status === 'uploading' && (
                  <>
                    <div style={{ fontSize: 12.5, fontWeight: 600, marginTop: 6 }}>
                      Uploading… {Math.round(g.progress * 100)}%
                    </div>
                    <div className="progress-bar">
                      <div style={{ width: `${Math.round(g.progress * 100)}%` }} />
                    </div>
                  </>
                )}
                {g.status === 'done' && <div style={{ color: 'var(--success)', fontSize: 12.5, marginTop: 6 }}>✓ Image ready</div>}
                {g.status === 'error' && <div style={{ color: 'var(--danger)', fontSize: 12.5, marginTop: 6 }}>Upload failed — try again</div>}
              </div>
            </div>
          </div>
        ))}

        <button className="btn" style={{ width: '100%', marginTop: 16 }} onClick={save} disabled={!canSave}>
          {saving ? 'Saving…' : 'Save Entry'}
        </button>
      </div>
      {toast && <div className={`toast${toast.error ? ' error' : ''}`}>{toast.msg}</div>}
    </>
  );
}
