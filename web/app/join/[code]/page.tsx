'use client';

import { useParams, useRouter } from 'next/navigation';
import { Suspense, useEffect, useState } from 'react';
import { joinEventByCode, supabase, supabaseConfigured } from '@/lib/supabase';

function JoinByCodeInner() {
  const params = useParams<{ code: string }>();
  const router = useRouter();
  const code = (params?.code || '').toString();
  const [status, setStatus] = useState<'checking' | 'joining' | 'ok' | 'need-auth' | 'error'>('checking');
  const [error, setError] = useState<string | null>(null);
  const [eventName, setEventName] = useState<string | null>(null);

  useEffect(() => {
    if (!supabaseConfigured || !code) return;
    let cancelled = false;
    (async () => {
      const { data } = await supabase.auth.getSession();
      if (cancelled) return;
      if (!data.session) {
        setStatus('need-auth');
        router.replace(`/login?next=/join/${encodeURIComponent(code)}`);
        return;
      }
      setStatus('joining');
      try {
        const ev = await joinEventByCode(code);
        if (cancelled) return;
        setEventName(ev.name);
        setStatus('ok');
        setTimeout(() => router.replace('/dashboard'), 1200);
      } catch (e: any) {
        if (cancelled) return;
        setError(e?.message?.includes('Invalid') ? 'Ye event code galat hai ya expire ho gaya hai.' : (e?.message || 'Join nahi ho paya.'));
        setStatus('error');
      }
    })();
    return () => { cancelled = true; };
  }, [code, router]);

  return (
    <div className="auth-wrap">
      <div className="auth-card" style={{ maxWidth: 440, textAlign: 'center' }}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/logo_mark.png" alt="Nyota" style={{ width: 90, height: 90, borderRadius: 22, margin: '0 auto 10px' }} />
        <h1 style={{ marginBottom: 6 }}>Join Event</h1>
        {status === 'checking' && <p style={{ color: 'var(--muted)' }}>Checking…</p>}
        {status === 'need-auth' && <p style={{ color: 'var(--muted)' }}>Login required — redirecting…</p>}
        {status === 'joining' && <p style={{ color: 'var(--muted)' }}>Joining event <b>{code}</b>…</p>}
        {status === 'ok' && <p style={{ color: 'var(--success)', fontWeight: 700 }}>Joined &quot;{eventName}&quot;! Opening dashboard…</p>}
        {status === 'error' && (
          <>
            <p className="error-text" style={{ marginBottom: 14 }}>{error}</p>
            <button className="btn" style={{ width: '100%' }} onClick={() => router.push('/join')}>Enter code manually</button>
            <button className="btn secondary" style={{ width: '100%', marginTop: 10 }} onClick={() => router.push('/dashboard')}>Go to Dashboard</button>
          </>
        )}
        {!code && <p className="error-text">No event code in link.</p>}
      </div>
    </div>
  );
}

export default function JoinByCodePage() {
  return (
    <Suspense fallback={<div className="auth-wrap"><div className="auth-card">Loading…</div></div>}>
      <JoinByCodeInner />
    </Suspense>
  );
}
