# dirty-repos

dirty-repos is a small POSIX shell script. It takes one or more folders, finds every git repository under them, and lists each repository that has modified, staged or untracked files, with a count per repository and a total. Work that exists only in a working tree is lost by a clean, a sync or a wipe, so run it first and see in a couple of minutes what would go.

## Quick start

```
sh dirty-repos.sh ~/code ~/projects
sh tests/test.sh
```

It needs a POSIX shell and git 2.15 or newer (`GIT_OPTIONAL_LOCKS` starts there). There is nothing to install. The tests were run with git 2.54.0 (Apple Git-157), under `sh`, `bash`, `zsh` and `dash`.

The script writes nothing into the folders it scans. It runs `git status` with `GIT_OPTIONAL_LOCKS=0`, so it takes no index lock and does not refresh an index, and with `core.fsmonitor=false`, so it does not start git's file monitor. It does run `git status` in each repository, and git reads that repository's own config and attributes, so a program a repository names there (a clean filter, for example) is run by git as you. Scan folders whose repositories you would run `git status` in yourself.

## Example

`tests/test.sh` builds five sample folders in a temporary folder: `clean` (a repository with one commit and no changes), `modified` (a committed file, then edited), `untracked` (one untracked file), `staged` (a new file added to the index) and `plain folder` (not a repository, with a repository two levels down that has one edited file). Setting `DIRTY_REPOS_EXAMPLE=1` makes the test print one run on those folders and stop:

```
$ DIRTY_REPOS_EXAMPLE=1 sh tests/test.sh
    1  modified
    1  untracked
    1  staged
    1  plain folder/team/app
TOTAL: 4 files in 4 repositories (5 scanned)
exit code: 1
```

The four repositories with changes are listed. `clean` is scanned, so it counts in the five, but it has nothing to list.

## Options and exit codes

```
sh dirty-repos.sh [--max-depth N] FOLDER...
```

- `--max-depth N` searches N folders below each FOLDER. The default is 6. A FOLDER that is itself a repository is always checked, even with `--max-depth 0`. Leading zeros are dropped, so `08` means 8 and `010` means 10. A number of more than 9 digits (after the zeros) is refused with exit 2.
- `-h` and `--help` print the usage line and exit 0.

Options come before folders. A folder whose name starts with a dash is written `./-name`; `-name` is refused as an unknown option.

A repository is a folder that contains a `.git` entry, which may be a folder or a file (worktrees and submodules use a file). The search goes inside repositories too, so nested repositories are found. It does not enter `.git` or `node_modules`, and it does not follow symbolic links below a FOLDER. A repository reached twice, for example through overlapping folders, is counted once.

Each line is the count right-aligned in at least five columns, two spaces, then the path as found. The count is the number of lines in `git status --porcelain`. A modified, staged, deleted or untracked file counts once, and a new untracked folder counts once, as git reports it. A rename staged with `git mv` counts once. A plain `mv` that git has not been told about counts as two, one deleted file and one untracked file. Untracked files are counted even when a repository's own config hides them from `git status`. The last line is `TOTAL: F files in R repositories (S scanned)`, where R is the repositories with changes and S is the repositories whose status was read.

If `git status` fails for a repository, the line is `?  PATH (git status failed)`. That repository counts toward neither F, R nor S. A `.git` entry that git does not accept as that folder's own repository is treated the same way, so a broken one inside a healthy repository does not borrow the outer repository's status.

| Exit code | Meaning |
| --- | --- |
| 0 | No repository has changes |
| 1 | At least one repository has changes, or a `git status` failed |
| 2 | Usage error, a FOLDER that is not a folder, or git not found |

Paths with spaces work.

## Limits

- It does not report commits that were never pushed, stashes, or ignored files.
- A repository deeper than the depth limit is not scanned.
- A bare repository has no working tree, so it is not scanned.
- A repository inside another repository's working tree is listed on its own, and the outer repository also counts the inner folder once as an untracked entry, so an inner repository can add one to its parent's count (a clean repository holding a clean inner repository printed 1).
- A submodule is a repository too. A clean one adds nothing. A modified one is counted once as a modified entry in its parent and is listed on its own as well (in a run, a modified submodule gave 1 for the parent and 1 for the submodule).
- A folder the script cannot read is skipped without a message, so a repository inside it is not found. An unreadable folder inside a repository hides the untracked files in it, so a repository whose only changes are there prints no line.
- A path that contains a newline is counted once and printed over two lines.
- A very large untracked tree makes `git status` slow.

## Tests

`sh tests/test.sh` runs the script under each shell present and prints `cases passed: N, failed: M`. `sh tests/mutate.sh` breaks a copy of the script in 30 ways, one at a time, and checks that `tests/test.sh` fails for each; in the run for this README, all 30 were caught.

## License

MIT. See `LICENSE`.

## Built at San Diego AI Studio

This script comes out of San Diego AI Studio, the builders' community in San Diego. More of what its members build is at https://sandiegoaistudio.com/projects.
