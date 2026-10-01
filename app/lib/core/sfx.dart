import 'dart:async';

import 'package:flutter/foundation.dart';

import 'sfx_backend.dart';
import 'session_store_stub.dart'
    if (dart.library.js_interop) 'session_store_web.dart';

/// Every sound the game makes. The file lives at `assets/sounds/<file>.wav`;
/// `tool/build_sounds.py` is where each one comes from and why.
enum Cue {
  /// The buzzer is live -- the one cue a player has to react to.
  buzzOpen('buzz_open', 0.8),

  /// Somebody hit the buzzer first.
  buzzIn('buzz_in', 0.9),

  /// The local tap, played on the device the instant the button is pressed,
  /// before the server has said who won.
  tap('tap', 0.9),

  /// A tile was picked and its clue is coming up.
  cluePick('clue_pick', 1.0),

  correct('correct', 0.9),
  wrong('wrong', 0.8),

  /// The clue ended with nobody scoring.
  noAnswer('no_answer', 0.8),

  /// Countdown beat for the last seconds before an automatic buzzer opens.
  tick('tick', 0.5),

  /// A fresh board, or the game starting.
  roundStart('round_start', 0.9),

  /// Wagers are being placed for the final clue.
  finalIntro('final_intro', 0.9),

  /// The game is over.
  finale('finale', 1.0);

  const Cue(this.file, this.volume);

  final String file;
  final double volume;
}

/// The app's one sound player. A singleton because a mute switch only means
/// something if it is the same switch everywhere; [Sfx.test] exists so a test
/// can watch what was played without any audio at all.
class Sfx {
  Sfx._(this._backend) : muted = ValueNotifier(readRaw(_mutedKey) == '1');

  @visibleForTesting
  Sfx.test(this._backend) : muted = ValueNotifier(false);

  static final instance = Sfx._(createSfxBackend());

  static const _mutedKey = 'jeopard.muted.v1';

  final SfxBackend _backend;

  /// Remembered across reloads like the session is -- someone who silenced a
  /// laptop at a dinner table does not want it back after an F5.
  final ValueNotifier<bool> muted;

  /// Kicks off decoding every cue. Cheap enough (under a megabyte) to do all at
  /// once, and it means the first buzzer is never the first time a file loads.
  Future<void> preload() => Future.wait([
    for (final cue in Cue.values)
      _backend.load(cue.file, 'assets/sounds/${cue.file}.wav'),
  ]);

  void toggleMuted() {
    muted.value = !muted.value;
    writeRaw(_mutedKey, muted.value ? '1' : '0');
  }

  void play(Cue cue, {Duration delay = Duration.zero}) {
    if (!_backend.audible) return;
    if (delay > Duration.zero) {
      // Muting is checked again when the timer fires, not only now.
      Timer(delay, () => play(cue));
      return;
    }
    if (muted.value) return;
    _backend.play(cue.file, cue.volume);
  }
}
