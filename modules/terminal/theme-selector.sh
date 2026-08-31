#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: keystone-theme-selector <current|list-json|backgrounds-json|gc|reconcile DEFAULT_THEME|select THEME|select-background BACKGROUND|refresh>" >&2
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

generation_cleanup_path=""
generation_final_cleanup_path=""
generation_reservation_path=""
generation_reservation_token=""
generation_list_path=""
current_link_temporary_path=""
metadata_temporary_path=""
composed_generation=""
composed_final_generation=""
composed_reservation_token=""

owned_path_is_current() {
  local path="$1" current_path owned_path
  [[ -n "$path" && -L "$current_theme" ]] || return 1
  current_path="$(readlink -f "$current_theme")" || return 1
  owned_path="$(readlink -f "$path")" || return 1
  [[ "$current_path" == "$owned_path" ]]
}

reservation_is_owned() {
  local token
  [[ -n "$generation_reservation_path" && -n "$generation_reservation_token" \
    && -f "$generation_reservation_path" && ! -L "$generation_reservation_path" ]] || return 1
  token="$(cat -- "$generation_reservation_path")" || return 1
  [[ "$token" == "$generation_reservation_token" ]]
}

reservation_writer_status() {
  local path="$1" token pid
  [[ -f "$path" && ! -L "$path" ]] || return 2
  token="$(cat -- "$path")" || return 2
  [[ "$token" =~ ^([1-9][0-9]*):[0-9]+:[0-9]+:[0-9]+$ ]] || return 2
  pid="${BASH_REMATCH[1]}"
  kill -0 "$pid" 2>/dev/null && return 0
  return 1
}

owned_stage_exists() {
  [[ -n "$generation_cleanup_path" && -d "$generation_cleanup_path" \
    && ! -L "$generation_cleanup_path" ]]
}

cleanup_generation_on_exit() {
  local failed=0
  if [[ -n "$generation_cleanup_path" ]] \
    && ! owned_path_is_current "$generation_cleanup_path" \
    && ! rm -rf -- "$generation_cleanup_path"; then
    printf 'Cleanup warning: could not remove owned path: %s\n' "$generation_cleanup_path" >&2
    failed=1
  fi
  if [[ -n "$generation_final_cleanup_path" ]] \
    && ! owned_path_is_current "$generation_final_cleanup_path" \
    && ! rm -rf -- "$generation_final_cleanup_path"; then
    printf 'Cleanup warning: could not remove promoted path: %s\n' "$generation_final_cleanup_path" >&2
    failed=1
  fi
  if reservation_is_owned && ! rm -f -- "$generation_reservation_path"; then
    printf 'Cleanup warning: could not remove reservation: %s\n' "$generation_reservation_path" >&2
    failed=1
  fi
  if [[ -n "$generation_list_path" ]] && ! rm -f -- "$generation_list_path"; then
    printf 'Cleanup warning: could not remove temporary list: %s\n' "$generation_list_path" >&2
    failed=1
  fi
  if [[ -n "$current_link_temporary_path" ]] && ! rm -f -- "$current_link_temporary_path"; then
    printf 'Cleanup warning: could not remove temporary current link: %s\n' "$current_link_temporary_path" >&2
    failed=1
  fi
  if [[ -n "$metadata_temporary_path" ]] && ! rm -f -- "$metadata_temporary_path"; then
    printf 'Cleanup warning: could not remove temporary metadata: %s\n' "$metadata_temporary_path" >&2
    failed=1
  fi
  return "$failed"
}

cleanup_generation_at_exit() {
  local status="$1"
  cleanup_generation_on_exit || true
  return "$status"
}

cleanup_generation_on_signal() {
  local signal="$1" status="$2" shell_pid="${BASHPID:-$$}"
  cleanup_generation_on_exit || true
  trap - EXIT HUP INT TERM
  kill -s "$signal" "$shell_pid"
  exit "$status"
}

own_generation_cleanup() {
  generation_cleanup_path="$1"
  generation_reservation_path="${2:-}"
  generation_list_path="${3:-}"
  generation_reservation_token="${4:-}"
  install_cleanup_traps
}

