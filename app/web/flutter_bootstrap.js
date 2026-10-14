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

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}}
  }
});
