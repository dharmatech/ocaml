# OCaml Plan 9 local current state

Last recorded: 2026-07-23 18:36:48 -07:00 America/Los_Angeles

Origin profile: Dharmatech Windows/QEMU development host

Update this file after every accepted or rejected stateful gate and before
handing work to another task.

Treat this as a dated observation, not proof of live state:

- **Recorded** describes what was observed at the timestamp above.
- **Verified** describes the checks completed without guest access.
- **Required next** describes what must be revalidated before acting.

## Pre-publication repository observation

```text
repository: C:\Users\dharm\src\ocaml
branch: plan9-4.14.3-000
HEAD: 3bddbb623ddc0b8d9cfe42c3b190097b99ae6408
tree: 93c05f180764eecce072388353c23d54a9e39dd4
subject: Make Plan 9 README the repository landing page
tracking: origin/plan9-4.14.3-000 equals HEAD
remote: https://github.com/dharmatech/ocaml.git
tracked worktree and index: unchanged
untracked: ten intended onboarding files beneath AGENTS.md,
  docs/design/plan9, and .agents/skills/ocaml-plan9-local
```

This block records the documentation-onboarding state immediately before its
publication commit. After publication it is historical, not a claim about the
current checkout. Read live Git before every task; live Git is authoritative.

## Host tooling boundary

```text
installed p9qemu:
  path: C:\Users\dharm\.local\bin\p9qemu.exe
  reported version: 0.1.0
  SHA-256: 05081e4e15d3ba53b1a1c70e82dd474cdeaaa1c96a6fa1401590e48ae1c6e43c

p9qemu source:
  path: C:\Users\dharm\src\p9qemu
  branch: main
  HEAD: fd723efb031567bb60101e6cd1df98b2ba4ae2c8
  tree: 7d1e81ec4a5466fc0d745b800428ece3757624c6
  tracking: origin/main equals HEAD
  worktree: clean

QEMU:
  path: C:\Program Files\qemu\qemu-system-x86_64.exe
  version: 10.2.0 (v10.2.0-12105-g0f12d445bd)

Drawterm:
  path: C:\Users\dharm\src\drawterm\build\msvc\drawterm.exe
  bytes: 774144
  SHA-256: 746938acdef38625505389886481965d68fc2b91215eee265a46eb6502d4df0a
```

These identities were read without starting QEMU or connecting to Plan 9.
Revalidate installed help and the selected paths before an operational gate.

## Reported native state

The user reports:

```text
known-built source tree: /usr/glenda/src/ocaml
GNU Make source tree: /usr/glenda/src/make
documented compiler prefix: /usr/glenda/lib/unix/ocaml-4.14.3
```

None of those paths, their Git identities, build configuration, artifacts, or
installed compiler behavior were accessed or revalidated during onboarding.
Preserve them until the first separately authorized read-only guest inventory.

## Compiler-lab inventory

```text
OCaml VM root: proposed C:\Users\dharm\vm\ocaml; not created or verified
assigned instance: none
assigned address: none
P9QEMU/Python/QEMU PID: none
serial log: none
native development tree: none
experimental install prefix: none
protected OCaml checkpoint: none assigned
raw evidence root: proposed beneath C:\Users\dharm\vm\ocaml; not created
```

No address is reserved by this record. `127.0.0.1` remains reserved for the
user's default lane. The caml9 task owns its separate repository, running lab,
ports, instances, checkpoints, and current-state. Do not inspect or mutate
them without an explicit stateful ownership transfer.

## Last completed gate

`plan9-onboarding-001` is a documentation-publication milestone. It performed
host-only source and tooling review; created the repository guidance, Plan 9
design documents, local skill, current-state record, and compiler-lab runbook;
and completed an independent documentation-only review. The caml9 task then
ran the official skill validator against the final skill files in its existing
uv/PyYAML environment. Its result was:

```text
Skill is valid!
```

The recorded host tool identities were revalidated without accessing a guest,
VM, port, mounted guest filesystem, or checkpoint.

It did not:

- access a Plan 9 guest or mounted guest filesystem;
- use Drawterm or any forwarded port;
- create, boot, halt, copy, hash, or modify a VM;
- transfer source;
- configure, build, test, or install OCaml;
- change compiler/runtime/library source;
- create or replace an install prefix or checkpoint.

## Exact next gate

The next proposed gate is `plan9-compiler-lab-preflight-001`, separately
authorized and host-only. It should:

- confirm with the caml9 stateful operator which instances, addresses, ports,
  and checkpoints remain out of scope without inspecting, booting, copying,
  hashing, or otherwise accessing any caml9 instance or checkpoint;
- revalidate the P9QEMU, QEMU, and Drawterm identities;
- compare prospective future origins, including the public Drawterm-ready image
  and a separately authorized future derivation, without operationally
  selecting or mutating either;
- compare candidate future destinations, loopback addresses, serial-log
  policies, and evidence roots without reserving or creating them;
- not create the proposed `C:\Users\dharm\vm\ocaml` parent directory;
- run `p9qemu image create --dry-run` only with a nonexistent destination
  beneath an already existing parent, while recording the bounded manifest
  network access and host-cache effects; and
- run `p9qemu start --dry-run` only if the preflight discovers an already
  existing, genuinely independent OCaml instance.

That preflight does not create a parent, destination, or instance; start an
instance; select or mutate a recovery source; or access a guest. A later,
separately authorized compiler-lab inventory gate may create or start a
selected independent instance and inspect the reported native OCaml and GNU
Make trees, known compiler prefix, digest commands, and build tools without
modifying them.

## Recovery boundary

No OCaml-project compiler-lab recovery boundary has been selected. The reported
known-built source tree and compiler prefix are preservation boundaries, not
yet verified checkpoints.

Do not reuse caml9's protected checkpoints or mutable labs as OCaml compiler
recovery boundaries. Select or create an independent OCaml instance only after
the user approves the exact lab phase.
