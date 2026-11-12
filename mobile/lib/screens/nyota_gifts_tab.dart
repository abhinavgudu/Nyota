import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart' show GiftPayload;
import '../services/nyota_service.dart';
import '../theme.dart';
import '../utils/image_compressor.dart';

/// Nyota with Gifts: guest details + cash + any number of gifts,
/// each with its own optional image (compressed, uploaded with progress).
class NyotaGiftsTab extends StatefulWidget {
  const NyotaGiftsTab({super.key, this.onSaved});

  final VoidCallback? onSaved;

  @override
  State<NyotaGiftsTab> createState() => _NyotaGiftsTabState();
}

class _NyotaGiftsTabState extends State<NyotaGiftsTab>
    with AutomaticKeepAliveClientMixin {
  final _nameCtrl = TextEditingController();
  final _fatherCtrl = TextEditingController();
  final _villageCtrl = TextEditingController();
  final _cashCtrl = TextEditingController();

  final _giftDrafts = <_GiftDraft>[];

  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _fatherCtrl.dispose();
    _villageCtrl.dispose();
    _cashCtrl.dispose();
    for (final g in _giftDrafts) {
      g.dispose();
    }
    super.dispose();
  }

  double get _cash =>
      double.tryParse(_cashCtrl.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

  bool get _canSave {
    if (_saving) return false;
    if (_cash <= 0) return false;
    if (_giftDrafts.any((g) => !g.isValid)) return false;
    return true;
  }

  void _addGift() {
    setState(() => _giftDrafts.add(_GiftDraft()));
  }

  Future<void> _pickGift(_GiftDraft draft) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      draft.pendingBytes = bytes;
      draft.status = _GiftImageStatus.compressing;
    });
    try {
      draft.pendingBytes = await ImageCompressor.compress(bytes);
      draft.status = _GiftImageStatus.idle;
    } catch (_) {
      draft.status = _GiftImageStatus.idle; // keep original bytes if compression fails
    }
    if (mounted) setState(() {});
  }

  void _removeGift(int index) {
    setState(() {
      _giftDrafts[index].dispose();
      _giftDrafts.removeAt(index);
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      final event = await NyotaService.latestEvent();
      if (event == null) {
        _showError('No event found. Open the Dashboard tab and create an event first.');
        return;
      }

      // Resolve the real entry id first, then upload images against its id,
      // then insert gifts. The cash entry is saved before any image work,
      // so money is never lost to a flaky network.
      final entryId = await NyotaService.saveNyotaEntry(
        eventId: event.id,
        cashAmount: _cash,
        guestName: _nameCtrl.text,
        fatherName: _fatherCtrl.text,
        village: _villageCtrl.text,
      );

      final uploadedGifts = <GiftPayload>[];
      var imageFailed = false;
      for (final draft in _giftDrafts) {
        final pending = draft.pendingBytes;
        if (pending != null) {
          setState(() => draft.status = _GiftImageStatus.uploading);
          try {
            final path = await NyotaService.uploadGiftImage(
              entryId,
              pending,
              onProgress: (r) {
                if (mounted) setState(() => draft.progress = r);
              },
            );
            draft.imagePath = path;
            draft.status = _GiftImageStatus.done;
            draft.pendingBytes = null;
          } catch (e) {
            imageFailed = true;
            draft.status = _GiftImageStatus.error;
          }
          if (mounted) setState(() {});
        }
        uploadedGifts.add(GiftPayload(
          name: draft.nameCtrl.text.trim(),
          description: draft.descCtrl.text.trim().isEmpty ? null : draft.descCtrl.text.trim(),
          imagePath: draft.imagePath,
        ));
      }

      if (uploadedGifts.isNotEmpty) {
        await NyotaService.addGiftsToEntry(
          eventId: event.id,
          entryId: entryId,
          gifts: uploadedGifts,
        );
      }

      if (!mounted) return;
      setState(() => _saving = false);
      _resetForm();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          backgroundColor: NyotaColors.success,
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                imageFailed
                    ? 'Entry saved, but one gift image failed to upload.'
                    : 'Entry saved!',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ]),
        ));
      widget.onSaved?.call();
    } catch (e) {
      _showError('Could not save entry. Please try again.');
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetForm() {
    _nameCtrl.clear();
    _fatherCtrl.clear();
    _villageCtrl.clear();
    _cashCtrl.clear();
    for (final g in _giftDrafts) {
      g.dispose();
    }
    _giftDrafts.clear();
    setState(() {});
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(backgroundColor: NyotaColors.danger, content: Text(msg)));
    setState(() => _saving = false);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SafeArea(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Guest name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fatherCtrl,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: "Father's name",
                prefixIcon: Icon(Icons.family_restroom_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _villageCtrl,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Village / City',
                prefixIcon: Icon(Icons.location_city_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cashCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              decoration: const InputDecoration(
                labelText: 'Cash / Lifafa amount ₹',
                prefixIcon: Icon(Icons.currency_rupee),
              ),
            ),
            const SizedBox(height: 20),

            // Gifts
            Row(
              children: [
                const Text('Gifts',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addGift,
                  icon: const Icon(Icons.add),
                  label: const Text('Add gift'),
                ),
              ],
            ),
            if (_giftDrafts.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE5E1F0)),
                ),
                child: const Text(
                  'No gifts added. Tap "Add gift" for each physical gift (optional).',
                  style: TextStyle(color: NyotaColors.muted),
                ),
              )
            else
              ..._giftDrafts.asMap().entries.map((e) {
                final i = e.key;
                final draft = e.value;
                return _GiftDraftCard(
                  draft: draft,
                  index: i,
                  onRemove: () => _removeGift(i),
                  onPickImage: () => _pickGift(draft),
                );
              }),

            const SizedBox(height: 22),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _canSave ? _save : null,
                icon: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : const Icon(Icons.save),
                label: Text(_saving ? 'Saving…' : 'Save Entry'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _GiftImageStatus { idle, compressing, uploading, done, error }

class _GiftDraft {  final nameCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  Uint8List? pendingBytes;
  String? imagePath;
  _GiftImageStatus status = _GiftImageStatus.idle;
  double progress = 0;

  bool get isValid => nameCtrl.text.trim().isNotEmpty;

  void dispose() {
    nameCtrl.dispose();
    descCtrl.dispose();
  }
}

class _GiftDraftCard extends StatelessWidget {
  const _GiftDraftCard({
    required this.draft,
    required this.index,
    required this.onRemove,
    required this.onPickImage,
  });

  final _GiftDraft draft;
  final int index;
  final VoidCallback onRemove;
  final VoidCallback onPickImage;

  @override
  Widget build(BuildContext context) {
    final image = draft.pendingBytes;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Gift ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: NyotaColors.royalPurple)),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, color: NyotaColors.danger),
                  onPressed: onRemove,
                ),
              ],
            ),
            TextField(
              controller: draft.nameCtrl,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Gift name *',
                hintText: 'e.g. Brass Diya Set',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: draft.descCtrl,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'e.g. Pair of 6" brass diyas',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail preview
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F0FA),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE5E1F0)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: image != null
                      ? Image.memory(image, fit: BoxFit.cover)
                      : const Icon(Icons.image_outlined, color: NyotaColors.muted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OutlinedButton.icon(
                        onPressed: onPickImage,
                        icon: const Icon(Icons.photo_camera_outlined, size: 20),
                        label: Text(image == null ? 'Add photo' : 'Change photo'),
                      ),
                      if (draft.status == _GiftImageStatus.compressing)
                        const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: Row(children: [
                            SizedBox(
                                height: 14,
                                width: 14,
                                child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 8),
                            Text('Compressing image…', style: TextStyle(fontSize: 12.5)),
                          ]),
                        ),
                      if (draft.status == _GiftImageStatus.uploading) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Uploading… ${(draft.progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: draft.progress > 0 ? draft.progress : null,
                          color: NyotaColors.royalPurple,
                          backgroundColor: const Color(0xFFE5E1F0),
                        ),
                      ],
                      if (draft.status == _GiftImageStatus.done)
                        const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: Row(children: [
                            Icon(Icons.check_circle, color: NyotaColors.success, size: 16),
                            SizedBox(width: 6),
                            Text('Image ready', style: TextStyle(fontSize: 12.5, color: NyotaColors.success)),
                          ]),
                        ),
                      if (draft.status == _GiftImageStatus.error)
                        const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: Text('Upload failed — try again',
                              style: TextStyle(fontSize: 12.5, color: NyotaColors.danger)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

