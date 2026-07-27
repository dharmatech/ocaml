# OCaml Plan 9 local current state

Last recorded: 2026-07-25 18:36:10 -07:00 America/Los_Angeles

Origin profile: Dharmatech Windows/QEMU development host

Update this file after every accepted or rejected stateful gate and before
handing work to another task.

Treat this as a dated observation, not proof of live state:

- **Recorded** describes what was observed at the timestamp above.
- **Verified** describes checks completed in the named gate.
- **Required next** describes what must be revalidated before acting.

## Repository observation

The reviewed Phase 2 implementation candidate is frozen on the qualification
branch:

```text
branch: codex/plan9-phase2-process-primitives-qualification
implementation commit: c8345f28a1be5d59b0ebcc93544e6a6aaa172984
implementation tree: 5e9f01be369aeecbe6d3c8f9a879f6652d685944
parent: 4f3330ede0d6e0e7e0eb573afb5b23cb12d7ca3d
subject: Add Plan 9 native process primitives candidate
candidate paths: exactly 19
otherlibs/plan9 subtree: 73b4058baaae819c30a7f868d38e6d910dd39297
runtime subtree: 582dc1cf834e2e3c8818c82d49d66c071a4434d4
```

That commit includes the complete reviewed implementation, build integration,
focused test harness, acknowledgment-recovery corrections, final-unit API
shape, warning cleanup, and handled-interruption harness correction. It is a
qualification candidate backed by the incremental build and test observations
below; it is not final Gate 2.4 acceptance. This record and the canonical
`RFNOMNT` evidence wording are layered after that exact implementation tree.
Read live Git for the record commit and remote publication identity.

The clean published boundaries at the start of
`plan9-phase-2-cross-repository-state-reconciliation-001` were:

```text
OCaml repository: C:\Users\dharm\src\ocaml
branch: plan9-4.14.3-000
HEAD: 0cac1612379a1fad427c82663fc81454a7b2d15a
tree: 32c6e9f5de738dcbf8bc28ff04ae9ecd629f49e1
tracking and advertised origin ref: equal to HEAD

caml9 repository: C:\Users\dharm\src\caml9
branch: front
HEAD: 838a8a22d2621bc39861430aedfe441c337acee8
tree: f6157ab9a5b65f65a51d767264bd8a8b823323ab
tracking and advertised origin ref: equal to HEAD
```

Both indexes and worktrees were clean. These are pre-publication identities;
read live Git for the commits containing this reconciliation record.

The published boundary at the start of
`plan9-phase-1-env-completion-001` was:

```text
repository: C:\Users\dharm\src\ocaml
branch: plan9-4.14.3-000
HEAD: 53ed651d50f58e644be359e4066ead7825ce0e9e
tree: d81d2cd9705c380ab66a27c854aa7db993d866e8
tracking: origin/plan9-4.14.3-000 equals HEAD
remote: https://github.com/dharmatech/ocaml.git
```

The exact accepted implementation index tested on native Plan 9 was:

```text
staged index tree: 7dee13d2b8c9fd159cb90d9834ea7100e5592e3b
otherlibs/plan9 subtree: c7c4d0b98ee94c7ca0fe601244af917dc02ee33f
synthetic archive commit: 8e44df687c09c549e7a37c96ed3d11f437501072
archive bytes: 29798400
archive SHA-256:
  6d9f80a33672973203ac2ca606d52c840a70c29c106a345da6fa7c921809802c
archive SHA-1:
  5307bcc851273cf16a8f7587227890e20ab2f435
```

The archive contained 4,207 entries and 3,842 non-directory entries, had the
expected single prefix, and contained no `.git`. The accepted index includes
two Phase-1-local build corrections: Plan 9 bytecode compilation names the
generic `.cmo` output explicitly, avoiding a false warning 11 caused by
implicit output naming, and the Plan9.Env test recipe runs bytecode through
the freshly built `ocamlrun`.

This current-state update and the other acceptance notes are record-only
documentation layered after the exact tested index. They do not change the
tested implementation subtree. The publication commit and tree are supplied
by live Git; revalidate them rather than treating this dated observation as
live state.

## Host tooling boundary

```text
installed p9qemu:
  path: C:\Users\dharm\.local\bin\p9qemu.exe
  reported version: 0.1.0
  previously recorded SHA-256:
    05081e4e15d3ba53b1a1c70e82dd474cdeaaa1c96a6fa1401590e48ae1c6e43c

QEMU:
  path: C:\Program Files\qemu\qemu-system-x86_64.exe
  previously recorded version: 10.2.0 (v10.2.0-12105-g0f12d445bd)

Drawterm:
  path: C:\Users\dharm\src\drawterm\build\msvc\drawterm.exe
  previously recorded bytes: 774144
  previously recorded SHA-256:
    746938acdef38625505389886481965d68fc2b91215eee265a46eb6502d4df0a
```

The first-boot gate exercised those installed paths successfully but did not
rehash them. P9QEMU generated and launched exactly
`-accel whpx,kernel-irqchip=off`; it reported WHPX operational and performed no
fallback.

## Compiler-lab state

```text
VM root: C:\Users\dharm\vm\ocaml
mutable instance: C:\Users\dharm\vm\ocaml\dev
instance state:
  running after accepted exact-source qualification, dev-002 installation,
  installed-consumer validation, and RC001 packaging
assigned address: 127.0.0.40
forwarded endpoints: 17010, 17019, 17020, 17021, 17022, 17564, 17567
endpoint state:
  QEMU PID 10892 owned all seven at the final RC001 post-copy check; revalidate
  live before acting
P9QEMU shim PID: 35220 at launch
console PID: none recorded
Python PIDs: 36204 and 28120 at launch
QEMU PID: 10892 at launch
accepted native development tree:
  /usr/glenda/src/ocaml-plan9-phase1-completion-001-build-004/
    ocaml-plan9-phase1-env-completion-001-build004
native tree state: exact tested archive, configured and fully built
incremental Phase 2 development tree:
  /usr/glenda/src/ocaml-plan9-phase2-incremental-001
incremental tree state:
  fully built Phase 1 seed plus the reviewed Phase 2 candidate and incremental
  corrections; world build, all five focused suites, warning-clean rerun, and
  handled native interruption test passed
exact-source GitHub qualification tree:
  /usr/glenda/src/ocaml-plan9-phase2-github-qualification-001
exact-source tree state:
  commit d8ec53e72a09d4ff9532778d4dfd0c6b87cb83f2, configured and fully
  built; focused, interruption, and broader upstream tests passed; retained
  intentionally with all build products as the incremental correction base
first experimental prefix:
  /usr/glenda/lib/unix/ocaml-4.14.3-plan9-dev-001
prefix state: installed and accepted for this experiment
second experimental prefix:
  /usr/glenda/lib/unix/ocaml-4.14.3-plan9-dev-002
second-prefix state:
  installed and accepted; 338 files; installed consumer passed without source
  visibility, `-custom`, an alternate runtime, or a consumer C tool
known-working prefix:
  /usr/glenda/lib/unix/ocaml-4.14.3
accepted incremental-setup evidence:
  C:\Users\dharm\vm\ocaml\evidence\
    plan9-phase-2-process-primitives-incremental-setup-001\attempt-001
latest correction/transfer evidence:
  C:\Users\dharm\vm\ocaml\evidence\
    plan9-phase-2-process-primitives-optional-argument-correction-001\
      attempt-001
serial log:
  C:\Users\dharm\vm\ocaml\evidence\
    plan9-phase-2-process-primitives-github-qualification-001\
      attempt-001\serial.raw.log
serial state:
  active while .40 remains running; do not treat size or hash as final
```

The known-working compiler was used only for bounded read-only inventory and
source-archive inspection. Its 336-line inventory was byte-identical before
and after installation, SHA-1
`e871b8a897976a13aa8f4b8283acc61a48e349fe`. It was not used as an
installation destination.

### Halted instance identities

```text
instance.json SHA-256, before and after:
  c87a3a9c2ef79d7640e03c689861cfea0cd73c54c72eea5f77b81cd6d8e46225
immutable base SHA-256:
  7ff689b7b614f6884bf0a1ac525fca10b750934d99640e744823f450d28ff6b8
cached manifest SHA-256:
  d04b06e49c5357cd95b8a8dd47457cd2e935b89d8e49117032b29206874aead2

Phase 1 completion preboot disk bytes: 753795072
Phase 1 completion preboot disk SHA-256:
  73ec81d135de81cbc5f502faf07c917524bce2d934fbe8d4e002a3334aa4b1d0
Phase 1 completion postboot disk bytes: 1387921408
Phase 1 completion postboot disk SHA-256:
  71103c98e39e272a712af778abb90b430dd02e1dfec6335f9742d67154ef1e94

Phase 2 ABI accepted-attempt preboot disk bytes: 1387921408
Phase 2 ABI accepted-attempt preboot disk SHA-256:
  6588efbcb394754a514ea1c3aed4903bbfd1dad6645043d824fcb14563acd8fe
Phase 2 ABI post-probe disk bytes: 1388969984
Phase 2 ABI post-probe disk SHA-256:
  8e89481999df567fca895f4c881388e5935cba4f49e597c3523187f83ebd2a2b

Phase 2 exact-source build preboot disk bytes: 1388969984
Phase 2 exact-source build preboot disk SHA-256:
  8e89481999df567fca895f4c881388e5935cba4f49e597c3523187f83ebd2a2b
current post-failed-build disk bytes: 1465843712
current post-failed-build disk SHA-256:
  5d3e0af857ba8b4f5c58deb14a282e2e94ff7dd9f155894f5399f42bfcabc204

Phase 2 resume preboot disk bytes: 1465843712
Phase 2 resume preboot disk SHA-256:
  5d3e0af857ba8b4f5c58deb14a282e2e94ff7dd9f155894f5399f42bfcabc204
current post-rejected-resume disk bytes: 1465843712
current post-rejected-resume disk SHA-256:
  da1d0ed6be1040723e82205843403d4dfa30d3ed23acdc21f2e36b331db292ca

Phase 2 resume-002 attempt-002 postboot disk bytes: 1465843712
Phase 2 resume-002 attempt-002 postboot disk SHA-256:
  394f84acd690dfc2dc7da767b36408d5c28858b529b73ce48f394df30a1cb5a2
Phase 2 resume-002 attempt-003 postboot disk bytes: 1465843712
Phase 2 resume-002 attempt-003 postboot disk SHA-256:
  9a94e9b938ee2f3d66aea92b82bcdf9fa643796bc719ddbb98d1daf05d8762a9
Phase 2 resume-002 attempt-004 postboot disk bytes: 1465843712
Phase 2 resume-002 attempt-004 postboot disk SHA-256:
  2294632765988ae8332ccf5d833ef61fb55584ccf04d4d399ab957ba037e5cb3
Phase 2 resume-002 attempt-005 postboot disk bytes: 1536884736
Phase 2 resume-002 attempt-005 postboot disk SHA-256:
  dbbc15174325a513ff28db160dfc8fc4ebc9e48043a597943e65fbbcc6066dd5
Phase 2 resume-002 attempt-006 postboot disk bytes: 1635188736
Phase 2 resume-002 attempt-006 postboot disk SHA-256:
  c23344aa7bed26dcc273f0984a9aefacf7740301565992c6ac2f886d631b4104

Phase 2 resume-003 attempt-001 preboot disk bytes: 1635188736
Phase 2 resume-003 attempt-001 preboot disk SHA-256:
  c23344aa7bed26dcc273f0984a9aefacf7740301565992c6ac2f886d631b4104
Phase 2 resume-003 attempt-001 postboot disk bytes: 1635450880
Phase 2 resume-003 attempt-001 postboot disk SHA-256:
  ed36f9d81bbabce29252761f7346cb80f723ca3e0d0141b18c8925a291cc2e8c

Phase 2 accepted incremental closeout disk bytes: 1641086976
Phase 2 accepted incremental closeout disk SHA-256:
  559fb5c400d10727ac38fed2cf5aecafbb701e309d18b881101a5b77ff4c59eb
```

The Phase 1 transition records its mutable build, test, and isolated-prefix
installation. The later transitions record one rejected boot-only ABI
attempt, the accepted harmless installed-ABI probe, the exact-source compile
that stopped at the first runtime link failure, a rejected resume that stopped
before source transfer, the six procedural/native-build resume-002 attempts,
and the warning-16 resume-003 failure recorded below. Halted `qemu-img info`
retained the exact immutable
backing path, both dirty and corrupt flags were false, and `qemu-img check`
reported no errors. A pinned-WHPX dry run passed using a fresh placeholder
serial path and did not create that path.

The caml9 repository, running `.32` lab, processes, listeners, instances,
checkpoints, and active disks remained outside the gate and were not inspected
or changed. The OCaml task remains the sole stateful operator for the shared
P9QEMU/VM/port state, with operational scope limited to this independent OCaml
lab unless the user explicitly expands it.

### Phase 2 cross-repository reconciliation

`plan9-phase-2-cross-repository-state-reconciliation-001` revalidated the
halted `.40` boundary without accessing a guest or any caml9 operational
resource:

```text
instance contents: exactly disk.qcow2 and instance.json
instance state: halted
P9QEMU/Python/QEMU processes matching the exact .40 scope: none
listeners on the seven 127.0.0.40 endpoints: none
bindability: all seven endpoints passed
disk bytes: 1387921408
disk SHA-256:
  71103c98e39e272a712af778abb90b430dd02e1dfec6335f9742d67154ef1e94
instance.json bytes: 1033
instance.json SHA-256:
  c87a3a9c2ef79d7640e03c689861cfea0cd73c54c72eea5f77b81cd6d8e46225
immutable base bytes: 559022080
immutable base SHA-256:
  7ff689b7b614f6884bf0a1ac525fca10b750934d99640e744823f450d28ff6b8
cached manifest bytes: 1472
cached manifest SHA-256:
  d04b06e49c5357cd95b8a8dd47457cd2e935b89d8e49117032b29206874aead2
```

The exact two-object QCOW2 overlay/base relationship passed. Both objects had
clean dirty and corrupt flags, and `qemu-img check` reported zero corruptions,
leaks, or check errors. Installed P9QEMU 0.1.0 rendered only
`whpx,kernel-irqchip=off` with no fallback in a non-launching dry run. Its
fresh serial placeholder remained absent, and the post-dry-run process,
listener, bindability, disk, and manifest checks passed unchanged.

The accepted evidence is retained at:

```text
C:\Users\dharm\vm\ocaml\evidence\
  plan9-phase-2-cross-repository-state-reconciliation-001\attempt-002
```

Attempt 001 is retained as rejected because it captured read-only QCOW2
information before recording the required exact `.40` process and listener
proof. It ran no integrity check, launched no process, and changed no VM,
listener, disk, guest, or repository state.

The explicit compiler-lab handoff had already transferred sole stateful
ownership to the OCaml task. This gate corrected caml9's dated creation record
without transferring ownership back. The caml9 `.32` guest, endpoints, process
chain, disk, serial log, instances, and checkpoints were not queried,
inspected, or changed; their tracked statements retain their earlier dated
observations.

### Phase 2 harmless installed-ABI probe

`plan9-phase-2-process-primitives-abi-probe-001` used only the `.40` compiler
lab. It made no compiler/runtime/library source or installed-prefix change.

