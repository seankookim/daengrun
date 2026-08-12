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

  auth = {
    getUser: (jwt: string) => {
      const id = this.users[jwt];
      return Promise.resolve(
        id ? { data: { user: { id } }, error: null } : { data: { user: null }, error: { message: "bad jwt" } },
      );
    },
  };

  rpc(name: string, args: any) {
    this.log.push(`rpc:${name}`);
    const fn = this.rpcs[name];
    if (!fn) return Promise.resolve({ data: null, error: { message: `no rpc ${name}` } });
    const r = fn(args);
    return Promise.resolve({ data: r.data ?? null, error: r.error ?? null });
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

class Q implements PromiseLike<any> {
  private filters: Filter[] = [];
  private returning = false;
  private shape: "many" | "single" | "maybe" = "many";
  private orderBy: { col: string; asc: boolean } | null = null;
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
  in(col: string, vals: any[]) {
    this.filters.push(["in", col, vals]);
    return this;
  }
  order(col: string, opts?: { ascending?: boolean }) {
    this.orderBy = { col, asc: opts?.ascending !== false };
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
      switch (op) {
        case "eq":
          return r[col] === val;
        case "neq":
          return r[col] !== val;
        case "is":
          return val === null ? (r[col] === null || r[col] === undefined) : r[col] === val;
        case "in":
          return (val as any[]).includes(r[col]);
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
      if (this.orderBy) {
        const { col, asc } = this.orderBy;
        out = [...out].sort((a, b) => (a[col] > b[col] ? 1 : a[col] < b[col] ? -1 : 0) * (asc ? 1 : -1));
      }
      if (this.cap !== null) out = out.slice(0, this.cap);
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
