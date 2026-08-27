/// Non-web platforms: nothing to persist to without a native plugin, and
/// nothing that reloads the way a browser tab does.
String? readRaw(String key) => null;

void writeRaw(String key, String value) {}

void removeRaw(String key) {}
