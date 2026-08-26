// 빌링키 등록 — 배선뿐이다. 로직은 handler.ts (Deno.serve가 모듈 최상위에서 도는 한 테스트가
// import할 수 없다 — create-booking-hold·settle-run과 같은 분리 이유).
import { admin, handle } from "../_shared/ctx.ts";
import { registerBillingKey } from "./handler.ts";

Deno.serve(handle((req) => registerBillingKey(req, admin())));
