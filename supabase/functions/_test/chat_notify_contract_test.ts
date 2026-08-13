// ⑬ 0090's notification title is a cross-language ROUTING CONTRACT, and this pins it.
//
// The title is not decoration: `routeForNotification` (app/src/lib/push.ts) sends a tapped
// `booking` notification to the role's default screen EXCEPT for titles it recognises. So
// 0090 writes '새 메시지' and push.ts matches on '새 메시지' — the same shape as the existing
// RUN_STOP_TITLE, whose own comment warns "한쪽을 바꾸면 둘 다 바꾼다".
//
// Rename it on one side only and NOTHING fails: the trigger keeps writing rows, push keeps
// delivering them, and every tap silently lands on the wrong screen — a runner who taps an
// urgent message gets their calendar. No SQL suite can see the client and no client test can
// see the migration, so the only thing that catches it is reading both.
//
// ⚠ DO NOT "TIDY" THIS BY HOISTING THE LITERAL INTO A SHARED CONSTANT. Reading the migration
// text at test time IS the mechanism: the contract lives in exactly ONE place (0090) and
// TypeScript is verified against it. A constant on this side makes the test pass against the
// copy and reopens the join — an edit that reads as cleanup and would pass review, because
// hoisting a repeated string is normally correct. Here it is backwards.
import { assert, assertEquals } from "jsr:@std/assert@1";

const read = (rel: string) => Deno.readTextFile(new URL(rel, import.meta.url));

Deno.test("[0090 ⑬] the chat notification title is ONE contract, verified against the migration", async () => {
  const [sql, ts] = await Promise.all([
    read("../../migrations/0090_chat_notify.sql"),
    read("../../../app/src/lib/push.ts"),
  ]);

  // The literal the trigger actually inserts — taken from the INSERT, not from a comment,
  // so a stale comment cannot satisfy this test.
  const insertMatch = sql.match(/values\s*\(\s*v_to,\s*'booking',\s*'([^']+)'/);
  assert(insertMatch, "0090 no longer inserts a notification with a literal title — contract moved");
  const sqlTitle = insertMatch![1];

  // → forward: push.ts must route on exactly that string
  const tsMatch = ts.match(/const CHAT_TITLE = '([^']+)'/);
  assert(tsMatch, "push.ts no longer declares CHAT_TITLE");
  assertEquals(
    tsMatch![1],
    sqlTitle,
    `push.ts routes on '${tsMatch![1]}' but 0090 writes '${sqlTitle}' — every tap lands on the wrong screen`,
  );

  // ← reverse: the constant must actually be USED in the router, or the route is dead code
  assert(
    /title === CHAT_TITLE/.test(ts),
    "CHAT_TITLE is declared but never compared in routeForNotification — the chat route is unreachable",
  );

  // and the anti-storm guard must key on the SAME literal the insert uses; if those two drift,
  // the guard stops matching and every message notifies again (0090's N2 pin covers behaviour,
  // this covers the string they share)
  const guardMatch = sql.match(/and n\.title = '([^']+)'/);
  assert(guardMatch, "0090's unread guard no longer filters on a title literal");
  assertEquals(
    guardMatch![1],
    sqlTitle,
    "0090's unread guard and its insert use DIFFERENT titles — the anti-storm rule silently stops matching",
  );
});
