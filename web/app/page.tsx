'use client';

import { useRouter } from 'next/navigation';
import { useEffect } from 'react';
import { supabase, supabaseConfigured } from '@/lib/supabase';

export default function Home() {
  const router = useRouter();

  useEffect(() => {
    if (!supabaseConfigured) return;
    supabase.auth.getSession().then(({ data }) => {
      router.replace(data.session ? '/dashboard' : '/login');
    });
  }, [router]);

  return (
    <div className="container" style={{ textAlign: 'center', marginTop: 80, color: 'var(--muted)' }}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src="/logo_mark.png" alt="Nyota" style={{ width: 120, height: 120, borderRadius: 24 }} />
      <h1 style={{ color: 'var(--ink)' }}>Nyota</h1>
      <p>Loading…</p>
    </div>
  );
}
