// In-memory stand-in for the supabase-js client, for edge-function unit tests (toss-plan §4-1).
//
// Why a fake client and not a mocked REST layer: the handlers are written in the repo's normal
// idiom (`db.from(...).update(...).eq(...).select()`), and that idiom IS the thing under test —
// a CAS that forgets its `.eq('status', ...)` is exactly the bug class these tests exist to
// catch. Intercepting HTTP would test PostgREST's URL grammar instead. So this fake implements
// the small slice of the builder the payment functions actually use, and nothing more.
//
// Deliberately NOT implemented: RLS (every edge function runs as service_role, which bypasses
// it — RLS is pinned by `109_payments_suite.sql`, which is the right tool for it), column
// projection (handlers read fields off whole rows), and unique constraints (0071/0076 own those,
// and 109 pins them). Anything this fake cannot see, a SQL pin must.
//
// Directory: `_test` — the supabase CLI skips `functions/` subdirectories that start with `_`,
// the same reason `_shared` is named that way. Nothing here is ever deployed.

// deno-lint-ignore-file no-explicit-any

export type Row = Record<string, any>;

type Filter = [op: string, col: string, val: any];

export class FakeDb {
  tables: Record<string, Row[]> = {};
  /** jwt string → user id. A jwt absent from this map authenticates as nobody (401). */
  users: Record<string, string> = {};
  rpcs: Record<string, (args: any) => { data?: any; error?: { message: string } }> = {};
  /** "table:op" → message. Forces that operation to return an error, for the 500 paths. */
  failures: Record<string, string> = {};
  /** Every mutating operation, in order — the tests assert on this, not on prose. */
  log: string[] = [];

  seed(table: string, rows: Row[]) {
    this.tables[table] = rows.map((r) => ({ ...r }));
    return this;
  }
  rows(table: string): Row[] {
    return this.tables[table] ??= [];
  }
  fail(key: string, message: string) {
    this.failures[key] = message;
    return this;
  }

  /** bucket → object names. The Storage API's world; `storage.objects` is not reachable by PostgREST. */
  objects: Record<string, string[]> = {};
  /** Every path actually handed to `remove()`, in order — so "we did NOT sweep chat" is checkable. */
  removed: string[] = [];

  seedObjects(bucket: string, names: string[]) {
    this.objects[bucket] = [...names];
    return this;
  }

  auth = {
    getUser: (jwt: string) => {
      const id = this.users[jwt];
      return Promise.resolve(
        id ? { data: { user: { id } }, error: null } : { data: { user: null }, error: { message: "bad jwt" } },
      );
    },
    // The Auth admin API — the one thing no SQL path can do, which is why account deletion needs
    // an edge function at all. Fails via `failures["auth:deleteUser"]`, the durable state the
    // retry path exists for.
    admin: {
      deleteUser: (uid: string) => {
        this.log.push(`auth:deleteUser:${uid}`);
        const msg = this.failures["auth:deleteUser"];
        if (msg) return Promise.resolve({ data: null, error: { message: msg } });
        this.deletedUsers.push(uid);
        return Promise.resolve({ data: { user: { id: uid } }, error: null });
      },
    },
  };
  deletedUsers: string[] = [];

  // Storage API. `list(prefix)` mirrors the real one closely enough for the thing under test:
  // it returns the entries DIRECTLY under `prefix`, with a null `id` for pseudo-folders — which
  // is how a folder-scoped sweep stays folder-scoped instead of quietly recursing.
  storage = {
    from: (bucket: string) => ({
      list: (prefix: string, opts?: { limit?: number; offset?: number }) => {
        this.log.push(`storage:list:${bucket}:${prefix}`);
        const msg = this.failures[`storage:${bucket}:list`];
        if (msg) return Promise.resolve({ data: null, error: { message: msg } });
        const base = prefix ? `${prefix}/` : "";
        const seen = new Map<string, { name: string; id: string | null }>();
        for (const name of this.objects[bucket] ?? []) {
          if (!name.startsWith(base)) continue;
          const rest = name.slice(base.length);
          if (rest.length === 0) continue;
          const slash = rest.indexOf("/");
          if (slash === -1) seen.set(rest, { name: rest, id: crypto.randomUUID() });
          else {
            const folder = rest.slice(0, slash);
            if (!seen.has(folder)) seen.set(folder, { name: folder, id: null });
          }
        }
        const all = [...seen.values()];
        const off = opts?.offset ?? 0;
        const lim = opts?.limit ?? all.length;
        return Promise.resolve({ data: all.slice(off, off + lim), error: null });
      },
      remove: (paths: string[]) => {
        this.log.push(`storage:remove:${bucket}:${paths.length}`);
        const msg = this.failures[`storage:${bucket}:remove`];
        if (msg) return Promise.resolve({ data: null, error: { message: msg } });
        this.removed.push(...paths);
        this.objects[bucket] = (this.objects[bucket] ?? []).filter((n) => !paths.includes(n));
        return Promise.resolve({ data: paths.map((n) => ({ name: n })), error: null });
      },
    }),
  };

