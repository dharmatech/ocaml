# Plan 9 development workflow

## Authoritative source

The mainstream-Git checkout on Windows is authoritative:

```text
C:\Users\dharm\src\ocaml
```

Edit, review, stage, commit, and push there. Use Plan 9 only as the native
build and execution environment. Do not develop competing changes in a git9
checkout and never copy `.git` between implementations.

The reported `/usr/glenda/src/ocaml` tree produced the known compiler. Preserve
it until it is independently revalidated and deliberately assigned another
role. Active work uses a distinct native development tree.

## Developmental inner loop

The fast loop is:

1. inspect live Windows Git and identify the exact intended changes;
2. create a manifest of additions, changes, and deletions;
3. copy only those files through Drawterm's `/mnt/term` mount;
4. apply them to a disposable tree on native Plan 9 storage;
5. verify the copied paths and hashes;
6. configure, build, and test in that native tree; and
7. copy only useful logs or small results back to the host.

The manifest records operation, repository-relative path, size, and host
digest. Reject absolute paths, `..`, `.git`, unlisted files, destination paths
outside the disposable tree, and hash mismatches. Apply deletions only to the
declared disposable tree.

Do not compile inside `/mnt/term/C:/...`. The bridge is a transfer boundary,
not a build filesystem.

## Native build

Use the existing APE/GNU Make helpers unless a separately scoped build-system
milestone changes them:

```sh
ape/psh
MAKE=/usr/glenda/lib/unix/bin/gmake
export MAKE
build-aux/plan9/configure.sh --prefix=<new-versioned-prefix>
build-aux/plan9/build-world.sh
build-aux/plan9/install.sh
```

Revalidate the actual GNU Make and C compiler paths in the assigned lab. Do not
assume the known reference tree or prefix is current merely because the
repository documentation names it.

Install every experimental compiler under a fresh versioned prefix. Run
source-tree checks and then repeat the consumer-facing checks using only the
installed prefix from native `rc`.

## Exact milestone source

Inner-loop file copies are diagnostic. A milestone requires a fresh archive of
the exact reviewed Windows Git index:

1. reject unstaged tracked changes outside the declared record-only boundary;
2. reject unexpected untracked files;
3. record `HEAD` and `git write-tree`;
4. export the exact index without `.git` or build products;
5. record archive SHA-1 and SHA-256;
6. verify the transfer digest in Plan 9;
7. extract into a fresh native directory; and
8. build and test only that extracted source.

The repository contains at least one gitlink. The eventual export tool must
record each gitlink identity and explicitly include any required submodule
content; do not silently assume `git archive` includes it.

Documentation-only closeout after an exact build may record both the tested
implementation subtree and the final full index, but any implementation change
requires a new exact build.

## Evidence

For each meaningful native run, retain:

- Windows branch, `HEAD`, index tree, and dirty-state result;
- transfer manifest and archive hashes;
- Plan 9 revision and assigned VM identity;
- source and install paths;
- configure environment and command;
- GNU Make and C compiler identities;
- build, test, install, and smoke-test commands with exit statuses;
- built runtime and library hashes;
- installed prefix inventory;
- `ocamlrun -p` and installed `plan9/plan9.cma` `ocamlobjinfo` results;
- exact consumer command lines;
- failures and corrected retries as distinct attempts; and
- cleanup, shutdown, and host postflight results.

Raw logs stay in the machine-local evidence root declared by the local skill.
Curated tracked notes record stable conclusions and identities rather than
copying full transcripts.

## Publication

Commit and push only a coherent milestone whose exact source passed the
declared native and installed-prefix checks. GitHub is the durable publication
path. Direct git9 access to the Windows `.git` directory is experimental and
is not part of this workflow.
