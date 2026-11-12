'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { signIn, signUp, supabase, supabaseConfigured } from '@/lib/supabase';

export default function LoginPage() {
  const router = useRouter();
  const [isSignUp, setIsSignUp] = useState(false);
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  useEffect(() => {
    if (!supabaseConfigured) return;
    supabase.auth.getSession().then(({ data }) => {
      if (data.session) router.replace('/dashboard');
    });
  }, [router]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      if (isSignUp) {
        await signUp(email, password, name);
        setNotice('Account created. Please sign in.');
        setIsSignUp(false);
      } else {
        await signIn(email, password);
        router.replace('/dashboard');
      }
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Something went wrong.';
      if (msg.includes('Invalid login')) setError('Wrong email or password.');
      else if (msg.includes('already registered')) setError('This email is already registered. Please sign in.');
      else setError(msg);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="auth-wrap">
      <form className="auth-card" onSubmit={submit}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/logo.png" alt="Nyota logo" />
        <h1>Nyota</h1>
        <div className="sub">Digital Guest &amp; Gift Manager</div>

        {!supabaseConfigured && (
          <p className="error-text">
            Missing Supabase configuration — set NEXT_PUBLIC_SUPABASE_URL and
            NEXT_PUBLIC_SUPABASE_ANON_KEY in web/.env.local and restart.
          </p>
        )}

        {isSignUp && (
          <div className="field">
            <label>Your name</label>
            <input value={name} onChange={(e) => setName(e.target.value)} required placeholder="Your name" />
          </div>
        )}
        <div className="field">
          <label>Email</label>
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            placeholder="you@example.com"
          />
        </div>
        <div className="field">
          <label>Password</label>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            minLength={6}
            placeholder="At least 6 characters"
          />
        </div>

        {error && <div className="error-text">{error}</div>}
        {notice && <div style={{ color: 'var(--success)', fontSize: 13.5, margin: '8px 0' }}>{notice}</div>}

        <button className="btn" style={{ width: '100%' }} disabled={busy || !supabaseConfigured}>
          {busy ? 'Please wait…' : isSignUp ? 'Create Account' : 'Sign In'}
        </button>
        <button
          type="button"
          className="btn secondary"
          style={{ width: '100%', marginTop: 10, background: 'transparent' }}
          onClick={() => setIsSignUp(!isSignUp)}
        >
          {isSignUp ? 'Already have an account? Sign in' : 'New here? Create an account'}
        </button>
      </form>
    </div>
  );
}
