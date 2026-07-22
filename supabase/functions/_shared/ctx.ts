// Shared context for Edge Functions: service-role client + caller identity.
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

export const PRICING = {
  baseFare: 9900,
  perKm: 3000,
  minFare: 9900,
  addons: {
    river: 3000,
    homecare: 2000,
    snack: 2000,
    snap: 4000,
  } as Record<string, number>,
};

export function admin(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

export async function caller(req: Request, db: SupabaseClient): Promise<string> {
  const jwt = req.headers.get("Authorization")?.replace("Bearer ", "") ?? "";
  const { data, error } = await db.auth.getUser(jwt);
  if (error || !data.user) throw new HttpError(401, "unauthorized");
  return data.user.id;
}

export class HttpError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

export function handle(fn: (req: Request) => Promise<unknown>) {
  return async (req: Request): Promise<Response> => {
    try {
      const body = await fn(req);
      return Response.json(body ?? { ok: true });
    } catch (e) {
      if (e instanceof HttpError) return Response.json({ error: e.message }, { status: e.status });
      console.error(e);
      return Response.json({ error: "internal" }, { status: 500 });
    }
  };
}
