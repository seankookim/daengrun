// 러닝 종료 정산 (0020 + toss-plan §0-ter 수금 분기). 로직은 handler.ts — 이 파일은 배선뿐이다.
// 분리 이유는 confirm-payment와 같다: Deno.serve가 모듈 최상위에서 도는 한 테스트가 import할 수 없다.
import { admin, handle } from "../_shared/ctx.ts";
import { settleRun } from "./handler.ts";

Deno.serve(handle((req) => settleRun(req, admin())));
