import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../services/nyota_service.dart';
import '../theme.dart';
import 'event_dialog.dart';
import 'pdf_export_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  static final _money = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

  NyotaEvent? _event;
  DashboardTotals? _totals;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  String? _error;

  Future<void> refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final event = await NyotaService.latestEvent();
      if (event == null) {
        setState(() {
          _event = null;
          _totals = null;
          _loading = false;
        });
        return;
      }
      final totals = await NyotaService.dashboardTotals(event.id);
      if (mounted) {
        setState(() {
          _event = event;
          _totals = totals;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: NyotaColors.danger,
            content: Text('Could not load: ${e.toString()}'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  Future<void> _createFirstEvent() async {
    final event = await showEventDialog(context);
    if (event != null) refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_event == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_error != null ? Icons.error_outline : Icons.celebration_outlined,
                  size: 64, color: _error != null ? NyotaColors.danger : NyotaColors.saffron),
              const SizedBox(height: 16),
              Text(
                _error != null ? 'Could not load data' : 'Welcome to Nyota',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? 'Create your first event or join one to start recording guests, gifts and collections.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _error != null ? NyotaColors.danger : NyotaColors.muted, height: 1.4),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _error != null ? refresh : _createFirstEvent,
                icon: Icon(_error != null ? Icons.refresh : Icons.add),
                label: Text(_error != null ? 'Retry' : 'Create / Join Event'),
              ),
            ],
          ),
        ),
      );
    }

    final t = _totals;
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Event card
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: NyotaColors.royalPurple.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.event, color: NyotaColors.royalPurple),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_event!.name,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800, color: NyotaColors.ink)),
                        if (_event!.eventDate != null && _event!.eventDate!.isNotEmpty)
                          Text(
                            DateFormat('d MMMM yyyy').format(DateTime.parse(_event!.eventDate!)),
                            style: const TextStyle(color: NyotaColors.muted),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Switch / add event',
                    icon: const Icon(Icons.swap_horiz, color: NyotaColors.royalPurple),
                    onPressed: _createFirstEvent,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (t == null)
            const Center(child: CircularProgressIndicator())
          else ...[
            _StatGrid(t: t, money: _money),
            const SizedBox(height: 16),
            if (_event!.joinCode != null && _event!.joinCode!.isNotEmpty)
              _ShareJoinCard(event: _event!),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: NyotaColors.danger),
                title: const Text('Export Guest Register PDF',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Share or print the full register'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PdfExportScreen(event: _event!),
                  ));
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShareJoinCard extends StatelessWidget {
  const _ShareJoinCard({required this.event});
  final NyotaEvent event;

  @override
  Widget build(BuildContext context) {
    final code = event.joinCode ?? '';
    final url = NyotaService.eventShareUrl(code);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Share / Join Event', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
              'Share link, QR code ya event code se koi bhi join kar sakta hai.',
              style: TextStyle(color: NyotaColors.muted),
            ),
            const SizedBox(height: 14),
            Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE5E1F0)),
                ),
                child: QrImageView(
                  data: url,
                  size: 170,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Center(child: Text('Scan to join', style: TextStyle(color: NyotaColors.muted, fontSize: 12))),
            const SizedBox(height: 14),
            const Text('EVENT CODE', style: TextStyle(fontSize: 12, color: NyotaColors.muted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: NyotaColors.royalPurple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    code,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 3, color: NyotaColors.royalPurple),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Event code copied')));
                    }
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('SHARE LINK', style: TextStyle(fontSize: 12, color: NyotaColors.muted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            SelectableText(url, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: url));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Share link copied')));
                    }
                  },
                  icon: const Icon(Icons.link),
                  label: const Text('Copy Link'),
                ),
                FilledButton.icon(
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(text: 'Join "${event.name}" on Nyota: $url', subject: 'Join ${event.name} on Nyota'),
                  ),
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.t, required this.money});

  final DashboardTotals t;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.35,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: [
        _StatCard(
          icon: Icons.people_alt_outlined,
          color: NyotaColors.royalPurple,
          label: 'Total Guests',
          value: '${t.totalGuests}',
        ),
        _StatCard(
          icon: Icons.card_giftcard,
          color: NyotaColors.saffron,
          label: 'Nyota Cash',
          value: money.format(t.totalNyotaCash),
        ),
        _StatCard(
          icon: Icons.restaurant,
          color: NyotaColors.deepIndigo,
          label: 'Food Only',
          value: money.format(t.totalFoodOnly),
        ),
        _StatCard(
          icon: Icons.currency_rupee,
          color: NyotaColors.success,
          label: 'Total Cash',
          value: money.format(t.totalCash),
          emphasized: true,
        ),
        _StatCard(
          icon: Icons.redeem,
          color: NyotaColors.royalPurple,
          label: 'Physical Gifts',
          value: '${t.totalGifts}',
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: emphasized ? 26 : 22,
                  fontWeight: FontWeight.w800,
                  color: emphasized ? color : NyotaColors.ink,
                ),
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: NyotaColors.muted, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