disown_reservation_cleanup() {
  generation_reservation_path=""
  generation_reservation_token=""
  clear_cleanup_traps_if_unowned
}

remove_owned_reservation() {
  reservation_is_owned || return 1
  rm -f -- "$generation_reservation_path"
}

install_cleanup_traps() {
  trap 'cleanup_generation_at_exit "$?"' EXIT
  trap 'cleanup_generation_on_signal HUP 129' HUP
  trap 'cleanup_generation_on_signal INT 130' INT
  trap 'cleanup_generation_on_signal TERM 143' TERM
}

clear_cleanup_traps_if_unowned() {
  if [[ -z "$generation_cleanup_path" && -z "$generation_final_cleanup_path" \
    && -z "$generation_reservation_path" \
    && -z "$generation_list_path" && -z "$current_link_temporary_path" \
    && -z "$metadata_temporary_path" ]]; then
    trap - EXIT HUP INT TERM
  fi
}

clear_generation_cleanup() {
  generation_cleanup_path=""
  generation_final_cleanup_path=""
  generation_reservation_path=""
  generation_reservation_token=""
  generation_list_path=""
  current_link_temporary_path=""
  metadata_temporary_path=""
  trap - EXIT HUP INT TERM
}

track_current_link_temporary() {
  current_link_temporary_path="$1"
  install_cleanup_traps
}

clear_current_link_temporary() {
  current_link_temporary_path=""
  clear_cleanup_traps_if_unowned
}

track_metadata_temporary() {
  metadata_temporary_path="$1"
  install_cleanup_traps
}

create_tracked_metadata_temporary() {
  local template="$1"
  trap '' HUP INT TERM
  metadata_temporary_path=""
  if ! metadata_temporary_path="$(mktemp "$template")"; then
    install_cleanup_traps
    return 1
  fi
  install_cleanup_traps
}

clear_metadata_temporary() {
  metadata_temporary_path=""
  clear_cleanup_traps_if_unowned
}

discard_owned_generation() {
  local cleanup_status=0
  cleanup_generation_on_exit || cleanup_status=$?
  clear_generation_cleanup
  return "$cleanup_status"
}

state_home="${KEYSTONE_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}}"
themes_state="$state_home/keystone/themes"
generations="$themes_state/generations"
current_theme="$themes_state/current"
required_paths="${KEYSTONE_THEME_REQUIRED_PATHS-zellij.kdl:helix.toml:btop.theme:lazygit.yml}"
catalog_spec="${KEYSTONE_THEME_CATALOGS:-}"
hook_spec="${KEYSTONE_THEME_HOOKS:-}"
render_hook_spec="${KEYSTONE_THEME_RENDER_HOOKS:-}"
adapter_spec="${KEYSTONE_THEME_ADAPTERS:-}"

declare -a catalog_names=()
declare -a catalog_paths=()
declare -a adapter_sources=()
declare -a adapter_targets=()

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