Attempt 001 was rejected before any VM, endpoint, QCOW2, P9QEMU, or guest
operation because its process query matched the PowerShell command containing
the target path. Attempt 002 booted only `.40` but was rejected when an
authenticated readiness command used unquoted `name=value` tokens that native
`rc` rejected before execution. It transferred no source and ran no probe.
Attempt 002 then halted through `.40`, closed and rebound every selected
endpoint, and passed halted QCOW2 and pinned-WHPX postflight. Its mutable disk
transitioned to the accepted-attempt preboot identity recorded above.

Accepted attempt 003:

- revalidated clean published OCaml commit
  `4f3330ede0d6e0e7e0eb573afb5b23cb12d7ca3d`, tree
  `c86f23530f2eafe7e95c63539039fd6d909adf76`;
- passed exact instance, process, listener, bindability, identity,
  two-object QCOW2, integrity, and pinned-WHPX preflight;
- launched only `.40` with `whpx,kernel-irqchip=off`;
- recorded P9QEMU PID 2708, Python PIDs 31428 and 30996, and QEMU PID
  6572; QEMU alone owned all seven selected listeners;
- captured installed headers, libc wrappers and symbols, kernel rfork/exec/
  await/pipe/descriptor source, and the relevant manuals;
- transferred only ten purpose-built files through `/mnt/term` into
  `/tmp/plan9-phase-2-process-primitives-abi-probe-001-a003`;
- compiled and ran all native probes from that disposable Plan 9 tree;
- retained the first run as invalid formatted evidence because its probes had
  not installed libc's `%q` formatter, then rehashed, retransferred, compiled,
  and accepted the corrected sources without overwriting the failed evidence;
- removed the disposable tree, unique environment variable, temporary output,
  and every short-lived probe process;
- halted through `.40`; recorded exact P9QEMU exit zero and exit of all launch
  PIDs; closed and rebound all seven endpoints; and
- passed the halted backing, dirty, corrupt, `qemu-img check`, and
  pinned-WHPX postflight at the current disk identity above.

The accepted source manifest is 1,276 bytes, SHA-256
`d7e3a1a71aef0611f412269e88f2bbe0cd889e6264ad413e149bebb88f39eb9e`.
The accepted probe output is 6,121 bytes, SHA-256
`5dda851337cb929c0597efadbdb86b45dead406c7b43f302b4ca20ed69443796`.

Measured facts include:

- amd64 `Waitmsg` is 24 bytes; `pid`, `time`, and `msg` are at offsets 0,
  4, and 16; each `ulong` timing field is unsigned 32-bit milliseconds;
- nonempty native messages retain the process-name/PID prefix, and the tested
  maximum complete message was 127 bytes;
- exact no-child and interrupted errors were respectively
  `no living children` and `interrupted`;
- native rfork ignores an unknown-only bit, reinforcing mandatory primitive
  validation, while documented conflicts fail with `bad arg in system call`;
- current-process `RFENVG` returned zero, created no child, and copied rather
  than shared later mutations;
- direct exec preserved literal argv0, empty and arbitrary non-NUL arguments,
  performed no PATH search, and rejected an empty vector;
- `#d/<fd>` and `/fd/<fd>` reopening worked; `OCEXEC` closed its descriptor
  after exec, while `dup` cleared the flag;
- pipe reads required looping, standard-descriptor holes were reused by new
  pipe endpoints, and the bounded `P9E1` frame survived deliberately partial
  parent reads with exact EOF;
- completion order differed from spawn order; and
- await interruption consumed neither short-lived child completion.

No material contradiction with the accepted P2-004 plus P2-006 design was
found. One later documentation refinement is warranted: installed source and
the manual retain pipe, dup (`#d`), env, cons, and proc devices under
`RFNOMNT`. Phase 2 should still reject `RFNOMNT` because its sandbox policy is
unselected and deferred, not because this installed source proves `#d`
unavailable.

The accepted findings and exact unresolved facts are retained at:

```text
C:\Users\dharm\vm\ocaml\evidence\
  plan9-phase-2-process-primitives-abi-probe-001\
    attempt-003\abi-findings.md
```

The caml9 repository and all `.32` guest, endpoint, process, disk, serial,
instance, and checkpoint state remained excluded and were not queried,
inspected, or changed.

### Rejected Phase 2 exact-source native build

`plan9-phase-2-process-primitives-native-build-test-001` stopped at the first
new build failure. It used only the `.40` compiler lab and made no source
correction, installation, compiler-prefix mutation, checkpoint, commit, or
push.

The Windows checkout started at published commit
`4f3330ede0d6e0e7e0eb573afb5b23cb12d7ca3d`, tree
`c86f23530f2eafe7e95c63539039fd6d909adf76`. Exactly the 19 reviewed Phase 2
candidate paths were staged while this current-state record remained
unstaged. The exact staged tree is
`91111263f28eda70f12e2c2db3b82c2503e33ba2`; its `otherlibs/plan9`,
`runtime`, and `build-aux/plan9` subtrees are respectively
`47e957d7e98c3d2201c2d354445362ed85f9233c`,
`d9e394abc9acb62cf3347b0c6c578ce432c673f3`, and
`ad15caf6f5bb3c63fc29851cda697d9f85d68dc0`.

Two independently exported deterministic archives were byte-identical. Each
is 30,177,280 bytes, SHA-256
`0fd5125e67a5b3b6fc34d36e8546503850ebbef7fb555c2172711395af8b611c`
and SHA-1 `e86a2239e3a6f0cca38ae8f0a95f08805dd27b57`. The transferred
archive had the same SHA-1 in the guest and was extracted on native storage at:

```text
/usr/glenda/src/ocaml-plan9-phase2-process-native-001
```

Configuration completed with `HOST` and `TARGET` both
`x86_64-unknown-plan9`, `CC=c89`, shared libraries disabled, and
`OTHERLIBRARIES=dynlink unix bigarray str plan9`. The complete bytecode-world
build then stopped while linking the new standard `runtime/ocamlrun`:

```text
p9_prepare_descriptors: undefined: caml_snprintf in p9_prepare_descriptors
cc: 6l: 6l 4037: error
make[1]: *** [Makefile:284: ocamlrun] Error 1
make: *** [Makefile:165: coldstart] Error 2
```

The reference is at `runtime/plan9_process.c:487`. The failed object retained
an undefined `caml_snprintf` symbol, while the only runtime C definition found
by the bounded diagnostic was the Win32 implementation. All seven intended
`caml_plan9_*` names were already present exactly once in the generated
primitive table. No source suite, interruption driver, install step, artifact
qualification, installed consumer, or C-tool sentinel ran after the runtime
link failure.

The proposed experimental prefix
`/usr/glenda/lib/unix/ocaml-4.14.3-plan9-dev-002` was never created. No command
wrote to the production or accepted Phase 1 prefix; the pre-build production
path/size/mtime inventory is retained, but the planned post-install
byte-identity comparison was not reached. The failed native source tree,
temporary transferred archive, configure log, and build products remain on
the halted mutable disk as diagnostic state.

Only `.40` was launched with `whpx,kernel-irqchip=off`. P9QEMU PID 5300,
Python PIDs 6136 and 16252, and QEMU PID 6820 all exited after address-specific
`fshalt`; QEMU alone had owned the seven selected listeners. Postflight found
no `.40` process or listener, rebound all seven endpoints, exclusively opened
the halted disk, retained the exact immutable backing path, found both dirty
and corrupt flags false, and reported zero `qemu-img check` errors. The
pinned-WHPX dry run passed without TCG and without creating its placeholder
serial path.

Raw evidence is retained at:

```text
C:\Users\dharm\vm\ocaml\evidence\
  plan9-phase-2-process-primitives-native-build-test-001\attempt-001
```

The caml9 repository and every `.32` guest, endpoint, process, disk, serial,
instance, and checkpoint path remained excluded and were not queried,
inspected, or changed.

### Phase 2 runtime-link source correction

`plan9-phase-2-process-primitives-runtime-link-correction-001` was a
Windows-source-only correction. It did not revalidate or access a VM, guest,
endpoint, native tree, prefix, checkpoint, or caml9 state.

Live Git revalidation found published HEAD, upstream, and advertised origin at
`4f3330ede0d6e0e7e0eb573afb5b23cb12d7ca3d`. The frozen 19-path candidate
remained staged at tree
`91111263f28eda70f12e2c2db3b82c2503e33ba2`; this current-state record
remained separately unstaged.

The rejected native build had compiled ordinary runtime users of `snprintf`
from `<stdio.h>` and stopped only on the explicitly named
`caml_snprintf`. Source inspection confirmed that `caml_snprintf` is declared
and defined only for the Win32 runtime compatibility path. The correction in
`runtime/plan9_process.c` therefore:

- includes `<stdio.h>`;
- replaces the direct Win32-only call with the already used APE `snprintf`;
- validates both a negative result and a result outside the 32-byte
  destination;
- keeps the exact `#d/<fd>` path;
- runs before rfork; and
- enters the existing descriptor-failure cleanup on formatting failure.

It does not change descriptor-hole handling, `OCEXEC`, the fixed rfork flags,
child execution, the public API, wait ownership, frame handling, or test
policy. The corrected unstaged runtime file is SHA-256
`2675018e0085266666452871908e899fb96c781a3673779fb8ed59eadb5e51f6`
and Git blob `8c7c16c47baf850ffee1466a6496e3b3ab6aeb99`. Its frozen staged predecessor
remains blob `5a9762def8da767058c490a5f7e4410fab0795af`.

Cold host review passed primitive-definition/declaration cardinality, Plan 9
conditional build and primitive generation, narrow public surfaces, fixed
rfork rejection, checked P9E1 bounds, acknowledgment ordering, mismatch
non-acknowledgment, native test wiring, forbidden-backend scans, exact-path
accounting, whitespace, and final-newline checks. No Windows compiler or
native build was invoked.

### Rejected Phase 2 exact-source native-build resume

`plan9-phase-2-process-primitives-native-build-test-resume-001` stopped
fail-closed before source transfer. It made no source correction,
installation, compiler-prefix mutation, checkpoint, commit, or push.

Live Git began and ended at published HEAD and upstream
`4f3330ede0d6e0e7e0eb573afb5b23cb12d7ca3d`. The reviewed
`runtime/plan9_process.c` correction was staged into the 19-path candidate
while this record remained separately unstaged. The exact staged tree is:

```text
index tree: b1c0c9e8e47d49b9e2d677e4dd51adf7bd7c7b6d
otherlibs/plan9 subtree: 47e957d7e98c3d2201c2d354445362ed85f9233c
runtime subtree: 582dc1cf834e2e3c8818c82d49d66c071a4434d4
build-aux/plan9 subtree: ad15caf6f5bb3c63fc29851cda697d9f85d68dc0
corrected runtime blob: 8c7c16c47baf850ffee1466a6496e3b3ab6aeb99
```

Attempts 001 through 003 were retained as host-only preflight rejections.
They respectively caught a self-matching process query, an invalid
PowerShell `Test-Path` expression, and a `qemu-img` JSON property-name
assertion. None launched P9QEMU, contacted an endpoint, accessed the guest, or
transferred source.

Attempt 004 independently reproduced its exact-index archive and passed the
complete halted `.40` preflight:

```text
synthetic archive commit: 98b4aabffc198f07e867933131e246158c08a4c6
archive bytes: 30177280
archive SHA-256:
  72f9936cb306c98451c4ba495233278c59cb911c3a75fac9567ee350d7df803e
archive SHA-1:
  9a7569d752b3425e0fc9261e18b9b718d4ffa1b5
archive entries: 4227
```

The two exports were byte-identical and had a single expected prefix with no
`.git`. Preflight revalidated the exact disk and `instance.json`, exclusive
disk access, no relevant `.40` process or listener, all seven ports bindable,
clean halted QCOW2 state, zero check errors, and
`whpx,kernel-irqchip=off` with no TCG fallback.

The gate launched only `.40`. P9QEMU PID 26244, Python PIDs 36464 and 24840,
and QEMU PID 23360 formed the recorded process chain; QEMU alone owned all
seven listeners. Guest preflight found the attempt source tree, guest archive,
attempt evidence directory, and dev-002 prefix absent; confirmed the
production and accepted Phase 1 prefixes; resolved GNU Make 4.4.1, `c89`,
`sha1sum`, `tar`, `sed`, and `cmp`; and observed the exact archive through
`/mnt/term`.

The first guest mutation created only the attempt evidence directory and its
336-line production-prefix path/size/mtime listing. The next command reached
native rc as:

```text
for(f in {walk -f /usr/glenda/lib/unix/ocaml-4.14.3 | sort}) ...
```

PowerShell construction had removed rc's required backquote. Rc rejected the
bare `{` with status 114. The gate stopped before copying the archive,
creating the fresh native source tree, configuring, building, testing,
installing, or running an artifact, consumer, sentinel, or interruption
check. The dev-002 prefix remained absent. The completed partial listing was
copied to host evidence with SHA-1
`e871b8a897976a13aa8f4b8283acc61a48e349fe`, and the guest attempt directory
was removed.

Address-specific `fshalt` then stopped the lab. All four recorded processes
exited, no relevant `.40` process or listener remained, and all seven ports
were bindable. The selected disk was exclusively openable; its backing path
was preserved; dirty and corrupt flags were false; `qemu-img check` reported
zero errors; and the pinned-WHPX postflight passed without creating its
placeholder serial log.

The sealed attempt-004 evidence manifest is 5,713 bytes, SHA-256
`6b33ea411e031fa37ea8c4b334ec37c4e0c7c4c754db56cfee3bdb2bcc34e6ca`.
Raw evidence, including the three prior rejection records, is retained under:

```text
C:\Users\dharm\vm\ocaml\evidence\
  plan9-phase-2-process-primitives-native-build-test-resume-001\
```

The gate did not inspect or change caml9, `.32`, a protected checkpoint or
base, the production or Phase 1 prefix, `Sys`, `Unix`, RFNOMNT, custom-runtime
linking, service state, or CPU-017.

### Rejected Phase 2 exact-source native-build resume-002

`plan9-phase-2-process-primitives-native-build-test-resume-002` stopped at the
first native source failure. It made no source correction, installation,
compiler-prefix mutation, checkpoint, commit, or push.

Live Git began and ended at published HEAD and upstream
`4f3330ede0d6e0e7e0eb573afb5b23cb12d7ca3d`. The exact 19-path Phase 2
candidate remained staged at tree
`b1c0c9e8e47d49b9e2d677e4dd51adf7bd7c7b6d`; this current-state record
remained separately unstaged. Its recorded subtrees and corrected runtime
blob remained:

```text
otherlibs/plan9 subtree: 47e957d7e98c3d2201c2d354445362ed85f9233c
runtime subtree: 582dc1cf834e2e3c8818c82d49d66c071a4434d4
build-aux/plan9 subtree: ad15caf6f5bb3c63fc29851cda697d9f85d68dc0
runtime/plan9_process.c blob:
  8c7c16c47baf850ffee1466a6496e3b3ab6aeb99
```

Attempts 001 through 005 were retained as distinct procedural rejections:

- attempt 001 found an invalid host source-boundary subtree recorder and did
  not operate the VM;
- attempt 002 exhausted the bounded Drawterm readiness window, made no guest
  mutation, and shut down cleanly;
- attempt 003 proved the native `rc` lacks the proposed `-n` parse-only
  option, copied and removed only the inventory driver, and shut down cleanly;
- attempt 004 found that loop-level output redirection truncated the digest
  inventory to one line rather than 336, stopped before source transfer, and
  shut down cleanly; and
