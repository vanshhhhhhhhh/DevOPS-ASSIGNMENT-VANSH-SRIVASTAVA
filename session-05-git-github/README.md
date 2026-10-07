# Session 05: Git & GitHub

**Name:** Vansh Srivastava
**Enrollment No.:** 24bcs10567
**Session:** 05

Session 05 covered Git and GitHub: the working tree, staging area and commits, branches, and the common commands from the Git cheat sheets linked in the course repo (`session5-git-github/resources.md`). For the homework I tested `git commit -a -m` against `git commit -m`, and practised `git cherry-pick` by copying one fix commit from a feature branch into `main`. Both exercises ran in throwaway Git repositories outside this repo; every command and its real output is below.

## Folder structure

```text
session-05-git-github/
├── README.md                     # this file: the commands, real output and what I observed
├── .gitignore                    # ignores the demo repos if the scripts are run inside this folder
└── scripts/
    ├── lib.sh                    # run/block helpers: print "$ command", then its output
    ├── task1-commit-a.sh         # Task 1: commit -a -m vs commit -m
    └── task2-cherry-pick.sh      # Task 2: cherry-pick a commit from a branch into main
```

## Environment

```bash
$ git --version
git version 2.50.1 (Apple Git-155)
$ git config --global user.name
Vansh Srivastava
```

- macOS 26.6.2 on Apple Silicon, Git 2.50.1, my normal global Git identity.
- Both scripts take an empty directory as an argument and create their demo repository inside it, so they never touch a real project. I ran them like this, from an empty scratch folder (not inside this assignment repo):

```bash
$ bash scripts/task1-commit-a.sh <empty-dir>
$ bash scripts/task2-cherry-pick.sh <empty-dir>
```

The commit hashes below come from those runs; running the scripts again gives different hashes because hashes include the time.

## Task 1: git commit -a -m vs git commit -m

### The difference

Git has three places a change can be: the **working tree** (files on disk), the **staging area** (index, what the next commit will contain) and the **repository** (commits).

- `git commit -m "msg"` commits **only what is already staged** with `git add`.
- `git commit -a -m "msg"` first stages **every modified or deleted file that Git already tracks**, then commits. It is the same as `git add -u` followed by `git commit -m`.
- `-a` **never adds new (untracked) files**. A new file always needs `git add` once.

### Setup: a repo with two tracked files

```bash
$ git init -q -b main commit-a-demo && cd commit-a-demo
$ echo "line 1" > app.txt && echo "# Notes" > notes.md
$ git add app.txt notes.md
$ git commit -m "Initial commit: add app.txt and notes.md"
[main (root-commit) a618b80] Initial commit: add app.txt and notes.md
 2 files changed, 2 insertions(+)
 create mode 100644 app.txt
 create mode 100644 notes.md
```

### Make two kinds of change

```bash
$ echo "line 2" >> app.txt
$ echo "I am a brand new file" > new.txt
$ git status --short
 M app.txt
?? new.txt
```

`M` in the second column = modified in the working tree but not staged; `??` = untracked (Git has never seen `new.txt`).

### Test 1: git commit -m without git add

```bash
$ git commit -m "Try plain commit -m without git add"
On branch main
Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
	modified:   app.txt

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	new.txt

no changes added to commit (use "git add" and/or "git commit -a")
$ git status --short
 M app.txt
?? new.txt
```

Nothing was committed. Git says `no changes added to commit` and even suggests `git add` or `git commit -a`. Plain `-m` only takes the staging area, and the staging area was empty.

### Test 2: git commit -a -m

```bash
$ git commit -a -m "Commit with -a: stages modified tracked files"
[main d709293] Commit with -a: stages modified tracked files
 1 file changed, 1 insertion(+)
$ git show --stat --format="%h %s" HEAD
d709293 Commit with -a: stages modified tracked files

 app.txt | 1 +
 1 file changed, 1 insertion(+)
$ git status --short
?? new.txt
```

This time the commit worked, but `git show --stat` proves it contains **only `app.txt`** (the modified tracked file). `new.txt` is still `??` untracked after the commit: `-a` did not pick it up.

### A new file needs git add

```bash
$ git add new.txt
$ git commit -m "Add new.txt with git add + commit -m"
[main e10ee6a] Add new.txt with git add + commit -m
 1 file changed, 1 insertion(+)
 create mode 100644 new.txt
$ git status --short
```

After `git add new.txt`, a normal `git commit -m` commits it (`create mode`), and the working tree is clean (empty `git status --short`).

### Choosing what to commit: -m commits only the staged part

