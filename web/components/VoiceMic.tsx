'use client';

import { useEffect, useRef, useState } from 'react';

type Props = {
  onResult: (text: string) => void;
  numeric?: boolean;
  title?: string;
  size?: number;
};

export function VoiceMic({ onResult, numeric, title, size = 38 }: Props) {
  const [listening, setListening] = useState(false);
  const [supported, setSupported] = useState(true);
  const recRef = useRef<any>(null);

  useEffect(() => {
    const SR = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
    if (!SR) setSupported(false);
  }, []);

  function toggle() {
    if (listening) {
      try { recRef.current?.stop(); } catch {}
      setListening(false);
      return;
    }
    const SR = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
    if (!SR) {
      alert('Voice typing not supported in this browser. Try Chrome/Edge.');
      return;
    }
    const rec = new SR();
    rec.lang = 'en-IN';
    rec.interimResults = false;
    rec.maxAlternatives = 1;
    rec.continuous = false;
    rec.onresult = (e: any) => {
      const raw = e.results?.[0]?.[0]?.transcript || '';
      let out = raw.trim();
      if (numeric) out = parseAmount(out);
      else out = titleCase(out);
      if (out) onResult(out);
    };
    rec.onerror = () => setListening(false);
    rec.onend = () => setListening(false);
    recRef.current = rec;
    setListening(true);
    try {
      rec.start();
    } catch {
      setListening(false);
    }
  }

  if (!supported) return null;

  return (
    <button
      type="button"
      onClick={toggle}
      title={listening ? 'Stop voice input' : (title || 'Voice typing — tap and speak')}
      style={{
        width: size,
        height: size,
        borderRadius: '50%',
        border: 'none',
        cursor: 'pointer',
        background: listening ? 'var(--danger)' : 'var(--purple)',
        color: '#fff',
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        fontSize: size * 0.5,
        boxShadow: listening
          ? '0 0 0 6px rgba(220,38,38,0.18)'
          : '0 2px 8px rgba(108,60,233,0.3)',
        flexShrink: 0,
      }}
    >
      {listening ? '⏹' : '🎤'}
    </button>
  );
}

function parseAmount(raw: string): string {
  const t = raw.toLowerCase().trim();
  const digits = t.replace(/,/g, '').match(/[\d]+(?:\.\d+)?/g);
  if (digits && digits.length) {
    // pick longest
    return digits.reduce((a, b) => (a.length >= b.length ? a : b));
  }
  const n = wordsToNumber(t);
  return n != null ? String(n) : t.replace(/[^0-9.]/g, '');
}

function titleCase(s: string): string {
  return s
    .split(/\s+/)
    .map((w) => (w ? w[0].toUpperCase() + w.slice(1).toLowerCase() : w))
    .join(' ');
}

function wordsToNumber(t: string): number | null {
  const small: Record<string, number> = {
    zero: 0, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9,
    ten: 10, eleven: 11, twelve: 12, thirteen: 13, fourteen: 14, fifteen: 15, sixteen: 16,
    seventeen: 17, eighteen: 18, nineteen: 19, twenty: 20, thirty: 30, forty: 40, fourty: 40,
    fifty: 50, sixty: 60, seventy: 70, eighty: 80, ninety: 90,
    ek: 1, do: 2, teen: 3, char: 4, paanch: 5, panch: 5, chhah: 6, che: 6, saat: 7, aath: 8,
    ath: 8, nau: 9, das: 10, bees: 20, pachees: 25, pachchis: 25, tees: 30, chalis: 40,
    pachas: 50, saath: 60, sath: 60, sattar: 70, assi: 80, nabbe: 90, sau: 100, so: 100,
  };
  const mult: Record<string, number> = { hundred: 100, sau: 100, so: 100, thousand: 1000, hazaar: 1000, hazar: 1000, lakh: 100000, lac: 100000 };
  const tokens = t.replace(/[^a-z0-9\s-]/g, ' ').replace(/-/g, ' ').split(/\s+/).filter(Boolean);
  if (!tokens.some((w) => small[w] != null || mult[w] != null)) return null;
  let total = 0, current = 0, any = false;
  for (const w of tokens) {
    if (['and', 'rupees', 'rupee', 'rs', 'rupaye', 'only'].includes(w)) continue;
    if (small[w] != null) {
      const v = small[w];
      if ((w === 'sau' || w === 'so') && current > 0 && current < 100) current *= 100;
      else current += v;
      any = true; continue;
    }
    if (mult[w] != null) {
      const m = mult[w];
      if (current === 0) current = 1;
      if (m === 100) current *= 100;
      else { total += current * m; current = 0; }
      any = true; continue;
    }
  }
  if (!any) return null;
  const r = total + current;
  return r > 0 && r <= 100000000 ? r : null;
}