- attempt 005 passed the corrected driver, both 336-line pre-inventories,
  exact source transfer, extraction, and configuration, then stopped before
  build when a follow-up inspection command was malformed.

Each booted rejected attempt used only `.40`, halted by address-specific
`fshalt`, closed and rebound all seven endpoints, and passed halted QCOW2 and
pinned-WHPX postflight. Its attempt-unique guest source, archive, driver,
evidence, and proposed dev-002 prefix state was removed or proved absent
before shutdown.

Attempt 006 used a separately transferred bounded `rc` driver represented by
a host single-quoted literal. Native `rc` fully parsed its `check` mode before
the driver wrote anything. The driver then produced 336 path/size/mtime lines
and 336 per-file SHA-1 lines before the qualification. Both independently
exported exact-index archives were byte-identical:

```text
synthetic archive commit: d0d62b735234f354a392d59540d6d32b08441b70
archive bytes: 30177280
archive SHA-256:
  0d9a2b4d93644a2093bac85f8050997ef363f04ff41647e6bae42e0e9d94a72e
archive SHA-1:
  1e86f8576c187ad0db91581048b545da03886eef
archive entries: 4227
```

The guest archive hash matched, the fresh native tree had no `.git`, and
configuration completed with `HOST` and `TARGET` both
`x86_64-unknown-plan9`, `CC=c89`, shared libraries disabled, isolated prefix
`/usr/glenda/lib/unix/ocaml-4.14.3-plan9-dev-002`, and
`OTHERLIBRARIES=dynlink unix bigarray str plan9`.

The complete bytecode-world build then reached the Plan 9 otherlib and failed
under its existing warnings-as-errors policy:

```text
File ".../otherlibs/plan9/plan9_process.mli", line 89, characters 13-19:
89 | module Make (Native : Native) : sig
                  ^^^^^^
Error (warning 67 [unused-functor-parameter]):
  unused functor parameter Native.
make[4]: *** [../Makefile.otherlibs.common:140: plan9_process.cmi] Error 2
make: *** [Makefile:308: world] Error 2
```

The full 415,411-byte build log is SHA-256
`dc1f0b05bb5128d3ef78d3368398019bfbd63b0cf6a8031cc64c7ae7ac9c668b`.
No source-owned suite, interruption driver, installation, artifact
qualification, installed consumer, or C-tool sentinel ran. The dev-002 prefix
was never created.

The validated `after` inventory was byte-identical to the `before` inventory:
both views retained 336 lines, layout SHA-1
`e871b8a897976a13aa8f4b8283acc61a48e349fe`, and digest-manifest SHA-1
`06bacc059c59a928ae69df5bee1e084772b8b77e`. The production prefix therefore
remained unchanged. The verified 5,173-file failed source tree and all other
attempt-006 guest temporaries were removed after the guest evidence bundle was
copied and rehashed. The 589,824-byte bundle is SHA-1
`508296c54ae7b08cc1f881c17906536ec0d39806` and SHA-256
`e552edade59a32acbaf974a688d12124fc81b3625b20f6d60d308817342bb2f4`.

Address-specific shutdown exited P9QEMU PID 34276, Python PIDs 21932 and
34288, and QEMU PID 27352. No `.40` listener remained, every endpoint was
bindable, the selected disk was exclusively readable, the exact backing path
was retained, dirty and corrupt flags were false, and `qemu-img check`
reported zero errors. The pinned-WHPX dry run rendered only
`whpx,kernel-irqchip=off`, performed no fallback, and did not create its
serial placeholder.

The evidence manifest covers 178 files, is 18,680 bytes, and has SHA-256
`6b1b5e88299a63ec526ac9b37c061d9427faf0c9c08a9db1679f92bca728881d`.
Raw evidence is retained under:

```text
C:\Users\dharm\vm\ocaml\evidence\
  plan9-phase-2-process-primitives-native-build-test-resume-002
```

The gate did not inspect or change caml9, `.32`, a protected checkpoint or
base, the production or Phase 1 prefix, `Sys`, `Unix`, RFNOMNT, custom-runtime
linking, service state, or CPU-017.

### Phase 2 private-functor warning correction

`plan9-phase-2-process-primitives-functor-warning-correction-001` was a
Windows-source-only correction. It did not access a VM, guest, endpoint,
Drawterm, native tree, prefix, checkpoint, or caml9 state.

Live Git revalidation found published HEAD, upstream, and advertised origin at
`4f3330ede0d6e0e7e0eb573afb5b23cb12d7ca3d`. The frozen 19-path candidate
remained staged at tree
`b1c0c9e8e47d49b9e2d677e4dd51adf7bd7c7b6d`; this current-state record
remained separately unstaged.

The rejected native build had compiled through the runtime, standard library,
and earlier otherlibs before warning 67 rejected this private interface:

```ocaml
module Make (Native : Native) : sig
```

The result signature does not refer to the parameter name, so the correction
in `otherlibs/plan9/plan9_process.mli` makes that interface parameter
explicitly anonymous:

```ocaml
module Make (_ : Native) : sig
```

The implementation remains `module Make (Native : Native) = struct` and
continues to invoke the backend. All 18 focused-test applications remain
unchanged. OCaml 4.14.3 already uses the anonymous form for the same
non-dependent interface shape in `otherlibs/dynlink/dynlink_common.mli`,
`middle_end/flambda/augment_specialised_args.mli`, and
`toplevel/topcommon.mli`.

The staged predecessor and reviewed worktree identities are:

```text
staged plan9_process.mli blob:
  93fdd2ef4fd37fc0464a28838b5ad43a119203cc
reviewed worktree plan9_process.mli blob:
  bc533b10fa21e63f9d63c0436faaf732d38446aa
reviewed worktree plan9_process.mli SHA-256:
  d6f9ec7e35d0655e44e68596c04cfad96c4d9fd74f51e65d59ef716c7f27e83f
```

The correction does not disable warning 67, weaken warnings-as-errors, change
a public type, alter the implementation functor, or change lifecycle, ABI,
runtime, build, or test behavior. Cold host review passed exact-path
accounting, interface/implementation agreement, all functor applications,
repository precedent, whitespace, and final-newline checks. No compiler or
build was invoked.

### Rejected Phase 2 exact-source native-build resume-003

`plan9-phase-2-process-primitives-native-build-test-resume-003` stopped at the
first new native source failure. It made no source correction, retry,
installation, compiler-prefix mutation, checkpoint, commit, or push.

Live Git began and ended at published HEAD, upstream, and advertised origin
`4f3330ede0d6e0e7e0eb573afb5b23cb12d7ca3d`. The reviewed anonymous-functor
signature was staged into the same 19-path candidate while this current-state
record remained separately unstaged. The exact tested source identities are:

```text
index tree: d1fad9efbc188dd079ba0f777fbb4840fca00af3
otherlibs/plan9 subtree: f21fb8c3332134c907cc829f930c9bb4688b364b
runtime subtree: 582dc1cf834e2e3c8818c82d49d66c071a4434d4
build-aux/plan9 subtree: ad15caf6f5bb3c63fc29851cda697d9f85d68dc0
otherlibs/plan9/plan9_process.mli blob:
  bc533b10fa21e63f9d63c0436faaf732d38446aa
runtime/plan9_process.c blob:
  8c7c16c47baf850ffee1466a6496e3b3ab6aeb99
```

Both deterministic exports were byte-identical:

```text
synthetic archive commit: 56bcd801da70dbadeea907cf4a5fb206c328239b
archive bytes: 30177280
archive SHA-256:
  ca9efdd10fd24285d240aa5f57cb894dbd6c741202c3bf098d9b038e9b22f1c4
archive SHA-1:
  0e142cfd1c3b08e8135d6ba3f5917634d88fd447
archive entries: 4227
```

The archive had one expected prefix, no `.git`, and only the empty directory
entry for the intentionally unresolved `flexdll` gitlink. The guest archive
SHA-1 matched. The fresh native tree had no `.git`, and its extracted
`runtime/plan9_process.c` and `otherlibs/plan9/plan9_process.mli` hashes
matched the staged source.

The separately transferred inventory driver remained LF-only with its three
native rc backquotes intact. Its host SHA-256 was
`a6d81c83f747ed72cbf2927f74827e5cf84e428046829e8cac1af41f2b2ad96b`;
host and guest SHA-1 were
`134c43833240bef77266c74629d18cd3267c3318`. Native rc parsed the driver
before it wrote anything. It then produced 336 path/size/mtime lines and 336
per-file digest lines before qualification.

Three procedural assertions were corrected before native compilation without
changing source:

- APE `command -v c89` resolved `/bin/c89`; native rc `test -e` does not prove
  existence for that synthetic `/bin` entry.
- One archive command lost an rc backquote during PowerShell construction and
  was rejected during parse before its copy or extraction. The accepted
  transfer used separate backquote-free copy/hash, entry-count, and extraction
  commands.
- Bytecode-only `Makefile.config` records `SYSTEM=unknown`; the authoritative
  target checks are `HOST=x86_64-unknown-plan9`,
  `TARGET=x86_64-unknown-plan9`, `CC=c89`, and the selected `plan9` otherlib.

Configuration passed those exact checks for the isolated
`/usr/glenda/lib/unix/ocaml-4.14.3-plan9-dev-002` prefix. The complete
bytecode-world build compiled through the runtime, standard library, and
earlier otherlibs. The private-interface warning-67 correction passed. The
Plan 9 otherlib implementation then failed under the unchanged
warnings-as-errors policy:

```text
File ".../otherlibs/plan9/plan9_process.ml", line 886, characters 14-30:
886 |   let spawn ?(stdout = Inherit) ~program ~args =
                    ^^^^^^^^^^^^^^^^
Error (warning 16 [unerasable-optional-argument]):
  this optional argument cannot be erased.
File ".../otherlibs/plan9/plan9_process.ml", line 926, characters 12-28:
926 |   let run ?(stdout = Inherit) ~program ~args =
                  ^^^^^^^^^^^^^^^^
Error (warning 16 [unerasable-optional-argument]):
  this optional argument cannot be erased.
```

The complete 415,953-byte build log is SHA-1
`5d29d91bba293e21ff2cc08bff32bcd4c2a3decd` and SHA-256
`9c16fd7a12247f8971fe5b45d4276785d100fda200d249ce3b31182a275ce20c`.
No source-owned suite, interruption driver, installation, built-in primitive
artifact check, `ocamlobjinfo` check, installed consumer, or C-tool sentinel
ran. The dev-002 prefix was never created.

The production-prefix before and after inventories were byte-identical. Both
views retained 336 lines, layout SHA-1
`e871b8a897976a13aa8f4b8283acc61a48e349fe`, and digest-manifest SHA-1
`06bacc059c59a928ae69df5bee1e084772b8b77e`. The verified 5,176-file
attempt source tree, archive, driver, evidence directory, and guest evidence
tar were removed after the evidence bundle was copied and rehashed. The
589,824-byte guest bundle is SHA-1
`e48e73782684349544472d239881bb7a96ab2f7e` and SHA-256
`32a715900200007f33e5d457940a9a8de959b4315bc77a94b90b1266c13620e7`.

Address-specific `fshalt` exited P9QEMU PID 24468, its console PID 30384,
Python PIDs 23012 and 468, and QEMU PID 29456. QEMU alone had owned all seven
`.40` listeners. No selected process or listener remained, every endpoint was
bindable, and the disk was exclusively readable. The exact backing path was
retained, dirty and corrupt flags were false, `qemu-img check` reported zero
errors, and the pinned-WHPX dry run rendered only
`whpx,kernel-irqchip=off` without creating its serial placeholder.

The attempt evidence manifest covers 60 files, is 10,125 bytes, and has
SHA-256
`5a5ea1f61530189d64e61db0fbec0327dcb885376e648ee4c75e696b9dc2cad7`.
Raw evidence is retained at:

```text
C:\Users\dharm\vm\ocaml\evidence\
  plan9-phase-2-process-primitives-native-build-test-resume-003\attempt-001
```

The gate did not inspect or change caml9, `.32`, a protected checkpoint or
base, the production or Phase 1 prefix, `Sys`, `Unix`, RFNOMNT,
custom-runtime linking, service state, or CPU-017.

## Read-only guest inventory

The authenticated Drawterm inventory used only `127.0.0.40`.

```text
user: glenda
sysname: cirno
cputype and objtype: amd64
/dev/osversion: 2000
APE uname: Plan9 cirno 4 0 amd64
initial directory: /usr/glenda
```

The namespace contained the expected Plan 9 device and service bindings and a
Drawterm `/mnt/term` mount. The inventory listed the mount point and namespace
only; it did not traverse the Windows mount or transfer source.

### Installed OCaml

```text
ocamlc version: 4.14.3
ocamlrun version: 4.14.3
standard library:
  /usr/glenda/lib/unix/ocaml-4.14.3/lib/ocaml
host and target: x86_64-unknown-plan9
os_type: Unix
system: unknown
architecture: none
native compiler: disabled
shared libraries: disabled
systhreads: disabled
C compiler: c89
configured otherlibs: dynlink unix bigarray str
```

The installed prefix contains the bytecode tools and runtime, `stdlib.cma`,
`dynlink.cma`, `unix.cma`, `bigarray.cma`, `str.cma`, `libcamlrun.a`, and
`libunix.a`. The normal native compiler is not enabled.

### Source and build tools

```text
OCaml source: /usr/glenda/src/ocaml
Plan 9 git9 branch: heads/plan9-4.14.3-000
source HEAD: 3bddbb623ddc0b8d9cfe42c3b190097b99ae6408
source subject: Make Plan 9 README the repository landing page
runtime/ocamlrun: present
config.status and Makefile.config: present
configured prefix: /usr/glenda/lib/unix/ocaml-4.14.3

native tools resolved: /bin/rc, /bin/mk
Plan 9 compatibility tools resolved: /bin/ape/psh, /bin/git/branch
APE tools resolved: /bin/sh, /bin/make, /bin/c89, /bin/cc, /bin/ld,
  /bin/ar, /bin/ranlib
GNU Make source: /usr/glenda/src/make
```

`/usr/glenda/lib/unix/bin/gmake` is absent. The qualified GNU Make is:

```text
/usr/glenda/lib/unix/make-4.4.1/bin/make
GNU Make 4.4.1
Built for x86_64-unknown-plan9
```

The guest provides `/bin/sha1sum`; no SHA-256 command was resolved.

## Earlier rejected warning-probe gate

`plan9-phase-1-env-native-build-warning-probe-001` was rejected before its
compiler matrix:

- retained attempt 001 as a rejected preboot evidence attempt after aggregate
  property access recorded the two-object QCOW2 backing chain with the wrong
  JSON shape;
- started fresh attempt 002 without booting from attempt 001;
- revalidated HEAD, upstream, the exact staged index, Plan9 subtree, the sole
  unstaged current-state record, and absence of untracked files;
- rehashed every attempt-004 manifest entry and the rejected build log;
- revalidated the exact instance files and identities, exclusive writable-disk
  access, all seven `.40` endpoints, two-object QCOW2 relationship, clean dirty
  flag, `qemu-img check`, and pinned WHPX dry run;
- launched only the OCaml instance with
  `whpx,kernel-irqchip=off` and no fallback;
- recorded P9QEMU shim PID 34592, Python PIDs 25508 and 27816, QEMU PID 32456,
  and conhost PID 28156;
- proved QEMU alone owned all seven `.40` listeners and authenticated only to
  `.40` through Drawterm;
