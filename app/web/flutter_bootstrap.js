{{flutter_js}}
{{flutter_build_config}}

// Until 2026-10-14 Caddy served main.dart.js as immutable for a year, so a
// browser that loaded it before then never asks for it again, reload or not.
// A per-build query string is a URL that browser has never cached.
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) {
    build.mainJsPath += "?v=" + {{flutter_service_worker_version}};
  }
}

// The same went for everything under assets/, whose names no build changes:
// such a browser draws today's icons from a font tree-shaken before they
// existed, as blanks. /clear-cache answers with Clear-Site-Data, once per
// browser, before the engine asks for any of it.
const CACHE_CLEARED_KEY = "jeopard.cacheCleared.v1";

async function clearStaleCacheOnce() {
  try {
    if (localStorage.getItem(CACHE_CLEARED_KEY)) return;
    const res = await fetch("clear-cache", { cache: "no-store" });
    // A dev server has no such route; asking again next load costs nothing.
    if (res.ok) localStorage.setItem(CACHE_CLEARED_KEY, "1");
  } catch (_) {
    // Storage blocked or offline: start the app regardless.
  }
}

clearStaleCacheOnce().then(() => {
  _flutter.loader.load({
    serviceWorkerSettings: {
      serviceWorkerVersion: {{flutter_service_worker_version}}
    }
  });
});
