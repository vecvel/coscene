import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Every sound in the game. All are synthesised here in code; the app
/// ships no audio files.
enum Sfx { tick, lift, snap, reject, engage, fail, success, reveal, star }

const int _rate = 22050;

/// Builds one sound as 16-bit mono samples.
Int16List synthesize(Sfx sfx) {
  switch (sfx) {
    case Sfx.tick:
      return _render(0.022, (t, n) => _sine(1400, t) * _decay(t, 0.006) * 0.5 + _noise(n) * _decay(t, 0.002) * 0.25);
    case Sfx.lift:
      return _render(0.06, (t, n) => _sine(520 + 4200 * t, t) * _bell(t, 0.06) * 0.35);
    case Sfx.snap:
      return _render(
        0.09,
        (t, n) => (t < 0.03 ? _sine(880, t) : _sine(1320, t)) * _decay(t < 0.03 ? t : t - 0.03, 0.02) * 0.5,
      );
    case Sfx.reject:
      return _render(0.15, (t, n) => _square(150, t) * _decay(t, 0.05) * 0.28);
    case Sfx.engage:
      return _render(0.11, (t, n) => _sine(420 + 2400 * t, t) * _bell(t, 0.11) * 0.45);
    case Sfx.fail:
      return _render(0.42, (t, n) {
        final f = (t < 0.2 ? 311.0 : 233.0) * (1 + 0.02 * math.sin(2 * math.pi * 11 * t));
        return (_sine(f, t) * 0.6 + _sine(f * 2, t) * 0.15) * _decay(t < 0.2 ? t : t - 0.2, 0.09) * 0.5;
      });
    case Sfx.success:
      const notes = [523.25, 659.25, 783.99, 1046.5];
      return _render(0.75, (t, n) {
        var v = 0.0;
        for (var i = 0; i < notes.length; i++) {
          final start = i * 0.11;
          if (t >= start) v += _sine(notes[i], t - start) * _decay(t - start, 0.16);
        }
        return v * 0.32;
      });
    case Sfx.reveal:
      return _render(0.6, (t, n) {
        final env = math.min(1.0, t / 0.08) * _decay(math.max(0, t - 0.08), 0.22);
        return (_sine(392, t) + _sine(523.25, t) + _sine(659.25, t)) * env * 0.16;
      });
    case Sfx.star:
      return _render(0.16, (t, n) => (_sine(1568, t) + _sine(2349, t) * 0.4) * _decay(t, 0.05) * 0.35);
  }
}

Int16List _render(double seconds, double Function(double t, int n) wave) {
  final count = (seconds * _rate).round();
  final out = Int16List(count);
  for (var n = 0; n < count; n++) {
    final t = n / _rate;
    // A few milliseconds of fade at each end removes clicks.
    final edge = math.min(1.0, math.min(n, count - n) / (_rate * 0.003));
    out[n] = (wave(t, n).clamp(-1.0, 1.0) * edge * 32767).round();
  }
  return out;
}

double _sine(double hz, double t) => math.sin(2 * math.pi * hz * t);
double _square(double hz, double t) => _sine(hz, t) >= 0 ? 1 : -1;
double _decay(double t, double tau) => math.exp(-t / tau);
double _bell(double t, double length) => math.sin(math.pi * (t / length).clamp(0.0, 1.0));

/// Repeatable noise from the sample number, so every build sounds the same.
double _noise(int n) {
  var x = (n * 1103515245 + 12345) & 0x7FFFFFFF;
  x = (x ^ (x >> 13)) & 0x7FFFFFFF;
  return x / 0x3FFFFFFF - 1;
}

/// Plays synthesised sounds through a small native player on each platform
/// (AVAudioEngine on iOS, AudioTrack on Android).
class AudioPlayer {
  static const _channel = MethodChannel('coscene/audio');
  bool _ready = false;

  /// Synthesises every sound once and hands the samples to the platform.
  Future<void> prepare() async {
    if (_ready) return;
    try {
      for (final sfx in Sfx.values) {
        final samples = synthesize(sfx);
        await _channel.invokeMethod<void>('load', {
          'id': sfx.index,
          'rate': _rate,
          'pcm': samples.buffer.asUint8List(),
        });
      }
      _ready = true;
    } on MissingPluginException {
      // No native player (for example in widget tests): stay silent.
    } on PlatformException {
      // Audio could not start; the game is fully playable without it.
    }
  }

  void play(Sfx sfx, {double volume = 1}) {
    if (!_ready) return;
    _channel.invokeMethod<void>('play', {'id': sfx.index, 'volume': volume}).catchError((_) {});
  }
}
