import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models.dart';
import '../services/nyota_service.dart';
import '../theme.dart';
import '../utils/image_compressor.dart';
import '../widgets/gift_thumb.dart';
import 'image_viewer_screen.dart';

/// View, edit and delete a single guest entry.
class EntryDetailScreen extends StatefulWidget {
  const EntryDetailScreen({super.key, required this.entryId});

  final String entryId;

  @override
  State<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<EntryDetailScreen> {
  static final _money = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

  final _nameCtrl = TextEditingController();
  final _fatherCtrl = TextEditingController();
  final _villageCtrl = TextEditingController();
  final _cashCtrl = TextEditingController();
  final _giftDrafts = <_GiftDraft>[];

  GuestEntry? _entry;
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _fatherCtrl.dispose();
    _villageCtrl.dispose();
    _cashCtrl.dispose();
    for (final d in _giftDrafts) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await NyotaService.client
          .from('guest_entries')
          .select('*, gifts(*)')
          .eq('id', widget.entryId)
          .single();
      final entry = GuestEntry.fromMap(rows);
      _hydrate(entry);
      if (mounted) {
        setState(() {
          _entry = entry;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load this entry.')),
        );
      }
    }
  }

  void _hydrate(GuestEntry entry) {
    _nameCtrl.text = entry.guestName ?? '';
    _fatherCtrl.text = entry.fatherName ?? '';
    _villageCtrl.text = entry.village ?? '';
    _cashCtrl.text = entry.cashAmount % 1 == 0
        ? entry.cashAmount.toStringAsFixed(0)
        : entry.cashAmount.toStringAsFixed(2);
    for (final d in _giftDrafts) {
      d.dispose();
    }
    _giftDrafts.clear();
    for (final g in entry.gifts) {
      final d = _GiftDraft()
        ..nameCtrl.text = g.name
        ..descCtrl.text = g.description ?? ''
        ..imagePath = g.imagePath;
      _giftDrafts.add(d);
    }
  }

  bool get _canSave {
    if (_saving) return false;
    if ((double.tryParse(_cashCtrl.text) ?? 0) <= 0) return false;
    if (_giftDrafts.any((g) => g.nameCtrl.text.trim().isEmpty)) return false;
    return true;
  }