  // The real rpc builder is thenable AND carries `.single()`/`.maybeSingle()`, which handlers use
  // on `returns table(...)` functions (transition-booking's `marketplace_cancel_fee(...).single()`).
  // Awaiting it directly still yields `{ data, error }` exactly as before; the row-shaping mirrors
  // PostgREST's: `.single()` is an ERROR unless there is exactly one row.
  rpc(name: string, args: any) {
    this.log.push(`rpc:${name}`);
    const run = () => {
      const fn = this.rpcs[name];
      if (!fn) return { data: null, error: { message: `no rpc ${name}` } };
      const r = fn(args);
      return { data: r.data ?? null, error: r.error ?? null };
    };
    const shaped = (shape: "many" | "single" | "maybe") => {
      const r = run();
      if (r.error || shape === "many") return r;
      const list = Array.isArray(r.data) ? r.data : r.data === null ? [] : [r.data];
      if (shape === "single") {
        return list.length === 1
          ? { data: { ...list[0] }, error: null }
          : { data: null, error: { message: `expected 1 row, got ${list.length}` } };
      }
      return { data: list.length ? { ...list[0] } : null, error: null };
    };
    return {
      then: <T1 = any, T2 = never>(
        ok?: ((v: any) => T1 | PromiseLike<T1>) | null,
        err?: ((r: any) => T2 | PromiseLike<T2>) | null,
      ) => Promise.resolve(shaped("many")).then(ok, err),
      single: () => Promise.resolve(shaped("single")),
      maybeSingle: () => Promise.resolve(shaped("maybe")),
    };
  }

  from(table: string) {
    return {
      select: (_cols?: string) => new Q(this, table, "select"),
      insert: (payload: Row | Row[]) => new Q(this, table, "insert", payload),
      update: (payload: Row) => new Q(this, table, "update", payload),
      delete: () => new Q(this, table, "delete"),
    };
  }
}

/**
 * Resolve a PostgREST column reference, including jsonb paths: `raw->kind` (json value) and
 * `raw->>attempts` (TEXT — the `->>` operator's whole point). A plain column name is returned as is.
 *
 * This exists because the charge core CASes on `raw->>attempts` — the dispatch claim — and
 * collect-charges filters on `raw->kind`. A fake that could not see those filters would let a
 * missing CAS pass its own tests, which is the exact bug class this file was written to catch.
 * Missing keys resolve to `undefined`, matching SQL NULL for `is`/`not.is` purposes.
 */
function jsonPath(r: Row, col: string): any {
  if (!col.includes("->")) return r[col];
  const parts = col.split("->");
  let cur: any = r[parts[0]];
  for (let i = 1; i < parts.length; i++) {
    let key = parts[i];
    const asText = key.startsWith(">"); // `->>` split leaves the second `>` on the key
    if (asText) key = key.slice(1);
    key = key.replace(/^'|'$/g, "");
    cur = cur !== null && typeof cur === "object" ? cur[key] : undefined;
    if (asText) return cur === null || cur === undefined ? undefined : String(cur);
  }
  return cur;
}

class Q implements PromiseLike<any> {
  private filters: Filter[] = [];
  private returning = false;
  private shape: "many" | "single" | "maybe" = "many";
  private orderBys: { col: string; asc: boolean }[] = [];
  private offset = 0;
  private cap: number | null = null;

