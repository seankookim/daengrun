<!--
DRAFT — requires 변호사 review before publication. Written 2026-08-08.

Scope note: this is a marketplace where a stranger takes physical custody of a live animal.
The clauses that matter most are custody, liability, and insurance — exactly the ones a model
should not finalize. They are drafted here so counsel edits rather than starts from nothing,
and every genuinely open question is marked inline.

DECIDE BEFORE PUBLICATION:
  1. Insurance. safety.tsx currently says "파일럿 보험 파트너와 협의 중이에요" — honest, and it
     means §7 must say the pilot runs WITHOUT insurance, in plain language, or the policy must
     be signed first. Do not publish a terms document implying coverage that does not exist.
  2. Platform vs. party. §2 currently says 회사 is an intermediary (통신판매중개자). That is the
     standard posture but it interacts with 전자상거래법 duties and with how much control the
     platform exercises over runners (we vet, price, and assign them). Counsel should confirm
     the posture is defensible rather than assumed.
  3. Cancellation/refund percentages in §5 are placeholders matching the current code
     (cancel_owner fee logic in transition-booking) — confirm they are lawful and consistent
     with 청약철회 rules for services.
-->

# 도그스하이 이용약관

시행일: (미정 — 공개 시 확정)

## 제1조 (목적)
이 약관은 도그스하이(이하 "회사")가 제공하는 반려견 러닝 중개 서비스(이하 "서비스")의 이용
조건과 절차, 회사와 이용자의 권리·의무를 정합니다.

## 제2조 (서비스의 성격)
회사는 반려견의 러닝을 원하는 **보호자**와 이를 수행하는 **러너**를 연결하는 중개자입니다.
러닝 자체는 러너가 수행하며, 회사는 거래 당사자가 아닙니다.

<!-- 변호사 확인: 통신판매중개자 지위 고지 문구, 전자상거래법 제20조 준수 형식. 회사가 러너를
     심사·배정하고 요금을 정하므로 순수 중개로 볼 수 있는지 검토 필요. -->

## 제3조 (이용자의 구분)
- **보호자**: 반려견의 러닝을 요청하는 이용자
- **러너**: 러닝을 수행하는 이용자. 회사의 인증 절차를 통과한 경우에만 예약을 수락할 수 있습니다.
- 러너는 회사의 근로자가 아니며, 독립적으로 서비스를 수행합니다.

## 제4조 (예약 및 요금)
1. 요금은 거리와 선택한 옵션에 따라 예약 시점에 확정되며, 결제 전 전액이 표시됩니다.
2. 확정된 예약의 시간 변경은 러너의 수락이 있어야 적용됩니다.
3. 회사는 중개 수수료를 수취하며, 나머지는 러너에게 정산됩니다.

## 제5조 (취소 및 환불)
1. 매칭 전 취소: 전액 환불
2. 러너 확정 후 취소: 러닝 시작까지 남은 시간에 따라 취소 수수료가 부과될 수 있으며, 취소 시점에
   금액이 명시됩니다.
3. 러닝 시작 후에는 취소가 불가능하며, 조기 종료 시 실제 수행된 범위에 따라 정산됩니다.
4. 러너의 사정으로 러닝이 이루어지지 않은 경우 전액 환불됩니다.

<!-- 변호사 확인: 구체 수수료율, 청약철회권 배제 가능 범위(용역 개시 후), 표시 의무. -->

## 제6조 (반려견의 인계와 책임)
1. **인계**: 러닝의 시작과 종료 시점에 보호자와 러너가 각각 인계를 확인합니다. 양측 확인이
   완료된 시점부터 러너가 반려견을 보호·관리할 책임을 집니다.
2. **보호자의 의무**: 보호자는 반려견의 건강 상태, 공격성, 알레르기, 복용 중인 약 등 안전에
   영향을 주는 사항을 사전에 정확히 알려야 합니다. 고지하지 않은 사항으로 발생한 사고에 대해
   보호자가 책임을 집니다.
3. **러너의 의무**: 러너는 반려견의 상태를 살피며 무리한 운동을 시키지 않아야 하고, 이상 징후가
   있으면 즉시 러닝을 중단하고 보호자에게 알려야 합니다.
4. **사고 발생 시**: 즉시 상대방과 회사에 알리고, 필요한 경우 동물병원 진료를 우선합니다.

<!-- 변호사 확인: 수치화된 책임 한도, 과실 분배, 동물보호법상 의무 반영 여부. 이 조항이
     이 서비스에서 가장 중요합니다. -->

## 제7조 (보험)
<!-- 아래는 '보험 미체결' 상태를 정직하게 쓴 초안입니다. 보험 체결 시 전면 교체하십시오.
     앱 화면(safety.tsx)도 같은 사실을 말하고 있어야 합니다 — 두 곳이 어긋나면 안 됩니다. -->
파일럿 기간 동안 회사는 별도의 반려동물 보험을 제공하지 않습니다. 사고 발생 시 제6조에 따른
당사자 간 책임 원칙이 적용됩니다. 보험이 도입되면 시행일 전에 공지하고 이 조항을 개정합니다.

## 제8조 (위치정보 및 촬영)
1. 러닝 중 러너의 위치정보가 수집되어 보호자에게 실시간으로 제공됩니다.
2. 러너가 촬영한 사진은 보호자에게 전달되며, 보호자의 동의 없이 마케팅에 사용하지 않습니다.
3. 상세한 내용은 개인정보처리방침에 따릅니다.

## 제9조 (금지행위)
- 회사를 거치지 않고 직접 거래하여 수수료를 회피하는 행위
- 타인의 반려견을 무단으로 예약하는 행위
- 허위 정보 등록, 타인 사칭, 후기 조작
- 반려견을 학대하거나 방치하는 행위 (즉시 이용 정지 및 관계기관 신고)

## 제10조 (이용 제한)
회사는 이용자가 이 약관을 위반하거나 다른 이용자·반려견의 안전을 위협하는 경우 사전 통지 후
이용을 제한할 수 있습니다. 긴급한 경우 먼저 조치하고 사후에 통지합니다.

## 제11조 (책임의 한계)
회사는 중개자로서 서비스의 안정적 제공을 위해 노력하나, 러너와 보호자 사이에서 발생한 분쟁에
대해서는 원칙적으로 당사자가 책임을 집니다. 다만 회사의 고의 또는 과실이 있는 경우에는 그러하지
아니합니다.

<!-- 변호사 확인: 약관규제법상 무효가 되지 않는 면책 범위. 광범위한 면책 조항은 무효입니다. -->

## 제12조 (약관의 변경)
회사는 이 약관을 변경할 수 있으며, 변경 시 시행일 7일 전(이용자에게 불리한 변경은 30일 전)에
앱 내 공지로 알립니다.

## 제13조 (분쟁 해결)
분쟁이 발생한 경우 당사자 간 협의를 우선하며, 협의가 이루어지지 않으면 관계 법령이 정하는
절차에 따릅니다.
