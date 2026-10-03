repo=""
target=""
source=""
check=0
while (( $# )); do
  case "$1" in
    --repo|--target|--source)
      if (( $# < 2 )); then echo "Missing value for $1" >&2; exit 2; fi
      case "$1" in
        --repo) repo="$2" ;;
        --target) target="$2" ;;
        --source) source="$2" ;;
      esac
      shift 2 ;;
    --check) check=1; shift ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) break ;;
  esac
done
if [[ -z "$repo" || -z "$target" || $# == 0 ]]; then
  echo 'Usage: ks-stow-dotfiles --repo PATH --target HOME [--check] [--source LOCKED_REPO] PACKAGE...' >&2
  exit 2
fi
for package in "$@"; do
  if [[ ! "$package" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ || ! -d "$repo/packages/$package" ]]; then
    echo "dotfiles: invalid or missing selected package: $package" >&2
    exit 1
  fi
  if (( check )) && [[ -n "$source" ]]; then
    # Compare only the selected source trees, never the target home directory.
    diff --recursive --brief --no-dereference "$source/packages/$package" "$repo/packages/$package"
  fi
done
# Ignore ambient ~/.stowrc and working-directory .stowrc (which can enable
# --adopt). Only the explicit command below controls installation.
repo="$(realpath "$repo")"
target="$(realpath "$target")"
cd "$(dirname "$(readlink -f "$0")")"
export HOME=/dev/null
args=(--dir "$repo/packages" --target "$target" --no-folding --stow)
# Always simulate before applying, so a conflict cannot partially install packages.
stow "${args[@]}" --simulate "$@"
if (( ! check )); then
  stow "${args[@]}" "$@"
fi
