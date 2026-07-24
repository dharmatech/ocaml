# OCaml Plan 9 compiler-lab runbook

This is the Dharmatech-host operational reference for P9QEMU, Drawterm, source
transfer, native compiler builds, versioned installs, and recovery. It does not
broaden authorization. Read `current-state.md` and the repository design docs
before using it.

## Contents

- [Tools and roots](#tools-and-roots)
- [Authorization and ownership](#authorization-and-ownership)
- [Selecting or creating a lab](#selecting-or-creating-a-lab)
- [Process and listener preflight](#process-and-listener-preflight)
- [Starting with P9QEMU](#starting-with-p9qemu)
- [Connecting with Drawterm](#connecting-with-drawterm)
- [Transferring source](#transferring-source)
- [Building and installing](#building-and-installing)
- [Evidence and postflight](#evidence-and-postflight)
- [Halting the lab](#halting-the-lab)
- [Private checkpoints](#private-checkpoints)
- [Failure behavior](#failure-behavior)

## Tools and roots

```text
OCaml repository: C:\Users\dharm\src\ocaml
P9QEMU repository: C:\Users\dharm\src\p9qemu
installed P9QEMU: C:\Users\dharm\.local\bin\p9qemu.exe
proposed VM root: C:\Users\dharm\vm\ocaml
QEMU: C:\Program Files\qemu\qemu-system-x86_64.exe
qemu-img: C:\Program Files\qemu\qemu-img.exe
Drawterm: C:\Users\dharm\src\drawterm\build\msvc\drawterm.exe
Windows source in Drawterm: /mnt/term/C:/Users/dharm/src/ocaml
reported known-built tree: /usr/glenda/src/ocaml
```

Verify every path before first use. The VM root is only a proposal until
created in an explicitly authorized lab phase.

The published unattended Drawterm-ready source image is:

```text
https://github.com/dharmatech/p9qemu/releases/download/ready-9front-11554-amd64-hjfs-gmt-drawterm-001/image.json
```

Its public localhost demonstration credential is `p9qemu-demo`. Keep its
services bound to loopback. Never replace that fixture in tracked files with a
real credential.

## Authorization and ownership

Name every stateful phase before starting:

- selected instance and recovery source;
- unique loopback address;
- allowed guest and host mutations;
- native source tree;
- install prefix;
- build and test commands;
- expected evidence;
- whether the VM may remain running; and
- explicit exclusions.

One task owns all OCaml lab state. Do not inspect, boot, copy, hash, or
otherwise access caml9's `.32` or any other caml9 instance, port, disk, guest,
or checkpoint. Before allocating an address, coordinate with the current
stateful operator and revalidate live listeners.

Creating an instance, starting it, transferring source, installing a compiler,
halting it, deriving a checkpoint, committing, and pushing are distinct
authority boundaries unless the user has approved them together as one named
developmental compiler-lab phase.

## Selecting or creating a lab

A future lab may use a new writable instance created from the published
Drawterm image or a new writable copy of an explicitly selected, halted,
independently owned OCaml checkpoint. A host-only preflight may compare the
public image and a separately authorized future derivation as prospective
origins, but it does not operationally select, inspect, or mutate either. Do
not use the reported known-built tree as permission to reuse caml9's VM.

To inspect a public ready-image plan, use a destination that does not exist
whose parent directory already exists:

```powershell
p9qemu image create `
    'https://github.com/dharmatech/p9qemu/releases/download/ready-9front-11554-amd64-hjfs-gmt-drawterm-001/image.json' `
    'C:\Users\dharm\vm\ocaml\dev' `
    --dry-run
```

The currently proposed `C:\Users\dharm\vm\ocaml` parent has not been created.
`plan9-compiler-lab-preflight-001` must not create it, so the exact command
above is not eligible during that gate. Any `p9qemu image create --dry-run`
performed during preflight requires an explicitly approved nonexistent
destination beneath an already existing parent. The dry run fetches, verifies,
and may cache the small manifest. It does not download the large archive or
create the instance, but its bounded network and host-cache effects must be
recorded.

The real `image create` is a separately authorized state change. P9QEMU refuses
to replace an existing destination. A ready instance contains:

```text
dev/
  disk.qcow2
  instance.json
```

The writable overlay depends directly on an immutable content-addressed cache
base. Do not move, delete, or mutate that base.

## Process and listener preflight

P9QEMU forwards these seven host ports to the guest:

```text
17010 17019 17020 17021 17022 17564 17567
```

Reserve `127.0.0.1` for the user's ordinary/default lane. Choose another
canonical loopback address, record it in current-state, and require every one
of the seven endpoints to be free before launch.

Before starting:

1. revalidate Windows Git;
2. prove the selected writable image is not used by another QEMU process;
3. inspect the exact P9QEMU, Python, and QEMU command lines already running;
4. inspect the selected address's seven listeners;
5. validate `instance.json` and run `qemu-img check` only while halted;
6. run P9QEMU dry-run with the exact instance, address, accelerator, and
   serial-log policy; and
7. require a unique evidence directory and serial-log path that do not exist.

During `plan9-compiler-lab-preflight-001`, step 6 is allowed only if host-only
inspection discovers an already existing, genuinely independent OCaml
instance. The preflight does not create or copy an instance merely to make a
start dry run possible.

Never select or terminate a process merely by executable name. Record the
exact QEMU PID and full command line.

## Starting with P9QEMU

On this pinned Windows host, use explicit WHPX:

```powershell
p9qemu start `
    --instance 'C:\Users\dharm\vm\ocaml\dev' `
    --host-forward-address $labAddress `
    --serial-log $serialLog `
    --accel whpx
```

P9QEMU's WHPX profile is
`-accel whpx,kernel-irqchip=off -display sdl`. There is no silent TCG fallback.
Use `--accel tcg` only for a declared fallback or diagnostic comparison.

`--serial-log` retains the graphical display while recording raw COM1 into a
new file. P9QEMU refuses to overwrite or append to an existing log. Use
`--serial-console` instead when an interactive foreground COM1 session is
deliberately required.

After launch, record:

- P9QEMU shim and Python launcher PIDs and command lines;
- exact QEMU PID and command line;
- selected instance and address;
- serial-log path;
- QEMU ownership of all seven address-specific listeners; and
- whether the lab will remain running.

Do not hash or run `qemu-img check` against the active disk.

## Connecting with Drawterm

Use the same selected address for explicit CPU and auth endpoints:

```powershell
$env:PASS = 'p9qemu-demo'
& 'C:\Users\dharm\src\drawterm\build\msvc\drawterm.exe' `
    -h "tcp!$labAddress!17019" `
    -a "tcp!$labAddress!17567" `
    -u glenda -G -c 'echo OCAML_PLAN9_READY'
```

For an interactive graphical session, omit `-G -c ...`.

The CPU listener may accept before p9any authentication is ready. Retry only
the observed pre-authentication hangup with a small fixed bound. Do not turn a
general command failure into an unbounded retry.

Keep `-c` commands short; the published image qualification found that one long
command stopped before all markers. Prefer separately authenticated commands
or copy a guest-side driver script for a long sequence.

Drawterm's namespace is not automatically the boot process's namespace. Run
namespace-mutating probes under `rfork n` by default and identify the exact
process whose namespace is authoritative for a claim.

## Transferring source

From a Windows Drawterm session, the authoritative checkout appears at:

```text
/mnt/term/C:/Users/dharm/src/ocaml
```

Use `/mnt/term` only to transfer files or archives. Copy into a disposable
native directory, such as a uniquely named tree beneath `/usr/glenda/src` or
`/tmp`, and build there.

For the inner loop:

1. generate a reviewed manifest on Windows;
2. list every add, change, and delete with a repository-relative path, size,
   and digest;
3. reject `.git`, absolute paths, `..`, build output, and unlisted files;
4. copy additions and changes through `/mnt/term`;
5. apply deletions only inside the disposable destination;
6. verify destination size and the guest's validated digest command; and
7. record the manifest and result.

The installed guest is already known to provide `sha1sum`; verify the available
SHA-2 command before depending on its spelling. A milestone archive records
both SHA-1 and SHA-256 on Windows and verifies at least the recorded SHA-1
inside the guest.

Never transfer `.git`, build directly through `/mnt/term`, or overwrite
`/usr/glenda/src/ocaml` during an uncommitted iteration.

For a milestone, transfer a fresh exact-index archive rather than a changed-file
manifest. Record the Windows `HEAD`, index tree, archive hashes, gitlink
identities, native extraction path, and cleanup.

## Building and installing

The current port uses APE, GNU Make, and `c89`. In the disposable native source
tree:

```sh
ape/psh
PATH=$PWD/build-aux/plan9/shims/bin:/usr/glenda/lib/unix/bin:/bin:.
export PATH
MAKE=/usr/glenda/lib/unix/bin/gmake
export MAKE
build-aux/plan9/configure.sh --prefix=/usr/glenda/lib/unix/ocaml-4.14.3-plan9-dev-001
build-aux/plan9/build-world.sh
build-aux/plan9/install.sh
```

Treat every path above as a candidate until the read-only guest inventory
confirms it. Increment the development prefix for a new milestone. Never
install over `/usr/glenda/lib/unix/ocaml-4.14.3`.

On the compiler lab qualified for Phase 1, the resolved GNU Make command was
`/usr/glenda/lib/unix/make-4.4.1/bin/make`; the example
`/usr/glenda/lib/unix/bin/gmake` path was absent. Export the resolved command
as `MAKE` for every helper in a gate and record it in evidence.

Record configure inputs and resolved `MAKE`, `CC`, and prefix. After source-tree
tests, leave APE and run installed consumer checks from native `rc` using only
the new prefix.

For built-in `Plan9` packaging, require at least:

```text
ocamlrun -p
ocamlobjinfo "$(ocamlc -where)/plan9/plan9.cma"
ocamlc -I +plan9 plan9.cma smoke.ml -o smoke
smoke
```

Prove the normal link invokes no C tools and succeeds with them absent from
`PATH`. Keep custom-runtime regression testing separate.

## Evidence and postflight

Use a unique machine-local evidence directory beneath the selected OCaml VM
root. Raw serial logs may contain commands, guest data, or credentials and
remain untracked.

Retain:

- Git and exact-index identities;
- tool versions and paths;
- instance manifest and halted disk identities;
- P9QEMU dry-run output;
- exact process chain and listeners;
- serial log and hash;
- Drawterm commands, exit statuses, and output;
- transfer manifest and hashes;
- configure, build, test, and install logs;
- runtime, library, and prefix hashes;
- every failure and corrected retry; and
- shutdown, listener, QCOW2, and Git postflight.

A passing command alone does not prove the compiler milestone. Require all
postconditions declared for the phase.

## Halting the lab

Use address-specific Drawterm:

```powershell
$env:PASS = 'p9qemu-demo'
& 'C:\Users\dharm\src\drawterm\build\msvc\drawterm.exe' `
    -h "tcp!$labAddress!17019" `
    -a "tcp!$labAddress!17567" `
    -u glenda -G -c 'fshalt'
```

Then:

1. wait for the exact QEMU PID to exit;
2. prove the P9QEMU/Python/QEMU process chain is gone;
3. prove all seven selected listeners closed;
4. run `qemu-img check` on the halted overlay;
5. rerun the same P9QEMU dry run;
6. compare the instance manifest and any protected source identities; and
7. revalidate Windows Git.

TCP `TIME_WAIT` is not an active QEMU listener. Require the ports to stop
accepting connections and use strict bindability as a prelaunch condition.

## Private checkpoints

P9QEMU does not yet provide a checkpoint command. A private checkpoint is a
halted sibling copy of `disk.qcow2` and `instance.json` that continues to
depend on the same immutable cache base.

Checkpoint creation is separately authorized:

1. require successful guest `fshalt` and complete QEMU exit;
2. hash and validate the source instance while halted;
3. require a unique final name and unique staging directory;
4. copy only the instance contents into staging;
5. verify exact source/destination hashes, backing relationship,
   `qemu-img check`, and P9QEMU dry run;
6. rename staging atomically to the final checkpoint name; and
7. prove the source remained unchanged.

Never boot a protected checkpoint directly. Copy it to a new mutable instance
before resuming. Never copy a live QCOW2 or create a nested backing chain
through another writable overlay.

Checkpoint copies inherit all guest source, credentials, keys, and history.
Treat them as private.

## Failure behavior

Preserve all available evidence. If Drawterm readiness or `fshalt` fails,
report the exact QEMU PID and whether it remains alive. Attempt guest shutdown
only when Drawterm is reachable.

Never broad-kill QEMU, Python, or P9QEMU. Request explicit approval before
terminating only the exact recorded PID, then perform the complete halted-host
postflight.

Do not rewrite a rejected attempt as accepted after correcting a parser,
command, timeout, or environment. Record a new attempt.
