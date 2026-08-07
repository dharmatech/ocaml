---
name: ocaml-plan9-vm-workflow
description: Use when establishing, recreating, cloning, starting, stopping, checkpointing, restoring, or removing the OCaml project's Plan 9 P9QEMU lab, including its local-network baseline, mutable dev instance, scratch instances, loopback lease, serial log, and Drawterm lifecycle. Do not use for OCaml source transfer, native builds, tests, or installation in an already prepared guest; use ocaml-plan9-local instead.
---

# OCaml Plan 9 VM Workflow

Manage the OCaml project's private Plan 9 VM lineage as explicit, reviewable
host and guest operations. Keep `C:\Users\dharm\vm\ocaml` as the project VM
root and never operate another project's instance.

Use `$p9qemu-local` for current P9QEMU behavior and safety rules. Use
`$plan9-drawterm-windows` for Drawterm invocation and `/mnt/term` exchange.
Read current P9QEMU help, project status, the selected image page, and the
private-checkpoint guide before creating a new lineage. Do not use a remembered
manifest URL or endpoint map.

## Instance roles

- `checkpoint-local-network-baseline-001`: halted protected baseline containing
  only the selected Drawterm-ready image plus the local IPv4 DNS customization.
  Never boot it directly.
- `checkpoint-010-gnu-make-4.4.1-private`: halted protected baseline derived
  from the local-network baseline with the documented GNU Make 4.4.1 build
  installed. It is the preferred clean seed for compiler-development
  instances. Never boot it directly.
- `dev`: long-lived mutable development instance. Inspect its current identity
  and state before deciding whether its incremental native OCaml tree is useful.
- `scratch-<purpose>-NNN`: optional disposable instance copied from a halted
  checkpoint for one bounded experiment.
- `runs`: host logs and accepted private evidence. Give every real start a new
  serial-log path. Other exchange or artifact siblings are not VM instances;
  verify the expected P9QEMU metadata and disk before treating a directory as
  one.

For ordinary incremental work, inspect and reuse `dev` when its state suits the
task. For clean compiler-development work, copy the halted GNU Make checkpoint
to a new absent mutable sibling; do not overwrite `dev`. The checkpoint makes
no assumption that an OCaml checkout or build already exists. Final native
qualification still uses a fresh native source tree even when the surrounding
guest is reused.

Treat loopback addresses as per-start leases. Keep `127.0.0.1` available for
the ordinary P9QEMU lane. Select a currently unused canonical IPv4 loopback
address only after inspecting live processes and listeners.

## Preconditions for every VM mutation

1. Confirm the exact instance, loopback address, accelerator, and intended
   action with the user.
2. Resolve the installed commands with `Get-Command p9qemu` and
   `Get-Command drawterm`. Do not use development-checkout binaries.
3. Inspect P9QEMU, Python, and QEMU command lines and the selected address's
   listeners. Do not infer availability from an earlier task.
4. Require every destination to be absent. Never overwrite an instance,
   checkpoint, or serial log.
5. Use explicit `--accel whpx` on this host. Use TCG only when the user
   deliberately chooses it; never fall back silently.
6. Never copy, move, hash, inspect, checkpoint, or delete a live writable
   QCOW2. Never start two QEMU processes against one writable disk.

Useful read-only host inspection:

```powershell
Get-CimInstance Win32_Process |
    Where-Object { $_.Name -match 'p9qemu|python|qemu' } |
    Select-Object ProcessId, ParentProcessId, Name, CommandLine

Get-NetTCPConnection -State Listen |
    Where-Object LocalAddress -eq $address |
    Select-Object LocalAddress, LocalPort, OwningProcess
```

## Establish the protected local-network baseline

Perform these as separate operations. Stop for review at any unexpected result.

### 1. Select current inputs

From the current P9QEMU project status and Drawterm-ready image page, obtain the
immutable manifest URL, documented Drawterm CPU and auth host ports, and current
loopback-only development credential.

Set explicit variables after the preflight:

