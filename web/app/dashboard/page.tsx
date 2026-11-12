'use client';

import { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Shell from '@/components/Shell';
import { EventQr } from '@/components/EventQr';
import {
  DashboardTotals,
  NyotaEvent,
  createEvent,
  dashboardTotals,
  eventShareUrl,
  fmtDate,
  joinEventByCode,
  latestEvent,
  listEvents,
  money,
} from '@/lib/supabase';

export default function DashboardPage() {
  const router = useRouter();
  const [event, setEvent] = useState<NyotaEvent | null>(null);
  const [totals, setTotals] = useState<DashboardTotals | null>(null);
  const [loading, setLoading] = useState(true);
  const [showEventModal, setShowEventModal] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const ev = await latestEvent();
      setEvent(ev);
      setTotals(ev ? await dashboardTotals(ev.id) : null);
    } catch {
      /* shown as empty state */
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  return (
    <Shell>
      <div className="container">
        {!loading && !event && (
          <div className="card" style={{ textAlign: 'center', padding: 40 }}>
            <div style={{ fontSize: 48 }}>🎉</div>
            <h2 style={{ margin: '10px 0 6px' }}>Welcome to Nyota</h2>
            <p style={{ color: 'var(--muted)' }}>
              Create your first event to start recording guests, gifts and collections.
            </p>
            <button className="btn" onClick={() => setShowEventModal(true)}>
              + Create Event
            </button>
          </div>
        )}

        {event && (
          <>
            <div className="card" style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 16, flexWrap: 'wrap' }}>
              <div
                style={{
                  width: 44,
                  height: 44,
                  borderRadius: 12,
                  background: 'rgba(108,60,233,0.08)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: 20,
                }}
              >
                🎊
              </div>
              <div style={{ flex: 1, minWidth: 180 }}>
                <div style={{ fontWeight: 800, fontSize: 18 }}>{event.name}</div>
                <div style={{ color: 'var(--muted)', fontSize: 13 }}>{fmtDate(event.event_date)}</div>
              </div>
              <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                <button className="btn secondary small" onClick={() => setShowEventModal(true)}>
                  Switch / New / Join
                </button>
                <button
                  className="btn danger small"
                  onClick={() => router.push('/register?export=1')}
                  title="Export Guest Register PDF"
                >
                  Export PDF
                </button>
              </div>
            </div>

            {event.join_code && <ShareEventCard event={event} />}

            {loading || !totals ? (
              <p style={{ color: 'var(--muted)', textAlign: 'center' }}>Loading totals…</p>
            ) : (
              <div className="stat-grid">
                <StatCard icon="👥" bg="rgba(108,60,233,0.1)" label="Total Guests" value={`${totals.total_guests}`} />
                <StatCard
                  icon="🎁"
                  bg="rgba(245,158,11,0.12)"
                  label="Nyota Cash"
                  value={money(totals.total_nyota_cash)}
                />
                <StatCard icon="🍛" bg="rgba(67,56,202,0.1)" label="Food Only" value={money(totals.total_food_only)} />
                <StatCard
                  icon="💰"
                  bg="rgba(22,163,74,0.1)"
                  label="Total Cash"
                  value={money(totals.total_cash)}
                  emphasized
                />
                <StatCard icon="📦" bg="rgba(108,60,233,0.1)" label="Physical Gifts" value={`${totals.total_gifts}`} />
              </div>
            )}
          </>
        )}
      </div>

      {showEventModal && (
        <EventModal
          onClose={() => setShowEventModal(false)}
          onDone={(ev) => {
            setShowEventModal(false);
            if (ev) {
              setEvent(ev);
              dashboardTotals(ev.id).then(setTotals);
            } else {
              load();
            }
          }}
        />
      )}
    </Shell>
  );
}

function ShareEventCard({ event }: { event: NyotaEvent }) {
  const [copied, setCopied] = useState<string | null>(null);
  const code = event.join_code || '';
  const url = eventShareUrl(code);

  async function copy(text: string, label: string) {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(label);
      setTimeout(() => setCopied(null), 1800);
    } catch {
      setCopied('Copy failed');
      setTimeout(() => setCopied(null), 1800);
    }
  }

  async function share() {
    if (navigator.share) {
      try {
        await navigator.share({ title: `Join ${event.name} on Nyota`, text: `Join event "${event.name}" on Nyota`, url });
        return;
      } catch {
        /* user cancelled or unsupported */
      }
    }
    copy(url, 'Link copied');
  }

  return (
    <div className="card" style={{ marginBottom: 16 }}>
      <h3 style={{ margin: '0 0 6px' }}>Share / Join Event</h3>
      <p style={{ color: 'var(--muted)', margin: '0 0 12px', fontSize: 13.5 }}>
        Kisi ko bhi invite karo — share link, QR code scan, ya event code se join kar sakte hain.
      </p>
      <div style={{ display: 'flex', gap: 16, flexWrap: 'wrap', alignItems: 'center' }}>
        <div style={{ textAlign: 'center' }}>
          <EventQr url={url} size={170} />
          <div style={{ fontSize: 12, color: 'var(--muted)', marginTop: 6 }}>Scan to join</div>
        </div>
        <div style={{ flex: 1, minWidth: 220 }}>
          <div style={{ marginBottom: 10 }}>
            <div style={{ fontSize: 12, color: 'var(--muted)', fontWeight: 700, marginBottom: 4 }}>EVENT CODE</div>
            <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
              <div
                style={{
                  fontSize: 22,
                  fontWeight: 800,
                  letterSpacing: 3,
                  color: 'var(--purple)',
                  background: 'rgba(108,60,233,0.08)',
                  padding: '8px 14px',
                  borderRadius: 12,
                }}
              >
                {code}
              </div>
              <button className="btn secondary small" onClick={() => copy(code, 'Code copied')}>
                Copy Code
              </button>
            </div>
          </div>
          <div>
            <div style={{ fontSize: 12, color: 'var(--muted)', fontWeight: 700, marginBottom: 4 }}>SHARE LINK</div>
            <div style={{ wordBreak: 'break-all', fontSize: 13, marginBottom: 8 }}>{url}</div>
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
              <button className="btn secondary small" onClick={() => copy(url, 'Link copied')}>
                Copy Link
              </button>
              <button className="btn small" onClick={share}>
                Share
              </button>
            </div>
          </div>
          {copied && <div style={{ marginTop: 8, color: 'var(--success)', fontWeight: 700, fontSize: 13 }}>{copied}</div>}
        </div>
      </div>
    </div>
  );
}

