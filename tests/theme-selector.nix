{
  pkgs,
  selector,
  themeSwitch,
  themeActivation,
  wrapperHomeDirectory,
  adapters,
  requiredPaths,
  configHome,
}:

let
  adapterSpec = builtins.concatStringsSep "\n" (
    map (adapter: ''
      printf '%s\t%s/config/%s\n' '${adapter.source}' "$1" '${pkgs.lib.removePrefix "${configHome}/" adapter.target}'
    '') adapters
  );
in
assert pkgs.stdenv.isLinux;
pkgs.runCommand "terminal-theme-selector"
  {
    nativeBuildInputs = [
      selector
      pkgs.jq
    ];
  }
  ''
        make_theme() {
        local root="$1"
        local name="$2"
          mkdir -p "$root/$name"
          printf 'themes { current { fg "#fff" bg "#000" } }\n' > "$root/$name/zellij.kdl"
          printf 'inherits = "base16_default_dark"\n' > "$root/$name/helix.toml"
          printf 'theme[main_bg]="#000000"\n' > "$root/$name/btop.theme"
          printf 'gui: {}\n' > "$root/$name/lazygit.yml"
        }

      run_selector() {
        local selector_required_paths="''${KEYSTONE_THEME_REQUIRED_PATHS-}"
        local selector_hooks="''${SELECTOR_HOOKS-}"
        local selector_render_hooks="''${SELECTOR_RENDER_HOOKS-}"
        [[ -n "$selector_required_paths" ]] \
          || selector_required_paths='${builtins.concatStringsSep ":" requiredPaths}'
        KEYSTONE_STATE_HOME="$1/state" \
          KEYSTONE_THEME_CATALOGS="$(printf 'base\t%s\noverlay\t%s' "$1/base" "$1/overlay")" \
          KEYSTONE_THEME_REQUIRED_PATHS="$selector_required_paths" \
          KEYSTONE_THEME_ADAPTERS="$(adapter_spec "$1")" \
          KEYSTONE_THEME_HOOKS="$selector_hooks" \
          KEYSTONE_THEME_RENDER_HOOKS="$selector_render_hooks" \
          keystone-theme-selector "''${@:2}"
      }

      adapter_spec() {
        ${adapterSpec}
      }

        root="$TMPDIR/layered"
        mkdir -p "$root/base" "$root/overlay"
        make_theme "$root/base" tokyo-night
        make_theme "$root/base" kanagawa
        mkdir -p "$root/base/tokyo-night/backgrounds" "$root/overlay/tokyo-night"
        printf base > "$root/base/tokyo-night/backgrounds/a.jpg"
        printf override > "$root/overlay/tokyo-night/btop.theme"
        find "$root/base" "$root/overlay" -type f -exec chmod 444 {} +

      echo "TEST layered selection"
      run_selector "$root" select tokyo-night
        current="$(readlink -f "$root/state/keystone/themes/current")"
        [[ "''${current##*/}" != .* ]]
        test "$(cat "$current/btop.theme")" = override
        test "$(jq -r .theme "$current/.keystone-theme.json")" = tokyo-night
        test "$(jq -r '.catalogs | join(",")' "$current/.keystone-theme.json")" = base,overlay
        test "$(jq -r .background "$current/.keystone-theme.json")" = backgrounds/a.jpg
    test "$(readlink "$root/config/zellij/themes/current.kdl")" = "$root/state/keystone/themes/current/zellij.kdl"
    test "$(readlink "$root/config/themes/current")" = "$root/state/keystone/themes/current"
      test -z "$(find "$current" -type l -print -quit)"

      echo "TEST generation survives catalog removal"
      mv "$root/base" "$root/base.hidden"
      mv "$root/overlay" "$root/overlay.hidden"
      test "$(cat "$root/config/zellij/themes/current.kdl")" = 'themes { current { fg "#fff" bg "#000" } }'
      test "$(cat "$root/config/btop/themes/current.theme")" = override
      test "$(cat "$root/config/themes/current/backgrounds/a.jpg")" = base
      mv "$root/base.hidden" "$root/base"
      mv "$root/overlay.hidden" "$root/overlay"

      json="$(run_selector "$root" list-json)"
      test "$json" = '{"themes":[{"name":"kanagawa","current":false},{"name":"tokyo-night","current":true}]}'
      test "$(run_selector "$root" current)" = tokyo-night

      echo "TEST retained visible generation name is skipped before rendering"
      retained_collision="$TMPDIR/retained-collision"
      mkdir -p "$retained_collision/base" "$retained_collision/overlay" \
        "$retained_collision/state/keystone/themes/generations/collision.000000"
      make_theme "$retained_collision/base" collision
      printf retained > "$retained_collision/state/keystone/themes/generations/collision.000000/sentinel"
      collision_renderer="$retained_collision/renderer"
      mkdir -p "$collision_renderer/bin"
      printf '%s\n' '#!${pkgs.runtimeShell}' \
        'printf rendered >> "$KEYSTONE_COLLISION_RENDER_LOG"' > "$collision_renderer/bin/keystone-theme-render"
      chmod +x "$collision_renderer/bin/keystone-theme-render"
      SELECTOR_RENDER_HOOKS="$collision_renderer" \
        KEYSTONE_COLLISION_RENDER_LOG="$retained_collision/render.log" \
        run_selector "$retained_collision" select collision
      collision_current="$(readlink -f "$retained_collision/state/keystone/themes/current")"
      test "''${collision_current##*/}" = collision.000001
      test "$(cat "$retained_collision/render.log")" = rendered
      test "$(cat "$retained_collision/state/keystone/themes/generations/collision.000000/sentinel")" = retained
      test -z "$(find "$retained_collision/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -name '.*' -print -quit)"

      echo "TEST independent background selection"
      printf second > "$root/base/tokyo-night/backgrounds/b.jpg"
      run_selector "$root" refresh
      current="$(readlink -f "$root/state/keystone/themes/current")"
      backgrounds="$(run_selector "$root" backgrounds-json)"
      test "$(printf '%s' "$backgrounds" | ${pkgs.jq}/bin/jq -r .theme)" = tokyo-night
      test "$(printf '%s' "$backgrounds" | ${pkgs.jq}/bin/jq -r '[.backgrounds[].path] | join(",")')" = backgrounds/a.jpg,backgrounds/b.jpg
      test "$(printf '%s' "$backgrounds" | ${pkgs.jq}/bin/jq -r '.backgrounds[] | select(.current) | .path')" = backgrounds/a.jpg
      echo "TEST background enumeration failure emits no partial JSON"
      chmod 111 "$current/backgrounds"
      backgrounds_failure_stdout="$root/backgrounds-failure.stdout"
      backgrounds_failure_stderr="$root/backgrounds-failure.stderr"
      if run_selector "$root" backgrounds-json > "$backgrounds_failure_stdout" 2> "$backgrounds_failure_stderr"; then
        chmod 755 "$current/backgrounds"
        echo "FAIL: returned partial JSON after background enumeration failure" >&2
        exit 1
      fi
      chmod 755 "$current/backgrounds"
      test ! -s "$backgrounds_failure_stdout"
      grep -Fq "Could not enumerate current theme backgrounds: $current/backgrounds" "$backgrounds_failure_stderr"
      chmod 640 "$current/.keystone-theme.json"
      run_selector "$root" select-background backgrounds/b.jpg
      test "$(jq -r .background "$current/.keystone-theme.json")" = backgrounds/b.jpg
      test "$(stat -c %a "$current/.keystone-theme.json")" = 640
      if run_selector "$root" select-background backgrounds/missing.jpg; then
        echo "FAIL: accepted a missing background" >&2
        exit 1
      fi
      if run_selector "$root" select-background backgrounds/../btop.theme; then
        echo "FAIL: accepted a background path outside backgrounds/" >&2
        exit 1
      fi
      test "$(jq -r .background "$current/.keystone-theme.json")" = backgrounds/b.jpg

      echo "TEST failed background metadata update leaves no live temporary file"
      cp "$current/.keystone-theme.json" "$root/background-metadata.saved"
      printf 'not json\n' > "$current/.keystone-theme.json"
      generations_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      if run_selector "$root" select-background backgrounds/a.jpg; then
        echo "FAIL: accepted an invalid current metadata document" >&2
        exit 1
      fi
      test "$(cat "$current/.keystone-theme.json")" = 'not json'
      test -z "$(find "$root/state/keystone/themes" -maxdepth 1 -name '.metadata.*' -print -quit)"
      test ! -e "$current/.metadata.tmp"
      mv "$root/background-metadata.saved" "$current/.keystone-theme.json"
      run_selector "$root" reconcile tokyo-night
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$current"
      test "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$generations_before"

      echo "TEST refresh"
      old_generation="$current"
      printf third > "$root/base/tokyo-night/backgrounds/c.jpg"
      generations_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      run_selector "$root" refresh
        refreshed="$(readlink -f "$root/state/keystone/themes/current")"
        test "$refreshed" != "$current"
      test "$(jq -r .background "$refreshed/.keystone-theme.json")" = backgrounds/b.jpg
      test -d "$old_generation"
      [[ "''${old_generation##*/}" != .* ]]
      [[ "''${refreshed##*/}" != .* ]]
      test "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$((generations_before + 1))"

      echo "TEST refresh metadata failure cleanup"
      generations_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      chmod 555 "$root/state/keystone/themes"
      if run_selector "$root" refresh; then
        chmod 755 "$root/state/keystone/themes"
        echo "FAIL: refresh ignored a metadata update failure" >&2
        exit 1
      fi
      chmod 755 "$root/state/keystone/themes"
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$refreshed"
      test "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$generations_before"
      test -z "$(find "$root/state/keystone/themes" -maxdepth 1 -name '.metadata.*' -print -quit)"

      echo "TEST read-only generation gc audit"
      hidden_stage="$root/state/keystone/themes/generations/.in-flight"
      mkdir "$hidden_stage"
      printf staged > "$hidden_stage/sentinel"
      in_flight_generation="$root/state/keystone/themes/generations/in-flight.000000"
      in_flight_reservation="$root/state/keystone/themes/generations/.in-flight.000000.reserve"
      mkdir "$in_flight_generation"
      printf composing > "$in_flight_generation/sentinel"
      printf '%s:1:2:0\n' "$$" > "$in_flight_reservation"
      dead_writer_generation="$root/state/keystone/themes/generations/dead-writer.000000"
      dead_writer_reservation="$root/state/keystone/themes/generations/.dead-writer.000000.reserve"
      malformed_writer_generation="$root/state/keystone/themes/generations/malformed-writer.000000"
      malformed_writer_reservation="$root/state/keystone/themes/generations/.malformed-writer.000000.reserve"
      mkdir "$dead_writer_generation" "$malformed_writer_generation"
      printf '999999999:1:2:0\n' > "$dead_writer_reservation"
      printf 'unknown-writer\n' > "$malformed_writer_reservation"
      gc_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -printf '%P\t%y\t%m\t%s\t%T@\t%l\n' | LC_ALL=C sort)"
      gc_output="$(run_selector "$root" gc)"
      gc_output_again="$(run_selector "$root" gc)"
      gc_after="$(find "$root/state/keystone/themes/generations" -mindepth 1 -printf '%P\t%y\t%m\t%s\t%T@\t%l\n' | LC_ALL=C sort)"
      test "$gc_output" = "$gc_output_again"
      test "$gc_before" = "$gc_after"
      grep -Fqx "candidate: $old_generation" <<< "$gc_output"
      if grep -Fqx "candidate: $refreshed" <<< "$gc_output"; then
        echo "FAIL: gc listed the current generation" >&2
        exit 1
      fi
      if grep -Fq "$hidden_stage" <<< "$gc_output"; then
        echo "FAIL: gc listed a hidden in-flight generation" >&2
        exit 1
      fi
      if grep -Fq "$in_flight_generation" <<< "$gc_output"; then
        echo "FAIL: gc listed a visible generation with a live reservation" >&2
        exit 1
      fi
      grep -Fqx "candidate: $dead_writer_generation" <<< "$gc_output"
      if grep -Fq "$malformed_writer_generation" <<< "$gc_output"; then
        echo "FAIL: gc listed a generation with an unknown reservation writer" >&2
        exit 1
      fi
      test -d "$old_generation"
      test -d "$refreshed"

      echo "TEST gc without a current selection"
      current_target="$(readlink "$root/state/keystone/themes/current")"
      rm -f "$root/state/keystone/themes/current"
      gc_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -printf '%P\t%y\t%m\t%s\t%T@\t%l\n' | LC_ALL=C sort)"
      gc_without_current="$(run_selector "$root" gc)"
      gc_after="$(find "$root/state/keystone/themes/generations" -mindepth 1 -printf '%P\t%y\t%m\t%s\t%T@\t%l\n' | LC_ALL=C sort)"
      test "$gc_before" = "$gc_after"
      grep -Fqx "candidate: $old_generation" <<< "$gc_without_current"
      grep -Fqx "candidate: $refreshed" <<< "$gc_without_current"
      if grep -Fq "$hidden_stage" <<< "$gc_without_current"; then
        echo "FAIL: gc listed hidden staging without a current selection" >&2
        exit 1
      fi
      if grep -Fq "$in_flight_generation" <<< "$gc_without_current"; then
        echo "FAIL: gc listed an in-flight generation without a current selection" >&2
        exit 1
      fi
      grep -Fqx "candidate: $dead_writer_generation" <<< "$gc_without_current"
      if grep -Fq "$malformed_writer_generation" <<< "$gc_without_current"; then
        echo "FAIL: gc listed malformed reservation ownership without a current selection" >&2
        exit 1
      fi
      ln -s "$current_target" "$root/state/keystone/themes/current"

      echo "TEST gc refuses a dangling current selection"
      rm -f "$root/state/keystone/themes/current"
      ln -s "$root/state/keystone/themes/generations/missing" "$root/state/keystone/themes/current"
      gc_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -printf '%P\t%y\t%m\t%s\t%T@\t%l\n' | LC_ALL=C sort)"
      gc_dangling_stderr="$root/gc-dangling.stderr"
      if run_selector "$root" gc > "$root/gc-dangling.stdout" 2> "$gc_dangling_stderr"; then
        echo "FAIL: gc accepted a dangling current selection" >&2
        exit 1
      fi
      grep -Fq 'Current theme is a broken symbolic link' "$gc_dangling_stderr"
      gc_after="$(find "$root/state/keystone/themes/generations" -mindepth 1 -printf '%P\t%y\t%m\t%s\t%T@\t%l\n' | LC_ALL=C sort)"
      test "$gc_before" = "$gc_after"
      rm -f "$root/state/keystone/themes/current"
      ln -s "$current_target" "$root/state/keystone/themes/current"

      echo "TEST gc enumeration failure emits no candidates"
      chmod 111 "$root/state/keystone/themes/generations"
      gc_failure_stdout="$root/gc-failure.stdout"
      gc_failure_stderr="$root/gc-failure.stderr"
      if run_selector "$root" gc > "$gc_failure_stdout" 2> "$gc_failure_stderr"; then
        chmod 755 "$root/state/keystone/themes/generations"
        echo "FAIL: returned partial candidates after generation enumeration failure" >&2
        exit 1
      fi
      chmod 755 "$root/state/keystone/themes/generations"
      test ! -s "$gc_failure_stdout"
      grep -Fq "Could not enumerate theme generations: $root/state/keystone/themes/generations" "$gc_failure_stderr"
      rm -rf "$hidden_stage" "$in_flight_generation" "$dead_writer_generation" "$malformed_writer_generation"
      rm -f "$in_flight_reservation" "$dead_writer_reservation" "$malformed_writer_reservation"

      echo "TEST dangling selection reconciliation"
      rm -f "$root/state/keystone/themes/current"
      ln -s "$root/state/keystone/themes/generations/missing" "$root/state/keystone/themes/current"
      run_selector "$root" reconcile tokyo-night
      reconciled="$(readlink -f "$root/state/keystone/themes/current")"
      test -d "$reconciled"
      test "$(jq -r .theme "$reconciled/.keystone-theme.json")" = tokyo-night

      echo "TEST identical reconciliation reuses the current generation"
      generations_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      run_selector "$root" reconcile tokyo-night
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$reconciled"
      test "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$generations_before"

      echo "TEST valid stale selection remains the rollback anchor"
      stale="$TMPDIR/stale-selection"
      mkdir -p "$stale/base" "$stale/overlay"
      make_theme "$stale/base" retired
      make_theme "$stale/base" fallback
      run_selector "$stale" select retired
      stale_current="$(readlink -f "$stale/state/keystone/themes/current")"
      stale_adapters="$(while IFS=$'\t' read -r source target; do printf '%s\t%s\n' "$target" "$(readlink "$target")"; done < <(adapter_spec "$stale"))"
      mv "$stale/base/retired" "$stale/retired.hidden"
      stale_renderer="$stale/failing-renderer"
      mkdir -p "$stale_renderer/bin"
      printf '%s\n' '#!${pkgs.runtimeShell}' 'exit 1' > "$stale_renderer/bin/keystone-theme-render"
      chmod +x "$stale_renderer/bin/keystone-theme-render"
      generations_before="$(find "$stale/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      if SELECTOR_RENDER_HOOKS="$stale_renderer" run_selector "$stale" reconcile fallback; then
        echo "FAIL: valid stale reconciliation ignored a failing renderer" >&2
        exit 1
      fi
      test "$(readlink -f "$stale/state/keystone/themes/current")" = "$stale_current"
      test "$(while IFS=$'\t' read -r source target; do printf '%s\t%s\n' "$target" "$(readlink "$target")"; done < <(adapter_spec "$stale"))" = "$stale_adapters"
      test "$(find "$stale/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$generations_before"

      echo "TEST hook rollback"
      hook_one="$root/hook-one"
      hook_two="$root/hook-two"
      mkdir -p "$hook_one/bin" "$hook_two/bin"
      printf '%s\n' '#!${pkgs.runtimeShell}' \
        'if IFS= read -r unexpected; then echo "post-switch hook inherited stdin: $unexpected" >&2; exit 2; fi' \
        'if [ "$1" = kanagawa ]; then exit 1; fi' \
        'printf "one:%s\\n" "$1" > "$KEYSTONE_HOOK_LOG"' > "$hook_one/bin/keystone-theme-hook"
      printf '%s\n' '#!${pkgs.runtimeShell}' \
        'printf "two:%s\\n" "$1" >> "$KEYSTONE_HOOK_LOG"' > "$hook_two/bin/keystone-theme-hook"
      chmod +x "$hook_one/bin/keystone-theme-hook" "$hook_two/bin/keystone-theme-hook"
      before="$(readlink -f "$root/state/keystone/themes/current")"
      generations_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      if SELECTOR_HOOKS="$(printf '%s\n%s' "$hook_one" "$hook_two")" \
        KEYSTONE_HOOK_LOG="$root/hook.log" run_selector "$root" select kanagawa; then
        echo "FAIL: ignored a failed post-switch hook" >&2
        exit 1
      fi
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$before"
      test "$(cat "$root/hook.log")" = $'one:tokyo-night\ntwo:tokyo-night'
      test "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$generations_before"

      echo "TEST rollback failure retains the generation named by current"
      restore_failure="$TMPDIR/restore-failure"
      mkdir -p "$restore_failure/base" "$restore_failure/overlay"
      make_theme "$restore_failure/base" old-theme
      make_theme "$restore_failure/base" new-theme
      run_selector "$restore_failure" select old-theme
      restore_failure_hook="$restore_failure/failing-hook"
      mkdir -p "$restore_failure_hook/bin"
      printf '%s\n' '#!${pkgs.runtimeShell}' \
        'chmod 555 "$KEYSTONE_RESTORE_STATE"' \
        'exit 1' > "$restore_failure_hook/bin/keystone-theme-hook"
      chmod +x "$restore_failure_hook/bin/keystone-theme-hook"
      generations_before="$(find "$restore_failure/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      restore_failure_stderr="$restore_failure/stderr"
      if SELECTOR_HOOKS="$restore_failure_hook" \
        KEYSTONE_RESTORE_STATE="$restore_failure/state/keystone/themes" \
        run_selector "$restore_failure" select new-theme 2> "$restore_failure_stderr"; then
        chmod 755 "$restore_failure/state/keystone/themes"
        echo "FAIL: ignored a failed hook and failed rollback" >&2
        exit 1
      fi
      chmod 755 "$restore_failure/state/keystone/themes"
      grep -Fq 'A post-switch hook failed and the previous theme could not be restored; retained the newly activated generation' "$restore_failure_stderr"
      restore_failure_current="$(readlink -f "$restore_failure/state/keystone/themes/current")"
      test -d "$restore_failure_current"
      test "$(jq -r .theme "$restore_failure_current/.keystone-theme.json")" = new-theme
      test "$(find "$restore_failure/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$((generations_before + 1))"
      while IFS=$'\t' read -r source target; do
        test -L "$target"
        test -e "$target"
      done < <(adapter_spec "$restore_failure")

      echo "TEST first-switch hook failure removes adapters"
      first_switch="$TMPDIR/first-switch"
      mkdir -p "$first_switch/base" "$first_switch/overlay"
      make_theme "$first_switch/base" tokyo-night
      first_switch_hook="$first_switch/failing-hook"
      mkdir -p "$first_switch_hook/bin"
      first_switch_race_target=""
      while IFS=$'\t' read -r source target; do
        first_switch_race_target="$target"
        break
      done < <(adapter_spec "$first_switch")
      printf '%s\n' '#!${pkgs.runtimeShell}' \
        'rm -f -- "$KEYSTONE_ADAPTER_RACE_TARGET"' \
        'printf raced > "$KEYSTONE_ADAPTER_RACE_TARGET"' \
        'exit 1' > "$first_switch_hook/bin/keystone-theme-hook"
      chmod +x "$first_switch_hook/bin/keystone-theme-hook"
      if SELECTOR_HOOKS="$first_switch_hook" \
        KEYSTONE_ADAPTER_RACE_TARGET="$first_switch_race_target" \
        run_selector "$first_switch" select tokyo-night; then
        echo "FAIL: first switch ignored a failed post-switch hook" >&2
        exit 1
      fi
      test ! -e "$first_switch/state/keystone/themes/current"
      test ! -L "$first_switch/state/keystone/themes/current"
      test "$(find "$first_switch/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = 0
      while IFS=$'\t' read -r source target; do
        if [[ "$target" = "$first_switch_race_target" ]]; then
          test ! -L "$target"
          test "$(cat "$target")" = raced
        else
          test ! -e "$target"
          test ! -L "$target"
        fi
      done < <(adapter_spec "$first_switch")

      echo "TEST post-switch hook executable preflight"
      missing_hook="$root/missing-hook"
      mkdir -p "$missing_hook/bin"
      before="$(readlink -f "$root/state/keystone/themes/current")"
      generations_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      missing_hook_stderr="$root/missing-hook.stderr"
      if SELECTOR_HOOKS="$missing_hook" \
        run_selector "$root" select kanagawa 2> "$missing_hook_stderr"; then
        echo "FAIL: accepted a missing post-switch hook executable" >&2
        exit 1
      fi
      grep -Fq "Post-switch hook does not provide executable bin/keystone-theme-hook: $missing_hook" "$missing_hook_stderr"
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$before"
      test "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$generations_before"

      echo "TEST adapter conflict rollback"
      adapter="$root/config/btop/themes/current.theme"
      rm -f "$adapter"
      printf user-owned > "$adapter"
      before="$(readlink -f "$root/state/keystone/themes/current")"
      generations_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      if run_selector "$root" select kanagawa; then
        echo "FAIL: replaced a user-owned adapter" >&2
        exit 1
      fi
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$before"
      test "$(cat "$adapter")" = user-owned
      test "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$generations_before"
      rm -f "$adapter"

      echo "TEST adapter parent creation failure is precise"
      adapter_parent_failure="$TMPDIR/adapter-parent-failure"
      mkdir -p "$adapter_parent_failure/base" "$adapter_parent_failure/overlay" \
        "$adapter_parent_failure/config"
      make_theme "$adapter_parent_failure/base" tokyo-night
      printf blocked > "$adapter_parent_failure/config/zellij"
      adapter_parent_stderr="$adapter_parent_failure/stderr"
      if run_selector "$adapter_parent_failure" select tokyo-night 2> "$adapter_parent_stderr"; then
        echo "FAIL: selected a theme with an uncreatable adapter parent" >&2
        exit 1
      fi
      grep -Fq "Could not create theme adapter parent directory: $adapter_parent_failure/config/zellij/themes" "$adapter_parent_stderr"
      test ! -e "$adapter_parent_failure/state/keystone/themes/current"
      test "$(find "$adapter_parent_failure/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = 0

      echo "TEST invalid required-path and catalog entries"
    if KEYSTONE_STATE_HOME="$root/state" \
        KEYSTONE_THEME_CATALOGS="$(printf 'base\t%s' "$root/base")" \
        KEYSTONE_THEME_ADAPTERS="$(printf 'zellij.kdl\t%s' "$root/config/zellij/themes/current.kdl")" \
        KEYSTONE_THEME_REQUIRED_PATHS='zellij.kdl::helix.toml' \
        keystone-theme-selector select tokyo-night; then
        echo "FAIL: accepted an empty required-path entry" >&2
        exit 1
      fi
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$before"
      if KEYSTONE_THEME_CATALOGS="$(printf 'missing\t%s' "$root/missing")" \
        keystone-theme-selector list-json; then
        echo "FAIL: accepted a missing catalog" >&2
        exit 1
      fi

      echo "TEST theme enumeration failure cannot return a truncated list"
      enumeration_failure="$TMPDIR/enumeration-failure"
      mkdir -p "$enumeration_failure/base" "$enumeration_failure/overlay"
      make_theme "$enumeration_failure/base" first
      make_theme "$enumeration_failure/overlay" second
      chmod 000 "$enumeration_failure/overlay"
      enumeration_stdout="$enumeration_failure.stdout"
      enumeration_stderr="$enumeration_failure.stderr"
      if run_selector "$enumeration_failure" list-json > "$enumeration_stdout" 2> "$enumeration_stderr"; then
        chmod 755 "$enumeration_failure/overlay"
        echo "FAIL: returned a truncated theme list after enumeration failure" >&2
        exit 1
      fi
      chmod 755 "$enumeration_failure/overlay"
      test ! -s "$enumeration_stdout"
      grep -Fq "Could not enumerate theme catalog: $enumeration_failure/overlay" "$enumeration_stderr"

      echo "TEST catalog entry enumeration failure cannot compose a partial generation"
      entry_enumeration_failure="$TMPDIR/entry-enumeration-failure"
      mkdir -p "$entry_enumeration_failure/base" "$entry_enumeration_failure/overlay"
      make_theme "$entry_enumeration_failure/base" unreadable
      chmod 111 "$entry_enumeration_failure/base/unreadable"
      entry_enumeration_stderr="$entry_enumeration_failure/stderr"
      if run_selector "$entry_enumeration_failure" select unreadable 2> "$entry_enumeration_stderr"; then
        chmod 755 "$entry_enumeration_failure/base/unreadable"
        echo "FAIL: composed a partial generation after catalog enumeration failure" >&2
        exit 1
      fi
      chmod 755 "$entry_enumeration_failure/base/unreadable"
      grep -Fq "Could not enumerate theme catalog entries: $entry_enumeration_failure/base/unreadable" "$entry_enumeration_stderr"
      test ! -e "$entry_enumeration_failure/state/keystone/themes/current"
      test -z "$(find "$entry_enumeration_failure/state/keystone/themes/generations" -mindepth 1 -print -quit)"

      echo "TEST staged generation creation failure cannot write at filesystem root"
      mktemp_failure="$TMPDIR/mktemp-failure"
      mkdir -p "$mktemp_failure/base" "$mktemp_failure/overlay" \
        "$mktemp_failure/state/keystone/themes/generations"
      make_theme "$mktemp_failure/base" tokyo-night
      chmod 555 "$mktemp_failure/state/keystone/themes/generations"
      for root_path in /zellij.kdl /helix.toml /btop.theme /lazygit.yml; do
        test ! -e "$root_path"
        test ! -L "$root_path"
      done
      mktemp_failure_stderr="$mktemp_failure/stderr"
      if run_selector "$mktemp_failure" select tokyo-night 2> "$mktemp_failure_stderr"; then
        echo "FAIL: selected a theme without a writable generations directory" >&2
        exit 1
      fi
      grep -Fq "Could not create a staged theme generation in: $mktemp_failure/state/keystone/themes/generations" "$mktemp_failure_stderr"
      test -z "$(find "$mktemp_failure/state/keystone/themes/generations" -mindepth 1 -print -quit)"
      test ! -e "$mktemp_failure/state/keystone/themes/current"
      for root_path in /zellij.kdl /helix.toml /btop.theme /lazygit.yml; do
        test ! -e "$root_path"
        test ! -L "$root_path"
      done

      echo "TEST catalog cannot provide selector metadata"
      catalog_metadata="$TMPDIR/catalog-metadata"
      mkdir -p "$catalog_metadata/base" "$catalog_metadata/overlay"
      make_theme "$catalog_metadata/base" tokyo-night
      printf '{}\n' > "$catalog_metadata/base/tokyo-night/.keystone-theme.json"
      catalog_metadata_stderr="$catalog_metadata/stderr"
      if run_selector "$catalog_metadata" select tokyo-night 2> "$catalog_metadata_stderr"; then
        echo "FAIL: accepted catalog-provided selector metadata" >&2
        exit 1
      fi
      grep -Fq 'Theme catalogs MUST NOT provide .keystone-theme.json' "$catalog_metadata_stderr"
      test ! -e "$catalog_metadata/state/keystone/themes/current"
      test "$(find "$catalog_metadata/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = 0

        incomplete="$TMPDIR/incomplete"
        mkdir -p "$incomplete/base" "$incomplete/overlay"
        make_theme "$incomplete/base" tokyo-night
        mkdir -p "$incomplete/base/broken"
        printf keep > "$incomplete/base/broken/zellij.kdl"
      echo "TEST incomplete theme"
      run_selector "$incomplete" select tokyo-night
        before="$(readlink -f "$incomplete/state/keystone/themes/current")"
        generations_before="$(find "$incomplete/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
        if run_selector "$incomplete" select broken; then
          echo "FAIL: accepted an incomplete theme" >&2
          exit 1
        fi
        test "$(readlink -f "$incomplete/state/keystone/themes/current")" = "$before"
        test "$(find "$incomplete/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$generations_before"

      echo "TEST staged render hooks and renderer rollback"
      renderer_one="$root/renderer-one"
      renderer_two="$root/renderer-two"
      mkdir -p "$renderer_one/bin" "$renderer_two/bin"
      printf '%s\n' '#!${pkgs.runtimeShell}' 'set -euo pipefail' \
        'printf "renderer one: %s\\n" "$1"' \
        'if IFS= read -r unexpected; then echo "renderer inherited stdin: $unexpected" >&2; exit 1; fi' \
        'printf "theme[main_bg]=\"#123456\"\\n" > "$2/btop.theme"' \
        'if [[ "$1" = reserved-metadata ]]; then printf "{}\\n" > "$2/.keystone-theme.json"; fi' \
        'if [[ "$1" = metadata-temp-collision ]]; then printf "renderer-owned\\n" > "$2/.keystone-theme.json.tmp"; fi' \
        'if [[ "$1" = renderer-write-through ]]; then ln -s "$KEYSTONE_RENDER_OUTSIDE" "$2/generated-link"; fi' \
        'if [[ "$1" = renderer-hardlink ]]; then ln "$KEYSTONE_RENDER_OUTSIDE" "$2/generated-hardlink"; fi' \
        '[[ "$1" != broken-render ]]' > "$renderer_one/bin/keystone-theme-render"
      printf '%s\n' '#!${pkgs.runtimeShell}' 'set -euo pipefail' \
        'printf "renderer two: %s\\n" "$1"' \
        'if [[ "$1" = renderer-write-through ]]; then printf mutated > "$2/generated-link"; fi' \
        'if [[ "$1" = renderer-hardlink ]]; then printf mutated > "$2/generated-hardlink"; fi' \
        'grep -Fqx "theme[main_bg]=\"#123456\"" "$2/btop.theme"' \
        'printf "%s\\n" "$1" > "$2/second-renderer"' > "$renderer_two/bin/keystone-theme-render"
      chmod +x "$renderer_one/bin/keystone-theme-render" "$renderer_two/bin/keystone-theme-render"

      echo "TEST render hook executable preflight is complete"
      preflight_renderer="$root/preflight-renderer"
      late_missing_renderer="$root/late-missing-renderer"
      mkdir -p "$preflight_renderer/bin" "$late_missing_renderer/bin"
      printf '%s\n' '#!${pkgs.runtimeShell}' \
        'printf ran > "$KEYSTONE_RENDER_PREFLIGHT_MARKER"' > "$preflight_renderer/bin/keystone-theme-render"
      chmod +x "$preflight_renderer/bin/keystone-theme-render"
      preflight_marker="$root/preflight-renderer-ran"
      preflight_stderr="$root/preflight-renderer.stderr"
      before="$(readlink -f "$root/state/keystone/themes/current")"
      generations_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      if SELECTOR_RENDER_HOOKS="$(printf '%s\n%s' "$preflight_renderer" "$late_missing_renderer")" \
        KEYSTONE_RENDER_PREFLIGHT_MARKER="$preflight_marker" \
        run_selector "$root" select kanagawa 2> "$preflight_stderr"; then
        echo "FAIL: accepted a late missing render hook executable" >&2
        exit 1
      fi
      grep -Fq "Theme render hook does not provide executable bin/keystone-theme-render: $late_missing_renderer" "$preflight_stderr"
      test ! -e "$preflight_marker"
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$before"
      test "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$generations_before"

      echo "TEST generation metadata write failure cannot promote a stage"
      make_theme "$root/base" metadata-write-failure
      metadata_failure_renderer="$root/metadata-failure-renderer"
      mkdir -p "$metadata_failure_renderer/bin"
      printf '%s\n' '#!${pkgs.runtimeShell}' \
        'chmod 555 "$(dirname "$(dirname "$2")")"' > "$metadata_failure_renderer/bin/keystone-theme-render"
      chmod +x "$metadata_failure_renderer/bin/keystone-theme-render"
      metadata_failure_stderr="$root/metadata-failure.stderr"
      before="$(readlink -f "$root/state/keystone/themes/current")"
      generations_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      if SELECTOR_RENDER_HOOKS="$metadata_failure_renderer" \
        run_selector "$root" select metadata-write-failure 2> "$metadata_failure_stderr"; then
        chmod 755 "$root/state/keystone/themes"
        echo "FAIL: promoted a generation with failed metadata output" >&2
        exit 1
      fi
      chmod 755 "$root/state/keystone/themes"
      grep -Fq "Could not create temporary theme generation metadata in: $root/state/keystone/themes" "$metadata_failure_stderr"
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$before"
      test "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$generations_before"

      make_theme "$root/base" metadata-temp-collision
      catalog_snapshot="$TMPDIR/catalog-snapshot"
      mkdir -p "$catalog_snapshot"
      cp -R "$root/base" "$root/overlay" "$catalog_snapshot"
      test ! -w "$root/base/kanagawa/btop.theme"
      render_stdout="$root/render.stdout"
      render_stderr="$root/render.stderr"
      if ! printf 'selector input must not reach renderers\n' \
        | SELECTOR_RENDER_HOOKS="$(printf '%s\n%s' "$renderer_one" "$renderer_two")" \
          KEYSTONE_THEME_REQUIRED_PATHS='${
            builtins.concatStringsSep ":" (requiredPaths ++ [ "second-renderer" ])
          }' \
          run_selector "$root" select kanagawa > "$render_stdout" 2> "$render_stderr"; then
        cat "$render_stderr" >&2
        echo "FAIL: renderer isolation prevented theme selection" >&2
        exit 1
      fi
      test ! -s "$render_stdout"
      grep -qx 'renderer one: kanagawa' "$render_stderr"
      grep -qx 'renderer two: kanagawa' "$render_stderr"
      current="$(readlink -f "$root/state/keystone/themes/current")"
      test "$(cat "$current/btop.theme")" = 'theme[main_bg]="#123456"'
      test "$(cat "$current/second-renderer")" = kanagawa
      diff -r "$catalog_snapshot/base" "$root/base"
      diff -r "$catalog_snapshot/overlay" "$root/overlay"
      test ! -w "$root/base/kanagawa/btop.theme"

      echo "TEST renderer metadata temporary path remains renderer-owned"
      foreign_metadata="$root/state/keystone/themes/.metadata-temp-collision.000000.metadata.foreign"
      printf 'foreign-metadata\n' > "$foreign_metadata"
      SELECTOR_RENDER_HOOKS="$(printf '%s\n%s' "$renderer_one" "$renderer_two")" \
        run_selector "$root" select metadata-temp-collision \
        > "$root/metadata-temp-collision.stdout" 2> "$root/metadata-temp-collision.stderr"
      test ! -s "$root/metadata-temp-collision.stdout"
      current="$(readlink -f "$root/state/keystone/themes/current")"
      test "$(cat "$current/.keystone-theme.json.tmp")" = renderer-owned
      test "$(jq -r .theme "$current/.keystone-theme.json")" = metadata-temp-collision
      grep -Fqx 'renderer one: metadata-temp-collision' "$root/metadata-temp-collision.stderr"
      grep -Fqx 'renderer two: metadata-temp-collision' "$root/metadata-temp-collision.stderr"
      test "$(cat "$foreign_metadata")" = foreign-metadata
      test -z "$(find "$root/state/keystone/themes" -maxdepth 1 -name '.metadata-temp-collision.*.metadata.??????' -print -quit)"
      rm -f "$foreign_metadata"

      make_theme "$root/base" broken-render
      before="$current"
      generations_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      if SELECTOR_RENDER_HOOKS="$(printf '%s\n%s' "$renderer_one" "$renderer_two")" \
        run_selector "$root" select broken-render; then
        echo "FAIL: accepted a failing renderer" >&2
        exit 1
      fi
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$before"
      test "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$generations_before"

      echo "TEST render hook cannot create selector metadata"
      make_theme "$root/base" reserved-metadata
      generations_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      reserved_stderr="$root/reserved.stderr"
      if SELECTOR_RENDER_HOOKS="$(printf '%s\n%s' "$renderer_one" "$renderer_two")" \
        run_selector "$root" select reserved-metadata 2> "$reserved_stderr"; then
        echo "FAIL: accepted renderer-created selector metadata" >&2
        exit 1
      fi
      grep -Fq 'created reserved metadata path .keystone-theme.json' "$reserved_stderr"
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$before"
      test "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$generations_before"

      echo "TEST interrupted renderer removes hidden staging"
      make_theme "$root/base" interrupted-render
      interrupt_renderer="$root/interrupt-renderer"
      mkdir -p "$interrupt_renderer/bin"
      printf '%s\n' '#!${pkgs.runtimeShell}' \
        'kill -TERM "$PPID"' \
        'exit 0' > "$interrupt_renderer/bin/keystone-theme-render"
      chmod +x "$interrupt_renderer/bin/keystone-theme-render"
      generations_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      if SELECTOR_RENDER_HOOKS="$interrupt_renderer" run_selector "$root" select interrupted-render; then
        echo "FAIL: accepted a renderer-interrupted composition" >&2
        exit 1
      fi
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$before"
      test "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$generations_before"
      test -z "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -name '.*' -print -quit)"

      echo "TEST reservation creation interrupt leaves no stale ownership"
      make_theme "$root/base" reservation-window
      reservation_interrupt_env="$root/reservation-interrupt.bashenv"
      printf '%s\n' \
        'set -T' \
        'reservation_interrupt() {' \
        '  if [[ "''${FUNCNAME[1]:-}" == compose_theme && "$BASH_COMMAND" == reservation_is_owned ]]; then' \
        '    trap - DEBUG' \
        '    kill -TERM "$$"' \
        '  fi' \
        '}' \
        'trap reservation_interrupt DEBUG' > "$reservation_interrupt_env"
      before="$(readlink -f "$root/state/keystone/themes/current")"
      generations_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      set +e
      BASH_ENV="$reservation_interrupt_env" run_selector "$root" select reservation-window \
        2> "$root/reservation-interrupt.stderr"
      reservation_interrupt_status=$?
      set -e
      test "$reservation_interrupt_status" = 143
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$before"
      test -d "$before"
      test "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$generations_before"
      test -z "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -name '*reservation-window*' -print -quit)"

      echo "TEST failed reservation create never removes foreign ownership"
      make_theme "$root/base" foreign-reservation-window
      foreign_reservation="$root/state/keystone/themes/generations/.foreign-reservation-window.000000.reserve"
      printf 'foreign-token\n' > "$foreign_reservation"
      foreign_reservation_interrupt_env="$root/foreign-reservation-interrupt.bashenv"
      printf '%s\n' \
        'set -T' \
        'foreign_reservation_interrupt() {' \
        '  if [[ "''${FUNCNAME[1]:-}" == compose_theme && "$BASH_COMMAND" == disown_reservation_cleanup ]]; then' \
        '    trap - DEBUG' \
        '    kill -TERM "$$"' \
        '  fi' \
        '}' \
        'trap foreign_reservation_interrupt DEBUG' > "$foreign_reservation_interrupt_env"
      before="$(readlink -f "$root/state/keystone/themes/current")"
      set +e
      BASH_ENV="$foreign_reservation_interrupt_env" run_selector "$root" select foreign-reservation-window \
        2> "$root/foreign-reservation-interrupt.stderr"
      foreign_reservation_interrupt_status=$?
      set -e
      test "$foreign_reservation_interrupt_status" = 143
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$before"
      test -d "$before"
      test "$(cat "$foreign_reservation")" = foreign-token
      test "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -name '*foreign-reservation-window*' | wc -l)" = 1
      rm -f "$foreign_reservation"

      echo "TEST stage creation interrupt leaves no hidden generation"
      make_theme "$root/base" stage-window
      stage_interrupt_env="$root/stage-interrupt.bashenv"
      printf '%s\n' \
        'set -T' \
        'stage_interrupt() {' \
        '  if [[ "''${FUNCNAME[1]:-}" == compose_theme && "$BASH_COMMAND" == owned_stage_exists ]]; then' \
        '    trap - DEBUG' \
        '    kill -TERM "$$"' \
        '  fi' \
        '}' \
        'trap stage_interrupt DEBUG' > "$stage_interrupt_env"
      before="$(readlink -f "$root/state/keystone/themes/current")"
      generations_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      set +e
      BASH_ENV="$stage_interrupt_env" run_selector "$root" select stage-window \
        2> "$root/stage-interrupt.stderr"
      stage_interrupt_status=$?
      set -e
      test "$stage_interrupt_status" = 143
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$before"
      test -d "$before"
      test "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$generations_before"
      test -z "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -name '*stage-window*' -print -quit)"

      echo "TEST promotion interrupt cleans hidden and visible ownership"
      make_theme "$root/base" promotion-interrupt
      promotion_interrupt_env="$root/promotion-interrupt.bashenv"
      printf '%s\n' \
        'set -T' \
        'promotion_interrupt() {' \
        '  if [[ "''${FUNCNAME[1]:-}" == activate_generation && "$BASH_COMMAND" == generation_cleanup_path=\"\" ]]; then' \
        '    trap - DEBUG' \
        '    kill -TERM "$$"' \
        '  fi' \
        '}' \
        'trap promotion_interrupt DEBUG' > "$promotion_interrupt_env"
      before="$(readlink -f "$root/state/keystone/themes/current")"
      promotion_adapters="$(while IFS=$'\t' read -r source target; do printf '%s\t%s\n' "$target" "$(readlink "$target")"; done < <(adapter_spec "$root"))"
      generations_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      set +e
      BASH_ENV="$promotion_interrupt_env" run_selector "$root" select promotion-interrupt \
        2> "$root/promotion-interrupt.stderr"
      promotion_interrupt_status=$?
      set -e
      test "$promotion_interrupt_status" = 143
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$before"
      test "$(while IFS=$'\t' read -r source target; do printf '%s\t%s\n' "$target" "$(readlink "$target")"; done < <(adapter_spec "$root"))" = "$promotion_adapters"
      test "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$generations_before"
      test -z "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -name '*promotion-interrupt*' -print -quit)"

      echo "TEST current-link interrupt preserves its active generation"
      make_theme "$root/base" current-switch-interrupt
      current_switch_interrupt_env="$root/current-switch-interrupt.bashenv"
      printf '%s\n' \
        'set -T' \
        'current_switch_interrupt() {' \
        '  if [[ "''${FUNCNAME[1]:-}" == activate_generation && "$BASH_COMMAND" == clear_current_link_temporary ]]; then' \
        '    trap - DEBUG' \
        '    kill -TERM "$$"' \
        '  fi' \
        '}' \
        'trap current_switch_interrupt DEBUG' > "$current_switch_interrupt_env"
      before="$(readlink -f "$root/state/keystone/themes/current")"
      generations_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      set +e
      BASH_ENV="$current_switch_interrupt_env" run_selector "$root" select current-switch-interrupt \
        2> "$root/current-switch-interrupt.stderr"
      current_switch_interrupt_status=$?
      set -e
      test "$current_switch_interrupt_status" = 143
      current_after_interrupt="$(readlink -f "$root/state/keystone/themes/current")"
      test "$current_after_interrupt" != "$before"
      test -d "$before"
      test -d "$current_after_interrupt"
      test "$(jq -r .theme "$current_after_interrupt/.keystone-theme.json")" = current-switch-interrupt
      test "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$((generations_before + 1))"
      test -z "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -name '.current-switch-interrupt.*.reserve' -print -quit)"
      while IFS=$'\t' read -r source target; do
        test -L "$target"
        test -e "$target"
      done < <(adapter_spec "$root")

      echo "TEST rollback-link interrupt preserves the restored generation"
      make_theme "$root/base" restore-switch-interrupt
      restore_switch_hook="$root/restore-switch-hook"
      mkdir -p "$restore_switch_hook/bin"
      printf '%s\n' '#!${pkgs.runtimeShell}' 'exit 1' > "$restore_switch_hook/bin/keystone-theme-hook"
      chmod +x "$restore_switch_hook/bin/keystone-theme-hook"
      restore_switch_interrupt_env="$root/restore-switch-interrupt.bashenv"
      printf '%s\n' \
        'set -T' \
        'restore_switch_interrupt() {' \
        '  if [[ "''${FUNCNAME[1]:-}" == restore_generation && "$BASH_COMMAND" == clear_current_link_temporary ]]; then' \
        '    trap - DEBUG' \
        '    kill -TERM "$$"' \
        '  fi' \
        '}' \
        'trap restore_switch_interrupt DEBUG' > "$restore_switch_interrupt_env"
      before="$current_after_interrupt"
      generations_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      set +e
      BASH_ENV="$restore_switch_interrupt_env" SELECTOR_HOOKS="$restore_switch_hook" \
        run_selector "$root" select restore-switch-interrupt \
        2> "$root/restore-switch-interrupt.stderr"
      restore_switch_interrupt_status=$?
      set -e
      test "$restore_switch_interrupt_status" = 143
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$before"
      test -d "$before"
      test "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$generations_before"
      test -z "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -name '*restore-switch-interrupt*' -print -quit)"
      while IFS=$'\t' read -r source target; do
        test -L "$target"
        test -e "$target"
      done < <(adapter_spec "$root")

      echo "TEST compose handoff interrupt remains owned in select and refresh"
      make_theme "$root/base" handoff-interrupt
      handoff_interrupt_env="$root/handoff-interrupt.bashenv"
      printf '%s\n' \
        'set -T' \
        'handoff_interrupt() {' \
        '  if [[ ( "''${FUNCNAME[1]:-}" == select_theme || "''${FUNCNAME[1]:-}" == refresh_theme ) && "$BASH_COMMAND" == generation=\"\$composed_generation\" ]]; then' \
        '    trap - DEBUG' \
        '    kill -TERM "$$"' \
        '  fi' \
        '}' \
        'trap handoff_interrupt DEBUG' > "$handoff_interrupt_env"
      before="$current_after_interrupt"
      generations_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      set +e
      BASH_ENV="$handoff_interrupt_env" run_selector "$root" select handoff-interrupt \
        2> "$root/select-handoff-interrupt.stderr"
      select_handoff_status=$?
      set -e
      test "$select_handoff_status" = 143
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$before"
      test "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$generations_before"
      test -z "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 \( -type d -name '.*' -o -name '.*.reserve' \) -print -quit)"
      set +e
      BASH_ENV="$handoff_interrupt_env" run_selector "$root" refresh \
        2> "$root/refresh-handoff-interrupt.stderr"
      refresh_handoff_status=$?
      set -e
      test "$refresh_handoff_status" = 143
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$before"
      test "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$generations_before"
      test -z "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 \( -type d -name '.*' -o -name '.*.reserve' \) -print -quit)"

      echo "TEST cleanup failure still removes later owned state"
      make_theme "$root/base" cleanup-failure
      cleanup_failure_renderer="$root/cleanup-failure-renderer"
      mkdir -p "$cleanup_failure_renderer/bin"
      printf '%s\n' '#!${pkgs.runtimeShell}' \
        'chmod 555 "$2"' \
        'exit 1' > "$cleanup_failure_renderer/bin/keystone-theme-render"
      chmod +x "$cleanup_failure_renderer/bin/keystone-theme-render"
      before="$(readlink -f "$root/state/keystone/themes/current")"
      generations_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      set +e
      SELECTOR_RENDER_HOOKS="$cleanup_failure_renderer" \
        run_selector "$root" select cleanup-failure 2> "$root/cleanup-failure.stderr"
      cleanup_failure_status=$?
      set -e
      test "$cleanup_failure_status" = 1
      cleanup_failure_stage="$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d -name '.cleanup-failure.*' -print -quit)"
      test -n "$cleanup_failure_stage"
      grep -Fq "Cleanup warning: could not remove owned path: $cleanup_failure_stage" "$root/cleanup-failure.stderr"
      test -z "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -name '.cleanup-failure.*.reserve' -print -quit)"
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$before"
      chmod -R u+w "$cleanup_failure_stage"
      rm -rf "$cleanup_failure_stage"
      test "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$generations_before"

      echo "TEST renderer hard-link write-through is stopped between hooks"
      make_theme "$root/base" renderer-hardlink
      hardlink_outside="$root/hardlink-outside"
      printf unchanged > "$hardlink_outside"
      generations_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      renderer_hardlink_stderr="$root/renderer-hardlink.stderr"
      if SELECTOR_RENDER_HOOKS="$(printf '%s\n%s' "$renderer_one" "$renderer_two")" \
        KEYSTONE_RENDER_OUTSIDE="$hardlink_outside" \
        run_selector "$root" select renderer-hardlink 2> "$renderer_hardlink_stderr"; then
        echo "FAIL: allowed a later renderer to write through a hard link" >&2
        exit 1
      fi
      grep -Fq "Theme render hook MUST NOT leave hard-linked files in staged generation: $renderer_one: generated-hardlink" "$renderer_hardlink_stderr"
      test "$(cat "$hardlink_outside")" = unchanged
      test "$(stat -c %h "$hardlink_outside")" = 1
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$before"
      test "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$generations_before"

      echo "TEST renderer write-through is stopped between hooks"
      make_theme "$root/base" renderer-write-through
      outside_target="$root/outside-target"
      printf unchanged > "$outside_target"
      generations_before="$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
      renderer_symlink_stderr="$root/renderer-write-through.stderr"
      if SELECTOR_RENDER_HOOKS="$(printf '%s\n%s' "$renderer_one" "$renderer_two")" \
        KEYSTONE_RENDER_OUTSIDE="$outside_target" \
        run_selector "$root" select renderer-write-through 2> "$renderer_symlink_stderr"; then
        echo "FAIL: allowed a later renderer to write through a symbolic link" >&2
        exit 1
      fi
      grep -Fq "Theme render hook MUST NOT leave symbolic links in staged generation: $renderer_one: generated-link" "$renderer_symlink_stderr"
      test "$(cat "$outside_target")" = unchanged
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$before"
      test "$(find "$root/state/keystone/themes/generations" -mindepth 1 -maxdepth 1 -type d | wc -l)" = "$generations_before"

        conflict="$TMPDIR/conflict"
        mkdir -p "$conflict/base" "$conflict/overlay"
        make_theme "$conflict/base" tokyo-night
        mkdir -p "$conflict/base/tokyo-night/collision" "$conflict/overlay/tokyo-night"
        printf file > "$conflict/overlay/tokyo-night/collision"
      echo "TEST overlay conflict"
      if run_selector "$conflict" select tokyo-night; then
          echo "FAIL: accepted a file/directory overlay conflict" >&2
          exit 1
        fi
        test ! -e "$conflict/state/keystone/themes/current"

        unsafe="$TMPDIR/unsafe"
        mkdir -p "$unsafe/base/bad@name" "$unsafe/overlay"
    echo "TEST unsafe name"
      if run_selector "$unsafe" list-json; then
          echo "FAIL: accepted an unsafe theme name" >&2
          exit 1
      fi

      empty="$TMPDIR/empty"
      mkdir -p "$empty/base" "$empty/overlay"
      test "$(run_selector "$empty" list-json)" = '{"themes":[]}'

        broken="$TMPDIR/broken-link"
        mkdir -p "$broken/base" "$broken/overlay"
        make_theme "$broken/base" tokyo-night
        ln -s missing "$broken/base/tokyo-night/dangling"
      echo "TEST broken link"
      if run_selector "$broken" select tokyo-night; then
          echo "FAIL: accepted a broken symbolic link" >&2
          exit 1
        fi

      echo "TEST public theme wrapper wiring and case ordering"
      wrapper_home='${wrapperHomeDirectory}'
      case "$wrapper_home" in
        /build/*) ;;
        *) echo "FAIL: wrapper check does not use the Linux build sandbox" >&2; exit 1 ;;
      esac
      ${themeSwitch}/bin/keystone-theme-switch tokyo-night
      wrapper_current="$(readlink -f "$wrapper_home/.local/state/keystone/themes/current")"
      test "$(cat "$wrapper_current/wrapper-rendered")" = tokyo-night
      wrapper_backgrounds="$(${themeSwitch}/bin/keystone-theme-switch --backgrounds --json)"
      test "$(printf '%s' "$wrapper_backgrounds" | ${pkgs.jq}/bin/jq -r .theme)" = tokyo-night
      test "$(printf '%s' "$wrapper_backgrounds" | ${pkgs.jq}/bin/jq -r '.backgrounds | length')" = 0
      wrapper_candidate="$wrapper_home/.local/state/keystone/themes/generations/manual-candidate"
      mkdir "$wrapper_candidate"
      wrapper_gc="$(${themeSwitch}/bin/keystone-theme-switch --gc)"
      grep -Fqx "candidate: $wrapper_candidate" <<< "$wrapper_gc"
      render_export_line="$(grep -Fn 'KEYSTONE_THEME_RENDER_HOOKS=' ${themeActivation} | cut -d: -f1)"
      reconcile_line="$(grep -Fn 'keystone-theme-selector reconcile "tokyo-night"' ${themeActivation} | cut -d: -f1)"
      test -n "$render_export_line"
      test -n "$reconcile_line"
      test "$render_export_line" -lt "$reconcile_line"
      grep -Fq 'KEYSTONE_THEME_RENDER_HOOKS="/nix/store/' ${themeActivation}

        touch "$out"
  ''
