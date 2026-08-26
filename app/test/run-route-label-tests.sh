#!/usr/bin/env bash
# route-label — 이름 속 km 와 옆의 km 가 겹치지 않는다는 성질.
set -euo pipefail
cd "$(dirname "$0")/.."
npx tsx test/route-label.test.ts