- copied the proposed diagnostic driver into host evidence but did not
  transfer it into the guest;
- stopped when the first native rc parent-environment command failed to parse
  at an unquoted `=` token, before it executed, created the proposed
  `/tmp/p1-warning-probe-001` workspace, inspected the candidate tree, or
  invoked either compiler/runtime; and
- invoked no GNU Make, configure, clean, build, install, Plan9.Env test,
  compiler matrix, source correction, or prefix mutation.

Attempt 002 then halted through `.40` Drawterm, waited for the complete
recorded process chain, closed and rebound all seven endpoints, and passed the
halted QCOW2 and pinned-WHPX postflight.

```text
attempt 001 evidence manifest SHA-256:
  39e9ecd510f809ea2a6f8b777a6c6c6a60d3a46aaecc6eeaa72884a4ab513f5e
attempt 002 evidence manifest SHA-256:
  914963d5356fae9e0b181f13e03cc227da47dc10e966fcf64e64acd340c29b99
```

The preserved partial native build and both compiler prefixes were not
accessed or changed. No guest diagnostic workspace was created. The candidate
build warning was not reproduced or further classified.

## Earlier rejected native-build gate

`plan9-phase-1-env-native-build-resume-001` was rejected during the native
compiler build:

- retained attempt 003 as a rejected no-build boot after a host PowerShell
  interpolation error occurred before any resume-driver command executed;
- started fresh attempt 004 from the resulting fully postflighted halted disk;
- revalidated HEAD, upstream, exact staged index, `otherlibs/plan9` subtree,
  archive carrier, archive hashes, and the sole unstaged current-state record;
- revalidated the preserved guest archive SHA-1 and absence of `.git`, build
  products, and the experimental prefix;
- matched twelve implementation and build-integration file SHA-1 values
  against the exact archive;
- corrected only the rejected evidence assertion, without reconfiguring or
  modifying the frozen candidate;
- proved `config.status --config` records the final isolated prefix and
  resolved `prefix`, `exec_prefix`, `BINDIR`, `LIBDIR`, `STUBLIBDIR`, and
  `MANDIR` entirely beneath that prefix;
- launched the bytecode-world build with GNU Make 4.4.1 from the versioned
  Make prefix;
- built the runtime and standard library, then progressed through the
  bytecode compiler until `typing/typemod.ml:368`;
- failed when warning 11 (`redundant-case`) was promoted to an error while
  compiling `typing/typemod.ml`, causing Make to exit 112; and
- stopped without retrying, changing source, running Plan9.Env tests,
  installing, running consumers or environment cross-checks, committing, or
  pushing.

Attempt 004 then halted through `.40` Drawterm, waited for the complete
recorded process chain, closed and rebound all seven endpoints, and passed the
halted QCOW2 and pinned-WHPX postflight.

```text
attempt 003 evidence manifest SHA-256:
  eb1f119b66e5f576cf0cedbf3b9b4db9d889b0924df4ea42265de436f1415249
attempt 004 build log SHA-256:
  f28a89e9ec9d1355e5400291a26e654ad5bf6c22b025167bb21f97194581057b
attempt 004 evidence manifest SHA-256:
  005a54a0c73b6f5985cf1d4a5461bcfb994bbfc2f90b074ccc0ca63623146820
```

The partial native build tree, preserved archive, original driver, and
attempt-004 driver remain on the halted mutable disk. No Phase 1 test `/env`
name was created.

## Earlier rejected stateful lab gate

`plan9-phase-1-env-native-build-001` was rejected before build:

- preserved rejected attempt 001 for a host-only evidence-directory command
  error that occurred before VM, endpoint, disk, or source mutation;
- froze exact index tree `18e05515c69e454769f2056ce8a4905763441c8c`
  and `otherlibs/plan9` tree
  `f3b52c9ed77638dd7d27752b09b272a335705c11`;
- exported a deterministic 29,798,400-byte archive with SHA-1
  `e9e99f5dd3703ed586566ed04859f7d278bedfba` and SHA-256
  `253ffae1ab5650487c3cfb0ade42772b47450ab79acc14a1abe9802e96ced437`;
- recorded the unused `flexdll` gitlink
  `a47f93667bd4dcc7c7e85aa02f34446d47d28915`;
- passed the instance, exclusive-disk, seven-endpoint, halted QCOW2, and pinned
  WHPX dry-run preflight;
- launched only the OCaml instance with WHPX and no fallback;
- copied only the exact archive through `/mnt/term`, verified its SHA-1 inside
  the guest, and extracted it to fresh native storage without `.git`;
- qualified GNU Make 4.4.1 at the versioned path above;
- configured the exact tree for host and target `x86_64-unknown-plan9`, `CC=c89`,
  the isolated prefix, and
  `OTHERLIBRARIES=dynlink unix bigarray str plan9`;
- stopped before build when a host assertion incorrectly expected a
  `PREFIX=` line in `Makefile.config`; the configure command itself had passed,
  but the gate's fail-closed rule prohibited correcting the assertion in the
  same attempt;
- invoked no build, test, install, consumer link, or environment cross-check;
  and
- halted through `.40` Drawterm, waited for the exact process chain, closed and
  rebound all seven endpoints, and passed the halted QCOW2 and WHPX postflight.

The guest-local `/tmp/p1e001.tar`, `/tmp/p1driver`, and the configured native
tree were retained with the rejected attempt. No test `/env` name was created.
No experimental prefix installation was attempted.

The gate did not access caml9 state or a protected checkpoint; directly
inspect, hash, or mutate the immutable base; access the known-built
`/usr/glenda/src/ocaml` tree; or mutate the known-working compiler prefix. It
did not use TCG or create a checkpoint.

## Earlier completed stateful lab gate

`plan9-compiler-lab-first-boot-inventory-001`:

- revalidated the clean published Windows repository boundary;
- revalidated only the accepted OCaml `dev` instance and all seven `.40`
  endpoints;
- retained attempt 001 as a record of two host-script construction errors that
  occurred before any VM, socket, QCOW2, or P9QEMU operation;
- passed the corrected containment, identity, exclusive-disk, endpoint,
  halted-QCOW2, and P9QEMU dry-run checks in attempt 002;
- launched only the mutable OCaml instance with WHPX and no fallback;
- observed P9QEMU shim PID 22004 and QEMU PID 29936, with QEMU alone owning all
  seven `.40` listeners;
- performed the inventory above without editing guest files;
- halted through authenticated `.40` Drawterm using `fshalt`;
- waited for both exact launch PIDs to exit;
- proved all `.40` listeners closed and all seven endpoints bindable; and
- passed the halted QCOW2 and P9QEMU postflight while recording the expected
  disk transition.

It did not transfer source; build, install, implement, patch, or checkpoint;
create another VM; use TCG; or access any caml9 state.

## Earlier source-only gate

`plan9-phase-1-built-in-env-implementation-001`:

- added the Plan 9-only `Plan9` compilation unit and nested `Plan9.Env` API;
- kept `plan9.cma` ML-only, with no `external`, C object, DLL, custom-link, or
  runtime-primitive dependency;
- implemented every lookup through a fresh `/env` enumeration and file read,
  every set through a direct create/truncate/write, and every removal through
  direct file removal;
- preserved absent, empty-list, empty-scalar, list, unterminated-final-element,
  arbitrary non-NUL byte, whitespace, newline, and empty-element semantics;
- added name and value validation, result-preserving I/O errors, and the
  explicitly raising `get_exn`;
- selected the library only for `*-*-plan9` configure hosts;
- installed the archive and interface beneath the `plan9` standard-library
  subdirectory for `ocamlc -I +plan9 plan9.cma ...`;
- added a focused source-tree test and updated the build, API, workflow,
  verification, runbook, and user documentation; and
- passed Windows-host whitespace, generated-configure shell syntax, line
  length, forbidden-source-area, forbidden-API, and packaging-consistency
  checks.

No OCaml compiler, runtime, library, or Make test was run on Windows. Those
checks require native Plan 9 storage under repository policy. At that gate's
close, the exact candidate was staged and pending native validation; the
accepted completion gate below supersedes that pending state.

The gate did not access the OCaml VM, `.40` endpoints, Drawterm, `/mnt/term`,
any guest or native tree, an install prefix, or any caml9 state. It did not
transfer, configure, build, install, stage, commit, push, or checkpoint.

## Rejected warning-probe resume gate

`plan9-phase-1-env-native-build-warning-probe-resume-001` remained diagnostic
only:

- attempts 001 and 002 were rejected before parser or compiler access because
  of host-side evidence and launch-validation mistakes; their sealed manifest
  SHA-256 values are respectively
  `73c3231515eaeaa0c615c48d7d6718ccaaeb91eac8cee0cf3c948e5f995500ba`
  and
  `91c7797124a9d45a0cd6028954486a791bd3232366756c973372c0884367a7d8`;
- attempt 003 transferred and verified only its two rc scripts and three
  minimal OCaml sources beneath
  `/tmp/p1-warning-probe-resume-003`;
- the first parser invocation did not start because of a wrong host executable
  path, the second reached only the authentication prompt, and the third
  wrapper falsely interpreted native rc's empty success status; no guest
  driver version was rejected in those host-side failures;
- the corrected parser wrapper accepted the unchanged driver and sanitation
  helper with their guard markers present and empty parser stderr;
- the frozen accepted driver SHA-256 is
  `958c63d6cd83ed5e86efd8ef2f17b1dac323a04874c70372d177d264e07d61c9`;
  the sanitation helper SHA-256 is
  `9f9404f0e0b81f4a0c41d9e6cac414dc8c9827ade187a4cf1b9ea30d4377d7f2`;
- direct `/env` and native rc showed all nine uppercase compiler-affecting
  names absent, while native rc `path` was `(/bin .)`; the parent direct view
  was unchanged after the isolated child probes;
- APE-visible state was not captured: the driver invoked nonexistent
  `/bin/env`, so its reported APE absences are invalid;
- the bootstrap compiler embedded standard-library path was
  `/tmp/ocaml-4.14.3/lib/ocaml`, where
  `ocaml_compiler_internal_params` was absent;
- `boot/ocamlrun` and `runtime/ocamlrun` were byte-identical, both 1,297,534
  bytes with SHA-1
  `6318cf9cbfd2dfba1f40f320ec72952dc78898d5`; the known-working installed
  runtime SHA-1 was `c6dc3c9f746e54f22d77024fc1845e44c0b82a59`;
- the only discovered `path.cmi` was the 15,690-byte
  `typing/path.cmi`, SHA-1
  `83c7b0f81533299187e440595917ecf8814d2b69`, with Path unit CRC
  `c74c2553734e7c86ab23c6946a08a019`; every imported Path probe recorded
  that same CRC;
- all nine minimal A/B/C invocations produced CMOs with empty compiler stderr
  and no warning 11; each source's CMO hash was identical across the captured,
  sanitized-new-runtime, and sanitized-known-runtime cases;
- the rc `result=$status` handling recorded blank exit statuses and therefore
  incorrectly skipped the conditional exact `typemod.ml` matrix;
- `walk -f -e 'p s m'` rejected the spaced stat format, producing two empty
  inventory files, so their equality is not a complete candidate-tree
  immutability proof; the separately recorded relevant artifact sizes and
  hashes did match before and after;
- no warning root cause was discriminated, and no correction or diagnostic
  rerun occurred after those post-parser failures; and
- the temporary diagnostic workspace remains on the halted mutable disk.

The gate invoked no Make, configure, build, clean, install, Plan9.Env test, or
source change. It did not alter a compiler prefix, staged index, or caml9 state.
It halted only the `.40` lab, waited for its complete recorded process chain,
closed and rebound all seven endpoints, and passed the halted QCOW2 and pinned
WHPX postflight.

## Accepted Phase 1 completion gate

`plan9-phase-1-env-completion-001` autonomously corrected and validated the
bounded Phase 1 candidate:

- the exact `typing/typemod.ml` compiler matrix passed with empty stderr and
  byte-identical CMO SHA-1
  `841c354b2a99493d5e97658628af7fd70a1ecce3`;
- fresh build 004 configured with `HOST=x86_64-unknown-plan9`, `CC=c89`,
  `SYSTEM=unknown`, and
  `OTHERLIBRARIES=dynlink unix bigarray str plan9`;
- GNU Make 4.4.1 at
  `/usr/glenda/lib/unix/make-4.4.1/bin/make` completed the bytecode world;
- the complete focused Plan9.Env suite passed with unique suffix
  `p1env_completion_a001_20260724` and proved cleanup;
- `plan9.cma` is 23,430 bytes, SHA-1
  `b45eba2a84b4cda12c49c2afcf7cd20b7f10e2fd`;
- `plan9.cmi` is 1,616 bytes, SHA-1
  `2ceecb96e7c309dc57239d80d5677ee5cd8dc624`;
- installed `ocamlobjinfo` reports `Force custom: no`, no extra C objects,
  no extra C options, and no dynamically loaded libraries;
- the installed archive and interface hashes equal the source-tree artifacts
  beneath the isolated prefix;
- an installed consumer built with
  `ocamlc -I +plan9 plan9.cma consumer.ml -o consumer`, ran successfully,
  and did not invoke any fail-closed `c89`, `cc`, `gcc`, `clang`, `ld`,
  `link`, `flexlink`, `ocamlmklib`, `ar`, or `ranlib` sentinel;
- an rc-created list was read with native element boundaries, an APE-created
  scalar was read from its live unterminated `/env` representation, and a
  Plan9.Env mutation was immediately visible through a direct `/env` read
  while APE's cached `Sys.getenv` value intentionally remained unchanged; and
- all unique test names and the C-tool sentinel marker were absent at
  closeout.

The Phase 1 final guest-evidence archive is 1,572,864 bytes, SHA-256
`dc00acae84df339377d0e4920ac6fde38b595e5fe32d68767b2eb8af6851edd5`
and SHA-1 `b4119ad1e996ab9eaa257e7816cd9d520bb82576`. Its raw evidence root is:

```text
C:\Users\dharm\vm\ocaml\evidence\
  plan9-phase-1-env-completion-001\attempt-001
```

The gate did not change the production prefix, retained source checkout,
runtime or C source, `Sys`, `Unix`, process APIs, caml9 state, or any protected
checkpoint. It did not create a checkpoint or use TCG.

## Phase 2 incremental development-tree setup

`plan9-phase-2-process-primitives-incremental-setup-001` prepared a native
incremental development tree without starting a build.

Live Git remained at published HEAD, upstream, and advertised origin
`4f3330ede0d6e0e7e0eb573afb5b23cb12d7ca3d`. The 19-path Phase 2 candidate
remained staged at exact index tree
`d1fad9efbc188dd079ba0f777fbb4840fca00af3`; this record remained the only
unstaged path.

Halted preflight revalidated:

```text
instance: C:\Users\dharm\vm\ocaml\dev
instance contents: exactly disk.qcow2 and instance.json
disk bytes: 1635450880
disk SHA-256:
  ed36f9d81bbabce29252761f7346cb80f723ca3e0d0141b18c8925a291cc2e8c
instance.json SHA-256:
  c87a3a9c2ef79d7640e03c689861cfea0cd73c54c72eea5f77b81cd6d8e46225
processes in the exact .40 instance scope: none
listeners on the seven 127.0.0.40 endpoints: none
bindability: all seven endpoints passed
exclusive disk open: passed
QCOW2 backing relationship: exact two-object chain
dirty and corrupt flags: false
qemu-img check errors: zero
P9QEMU dry run: whpx,kernel-irqchip=off, no TCG fallback
```