function StatCard({
  icon,
  bg,
  label,
  value,
  emphasized,
}: {
  icon: string;
  bg: string;
  label: string;
  value: string;
  emphasized?: boolean;
}) {
  return (
    <div className={`stat-card${emphasized ? ' emphasized' : ''}`}>
      <div className="icon" style={{ background: bg }}>
        {icon}
      </div>
      <div className="value">{value}</div>
      <div className="label">{label}</div>
    </div>
  );
}

function EventModal({
  onClose,
  onDone,
}: {
  onClose: () => void;
  onDone: (ev: NyotaEvent | null) => void;
}) {
  const [mode, setMode] = useState<'choose' | 'create' | 'join'>('choose');
  const [events, setEvents] = useState<NyotaEvent[] | null>(null);
  const [name, setName] = useState('');
  const [date, setDate] = useState('');
  const [joinCode, setJoinCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    listEvents().then(setEvents).catch(() => setEvents([]));
  }, []);

  async function create() {
    if (!name.trim()) {
      setError('Please enter an event name');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const ev = await createEvent(name.trim(), date || null);
      onDone(ev);
    } catch {
      setBusy(false);
      setError('Could not create event. Please try again.');
    }
  }

  async function join() {
    if (!joinCode.trim()) {
      setError('Please enter event code');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const ev = await joinEventByCode(joinCode);
      onDone(ev);
    } catch (e: unknown) {
      setBusy(false);
      const msg = e instanceof Error ? e.message : '';
      setError(msg.includes('Invalid') ? 'Galat code — sahi event code daalo.' : 'Join nahi ho paya. Code check karo.');
    }
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h2>{mode === 'create' ? 'New Event' : mode === 'join' ? 'Join Event' : 'Choose Event'}</h2>

        {mode === 'choose' && (
          <>
            <button className="btn" style={{ width: '100%', marginBottom: 10 }} onClick={() => { setError(null); setMode('join'); }}>
              Join by Code / Link
            </button>
            {events === null ? (
              <p style={{ color: 'var(--muted)' }}>Loading…</p>
            ) : events.length === 0 ? (
              <p style={{ color: 'var(--muted)' }}>No events yet — create or join one!</p>
            ) : (
              events.map((ev) => (
                <div
                  key={ev.id}
                  className="card"
                  style={{ marginBottom: 8, cursor: 'pointer', display: 'flex', justifyContent: 'space-between' }}
                  onClick={() => onDone(ev)}
                >
                  <div>
                    <div style={{ fontWeight: 700 }}>{ev.name}</div>
                    <div style={{ color: 'var(--muted)', fontSize: 13 }}>{fmtDate(ev.event_date)}</div>
                  </div>
                  <div style={{ color: 'var(--purple)', alignSelf: 'center' }}>→</div>
                </div>
              ))
            )}
            <button className="btn secondary" style={{ width: '100%', marginTop: 8 }} onClick={() => { setError(null); setMode('create'); }}>
              + Create New Event
            </button>
          </>
        )}

        {mode === 'join' && (
          <>
            <p style={{ color: 'var(--muted)', fontSize: 13.5 }}>Event ka 8-character code daalo (jo host ne share kiya hai), ya share link open karo.</p>
            <div className="field">
              <label>Event code</label>
              <input
                value={joinCode}
                onChange={(e) => setJoinCode(e.target.value.toUpperCase())}
                placeholder="e.g. A1B2C3D4"
                style={{ textTransform: 'uppercase', letterSpacing: 2, fontWeight: 800 }}
              />
            </div>
            {error && <div className="error-text">{error}</div>}
            <button className="btn" style={{ width: '100%' }} onClick={join} disabled={busy}>
              {busy ? 'Joining…' : 'Join Event'}
            </button>
            <button className="btn secondary" style={{ width: '100%', marginTop: 10 }} onClick={() => { setError(null); setMode('choose'); }}>
              Back
            </button>
          </>
        )}

        {mode === 'create' && (
          <>
            <div className="field">
              <label>Event name *</label>
              <input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Sharma Wedding Reception" />
            </div>
            <div className="field">
              <label>Event date (optional)</label>
              <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
            </div>
            {error && <div className="error-text">{error}</div>}
            <button className="btn" style={{ width: '100%' }} onClick={create} disabled={busy}>
              {busy ? 'Creating…' : 'Create Event'}
            </button>
            <button className="btn secondary" style={{ width: '100%', marginTop: 10 }} onClick={() => { setError(null); setMode('choose'); }}>
              Back
            </button>
          </>
        )}
      </div>
    </div>
  );
}
