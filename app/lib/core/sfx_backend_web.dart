import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import 'sfx_backend.dart';

SfxBackend createBackend() => _WebAudioBackend();

/// Web Audio rather than `<audio>` elements: a decoded buffer starts in a
/// fraction of a millisecond and can overlap itself, which a buzzer needs, and
/// there is no per-element network fetch on the critical path.
class _WebAudioBackend implements SfxBackend {
  web.AudioContext? _ctx;
  final _buffers = <String, web.AudioBuffer>{};

  @override
  bool get audible => true;

  /// A browser keeps an AudioContext suspended until the page has seen a user
  /// gesture. Every screen of this app is reached through a tap, so one
  /// listener that resumes it is enough; until then [play] simply drops the
  /// sound rather than queueing a burst of stale cues for the first click.
  web.AudioContext? _context() {
    if (_ctx != null) return _ctx;
    try {
      final ctx = _ctx = web.AudioContext();
      void resume(web.Event _) {
        if (ctx.state != 'running') ctx.resume();
      }

      final handler = resume.toJS;
      web.document.addEventListener('pointerdown', handler);
      web.document.addEventListener('keydown', handler);
      return ctx;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> load(String name, String assetPath) async {
    try {
      final ctx = _context();
      if (ctx == null) return;
      final data = await rootBundle.load(assetPath);
      // A copy, so the ArrayBuffer is exactly the file: the bundle's own
      // buffer can be a larger slab with this asset somewhere inside it.
      final bytes = Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      _buffers[name] = await ctx.decodeAudioData(bytes.buffer.toJS).toDart;
    } catch (_) {
      // Stays silent; the game does not depend on it.
    }
  }

  @override
  void play(String name, double volume) {
    try {
      final ctx = _ctx;
      final buffer = _buffers[name];
      if (ctx == null || buffer == null) return;
      if (ctx.state != 'running') {
        ctx.resume();
        return;
      }
      final gain = ctx.createGain()..gain.value = volume;
      final source = ctx.createBufferSource()..buffer = buffer;
      source.connect(gain);
      gain.connect(ctx.destination);
      source.start();
    } catch (_) {}
  }
}
