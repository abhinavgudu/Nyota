'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { signOut, supabase, supabaseConfigured } from '@/lib/supabase';

export default function Shell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const [checked, setChecked] = useState(false);

  useEffect(() => {
    if (!supabaseConfigured) return;
    supabase.auth.getSession().then(({ data }) => {
      if (!data.session) router.replace('/login');
      else setChecked(true);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_e, session) => {
      if (!session) router.replace('/login');
    });
    return () => sub.subscription.unsubscribe();
  }, [router]);

  if (!supabaseConfigured) {
    return (
      <div className="container">
        <div className="card" style={{ marginTop: 40 }}>
          <h2>Missing Supabase configuration</h2>
          <p>
            Create <code>web/.env.local</code> with:
            <br />
            <code>NEXT_PUBLIC_SUPABASE_URL=&lt;your-project-url&gt;</code>
            <br />
            <code>NEXT_PUBLIC_SUPABASE_ANON_KEY=&lt;your-anon-key&gt;</code>
          </p>
          <p>Then restart the dev server.</p>
        </div>
      </div>
    );
  }

  if (!checked) {
    return (
      <div className="container" style={{ textAlign: 'center', marginTop: 60, color: 'var(--muted)' }}>
        Loading…
      </div>
    );
  }

  const nav = [
    { href: '/dashboard', label: 'Dashboard' },
    { href: '/add', label: 'Add Entry' },
    { href: '/register', label: 'Register' },
  ];

  return (
    <>
      <header className="topbar">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/logo_mark.png" alt="Nyota logo" />
        <span className="brand">Nyota</span>
        <span className="spacer" />
        <nav style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
          {nav.map((n) => (
            <Link
              key={n.href}
              href={n.href}
              style={{
                color: '#fff',
                fontWeight: pathname === n.href ? 900 : 500,
                padding: '8px 12px',
                borderRadius: 10,
                background: pathname === n.href ? 'rgba(255,255,255,0.2)' : 'transparent',
              }}
            >
              {n.label}
            </Link>
          ))}
        </nav>
        <button
          onClick={async () => {
            await signOut();
            router.replace('/login');
          }}
        >
          Sign out
        </button>
      </header>
      {children}
    </>
  );
}
