'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { joinEventByCode, supabase, supabaseConfigured } from '@/lib/supabase';

export default function JoinPage() {
  const router = useRouter();
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!supabaseConfigured) return;
    supabase.auth.getSession().then(({ data }) => {
      if (!data.session) router.replace('/login?next=/join');
    });
  }, [router]);

  async function join() {
    if (!code.trim()) { setError('Event code daalo'); return; }
    setBusy(true); setError(null); setMsg(null);
    try {
      const ev = await joinEventByCode(code);
      setMsg(`Joined "${ev.name}"!`);
      setTimeout(() => router.replace('/dashboard'), 800);
    } catch (e: any) {
      setError(e?.message?.includes('Invalid') ? 'Galat code — sahi event code daalo.' : (e?.message || 'Join nahi ho paya. Dobara try karo.'));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="auth-wrap">
      <div className="auth-card" style={{ maxWidth: 440 }}>
        <h1 style={{ marginBottom: 4 }}>Join Event</h1>
        <div className="sub">Event ka code ya share link se join karo</div>

        {!supabaseConfigured && <p className="error-text">Supabase configuration missing.</p>}

        <div className="field">
          <label>Event code</label>
          <input
            value={code}
            onChange={(e) => setCode(e.target.value.toUpperCase())}
            placeholder="e.g. A1B2C3D4"
            style={{ textTransform: 'uppercase', letterSpacing: 2, fontWeight: 800, fontSize: 18 }}
          />
        </div>
        {error && <div className="error-text">{error}</div>}
        {msg && <div style={{ color: 'var(--success)', fontWeight: 700, marginBottom: 10 }}>{msg}</div>}
        <button className="btn" style={{ width: '100%' }} onClick={join} disabled={busy || !supabaseConfigured}>
          {busy ? 'Joining…' : 'Join Event'}
        </button>
        <button className="btn secondary" style={{ width: '100%', marginTop: 10 }} onClick={() => router.push('/dashboard')}>
          Back to Dashboard
        </button>
      </div>
    </div>
  );
}