  constructor(
    private db: FakeDb,
    private table: string,
    private op: "select" | "insert" | "update" | "delete",
    private payload?: Row | Row[],
  ) {}

  // On a mutation, `.select()` is PostgREST's "return the affected rows" — the CAS row count
  // the handlers read. On a read it is the projection, which this fake ignores on purpose.
  select(_cols?: string) {
    if (this.op !== "select") this.returning = true;
    return this;
  }
  eq(col: string, val: any) {
    this.filters.push(["eq", col, val]);
    return this;
  }
  neq(col: string, val: any) {
    this.filters.push(["neq", col, val]);
    return this;
  }
  is(col: string, val: any) {
    this.filters.push(["is", col, val]);
    return this;
  }
  // PostgREST's negation: `.not(col, 'is', null)` → `col=not.is.null`. Used by collect-charges to
  // push "this is a server-minted charge intent" (`raw->kind` present) into the QUERY, so
  // BATCH_LIMIT bounds the candidates instead of the whole table.
  not(col: string, op: string, val: any) {
    this.filters.push([`not:${op}`, col, val]);
    return this;
  }
  in(col: string, vals: any[]) {
    this.filters.push(["in", col, vals]);
    return this;
  }
  // Range filters — create-booking-hold's same-dog clash window. ISO timestamp strings compare
  // in chronological order lexicographically, which is exactly what PostgREST does with them.
  gte(col: string, val: any) {
    this.filters.push(["gte", col, val]);
    return this;
  }
  lte(col: string, val: any) {
    this.filters.push(["lte", col, val]);
    return this;
  }
  order(col: string, opts?: { ascending?: boolean }) {
    // PostgREST CHAINS .order calls (primary, then tiebreak); a single-slot model silently made
    // the LAST call the only sort and reordered pages under the paginated candidate walk.
    this.orderBys.push({ col, asc: opts?.ascending !== false });
    return this;
  }
  range(from_: number, to: number) {
    // PostgREST .range(from, to) — inclusive window after ordering. Modeled as offset+limit.
    this.offset = from_;
    this.cap = to - from_ + 1;
    return this;
  }
  limit(n: number) {
    this.cap = n;
    return this;
  }
  single() {
    this.shape = "single";
    return this;
  }
  maybeSingle() {
    this.shape = "maybe";
    return this;
  }

  then<T1 = any, T2 = never>(
    ok?: ((v: any) => T1 | PromiseLike<T1>) | null,
    err?: ((r: any) => T2 | PromiseLike<T2>) | null,
  ): PromiseLike<T1 | T2> {
    return Promise.resolve(this.exec()).then(ok, err);
  }

  private matches(r: Row): boolean {
    return this.filters.every(([op, col, val]) => {
      const cell = jsonPath(r, col);
      switch (op) {
        case "eq":
          return cell === val;
        case "neq":
          return cell !== val;
        case "is":
          return val === null ? (cell === null || cell === undefined) : cell === val;
        case "not:is":
          return val === null ? !(cell === null || cell === undefined) : cell !== val;
        case "not:eq":
          return cell !== val;
        case "not:in": {
          // PostgREST `col=not.in.(a,b,c)` — compare the ->> TEXT form, the way PostgREST does:
          // 0 → "0", false → "false". Parses the parenthesized, comma-separated, quoted list.
          const items = String(val).replace(/^\(|\)$/g, "").split(",")
            .map((x) => x.trim().replace(/^"|"$/g, ""));
          return !items.includes(String(cell));
        }
        case "in":
          return (val as any[]).includes(cell);
        case "gte":
          return cell >= val;
        case "lte":
          return cell <= val;
        default:
          return false;
      }
    });
  }

