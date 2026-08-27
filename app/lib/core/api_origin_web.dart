import 'package:web/web.dart' as web;

/// The origin the app was served from, e.g. `https://jeopard.example`.
///
/// This is what lets one build run anywhere: served over https the socket URL
/// derives to `wss://`, which a browser requires -- an https page may not open a
/// plain `ws://` socket, and that failure is silent.
String? pageOrigin() {
  try {
    final origin = web.window.location.origin;
    // `file://` pages report "null" as a string.
    if (origin.isEmpty || origin == 'null') return null;
    return origin;
  } catch (_) {
    return null;
  }
}
