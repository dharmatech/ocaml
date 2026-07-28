---
name: ocaml-plan9-local
description: Use when operating the OCaml Plan 9 P9QEMU VM from Dharmatech's Windows host, including starting or stopping an instance, selecting its loopback address, connecting through the P9QEMU Drawterm ports, or transferring OCaml files through /mnt/term.
---

# OCaml Plan 9 local VM access

Use this skill only for the host-specific P9QEMU and Windows Drawterm details
needed by the OCaml port.

## Local paths

- Installed P9QEMU: `C:\Users\dharm\.local\bin\p9qemu.exe`
- P9QEMU documentation: `C:\Users\dharm\src\p9qemu\README.md`
- Drawterm: `C:\Users\dharm\src\drawterm\build\msvc\drawterm.exe`
- OCaml VM root: `C:\Users\dharm\vm\ocaml`
- OCaml checkout through Drawterm:
  `/mnt/term/C:/Users/dharm/src/ocaml`

Consult the P9QEMU README for image creation and uncommon options.

## Start an instance

Choose the instance and canonical `127.0.0.0/8` address with the user. P9QEMU
forwards these seven TCP ports on that address:

`17010`, `17019`, `17020`, `17021`, `17022`, `17564`, and `17567`.

Confirm that the instance is not already running and that all seven ports are
free. Then dry-run the exact start:

```powershell
& 'C:\Users\dharm\.local\bin\p9qemu.exe' start `
    --instance 'C:\Users\dharm\vm\ocaml\dev' `
    --host-forward-address 127.0.0.40 `
    --accel whpx `
    --dry-run
```

Remove `--dry-run` to start. Explicit `--accel whpx` has no automatic TCG
fallback; use `--accel tcg` only when the user chooses software emulation.

## Connect with Windows Drawterm

Use the P9QEMU CPU and auth ports on the selected address:

```powershell
$labAddress = '127.0.0.40'
$command = 'pwd'
$env:PASS = '<password supplied by the user>'
& 'C:\Users\dharm\src\drawterm\build\msvc\drawterm.exe' `
    -h "tcp!$labAddress!17019" `
    -a "tcp!$labAddress!17567" `
    -u glenda -G -c $command
```

Set `$command` to the desired short rc command. Omit `-G -c $command` for an
interactive graphical session.

Use `/mnt/term/C:/Users/dharm/src/ocaml` to copy Windows OCaml files into native
Plan 9 storage before compiling.

## Stop the VM

Use the same Drawterm template with `$command = 'fshalt'`. Wait for the
P9QEMU/QEMU process to exit and verify that all seven ports on the selected
address are closed.