  Future<void> _save() async {
    if (!_canSave || _entry == null) return;
    setState(() => _saving = true);
    try {
      // Upload any newly picked images first.
      for (final d in _giftDrafts) {
        final pending = d.pendingBytes;
        if (pending != null) {
          try {
            final path = await NyotaService.uploadGiftImage(_entry!.id, pending,
                onProgress: (r) {
              if (mounted) setState(() => d.progress = r);
            });
            d.imagePath = path;
            d.pendingBytes = null;
          } catch (_) {
            d.status = 'Upload failed';
          }
        }
      }

      await NyotaService.updateEntry(
        _entry!,
        cashAmount: double.tryParse(_cashCtrl.text) ?? 0,
        guestName: _nameCtrl.text,
        fatherName: _fatherCtrl.text,
        village: _villageCtrl.text,
        gifts: _giftDrafts
            .map((d) => Gift(
                  id: '',
                  name: d.nameCtrl.text.trim(),
                  description: d.descCtrl.text.trim().isEmpty ? null : d.descCtrl.text.trim(),
                  imagePath: d.imagePath,
                ))
            .toList(),
      );
      if (!mounted) return;
      setState(() => _editing = false);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: NyotaColors.success,
          content: Text('Entry updated.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: NyotaColors.danger,
          content: Text('Could not update entry. Please try again.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text(
            'This will permanently remove the guest entry, its gifts and totals will update.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NyotaColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      await NyotaService.deleteEntry(widget.entryId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: NyotaColors.danger,
          content: Text('Could not delete entry. Please try again.'),
        ));
      }
    }
  }

  void _addGift() {
    setState(() => _giftDrafts.add(_GiftDraft()));
  }

  Future<void> _pickImage(_GiftDraft d) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      d.pendingBytes = bytes;
    });
    try {
      d.pendingBytes = await ImageCompressor.compress(bytes);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final entry = _entry;
    if (entry == null) {
      return const Scaffold(body: Center(child: Text('Entry not found.')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(entry.category.label),
        actions: [
          IconButton(
            tooltip: _editing ? 'View' : 'Edit',
            icon: Icon(_editing ? Icons.visibility_outlined : Icons.edit_outlined),
            onPressed: () => setState(() => _editing = !_editing),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: _deleting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.delete_outline),
            onPressed: _deleting ? null : _delete,
          ),
        ],
      ),
      body: _editing ? _buildEdit(entry) : _buildView(entry),
      bottomNavigationBar: _editing
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _canSave ? _save : null,
                  child: _saving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : const Text('Save Changes'),
                ),
              ),
            )
          : null,
    );
  }

  // ---------------- View mode ----------------

  Widget _buildView(GuestEntry entry) {
    final isNyota = entry.category == EntryCategory.nyotaGifts;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(entry.displayName,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w800, color: NyotaColors.ink)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: isNyota
                            ? NyotaColors.royalPurple.withValues(alpha: 0.1)
                            : NyotaColors.deepIndigo.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(entry.category.label,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isNyota ? NyotaColors.royalPurple : NyotaColors.deepIndigo,
                              fontSize: 12.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (entry.fatherName != null && entry.fatherName!.isNotEmpty)
                  _viewRow(Icons.family_restroom_outlined, "Father's name", entry.fatherName!),
                if (entry.village != null && entry.village!.isNotEmpty)
                  _viewRow(Icons.location_city_outlined, 'Village / City', entry.village!),
                _viewRow(Icons.currency_rupee, 'Cash / Lifafa',
                    _money.format(entry.cashAmount), valueColor: NyotaColors.success),
                if (entry.createdAt != null)
                  _viewRow(Icons.schedule, 'Recorded at',
                      DateFormat('d MMM yyyy, h:mm a').format(DateTime.parse(entry.createdAt!).toLocal())),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Gifts (${entry.gifts.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (entry.gifts.isEmpty)
          const Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No gifts recorded for this entry.',
                  style: TextStyle(color: NyotaColors.muted)),
            ),
          )
        else
          ...entry.gifts.map((g) => Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (g.imagePath != null)
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ImageViewerScreen(path: g.imagePath!),
                          )),
                          child: Hero(
                            tag: g.imagePath!,
                            child: CachedNetworkImage(
                              imageUrl: NyotaService.publicUrl(g.imagePath!),
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => Container(
                                width: 72,
                                height: 72,
                                color: const Color(0xFFF3F0FA),
                                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              ),
                              errorWidget: (_, _, _) => Container(
                                width: 72,
                                height: 72,
                                color: const Color(0xFFF3F0FA),
                                child: const Icon(Icons.broken_image),
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F0FA),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.card_giftcard, color: NyotaColors.muted),
                        ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(g.name,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                            if (g.description != null && g.description!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(g.description!,
                                    style: const TextStyle(color: NyotaColors.muted, fontSize: 13)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )),
      ],
    );
  }

  Widget _viewRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: NyotaColors.muted),
          const SizedBox(width: 10),
          SizedBox(
            width: 108,
            child: Text(label,
                style: const TextStyle(color: NyotaColors.muted, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: valueColor ?? NyotaColors.ink)),
          ),
        ],
      ),
    );
  }

  // ---------------- Edit mode ----------------

  Widget _buildEdit(GuestEntry entry) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Guest name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _fatherCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: "Father's name"),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _villageCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Village / City'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _cashCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(labelText: 'Cash / Lifafa amount ₹'),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Text('Gifts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const Spacer(),
            TextButton.icon(
              onPressed: _addGift,
              icon: const Icon(Icons.add),
              label: const Text('Add gift'),
            ),
          ],
        ),
        for (var i = 0; i < _giftDrafts.length; i++) _giftEditCard(i),
      ],
    );
  }

  Widget _giftEditCard(int index) {
    final d = _giftDrafts[index];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: d.nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Gift name *'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: NyotaColors.danger),
                  onPressed: () {
                    setState(() {
                      _giftDrafts[index].dispose();
                      _giftDrafts.removeAt(index);
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: d.descCtrl,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (d.imagePath != null && d.pendingBytes == null)
                  GiftThumb(path: d.imagePath!, size: 56)
                else if (d.pendingBytes != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(d.pendingBytes!, width: 56, height: 56, fit: BoxFit.cover),
                  )
                else
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F0FA),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.image_outlined, color: NyotaColors.muted),
                  ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => _pickImage(d),
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: Text(d.imagePath == null && d.pendingBytes == null
                      ? 'Add photo'
                      : 'Change photo'),
                ),
                if (d.status != null) ...[
                  const SizedBox(width: 8),
                  Text(d.status!,
                      style: const TextStyle(color: NyotaColors.danger, fontSize: 12)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GiftDraft {
  final nameCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  Uint8List? pendingBytes;
  String? imagePath;
  String? status;
  double progress = 0;

  void dispose() {
    nameCtrl.dispose();
    descCtrl.dispose();
  }
}