```powershell
$root = 'C:\Users\dharm\vm\ocaml'
$manifest = '<immutable manifest URL from the current image page>'
$candidate = Join-Path $root 'scratch-local-network-baseline-001'
$checkpoint = Join-Path $root 'checkpoint-local-network-baseline-001'
$address = '<currently unused non-default 127.x.y.z address>'
$cpuPort = '<CPU host port from the current image page>'
$authPort = '<auth host port from the current image page>'
```

Create `$root` only with user authorization:

```powershell
if(!(Test-Path -LiteralPath $root)) {
    New-Item -ItemType Directory -Path $root | Out-Null
}
if(Test-Path -LiteralPath $candidate) { throw "destination exists: $candidate" }
if(Test-Path -LiteralPath $checkpoint) { throw "destination exists: $checkpoint" }
```

### 2. Create the candidate

```powershell
p9qemu image create --dry-run $manifest $candidate
p9qemu image create $manifest $candidate
```

The dry run may perform the documented bounded manifest, network, and cache
checks. Review it before the real create. Do not continue if the destination
was partially created or its identity is unexpected.

### 3. Start the candidate

Create the host runs directory only after authorization, then choose a unique
new serial path:

```powershell
$runs = Join-Path $root 'runs'
if(!(Test-Path -LiteralPath $runs)) {
    New-Item -ItemType Directory -Path $runs | Out-Null
}
$serial = Join-Path $runs 'baseline-create-001-boot-001.serial.log'
if(Test-Path -LiteralPath $serial) { throw "serial log exists: $serial" }
p9qemu start --instance $candidate --host-forward-address $address `
    --accel whpx --serial-log $serial --dry-run
p9qemu start --instance $candidate --host-forward-address $address `
    --accel whpx --serial-log $serial
```

Run the real start in a dedicated host terminal; it remains attached until
QEMU exits. Record the exact P9QEMU/Python/QEMU process chain and the forwarded
listeners displayed by the launch. Do not silently switch accelerators.

### 4. Wait for Drawterm readiness

In a second host terminal, set `PASS` without putting the password on the
command line or in a log. Retry the short readiness command until it succeeds
or the bounded startup window expires:

```powershell
$env:PASS = '<current image password>'
$cpu = "tcp!$address!$cpuPort"
$auth = "tcp!$address!$authPort"
drawterm -h $cpu -a $auth -u glenda -G -c 'echo BASELINE_READY'
```

Do not substitute a fixed sleep for readiness and do not probe another address.

### 5. Install the local boot hook

The source asset is `assets/cpurc.local`, visible in the guest as:

```text
/mnt/term/C:/Users/dharm/src/ocaml/.agents/skills/ocaml-plan9-vm-workflow/assets/cpurc.local
```

First require `/rc/bin/cpurc.local` to be absent. Do not overwrite a different
site hook.

```powershell
$guestHook = '/mnt/term/C:/Users/dharm/src/ocaml/.agents/skills/ocaml-plan9-vm-workflow/assets/cpurc.local'
drawterm -h $cpu -a $auth -u glenda -G `
    -c "if(test -e /rc/bin/cpurc.local) exit existing; exit ''"
drawterm -h $cpu -a $auth -u glenda -G `
    -c "cp $guestHook /rc/bin/cpurc.local"
drawterm -h $cpu -a $auth -u glenda -G `
    -c 'chmod +x /rc/bin/cpurc.local'
drawterm -h $cpu -a $auth -u glenda -G `
    -c "cmp $guestHook /rc/bin/cpurc.local"
```

This hook starts `ndb/cs -4` only when neither `/srv/cs` nor `/net/cs`
already exists. It is a deterministic IPv4 DNS selection for this local
network, not the stateful `echo ipv6 >/net/cs` toggle.

### 6. Halt and verify host closeout

Use the image-qualified CPU-session shutdown recipe:

```powershell
drawterm -h $cpu -a $auth -u glenda -G `
    -c "bind -b '#S' /dev; 9fs 9fat /dev/sd00/9fat; fshalt"
```

Wait for the exact QEMU PID and its P9QEMU/Python parents to exit. Verify every
listener displayed by the corresponding dry run is closed on `$address`.
Never broad-kill by executable name.

### 7. Reboot and verify the persistent customization

Use a second unique serial-log path, repeat the exact dry run and real start,
and wait for Drawterm readiness:

```powershell
$serial = Join-Path $runs 'baseline-create-001-boot-002.serial.log'
if(Test-Path -LiteralPath $serial) { throw "serial log exists: $serial" }
p9qemu start --instance $candidate --host-forward-address $address `
    --accel whpx --serial-log $serial --dry-run
p9qemu start --instance $candidate --host-forward-address $address `
    --accel whpx --serial-log $serial
