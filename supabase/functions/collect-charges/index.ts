// 수금 재시도 (toss-plan §0-ter). 로직은 handler.ts — 이 파일은 배선뿐이다.
import { admin, handle } from "../_shared/ctx.ts";
import { collectCharges } from "./handler.ts";

Deno.serve(handle((req) => collectCharges(req, admin())));
