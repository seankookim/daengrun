// Private media resolver (0064) — dog/run/chat photos live in the PRIVATE `media` bucket and
// are stored in the DB as bare storage paths ("{uid}/dogs/{dogId}.jpg", optionally "?v=<ts>"
// for cache busting). Legacy rows still hold full public URLs into the avatars bucket; those
// pass through untouched until the one-shot backfill (scripts/migrate-private-media.mjs) runs.
//
// Failure dogma: an expired/unsignable URL is a FAILURE STATE and must look like one.
// <MediaImage> auto-refreshes the signature exactly once on image error, then renders an
// explicit broken-photo tile with a manual retry — no silent placeholder, no retry spam.
import React, { useCallback, useEffect, useState } from 'react';
import { Image, ImageResizeMode, Pressable, StyleProp, StyleSheet, Text, View, ViewStyle } from 'react-native';
import { supabase } from './supabase';

export const MEDIA_BUCKET = 'media';
// Signed URLs live 1 hour. Known and accepted exposure: Supabase validates a signed URL at the
// storage edge by signature + expiry, NOT against live RLS — so a URL signed while a photo was
// visible stays fetchable for up to TTL after the grant is revoked (un-sharing a feed post, or a
// booking party changing, removes no storage object). Club-chat delete is the exception: it also
// removes the object, so even a valid signature 404s. Shorten this if that window ever matters
// more than the re-sign traffic it costs.
const TTL_SEC = 60 * 60;
const REFRESH_MARGIN_MS = 5 * 60 * 1000; // re-sign when less than 5 minutes remain

// A media path is anything that is not already a fetchable URI (http/file/data/asset).
export const isMediaPath = (v: string | null | undefined): v is string =>
  !!v && !/^(https?|file|data|content|asset|ph):/.test(v);

// Signed-URL cache + single-flight — one storage round trip per path per TTL window.
const cache = new Map<string, { url: string; expiresAt: number }>();
const inflight = new Map<string, Promise<string>>();

export async function signMediaPath(value: string, force = false): Promise<string> {
  const [path, query] = value.split('?');
  const hit = cache.get(value);
  if (!force && hit && hit.expiresAt - Date.now() > REFRESH_MARGIN_MS) return hit.url;
  const pending = inflight.get(value);
  if (!force && pending) return pending;
  const p = (async () => {
    const { data, error } = await supabase.storage.from(MEDIA_BUCKET).createSignedUrl(path, TTL_SEC);
    if (error || !data?.signedUrl) throw error ?? new Error('sign failed');
    // keep the ?v= cache-buster in the final URI so RN's image cache sees replacements
    const url = query ? `${data.signedUrl}&${query}` : data.signedUrl;
    cache.set(value, { url, expiresAt: Date.now() + TTL_SEC * 1000 });
    return url;
  })();
  inflight.set(value, p);
  try { return await p; } finally { inflight.delete(value); }
}

// Path → signed URL; legacy full URLs (and local file/data URIs) pass through unchanged.
export async function resolveMediaUrl(value: string): Promise<string> {
  return isMediaPath(value) ? signMediaPath(value) : value;
}

// Hook form. `retry` forces a fresh signature (used for expiry recovery).
export function useMediaUrl(value: string | null | undefined): { uri: string | null; failed: boolean; retry: () => void } {
  const [uri, setUri] = useState<string | null>(isMediaPath(value) ? null : value ?? null);
  const [failed, setFailed] = useState(false);
  const [gen, setGen] = useState(0);
  useEffect(() => {
    let live = true;
    setFailed(false);
    if (!isMediaPath(value)) { setUri(value ?? null); return; }
    signMediaPath(value, gen > 0).then(
      (u) => { if (live) setUri(u); },
      () => { if (live) { setUri(null); setFailed(true); } },
    );
    return () => { live = false; };
  }, [value, gen]);
  const retry = useCallback(() => setGen((g) => g + 1), []);
  return { uri, failed, retry };
}

// Drop-in <Image> replacement for values that may be private media paths.
export function MediaImage({ source, style, resizeMode = 'cover' }: {
  source: string | null | undefined;
  style?: StyleProp<ViewStyle> | any;
  resizeMode?: ImageResizeMode;
}) {
  const { uri, failed, retry } = useMediaUrl(source);
  const [autoTried, setAutoTried] = useState(false);
  const [dead, setDead] = useState(false);
  useEffect(() => { setAutoTried(false); setDead(false); }, [source]);
  if (!source) return null;
  if (failed || dead) {
    return (
      <Pressable
        onPress={() => { setDead(false); setAutoTried(false); retry(); }}
        style={[ms.fail, style]}
      >
        <Text style={ms.failMark}>!</Text>
        <Text style={ms.failText} numberOfLines={2}>사진을 못 불러왔어요{'\n'}눌러서 다시 시도</Text>
      </Pressable>
    );
  }
  if (!uri) return <View style={[ms.loading, style]} />;
  return (
    <Image
      source={{ uri }}
      resizeMode={resizeMode}
      style={style}
      onError={() => {
        // one automatic re-sign for expired signatures, then an explicit failure tile
        if (!autoTried && isMediaPath(source)) { setAutoTried(true); retry(); } else { setDead(true); }
      }}
    />
  );
}

const ms = StyleSheet.create({
  loading: { backgroundColor: '#E3DFD2' },
  fail: { backgroundColor: '#2E2A26', alignItems: 'center', justifyContent: 'center', padding: 6 },
  failMark: { fontSize: 16, marginBottom: 2 },
  failText: { fontSize: 10, fontWeight: '700', color: '#D8D2C4', textAlign: 'center', lineHeight: 13 },
});