```

Then run these focused checks:

```powershell
drawterm -h $cpu -a $auth -u glenda -G `
    -c "cmp $guestHook /rc/bin/cpurc.local"
drawterm -h $cpu -a $auth -u glenda -G -c 'test -e /srv/cs'
drawterm -h $cpu -a $auth -u glenda -G `
    -c "ps -a | grep 'cs \[/net\]$'"
```

Require the exact hook, `/srv/cs`, and exactly one `cs [/net]` service. The
process listing cannot retain the original `-4` argument because `ndb/cs`
renames itself to the mount point. Halt and perform the same exact-process and
listener closeout again.

### 8. Publish the checkpoint and derive `dev`

Only after the candidate is halted and verified, rename it within the same VM
root and revalidate without launching:

```powershell
Move-Item -LiteralPath $candidate -Destination $checkpoint
p9qemu start --instance $checkpoint --host-forward-address $address `
    --accel whpx --dry-run
```

Never boot `$checkpoint` directly. Derive the ordinary mutable instance only
while the checkpoint is halted:

```powershell
$dev = Join-Path $root 'dev'
if(Test-Path -LiteralPath $dev) { throw "destination exists: $dev" }
Copy-Item -LiteralPath $checkpoint -Destination $dev -Recurse
p9qemu start --instance $dev --host-forward-address $address `
    --accel whpx --dry-run
```

The copies remain sibling overlays over P9QEMU's immutable cached base; they
are not QCOW2 internal snapshots and are not standalone backups.

## Operate the mutable development instance

For each start, repeat the live process/listener preflight, lease a free
address, and create a new serial-log path. Dry-run the exact command first:

```powershell
p9qemu start --instance $dev --host-forward-address $address `
    --accel whpx --serial-log $serial --dry-run
p9qemu start --instance $dev --host-forward-address $address `
    --accel whpx --serial-log $serial
```

Use Drawterm with the selected image's qualified CPU/auth endpoints. Halt
address-specifically, wait for the recorded QEMU PID to exit, and verify the
same listeners close before copying or inspecting the disk. Use
`$ocaml-plan9-local` once the guest is ready for OCaml development.

## Create a later checkpoint

Checkpoint only a valuable known-good milestone. Cleanly halt `dev`, wait for
complete QEMU exit, and verify its listeners are closed. Then copy it to a new,
semantic, numbered, absent destination and dry-run that copy:

```powershell
$newCheckpoint = Join-Path $root 'checkpoint-020-<milestone>-private'
if(Test-Path -LiteralPath $newCheckpoint) {
    throw "destination exists: $newCheckpoint"
}
Copy-Item -LiteralPath $dev -Destination $newCheckpoint -Recurse
p9qemu start --instance $newCheckpoint --host-forward-address $address `
    --accel whpx --dry-run
```

Treat checkpoints as private if their lineage has ever contained credentials
or private source. Never boot or publish them.

## Use a disposable scratch instance

Copy a halted checkpoint to a new `scratch-<purpose>-NNN` sibling, dry-run it,
and boot only the copy. Give it its own address when another guest is running.
After clean shutdown, delete it only when the user explicitly identifies that
exact disposable path and the resolved absolute path remains beneath
`C:\Users\dharm\vm\ocaml`. Never delete a cache base or infer deletion scope
from a wildcard.

## Fail closed

- On any identity, destination, accelerator, endpoint, readiness, guest-hook,
  process, or closeout discrepancy, stop before the next mutation.
- Do not publish or rename a failed candidate.
- If the owned candidate is reachable, halt it through its exact address,
  then wait for its recorded process chain and listeners to close.
- Preserve the failed candidate and its unique logs for review unless the user
  separately authorizes exact-path deletion.
- Never repair uncertainty by broad-killing QEMU, probing other addresses,
  booting a checkpoint, or improvising a disk copy.