  private exec() {
    const key = `${this.table}:${this.op}`;
    if (this.db.failures[key]) return this.wrap(null, { message: this.db.failures[key] });

    const store = this.db.rows(this.table);
    let out: Row[] = [];

    if (this.op === "select") {
      out = store.filter((r) => this.matches(r));
      if (this.orderBys.length) {
        out = [...out].sort((a, b) => {
          for (const { col, asc } of this.orderBys) {
            const d = (a[col] > b[col] ? 1 : a[col] < b[col] ? -1 : 0) * (asc ? 1 : -1);
            if (d !== 0) return d;
          }
          return 0;
        });
      }
      if (this.offset || this.cap !== null) out = out.slice(this.offset, this.cap === null ? undefined : this.offset + this.cap);
    } else if (this.op === "insert") {
      const items = (Array.isArray(this.payload) ? this.payload : [this.payload]) as Row[];
      out = items.map((it) => {
        const row: Row = { id: crypto.randomUUID(), created_at: new Date().toISOString(), ...it };
        store.push(row);
        return row;
      });
      this.db.log.push(`insert:${this.table}`);
    } else if (this.op === "update") {
      out = store.filter((r) => this.matches(r));
      for (const r of out) Object.assign(r, this.payload);
      this.db.log.push(`update:${this.table}:${out.length}`);
    } else {
      out = store.filter((r) => this.matches(r));
      this.db.tables[this.table] = store.filter((r) => !this.matches(r));
      this.db.log.push(`delete:${this.table}:${out.length}`);
    }

    const visible = this.op === "select" || this.returning || this.shape !== "many" ? out : [];
    return this.wrap(visible, null);
  }

  private wrap(rows: Row[] | null, error: { message: string } | null) {
    if (error) return { data: null, error };
    const list = rows ?? [];
    if (this.shape === "single") {
      return list.length === 1
        ? { data: { ...list[0] }, error: null }
        : { data: null, error: { message: `expected 1 row, got ${list.length}` } };
    }
    if (this.shape === "maybe") {
      return { data: list.length ? { ...list[0] } : null, error: null };
    }
    return { data: list.map((r) => ({ ...r })), error: null };
  }
}

// ── fetch mocking ──────────────────────────────────────────────────────────────────────────
// One route table, one recorder. Tests assert on `calls` so "we did NOT call cancel" is a
// checkable claim rather than an assumption (the Toss-refused branch depends on it).
export interface FetchCall {
  url: string;
  method: string;
  headers: Record<string, string>;
  body: any;
  /** The abort signal the caller attached, if any — how "this call has a timeout" is checkable. */
  signal: AbortSignal | null;
}

export class FetchMock {
  calls: FetchCall[] = [];
  private original = globalThis.fetch;
  private routes: Array<{ match: (url: string) => boolean; reply: (call: FetchCall, n: number) => Response | Error }> = [];
  private hits = new Map<number, number>();

  on(match: (url: string) => boolean, reply: (call: FetchCall, n: number) => Response | Error) {
    this.routes.push({ match, reply });
    return this;
  }
  /** Convenience: JSON response with a status code. */
  static json(body: unknown, status = 200): Response {
    return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
  }

  install() {
    globalThis.fetch = ((input: any, init?: RequestInit) => {
      const url = typeof input === "string" ? input : input.url;
      const call: FetchCall = {
        url,
        method: init?.method ?? "GET",
        headers: (init?.headers as Record<string, string>) ?? {},
        body: init?.body ? JSON.parse(String(init.body)) : null,
        signal: init?.signal ?? null,
      };
      this.calls.push(call);
      const route = this.routes.find((r) => r.match(url));
      if (!route) return Promise.reject(new Error(`unmocked fetch: ${url}`));
      const idx = this.routes.indexOf(route);
      const n = (this.hits.get(idx) ?? 0) + 1;
      this.hits.set(idx, n);
      const out = route.reply(call, n);
      return out instanceof Error ? Promise.reject(out) : Promise.resolve(out);
    }) as typeof fetch;
    return this;
  }
  restore() {
    globalThis.fetch = this.original;
  }
  countTo(fragment: string) {
    return this.calls.filter((c) => c.url.includes(fragment)).length;
  }
}

// ── request helper ─────────────────────────────────────────────────────────────────────────
export function req(body: unknown, jwt?: string): Request {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (jwt) headers["Authorization"] = `Bearer ${jwt}`;
  return new Request("http://localhost/fn", { method: "POST", headers, body: JSON.stringify(body) });
}
