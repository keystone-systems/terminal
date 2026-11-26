#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cd "$scratch"
export HOME="$scratch/home" KEYSTONE_STATE_HOME="$scratch/state"
catalog="$repo/templates/themes/.config/themes"
for theme in "$catalog"/*; do
  for file in zellij.kdl helix.toml btop.theme lazygit.yml; do
    test -s "$theme/$file"
  done
done

helix_theme="$HOME/.config/helix/themes/current.toml"
export KEYSTONE_THEME_CATALOGS=$'terminal\t'"$catalog"
export KEYSTONE_THEME_ADAPTERS=$'helix.toml\t'"$helix_theme"
selector="$repo/modules/terminal/theme-selector.sh"
bash "$selector" select tokyo-night
test "$(bash "$selector" current)" = tokyo-night
jq -e 'any(.themes[]; .name == "tokyo-night" and .current)' < <(bash "$selector" list-json)
bash "$selector" select kanagawa
test -L "$helix_theme"
cmp "$catalog/kanagawa/helix.toml" "$helix_theme"

for command in zide zide-pick zide-edit zide-rename; do
  bash "$repo/packages/zide/bin/$command" --help >/dev/null
done

bash "$repo/tests/retired-agent-assets-cleanup.sh" "$repo/modules/terminal/agents/cleanup-retired-agent-assets.sh"
