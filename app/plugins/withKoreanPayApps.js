// Config plugin — makes the Korean card / easy-pay apps *reachable* from this app.
//
// The Toss payment window (SDK path and WebView-fallback path alike) hands off to a card
// company's own app via a custom URL scheme, then that app returns here via our own scheme.
// Neither hop works out of the box:
//   · iOS  — canOpenURL() returns false for any scheme not declared in LSApplicationQueriesSchemes
//            ("canOpenURL: failed for URL" in the console), so the handoff dies silently.
//   · Android 11+ — package visibility hides other apps unless <queries> declares them.
// Both lists come from plugins/korean-pay-schemes.json (single source of truth; see its
// _sources for provenance). Declaring visibility is inert on its own: it grants no permission
// and changes no behavior until something actually opens one of these URLs.
//
// Requires a native rebuild (expo prebuild + a device build) — a JS-only OTA cannot ship it.

const { withInfoPlist, withAndroidManifest } = require('expo/config-plugins');

const { schemes } = require('./korean-pay-schemes.json');
const SCHEMES = schemes.map((s) => s.scheme);

const withIosQueriesSchemes = (config) =>
  withInfoPlist(config, (cfg) => {
    const existing = cfg.modResults.LSApplicationQueriesSchemes ?? [];
    // Union, order-stable — never drop what another plugin (naver map's `nmap`) put there.
    cfg.modResults.LSApplicationQueriesSchemes = [
      ...existing,
      ...SCHEMES.filter((s) => !existing.includes(s)),
    ];
    return cfg;
  });

const withAndroidPackageQueries = (config) =>
  withAndroidManifest(config, (cfg) => {
    const manifest = cfg.modResults.manifest;
    if (!Array.isArray(manifest.queries)) manifest.queries = [{}];
    const q = manifest.queries[0];
    if (!Array.isArray(q.intent)) q.intent = [];

    const already = new Set(
      q.intent
        .flatMap((i) => i.data ?? [])
        .map((d) => d.$?.['android:scheme'])
        .filter(Boolean)
    );

    for (const scheme of SCHEMES) {
      if (already.has(scheme)) continue;
      q.intent.push({
        action: [{ $: { 'android:name': 'android.intent.action.VIEW' } }],
        data: [{ $: { 'android:scheme': scheme } }],
      });
    }
    return cfg;
  });

module.exports = function withKoreanPayApps(config) {
  return withAndroidPackageQueries(withIosQueriesSchemes(config));
};
