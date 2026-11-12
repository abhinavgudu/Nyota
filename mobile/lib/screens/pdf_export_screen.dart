import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models.dart';
import '../services/nyota_service.dart';
import '../theme.dart';

/// Generates and shares the Guest Register PDF.
class PdfExportScreen extends StatefulWidget {
  const PdfExportScreen({super.key, required this.event});

  final NyotaEvent event;

  @override
  State<PdfExportScreen> createState() => _PdfExportScreenState();
}

class _PdfExportScreenState extends State<PdfExportScreen> {
  bool _generating = false;
  String _status = '';
  double _progress = 0;

  Future<void> _export() async {
    setState(() {
      _generating = true;
      _status = 'Loading entries…';
      _progress = 0;
    });
    try {
      final event = widget.event;
      final totals = await NyotaService.dashboardTotals(event.id);

      // Load all entries page by page.
      final all = <GuestEntry>[];
      var offset = 0;
      while (true) {
        final page = await NyotaService.fetchEntries(event.id, limit: 200, offset: offset);
        all.addAll(page);
        if (page.length < 200) break;
        offset += 200;
      }

      // Fetch gift images (already compressed in storage).
      setState(() => _status = 'Fetching gift images…');
      final imageCache = <String, pw.MemoryImage?>{};
      var fetched = 0;
      final giftCount =
          all.fold<int>(0, (n, e) => n + e.gifts.where((g) => g.imagePath != null).length);
      for (final entry in all) {
        for (final g in entry.gifts) {
          final p = g.imagePath;
          if (p == null || imageCache.containsKey(p)) continue;
          try {
            final res = await http.get(Uri.parse(NyotaService.publicUrl(p)));
            if (res.statusCode == 200) {
              imageCache[p] = pw.MemoryImage(res.bodyBytes);
            }
          } catch (_) {
            imageCache[p] = null; // skip image on failure, keep the PDF going
          }
          fetched++;
          if (mounted) {
            setState(() {
              _progress = giftCount == 0 ? 1 : fetched / giftCount;
              _status = 'Fetching gift images… $fetched/$giftCount';
            });
          }
        }
      }

      setState(() => _status = 'Building PDF…');
      final pdf = _buildPdf(event, totals, all, imageCache);

      setState(() => _status = 'Done');
      await Printing.sharePdf(bytes: await pdf.save(), filename: 'nyota-register-${event.name}.pdf');
      if (mounted) setState(() => _generating = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _generating = false;
          _status = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: NyotaColors.danger,
          content: Text('Could not generate PDF. Please try again.'),
        ));
      }
    }
  }

  pw.Document _buildPdf(
    NyotaEvent event,
    DashboardTotals totals,
    List<GuestEntry> entries,
    Map<String, pw.MemoryImage?> imageCache,
  ) {
    final pdf = pw.Document();
    final purple = const PdfColor.fromInt(0xFF6C3CE9);
    final saffron = const PdfColor.fromInt(0xFFF59E0B);

    final header = pw.Header(
      margin: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: pw.BoxDecoration(color: purple, borderRadius: pw.BorderRadius.circular(6)),
                child: pw.Text('NYOTA',
                    style: pw.TextStyle(
                        color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 14)),
              ),
              pw.SizedBox(width: 10),
              pw.Text('Guest Register',
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text('Event: ${event.name}', style: const pw.TextStyle(fontSize: 13)),
        ],
      ),
    );

    final totalsBlock = pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFFFF9EF),
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: saffron, width: 1),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _totalCell('Guests', '${totals.totalGuests}'),
          _totalCell('Nyota Cash', '₹${_fmt(totals.totalNyotaCash)}'),
          _totalCell('Food Only', '₹${_fmt(totals.totalFoodOnly)}'),
          _totalCell('Total Cash', '₹${_fmt(totals.totalCash)}'),
          _totalCell('Physical Gifts', '${totals.totalGifts}'),
        ],
      ),
    );

    final headerBg = purple;
    final rows = <List<pw.Widget>>[
      [
        _cell('#', bold: true, white: true, bg: headerBg),
        _cell('Guest', bold: true, white: true, bg: headerBg),
        _cell("Father's Name", bold: true, white: true, bg: headerBg),
        _cell('Village', bold: true, white: true, bg: headerBg),
        _cell('Category', bold: true, white: true, bg: headerBg),
        _cell('Cash', bold: true, white: true, bg: headerBg, alignRight: true),
        _cell('Gifts', bold: true, white: true, bg: headerBg),
      ]
    ];
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final giftsDesc = e.gifts.isEmpty
          ? '—'
          : e.gifts.map((g) {
              final desc = (g.description == null || g.description!.isEmpty) ? '' : ' (${g.description})';
              return '${g.name}$desc';
            }).join(', ');
      final images = e.gifts
          .map((g) => g.imagePath == null ? null : imageCache[g.imagePath])
          .whereType<pw.MemoryImage>()
          .toList();

      rows.add([
        _cell('${i + 1}'),
        _cell(e.displayName),
        _cell(e.fatherName ?? '—'),
        _cell(e.village ?? '—'),
        _cell(e.category.label),
        _cell('₹${_fmt(e.cashAmount)}', alignRight: true),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(giftsDesc, style: const pw.TextStyle(fontSize: 8.5)),
            if (images.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Row(
                  children: [
                    for (final img in images.take(4))
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(right: 4),
                        child: pw.ClipRRect(
                          horizontalRadius: 4,
                          verticalRadius: 4,
                          child: pw.Image(img, width: 44, height: 44, fit: pw.BoxFit.cover),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ]);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 30),
        header: (ctx) => header,
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount} — Generated by Nyota',
              style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600)),
        ),
        build: (ctx) => [
          totalsBlock,
          pw.Table(
            border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFE5E1F0), width: 0.5),
            columnWidths: const {
              0: pw.FixedColumnWidth(24),
              1: pw.FlexColumnWidth(2.2),
              2: pw.FlexColumnWidth(2),
              3: pw.FlexColumnWidth(1.6),
              4: pw.FlexColumnWidth(1.8),
              5: pw.FixedColumnWidth(56),
              6: pw.FlexColumnWidth(3.2),
            },
            children: [for (final row in rows) pw.TableRow(children: row)],
          ),
        ],
      ),
    );
    return pdf;
  }

  pw.Widget _totalCell(String label, String value) => pw.Column(
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
          pw.Text(value, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ],
      );

  pw.Widget _cell(String text,
      {bool bold = false, bool white = false, bool alignRight = false, PdfColor? bg}) {
    final cell = pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8.5,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: white ? PdfColors.white : PdfColors.black,
        ),
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      ),
    );
    if (bg == null) return cell;
    return pw.Container(
      color: bg,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8.5,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: white ? PdfColors.white : PdfColors.black,
        ),
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      ),
    );
  }

  String _fmt(num v) {
    if (v == v.roundToDouble()) {
      return v.toInt().toString();
    }
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export PDF')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.picture_as_pdf, size: 56, color: NyotaColors.danger),
              const SizedBox(height: 12),
              Text(
                widget.event.name,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'The PDF includes every entry, gift details and images,\nplus all totals — ready to print or share.',
                textAlign: TextAlign.center,
                style: TextStyle(color: NyotaColors.muted, height: 1.5),
              ),
              const SizedBox(height: 24),
              if (_generating) ...[
                LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  color: NyotaColors.royalPurple,
                  backgroundColor: const Color(0xFFE5E1F0),
                ),
                const SizedBox(height: 10),
                Text(_status, style: const TextStyle(color: NyotaColors.muted)),
              ] else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _export,
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Generate & Share PDF'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
