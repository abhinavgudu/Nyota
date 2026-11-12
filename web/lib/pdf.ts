import { jsPDF } from 'jspdf';
import autoTable from 'jspdf-autotable';
import { DashboardTotals, GuestEntry, NyotaEvent, giftImageUrl } from './supabase';

const PURPLE: [number, number, number] = [108, 60, 233]; // #6C3CE9
const SAFFRON: [number, number, number] = [245, 158, 11]; // #F59E0B
const CREAM: [number, number, number] = [255, 249, 239]; // #FFF9EF
const MUTED: [number, number, number] = [110, 107, 130];

async function imageToDataUrl(url: string, maxEdge = 120): Promise<string | null> {
  try {
    const res = await fetch(url);
    if (!res.ok) return null;
    const blob = await res.blob();
    const bitmap = await createImageBitmap(blob);
    const scale = Math.min(1, maxEdge / Math.max(bitmap.width, bitmap.height));
    const canvas = document.createElement('canvas');
    canvas.width = Math.round(bitmap.width * scale);
    canvas.height = Math.round(bitmap.height * scale);
    canvas.getContext('2d')!.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    bitmap.close();
    return canvas.toDataURL('image/jpeg', 0.7);
  } catch {
    return null; // keep the PDF going without this image
  }
}

export async function exportRegisterPdf(
  event: NyotaEvent,
  totals: DashboardTotals,
  entries: GuestEntry[],
  onProgress?: (status: string, ratio: number) => void
): Promise<void> {
  // Collect gift image data urls (each stored image is already compressed).
  const images = new Map<string, string>();
  const paths: string[] = [];
  for (const e of entries) {
    for (const g of e.gifts ?? []) {
      if (g.image_path && !images.has(g.image_path)) paths.push(g.image_path);
    }
  }
  for (let i = 0; i < paths.length; i++) {
    onProgress?.(`Fetching gift images… ${i + 1}/${paths.length}`, (i + 1) / Math.max(paths.length, 1));
    const dataUrl = await imageToDataUrl(giftImageUrl(paths[i]));
    if (dataUrl) images.set(paths[i], dataUrl);
  }

  onProgress?.('Building PDF…', 1);
  const doc = new jsPDF({ orientation: 'landscape', unit: 'pt', format: 'a4' });

  // Header
  doc.setFillColor(...PURPLE);
  doc.roundedRect(30, 26, 62, 22, 4, 4, 'F');
  doc.setTextColor(255, 255, 255);
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(10);
  doc.text('NYOTA', 36, 41);
  doc.setTextColor(30, 27, 46);
  doc.setFontSize(17);
  doc.text('Guest Register', 100, 42);
  doc.setFontSize(10.5);
  doc.setFont('helvetica', 'normal');
  doc.setTextColor(...MUTED);
  doc.text(`Event: ${event.name}`, 30, 62);

  // Totals strip
  doc.setFillColor(...CREAM);
  doc.setDrawColor(...SAFFRON);
  doc.roundedRect(30, 72, doc.internal.pageSize.getWidth() - 60, 40, 6, 6, 'FD');
  doc.setTextColor(30, 27, 46);
  doc.setFont('helvetica', 'bold');
  const cells: Array<[string, string]> = [
    ['Guests', `${totals.total_guests}`],
    ['Nyota Cash', `Rs ${inr(totals.total_nyota_cash)}`],
    ['Food Only', `Rs ${inr(totals.total_food_only)}`],
    ['Total Cash', `Rs ${inr(totals.total_cash)}`],
    ['Physical Gifts', `${totals.total_gifts}`],
  ];
  const cellW = (doc.internal.pageSize.getWidth() - 60) / cells.length;
  cells.forEach(([label, value], i) => {
    const x = 30 + i * cellW + cellW / 2;
    doc.setFontSize(7.5);
    doc.setFont('helvetica', 'normal');
    doc.setTextColor(...MUTED);
    doc.text(label, x, 89, { align: 'center' });
    doc.setFontSize(11);
    doc.setFont('helvetica', 'bold');
    doc.setTextColor(30, 27, 46);
    doc.text(value, x, 103, { align: 'center' });
  });

  autoTable(doc, {
    startY: 126,
    head: [['#', 'Guest', "Father's Name", 'Village', 'Category', 'Cash', 'Gifts', 'Photos']],
    body: entries.map((e, i) => [
      `${i + 1}`,
      e.guest_name || 'Guest',
      e.father_name || '—',
      e.village || '—',
      e.category === 'food_only' ? 'Food Only' : 'Nyota with Gifts',
      `Rs ${inr(Number(e.cash_amount))}`,
      (e.gifts ?? []).map((g) => `${g.name}${g.description ? ` (${g.description})` : ''}`).join(', ') || '—',
      '',
    ]),
    styles: { fontSize: 7.5, cellPadding: 4 },
    headStyles: { fillColor: PURPLE, textColor: 255, fontStyle: 'bold' },
    alternateRowStyles: { fillColor: [250, 248, 255] },
    columnStyles: { 0: { cellWidth: 24 }, 5: { cellWidth: 60, halign: 'right' }, 7: { cellWidth: 150 } },
    didParseCell: (data) => {
      // Leave the photos column empty textually; images drawn after.
    },
    willDrawCell: (data) => {
      // noop
    },
    didDrawCell: (data) => {
      if (data.section !== 'body') return;
      const entry = entries[data.row.index];
      const pathsFor = (entry.gifts ?? []).map((g) => g.image_path).filter(Boolean) as string[];
      if (!pathsFor.length) return;
      const size = 34;
      const gap = 4;
      pathsFor.slice(0, 4).forEach((p, i) => {
        const dataUrl = images.get(p);
        if (!dataUrl) return;
        try {
          doc.addImage(dataUrl, 'JPEG', data.cell.x + 3 + i * (size + gap), data.cell.y + 3, size, size);
        } catch {
          // skip broken images
        }
      });
    },
  });

  // Footer with page numbers
  const pages = doc.getNumberOfPages();
  for (let i = 1; i <= pages; i++) {
    doc.setPage(i);
    doc.setFontSize(7.5);
    doc.setTextColor(...MUTED);
    doc.text(`Page ${i} of ${pages} — Generated by Nyota`, doc.internal.pageSize.getWidth() - 30, doc.internal.pageSize.getHeight() - 16, { align: 'right' });
  }

  doc.save(`nyota-register-${event.name.replace(/\s+/g, '-').toLowerCase()}.pdf`);
}

function inr(n: number): string {
  return Number.isFinite(n) ? n.toLocaleString('en-IN', { maximumFractionDigits: 2 }) : '0';
}
