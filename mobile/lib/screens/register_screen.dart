import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/nyota_service.dart';
import '../theme.dart';
import '../widgets/gift_thumb.dart';
import 'entry_detail_screen.dart';

/// Unified guest register: all entries with search + infinite pagination.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static final _money = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<GuestEntry> _entries = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _refresh();
    _scrollCtrl.addListener(() {
      if (_scrollCtrl.position.pixels > _scrollCtrl.position.maxScrollExtent - 400) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final event = await NyotaService.latestEvent();
      if (event == null) {
        if (mounted) {
          setState(() {
            _entries = [];
            _hasMore = false;
            _loading = false;
          });
        }
        return;
      }
      final entries = await NyotaService.fetchEntries(
        event.id,
        search: _search,
        limit: 50,
        offset: 0,
      );
      if (mounted) {
        setState(() {
          _entries = entries;
          _hasMore = entries.length >= 50;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load entries. Pull down to retry.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final event = await NyotaService.latestEvent();
      if (event == null) return;
      final more = await NyotaService.fetchEntries(
        event.id,
        search: _search,
        limit: 50,
        offset: _entries.length,
      );
      if (mounted) {
        setState(() {
          _entries.addAll(more);
          _hasMore = more.length >= 50;
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onSearchChanged(String v) {
    _search = v;
    _refresh();
  }

  Future<void> _openEntry(GuestEntry entry) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EntryDetailScreen(entryId: entry.id)),
    );
    if (changed == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search name, father or village…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            _onSearchChanged('');
                          },
                        ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!, style: const TextStyle(color: NyotaColors.muted)))
                      : _entries.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.people_outline, size: 56, color: NyotaColors.muted),
                                    const SizedBox(height: 12),
                                    Text(
                                      _search.isEmpty
                                          ? 'No entries yet.\nAdd your first guest from the Add Entry tab.'
                                          : 'No guests match "$_search".',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: NyotaColors.muted, height: 1.5),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollCtrl,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.only(bottom: 24),
                              itemCount: _entries.length + (_hasMore ? 1 : 0),
                              itemBuilder: (context, i) {
                                if (i >= _entries.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(child: CircularProgressIndicator()),
                                  );
                                }
                                return _EntryCard(
                                  entry: _entries[i],
                                  money: _money,
                                  onTap: () => _openEntry(_entries[i]),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.money, required this.onTap});

  final GuestEntry entry;
  final NumberFormat money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isNyota = entry.category == EntryCategory.nyotaGifts;
    final thumbs = entry.gifts.where((g) => g.imagePath != null).take(4).toList();

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.displayName,
                      style: const TextStyle(
                          fontSize: 16.5, fontWeight: FontWeight.w800, color: NyotaColors.ink),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isNyota
                          ? NyotaColors.royalPurple.withValues(alpha: 0.1)
                          : NyotaColors.deepIndigo.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      entry.category.label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isNyota ? NyotaColors.royalPurple : NyotaColors.deepIndigo,
                      ),
                    ),
                  ),
                ],
              ),
              if (entry.fatherName != null && entry.fatherName!.isNotEmpty)
                _metaLine('S/o ${entry.fatherName!}', Icons.family_restroom_outlined),
              if (entry.village != null && entry.village!.isNotEmpty)
                _metaLine(entry.village!, Icons.location_city_outlined),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.currency_rupee, size: 18, color: NyotaColors.success),
                  Text(
                    money.format(entry.cashAmount),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w900, color: NyotaColors.success),
                  ),
                  const Spacer(),
                  if (entry.gifts.isNotEmpty) ...[
                    const Icon(Icons.card_giftcard, size: 17, color: NyotaColors.saffron),
                    const SizedBox(width: 4),
                    Text('${entry.gifts.length} gift${entry.gifts.length > 1 ? 's' : ''}',
                        style: const TextStyle(color: NyotaColors.muted, fontWeight: FontWeight.w600)),
                  ],
                  for (var i = 0; i < thumbs.length; i++)
                    Padding(
                      key: ValueKey(thumbs[i].id),
                      padding: EdgeInsets.only(left: i == 0 && entry.gifts.isNotEmpty ? 8 : 4),
                      child: GiftThumb(path: thumbs[i].imagePath!),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaLine(String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: NyotaColors.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: NyotaColors.muted, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
