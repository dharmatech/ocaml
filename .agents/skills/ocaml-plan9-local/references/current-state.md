# OCaml Plan 9 local current state

Last recorded: 2026-07-23 20:19:01 -07:00 America/Los_Angeles

Origin profile: Dharmatech Windows/QEMU development host

Update this file after every accepted or rejected stateful gate and before
handing work to another task.

Treat this as a dated observation, not proof of live state:

- **Recorded** describes what was observed at the timestamp above.
- **Verified** describes checks completed in the named gate.
- **Required next** describes what must be revalidated before acting.

## Repository observation

The source boundary before publishing this record-only milestone was:

```text
repository: C:\Users\dharm\src\ocaml
branch: plan9-4.14.3-000
HEAD: 76d5a52310aab686e6229abfb39efdbcd66e8da8
tree: 995758f6c7cc87e630adb4818d6a701940f04280
tracking: origin/plan9-4.14.3-000 equals HEAD
remote: https://github.com/dharmatech/ocaml.git
worktree and index: clean
```

The publication commit containing this update necessarily follows that source
boundary. Read live Git before every task; live Git is authoritative.

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
instance state: halted after one clean inventory boot
assigned address: 127.0.0.40
forwarded endpoints: 17010, 17019, 17020, 17021, 17022, 17564, 17567
endpoint state: no listeners; all seven addresses bindable after shutdown
P9QEMU/QEMU PIDs: none; launch PIDs 22004 and 29936 both exited
native development tree: not created
first experimental prefix:
  candidate /usr/glenda/lib/unix/ocaml-4.14.3-plan9-dev-001;
  not created or reserved
known-working prefix:
  /usr/glenda/lib/unix/ocaml-4.14.3
raw evidence:
  C:\Users\dharm\vm\ocaml\evidence\
    plan9-compiler-lab-first-boot-inventory-001\attempt-002
serial log:
  C:\Users\dharm\vm\ocaml\evidence\
    plan9-compiler-lab-first-boot-inventory-001\attempt-002\serial.raw.log
serial bytes: 2104
serial SHA-256:
  889221dfad37c41968df05d1c70aed7ee4572820b6366a14ae0b2c7c4158ac2f
```

The candidate development prefix is a planning boundary only. It does not
exist by authority of this record and must not replace the known-working
compiler.

### Halted instance identities

```text
instance.json SHA-256, before and after:
  c87a3a9c2ef79d7640e03c689861cfea0cd73c54c72eea5f77b81cd6d8e46225
immutable base SHA-256:
  7ff689b7b614f6884bf0a1ac525fca10b750934d99640e744823f450d28ff6b8
cached manifest SHA-256:
  d04b06e49c5357cd95b8a8dd47457cd2e935b89d8e49117032b29206874aead2

preboot disk bytes: 638648320
preboot disk SHA-256:
  28f0203d2c2bd7c65ff2697ac3fbf38c0e4809ecdb87e635d3ed5cd5a0954a11
postboot disk bytes: 638648320
postboot disk SHA-256:
  df8e4715d47737887f79e0b738814610ff82cb4743511967c911d90dfeca53b6
```

The changed disk digest with unchanged allocated length is the expected
mutable first-boot transition. Halted `qemu-img info` retained the exact
immutable backing path, the dirty flag was false, and `qemu-img check` reported
no errors.

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

`gmake` was not found on the default APE `PATH`, and `/bin/make` rejected the
GNU `--version` option. The runbook's candidate
`/usr/glenda/lib/unix/bin/gmake` path was not queried before shutdown and must
be checked at the start of a build-authorized gate. `git/walk -f` could not
report source dirt because no `git/fs` was running; do not infer a clean native
tree from this inventory.

## Last completed gate

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

## Exact next gate

The recommended next separately authorized implementation gate is
`plan9-phase-1-built-in-env-implementation-001`.

It should begin from the live clean Windows repository and the halted instance
identity above, then:

1. implement only Phase 1 from `docs/design/plan9/04-implementation-plan.md` in
   the authoritative Windows checkout;
2. conditionally compile the first `caml_plan9_*` environment primitives into
   the standard Plan 9 `ocamlrun`;
3. add the Plan 9-only otherlib with an ML-only `plan9.cma` and the documented
   `Plan9.Env` scalar/list/empty/absent semantics backed directly by `/env`;
4. add focused source and testsuite coverage without changing `Sys` or `Unix`;
5. review and stage no files until the exact mutation set and host-side checks
   pass; and
6. stop for a distinct build authorization before booting the lab,
   transferring source, creating a native development tree, or installing
   under `/usr/glenda/lib/unix/ocaml-4.14.3-plan9-dev-001`.

Explicit exclusions are process creation, wait, public `Raw.rfork`, `RFMEM`,
custom-runtime repair, caml9 integration, source transfer, guest boot, build,
install, checkpoint creation, and any change to the known-working prefix.

## Recovery boundary

The halted mutable disk identity above is the current lab recovery observation,
not a protected checkpoint. No OCaml-project checkpoint has been created.

Before any future boot, revalidate live Git, this exact halted instance,
exclusive access to its disk, the `.40` endpoint set, the backing relationship,
and the current P9QEMU dry run. Never boot a protected checkpoint directly or
reuse caml9 recovery state.
