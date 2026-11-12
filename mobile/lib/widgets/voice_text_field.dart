import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../theme.dart';
import '../utils/voice_parser.dart';

/// A mic button that listens to speech and reports the recognized text.
/// Powerful, tap-to-toggle: tap once to start, tap again (or auto-stop on
/// silence) to finish. Shows a clear listening state for fast event entry.
class VoiceMicButton extends StatefulWidget {
  const VoiceMicButton({
    super.key,
    required this.onResult,
    this.numeric = false,
    this.onListeningChanged,
    this.size = 44,
    this.compact = false,
  });

  /// Called with the final (or best partial) recognized text.
  /// For [numeric] fields this is already parsed to digits when possible.
  final ValueChanged<String> onResult;
  final bool numeric;
  final ValueChanged<bool>? onListeningChanged;
  final double size;
  final bool compact;

  @override
  State<VoiceMicButton> createState() => VoiceMicButtonState();
}

class VoiceMicButtonState extends State<VoiceMicButton>
    with SingleTickerProviderStateMixin {
  static final stt.SpeechToText _speech = stt.SpeechToText();
  static bool _initAttempted = false;
  static bool _available = false;
  static String? _localeId;

  bool _listening = false;
  String _lastWords = '';
  late final AnimationController _pulse;

  bool get isListening => _listening;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    if (_listening) {
      _speech.stop();
    }
    _pulse.dispose();
    super.dispose();
  }

  Future<bool> _ensureInit() async {
    if (_initAttempted && _available) return true;
    try {
      _available = await _speech.initialize(
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            if (mounted && _listening) _finish();
          }
        },
        onError: (_) {
          if (mounted && _listening) _finish(error: true);
        },
        debugLogging: false,
      );
      _initAttempted = true;
      if (_available) {
        final locales = await _speech.locales();
        // Prefer Indian English, then Hindi, then system default.
        _localeId = _pickLocale(locales);
      }
    } catch (_) {
      _available = false;
      _initAttempted = true;
    }
    return _available;
  }

  static String? _pickLocale(List<stt.LocaleName> locales) {
    String? find(String tag) {
      for (final l in locales) {
        if (l.localeId.toLowerCase().replaceAll('-', '_') ==
            tag.toLowerCase().replaceAll('-', '_')) {
          return l.localeId;
        }
      }
      // partial match
      for (final l in locales) {
        if (l.localeId.toLowerCase().startsWith(tag.toLowerCase().split('_').first)) {
          return l.localeId;
        }
      }
      return null;
    }
    return find('en_IN') ?? find('hi_IN') ?? find('en_US') ?? (locales.isNotEmpty ? locales.first.localeId : null);
  }

  Future<void> toggle() async {
    if (_listening) {
      await _speech.stop();
      _finish();
      return;
    }
    final ok = await _ensureInit();
    if (!ok || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Voice typing not available. Check microphone permission.'),
        ));
      }
      return;
    }
    setState(() {
      _listening = true;
      _lastWords = '';
    });
    widget.onListeningChanged?.call(true);
    _pulse.repeat(reverse: true);

    await _speech.listen(
      onResult: (result) {
        _lastWords = result.recognizedWords;
        if (result.finalResult) {
          _finish();
        }
      },
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
        localeId: _localeId,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  void _finish({bool error = false}) {
    if (!_listening) return;
    _pulse.stop();
    _pulse.reset();
    final words = _lastWords.trim();
    setState(() => _listening = false);
    widget.onListeningChanged?.call(false);
    if (error || words.isEmpty) return;

    String out = words;
    if (widget.numeric) {
      out = VoiceParse.amount(words) ?? words.replaceAll(RegExp(r'[^0-9.]'), '');
    } else {
      out = VoiceParse.text(words);
    }
    if (out.isNotEmpty) widget.onResult(out);
  }

  @override
  Widget build(BuildContext context) {
    final listening = _listening;
    final bg = listening ? NyotaColors.danger : NyotaColors.royalPurple;
    final icon = listening ? Icons.mic : Icons.mic_none_rounded;

    return Semantics(
      button: true,
      label: listening ? 'Stop voice input' : 'Start voice input',
      child: GestureDetector(
        onTap: toggle,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final scale = listening ? 1.0 + (_pulse.value * 0.12) : 1.0;
            return Transform.scale(
              scale: scale,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: bg,
                  shape: BoxShape.circle,
                  boxShadow: listening
                      ? [
                          BoxShadow(
                            color: NyotaColors.danger.withValues(alpha: 0.45),
                            blurRadius: 14,
                            spreadRadius: 2,
                          )
                        ]
                      : [
                          BoxShadow(
                            color: NyotaColors.royalPurple.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          )
                        ],
                ),
                child: Icon(icon, color: Colors.white, size: widget.compact ? 20 : 24),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Convenience text field with an integrated voice mic button.
/// For numeric fields, spoken amounts are parsed to digits automatically.
class VoiceTextField extends StatefulWidget {
  const VoiceTextField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.prefixIcon,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.numeric = false,
    this.autofocus = false,
    this.focusNode,
    this.onSubmitted,
    this.style,
    this.maxLines = 1,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final IconData? prefixIcon;
  final TextInputType? keyboardType;
  final List<dynamic>? inputFormatters;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final bool numeric;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  final TextStyle? style;
  final int maxLines;
  final bool enabled;

  @override
  State<VoiceTextField> createState() => _VoiceTextFieldState();
}

class _VoiceTextFieldState extends State<VoiceTextField> {
  bool _listening = false;

  void _onVoiceResult(String text) {
    if (widget.numeric) {
      // Replace amount field with parsed digits.
      widget.controller.text = text;
    } else {
      // Append to existing text (useful for names/village corrections).
      final existing = widget.controller.text.trim();
      widget.controller.text = existing.isEmpty ? text : '$existing $text';
    }
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: widget.controller.text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters?.cast(),
      textInputAction: widget.textInputAction,
      textCapitalization: widget.textCapitalization,
      onSubmitted: widget.onSubmitted,
      style: widget.style,
      maxLines: widget.maxLines,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: VoiceMicButton(
            compact: true,
            size: 38,
            numeric: widget.numeric,
            onResult: _onVoiceResult,
            onListeningChanged: (v) => setState(() => _listening = v),
          ),
        ),
        suffixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        focusedBorder: _listening
            ? OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: NyotaColors.danger, width: 1.8),
              )
            : null,
      ),
    );
  }
}