The exact staged tree was exported twice without an archive prefix. Both
30,177,280-byte archives were byte-identical:

```text
archive SHA-256:
  db4850516e3b6d35a644b087c69ad650716ed93363b04f605f2a9e7823abc8f2
archive SHA-1:
  ff8f52a689f4329b332bbe35294e31fb1242f73a
archive entries use a fixed 2000-01-01 timestamp
```

The guest observed and copied that exact archive through `/mnt/term`, and its
SHA-1 remained identical at
`/tmp/plan9-phase2-incremental-setup-001-a001.tar`. The accepted Phase 1
native tree was copied, not modified, into:

```text
/usr/glenda/src/ocaml-plan9-phase2-incremental-001
```

The exact staged archive was applied there with Plan 9 tar's time-preserving
mode. Only the 19 staged Phase 2 candidate paths were then touched, so a later
GNU Make invocation can reconsider the Phase 2 boundary without rebuilding
the complete Phase 1 world merely because of archive timestamps. An unchanged
`typing/typemod.ml` matched the Phase 1 SHA-1
`433cdcd48a0f20b3c9796cc93d0957bd27b31fda` and retained an old timestamp.
The copied `runtime/ocamlrun` and `otherlibs/plan9/plan9.cma` matched the
Phase 1 SHA-1 values
`474452dd2ae3966239a19587973eac9ad1c54351` and
`b45eba2a84b4cda12c49c2afcf7cd20b7f10e2fd`.

The prepared tree intentionally inherits the Phase 1 configuration and its
`/usr/glenda/lib/unix/ocaml-4.14.3-plan9-dev-001` prefix setting. The proposed
dev-002 prefix remains absent. No configure, GNU Make, compiler, test,
installation, consumer, or prefix command ran in this setup gate.

Only `.40` was launched. Its live boundary is:

```text
P9QEMU shim PID: 23720
console PID: 6764
Python PIDs: 35356 and 31784
QEMU PID: 9172
listeners: QEMU PID 9172 owns all seven 127.0.0.40 endpoints
accelerator: whpx,kernel-irqchip=off, no fallback
serial:
  C:\Users\dharm\vm\ocaml\evidence\
    plan9-phase-2-process-primitives-incremental-setup-001\
      attempt-001\serial.raw.log
```

The VM was deliberately left running for the user's read-only Drawterm
browsing. That browsing does not transfer stateful ownership. Do not hash,
copy, or run `qemu-img` against the live disk. The OCaml task remains the sole
stateful operator. Caml9, `.32`, protected checkpoints, and every other
instance and address remained excluded and were not queried or changed.

Raw setup and running-boundary evidence is retained at:

```text
C:\Users\dharm\vm\ocaml\evidence\
  plan9-phase-2-process-primitives-incremental-setup-001\attempt-001
```

## Phase 2 optional-argument correction and transfer

`plan9-phase-2-process-primitives-optional-argument-correction-001` corrected
the warning-16 failure in the authoritative Windows source and copied only
the reviewed correction into the prepared incremental tree. It did not start
a build.

The correction adds a final unlabeled `unit` argument to the high-level
`Plan9.Process.spawn` and `Plan9.Process.run` contracts, implementations, and
call sites:

```ocaml
val spawn :
  ?stdout:stdout ->
  program:string ->
  args:string array ->
  unit ->
  (launch, error) result

val run :
  ?stdout:stdout ->
  program:string ->
  args:string array ->
  unit ->
  (run, error) result
```

The implementation now has:

```ocaml
let spawn ?(stdout = Inherit) ~program ~args () =
let run ?(stdout = Inherit) ~program ~args () =
```

This is the smallest type-correct repair: the final argument makes the
optional `stdout` argument erasable. It does not suppress warning 16, weaken
warnings-as-errors, make `stdout` mandatory, change the private
`Native.spawn` primitive signature, or alter lifecycle, acknowledgment, wait,
ownership, routing, backpressure, cleanup, ABI, descriptor, frame, or argv
behavior.

The six reviewed correction paths are:

```text
docs/design/plan9/01-native-api-requirements.md
otherlibs/plan9/plan9.mli
otherlibs/plan9/plan9_process.ml
otherlibs/plan9/plan9_process.mli
otherlibs/plan9/tests/process_native_integration_test.ml
otherlibs/plan9/tests/process_state_test.ml
```

Host structural validation passed exact paths, canonical signatures, the
implementation shape, all focused high-level call sites, the unchanged
private native signature, staged and unstaged whitespace, and final newlines.
No Windows compiler was invoked. The frozen 19-path index remained unchanged
at tree `d1fad9efbc188dd079ba0f777fbb4840fca00af3`; the correction and this
record remain unstaged.

Before transfer, the exact `.40` QEMU process and seven-listener boundary
remained live. All six target files matched their pre-correction staged
SHA-1 values. The replacement manifest is:

```text
docs/design/plan9/01-native-api-requirements.md
  bytes: 18002
  SHA-1: e739a99a918330ac18cec35214fbe40031f33cd2
otherlibs/plan9/plan9.mli
  bytes: 8641
  SHA-1: ecae37b2397ecb738c59cd2076871049bfa926f1
otherlibs/plan9/plan9_process.ml
  bytes: 33097
  SHA-1: 2ebab82f26738c98ffeaa82e075911ec98b12c1c
otherlibs/plan9/plan9_process.mli
  bytes: 4762
  SHA-1: ffdd120c68a0cbe2d655c93fe0812cfc823a5873
otherlibs/plan9/tests/process_native_integration_test.ml
  bytes: 19626
  SHA-1: 2b1cd78ad6fcd78d253c6b0266a20bb3866839c8
otherlibs/plan9/tests/process_state_test.ml
  bytes: 31736
  SHA-1: b720b3093c5980bb58ea1fa4ad2b16fd19b0ca6a
```

The files were copied through `/mnt/term` into an attempt-specific staging
directory, rehashed there, then copied into:

```text
/usr/glenda/src/ocaml-plan9-phase2-incremental-001
```

Every destination SHA-1 matched the reviewed Windows source. The temporary
staging directory was removed. The guest implementation showed the corrected
function definitions at lines 886 and 926. The dev-002 prefix remained absent.
No configure, GNU Make, compiler, test, install, consumer, prefix, or
checkpoint command ran. The user's concurrent Drawterm activity remained
read-only and did not transfer operational ownership.

Raw evidence is retained at:

```text
C:\Users\dharm\vm\ocaml\evidence\
  plan9-phase-2-process-primitives-optional-argument-correction-001\
    attempt-001
```

## Phase 2 incremental world build

`plan9-phase-2-process-primitives-incremental-build-resume-001` ran the
existing Phase 1-configured GNU Make `world` target in:

```text
/usr/glenda/src/ocaml-plan9-phase2-incremental-001
```

The exact command was launched through an attempt-specific APE psh driver.
The guest log began at `2026-07-25 13:17:41 GMT` and ended at
`2026-07-25 13:44:42 GMT`; the host launch timestamps give a wall-clock
duration of 27 minutes and 1.251 seconds. GNU Make and the host Drawterm
launcher both returned zero.

The build was incremental but broad. It compiled the new
`runtime/plan9_process.b.o`, relinked the built-in primitive table and
standard `ocamlrun`, rebuilt the standard library after that foundational
runtime change, reused existing compiler objects while regenerating and
relinking affected compiler artifacts, and completed all selected
otherlibraries. The corrected Plan 9 sources compiled without warning 16 and
produced:

```text
runtime/ocamlrun
  SHA-1: 70527e2e1f16228b7f7ab7c93ba23f8fcc83429e
ocamlc
  SHA-1: a2c2a53b48ba15d9cb052916bd967576236dc0e6
ocaml
  SHA-1: fc12eb68d73d37d0b18a8cba75f2982a94a97f94
otherlibs/plan9/plan9.cma
  SHA-1: 7ee03a29b771cae4d87c8f173a234d5f51276b1d
```

The completed 619-line, 85,335-byte guest log remains at:

```text
/tmp/plan9-phase2-incremental-build-resume-001.log
SHA-1: b29239056f2fca1b4cd9b47e2d966320fa86c1c9
```

Its terminal record is `STATUS=0`. A post-build process snapshot contained no
GNU Make, compiler, `ocamlrun`, or build-driver process. The VM remains
running deliberately for the user's read-only Drawterm inspection.

The first attempt driver incorrectly wrote the literal four bytes `%s\n` to
its separate status file because its APE `printf` format was over-escaped.
That file remains preserved with SHA-1
`c9176b148258dcff129a41244ef3c16ad89e9197`. This procedural evidence defect
does not change the build result: the terminal guest log records `STATUS=0`,
the driver reached its end marker, and the independently retained host
Drawterm exit code is zero.

No test, installation, consumer, prefix, checkpoint, configure, clean, or
source-correction command ran during this build gate. Host launch evidence is
retained at:

```text
C:\Users\dharm\vm\ocaml\evidence\
  plan9-phase-2-process-primitives-incremental-build-resume-001\attempt-001
```

## Corrected reusable incremental-build driver

`plan9-phase-2-process-primitives-incremental-build-driver-correction-001`
preserved the completed attempt and created a distinct reusable driver:

```text
host:
  C:\Users\dharm\vm\ocaml\evidence\
    plan9-phase-2-process-primitives-incremental-build-driver-correction-001\
      attempt-001\incremental-build-driver-v2.sh
guest:
  /tmp/plan9-phase2-incremental-build-driver-v2.sh
bytes: 1596
SHA-1: c164a14c56cb130017ceab85a69f92945f2ae323
SHA-256: 950affbee95ac9c386f6e15ec5c53935c6436fcc135a3d12770c7cfbee3b34d1
```

The driver takes one validated attempt name, refuses existing attempt logs or
status files, uses an atomic build-lock directory to reject concurrent builds,
records start/end/status in a unique log, and writes the numeric exit status
with APE `echo` rather than the faulty `printf`. From rc, its invocation shape
is:

```rc
ape/psh /tmp/plan9-phase2-incremental-build-driver-v2.sh ATTEMPT
```

The non-building `--check` mode passed through that exact rc-to-APE
invocation, proved the configured native tree and GNU Make path, round-tripped
a temporary status value as exactly `0`, removed its temporary file, and left
no lock. An earlier nested invocation tried to resolve `ape/psh` from inside
APE psh and failed before the driver ran; it caused no build, log, lock, test,
or installation action. Validation evidence is retained beside the host
driver above.

## Phase 2 first focused suite and test-warning correction

The user launched `plan9-phase-2-process-primitives-incremental-test-001`
through the validated rc-to-APE wrapper. The repository-owned `test` target
compiled its test-only programs and ran all five focused suites:

```text
Plan9.Env tests passed
process_state_test: passed
process_primitive_validation_test: passed
process_frame_parser_test: passed
process_native_integration_test: passed
```

The test began at `2026-07-25 14:04:37 GMT` and ended at
`2026-07-25 14:04:47 GMT`. Its separate status file contains exactly `0`.
The completed log identities are:

```text
/tmp/plan9-phase2-incremental-test-001.log
  bytes: 2943
  lines: 38
  SHA-1: fe61eeea3589a608601a9bea04094d9f3e3fdd17
/tmp/plan9-phase2-incremental-test-001.status
  bytes: 2
  SHA-1: 09d2af8dd22201dd8d48e5dcfcaed281ff9422c7
```

A post-test process snapshot contained no GNU Make, compiler, test helper, or
managed child process. This was the complete focused Plan 9 library target,
not the upstream OCaml testsuite, isolated-prefix installation, installed
consumer proof, or opt-in native note-interruption test.

Compilation of the native integration harness emitted non-fatal warning 21
because the `--raw-exec` branch sequenced an unreachable `true` after
`raw_exec_mode`. Successful `Plan9.Raw.exec` replaces the process, while both
reported-return branches raise a test failure, so the branch itself already
has the required polymorphic result. The authoritative Windows correction
changed only:

```ocaml
| [_; "--raw-exec"; helper; output] ->
    raw_exec_mode helper output
```

The reviewed file identities are:

```text
otherlibs/plan9/tests/process_native_integration_test.ml
before:
  bytes: 19626
  SHA-1: 2b1cd78ad6fcd78d253c6b0266a20bb3866839c8
  SHA-256: 9f8b63fb077fe6d17189e60abbfa31021d3a8844d8d077b929c06611bef75ca1
after:
  bytes: 19614
  SHA-1: 1cf51a1e0e6dd09f49fb5340c56fcac64c49f537
  SHA-256: d9f22b0faf70beaa045564555f7b2bbc2f1bd6e37ea83191083c769f1d89261b
```

The correction remained unstaged and the index tree remained
`d1fad9efbc188dd079ba0f777fbb4840fca00af3`. The corrected file was copied
through `/mnt/term` into a unique guest staging directory, rehashed there,
then copied into the prepared native tree. The destination SHA-1 is the exact
corrected value above. The staging directory was removed, and the first test
log and status hashes remained unchanged.

No build or test ran after the correction. The source change affects only the
native integration test executable; the next `otherlibs/plan9 test` target
will incrementally recompile that program before rerunning the five suites.
No bytecode-world rebuild or configure step is required.

Correction and transfer evidence is retained at:

```text
C:\Users\dharm\vm\ocaml\evidence\
  plan9-phase-2-process-native-test-warning-correction-001\attempt-001
```

`plan9-phase-2-process-primitives-incremental-test-resume-001` then rebuilt
the corrected native integration test executable and reran all five focused
suites with suffix `p2_inc_002`. The run began at
`2026-07-25 14:15:30 GMT`, ended at `14:15:35 GMT`, and returned zero.
Warning 21 was absent. All suite markers passed:

```text
Plan9.Env tests passed
process_state_test: passed
process_primitive_validation_test: passed
process_frame_parser_test: passed
process_native_integration_test: passed
```

The rerun evidence identities are:

```text
/tmp/plan9-phase2-incremental-test-resume-001.log
  bytes: 2296
  lines: 30
  SHA-1: be8d8535e2c15336b6e7dbcb3fea4f9b0035b8a4
/tmp/plan9-phase2-incremental-test-resume-001.status
  bytes: 2
  value: 0
  SHA-1: 09d2af8dd22201dd8d48e5dcfcaed281ff9422c7
```

A post-test process snapshot contained no GNU Make, compiler, test helper, or
managed child process. No opt-in interruption test, installation, consumer
check, configure, bytecode-world rebuild, prefix mutation, or source change
followed this passing rerun. Host result metadata is retained at:

```text
C:\Users\dharm\vm\ocaml\evidence\
  plan9-phase-2-process-primitives-incremental-test-resume-001\attempt-001
```

## Opt-in interruption attempt and harness correction

The user launched
`plan9-phase-2-process-primitives-incremental-native-interruption-001`
through the validated one-line driver. The target rebuilt nothing, invoked
the native integration program, and failed after the helper posted its
`interrupt` note:

```text
start: Sat Jul 25 14:30:57 GMT 2026
end: Sat Jul 25 14:30:58 GMT 2026
driver status: 2

/tmp/plan9-phase2-incremental-native-interruption-001.log
  bytes: 1211
  lines: 16
  SHA-1: 72fe592461e761814371973bd821b69df3e9e925
/tmp/plan9-phase2-incremental-native-interruption-001.status
  bytes: 2
  value: 2
  SHA-1: 7448d8798a4380162d4b56f9b452e2f6f9e24e7a
```

