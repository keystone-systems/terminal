#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: keystone-theme-selector <list-json|reconcile DEFAULT_THEME|select THEME|refresh>" >&2
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

config_home="${KEYSTONE_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}}"
state_home="${KEYSTONE_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}}"
themes_state="$state_home/keystone/themes"
generations="$themes_state/generations"
current_theme="$themes_state/current"
required_paths="${KEYSTONE_THEME_REQUIRED_PATHS:-zellij.kdl:helix.toml:btop.theme:lazygit.yml}"
catalog_spec="${KEYSTONE_THEME_CATALOGS:-}"
hook_spec="${KEYSTONE_THEME_HOOKS:-}"

declare -a catalog_names=()
declare -a catalog_paths=()

valid_name() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "$1" != current ]]
}

load_catalogs() {
  local name path
  [[ -n "$catalog_spec" ]] || fail "No theme catalogs are configured"
  while IFS=$'\t' read -r name path; do
    [[ -n "$name" && -n "$path" ]] || fail "Theme catalog entries must contain a name and path"
    valid_name "$name" || fail "Theme catalog name is not valid: $name"
    [[ -d "$path" ]] || fail "Theme catalog directory does not exist: $path"
    catalog_names+=("$name")
    catalog_paths+=("${path%/}")
  done <<< "$catalog_spec"
}

available_themes() {
  local catalog entry name
  for catalog in "${catalog_paths[@]}"; do
    while IFS= read -r -d '' entry; do
      name="${entry##*/}"
      valid_name "$name" || fail "Theme name is not valid: $name"
      printf '%s\n' "$name"
    done < <(find -L "$catalog" -mindepth 1 -maxdepth 1 -type d -print0)
    if find "$catalog" -xtype l -print -quit | grep -q .; then
      fail "Theme catalog contains a broken symbolic link: $catalog"
    fi
  done | LC_ALL=C sort -u
}

theme_exists() {
  local theme="$1" catalog
  for catalog in "${catalog_paths[@]}"; do
    [[ -d "$catalog/$theme" ]] && return 0
  done
  return 1
}

metadata_value() {
  local path="$1" key="$2"
  [[ -f "$path/.keystone-theme.json" ]] || return 1
  jq -er ".${key} // empty" "$path/.keystone-theme.json"
}

