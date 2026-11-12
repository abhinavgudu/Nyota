'use client';

import { useEffect, useState } from 'react';
import QRCode from 'qrcode';

export function EventQr({ url, size = 180 }: { url: string; size?: number }) {
  const [src, setSrc] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    QRCode.toDataURL(url, { width: size, margin: 1, color: { dark: '#1e1b2e', light: '#ffffff' } })
      .then((data) => { if (!cancelled) setSrc(data); })
      .catch(() => { if (!cancelled) setSrc(null); });
    return () => { cancelled = true; };
  }, [url, size]);

  if (!src) {
    return (
      <div style={{ width: size, height: size, background: '#f3f0fa', borderRadius: 12, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--muted)', fontSize: 12 }}>
        QR…
      </div>
    );
  }
  // eslint-disable-next-line @next/next/no-img-element
  return <img src={src} alt="Event join QR code" width={size} height={size} style={{ borderRadius: 12, border: '1px solid var(--border)' }} />;
}
