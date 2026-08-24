{
  pkgs,
  selector,
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
        KEYSTONE_STATE_HOME="$1/state" \
          KEYSTONE_THEME_CATALOGS="$(printf 'base\t%s\noverlay\t%s' "$1/base" "$1/overlay")" \
          KEYSTONE_THEME_REQUIRED_PATHS='${builtins.concatStringsSep ":" requiredPaths}' \
          KEYSTONE_THEME_ADAPTERS="$(adapter_spec "$1")" \
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

      echo "TEST layered selection"
      run_selector "$root" select tokyo-night
        current="$(readlink -f "$root/state/keystone/themes/current")"
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

        printf second > "$root/base/tokyo-night/backgrounds/b.jpg"
      echo "TEST refresh"
      run_selector "$root" refresh
        refreshed="$(readlink -f "$root/state/keystone/themes/current")"
        test "$refreshed" != "$current"
      test "$(jq -r .background "$refreshed/.keystone-theme.json")" = backgrounds/a.jpg

      echo "TEST dangling selection reconciliation"
      rm -f "$root/state/keystone/themes/current"
      ln -s "$root/state/keystone/themes/generations/missing" "$root/state/keystone/themes/current"
      run_selector "$root" reconcile tokyo-night
      reconciled="$(readlink -f "$root/state/keystone/themes/current")"
      test -d "$reconciled"
      test "$(jq -r .theme "$reconciled/.keystone-theme.json")" = tokyo-night

      echo "TEST hook rollback"
      mkdir -p "$root/hook/bin"
    printf '%s\n' '#!${pkgs.runtimeShell}' 'if [ "$1" = kanagawa ]; then exit 1; fi' \
        'printf "%s" "$1" > "$KEYSTONE_HOOK_LOG"' > "$root/hook/bin/keystone-theme-hook"
      chmod +x "$root/hook/bin/keystone-theme-hook"
      before="$(readlink -f "$root/state/keystone/themes/current")"
    if KEYSTONE_STATE_HOME="$root/state" \
      KEYSTONE_THEME_CATALOGS="$(printf 'base\t%s\noverlay\t%s' "$root/base" "$root/overlay")" \
      KEYSTONE_THEME_REQUIRED_PATHS='${builtins.concatStringsSep ":" requiredPaths}' \
      KEYSTONE_THEME_ADAPTERS="$(adapter_spec "$root")" \
        KEYSTONE_THEME_HOOKS="$root/hook" KEYSTONE_HOOK_LOG="$root/hook.log" \
        keystone-theme-selector select kanagawa; then
        echo "FAIL: ignored a failed post-switch hook" >&2
        exit 1
      fi
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$before"
      test "$(cat "$root/hook.log")" = tokyo-night

      echo "TEST adapter conflict rollback"
      adapter="$root/config/btop/themes/current.theme"
      rm -f "$adapter"
      printf user-owned > "$adapter"
      before="$(readlink -f "$root/state/keystone/themes/current")"
      if run_selector "$root" select kanagawa; then
        echo "FAIL: replaced a user-owned adapter" >&2
        exit 1
      fi
      test "$(readlink -f "$root/state/keystone/themes/current")" = "$before"
      test "$(cat "$adapter")" = user-owned
      rm -f "$adapter"

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

        touch "$out"
  ''
