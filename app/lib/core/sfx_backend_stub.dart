import 'sfx_backend.dart';

/// Non-web platforms: silent. Playing audio there needs a native plugin, which
/// this project does not carry -- see [SfxBackend].
SfxBackend createBackend() => _SilentBackend();

class _SilentBackend implements SfxBackend {
  @override
  bool get audible => false;

  @override
  Future<void> load(String name, String assetPath) async {}

  @override
  void play(String name, double volume) {}
}