compose_theme() {
  local theme="$1" generation catalog source relative destination entry_type existing_type
  local -a used_catalogs=()
  valid_name "$theme" || fail "Theme name is not valid: $theme"
  theme_exists "$theme" || fail "Theme does not exist in any catalog: $theme"
  mkdir -p "$generations"
  generation="$(mktemp -d "$generations/.${theme}.XXXXXX")"

  for ((i=0; i<${#catalog_paths[@]}; i++)); do
    catalog="${catalog_paths[$i]}"
    [[ -d "$catalog/$theme" ]] || continue
    used_catalogs+=("${catalog_names[$i]}")
    if find "$catalog/$theme" -xtype l -print -quit | grep -q .; then
      fail "Theme contains a broken symbolic link: $catalog/$theme"
    fi
    while IFS= read -r -d '' source; do
      relative="${source#"$catalog/$theme/"}"
      [[ "$relative" != ".keystone-theme.json" ]] || fail "Theme catalogs MUST NOT provide .keystone-theme.json"
      destination="$generation/$relative"
      if [[ -d "$source" ]]; then
        entry_type="directory"
      else
        entry_type="file"
      fi
      if [[ -e "$destination" || -L "$destination" ]]; then
        if [[ -d "$destination" && ! -L "$destination" ]]; then existing_type="directory"; else existing_type="file"; fi
        [[ "$entry_type" == "$existing_type" ]] || fail "Theme overlay has a file/directory conflict: $relative"
      fi
      if [[ "$entry_type" == directory ]]; then
        mkdir -p "$destination"
      else
        mkdir -p "$(dirname "$destination")"
        ln -sfn "$source" "$destination"
      fi
    done < <(find -L "$catalog/$theme" -mindepth 1 -print0 | LC_ALL=C sort -z)
  done

  IFS=: read -r -a paths <<< "$required_paths"
  for relative in "${paths[@]}"; do
    [[ -n "$relative" ]] || fail "Required theme paths MUST NOT contain empty entries"
    [[ -e "$generation/$relative" ]] || fail "Theme does not contain required path $relative: $theme"
    if [[ -d "$generation/$relative" ]]; then
      find -L "$generation/$relative" -type f -print -quit | grep -q . \
        || fail "Required theme directory is empty: $relative"
    else
      [[ -s "$generation/$relative" ]] || fail "Required theme file is empty: $relative"
    fi
  done

  local background=""
  if [[ -d "$generation/backgrounds" ]]; then
    background="$(find -L "$generation/backgrounds" -type f -printf '%P\n' | LC_ALL=C sort | head -n1 || true)"
    [[ -z "$background" ]] || background="backgrounds/$background"
  fi
  jq -n --arg theme "$theme" --arg background "$background" \
    --argjson catalogs "$(printf '%s\n' "${used_catalogs[@]}" | jq -R . | jq -s .)" \
    '{theme:$theme,catalogs:$catalogs,background:$background}' > "$generation/.keystone-theme.json"
  printf '%s\n' "$generation"
}

validate_adapters() {
  local path
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if [[ ( -e "$path" || -L "$path" ) && ! -L "$path" ]]; then
      fail "Theme adapter must be a symbolic link: $path"
    fi
    mkdir -p "$(dirname "$path")"
  done <<EOF
$config_home/zellij/themes/current.kdl
$config_home/helix/themes/current.toml
$config_home/btop/themes/current.theme
$config_home/keystone/lazygit/current.yml
$config_home/themes/current
EOF
}

link_adapters() {
  local path target
  while IFS=$'\t' read -r path target; do
    [[ -n "$path" ]] || continue
    ln -sfn "$target" "$path" || return 1
  done <<EOF
$config_home/zellij/themes/current.kdl	$current_theme/zellij.kdl
$config_home/helix/themes/current.toml	$current_theme/helix.toml
$config_home/btop/themes/current.theme	$current_theme/btop.theme
$config_home/keystone/lazygit/current.yml	$current_theme/lazygit.yml
EOF
  path="$config_home/themes/current"
  ln -sfn "$current_theme" "$path" || return 1
}

run_hooks() {
  local theme="$1" path="$2" hook
  [[ -z "$hook_spec" ]] && return 0
  while IFS= read -r hook; do
    [[ -n "$hook" ]] || continue
    "$hook/bin/keystone-theme-hook" "$theme" "$path"
  done <<< "$hook_spec"
}

activate_generation() {
  local theme="$1" generation="$2" old_path="" old_theme="" temporary
  if [[ -e "$current_theme" && ! -L "$current_theme" ]]; then fail "Current theme must be a symbolic link: $current_theme"; fi
  if [[ -L "$current_theme" ]]; then
    old_path="$(readlink -f "$current_theme" || true)"
    [[ -n "$old_path" && -d "$old_path" ]] || fail "Current theme is a broken symbolic link"
    old_theme="$(metadata_value "$old_path" theme || true)"
  fi
  validate_adapters
  temporary="$themes_state/.current.$$"
  ln -s "$generation" "$temporary"
  mv -Tf "$temporary" "$current_theme"
  if ! link_adapters; then
    if [[ -n "$old_path" ]]; then
      ln -s "$old_path" "$temporary"
      mv -Tf "$temporary" "$current_theme"
    else
      rm -f "$current_theme"
    fi
    link_adapters || true
    fail "A theme adapter could not be installed; restored the previous theme"
  fi
  if ! run_hooks "$theme" "$generation"; then
    if [[ -n "$old_path" ]]; then
      ln -s "$old_path" "$temporary"
      mv -Tf "$temporary" "$current_theme"
    else
      rm -f "$current_theme"
    fi
    link_adapters || true
    if [[ -n "$old_path" ]]; then run_hooks "$old_theme" "$old_path" || true; fi
    fail "A post-switch hook failed; restored the previous theme"
  fi
}

select_theme() {
  local theme="$1" generation
  generation="$(compose_theme "$theme")" || return 1
  activate_generation "$theme" "$generation"
}

refresh_theme() {
  [[ -L "$current_theme" ]] || fail "No current theme is selected"
  local old_path theme old_background generation
  old_path="$(readlink -f "$current_theme")" || return 1
  [[ -d "$old_path" ]] || fail "Current theme is a broken symbolic link"
  theme="$(metadata_value "$old_path" theme)" || return 1
  old_background="$(metadata_value "$old_path" background || true)"
  generation="$(compose_theme "$theme")" || return 1
  if [[ -n "$old_background" && -e "$generation/$old_background" ]]; then
    jq --arg background "$old_background" '.background=$background' "$generation/.keystone-theme.json" > "$generation/.metadata.tmp"
    mv "$generation/.metadata.tmp" "$generation/.keystone-theme.json"
  fi
  activate_generation "$theme" "$generation"
}

list_json() {
  local current="" theme themes
  if [[ -L "$current_theme" ]]; then current="$(metadata_value "$(readlink -f "$current_theme")" theme || true)"; fi
  themes="$(available_themes)" || return 1
  while IFS= read -r theme; do
    [[ -n "$theme" ]] || continue
    jq -nc --arg name "$theme" --arg current "$current" '{name:$name,current:($name == $current)}'
  done <<< "$themes" | jq -sc '{themes:.}'
}

reconcile_theme() {
  local default_theme="$1" selected_path="" selected_theme=""
  if [[ -L "$current_theme" ]]; then
    selected_path="$(readlink -f "$current_theme" || true)"
    if [[ -n "$selected_path" && -d "$selected_path" ]]; then
      selected_theme="$(metadata_value "$selected_path" theme || true)"
    fi
    if [[ -n "$selected_theme" ]] && theme_exists "$selected_theme"; then
      refresh_theme
    else
      rm -f "$current_theme"
      select_theme "$default_theme"
    fi
  else
    select_theme "$default_theme"
  fi
}

load_catalogs
case "${1:-}" in
  list-json) [[ $# -eq 1 ]] || { usage; exit 2; }; list_json ;;
  reconcile) [[ $# -eq 2 ]] || { usage; exit 2; }; reconcile_theme "$2" ;;
  select) [[ $# -eq 2 ]] || { usage; exit 2; }; select_theme "$2" ;;
  refresh) [[ $# -eq 1 ]] || { usage; exit 2; }; refresh_theme ;;
  *) usage; exit 2 ;;
esac
