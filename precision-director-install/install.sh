#!/bin/sh
# precision-director installer — copies the skill + agents into the repo's .claude/.
# Run from the repo root: sh precision-director-install/install.sh
set -e
cd "$(dirname "$0")/.."
mkdir -p .claude/skills/precision-director/references .claude/agents
cp precision-director-install/skills/precision-director/SKILL.md .claude/skills/precision-director/
cp precision-director-install/skills/precision-director/references/*.md .claude/skills/precision-director/references/
cp precision-director-install/agents/*.md .claude/agents/
echo "installed:"
find .claude/skills/precision-director .claude/agents -name "*.md" | sort
echo "You can now delete precision-director-install/ or keep it as the versioned source."
