#!/bin/sh
# dirty-repos: list the git repositories under one or more folders that have
# modified, staged or untracked files. It writes nothing into the folders it
# scans. POSIX sh.
#
# Usage: sh dirty-repos.sh [--max-depth N] FOLDER...

# zsh runs a script with its own rules unless told otherwise.
if [ -n "${ZSH_VERSION:-}" ]; then
  emulate -R sh
fi

unset CDPATH GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

usage() {
  echo "usage: dirty-repos.sh [--max-depth N] FOLDER..."
}

fail_usage() {
  echo "dirty-repos: $1" >&2
  usage >&2
  exit 2
}

MAXDEPTH=6
while [ $# -gt 0 ]; do
  case "$1" in
    --max-depth)
      [ $# -ge 2 ] || fail_usage "--max-depth needs a number"
      MAXDEPTH=$2
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -?*)
      fail_usage "unknown option: $1"
      ;;
    *)
      break
      ;;
  esac
done

case "$MAXDEPTH" in
  '' | *[!0-9]*) fail_usage "--max-depth needs a whole number, got: $MAXDEPTH" ;;
esac

# A leading zero would make the shell read the number as octal (08 is an error,
# 010 is 8), so keep one digit at least and drop the zeros before it.
GIVEN_DEPTH=$MAXDEPTH
while [ "${#MAXDEPTH}" -gt 1 ] && [ "${MAXDEPTH#0}" != "$MAXDEPTH" ]; do MAXDEPTH=${MAXDEPTH#0}; done
[ "${#MAXDEPTH}" -le 9 ] || fail_usage "--max-depth is too large: $GIVEN_DEPTH"

[ $# -gt 0 ] || fail_usage "give at least one folder"

command -v git >/dev/null 2>&1 || {
  echo "dirty-repos: git not found" >&2
  exit 2
}

for folder in "$@"; do
  [ -d "$folder" ] || {
    echo "dirty-repos: not a folder: $folder" >&2
    exit 2
  }
done

FILES=0
REPOS=0
SCANNED=0
FAILED=0
SEEN='
'

# check_repo REPO: count the changed files of one repository and print a line.
check_repo() {
  # The same repository reached twice (overlapping folders) counts once.
  key=$(cd "$1" 2>/dev/null && pwd -P) || key=$1
  case "$SEEN" in
    *"
$key
"*) return 0 ;;
  esac
  SEEN="$SEEN$key
"

  out=
  # A .git entry that git does not accept as this folder's own repository
  # (git would otherwise report an enclosing repository) counts as a failure.
  prefix=$(git -C "$1" rev-parse --show-prefix 2>/dev/null) && [ -z "$prefix" ] \
    && out=$(GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -C "$1" status --porcelain --untracked-files=normal 2>/dev/null)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf '?  %s (git status failed)\n' "$1"
    FAILED=$((FAILED + 1))
    return 0
  fi

  SCANNED=$((SCANNED + 1))
  if [ -z "$out" ]; then
    return 0
  fi
  n=$(printf '%s\n' "$out" | grep -c '')
  printf '%5d  %s\n' "$n" "$1"
  FILES=$((FILES + n))
  REPOS=$((REPOS + 1))
}

# scan FOLDER LEVELS: check FOLDER, then look LEVELS folders further down.
scan() {
  if [ -e "$1/.git" ]; then
    check_repo "$1"
  fi
  [ "$2" -gt 0 ] || return 0
  for entry in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    [ -d "$entry" ] || continue
    if [ -L "$entry" ]; then continue; fi
    case "$entry" in
      */.git | */node_modules) continue ;;
    esac
    scan "$entry" $(($2 - 1))
  done
}

for folder in "$@"; do
  while [ "${#folder}" -gt 1 ] && [ "${folder%/}" != "$folder" ]; do
    folder=${folder%/}
  done
  scan "$folder" "$MAXDEPTH"
done

printf 'TOTAL: %d files in %d repositories (%d scanned)\n' "$FILES" "$REPOS" "$SCANNED"
if [ "$REPOS" -gt 0 ] || [ "$FAILED" -gt 0 ]; then exit 1; fi
exit 0
