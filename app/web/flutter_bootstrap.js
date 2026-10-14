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
// existed, as blanks. So, once per browser, fetch the manifests and the fonts
// with cache: "reload", which skips the cached copy and replaces it. Capped
// in time: nothing here may keep the app from starting.
const ASSETS_REFRESHED_KEY = "jeopard.assetsRefreshed.v1";
const REFRESH_TIMEOUT_MS = 4000;

async function refreshStaleAssetsOnce() {
  if (localStorage.getItem(ASSETS_REFRESHED_KEY)) return;
  const reload = (path) => fetch(path, { cache: "reload" });
  const fonts = await (await reload("assets/FontManifest.json")).json();
  await Promise.all([
    reload("assets/AssetManifest.bin.json"),
    ...fonts.flatMap((family) =>
      family.fonts.map((font) => reload(encodeURI("assets/" + font.asset))),
    ),
  ]);
  localStorage.setItem(ASSETS_REFRESHED_KEY, "1");
}

Promise.race([
  refreshStaleAssetsOnce().catch(() => {}),
  new Promise((resolve) => setTimeout(resolve, REFRESH_TIMEOUT_MS)),
]).then(() => {
  _flutter.loader.load({
    serviceWorkerSettings: {
      serviceWorkerVersion: {{flutter_service_worker_version}}
    }
  });
});
