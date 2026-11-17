#!/bin/sh
# Tests for dirty-repos.sh. Builds sample folders in a temporary folder and runs
# the script under every shell present among sh, bash, zsh and dash.
#
# Usage: sh tests/test.sh
# Environment: DIRTY_REPOS is the script to test (default: ../dirty-repos.sh).
# Exit 0 when every case passes in every shell, 1 otherwise.

here=$(cd "$(dirname "$0")" && pwd)
DIRTY_REPOS=${DIRTY_REPOS:-$here/../dirty-repos.sh}
case "$DIRTY_REPOS" in
  /*) ;;
  *) DIRTY_REPOS=$(pwd)/$DIRTY_REPOS ;;
esac
[ -f "$DIRTY_REPOS" ] || {
  echo "test: script not found: $DIRTY_REPOS" >&2
  exit 1
}

# Keep the sample repositories apart from every real configuration.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OPTIONAL_LOCKS CDPATH
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM

tmp_root=${TMPDIR:-/tmp}
tmp_root=${tmp_root%/}
T=$(mktemp -d "$tmp_root/dirty-repos-test.XXXXXX") || exit 1
case "$T" in
  "$tmp_root"/dirty-repos-test.*) ;;
  *)
    echo "test: unexpected temporary folder: $T" >&2
    exit 1
    ;;
esac
trap 'rm -rf "$T"' EXIT
trap 'exit 1' INT TERM

# The commit address ends in the reserved .invalid domain, so it cannot reach a mailbox.
mail_domain=example.invalid
g() {
  git -c user.name=test -c "user.email=test@$mail_domain" \
    -c init.defaultBranch=main -c commit.gpgsign=false "$@"
}

new_repo() {
  mkdir -p "$1"
  g -C "$1" init -q
}

commit_file() { # REPO FILE: commit one file
  printf 'base\n' >"$1/$2"
  g -C "$1" add "$2"
  g -C "$1" commit -q -m "add $2"
}

# Stop at once if building a sample fails (a full disk, for example).
set -e

# ---- the five sample folders ----
S=$T/samples
new_repo "$S/clean"
commit_file "$S/clean" a.txt

new_repo "$S/modified"
commit_file "$S/modified" a.txt
printf 'changed\n' >>"$S/modified/a.txt"

new_repo "$S/untracked"
printf 'new\n' >"$S/untracked/new.txt"

new_repo "$S/staged"
commit_file "$S/staged" a.txt
printf 'new\n' >"$S/staged/b.txt"
g -C "$S/staged" add b.txt

mkdir -p "$S/plain folder/team"
new_repo "$S/plain folder/team/app"
commit_file "$S/plain folder/team/app" a.txt
printf 'changed\n' >>"$S/plain folder/team/app/a.txt"

# DIRTY_REPOS_EXAMPLE=1 prints one run on the five sample folders and stops.
if [ -n "${DIRTY_REPOS_EXAMPLE:-}" ]; then
  cd "$S" || exit 1
  if sh "$DIRTY_REPOS" clean modified untracked staged "plain folder"; then
    echo "exit code: 0"
  else
    echo "exit code: $?"
  fi
  exit 0
fi

# ---- extra folders for the edge cases ----
X=$T/extra
new_repo "$X/multi"
for f in m1 m2 m3; do printf '%s\n' "$f" >"$X/multi/$f"; done
g -C "$X/multi" add m1 m2 m3
g -C "$X/multi" commit -q -m files
printf 'edit\n' >>"$X/multi/m1"
rm "$X/multi/m2"
g -C "$X/multi" mv m3 m4
printf 's\n' >"$X/multi/s"
g -C "$X/multi" add s
mkdir "$X/multi/ud"
printf 'x\n' >"$X/multi/ud/one"
printf 'y\n' >"$X/multi/ud/two"
printf 'u\n' >"$X/multi/u"

new_repo "$X/hidden-untracked"
g -C "$X/hidden-untracked" config status.showUntrackedFiles no
printf 'new\n' >"$X/hidden-untracked/new.txt"

new_repo "$X/stale"
commit_file "$X/stale" a.txt
touch -t 202001010000 "$X/stale/a.txt"

mkdir -p "$X/broken/.git"

new_repo "$X/outer"
commit_file "$X/outer" a.txt
printf 'changed\n' >>"$X/outer/a.txt"
mkdir -p "$X/outer/sub/.git"

mkdir -p "$X/bare-holder"
g init -q --bare "$X/bare-holder/r.git"

new_repo "$X/wt-base"
commit_file "$X/wt-base" a.txt
g -C "$X/wt-base" worktree add -q "$X/wt-holder/wt" -b wt
printf 'new\n' >"$X/wt-holder/wt/new.txt"

mkdir -p "$X/link-holder"
ln -s "$S/modified" "$X/link-holder/link"

new_repo "$X/nm/node_modules/pkg"
printf 'new\n' >"$X/nm/node_modules/pkg/new.txt"

new_repo "$X/dot/.cache/proj"
printf 'new\n' >"$X/dot/.cache/proj/new.txt"

new_repo "$X/depth6/a/b/c/d/e/f"
printf 'new\n' >"$X/depth6/a/b/c/d/e/f/new.txt"

new_repo "$X/depth7/a/b/c/d/e/f/g"
printf 'new\n' >"$X/depth7/a/b/c/d/e/f/g/new.txt"

new_repo "$X/depth9/a/b/c/d/e/f/g/h/i"
printf 'new\n' >"$X/depth9/a/b/c/d/e/f/g/h/i/new.txt"

# A repository whose config names a file monitor program that leaves a marker.
FSM_MARK=$T/fsm-marker
FSM_HOOK=$T/fsm-hook.sh
printf '#!/bin/sh\necho ran >>"%s"\n' "$FSM_MARK" >"$FSM_HOOK"
chmod +x "$FSM_HOOK"
new_repo "$X/fsm"
commit_file "$X/fsm" a.txt
g -C "$X/fsm" config core.fsmonitor "$FSM_HOOK"
printf 'new\n' >"$X/fsm/new.txt"

# A folder of links to the commands the script needs, and no git.
mkdir -p "$T/nogit-bin"
ln -s "$(command -v grep)" "$T/nogit-bin/grep"

printf 'not a folder\n' >"$X/a-file"

set +e

# ---- helpers ----
lines() { printf '%s\n' "$@"; }

# Sort every line but the last so the order a shell lists folders in cannot matter.
norm() {
  printf '%s\n' "$1" | sed '$d' | LC_ALL=C sort
  printf '%s\n' "$1" | tail -n 1
}

run() {
  # A run that does not finish in 30 seconds is stopped and fails its case.
  # RUN_PATH, when set, is the PATH the script runs with.
  # RUN_FLAGS is passed to the shell before the script name.
  PATH=${RUN_PATH:-$PATH} "$SH" $RUN_FLAGS "$DIRTY_REPOS" "$@" >"$T/stdout" 2>"$T/stderr" &
  run_pid=$!
  (
    waited=0
    while [ "$waited" -lt 30 ]; do
      sleep 1
      waited=$((waited + 1))
    done
    kill "$run_pid" 2>/dev/null
  ) &
  watchdog=$!
  wait "$run_pid"
  RC=$?
  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  OUT=$(sed "s|$T|<T>|g" "$T/stdout")
  ERR=$(sed "s|$T|<T>|g" "$T/stderr")
}

PASS=0
FAIL=0
STAMP=0
record() { # OK(0/1) NAME [DETAIL]
  if [ "$1" -eq 0 ]; then
    PASS=$((PASS + 1))
    printf 'PASS  %-5s  %s\n' "$SHNAME" "$2"
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL  %-5s  %s\n' "$SHNAME" "$2"
    [ -z "$3" ] || printf '%s\n' "$3" | sed 's/^/        /'
  fi
}

expect() { # NAME EXPECTED_OUT EXPECTED_RC
  want=$(norm "$2")
  got=$(norm "$OUT")
  if [ "$got" = "$want" ] && [ "$RC" = "$3" ]; then
    record 0 "$1"
  else
    record 1 "$1" "expected exit $3 and:
$want
got exit $RC and:
$got"
  fi
}

expect_stderr() { # NAME PATTERN
  if printf '%s\n' "$ERR" | grep -q -- "$2"; then
    record 0 "$1"
  else
    record 1 "$1" "stderr did not contain '$2'; it was: $ERR"
  fi
}

digest() { # FOLDER: checksum of every file under it, paths included
  (cd "$1" && find . -type f -exec cksum {} + | LC_ALL=C sort)
}

run_cases() {
  # The five sample folders together.
  run "$S/clean" "$S/modified" "$S/untracked" "$S/staged" "$S/plain folder"
  expect "five folders: four changed repositories, one count each, total, exit 1" "$(lines \
    '    1  <T>/samples/modified' \
    '    1  <T>/samples/untracked' \
    '    1  <T>/samples/staged' \
    '    1  <T>/samples/plain folder/team/app' \
    'TOTAL: 4 files in 4 repositories (5 scanned)')" 1

  run "$S/clean"
  expect "clean alone: no repository line, zero total, exit 0" \
    'TOTAL: 0 files in 0 repositories (1 scanned)' 0

  run "$S/modified"
  expect "modified: an edited tracked file counts once" "$(lines \
    '    1  <T>/samples/modified' \
    'TOTAL: 1 files in 1 repositories (1 scanned)')" 1

  run "$S/untracked"
  expect "untracked: a repository with only an untracked file is listed" "$(lines \
    '    1  <T>/samples/untracked' \
    'TOTAL: 1 files in 1 repositories (1 scanned)')" 1

  run "$S/staged"
  expect "staged: a new file in the index is listed" "$(lines \
    '    1  <T>/samples/staged' \
    'TOTAL: 1 files in 1 repositories (1 scanned)')" 1

  # Depth.
  run "$S"
  expect "default depth finds the nested repository" "$(lines \
    '    1  <T>/samples/modified' \
    '    1  <T>/samples/untracked' \
    '    1  <T>/samples/staged' \
    '    1  <T>/samples/plain folder/team/app' \
    'TOTAL: 4 files in 4 repositories (5 scanned)')" 1

  run --max-depth 1 "$S"
  expect "--max-depth 1 misses the nested repository" "$(lines \
    '    1  <T>/samples/modified' \
    '    1  <T>/samples/untracked' \
    '    1  <T>/samples/staged' \
    'TOTAL: 3 files in 3 repositories (4 scanned)')" 1

  run --max-depth 2 "$S"
  expect "--max-depth 2 still misses a repository three levels down" "$(lines \
    '    1  <T>/samples/modified' \
    '    1  <T>/samples/untracked' \
    '    1  <T>/samples/staged' \
    'TOTAL: 3 files in 3 repositories (4 scanned)')" 1

  run --max-depth 3 "$S"
  expect "--max-depth 3 reaches it" "$(lines \
    '    1  <T>/samples/modified' \
    '    1  <T>/samples/untracked' \
    '    1  <T>/samples/staged' \
    '    1  <T>/samples/plain folder/team/app' \
    'TOTAL: 4 files in 4 repositories (5 scanned)')" 1

  run --max-depth 0 "$S"
  expect "--max-depth 0 on a plain folder scans nothing" \
    'TOTAL: 0 files in 0 repositories (0 scanned)' 0

  run --max-depth 0 "$S/modified"
  expect "--max-depth 0 still counts a folder given that is itself a repository" "$(lines \
    '    1  <T>/samples/modified' \
    'TOTAL: 1 files in 1 repositories (1 scanned)')" 1

  run "$X/depth6"
  expect "the default depth of 6 reaches a repository six levels down" "$(lines \
    '    1  <T>/extra/depth6/a/b/c/d/e/f' \
    'TOTAL: 1 files in 1 repositories (1 scanned)')" 1

  run "$X/depth7"
  expect "the default depth of 6 does not reach a repository seven levels down" \
    'TOTAL: 0 files in 0 repositories (0 scanned)' 0

  run --max-depth 7 "$X/depth7"
  expect "--max-depth 7 reaches it" "$(lines \
    '    1  <T>/extra/depth7/a/b/c/d/e/f/g' \
    'TOTAL: 1 files in 1 repositories (1 scanned)')" 1

  # Counts.
  run "$X/multi"
  expect "modified, deleted, renamed, staged and untracked each count once, a new folder once" "$(lines \
    '    6  <T>/extra/multi' \
    'TOTAL: 6 files in 1 repositories (1 scanned)')" 1

  run "$X/multi" "$S/modified"
  expect "totals add across repositories" "$(lines \
    '    6  <T>/extra/multi' \
    '    1  <T>/samples/modified' \
    'TOTAL: 7 files in 2 repositories (2 scanned)')" 1

  run "$X/hidden-untracked"
  expect "untracked files count even when the repository config hides them" "$(lines \
    '    1  <T>/extra/hidden-untracked' \
    'TOTAL: 1 files in 1 repositories (1 scanned)')" 1

  # Paths.
  run "$S/modified/"
  expect "a trailing slash on the folder is dropped from the printed path" "$(lines \
    '    1  <T>/samples/modified' \
    'TOTAL: 1 files in 1 repositories (1 scanned)')" 1

  run "$S/modified" "$S/modified/"
  expect "the same repository given twice counts once" "$(lines \
    '    1  <T>/samples/modified' \
    'TOTAL: 1 files in 1 repositories (1 scanned)')" 1

  run "$S" "$S/modified"
  expect "a folder and a repository inside it count the repository once" "$(lines \
    '    1  <T>/samples/modified' \
    '    1  <T>/samples/untracked' \
    '    1  <T>/samples/staged' \
    '    1  <T>/samples/plain folder/team/app' \
    'TOTAL: 4 files in 4 repositories (5 scanned)')" 1

  run "$X/dot"
  expect "a repository inside a hidden folder is found" "$(lines \
    '    1  <T>/extra/dot/.cache/proj' \
    'TOTAL: 1 files in 1 repositories (1 scanned)')" 1

  run "$X/nm"
  expect "node_modules is not searched" \
    'TOTAL: 0 files in 0 repositories (0 scanned)' 0

  run "$X/link-holder"
  expect "a symbolic link to a folder is not followed" \
    'TOTAL: 0 files in 0 repositories (0 scanned)' 0

  run "$X/wt-holder"
  expect "a worktree, whose .git is a file, is found" "$(lines \
    '    1  <T>/extra/wt-holder/wt' \
    'TOTAL: 1 files in 1 repositories (1 scanned)')" 1

  run "$X/bare-holder"
  expect "a bare repository has no working tree and is not scanned" \
    'TOTAL: 0 files in 0 repositories (0 scanned)' 0

  # Failures.
  run "$X/broken"
  expect "a broken repository prints a failure line, counts toward neither total, exit 1" "$(lines \
    '?  <T>/extra/broken (git status failed)' \
    'TOTAL: 0 files in 0 repositories (0 scanned)')" 1

  run "$X/outer"
  expect "a broken repository inside a real one does not borrow the outer status" "$(lines \
    '    1  <T>/extra/outer' \
    '?  <T>/extra/outer/sub (git status failed)' \
    'TOTAL: 1 files in 1 repositories (1 scanned)')" 1

  # Read only. A fresh time stamp on every call makes the index stale again, so
  # a run that refreshes it is caught under every shell, not only the first.
  STAMP=$((STAMP + 1))
  touch -t "$(printf '202001010000.%02d' "$STAMP")" "$X/stale/a.txt"
  before=$(digest "$X/stale")
  run "$X/stale"
  after=$(digest "$X/stale")
  expect "a clean repository with a stale index reports no changes" \
    'TOTAL: 0 files in 0 repositories (1 scanned)' 0
  if [ "$before" = "$after" ]; then
    record 0 "the run leaves every file of the repository, .git/index included, unchanged"
  else
    record 1 "the run leaves every file of the repository, .git/index included, unchanged" \
      "before:
$before
after:
$after"
  fi

  : >"$S/modified/.git/index.lock"
  run "$S/modified"
  expect "a stale index.lock does not stop the run from reporting the repository" "$(lines \
    '    1  <T>/samples/modified' \
    'TOTAL: 1 files in 1 repositories (1 scanned)')" 1
  if [ -f "$S/modified/.git/index.lock" ]; then
    record 0 "the stale index.lock is still there after the run"
  else
    record 1 "the stale index.lock is still there after the run"
  fi
  rm -f "$S/modified/.git/index.lock"

  # Rule: the script never starts git's file monitor. A repository's config may
  # name a program there, and git runs it as the user; the override forbids that.
  rm -f "$FSM_MARK"
  run "$X/fsm"
  expect "a repository config that names a file monitor program is still counted" "$(lines \
    '    1  <T>/extra/fsm' \
    'TOTAL: 1 files in 1 repositories (1 scanned)')" 1
  if [ ! -e "$FSM_MARK" ]; then
    record 0 "the file monitor program a repository config names is never run"
  else
    record 1 "the file monitor program a repository config names is never run" \
      "the program ran and left $FSM_MARK"
  fi
  rm -f "$FSM_MARK"

  # Rule: a depth with leading zeros means the decimal number. The shell would
  # read 08 as an error and 010 as eight.
  run --max-depth 8 "$S/plain folder"
  expect "--max-depth 8 finds a repository two levels down" "$(lines \
    '    1  <T>/samples/plain folder/team/app' \
    'TOTAL: 1 files in 1 repositories (1 scanned)')" 1

  run --max-depth 08 "$S/plain folder"
  expect "--max-depth 08 means 8: same repository, same total line as --max-depth 8" "$(lines \
    '    1  <T>/samples/plain folder/team/app' \
    'TOTAL: 1 files in 1 repositories (1 scanned)')" 1

  run --max-depth 8 "$X/depth9"
  expect "--max-depth 8 does not reach a repository nine levels down" \
    'TOTAL: 0 files in 0 repositories (0 scanned)' 0

  run --max-depth 010 "$X/depth9"
  expect "--max-depth 010 means 10, not octal 8: it reaches a repository nine levels down" "$(lines \
    '    1  <T>/extra/depth9/a/b/c/d/e/f/g/h/i' \
    'TOTAL: 1 files in 1 repositories (1 scanned)')" 1

  run --max-depth 000 "$S"
  expect "--max-depth 000 behaves as 0 on a plain folder" \
    'TOTAL: 0 files in 0 repositories (0 scanned)' 0

  run --max-depth 000 "$S/modified"
  expect "--max-depth 000 still counts a folder given that is itself a repository" "$(lines \
    '    1  <T>/samples/modified' \
    'TOTAL: 1 files in 1 repositories (1 scanned)')" 1

  run --max-depth 000000000000000000000003 "$S"
  expect "zeros are stripped before the length check: 24 digits that mean 3 are accepted" "$(lines \
    '    1  <T>/samples/modified' \
    '    1  <T>/samples/untracked' \
    '    1  <T>/samples/staged' \
    '    1  <T>/samples/plain folder/team/app' \
    'TOTAL: 4 files in 4 repositories (5 scanned)')" 1

  run --max-depth 999999999 "$S/modified"
  expect "--max-depth with nine digits is accepted" "$(lines \
    '    1  <T>/samples/modified' \
    'TOTAL: 1 files in 1 repositories (1 scanned)')" 1

  # Rule: a depth too long for the shell's arithmetic is refused, not run as 0.
  run --max-depth 99999999999999999999 "$S"
  expect "--max-depth with 20 digits exits 2 and prints no total" '' 2
  expect_stderr "--max-depth with 20 digits is named too large on stderr" \
    'dirty-repos: --max-depth is too large: 99999999999999999999'

  run --max-depth 1000000000 "$S"
  expect "--max-depth with ten digits exits 2 and prints no total" '' 2

  # Rule: -h prints the usage line and exits 0 (the same as --help).
  run -h
  expect "-h prints the usage and exits 0" \
    'usage: dirty-repos.sh [--max-depth N] FOLDER...' 0

  # Rule: with no git on PATH the script exits 2 with a message and scans nothing.
  # zsh is started with -f here: a user's own zshenv file may put git back on PATH.
  RUN_PATH=$T/nogit-bin
  if [ "$SHNAME" = zsh ]; then RUN_FLAGS=-f; fi
  run "$S/modified"
  RUN_PATH=
  RUN_FLAGS=
  expect "no git on PATH exits 2 and prints nothing on stdout" '' 2
  expect_stderr "no git on PATH says git not found on stderr" 'git not found'

  # Rule: a caller's GIT_DIR, GIT_WORK_TREE or GIT_INDEX_FILE does not change
  # what a clean repository reports.
  GIT_DIR=$S/untracked/.git
  export GIT_DIR
  run "$S/clean"
  unset GIT_DIR
  expect "a caller GIT_DIR pointing at another repository does not change a clean repository" \
    'TOTAL: 0 files in 0 repositories (1 scanned)' 0

  GIT_WORK_TREE=$S/modified
  export GIT_WORK_TREE
  run "$S/clean"
  unset GIT_WORK_TREE
  expect "a caller GIT_WORK_TREE pointing at another repository does not change a clean repository" \
    'TOTAL: 0 files in 0 repositories (1 scanned)' 0

  GIT_INDEX_FILE=$S/staged/.git/index
  export GIT_INDEX_FILE
  run "$S/clean"
  unset GIT_INDEX_FILE
  expect "a caller GIT_INDEX_FILE pointing at another repository does not change a clean repository" \
    'TOTAL: 0 files in 0 repositories (1 scanned)' 0

  # Rule: a folder reached directly and through a symbolic link is one repository.
  run "$S/modified" "$X/link-holder/link"
  expect "a folder given directly and then through a symbolic link is counted once" "$(lines \
    '    1  <T>/samples/modified' \
    'TOTAL: 1 files in 1 repositories (1 scanned)')" 1

  run "$X/link-holder/link" "$S/modified"
  expect "a folder given through a symbolic link and then directly is counted once" "$(lines \
    '    1  <T>/extra/link-holder/link' \
    'TOTAL: 1 files in 1 repositories (1 scanned)')" 1

  # Usage errors.
  run
  expect "no folder argument exits 2" '' 2
  expect_stderr "no folder argument explains itself on stderr" 'at least one folder'

  run "$T/does not exist"
  expect "a missing folder exits 2 and prints nothing on stdout" '' 2
  expect_stderr "a missing folder is named on stderr" 'not a folder'

  run "$S/modified" "$T/does not exist"
  expect "a missing folder among good ones exits 2 before any scan" '' 2

  run "$X/a-file"
  expect "a file given as a folder exits 2" '' 2

  run --max-depth
  expect "--max-depth without a number exits 2" '' 2

  run --max-depth x "$S"
  expect "--max-depth with a non-number exits 2" '' 2

  run --bogus "$S"
  expect "an unknown option exits 2" '' 2

  run --help
  expect "--help prints the usage and exits 0" \
    'usage: dirty-repos.sh [--max-depth N] FOLDER...' 0
}

# ---- run under every shell present ----
RAN=
SKIPPED=
for name in sh bash zsh dash; do
  path=$(command -v "$name" 2>/dev/null)
  if [ -n "$path" ] && [ -x "$path" ]; then
    RAN="$RAN $name"
  else
    SKIPPED="$SKIPPED $name"
  fi
done
# The system bash on macOS is 3.2, a different program from a newer bash on PATH.
EXTRA=
if [ -x /bin/bash ] && [ "$(command -v bash 2>/dev/null)" != /bin/bash ]; then
  EXTRA=/bin/bash
fi
echo "shells run:${RAN}${EXTRA:+ bash3($EXTRA)}"
echo "shells skipped (not installed):${SKIPPED:- none}"

for name in $RAN; do
  SH=$(command -v "$name")
  SHNAME=$name
  run_cases
done
if [ -n "$EXTRA" ]; then
  SH=$EXTRA
  SHNAME=bash3
  run_cases
fi

echo "cases passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
