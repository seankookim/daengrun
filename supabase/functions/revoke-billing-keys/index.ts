// 빌링키 폐기 워커 — 배선뿐이다. 로직은 handler.ts (테스트가 import 할 수 있도록 분리).
import { admin, handle } from "../_shared/ctx.ts";
import { revokeBillingKeys } from "./handler.ts";

Deno.serve(handle((req) => revokeBillingKeys(req, admin())));
