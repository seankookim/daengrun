// 드랍 오픈 — 로직은 handler.ts, 이 파일은 배선뿐이다 (confirm-payment/index.ts 와 같은 이유).
// 분리 이유: Deno.serve가 모듈 최상위에서 도는 한 테스트가 이 모듈을 import할 수 없다.
import { admin, handle } from "../_shared/ctx.ts";
import { openDrop } from "./handler.ts";

Deno.serve(handle((req) => openDrop(req, admin())));
