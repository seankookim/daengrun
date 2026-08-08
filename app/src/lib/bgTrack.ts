// Background location task registration (2026-08-08).
//
// TaskManager.defineTask must run at module scope, before React renders, so the OS can
// dispatch into it — hence the side-effect import from app/_layout.tsx. The require is
// guarded: on a build without expo-task-manager nothing is registered, startTracking finds
// no task, and tracking degrades to the foreground watcher with a stated mode. Nothing crashes.
//
// The handler does exactly one thing: hand the batch to geo.ts's single sink. No arithmetic,
// no network, no React — the batch and the foreground watcher must produce the same km.
import { BG_TASK, GeoPoint, ingestFixes } from './geo';

export { BG_TASK };

try {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const TaskManager = require('expo-task-manager');
  TaskManager.defineTask(BG_TASK, ({ data, error }: { data?: any; error?: any }) => {
    if (error) { console.warn('[bgTrack]', error.message ?? error); return; }
    const locations: any[] = data?.locations ?? [];
    if (locations.length === 0) return;
    const pts: GeoPoint[] = locations.map((loc) => ({
      lat: loc.coords.latitude,
      lng: loc.coords.longitude,
      // OS timestamp, never Date.now(): a batch arrives at one instant but was recorded over
      // minutes, and stamping arrival time would collapse it into a single point.
      t: typeof loc.timestamp === 'number' && loc.timestamp > 0 ? loc.timestamp : Date.now(),
      acc: loc.coords.accuracy ?? undefined,
    }));
    ingestFixes(pts);
  });
} catch {
  // Old build without expo-task-manager — foreground path only.
}
