import 'sfx_backend_stub.dart'
    if (dart.library.js_interop) 'sfx_backend_web.dart'
    as impl;

/// What actually makes noise. Split from [Sfx] for the same reason
/// [SessionStore] splits off `readRaw`: the web build can reach the browser's
/// Web Audio API through package:web, which is part of the SDK, while every
/// audio *plugin* drags in `path_provider` -> `objective_c` and with it a native
/// asset build that this project deliberately avoids (see the font note in
/// pubspec.yaml, and `flutter test` on a machine with a partial MSVC install).
abstract class SfxBackend {
  /// False where nothing can be heard, so callers skip the work (and any timer
  /// they would have scheduled for a delayed cue) entirely.
  bool get audible;

  /// Decodes the bundled asset at [assetPath] and keeps it under [name].
  /// Must not throw: a sound that fails to load is a sound that stays silent.
  Future<void> load(String name, String assetPath);

  /// Fire-and-forget. Overlapping plays are fine; each one is its own voice.
  /// [volume] is 0..1.
  void play(String name, double volume);
}

SfxBackend createSfxBackend() => impl.createBackend();
