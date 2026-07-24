# OCaml Plan 9 local current state

Last recorded: 2026-07-24 11:44:52 -07:00 America/Los_Angeles

Origin profile: Dharmatech Windows/QEMU development host

Update this file after every accepted or rejected stateful gate and before
handing work to another task.

Treat this as a dated observation, not proof of live state:

- **Recorded** describes what was observed at the timestamp above.
- **Verified** describes checks completed in the named gate.
- **Required next** describes what must be revalidated before acting.

## Repository observation

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
instance state: halted after accepted Phase 1 completion
assigned address: 127.0.0.40
forwarded endpoints: 17010, 17019, 17020, 17021, 17022, 17564, 17567
endpoint state: no listeners; all seven addresses bindable after shutdown
P9QEMU/QEMU PIDs: none
last launch process chain: 27956, 31788, 32920, and 16208; all exited
accepted native development tree:
  /usr/glenda/src/ocaml-plan9-phase1-completion-001-build-004/
    ocaml-plan9-phase1-env-completion-001-build004
native tree state: exact tested archive, configured and fully built
first experimental prefix:
  /usr/glenda/lib/unix/ocaml-4.14.3-plan9-dev-001
prefix state: installed and accepted for this experiment
known-working prefix:
  /usr/glenda/lib/unix/ocaml-4.14.3
raw evidence:
  C:\Users\dharm\vm\ocaml\evidence\
    plan9-phase-1-env-completion-001\attempt-001
serial log:
  C:\Users\dharm\vm\ocaml\evidence\
    plan9-phase-1-env-completion-001\attempt-001\serial.raw.log
serial bytes: 2181
serial SHA-256:
  afea59a083466b48673f6c3209775ee2db08181c6815b80a62e0a6cf88525d3f
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

preboot disk bytes: 753795072
preboot disk SHA-256:
  73ec81d135de81cbc5f502faf07c917524bce2d934fbe8d4e002a3334aa4b1d0
postboot disk bytes: 1387921408
postboot disk SHA-256:
  71103c98e39e272a712af778abb90b430dd02e1dfec6335f9742d67154ef1e94
```

The changed digest and allocation length are the expected mutable build,
test, and isolated-prefix installation transition. Halted `qemu-img info`
retained the exact immutable backing path, the dirty flag and corrupt flag
were false, and `qemu-img check` reported no errors. A pinned-WHPX dry run
passed using a fresh placeholder serial path and did not create that path.
The first postflight dry run was retained as a harness rejection because
P9QEMU correctly refused to replace the real serial log.

The caml9 repository, running `.32` lab, processes, listeners, instances,
checkpoints, and active disks remained outside the gate and were not inspected
or changed. The OCaml task remains the sole stateful operator for the shared
P9QEMU/VM/port state, with operational scope limited to this independent OCaml
lab unless the user explicitly expands it.

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

The final guest-evidence archive is 1,572,864 bytes, SHA-256
`dc00acae84df339377d0e4920ac6fde38b595e5fe32d68767b2eb8af6851edd5`
and SHA-1 `b4119ad1e996ab9eaa257e7816cd9d520bb82576`. The raw evidence root is
the path recorded in the compiler-lab state above.

The gate did not change the production prefix, retained source checkout,
runtime or C source, `Sys`, `Unix`, process APIs, caml9 state, or any protected
checkpoint. It did not create a checkpoint or use TCG.

## Exact next gate

After publication, the recommended next separately authorized gate is
`plan9-phase-2-process-primitives-design-001`, a Windows-source and
documentation-only design gate.

It should freeze the exact FFI boundary for built-in Plan 9 runtime
primitives; the safe `Plan9.Process` API; native wait records and error
classification; the child exec-failure handshake; descriptor, environment,
namespace, and note-group policy; blocking-section behavior; and the public
boundary around `Plan9.Raw.rfork`.

The design must keep `RFMEM` impossible from public OCaml, minimize or
eliminate OCaml execution in the child, keep ordinary `plan9.cma` consumers
free of C tools and `-custom`, and preserve native `Waitmsg` status and timing
data. It must not implement or build the process primitives, boot the lab,
change either compiler prefix, repair general custom-runtime linking, or begin
caml9 integration without a later authorization.

## Recovery boundary

The halted mutable disk identity above is the current lab recovery observation,
not a protected checkpoint. No OCaml-project checkpoint has been created.

Before any future boot, revalidate live Git, this exact halted instance,
exclusive access to its disk, the `.40` endpoint set, the backing relationship,
and a P9QEMU dry run using a fresh nonexistent serial placeholder. Never boot
a protected checkpoint directly or reuse caml9 recovery state. The installed
experimental prefix is mutable lab state, not a protected recovery point.
