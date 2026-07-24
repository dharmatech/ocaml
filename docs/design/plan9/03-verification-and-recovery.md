# Verification and recovery

## Validation lanes

Use the smallest lane that proves the current claim.

### Host-only review

Use for source archaeology, API review, documentation, generated-file
consistency analysis, and offline tests. It authorizes no guest, Drawterm, VM,
transfer, build, install, or checkpoint action.

### Compiler-lab development

Use one mutable, isolated P9QEMU instance for fast changed-file transfer,
native builds, versioned-prefix installs, and focused runtime tests. The lab
may accumulate state and may remain running when recorded accurately.

Developmental success is not release acceptance and does not make the mutable
disk a recovery checkpoint.

### Exact-source milestone

Build a fresh exact-index archive in a fresh native tree. Install into a new
versioned prefix and run both source-tree and installed-prefix tests. Preserve
the prior compiler and recovery source.

### Release or recovery promotion

Use only when explicitly selected. Start from a clean writable instance
derived without booting a protected checkpoint, use the exact-source build,
perform comprehensive installed-compiler and runtime checks, shut down
cleanly, verify host and disk integrity, and create a new checkpoint only in a
separately authorized phase.

## Packaging acceptance

The built-in runtime packaging gate must prove:

- `ocamlobjinfo plan9.cma` reports no forced custom linking, C objects, or
  DLLs;
- standard Plan 9 `ocamlrun -p` lists each `caml_plan9_*` primitive exactly
  once;
- `ocamlc plan9.cma smoke.ml -o smoke` invokes no C compiler or linker;
- the link still succeeds with those tools absent from `PATH`;
- the executable runs under the matching standard runtime;
- ordinary bytecode not using `Plan9` remains unaffected;
- an older runtime fails clearly on a required unknown primitive; and
- non-Plan-9 builds neither compile nor advertise the primitives.

## Environment acceptance

Test absence, empty list, empty scalar, scalar, multiple values, embedded empty
elements, overwrite/truncation, removal, invalid names, and embedded-NUL
rejection. Cross-check both directions with native `rc` and prove that APE
`getenv` state is neither consulted nor updated.

## Process acceptance

Test literal arguments containing spaces, quotes, shell metacharacters,
redirection characters, and newlines. Test missing programs, permission
failures, exec-error handshakes, repeated failure under GC pressure,
environment and namespace policy, descriptor copying, note-group policy,
waitability, out-of-order children, exact status and timings, interruption,
cleanup, and leak-free failure.

Test the C boundary directly with forged or malformed OCaml values where
practical. Require unconditional `RFMEM` rejection.

## VM and recovery invariants

- One stateful operator owns the OCaml worktree, native tree, compiler VM,
  selected loopback address, install prefixes, and current-state.
- Every writable VM has one QEMU process and one unique explicit loopback
  address.
- Never boot a protected checkpoint directly or copy a live writable image.
- Before launch, validate the halted instance, QCOW2, P9QEMU dry run, selected
  endpoints, and evidence path.
- Record the exact process chain and listener owner after launch.
- Halt with `fshalt`, wait for the exact QEMU PID, require listener closure,
  then run the halted-instance checks again.
- If shutdown fails, preserve evidence and request separate approval before
  terminating only the exact recorded PID. Never kill by process name.

The machine-local skill supplies the concrete P9QEMU, Drawterm, transfer, and
checkpoint commands.

## Failure behavior

Do not overwrite failed evidence with a corrected retry. Do not infer success
from a prompt, a zero Drawterm exit, a disappeared QEMU process, or one passing
unit test. Record exactly which boundary passed and which remained untested.

Preserve the known compiler prefix and recovery source. A failed experimental
prefix or mutable lab can be abandoned without altering those boundaries.
