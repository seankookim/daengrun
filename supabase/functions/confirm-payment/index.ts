// 결제 승인 (toss-plan §2). 로직은 handler.ts — 이 파일은 배선뿐이다.
// 분리 이유: Deno.serve가 모듈 최상위에서 도는 한 테스트가 이 모듈을 import할 수 없다.
import { admin, handle } from "../_shared/ctx.ts";
import { confirmPayment } from "./handler.ts";

Deno.serve(handle((req) => confirmPayment(req, admin())));
