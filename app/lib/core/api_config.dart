import 'package:flutter/foundation.dart';

import 'api_origin_stub.dart'
    if (dart.library.js_interop) 'api_origin_web.dart';

/// Where the Spring backend lives.
///
/// On the web the default is **the origin the app was served from**, so one
/// built bundle runs on localhost, on a LAN address and on a deployed domain
/// with no rebuild. That is not just convenience: the socket URL is derived from
/// this, and a page served over https may not open a plain `ws://` socket. If
/// the base were pinned to `http://…` the REST calls would keep working while
/// the buzzer silently died -- which is why the API and the socket are served
/// from the same origin behind one proxy.
///
/// Defaults differ per platform because "localhost" means different things: the
/// Android emulator reaches the host machine at 10.0.2.2, while a real phone
/// needs the machine's LAN address. Override for a physical device, or to point
/// a native build at a deployment, with:
///
///   flutter run --dart-define=API_BASE=http://192.168.1.42:8080
///   flutter build apk --dart-define=API_BASE=https://jeopard.example
class ApiConfig {
  const ApiConfig._();

  static const String _override = String.fromEnvironment('API_BASE');

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    if (kIsWeb) {
      // Served by the same proxy that fronts the API, so the page's own origin
      // is the right base. Falls through only in a unit test, where there is no
      // page at all.
      final origin = pageOrigin();
      if (origin != null) return origin;
      return 'http://localhost:8080';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080';
    }
    return 'http://localhost:8080';
  }

  /// STOMP endpoint. http -> ws, https -> wss.
  static String get wsUrl {
    final base = baseUrl;
    final ws = base.startsWith('https')
        ? base.replaceFirst('https', 'wss')
        : base.replaceFirst('http', 'ws');
    return '$ws/ws';
  }

  /// Shown on the setup screen so a wrong address is obvious immediately.
  static String get describe => baseUrl;
}
