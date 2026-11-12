import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Entry-confirmation sound + haptic feedback.
///
/// The sound is short and warm (a bell-like chime) so it is audible in a noisy
/// venue but not irritating over a long shift. It can be switched off from the
/// app bar; the choice is remembered on the device.
class SoundUtil {
  static final AudioPlayer _player = AudioPlayer();
  static final AudioContext _context = AudioContext(
    android: const AudioContextAndroid(
      isSpeakerphoneOn: false,
      stayAwake: false,
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.assistanceSonification,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.ambient,
      options: const {AVAudioSessionOptions.mixWithOthers},
    ),
  );

  static bool _enabled = true;
  static bool _loaded = false;

  /// Whether the confirmation sound is enabled (default: on).
  static bool get enabled => _enabled;

  /// Loads the saved preference. Call once at app start.
  static Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool('nyota_sound_enabled') ?? true;
    } catch (_) {
      _enabled = true;
    }
  }

  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('nyota_sound_enabled', value);
    } catch (_) {
      /* ignore */
    }
  }

  /// Plays the success chime (no-op when disabled or when the player fails).
  static Future<void> playSuccess() async {
    if (!_enabled) return;
    try {
      await _player.setAudioContext(_context);
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.play(AssetSource('sounds/success.wav'), volume: 0.9);
    } catch (e) {
      if (kDebugMode) debugPrint('SoundUtil: $e');
    }
  }

  /// Light vibration so the confirmation is felt even when the phone is in a pocket.
  static Future<void> haptic() async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {
      /* ignore */
    }
  }

  /// Sound + haptic together — call this after every successful save.
  static Future<void> confirmSave() async {
    await haptic();
    await playSuccess();
  }
}
