# Experimental local Plan 9 baseline creator

This directory contains a project-local prototype for creating a private
P9QEMU baseline with Dharmatech's local network customization. It is not part
of OCaml, is not installed with OCaml, and is expected to move or be redesigned
after practical use exposes the right reusable boundary.

The tool invokes the installed `p9qemu` and `drawterm` commands. It does not
import P9QEMU internals, manage arbitrary VMs, install development tools, or
build OCaml.

## Persistent guest change

The prototype installs [`guest/cpurc.local`](guest/cpurc.local) as
`/rc/bin/cpurc.local`. That hook starts `ndb/cs -4` before the stock `cpurc`
would start the connection server. This selects IPv4-only DNS lookup behavior
deterministically instead of writing the state-dependent `ipv6` toggle to
`/net/cs`.

This ordering and option were checked against the 9front 11554 source tree at
commit `2191d72205863d2c53ea6ac36991cb4c13204c7c`, specifically `rc/bin/cpurc`
and `sys/src/cmd/ndb/cs.c`. On the verification boot, the prototype requires
the exact installed hook, `/srv/cs`, and exactly one `cs [/net]` service.
`ndb/cs` replaces its informational process arguments with the mount point via
`procsetname`, so `ps -a` cannot retain or prove the original `-4` argument.

The tool refuses to overwrite an existing, different `/rc/bin/cpurc.local`.
The first baseline contains no GNU Make or OCaml installation, source tree,
private credential, or project package.

## Modes

`plan` validates local inputs and prints the intended operation. It does not
invoke P9QEMU or Drawterm, access the network, create a directory, or operate a
VM.

`create` performs the complete experiment:

1. verify the selected ready-image manifest with P9QEMU's dry run;
2. create a new writable candidate instance;
3. dry-run and start it with an explicit address and accelerator;
4. require the qualified 9front 11554 Drawterm runtime profile, identify the
   owned P9QEMU/QEMU process chain, and derive its forward set;
5. connect with Drawterm, install the startup hook, and halt cleanly;
6. boot again, verify the exact hook and running `ndb/cs -4`, and halt;
7. halt through the image-qualified CPU-session namespace recipe and require
   halted P9QEMU postflight after each boot; and
8. rename the verified halted candidate to the protected checkpoint name and
   perform one final non-launching P9QEMU verification.

The rename is limited to sibling directories beneath one existing VM root.
It relies on P9QEMU's documented direct-to-cache ready-image layout. Never
boot the resulting checkpoint directly; copy it to a distinct writable
instance before further use.

Every run writes a unique event journal, command logs, and serial logs beneath
`VM_ROOT/runs`. Passwords are taken only from `PASS` and are not written to
arguments or logs. A failure preserves the candidate and run logs. The tool
waits boundedly for a just-launched Drawterm service before attempting its
address-specific clean shutdown. It never deletes an instance, broadly kills
QEMU, or silently falls back to a different accelerator. Retain the logs
locally: serial diagnostics can contain environment-specific guest information
even though the password is never sent through the serial channel.

## Inputs

Read the current P9QEMU project status and selected ready-image page before a
run. Supply their immutable manifest URL and documented Drawterm CPU and auth
ports explicitly; this prototype deliberately does not embed a moving image
selection or P9QEMU's complete port map.

Use a new candidate name, a new checkpoint name, and an address selected from
live host state. Keep `127.0.0.1` for the ordinary P9QEMU lane.

Example planning shape, with placeholders replaced from current P9QEMU
documentation:

```powershell
uv run tools/plan9-local/create_baseline.py plan `
    --manifest-url '<immutable-https-manifest-url>' `
    --vm-root 'C:\Users\dharm\vm\ocaml' `
    --candidate-name 'scratch-local-network-baseline-001' `
    --checkpoint-name 'checkpoint-010-local-network-private' `
    --host-forward-address '<unused-127.x.y.z-address>' `
    --cpu-port '<documented-cpu-port>' `
    --auth-port '<documented-auth-port>' `
    --username 'glenda' `
    --accel whpx
```

After reviewing that plan, replace `plan` with `create` and set `PASS` in the
current environment. Do not put the password on the command line.

## Host-only tests

The tests use only Python's standard library and do not invoke P9QEMU,
Drawterm, QEMU, WSL, or a guest:

```powershell
uv run python -m unittest discover -s tools/plan9-local/tests -v
```

Test a real run only against a newly agreed scratch destination and loopback
address. Do not use an existing project's mutable development instance.