load_adapters() {
  local source target
  [[ -n "$adapter_spec" ]] || fail "No theme adapters are configured"
  while IFS=$'\t' read -r source target; do
    [[ -n "$source" && -n "$target" ]] || fail "Theme adapter entries must contain a source and target"
    [[ "$source" != /* && "$source" != *..* ]] || fail "Theme adapter source is not valid: $source"
    adapter_sources+=("$source")
    adapter_targets+=("$target")
  done <<< "$adapter_spec"
}

available_themes() {
  local catalog entry name broken_link list_dir entries_list themes_list sorted_list themes_output
  list_dir="$(mktemp -d "${TMPDIR:-/tmp}/keystone-theme-list.XXXXXX")" \
    || fail "Could not create a temporary theme list directory"
  own_generation_cleanup "$list_dir"
  entries_list="$list_dir/entries"
  themes_list="$list_dir/themes"
  sorted_list="$list_dir/sorted"
  : > "$themes_list" || fail "Could not initialize the temporary theme list"
  for catalog in "${catalog_paths[@]}"; do
    if ! find -L "$catalog" -mindepth 1 -maxdepth 1 -type d -print0 > "$entries_list"; then
      fail "Could not enumerate theme catalog: $catalog"
    fi
    while IFS= read -r -d '' entry; do
      name="${entry##*/}"
      valid_name "$name" || fail "Theme name is not valid: $name"
      printf '%s\n' "$name" >> "$themes_list" \
        || fail "Could not append to the temporary theme list"
    done < "$entries_list"
    broken_link="$(find "$catalog" -xtype l -print -quit)" \
      || fail "Could not inspect theme catalog: $catalog"
    if [[ -n "$broken_link" ]]; then
      fail "Theme catalog contains a broken symbolic link: $broken_link"
    fi
  done
  if ! LC_ALL=C sort -u "$themes_list" > "$sorted_list"; then
    fail "Could not sort the temporary theme list"
  fi
  themes_output="$(cat "$sorted_list")" || fail "Could not read the temporary theme list"
  discard_owned_generation
  [[ -z "$themes_output" ]] || printf '%s\n' "$themes_output"
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
  local theme="$1" generation="" final_generation="" reservation_path="" entry_list=""
  local catalog source relative destination entry_type existing_type hook
  local rendered_symlink rendered_hardlink broken_link required_file catalogs_json metadata_path background_list
  local background="" suffix reservation_token=""
  local i attempt=0
  local -a used_catalogs=() paths=()
  composed_generation=""
  composed_final_generation=""
  composed_reservation_token=""
  valid_name "$theme" || fail "Theme name is not valid: $theme"
  theme_exists "$theme" || fail "Theme does not exist in any catalog: $theme"
  mkdir -p "$generations" || fail "Could not create the theme generations directory: $generations"
  [[ -w "$generations" ]] || fail "Could not create a staged theme generation in: $generations"

  while :; do
    printf -v suffix '%06d' "$attempt"
    final_generation="$generations/$theme.$suffix"
    reservation_path="$generations/.$theme.$suffix.reserve"
    generation="$generations/.$theme.$suffix.stage"
    if [[ -e "$final_generation" || -L "$final_generation" \
      || -e "$generation" || -L "$generation" ]]; then
      ((attempt += 1))
      continue
    fi
    reservation_token="${BASHPID:-$$}:$RANDOM:$RANDOM:$attempt"
    own_generation_cleanup "" "$reservation_path" "" "$reservation_token"
    if ! (set -o noclobber; printf '%s\n' "$reservation_token" > "$reservation_path") 2>/dev/null; then
      disown_reservation_cleanup
      if [[ -e "$reservation_path" || -L "$reservation_path" ]]; then
        ((attempt += 1))
        continue
      fi
      fail "Could not create theme generation reservation: $reservation_path"
    fi
    reservation_is_owned || fail "Could not verify theme generation reservation ownership: $reservation_path"
    if [[ -e "$final_generation" || -L "$final_generation" \
      || -e "$generation" || -L "$generation" ]]; then
      remove_owned_reservation \
        || fail "Could not release a collided theme generation reservation: $reservation_path"
      disown_reservation_cleanup
      ((attempt += 1))
      continue
    fi
    break
  done

  own_generation_cleanup "$generation" "$reservation_path" "" "$reservation_token"
  mkdir -- "$generation" || fail "Could not create a staged theme generation in: $generations"
  owned_stage_exists || fail "Could not verify staged theme generation ownership: $generation"
  entry_list="$generation.entries"
  own_generation_cleanup "$generation" "$reservation_path" "$entry_list" "$reservation_token"

  for ((i=0; i<${#catalog_paths[@]}; i++)); do
    catalog="${catalog_paths[$i]}"
    [[ -d "$catalog/$theme" ]] || continue
    used_catalogs+=("${catalog_names[$i]}")
    if ! find -L "$catalog/$theme" -mindepth 1 -print0 > "$entry_list"; then
      fail "Could not enumerate theme catalog entries: $catalog/$theme"
    fi
    if ! LC_ALL=C sort -z "$entry_list" -o "$entry_list"; then
      fail "Could not sort theme catalog entries: $catalog/$theme"
    fi
    broken_link="$(find "$catalog/$theme" -xtype l -print -quit)" \
      || fail "Could not inspect theme catalog path: $catalog/$theme"
    if [[ -n "$broken_link" ]]; then
      fail "Theme contains a broken symbolic link: $broken_link"
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
        mkdir -p "$destination" \
          || fail "Could not create staged theme directory: $relative"
      else
        mkdir -p "$(dirname "$destination")" \
          || fail "Could not create staged theme parent directory: $relative"
        cp -fL -- "$source" "$destination" \
          || fail "Could not materialize theme path: $relative"
        chmod u+w -- "$destination" \
          || fail "Could not make staged theme path writable: $relative"
      fi
    done < "$entry_list"
  done
  rm -f -- "$entry_list" || fail "Could not remove the temporary catalog entry list: $entry_list"
  generation_list_path=""

  validate_render_hooks
  while IFS= read -r hook; do
    [[ -n "$hook" ]] || continue
    "$hook/bin/keystone-theme-render" "$theme" "$generation" </dev/null >&2 \
      || fail "Theme render hook failed: $hook"
    if [[ -e "$generation/.keystone-theme.json" || -L "$generation/.keystone-theme.json" ]]; then
      fail "Theme render hook created reserved metadata path .keystone-theme.json: $hook"
    fi
    rendered_symlink="$(find "$generation" -type l -print -quit)" \
      || fail "Could not inspect the staged generation after render hook: $hook"
    if [[ -n "$rendered_symlink" ]]; then
      fail "Theme render hook MUST NOT leave symbolic links in staged generation: $hook: ${rendered_symlink#"$generation/"}"
    fi
    rendered_hardlink="$(find "$generation" -type f -links +1 -print -quit)" \
      || fail "Could not inspect staged file links after render hook: $hook"
    if [[ -n "$rendered_hardlink" ]]; then
      fail "Theme render hook MUST NOT leave hard-linked files in staged generation: $hook: ${rendered_hardlink#"$generation/"}"
    fi
  done <<< "$render_hook_spec"

  IFS=: read -r -a paths <<< "$required_paths"
  paths+=("${adapter_sources[@]}")
  for relative in "${paths[@]}"; do
    [[ "$relative" != "." ]] || continue
    [[ -n "$relative" ]] || fail "Required theme paths MUST NOT contain empty entries"
    [[ -e "$generation/$relative" ]] || fail "Theme does not contain required path $relative: $theme"
    if [[ -d "$generation/$relative" ]]; then
      required_file="$(find -L "$generation/$relative" -type f -print -quit)" \
        || fail "Could not inspect required theme directory: $generation/$relative"
      [[ -n "$required_file" ]] || fail "Required theme directory is empty: $generation/$relative"
    else
      [[ -s "$generation/$relative" ]] || fail "Required theme file is empty: $relative"
    fi
  done

  if [[ -d "$generation/backgrounds" ]]; then
    background_list="$generation.backgrounds"
    generation_list_path="$background_list"
    if ! find -L "$generation/backgrounds" -type f -printf '%P\n' > "$background_list"; then
      fail "Could not enumerate staged theme backgrounds: $generation/backgrounds"
    fi
    if ! LC_ALL=C sort "$background_list" -o "$background_list"; then
      fail "Could not sort staged theme backgrounds: $generation/backgrounds"
    fi
    IFS= read -r background < "$background_list" || true
    rm -f -- "$background_list" \
      || fail "Could not remove the temporary background list: $background_list"
    generation_list_path=""
    [[ -z "$background" ]] || background="backgrounds/$background"
  fi
  catalogs_json="$(printf '%s\n' "${used_catalogs[@]}" | jq -Rsc 'split("\n")[:-1]')" \
    || fail "Could not encode theme generation catalog metadata"
  create_tracked_metadata_temporary "$themes_state/.${theme}.${suffix}.metadata.XXXXXX" \
    || fail "Could not create temporary theme generation metadata in: $themes_state"
  metadata_path="$metadata_temporary_path"
  if ! jq -n --arg theme "$theme" --arg background "$background" \
    --argjson catalogs "$catalogs_json" \
    '{theme:$theme,catalogs:$catalogs,background:$background}' > "$metadata_path"; then
    fail "Could not write theme generation metadata: $metadata_path"
  fi
  mv -f -- "$metadata_path" "$generation/.keystone-theme.json" \
    || fail "Could not install theme generation metadata: $generation/.keystone-theme.json"
  clear_metadata_temporary
  composed_generation="$generation"
  composed_final_generation="$final_generation"
  composed_reservation_token="$reservation_token"
}

validate_adapters() {
  local path parent
  for path in "${adapter_targets[@]}"; do
    if [[ ( -e "$path" || -L "$path" ) && ! -L "$path" ]]; then
      fail "Theme adapter must be a symbolic link: $path"
    fi
    parent="$(dirname "$path")"
    mkdir -p "$parent" || fail "Could not create theme adapter parent directory: $parent"
  done
}

validate_hooks() {
  local hook
  [[ -z "$hook_spec" ]] && return 0
  while IFS= read -r hook; do
    [[ -n "$hook" ]] || continue
    [[ -x "$hook/bin/keystone-theme-hook" ]] \
      || fail "Post-switch hook does not provide executable bin/keystone-theme-hook: $hook"
  done <<< "$hook_spec"
}

validate_render_hooks() {
  local hook
  [[ -z "$render_hook_spec" ]] && return 0
  while IFS= read -r hook; do
    [[ -n "$hook" ]] || continue
    [[ -x "$hook/bin/keystone-theme-render" ]] \
      || fail "Theme render hook does not provide executable bin/keystone-theme-render: $hook"
  done <<< "$render_hook_spec"
}

link_adapters() {
  local i
  for ((i=0; i<${#adapter_sources[@]}; i++)); do
    if [[ "${adapter_sources[$i]}" == "." ]]; then
      ln -sfn "$current_theme" "${adapter_targets[$i]}" || return 1
    else
      ln -sfn "$current_theme/${adapter_sources[$i]}" "${adapter_targets[$i]}" || return 1
    fi
  done
}

unlink_adapters() {
  local path failed=0
  for path in "${adapter_targets[@]}"; do
    [[ -e "$path" || -L "$path" ]] || continue
    if [[ ! -L "$path" ]]; then
      failed=1
      continue
    fi
    rm -f -- "$path" || failed=1
  done
  return "$failed"
}

run_hooks() {
  local theme="$1" path="$2" hook
  [[ -z "$hook_spec" ]] && return 0
  while IFS= read -r hook; do
    [[ -n "$hook" ]] || continue
    "$hook/bin/keystone-theme-hook" "$theme" "$path" </dev/null || return 1
  done <<< "$hook_spec"
}

restore_generation() {
  local old_path="$1" temporary="$2"
  if [[ -n "$old_path" ]]; then
    track_current_link_temporary "$temporary"
    if ! ln -sfn "$old_path" "$temporary"; then
      clear_current_link_temporary
      return 1
    fi
    if ! mv -Tf "$temporary" "$current_theme"; then
      rm -f -- "$temporary" || true
      clear_current_link_temporary
      return 1
    fi
    clear_current_link_temporary
  else
    rm -f "$current_theme" || return 1
    unlink_adapters || true
    return 0
  fi
  link_adapters || true
}

activate_generation() {
  local theme="$1" generation="$2" final_generation="$3" reservation_token="$4"
  local old_path="" old_theme="" temporary staged_name reservation_path
  reservation_path="$generations/.${final_generation##*/}.reserve"
  own_generation_cleanup "$generation" "$reservation_path" "" "$reservation_token"
  if [[ -e "$current_theme" && ! -L "$current_theme" ]]; then fail "Current theme must be a symbolic link: $current_theme"; fi
  if [[ -L "$current_theme" ]]; then
    old_path="$(readlink -f "$current_theme" || true)"
    [[ -n "$old_path" && -d "$old_path" ]] || fail "Current theme is a broken symbolic link"
    old_theme="$(metadata_value "$old_path" theme || true)"
  fi
  validate_adapters
  staged_name="${generation##*/}"
  [[ "$staged_name" == .* ]] || fail "Staged theme generation name is not hidden: $staged_name"
  [[ "$final_generation" == "$generations/"* ]] \
    || fail "Reserved theme generation is outside the generations directory: $final_generation"
  reservation_is_owned || fail "Theme generation reservation ownership changed: $reservation_path"
  [[ ! -e "$final_generation" && ! -L "$final_generation" ]] \
    || fail "Final theme generation already exists: $final_generation"
  generation_final_cleanup_path="$final_generation"
  mv -T -- "$generation" "$final_generation" \
    || fail "Could not promote staged theme generation: $generation"
  generation_cleanup_path=""
  generation="$final_generation"
  temporary="$themes_state/.current.$$"
  track_current_link_temporary "$temporary"
  ln -sfn "$generation" "$temporary" \
    || fail "Could not create temporary current theme link: $temporary"
  if ! mv -Tf "$temporary" "$current_theme"; then
    rm -f -- "$temporary" || true
    clear_current_link_temporary
    fail "Could not activate theme generation: $generation"
  fi
  clear_current_link_temporary
  generation_final_cleanup_path=""
  remove_owned_reservation \
    || fail "Could not release theme generation reservation: $reservation_path"
  disown_reservation_cleanup
  if ! link_adapters; then
    own_generation_cleanup "$generation"
    if ! restore_generation "$old_path" "$temporary"; then
      clear_generation_cleanup
      fail "A theme adapter could not be installed and the previous theme could not be restored; retained the newly activated generation"
    fi
    fail "A theme adapter could not be installed; restored the previous theme"
  fi
  if ! run_hooks "$theme" "$generation"; then
    own_generation_cleanup "$generation"
    if ! restore_generation "$old_path" "$temporary"; then
      clear_generation_cleanup
      fail "A post-switch hook failed and the previous theme could not be restored; retained the newly activated generation"
    fi
    if [[ -n "$old_path" ]]; then run_hooks "$old_theme" "$old_path" || true; fi
    fail "A post-switch hook failed; restored the previous theme"
  fi
  clear_generation_cleanup
}

select_theme() {
  local theme="$1" generation final_generation reservation_token
  validate_hooks
  compose_theme "$theme"
  generation="$composed_generation"
  final_generation="$composed_final_generation"
  reservation_token="$composed_reservation_token"
  [[ -n "$generation" && -n "$final_generation" ]] || fail "Theme composition did not return a reserved generation"
  [[ "$generation" != "$final_generation" ]] || fail "Theme composition did not return a reserved generation"
  activate_generation "$theme" "$generation" "$final_generation" "$reservation_token"
}

update_background_metadata() {
  local path="$1" background="$2" temporary
  temporary="$(mktemp "$themes_state/.metadata.XXXXXX")" || return 1
  track_metadata_temporary "$temporary"
  if ! chmod --reference="$path/.keystone-theme.json" -- "$temporary"; then
    rm -f -- "$temporary" || true
    clear_metadata_temporary
    return 1
  fi
  if ! jq --arg background "$background" '.background=$background' \
    "$path/.keystone-theme.json" > "$temporary"; then
    rm -f -- "$temporary" || true
    clear_metadata_temporary
    return 1
  fi
  if ! mv -f -- "$temporary" "$path/.keystone-theme.json"; then
    rm -f -- "$temporary" || true
    clear_metadata_temporary
    return 1
  fi
  clear_metadata_temporary
}

refresh_theme() {
  [[ -L "$current_theme" ]] || fail "No current theme is selected"
  local old_path theme old_background generation final_generation reservation_path reservation_token comparison_status
  validate_hooks
  old_path="$(readlink -f "$current_theme")" || return 1
  [[ -d "$old_path" ]] || fail "Current theme is a broken symbolic link"
  theme="$(metadata_value "$old_path" theme)" || return 1
  old_background="$(metadata_value "$old_path" background || true)"
  compose_theme "$theme"
  generation="$composed_generation"
  final_generation="$composed_final_generation"
  reservation_token="$composed_reservation_token"
  [[ -n "$generation" && -n "$final_generation" ]] || fail "Theme composition did not return a reserved generation"
  [[ "$generation" != "$final_generation" ]] || fail "Theme composition did not return a reserved generation"
  reservation_path="$generations/.${final_generation##*/}.reserve"
  own_generation_cleanup "$generation" "$reservation_path" "" "$reservation_token"
  if [[ -n "$old_background" && -e "$generation/$old_background" ]]; then
    update_background_metadata "$generation" "$old_background" \
      || fail "Could not preserve the selected background in the staged generation"
  fi
  if diff -qr --exclude=.keystone-theme.json -- "$old_path" "$generation" >/dev/null; then
    discard_owned_generation
    return 0
  else
    comparison_status=$?
    [[ "$comparison_status" -eq 1 ]] \
      || fail "Could not compare the staged theme with the current generation"
  fi
  activate_generation "$theme" "$generation" "$final_generation" "$reservation_token"
}

gc_generations() {
  local current_path="" generations_path generation generation_path reservation_path
  local list_dir generations_list sorted_list candidates_list candidates_output reservation_status
  if [[ -e "$current_theme" && ! -L "$current_theme" ]]; then
    fail "Current theme must be a symbolic link: $current_theme"
  fi
  if [[ -L "$current_theme" ]]; then
    current_path="$(readlink -f "$current_theme")" \
      || fail "Could not resolve current theme link: $current_theme"
    [[ -d "$current_path" ]] || fail "Current theme is a broken symbolic link"
  fi
  [[ -d "$generations" ]] || return 0
  generations_path="$(readlink -f "$generations")" \
    || fail "Could not resolve the generations directory: $generations"
  if [[ -n "$current_path" && "$current_path" != "$generations_path/"* ]]; then
    fail "Current theme is outside the generations directory: $current_path"
  fi

  list_dir="$(mktemp -d "${TMPDIR:-/tmp}/keystone-theme-gc.XXXXXX")" \
    || fail "Could not create a temporary generation audit directory"
  own_generation_cleanup "$list_dir"
  generations_list="$list_dir/generations"
  sorted_list="$list_dir/sorted"
  candidates_list="$list_dir/candidates"
  : > "$candidates_list" || fail "Could not initialize the generation candidate list"
  if ! find "$generations" -mindepth 1 -maxdepth 1 -type d -print0 > "$generations_list"; then
    fail "Could not enumerate theme generations: $generations"
  fi
  if ! LC_ALL=C sort -z "$generations_list" > "$sorted_list"; then
    fail "Could not sort theme generations: $generations"
  fi
  while IFS= read -r -d '' generation; do
    [[ "${generation##*/}" == .* ]] && continue
    reservation_path="$generations/.${generation##*/}.reserve"
    if [[ -e "$reservation_path" || -L "$reservation_path" ]]; then
      if reservation_writer_status "$reservation_path"; then
        continue
      else
        reservation_status=$?
        [[ "$reservation_status" -eq 1 ]] || continue
      fi
    fi
    generation_path="$(readlink -f "$generation")" \
      || fail "Could not resolve theme generation: $generation"
    [[ -n "$current_path" && "$generation_path" == "$current_path" ]] && continue
    printf 'candidate: %s\n' "$generation_path" >> "$candidates_list" \
      || fail "Could not append to the generation candidate list"
  done < "$sorted_list"
  candidates_output="$(cat "$candidates_list")" \
    || fail "Could not read the generation candidate list"
  discard_owned_generation
  [[ -z "$candidates_output" ]] || printf '%s\n' "$candidates_output"
}

list_json() {
  local current="" theme themes
  if [[ -L "$current_theme" ]]; then current="$(metadata_value "$(readlink -f "$current_theme")" theme || true)"; fi
  themes="$(available_themes)" || return 1
  printf '%s\n' "$themes" | jq -Rsc --arg current "$current" \
    '{themes:(split("\n") | map(select(length > 0) | {name:.,current:(. == $current)}))}'
}

current_theme_name() {
  [[ -L "$current_theme" ]] || fail "No current theme is selected"
  metadata_value "$(readlink -f "$current_theme")" theme
}

current_theme_path() {
  [[ -L "$current_theme" ]] || fail "No current theme is selected"
  local path
  path="$(readlink -f "$current_theme")" || return 1
  [[ -d "$path" ]] || fail "Current theme is a broken symbolic link"
  printf '%s\n' "$path"
}

backgrounds_json() {
  local path theme current_background list_dir backgrounds_list sorted_list backgrounds_output
  path="$(current_theme_path)"
  theme="$(metadata_value "$path" theme)" || return 1
  current_background="$(metadata_value "$path" background || true)"

  if [[ ! -d "$path/backgrounds" ]]; then
    backgrounds_output="$(jq -n --arg theme "$theme" '{theme:$theme,backgrounds:[]}')" \
      || fail "Could not encode the background list"
    printf '%s\n' "$backgrounds_output"
    return 0
  fi

  list_dir="$(mktemp -d "${TMPDIR:-/tmp}/keystone-theme-backgrounds.XXXXXX")" \
    || fail "Could not create a temporary background list directory"
  own_generation_cleanup "$list_dir"
  backgrounds_list="$list_dir/backgrounds"
  sorted_list="$list_dir/sorted"
  if ! find -L "$path/backgrounds" -type f -printf 'backgrounds/%P\n' > "$backgrounds_list"; then
    fail "Could not enumerate current theme backgrounds: $path/backgrounds"
  fi
  if ! LC_ALL=C sort "$backgrounds_list" > "$sorted_list"; then
    fail "Could not sort current theme backgrounds: $path/backgrounds"
  fi
  backgrounds_output="$(jq -Rsc --arg theme "$theme" --arg current "$current_background" \
    '{theme:$theme,backgrounds:(split("\n") | map(select(length > 0) | {path:.,current:(. == $current)}))}' \
    < "$sorted_list")" || fail "Could not encode the background list"
  discard_owned_generation
  printf '%s\n' "$backgrounds_output"
}

select_background() {
  local background="$1" path old_background
  path="$(current_theme_path)"
  old_background="$(metadata_value "$path" background || true)"

  [[ "$background" == backgrounds/* ]] || fail "Background must be inside backgrounds/: $background"
  [[ "$background" != *"/../"* && "$background" != */.. ]] \
    || fail "Background path must not escape backgrounds/: $background"
  [[ -f "$path/$background" ]] || fail "Background does not exist in the current theme: $background"
  validate_hooks

  update_background_metadata "$path" "$background" \
    || fail "Could not update the selected background"
  if ! run_hooks "$(metadata_value "$path" theme)" "$path"; then
    update_background_metadata "$path" "$old_background" \
      || fail "A post-switch hook failed and the previous background could not be restored"
    run_hooks "$(metadata_value "$path" theme)" "$path" || true
    fail "A post-switch hook failed; restored the previous background"
  fi
}

reconcile_theme() {
  local default_theme="$1" selected_path="" selected_theme=""
  if [[ ! -L "$current_theme" ]]; then
    select_theme "$default_theme"
    return
  fi

  selected_path="$(readlink -f "$current_theme" || true)"
  if [[ -z "$selected_path" || ! -d "$selected_path" ]]; then
    rm -f "$current_theme"
    select_theme "$default_theme"
    return
  fi

  selected_theme="$(metadata_value "$selected_path" theme || true)"
  if [[ -n "$selected_theme" ]] && theme_exists "$selected_theme"; then
    refresh_theme
  else
    select_theme "$default_theme"
  fi
}

load_catalogs
load_adapters
case "${1:-}" in
  current) [[ $# -eq 1 ]] || { usage; exit 2; }; current_theme_name ;;
  list-json) [[ $# -eq 1 ]] || { usage; exit 2; }; list_json ;;
  backgrounds-json) [[ $# -eq 1 ]] || { usage; exit 2; }; backgrounds_json ;;
  gc) [[ $# -eq 1 ]] || { usage; exit 2; }; gc_generations ;;
  reconcile) [[ $# -eq 2 ]] || { usage; exit 2; }; reconcile_theme "$2" ;;
  select) [[ $# -eq 2 ]] || { usage; exit 2; }; select_theme "$2" ;;
  select-background) [[ $# -eq 2 ]] || { usage; exit 2; }; select_background "$2" ;;
  refresh) [[ $# -eq 1 ]] || { usage; exit 2; }; refresh_theme ;;
  *) usage; exit 2 ;;
esac