The program emitted neither its pass marker nor an OCaml assertion failure
before GNU Make reported the program's failure. A post-attempt process
snapshot contained no GNU Make, `ocamlrun`, native test helper, or managed
child process.

The accepted native ABI interruption probe had installed an `atnotify`
handler before posting `interrupt`. The OCaml integration test had installed
no APE signal handler, so the note took the default SIGINT disposition and
terminated the test process rather than allowing native await to report exact
error `interrupted`. This rejected attempt therefore exposed a test-harness
precondition, not evidence that the production wait classifier or
handle-retention path was wrong.

The reviewed Windows-only correction changed only
`otherlibs/plan9/tests/process_native_integration_test.ml`. The qualification
mode now installs a temporary no-op `Sys.sigint` handler before spawning the
notifier and restores the previous disposition with `Fun.protect` after the
managed child is terminally resolved. Production source and public APIs are
unchanged.

```text
before:
  bytes: 19614
  Git blob: 62bcff2184e969ab6d0eaf7e4a3d9e4ddf7d0a2b
  SHA-1: 1cf51a1e0e6dd09f49fb5340c56fcac64c49f537
  SHA-256: d9f22b0faf70beaa045564555f7b2bbc2f1bd6e37ea83191083c769f1d89261b
after:
  bytes: 19916
  Git blob: 9c016630d45b38626d08a7dac4529633fe41c772
  SHA-1: a024d7026688e2f6045a5ebb64bb843feaa4c428
  SHA-256: 6d15727816b5d428fc5bda4b3a00979f4a267b18995653449bddb2e7bb33ae11
```

The exact corrected file was copied through `/mnt/term` into a unique native
staging directory, matched the expected SHA-1 there, then replaced only the
corresponding file in
`/usr/glenda/src/ocaml-plan9-phase2-incremental-001`. The destination is
19,916 bytes with the same SHA-1. Plan 9 did not provide `rmdir`; after the
staged file had already been removed, the exact empty staging directory was
verified beneath `/tmp` and removed with Plan 9's supported `rm -r`.

A collision-free successor driver was derived from the already reviewed
driver by changing only attempt-specific names:

```text
/tmp/plan9-phase2-incremental-native-interruption-resume-001-a001.rc
  SHA-1: 7074186e4d21266b0b2b261b6e9dd95d9d92d0bc
/tmp/plan9-phase2-incremental-native-interruption-resume-001-a001.sh
  SHA-1: c1836eb9db9327c6b955553a17b2c716e08c1e3e
```

Its non-test `--check` path passed and confirmed the native tree, GNU Make,
ordinary-suite status zero, target, and absent log/status/lock paths. No build
or test ran after the correction.

`plan9-phase-2-process-primitives-incremental-native-interruption-resume-001`
then incrementally recompiled the corrected integration test, rebuilt its
bounded native helper, and ran only `test-native-interruption`. It passed:

```text
start: Sat Jul 25 14:43:58 GMT 2026
end: Sat Jul 25 14:44:00 GMT 2026
status: 0
marker: process_native_integration_test: interruption passed

/tmp/plan9-phase2-incremental-native-interruption-resume-001.log
  bytes: 1366
  lines: 18
  SHA-1: 3541cd5401d8f0e5830d65ec6f7805af27a18124
/tmp/plan9-phase2-incremental-native-interruption-resume-001.status
  bytes: 2
  value: 0
  SHA-1: 09d2af8dd22201dd8d48e5dcfcaed281ff9422c7
```

The handled note caused native await to return the exact distinct
`interrupted` result. The ML coordinator preserved the same logical handle,
retried through its single native wait path, terminally resolved the helper,
and left `Process.unresolved ()` empty. The source-scoped `Fun.protect`
restored the previous SIGINT disposition on the successful path. The complete
post-test `.40` process snapshot contained no GNU Make, compiler, `ocamlrun`,
integration test, native helper, or managed child process.

The user then halted `.40` with guest `fshalt`. Halted postflight established:

```text
recorded P9QEMU, console, Python, and QEMU PIDs: all exited
seven 127.0.0.40 listeners: all closed and bindable
instance contents: exactly disk.qcow2 and instance.json
disk bytes: 1641086976
disk SHA-256:
  559fb5c400d10727ac38fed2cf5aecafbb701e309d18b881101a5b77ff4c59eb
instance.json bytes: 1033
instance.json SHA-256:
  c87a3a9c2ef79d7640e03c689861cfea0cd73c54c72eea5f77b81cd6d8e46225
exclusive disk open: passed
dirty flag: false
corrupt flag: false
qemu-img check: no errors
backing relationship: unchanged exact immutable cached base
```

A non-launching dry run with a fresh nonexistent temporary serial path
selected only `whpx,kernel-irqchip=off`, the exact `.40` address and seven
forwards, and the accepted instance. It created no serial file and launched no
process.

## GitHub qualification launch and source-acquisition preparation

The user selected a fresh GitHub clone of the published qualification branch
as the next source-origin validation. This is a deliberate qualification
variant from the tracked exact-index-archive procedure. Windows remains the
authoritative editing and publication repository; the native git9 checkout
will be a build input, not a competing development repository.

Live Windows Git was clean before launch:

```text
branch: codex/plan9-phase2-process-primitives-qualification
HEAD and upstream: d8ec53e72a09d4ff9532778d4dfd0c6b87cb83f2
implementation parent: c8345f28a1be5d59b0ebcc93544e6a6aaa172984
remote: https://github.com/dharmatech/ocaml.git
```

Only `C:\Users\dharm\vm\ocaml\dev` was launched at `127.0.0.40`.
The non-launching dry run and live command line selected only
`whpx,kernel-irqchip=off`, with no TCG fallback:

```text
P9QEMU PID: 35220
Python PIDs: 36204 and 28120
QEMU PID: 10892
listeners: QEMU PID 10892 owns 17010, 17019, 17020, 17021, 17022,
  17564, and 17567 on 127.0.0.40
serial:
  C:\Users\dharm\vm\ocaml\evidence\
    plan9-phase-2-process-primitives-github-qualification-001\
      attempt-001\serial.raw.log
```

A bounded Drawterm readiness command returned `OCAML_PLAN9_READY`. The user
then reported an interactive Drawterm connection to `.40`. The OCaml task
remains the sole stateful operator; the user's inspection does not transfer
ownership.

The source-acquisition script preparation retained two host-only procedural
rejections before accepted attempt 003. Attempt 001 used a wildcard with
PowerShell's literal hash mode after copying the host evidence files. Attempt
002 discovered that native rc `test -e` emits diagnostics for expected
absence unless stderr is suppressed. Neither attempt transferred a script,
contacted GitHub, created the native source destination, or started a clone.

Accepted attempt 003 copied and verified these executable native scripts:

```text
/tmp/plan9-phase2-github-source-acquisition-driver-001.rc
  bytes: 3680
  SHA-1: 46e1907dc410a52ad943fd18d63fb4ba10999cfe
  SHA-256:
    f28bdb5d6726cbdf9849bfe47be262eb292b25762d0308db4185aaeb15ea2aa5

/tmp/plan9-phase2-github-source-acquisition-001.rc
  bytes: 946
  SHA-1: 3d8c4ae2b3515728c7cb0141ec05e20ecb6d4384
  SHA-256:
    9517281e816bca1e6fdb675931fc5099e692493d276524c36f6138d58e29dfc3
```

The driver's non-cloning `--check` mode passed. It parsed under native rc,
resolved the installed git9 and verification tools, required the exact
published branch tip and implementation parent, and confirmed the destination
was absent. Final validation found the launcher log, status, lock, and
destination absent:

```text
/tmp/plan9-phase2-github-source-acquisition-001.log
/tmp/plan9-phase2-github-source-acquisition-001.status
/tmp/plan9-phase2-github-source-acquisition-001.lock
/usr/glenda/src/ocaml-plan9-phase2-github-qualification-001
```

At script-delivery closeout, the scripts had not been run in acquisition mode.
No GitHub contact, clone, configure, build, test, installation, prefix
mutation, checkpoint, or source edit had occurred. Accepted raw delivery
evidence is retained at:

```text
C:\Users\dharm\vm\ocaml\evidence\
  plan9-phase-2-process-primitives-github-source-acquisition-script-001\
    attempt-003
```

### Rejected GitHub source-acquisition attempt 001

The user then ran
`/tmp/plan9-phase2-github-source-acquisition-001.rc` from the interactive
`.40` Drawterm session. The driver started git9 with the exact public remote,
branch, expected tip, parent, and destination, but git9's HTTPS transport
could not open its required webfs allocation file:

```text
git/get: could not dial https://github.com/dharmatech/ocaml.git:
  file does not exist: '/mnt/web/clone'
/bin/git/clone: could not clone repository
SOURCE_ACQUISITION_FAILURE git clone failed with status
  clone 768: clone 775: could not clone repository
```

Git9 cleaned
`/usr/glenda/src/ocaml-plan9-phase2-github-qualification-001`.
The launcher removed its exact lock and retained its log and status:

```text
/tmp/plan9-phase2-github-source-acquisition-001.log
  SHA-1: 2acbdfcde8bda18c9acdd599e5fb505591c3ef0c
/tmp/plan9-phase2-github-source-acquisition-001.status
  SHA-1: 86ad8a6dc0ade506b161d9f7c70becc514dfec8c
```

The status text is
`plan9-phase2-github-source-acquisition-driver-001.rc 751:
source-acquisition-failed`. The destination and lock are absent. No checkout,
configure, build, test, installation, prefix mutation, or source edit
occurred. The rejected attempt is preserved at:

```text
C:\Users\dharm\vm\ocaml\evidence\
  plan9-phase-2-process-primitives-github-source-acquisition-001\
    attempt-001
```

Installed `webfs(4)` states that `webfs` mounts itself at `/mnt/web` by
default and provides `clone` at the top level. The installed source calls
`postmountsrv` after creating its note group; lib9p mounts the pipe-backed
server into the caller's namespace and forks the server with its own name and
note groups. A later independent `.40` Drawterm namespace observed a webfs
process but no `/mnt/web/clone`, confirming that process existence alone does
not provide the mount to another namespace.

The qualification driver should therefore create a private namespace with
`rfork en`, start `webfs -m /mnt/web` inside that same namespace only when
`/mnt/web/clone` is absent, verify the clone file, then invoke git9. This keeps
the network filesystem requirement explicit and reproducible without adding
ambient qualification state to Glenda's profile. It is a source-backed
inference that the private mount connection will close and its server will
terminate when the driver namespace exits; the corrected attempt must verify
that no new webfs process remains.

### Corrected GitHub source-acquisition script preparation

The user authorized the `-002` correction and delivery. Accepted attempt 001
prepared and copied:

```text
/tmp/plan9-phase2-github-source-acquisition-driver-002.rc
  bytes: 4262
  SHA-1: 7e5986411e9636bca5de383b89598c1fc10b8a86
  SHA-256:
    ac5e123fe8a18aed4e3b7d3861aa42498beb2b3857910b1d4799cc30f9f65ac8

/tmp/plan9-phase2-github-source-acquisition-002.rc
  bytes: 1193
  SHA-1: f3a25658a72954880c1ba593c0e03f49de7d42ee
  SHA-256:
    cdad07c3aec8169e61ce6ff98b75fbd6d463db830cbd2c7a4aa93eea1f439629
```

The corrected driver uses `rfork en`. In acquisition mode it starts
`/bin/webfs -m /mnt/web` only when `/mnt/web/clone` is absent in that private
namespace, verifies the clone file, then invokes git9. After clone it starts a
private `git/fs` before the branch, history, gitlink, and clean-tree checks.
The launcher records webfs process snapshots before the driver, immediately
after it exits, and after a one-second settle interval.

The driver's non-cloning `--check` mode passed under native rc. It started no
webfs, contacted no network, and created no destination. Final delivery
validation found no webfs process and found all of these paths absent:

```text
/tmp/plan9-phase2-github-source-acquisition-002.log
/tmp/plan9-phase2-github-source-acquisition-002.status
/tmp/plan9-phase2-github-source-acquisition-002.lock
/usr/glenda/src/ocaml-plan9-phase2-github-qualification-001
```

Accepted preparation evidence is retained at:

```text
C:\Users\dharm\vm\ocaml\evidence\
  plan9-phase-2-process-primitives-github-source-acquisition-resume-001\
    attempt-001
```

### GitHub source acquisition runs and retained checkout

The user ran `/tmp/plan9-phase2-github-source-acquisition-002.rc` twice.
During the first run the private webfs mount became ready, but git9's HTTPS
request ended with:

```text
git/get: could not dial https://github.com/dharmatech/ocaml.git:
  0 No status interrupted: '/mnt/web/0/body'
```

Git9 cleaned the destination and the private webfs process did not remain.
The user then ran `echo ipv6 >/net/cs`. The user reports that this toggles
IPv6 lookup handling for the whole running Plan 9 system, does not survive a
reboot, and would reverse the setting if run a second time. This is recorded
as a user-performed, system-global operational workaround. It must not be
placed blindly in a rerunnable acquisition script. Any durable boot policy
requires separate source-backed analysis and authorization.

The second run cloned and checked out the repository, indexed 179793 objects,
and reached `GIT_FS_READY`. Its post-clone required-path loop then failed
because it reused `path`, rc's executable-search variable, as the loop
variable. On the first item rc therefore attempted to resolve `test` and then
the failure handler's `echo` beneath `README.md`:

```text
test: not a directory: 'README.md'
echo: not a directory: 'README.md'
```

The launcher correctly retained the checkout and removed its lock. Its
post-clone verification failure is recorded in:

```text
/tmp/plan9-phase2-github-source-acquisition-002.log
  SHA-1: 1248519e19942f6fdb0ac9bc84ad4c2a8fdcb202
/tmp/plan9-phase2-github-source-acquisition-002.status
  SHA-1: c38e7cdf975729544cca9e97cb986276d17382f6
  text:
    plan9-phase2-github-source-acquisition-driver-002.rc 1567:
      source-acquisition-failed
```

A separate read-only Drawterm verification started a private `git/fs` in the
retained checkout and established:

```text
destination:
  /usr/glenda/src/ocaml-plan9-phase2-github-qualification-001
branch:
  heads/codex/plan9-phase2-process-primitives-qualification
HEAD:
  d8ec53e72a09d4ff9532778d4dfd0c6b87cb83f2
parent:
  c8345f28a1be5d59b0ebcc93544e6a6aaa172984
required source paths: present
flexdll gitlink directory: empty
tracked changes: none
untracked paths: none
source-acquisition lock: absent
remaining webfs processes: none
```

The clone itself is therefore an exact, clean source acquisition. The
`-002` launcher result is not accepted as a fully passing evidence-driver run
because its verifier failed after checkout. Do not delete or reclone the
retained exact checkout merely to correct that procedural defect.

### Verification-only correction result

The verification-only correction scripts are prepared:

```text
/tmp/plan9-phase2-github-source-verification-driver-003.rc
  bytes: 3543
  SHA-1: ca8b69e92ea9f897937dab9c092f3376d0c2387a
  SHA-256:
    90515ad0bb431a890e382bfc40dca1f117f2a7908352cc1d4b56c6fbf5edfcc3

/tmp/plan9-phase2-github-source-verification-003.rc
  bytes: 1131
  SHA-1: 0c93c066116acad9884d3fb7aac550bea99df587
  SHA-256:
    c11ad8025d955951405ca66ded89a3be1ecf86d4d51ca696c2ce2090e7035379
```

