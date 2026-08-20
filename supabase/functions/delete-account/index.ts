// 계정 삭제 (App Store 5.1.1(v)). 로직은 handler.ts — 이 파일은 배선뿐이다.
// 분리 이유는 create-booking-hold·confirm-payment·settle-run과 같다: Deno.serve가 모듈 최상위에서
// 도는 한 테스트가 import할 수 없다.
import { admin, handle } from "../_shared/ctx.ts";
import { deleteAccount } from "./handler.ts";

Deno.serve(handle((req) => deleteAccount(req, admin())));
