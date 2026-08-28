export interface IdentifiedMessage { id: number }

/**
 * Merge a server snapshot into the messages already held by the screen.
 *
 * The current item wins an ID collision because it may have arrived from Realtime
 * after the snapshot request began. Later duplicates within either input win, and
 * the result is always ordered by the server-assigned numeric ID.
 */
export function mergeMessageSnapshot<T extends IdentifiedMessage>(current: T[], snapshot: T[]): T[] {
  const byId = new Map<number, T>();
  for (const message of snapshot) byId.set(message.id, message);
  for (const message of current) byId.set(message.id, message);

  const merged = [...byId.values()].sort((a, b) => a.id - b.id);
  return merged.length === current.length && merged.every((message, index) => message === current[index])
    ? current
    : merged;
}