Both use nonspecial loop variables. The driver performs no network operation,
does not start webfs, and does not write the checkout. Its non-running
`--check` mode passed against the retained destination. The distinct `-003`
log, status, and lock paths were absent after preparation. The initial
headless transfer path through the Windows user profile was inaccessible and
created no guest target; the accepted transfer used two hash-matched temporary
files beneath `C:\temp`, then removed only those verified transfer copies.
Host evidence copies are retained at:

```text
C:\Users\dharm\vm\ocaml\evidence\
  plan9-phase-2-process-primitives-github-source-verification-correction-001\
    attempt-001
```

The user ran:

```rc
/tmp/plan9-phase2-github-source-verification-003.rc
```

The result is accepted. It returned status `0` and finished with
`SOURCE_VERIFICATION_READY`. The log recorded `NETWORK none`, the exact
published branch, tip, and parent, the required source hashes, an empty
`flexdll` representation, and no tracked or untracked path. The launcher
removed its lock and neither the before nor after snapshot nor a separate
live check found a webfs process:

```text
/tmp/plan9-phase2-github-source-verification-003.log
  SHA-1: 4124b958915ea4f34866f1e36ae8db843b1b2cc0
/tmp/plan9-phase2-github-source-verification-003.status
  SHA-1: 09d2af8dd22201dd8d48e5dcfcaed281ff9422c7
  text: 0
```

The guest log and status remain in `/tmp`. A bounded attempt to copy them
through the headless Drawterm `/mnt/term/C:/temp` mount was denied before
creating either destination, so the host evidence attempt retains the scripts
and the tracked record retains the output identities and conclusions.

Read-only qualification preflight confirmed that the production prefix and
accepted Phase 1 prefix exist, while the intended isolated Phase 2 prefix is
absent:

```text
/usr/glenda/lib/unix/ocaml-4.14.3
/usr/glenda/lib/unix/ocaml-4.14.3-plan9-dev-001
ABSENT /usr/glenda/lib/unix/ocaml-4.14.3-plan9-dev-002
GNU Make:
  /usr/glenda/lib/unix/make-4.4.1/bin/make
```

## Exact-source GitHub qualification

The recommended next separately authorized action is
`plan9-phase-2-process-primitives-github-native-qualification-preparation-001`.
The first preparation step produced and verified:

```text
/tmp/plan9-phase2-github-qualification-preflight-driver-001.rc
  bytes: 3725
  SHA-1: 3f16b044967f3036ce19e73c390d61723184537b
  SHA-256:
    51ae054e4f04a567bc05fe98ae22d2d1c14af0cb975d6069bdebc98b2068d7be

/tmp/plan9-phase2-github-qualification-preflight-001.rc
  bytes: 1115
  SHA-1: 32fb53c7aeade8c57f0104655aa0487d62f17f37
  SHA-256:
    aa504066aeb7fab28dc2c57aaad3e674659557eb47c63b8676cc06be3ec5e86a
```

The driver's non-running `--check` mode passed. It confirmed the retained
source, production and Phase 1 prefixes, absent dev-002 prefix, exact
source-verification driver, GNU Make, APE shell, git9 and inventory tools,
unconfigured source tree, and collision-free preflight evidence paths. It
performed no inventory, configure, build, network, prefix, or source mutation.
Host evidence copies are retained at:

```text
C:\Users\dharm\vm\ocaml\evidence\
  plan9-phase-2-process-primitives-github-native-qualification-preparation-001\
    attempt-001
```

The user ran:

```rc
/tmp/plan9-phase2-github-qualification-preflight-001.rc
```

The preflight is accepted. It returned status `0`, finished with
`QUALIFICATION_PREFLIGHT_READY`, and ran from 16:53:28 through 16:53:34 GMT.
It reverified the exact branch, tip, parent, required source hashes, empty
gitlink, and clean checkout. GNU Make identified itself as 4.4.1 built for
`x86_64-unknown-plan9`, and the APE shell resolved `c89` as `/bin/c89`.

The production-prefix inventories both contain 336 files:

```text
/tmp/plan9-phase2-github-qualification-preflight-001.log
  SHA-1: 13abbee12a438ed1c686af224c79bd8ec147057a
/tmp/plan9-phase2-github-qualification-preflight-001.status
  SHA-1: 09d2af8dd22201dd8d48e5dcfcaed281ff9422c7
  text: 0
/tmp/plan9-phase2-github-qualification-preflight-001-a001/
  production-layout-before.txt
    SHA-1: e871b8a897976a13aa8f4b8283acc61a48e349fe
  production-sha1-before.txt
    SHA-1: 06bacc059c59a928ae69df5bee1e084772b8b77e
```

The preflight lock is absent, dev-002 remains absent, and `config.status` and
`Makefile.config` remain absent from the exact source. No configure, build,
install, network, or compiler-prefix mutation occurred.

The configure-only scripts are prepared and verified:

```text
/tmp/plan9-phase2-github-qualification-configure-driver-001.sh
  bytes: 5200
  SHA-1: f20f4e565f3d75dda31e0f491f889720eda9a4ec
  SHA-256:
    455f1fe78f5cdfbf95d411faf340612e69606a5a2ca5349e2e18dab14bb7002c

/tmp/plan9-phase2-github-qualification-configure-001.rc
  bytes: 163
  SHA-1: a1ef3ab18fd5901d282679c6c1accb960bdc1cc2
  SHA-256:
    72b0043b21e7db6a4da0b8a5d5de593412d88a04d428f5f844a3367c8ee9e6ad
```

The rc launcher enters the exact source and executes the driver under
`ape/psh`. The driver reruns the exact source verifier before mutation, sets
and exports GNU Make and `CC=c89`, invokes only the Plan 9 configure wrapper
for dev-002, and records human timestamps, numeric `date -n` timestamps,
elapsed seconds, and `HH:MM:SS`. On success it retains exact copies and hashes
of `config.status` and `Makefile.config`, records selected configuration
fields, and stops before Make.

Its non-running `--check` mode passed. It confirmed the accepted preflight,
production inventories, absent dev-002 prefix, unconfigured exact source, and
collision-free configure log, status, lock, and evidence paths. Host evidence
copies are in the existing preparation attempt.

The user ran:

```rc
/tmp/plan9-phase2-github-qualification-configure-001.rc
```

The configure result is accepted. It returned status `0`, finished with
`QUALIFICATION_CONFIGURE_READY`, and measured exactly eight seconds:

```text
/tmp/plan9-phase2-github-qualification-configure-001.log
  SHA-1: d31952744361167cdb09d903798b1ab077c168db
/tmp/plan9-phase2-github-qualification-configure-001.status
  SHA-1: 09d2af8dd22201dd8d48e5dcfcaed281ff9422c7
  text: 0
/tmp/plan9-phase2-github-qualification-configure-001-a001/
  config.status
    SHA-1: f521deda0dee8a793b860d860d4ac500c3729e83
  Makefile.config
    SHA-1: 0d003860a9b2a2b0da27b6423d783fe482cf945f

CONFIGURE_START_EPOCH=1784999263
CONFIGURE_END_EPOCH=1784999271
CONFIGURE_ELAPSED_SECONDS=8
CONFIGURE_ELAPSED_HMS=00:00:08
```

The evidence copies match the generated source files. The selected
configuration is `x86_64-unknown-plan9`, `CC=c89`, native compiler disabled,
shared libraries disabled, systhreads disabled, and
`OTHERLIBRARIES=dynlink unix bigarray str plan9`. The configure lock is
absent, dev-002 remains absent, and the fresh world-build sentinels
`runtime/ocamlrun`, `ocamlc`, and `otherlibs/plan9/plan9.cma` are absent.

The timed full-world build scripts are prepared and verified:

```text
/tmp/plan9-phase2-github-qualification-world-build-driver-001.sh
  bytes: 5287
  SHA-1: 26873e23518f1d8be5cd65900203deb253184514
  SHA-256:
    0b34dd7f595bebab8f4c417b231f07f6f12160661dd850a7f1d6c1574a865f0a

/tmp/plan9-phase2-github-qualification-world-build-001.rc
  bytes: 165
  SHA-1: 7f743fbbb89f35b511a9c8772e6642c7b3bd6932
  SHA-256:
    d2ef34aef3d7b77ae2f9ec2422e8e566ce26063439495c63f95e692bbc73ca2e
```

The driver's non-running `--check` mode passed. It pins the accepted
configuration and critical source hashes, refuses existing build artifacts,
dev-002, log, status, lock, or evidence paths, and records human and epoch
times, elapsed seconds, and `HH:MM:SS`. It runs only
`build-aux/plan9/build-world.sh`; it does not test or install.

The user ran:

```rc
/tmp/plan9-phase2-github-qualification-world-build-001.rc
```

The exact world build is accepted. It returned status `0`, finished with
`QUALIFICATION_WORLD_BUILD_READY`, and measured 2,276 seconds:

```text
/tmp/plan9-phase2-github-qualification-world-build-001.log
  SHA-1: f5c00b875295d25468aadc03ddff6f72d675b9e2
/tmp/plan9-phase2-github-qualification-world-build-001.status
  SHA-1: 09d2af8dd22201dd8d48e5dcfcaed281ff9422c7
  text: 0
/tmp/plan9-phase2-github-qualification-world-build-001-a001/
  artifact-sha1.txt
    SHA-1: 69364380914d5f0483f79bd0173cbe93d1bf23d3

WORLD_BUILD_END_EPOCH=1785001881
WORLD_BUILD_ELAPSED_SECONDS=2276
WORLD_BUILD_ELAPSED_HMS=00:37:56
WORLD_BUILD_COMMAND_STATUS=0
```

The evidence artifact hashes match the live build:

```text
bfd90e02106473094c2f54dc189217f5daaf32e4  runtime/ocamlrun
2d65adb530a1dff611715be5b4196aa96821d11f  ocamlc
b052ca6b994d6d73c8dc36184b928fdfc4f0b6b9  otherlibs/plan9/plan9.cma
```

No `Error` or `error:` line was found. The lowercase `warning` matches were
only compiler warning-option arguments or source paths containing
`warnings`; no emitted warning diagnostic was observed. The build lock is
absent, dev-002 remains absent, and no install evidence path exists.

The ordinary focused-test scripts are prepared and verified:

```text
/tmp/plan9-phase2-github-qualification-focused-test-driver-001.sh
  bytes: 5647
  SHA-1: 6cad7aa70d74eef46be0bdf42ad4bcb2eb1c2685
  SHA-256:
    32466eb71abf14b744fa99aab1bd1e28b460e29f818c05e2b6e1eea7c139c2ac

/tmp/plan9-phase2-github-qualification-focused-test-001.rc
  bytes: 166
  SHA-1: b54b2b41921db3dddd0692064ed98c156543a78b
  SHA-256:
    309f7f84cfabe20c8ac8a6bf42d54b661be375ef95b755a3bfc92cf9e508adaf
```

The non-running `--check` mode passed. The driver pins the three accepted
world-build artifacts, uses unique suffix `p2_github_qual_001`, runs the five
ordinary suites, validates all five success markers and dedicated `/env`
cleanup, records test-binary hashes and elapsed time, and keeps native note
interruption explicitly excluded for its separate step.

The user ran that launcher. The underlying GNU Make test command returned
zero in 11 seconds, and the log visibly contains all five required markers:

```text
Plan9.Env tests passed
process_state_test: passed
process_primitive_validation_test: passed
process_frame_parser_test: passed
process_native_integration_test: passed
```

The wrapper nevertheless returned status `81` after reporting each marker
missing:

```text
/tmp/plan9-phase2-github-qualification-focused-test-001.log
  SHA-1: 54667a4f3890963459bc7a01e9f5c673848963df
/tmp/plan9-phase2-github-qualification-focused-test-001.status
  SHA-1: 35bfc22420a7d20d27504a12743b4856fc0fedf9
  text: 81
```

This is a procedural evidence-driver rejection, not a focused implementation
test failure. The driver prepended the repository shim directory to `PATH` and
then invoked unqualified `fgrep`. That resolved to
`build-aux/plan9/shims/bin/fgrep`, which delegates to
`/tmp/gmake-shims/grep`; its exact marker probes reported no matches. Native
`/bin/fgrep` finds every marker in the same retained log. The test lock is
absent, no dedicated test environment name remains, and no install or prefix
mutation occurred. The driver stopped before writing
`test-artifact-sha1.txt`, so the test-binary evidence bundle is incomplete.

The corrected resume uses suffix `p2_github_qual_002`, invokes
`/bin/fgrep` explicitly, and writes only new `focused-test-002` log, status,
lock, and evidence paths. Its driver and launcher are:

```text
/tmp/plan9-phase2-github-qualification-focused-test-driver-002.sh
  bytes: 6989
  SHA-1: e2ec101fba36ed4139f8246fd8cc0fc25089cfd0
  SHA-256:
    531b83ebb9b299f6989c5a328a89c5ef8e5991eb42ade588ed1a5e059571ab10
/tmp/plan9-phase2-github-qualification-focused-test-002.rc
  bytes: 166
  SHA-1: e1d54ac5e12633372b5ba430504f4098cfa5bbe5
  SHA-256:
    5092ed51b23e48b7ef5d55df55a95d6088d25af32b45a72564408e8506deb911
```

Preparation retained three fail-closed procedural attempts. Attempt 001 used
POSIX `fail()` syntax in a native `rc` delivery wrapper and stopped at line 8
before copying. Attempt 002 corrected the function syntax but used an
unquoted `=` as a `test` argument. Native `rc` copied the exact driver and
launcher before encountering that later syntax error; it ran neither
`--check` nor tests. Attempt 003 used native `~` comparison and correctly
refused to overwrite the destinations left by attempt 002.

Accepted preparation attempt 004 used a verification-only wrapper, required
the two destination hashes above, and ran only the driver's `--check`. The
check passed and established:

```text
QUALIFICATION_FOCUSED_TEST_RESUME_CHECK_PASSED
TEST_SUFFIX=p2_github_qual_002
MARKER_SCANNER=/bin/fgrep
PREVIOUS_ATTEMPT=status-81-procedural-rejection-preserved
INTERRUPTION=excluded-separate-step
```

It also required the retained status-81 log and status hashes, proved all five
old markers through `/bin/fgrep`, pinned the accepted world artifacts, found
dev-002 absent, required all six retained test programs, and found every new
log, status, lock, and evidence path absent. The host evidence attempts are
retained beneath:

```text
C:\Users\dharm\vm\ocaml\evidence\
  plan9-phase-2-process-primitives-github-focused-test-resume-001\
    attempt-001 through attempt-004
```

Immediately before preparation, only the recorded `.40` chain was live:
P9QEMU PID 35220, Python PIDs 36204 and 28120, and QEMU PID 10892. QEMU
alone owned all seven `127.0.0.40` listeners and retained
`whpx,kernel-irqchip=off`.

The user ran the corrected launcher. The focused test is accepted: GNU Make
returned zero, all five suites emitted their required markers, and the run
took four seconds:

