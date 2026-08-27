import 'package:web/web.dart' as web;

/// `localStorage`, reached through package:web (part of the SDK, so this adds
/// no dependency). Wrapped in try/catch because a browser in private mode with
/// storage blocked throws rather than returning null.
String? readRaw(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

void writeRaw(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
  } catch (_) {
    // Storage unavailable: the session simply will not survive a reload.
  }
}

void removeRaw(String key) {
  try {
    web.window.localStorage.removeItem(key);
  } catch (_) {}
}