```bash
$ echo "line 3" >> app.txt && echo "second line" >> new.txt
$ git add new.txt
$ git status --short
 M app.txt
M  new.txt
$ git commit -m "commit -m commits only what is staged (new.txt)"
[main 6d3d329] commit -m commits only what is staged (new.txt)
 1 file changed, 1 insertion(+)
$ git status --short
 M app.txt
$ git commit -a -m "commit -a picks up the remaining app.txt change"
[main 19abdef] commit -a picks up the remaining app.txt change
 1 file changed, 1 insertion(+)
$ git status --short
```

I changed both files but staged only `new.txt` (`M ` in the first column = staged, ` M` in the second = not staged). `git commit -m` committed just `new.txt` and left `app.txt` modified; then `git commit -a -m` committed the rest. This is why `git add` + `commit -m` is better when one change should be split into separate, meaningful commits.

### -a also stages deleted files

```bash
$ rm notes.md
$ git status --short
 D notes.md
$ git commit -a -m "commit -a also stages deleted tracked files"
[main fc72577] commit -a also stages deleted tracked files
 1 file changed, 1 deletion(-)
 delete mode 100644 notes.md
```

Deleting a tracked file with plain `rm` is also picked up by `-a` (`delete mode`), without needing `git rm`.

### History

```bash
$ git log --oneline
fc72577 commit -a also stages deleted tracked files
19abdef commit -a picks up the remaining app.txt change
6d3d329 commit -m commits only what is staged (new.txt)
e10ee6a Add new.txt with git add + commit -m
d709293 Commit with -a: stages modified tracked files
a618b80 Initial commit: add app.txt and notes.md
$ git log --format="%h %s" --name-status
fc72577 commit -a also stages deleted tracked files

D	notes.md
19abdef commit -a picks up the remaining app.txt change

M	app.txt
6d3d329 commit -m commits only what is staged (new.txt)

M	new.txt
e10ee6a Add new.txt with git add + commit -m

A	new.txt
d709293 Commit with -a: stages modified tracked files

M	app.txt
a618b80 Initial commit: add app.txt and notes.md

A	app.txt
A	notes.md
```

`--name-status` shows what each commit contained: `A` added, `M` modified, `D` deleted. The commits made with `-a` only ever contain `M` or `D` for files that were already tracked; the `A` for `new.txt` came from `git add`.

### Summary

| | `git commit -m "msg"` | `git commit -a -m "msg"` |
|---|---|---|
| Modified tracked files | only if staged with `git add` | staged automatically |
| Deleted tracked files | only if staged (`git rm` / `git add`) | staged automatically |
| New untracked files | only if staged with `git add` | **never** |
| Partly staged changes | commits only the staged part | commits everything tracked |
| Good for | precise, split commits | quick commits when every tracked change belongs together |

## Task 2: Cherry-pick

`git cherry-pick <commit>` takes the changes of one existing commit and applies them as a **new** commit on the current branch. A typical use: a bug fix was made on a feature branch that is not ready to merge, but `main` needs the fix now.

### Step 1: create 3 commits on main and look at the log

```bash
$ git init -q -b main cherry-pick-demo && cd cherry-pick-demo
$ printf "# Cherry pick demo\nA tiny app for practising git.\n" > README.md && git add README.md && git commit -q -m "main: add README" && git log -1 --format="%h %s"
fb92c5a main: add README
$ printf "def greet(name):\n    return \"Hello \" + name\n" > app.py && git add app.py && git commit -q -m "main: add greet function" && git log -1 --format="%h %s"
78dab24 main: add greet function
$ printf "PORT=8080\nDEBUG=false\n" > config.env && git add config.env && git commit -q -m "main: add config" && git log -1 --format="%h %s"
caa3b39 main: add config
$ git log --oneline
caa3b39 main: add config
78dab24 main: add greet function
fb92c5a main: add README
```

### Step 2: create a branch and make 3 commits on it

```bash
$ git switch -c feature
Switched to a new branch 'feature'
$ printf "\ndef login(user):\n    return user + \" logged in\"\n" >> app.py && git commit -q -a -m "feature: add login function" && git log -1 --format="%h %s"
1412757 feature: add login function
$ printf "# Cherry pick demo\nA tiny app for practicing git.\n" > README.md && git diff --stat && git commit -q -a -m "fix: correct spelling in README" && git log -1 --format="%h %s"
 README.md | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
bd51666 fix: correct spelling in README
$ printf "\ndef logout(user):\n    return user + \" logged out\"\n" >> app.py && git commit -q -a -m "feature: add logout function" && git log -1 --format="%h %s"
6d45446 feature: add logout function
$ git log --oneline
6d45446 feature: add logout function
bd51666 fix: correct spelling in README
1412757 feature: add login function
caa3b39 main: add config
78dab24 main: add greet function
fb92c5a main: add README
```

