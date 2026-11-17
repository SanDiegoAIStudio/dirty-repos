#!/bin/sh
# Mutation check for dirty-repos.sh. Each mutation breaks one behavior in a
# temporary copy of the script; tests/test.sh must then fail against that copy.
# A mutation the tests do not catch is reported as survived and exits 1; so is
# one whose test run stopped without naming a failed case.
#
# Usage: sh tests/mutate.sh
# Environment: JOBS is how many mutations run at once (default 4).

here=$(cd "$(dirname "$0")" && pwd)
SOURCE=$here/../dirty-repos.sh
JOBS=${JOBS:-4}

tmp_root=${TMPDIR:-/tmp}
tmp_root=${tmp_root%/}
M=$(mktemp -d "$tmp_root/dirty-repos-mutate.XXXXXX") || exit 1
case "$M" in
  "$tmp_root"/dirty-repos-mutate.*) ;;
  *)
    echo "mutate: unexpected temporary folder: $M" >&2
    exit 1
    ;;
esac
trap 'rm -rf "$M"' EXIT
trap 'exit 1' INT TERM

: >"$M/order"
RUNNING=0

# mutant NAME SED_EXPRESSION: queue one mutation.
mutant() {
  printf '%s\n' "$1" >>"$M/order"
  (
    copy=$M/$1.sh
    sed -e "$2" "$SOURCE" >"$copy"
    if cmp -s "$SOURCE" "$copy"; then
      echo "no-change" >"$M/$1.result"
      exit 0
    fi
    if DIRTY_REPOS=$copy sh "$here/test.sh" >"$M/$1.log" 2>&1; then
      echo "survived" >"$M/$1.result"
    elif grep -q '^FAIL' "$M/$1.log"; then
      echo "killed" >"$M/$1.result"
    else
      # The test stopped without naming a failed case (a full disk, for example).
      echo "error" >"$M/$1.result"
    fi
  ) &
  RUNNING=$((RUNNING + 1))
  if [ "$RUNNING" -ge "$JOBS" ]; then
    wait
    RUNNING=0
  fi
}

# The unmodified script must pass, or "killed" would prove nothing.
if ! DIRTY_REPOS=$SOURCE sh "$here/test.sh" >"$M/baseline.log" 2>&1; then
  echo "mutate: the unmodified script does not pass tests/test.sh; fix that first" >&2
  tail -n 20 "$M/baseline.log" >&2
  exit 1
fi

mutant drop-untracked-from-count 's/--untracked-files=normal/--untracked-files=no/'
mutant no-untracked-flag 's/ --untracked-files=normal//'
mutant stop-descending-into-repositories 's/^    check_repo "\$1"$/    check_repo "$1"; return 0/'
mutant ignore-max-depth 's/\[ "\$2" -gt 0 \] || return 0/:/'
mutant total-adds-one-per-repository 's/FILES=\$((FILES + n))/FILES=$((FILES + 1))/'
mutant repository-total-doubled 's/REPOS=\$((REPOS + 1))/REPOS=$((REPOS + 2))/'
mutant scanned-total-never-grows 's/SCANNED=\$((SCANNED + 1))/SCANNED=$((SCANNED + 0))/'
mutant exit-1-becomes-0 's/then exit 1; fi/then exit 0; fi/'
mutant failure-no-longer-exits-1 's/ || \[ "\$FAILED" -gt 0 \]//'
mutant drop-optional-locks 's/GIT_OPTIONAL_LOCKS=0 //'
mutant quote-nothing 's/"\$1"/$1/g; s/"\$entry"/$entry/g; s/"\$folder"/$folder/g'
mutant follow-symbolic-links 's/if \[ -L "\$entry" \]; then continue; fi/:/'
mutant search-node-modules 's/\*\/\.git | \*\/node_modules)/*\/.git)/'
mutant skip-hidden-folders 's| "\$1"/\.\[!\.\]\*||'
mutant git-file-not-a-repository 's/if \[ -e "\$1\/\.git" \]/if [ -d "$1\/.git" ]/'
mutant no-duplicate-check 's/case "\$SEEN" in/case "" in/'
mutant no-enclosing-repository-guard 's/ && \[ -z "\$prefix" \]//'
mutant status-failure-ignored 's/if \[ "\$rc" -ne 0 \]; then/if false; then/'
mutant keep-trailing-slash 's/&& \[ "\${folder%\/}" != "\$folder" \]/\&\& false/'
mutant missing-folder-allowed 's/\[ -d "\$folder" \] || {/[ -d "$folder" ] || true || {/'
mutant no-folder-allowed 's/\[ \$# -gt 0 \] || fail_usage "give at least one folder"/:/'
mutant max-depth-not-checked 's/\*\[!0-9\]\*/NOMATCH/'
mutant max-depth-needs-no-value 's/\[ \$# -ge 2 \] || fail_usage "--max-depth needs a number"/:/'
mutant file-monitor-allowed 's/ -c core\.fsmonitor=false//'
mutant leading-zeros-kept 's/^while \[ "\${#MAXDEPTH}" -gt 1 \].*$/:/'
mutant long-depth-not-refused 's/^\[ "\${#MAXDEPTH}" -le 9 \] .*$/:/'
mutant dash-h-not-an-option 's/^    -h | --help)$/    --help)/'
mutant git-not-found-allowed 's/^command -v git >\/dev\/null 2>&1 || {$/command -v git >\/dev\/null 2>\&1 || true || {/'
mutant caller-git-variables-kept 's/^unset CDPATH GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE$/unset CDPATH/'
mutant logical-path-for-duplicates 's/pwd -P/pwd/'
wait

SURVIVED=0
while read -r name; do
  result=$(cat "$M/$name.result")
  case "$result" in
    killed)
      printf 'killed    %s\n' "$name"
      ;;
    survived)
      printf 'survived  %s\n' "$name"
      SURVIVED=$((SURVIVED + 1))
      ;;
    error)
      printf 'error     %s (the test stopped without a failed case)\n' "$name"
      SURVIVED=$((SURVIVED + 1))
      ;;
    *)
      printf 'no-change %s (the sed expression did not alter the script)\n' "$name"
      SURVIVED=$((SURVIVED + 1))
      ;;
  esac
done <"$M/order"

TOTAL=$(grep -c '' "$M/order")
echo "mutations: $TOTAL, not killed: $SURVIVED"
[ "$SURVIVED" -eq 0 ] || exit 1
exit 0