```text
/tmp/plan9-phase2-github-qualification-focused-test-002.log
  SHA-1: 90fadd984484d9d4592ebfbfdcac8f598380dd18
/tmp/plan9-phase2-github-qualification-focused-test-002.status
  SHA-1: 09d2af8dd22201dd8d48e5dcfcaed281ff9422c7
  text: 0
/tmp/plan9-phase2-github-qualification-focused-test-002-a001/
  test-artifact-sha1.txt
    SHA-1: 4075fb4cdc14adde0b73a7fdd23cb720729caaf3

FOCUSED_TEST_ELAPSED_SECONDS=4
FOCUSED_TEST_COMMAND_STATUS=0
QUALIFICATION_FOCUSED_TEST_RESUME_READY
```

The retained artifact manifest and an independent live comparison agree:

```text
6f703f32a1fc1695e4b7b71d9b55e375d40ebeed  tests/env_test
ffecd1df788334ee4f33d97cde60d74ec81ed07c  tests/process_state_test
c406474237cf384b092c3d374dbaecdfe014dddd  tests/process_primitive_validation_test
aa29af3f776e58841578dcc54ffaaeda7e50eaa8  tests/process_frame_parser_test
2464a9adc529bba05293bd8b89602da328b021d6  tests/process_native_integration_test
053e7fb3333adcfe59d68e1e847bd1ddb3b22e7b  tests/process_native_helper
```

The focused-test lock is absent. The scalar, function, and process-specific
dedicated `/env` names are absent. The first read-only cleanup command left
the function-name path unquoted, so native `rc` treated its `#` as a comment
and stopped after the scalar check; a corrected quoted check established both
remaining absences. No test or guest state was changed by either inspection.
Do not rewrite or delete the rejected `-001` log and status.

The separately opt-in native interruption scripts are now prepared:

```text
/tmp/plan9-phase2-github-qualification-native-interruption-driver-001.sh
  bytes: 5692
  SHA-1: 4aa0db026749573723dba348c2c0ba6458d541bc
  SHA-256:
    8e8e4c24eff9ec4eca39d038394d1caebe9ed8e193af048c86dca040276391cb
/tmp/plan9-phase2-github-qualification-native-interruption-001.rc
  bytes: 173
  SHA-1: 3fd60682c2dd119bfd44f585633e29db9e4323d0
  SHA-256:
    2fe7cce898de9e8aa42e3b178ac9a1c776835dd635a830adf5ec33b52a430a04
```

Their non-running check passed. It pins the accepted focused-test log, status,
artifact manifest, runtime, integration program, and native helper; requires
dev-002 and all new result paths absent; invokes only
`test-native-interruption`; validates the exact pass marker through
`/bin/fgrep`; records timing and artifact identities; and permits the bounded
helper to send `interrupt` only to its own parent. Preparation evidence is:

```text
C:\Users\dharm\vm\ocaml\evidence\
  plan9-phase-2-process-primitives-github-native-interruption-preparation-001\
    attempt-001
```

The user ran the interruption launcher. The result is accepted: it returned
zero in one second, emitted the exact interruption pass marker, terminally
resolved the retained handle on retry, and left its lock absent:

```text
/tmp/plan9-phase2-github-qualification-native-interruption-001.log
  SHA-1: fe8d8b553b2d81180489746a784be7da093fbb62
/tmp/plan9-phase2-github-qualification-native-interruption-001.status
  SHA-1: 09d2af8dd22201dd8d48e5dcfcaed281ff9422c7
  text: 0
/tmp/plan9-phase2-github-qualification-native-interruption-001-a001/
  interruption-artifact-sha1.txt
    SHA-1: 3003ce4bb38c20a6ee6cf6bf8ae701393682cbff

NATIVE_INTERRUPTION_ELAPSED_SECONDS=1
marker: process_native_integration_test: interruption passed
QUALIFICATION_NATIVE_INTERRUPTION_READY
```

The evidence manifest and independent live comparison agree on the unchanged
runtime, integration program, and bounded helper:

```text
bfd90e02106473094c2f54dc189217f5daaf32e4  runtime/ocamlrun
2464a9adc529bba05293bd8b89602da328b021d6
  otherlibs/plan9/tests/process_native_integration_test
053e7fb3333adcfe59d68e1e847bd1ddb3b22e7b
  otherlibs/plan9/tests/process_native_helper
```

The broader upstream suite first requires its `ocamltest` driver. The
configuration has deliberately excluded it from the documented world build
since the original Plan 9 configure wrapper. Upstream's bytecode `ocamltest`
target uses `ocamlc -custom`; the original Plan 9 port retained that mode and
added the build-tree-specific `-ccopt ../runtime/main.b.$(O)` workaround.
Therefore this exact `ocamltest` target may succeed even though general
installed/downstream custom-runtime linking remains a separately deferred
capability. Either result is testsuite infrastructure evidence rather than a
Phase 2 process regression.

The build-only scripts are prepared:

```text
/tmp/plan9-phase2-github-qualification-ocamltest-build-driver-001.sh
  bytes: 5932
  SHA-1: 7ccafe3602d21928650516e48bbbd492babc4da7
  SHA-256:
    f13b75f6fa3e0bebb88d2680fc2eb1de19477aed6c498bc30272cdfee7360bdc
/tmp/plan9-phase2-github-qualification-ocamltest-build-001.rc
  bytes: 169
  SHA-1: b8d46fb99297bcd00b9f8a9242e2a5fb81d84064
  SHA-256:
    9ce64da5f05b5a8571ecf755909d3a558ec9d6a7dc3c16cadbbc4857a9c4fca1
```

The non-build check passed. It pins the accepted interruption evidence and
world artifacts, requires the disabled-ocamltest configuration, absent
`ocamltest/ocamltest`, absent dev-002, and collision-free result paths. The
driver runs only root target `ocamltest`, records its upstream custom-link
mode and timing, smoke-runs `ocamltest -help` only after a successful build,
and stops before every testsuite target. Preparation evidence is:

```text
C:\Users\dharm\vm\ocaml\evidence\
  plan9-phase-2-process-primitives-github-ocamltest-build-preparation-001\
    attempt-001
```

At that point, the exact next user action was:

```rc
/tmp/plan9-phase2-github-qualification-ocamltest-build-001.rc
```

After that build-only prerequisite passes, prepare and review distinct
user-launched drivers for:

1. an upstream testsuite inventory and bounded bytecode-compatible run;
2. isolated install, runtime/primitive/archive/layout checks, ordinary
   installed-consumer and C-tool-sentinel proof, and production-prefix
   comparison; and
3. attempt-specific cleanup followed by the separately coordinated shutdown
   and halted host postflight.

The broader upstream testsuite is worthwhile regression evidence, but the
current Plan 9 configuration explicitly uses `--disable-ocamltest`, and root
`make tests` delegates to `testsuite all`, which refuses to run without a
built `../ocamltest/ocamltest`. A separate preparation step should first test
whether the already-built bytecode world can build the explicit root
`ocamltest` target without changing configuration, then inventory and classify
the bytecode-compatible test directories. Native-compiler, shared-library,
systhreads, debug-runtime, and unsupported Unix assumptions must be recorded
as unsupported or expected skips rather than confused with Phase 2
regressions. Run a bounded bytecode-compatible lane before considering a full
exploratory `testsuite all`, with separate infrastructure, skip, expected
failure, and regression accounting.

The focused-test step did not toggle `/net/cs`, contact GitHub, reclone, run
the opt-in interruption test, install, halt the guest, or create or mutate any
compiler prefix.

### Accepted broader upstream suite

The explicit `ocamltest` prerequisite built successfully from the already
built exact-source tree. This was a testsuite-infrastructure qualification of
the original Plan 9 build-tree custom-link workaround; it did not claim that
the separately deferred general downstream custom-runtime defect was fixed.

The broader upstream suite then completed successfully in 3,857 seconds
(`01:04:17`):

```text
passed: 1766
skipped: 522
not applicable or not started: 860
failures: 0
unexpected results: 0
timeouts: 0
missing-helper errors: 0
```

Retained evidence identities include:

```text
suite wrapper log SHA-1:
  5b331bdad48c22f463243165ee4cccba1b1da0dc
testsuite test log SHA-1:
  5625a883a86ac770defe2c015b0dab7c2f98df01
testsuite report SHA-1:
  dedf71166f3ff803c0bf9a5cd0783f26813c3f14
suite artifact-list SHA-1:
  2673b120eac16ef89fc52d5c26c183a61a012529
```

Native-compiler, shared-library, systhreads, debug-runtime, and unsupported
Unix cases remained classified by the configured bytecode-only Plan 9 lane;
they were not reported as Phase 2 regressions.

### Accepted isolated installation and installed consumer

The exact source installed only into:

```text
/usr/glenda/lib/unix/ocaml-4.14.3-plan9-dev-002
```

Installation returned zero in 14 seconds and produced 338 files. The
production prefix retained the same 336 paths and digests. Key installed
artifacts are:

```text
bfd90e02106473094c2f54dc189217f5daaf32e4  bin/ocamlrun
2d65adb530a1dff611715be5b4196aa96821d11f  bin/ocamlc
72f4d2e83cbadfe29ae304c8eea931f7658d1854  bin/ocaml
2fc7e820802398bc470c2b05eb5eb40174528b47  bin/ocamlobjinfo
b052ca6b994d6d73c8dc36184b928fdfc4f0b6b9
  lib/ocaml/plan9/plan9.cma
1b35a2867b20104a3ae92310638c3a178cf05698
  lib/ocaml/plan9/plan9.cmi
```

`ocamlobjinfo` reported `Force custom: no`, with no extra C objects, C
options, or dynamically loaded libraries. The standard installed runtime
advertised exactly the seven expected `caml_plan9_*` primitives. The private
`Plan9_process` interface, test programs, and private frame header were not
installed.

The installed-consumer qualification privately hid `/usr/glenda/src`, then
compiled and ran in four seconds with the normal command shape:

```text
ocamlc -I +plan9 plan9.cma program.ml -o program
```

It passed live `Plan9.Env` and native `Plan9.Process.run` checks. Fail-closed
sentinels proved the consumer invoked no `c89`, `cc`, `gcc`, `clang`, `ld`,
`ar`, `ocamlmklib`, or `flexlink`; the sentinel log remained absent. The
temporary consumer output, work directory, and locks were absent at closeout.
Post-consumer inventories reproduced both the production and dev-002
installation byte-for-byte.

Important retained installation evidence includes:

```text
install log SHA-1:
  2c3804e4ba21f68f2c32d8e2671159c52fc57f35
install evidence-manifest SHA-1:
  34b5b61a864dd1d326689aa902da7b31d4d9df4e
installed key-artifact list SHA-1:
  cc9628095ad14e095f5acd93bb22adcf86d45a00
dev-002 layout SHA-1:
  afdf8b0b77053921291b0ee92ae11f0984bd65e0
dev-002 digest inventory SHA-1:
  e1a950b6e996f0b08513508ecf72cd67c048a509
production layout SHA-1:
  e871b8a897976a13aa8f4b8283acc61a48e349fe
production digest inventory SHA-1:
  06bacc059c59a928ae69df5bee1e084772b8b77e
```

### Accepted binary release candidate RC001

The user directed that the fully built exact-source tree remain intact. Do not
remove:

```text
/usr/glenda/src/ocaml-plan9-phase2-github-qualification-001
```

It is the retained incremental correction base. A later reviewed source-only
change can update that tree, let GNU Make rebuild only affected outputs, run
focused regression tests, reinstall into a separately understood candidate
prefix, and generate a successor binary candidate without repeating an
unnecessary clean world build.

RC001 packages only the normal dev-002 installed prefix, not the Git checkout
or build tree. Native `/bin/tar` created it from `/usr/glenda/lib/unix` in
eight seconds. The 338-file prefix inventory was byte-identical before and
after packaging. Windows independently parsed all 351 POSIX ustar entries and
found the single expected top-level directory with no absolute or parent
traversal path:

```text
Windows artifact root:
  C:\Users\dharm\vm\ocaml\artifacts\plan9-phase2-rc001
archive:
  ocaml-4.14.3-plan9-phase2-rc001-amd64-d8ec53e.tar
top-level directory:
  ocaml-4.14.3-plan9-dev-002/
required extraction parent:
  /usr/glenda/lib/unix
bytes:
  49020928
SHA-1:
  80a6f2652385ba056295ad29c1b6b27efc25200d
SHA-256:
  6b3772442eb0788d209e4b6046c55932e7352e6b4ae560fe354eaa748868bfab
manifest:
  C:\Users\dharm\vm\ocaml\artifacts\
    plan9-phase2-rc001\MANIFEST.txt
```

The Windows artifact root contains the archive, checksums, manifest,
guest-generated archive listings, package log/status, and before/after prefix
inventories. It also contains a byte-identical companion copy of
`otherlibs/plan9/REFERENCE.md` as `PLAN9-LIBRARY-REFERENCE.md`, with SHA-256
`9905eb36e4db0b6483a2304fe4bb2ca772304b8b8a20176b2b70ce854c976e07`.
No partial transfer file remains. The `.40` VM was intentionally left running;
packaging did not build, reinstall, edit source, halt, copy a VM, or access any
caml9 operational resource.

## Exact next gate

The next separately owned consumer action is caml9's independent RC001
installation and evaluation on a caml9-selected compatible amd64 Plan 9
development machine. The caml9 task receives the Windows artifact path only;
it does not receive `.40`, P9QEMU, port, source-tree, prefix, or checkpoint
ownership.

Operational ownership of `.40` remains solely with the OCaml task. If caml9
reports a required source change, first reconcile the requested behavior with
the accepted Plan 9 API and lifecycle contracts, then authorize a bounded
Windows-source correction, explicit changed-file transfer into the retained
exact-source tree, incremental Make rebuild, focused native regression tests,
isolated installation, and a newly identified binary candidate. Do not
silently mutate RC001.

Caml9, `.32`, protected checkpoints, production and Phase 1 prefix mutation,
custom-runtime repair, RFNOMNT, service behavior, CPU-017, and milestone
publication remain excluded.

## Recovery boundary

The `.40` mutable lab is currently running. Do not hash, copy, exclusively
open, or run `qemu-img` against its active disk. The last verified halted disk
identity before this launch was 1,641,086,976 bytes with SHA-256
`559fb5c400d10727ac38fed2cf5aecafbb701e309d18b881101a5b77ff4c59eb`.

The retained exact GitHub checkout is configured and fully built, including
the `ocamltest` prerequisite and broader-suite products. Its rejected
procedural attempts, accepted focused and interruption evidence, complete
upstream-suite evidence, install evidence, installed-consumer evidence, and
RC001 packaging evidence remain distinct beneath `/tmp`. Dev-002 is installed
and accepted. The package and Windows-copy locks are absent; the installed
consumer left no work directory, sentinel log, or test output.

The user's one-time `echo ipv6 >/net/cs` workaround remains a global property
of this running guest and will not survive reboot. Do not toggle it again
blindly and do not turn it into a boot policy without separate analysis.

By explicit user direction, retain both the exact-source build tree and the
dev-002 prefix. They provide the fast incremental correction lane and the
accepted installed candidate. The Windows RC001 archive provides an immutable
handoff and rollback identity for caml9 evaluation.

Later shutdown must use address-specific `.40` `fshalt`, wait for the recorded
process chain, close and rebind all seven listeners, and complete the halted
QCOW2 and pinned-WHPX postflight. Until that shutdown, do not hash, copy,
exclusively open, or inspect the active writable disk.

No OCaml-project checkpoint has been created. The accepted Phase 1 tree and
prefix, the Phase 2 incremental tree, the retained exact-source tree, dev-002,
and the mutable disk are development state, not protected recovery points.