The middle commit is a spelling fix in `README.md`, mixed in with two unfinished feature commits in `app.py`.

### Step 3: use git log to identify the commit to cherry-pick

```bash
$ git log --oneline --graph --all
* 6d45446 feature: add logout function
* bd51666 fix: correct spelling in README
* 1412757 feature: add login function
* caa3b39 main: add config
* 78dab24 main: add greet function
* fb92c5a main: add README
$ git log --oneline main..feature
6d45446 feature: add logout function
bd51666 fix: correct spelling in README
1412757 feature: add login function
$ git log --oneline --grep="fix:" feature
bd51666 fix: correct spelling in README
$ FIX=$(git log --format=%h --grep="fix:" feature); echo "commit to cherry-pick: $FIX"
commit to cherry-pick: bd51666
$ git show --format="%h %s" "$FIX"
bd51666 fix: correct spelling in README

diff --git a/README.md b/README.md
index 119a78e..9417d4e 100644
--- a/README.md
+++ b/README.md
@@ -1,2 +1,2 @@
 # Cherry pick demo
-A tiny app for practising git.
+A tiny app for practicing git.
```

- `--graph --all` shows the whole history; at this point `main` and `feature` are on one line because `feature` just has 3 more commits.
- `main..feature` lists the commits that are on `feature` but not on `main`.
- `--grep="fix:"` searches commit messages; it found `bd51666`. I stored it in `FIX` and checked with `git show` that it only changes the README line.

### Step 4: cherry-pick it into main

```bash
$ git switch main
Switched to branch 'main'
$ cat README.md
# Cherry pick demo
A tiny app for practising git.
$ git cherry-pick "$FIX"
[main fddc010] fix: correct spelling in README
 Date: Wed Oct 7 23:41:00 2026 +0530
 1 file changed, 1 insertion(+), 1 deletion(-)
```

On `main` the README still had "practising". `git cherry-pick` applied the fix as a new commit `fddc010` on `main`. The `Date:` line shows it keeps the original author date of the commit it copied.

### Step 5: verify it is now on main

```bash
$ git log --oneline
fddc010 fix: correct spelling in README
caa3b39 main: add config
78dab24 main: add greet function
fb92c5a main: add README
$ git log --oneline --graph --all
* 6d45446 feature: add logout function
* bd51666 fix: correct spelling in README
* 1412757 feature: add login function
| * fddc010 fix: correct spelling in README
|/  
* caa3b39 main: add config
* 78dab24 main: add greet function
* fb92c5a main: add README
$ cat README.md
# Cherry pick demo
A tiny app for practicing git.
$ ls
README.md
app.py
config.env
$ grep -c "def " app.py
1
$ git cherry -v main feature
+ 1412757aed07b7816c3c8071048fb9f3a6f0828d feature: add login function
- bd51666519df281a835ea1babc0ca901a53e4261 fix: correct spelling in README
+ 6d4544635165c431cf0b7ea063699402f6abd29c feature: add logout function
$ git branch --contains "$FIX"
  feature
$ git status
On branch main
nothing to commit, working tree clean
```

What this shows:

- `git log --oneline` on `main` now has the fix commit on top.
- The graph shows that `main` and `feature` have split: the fix exists twice, as `bd51666` on `feature` and `fddc010` on `main`. A cherry-pick **copies** a commit; it gets a new hash because its parent is different.
- `README.md` on `main` has the corrected spelling, but `main` did **not** get the feature work: there is still only one function (`greet`) in `app.py`.
- `git cherry -v main feature` compares by content: `-` means "an equivalent change is already in main" (the fix), `+` means "not in main yet" (the two feature commits).
- `git branch --contains bd51666` only lists `feature`, because `main` contains a copy with a different hash, not the original commit.

Useful extras I read about: `git cherry-pick -x <hash>` adds "(cherry picked from commit ...)" to the message so the copy can be traced; if a cherry-pick conflicts, fix the files, `git add` them and run `git cherry-pick --continue` (or `--abort` to cancel).

## What I learned

- `git commit -a` is a shortcut for `git add -u` + `git commit`: it handles modified and deleted tracked files, never new files.
- Plain `git commit -m` commits only the staging area, which lets me split my work into small, focused commits.
- `git status --short` is the fastest way to see what is staged (first column), unstaged (second column) and untracked (`??`).
- `git cherry-pick` copies a single commit onto another branch with a new hash. It is great for hotfixes and backports, but the same change then lives in two commits, so merging is still the normal way to bring a whole branch in.
- `git log` with `--oneline`, `--graph --all`, `main..feature` and `--grep` makes it easy to find the exact commit to work with.
