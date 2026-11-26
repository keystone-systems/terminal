#!/usr/bin/env bash
set -euo pipefail

agents_root="$PWD/agents"
user_home="$PWD/home"
mkdir -p "$agents_root/skills/review" \
  "$agents_root/skills/deepwork" \
  "$agents_root/skills/deepplan" \
  "$agents_root/skills/user-review" \
  "$user_home/.gemini/commands"

printf '%s\n' '---' 'name: review' 'description: "legacy review"' '---' "" '# DeepWork Review' > "$agents_root/skills/review/SKILL.md"
printf '%s\n' '---' 'name: deepwork' 'description: "legacy workflow"' '---' "" '# DeepWork workflow manager' > "$agents_root/skills/deepwork/SKILL.md"
printf '%s\n' '---' 'name: user-review' 'description: "user skill"' '---' "" '# User Review' > "$agents_root/skills/user-review/SKILL.md"
printf '%s\n' '---' 'name: deepplan' 'description: "user replacement"' '---' "" '# User replacement' > "$agents_root/skills/deepplan/SKILL.md"
printf '%s\n' \
  'description = "Start or continue DeepWork workflows using MCP tools"' \
  'prompt = "# DeepWork workflow manager"' \
  > "$user_home/.gemini/commands/deepwork.toml"

bash "$1" "$agents_root" "$user_home"

test ! -e "$agents_root/skills/review"
test ! -e "$agents_root/skills/deepwork"
test ! -e "$user_home/.gemini/commands/deepwork.toml"
test -f "$agents_root/skills/user-review/SKILL.md"
test -f "$agents_root/skills/deepplan/SKILL.md"

printf '%s\n' \
  'description = "My DeepWork replacement"' \
  'prompt = "Run my local command"' \
  > "$user_home/.gemini/commands/deepwork.toml"
bash "$1" "$agents_root" "$user_home"
test -f "$user_home/.gemini/commands/deepwork.toml"

