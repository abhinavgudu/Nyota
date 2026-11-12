import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/nyota_service.dart';
import '../theme.dart';
import '../utils/sound_util.dart';
import '../widgets/voice_text_field.dart';

/// Food Only quick entry — built for ~1,000 guests arriving together.
/// Amount is compulsory; guest name is optional; one tap save & next.
class FoodOnlyTab extends StatefulWidget {
  const FoodOnlyTab({super.key, this.onSaved});

  final VoidCallback? onSaved;

  @override
  State<FoodOnlyTab> createState() => _FoodOnlyTabState();
}

class _FoodOnlyTabState extends State<FoodOnlyTab>
    with AutomaticKeepAliveClientMixin {
  static const _quickAmounts = [51, 101, 500, 501, 1001, 1000];

  final _amountCtrl = TextEditingController();
  final _extraCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _amountFocus = FocusNode();
  final _nameFocus = FocusNode();

  bool _saving = false;
  int _savedCount = 0;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_refreshTotal);
    _extraCtrl.addListener(_refreshTotal);
  }

  @override
  void dispose() {
    _amountCtrl.removeListener(_refreshTotal);
    _extraCtrl.removeListener(_refreshTotal);
    _amountCtrl.dispose();
    _extraCtrl.dispose();
    _nameCtrl.dispose();
    _amountFocus.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _refreshTotal() {
    if (mounted) setState(() {});
  }

  int get _baseAmount =>
      int.tryParse(_amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  int get _additional =>
      int.tryParse(_extraCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  int get _total => _baseAmount + _additional;

  bool get _canSave => _total > 0 && !_saving;

  Future<void> _saveAndNext() async {
    if (!_canSave) return;

    // Optimistically block double submission immediately.
    setState(() => _saving = true);
    final amount = _total;
    final name = _nameCtrl.text;

    try {
      final event = await NyotaService.latestEvent();
      if (event == null) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            backgroundColor: NyotaColors.danger,
            content: Text('No event found. Open the Dashboard tab and create an event first.'),
          ));
        return;
      }
      await NyotaService.saveFoodOnly(
        eventId: event.id,
        amount: amount.toDouble(),
        guestName: name,
      );
      if (!mounted) return;
      setState(() {
        _savedCount++;
        _saving = false;
      });
      // Confirmation sound + haptic so the counter knows the entry went in.
      await SoundUtil.confirmSave();
      if (!mounted) return;
      // Clear the form and prepare for the next guest instantly.
      _amountCtrl.clear();
      _extraCtrl.clear();
      _nameCtrl.clear();
      _amountFocus.unfocus();
      _nameFocus.requestFocus();

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(milliseconds: 1600),
          backgroundColor: NyotaColors.success,
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Saved ₹$amount — entry #$_savedCount. Ready for next guest!',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ));
      widget.onSaved?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          backgroundColor: NyotaColors.danger,
          duration: const Duration(seconds: 6),
          content: Text('Could not save entry: $e'),
        ));
    }
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
            // Voice typing hint - fast entry
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: NyotaColors.saffron.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: NyotaColors.saffron.withValues(alpha: 0.35)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.mic, color: NyotaColors.saffron, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tap the mic on any field to speak — say "paanch sau do" or "502" for instant amount entry.',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: NyotaColors.ink),
                    ),
                  ),
                ],
              ),
            ),
            // Guest name (optional)
            VoiceTextField(
              controller: _nameCtrl,
              focusNode: _nameFocus,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              label: 'Guest name (optional)',
              hint: 'Speak name or skip',
              prefixIcon: Icons.person_outline,
            ),
            const SizedBox(height: 14),

            // Amount (compulsory) with numeric keypad + voice
            VoiceTextField(
              controller: _amountCtrl,
              focusNode: _amountFocus,
              numeric: true,
              keyboardType: const TextInputType.numberWithOptions(),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.next,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              label: 'Amount ₹ *',
              hint: 'Tap quick amount, type, or speak (e.g. "501")',
              prefixIcon: Icons.currency_rupee,
            ),
            const SizedBox(height: 12),

            // Quick amount buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickAmounts.map((v) {
                final selected = _amountCtrl.text == '$v';
                return _QuickAmountChip(
                  label: '₹$v',
                  selected: selected,
                  onTap: () {
                    _amountCtrl.text = '$v';
                    setState(() {});
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            // Additional amount (e.g. ₹500 + ₹2 = ₹502)
            VoiceTextField(
              controller: _extraCtrl,
              numeric: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveAndNext(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              label: 'Additional amount (optional)',
              hint: 'e.g. speak "do" to add ₹2',
              prefixIcon: Icons.add,
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4, left: 4),
              child: Text('e.g. ₹500 + ₹2 → ₹502', style: TextStyle(fontSize: 12, color: NyotaColors.muted)),
            ),
            const SizedBox(height: 14),

            // Running total card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: _total > 0
                    ? NyotaColors.royalPurple.withValues(alpha: 0.08)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _total > 0 ? NyotaColors.royalPurple : const Color(0xFFE5E1F0),
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Saving',
                      style: TextStyle(
                          color: NyotaColors.muted, fontWeight: FontWeight.w700)),
                  Text(
                    '₹$_total',
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: NyotaColors.royalPurple),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Prominent Save & Next
            SizedBox(
              height: 58,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      _canSave ? NyotaColors.saffron : NyotaColors.saffron.withValues(alpha: 0.4),
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                onPressed: _canSave ? _saveAndNext : null,
                icon: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : const Icon(Icons.save),
                label: const Text('SAVE & NEXT'),
              ),
            ),
            if (_savedCount > 0) ...[
              const SizedBox(height: 10),
              Center(
                child: Text(
                  '$_savedCount entries saved in this session',
                  style: const TextStyle(color: NyotaColors.muted, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickAmountChip extends StatelessWidget {
  const _QuickAmountChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? NyotaColors.royalPurple : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? NyotaColors.royalPurple : const Color(0xFFE5E1F0),
            width: 1.4,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: NyotaColors.royalPurple.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : NyotaColors.ink,
          ),
        ),
      ),
    );
  }
}
