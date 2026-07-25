-- 0011: 러너 스토어프런트 리뷰 공개 — public 러너 리뷰는 모든 로그인 사용자가 읽음
-- (기존 정책은 예약 당사자만 읽을 수 있어 프로필 후기가 타인에게 항상 비어 보였음)
drop policy if exists "reviews storefront read" on reviews;
create policy "reviews storefront read" on reviews
  for select using (visibility = 'public' and target_kind = 'runner');
