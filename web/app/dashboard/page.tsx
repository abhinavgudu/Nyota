'use client';

import { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Shell from '@/components/Shell';
import {
  DashboardTotals,
  NyotaEvent,
  createEvent,
  dashboardTotals,
  fmtDate,
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
            <div className="card" style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 16 }}>
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
              <div style={{ flex: 1 }}>
                <div style={{ fontWeight: 800, fontSize: 18 }}>{event.name}</div>
                <div style={{ color: 'var(--muted)', fontSize: 13 }}>{fmtDate(event.event_date)}</div>
              </div>
              <button className="btn secondary small" onClick={() => setShowEventModal(true)}>
                Switch / New event
              </button>
              <button
                className="btn danger small"
                onClick={() => router.push('/register?export=1')}
                title="Export Guest Register PDF"
              >
                Export PDF
              </button>
            </div>

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
  const [events, setEvents] = useState<NyotaEvent[] | null>(null);
  const [creating, setCreating] = useState(false);
  const [name, setName] = useState('');
  const [date, setDate] = useState('');
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

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h2>{creating ? 'New Event' : 'Choose Event'}</h2>
        {!creating ? (
          <>
            {events === null ? (
              <p style={{ color: 'var(--muted)' }}>Loading…</p>
            ) : events.length === 0 ? (
              <p style={{ color: 'var(--muted)' }}>No events yet — create your first one!</p>
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
            <button className="btn secondary" style={{ width: '100%', marginTop: 8 }} onClick={() => setCreating(true)}>
              + Create New Event
            </button>
          </>
        ) : (
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
            <button
              className="btn secondary"
              style={{ width: '100%', marginTop: 10 }}
              onClick={() => setCreating(false)}
            >
              Back to events
            </button>
          </>
        )}
      </div>
    </div>
  );
}
