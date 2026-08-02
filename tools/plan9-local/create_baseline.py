# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Create and verify an experimental local P9QEMU baseline.

This is deliberately project-local prototype tooling.  It shells out to the
installed p9qemu and drawterm commands and never imports P9QEMU internals.
"""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
import hashlib
import ipaddress
import json
import os
from pathlib import Path, PureWindowsPath
import re
import shutil
import socket
import subprocess
import sys
import time
from typing import Any, Sequence, TextIO
from urllib.parse import urlsplit, urlunsplit
from uuid import uuid4


MAX_GUEST_COMMAND_BYTES = 127
INSTANCE_FILES = frozenset({"disk.qcow2", "instance.json"})
INSTANCE_KIND = "p9qemu-ready-image-instance"
SUPPORTED_RUNTIME_PROFILE = "9front-11554-amd64-hjfs-gmt-drawterm-v1"
REQUIRED_RUNTIME_CAPABILITIES = frozenset(
    {"unattended-boot", "serial-diagnostics", "drawterm", "loopback-services"}
)
GUEST_SHUTDOWN_COMMAND = "bind -b '#S' /dev; 9fs 9fat /dev/sd00/9fat; fshalt"
NAME_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$")
QEMU_NAME_PATTERN = re.compile(r"^qemu-system-.*(?:\.exe)?$", re.IGNORECASE)
HOST_FORWARD_PATTERN = re.compile(
    r"hostfwd=tcp:(?P<address>127(?:\.[0-9]{1,3}){3}):(?P<port>[0-9]+)-:"
)
CS_PROCESS_PATTERN = re.compile(r"\bcs \[/net\]$")
RETRYABLE_DRAWTERM_TEXT = ("p9any", "hung up")


class BaselineError(RuntimeError):
    """A fail-closed baseline creation error."""


@dataclass(frozen=True)
class Configuration:
    manifest_url: str
    vm_root: Path
    candidate_name: str
    checkpoint_name: str
    host_forward_address: str
    cpu_port: int
    auth_port: int
    username: str
    acceleration: str
    expected_forward_count: int
    boot_timeout: float
    shutdown_timeout: float
    command_timeout: float
    image_timeout: float

    @property
    def candidate(self) -> Path:
        return self.vm_root / self.candidate_name

    @property
    def checkpoint(self) -> Path:
        return self.vm_root / self.checkpoint_name

    @property
    def cpu_endpoint(self) -> str:
        return f"tcp!{self.host_forward_address}!{self.cpu_port}"

    @property
    def auth_endpoint(self) -> str:
        return f"tcp!{self.host_forward_address}!{self.auth_port}"


@dataclass(frozen=True)
class ProcessIdentity:
    pid: int
    parent_pid: int
    name: str
    executable_path: str | None
    command_line: str | None
    creation_date: str | None


@dataclass
class LiveVm:
    process: subprocess.Popen[bytes]
    output: TextIO
    start_log: Path
    serial_log: Path
    qemu: ProcessIdentity | None = None
    forward_ports: tuple[int, ...] = ()


def redact_url(value: str) -> str:
    parts = urlsplit(value)
    query = "<redacted>" if parts.query else ""
    return urlunsplit((parts.scheme, parts.netloc, parts.path, query, ""))


def sanitize_arguments(arguments: Sequence[str]) -> list[str]:
    return [
        redact_url(argument) if argument.startswith(("https://", "http://")) else argument
        for argument in arguments
    ]


def require_simple_name(value: str, label: str) -> str:
    if not NAME_PATTERN.fullmatch(value) or value in {".", ".."}:
        raise BaselineError(
            f"{label} must be one simple path component containing only "
            "letters, digits, dot, underscore, or hyphen"
        )
    return value


def canonical_loopback(value: str) -> str:
    try:
        address = ipaddress.IPv4Address(value)
    except ipaddress.AddressValueError as error:
        raise BaselineError("host-forward address must be an IPv4 literal") from error
    if str(address) != value or not address.is_loopback:
        raise BaselineError(
            "host-forward address must be a canonical IPv4 loopback literal"
        )
    if value == "127.0.0.1":
        raise BaselineError("127.0.0.1 is reserved for the ordinary P9QEMU lane")
    return value


def require_port(value: int, label: str) -> int:
    if not 1 <= value <= 65535:
        raise BaselineError(f"{label} must be between 1 and 65535")
    return value


def validate_configuration(configuration: Configuration) -> Configuration:
    requested_root = configuration.vm_root.expanduser().absolute()
    if requested_root.is_symlink():
        raise BaselineError(f"VM root must not be a symlink: {requested_root}")
    root = requested_root.resolve()
    if not root.is_dir() or root.is_symlink():
        raise BaselineError(f"VM root must be an existing real directory: {root}")
    if root.parent == root:
        raise BaselineError("refusing to use a filesystem root as the VM root")

    require_simple_name(configuration.candidate_name, "candidate name")
    require_simple_name(configuration.checkpoint_name, "checkpoint name")
    if configuration.candidate_name == configuration.checkpoint_name:
        raise BaselineError("candidate and checkpoint names must differ")

    candidate = root / configuration.candidate_name
    checkpoint = root / configuration.checkpoint_name
    if candidate.exists():
        raise BaselineError(f"refusing to replace candidate: {candidate}")
    if checkpoint.exists():
        raise BaselineError(f"refusing to replace checkpoint: {checkpoint}")

    canonical_loopback(configuration.host_forward_address)
    require_port(configuration.cpu_port, "CPU port")
    require_port(configuration.auth_port, "auth port")
    if configuration.cpu_port == configuration.auth_port:
        raise BaselineError("CPU and auth ports must differ")
    if not configuration.username or any(
        character.isspace() or ord(character) < 32
        for character in configuration.username
    ):
        raise BaselineError("username must be nonempty and contain no whitespace")
    if configuration.acceleration not in {"whpx", "tcg"}:
        raise BaselineError("acceleration must be explicitly whpx or tcg")
    if configuration.expected_forward_count < 2:
        raise BaselineError("expected forward count must be at least two")
    for label, value in (
        ("boot timeout", configuration.boot_timeout),
        ("shutdown timeout", configuration.shutdown_timeout),
        ("command timeout", configuration.command_timeout),
        ("image timeout", configuration.image_timeout),
    ):
        if value <= 0:
            raise BaselineError(f"{label} must be positive")

    parts = urlsplit(configuration.manifest_url)
    if parts.scheme != "https" or not parts.hostname or parts.username is not None:
        raise BaselineError(
            "manifest URL must be HTTPS, name a host, and contain no user information"
        )
    if parts.fragment:
        raise BaselineError("manifest URL must not contain a fragment")

    return Configuration(
        **{
            **asdict(configuration),
            "vm_root": root,
            "host_forward_address": canonical_loopback(
                configuration.host_forward_address
            ),
        }
    )


def resolve_required_commands() -> dict[str, str]:
    resolved: dict[str, str] = {}
    for command in ("p9qemu", "drawterm"):
        path = shutil.which(command)
        if path is None:
            raise BaselineError(f"required command is not installed on PATH: {command}")
        resolved[command] = str(Path(path).resolve())
    shell = shutil.which("powershell.exe") or shutil.which("pwsh.exe")
    if shell is None:
        raise BaselineError("PowerShell is required to inspect the owned process chain")
    resolved["powershell"] = str(Path(shell).resolve())
    return resolved


def rc_quote(value: str) -> str:
    if "\x00" in value or "\n" in value or "\r" in value:
        raise BaselineError("rc argument contains a forbidden control character")
    return "'" + value.replace("'", "''") + "'"


def windows_path_to_mnt_term(path: Path) -> str:
    windows = PureWindowsPath(str(path.resolve()))
    if not re.fullmatch(r"[A-Za-z]:", windows.drive):
        raise BaselineError(f"Drawterm transfer requires a drive-letter path: {path}")
    relative = "/".join(windows.parts[1:])
    return f"/mnt/term/{windows.drive}/{relative}"


def require_short_guest_command(command: str) -> str:
    if "\x00" in command or "\n" in command or "\r" in command:
        raise BaselineError("guest command must be one NUL-free line")
    length = len(command.encode("utf-8"))
    if length > MAX_GUEST_COMMAND_BYTES:
        raise BaselineError(
            f"guest command is {length} bytes; the qualified limit is "
            f"{MAX_GUEST_COMMAND_BYTES}"
        )
    return command


def image_create_command(configuration: Configuration, *, dry_run: bool) -> list[str]:
    command = [
        "p9qemu",
        "image",
        "create",
        configuration.manifest_url,
        str(configuration.candidate),
    ]
    if dry_run:
        command.append("--dry-run")
    return command


def start_command(
    configuration: Configuration,
    instance: Path,
    *,
    serial_log: Path | None,
    dry_run: bool,
) -> list[str]:
    command = [
        "p9qemu",
        "start",
        "--instance",
        str(instance),
        "--host-forward-address",
        configuration.host_forward_address,
        "--accel",
        configuration.acceleration,
    ]
    if serial_log is not None:
        command.extend(("--serial-log", str(serial_log)))
    if dry_run:
        command.append("--dry-run")
    return command


def drawterm_command(configuration: Configuration, guest_command: str) -> list[str]:
    require_short_guest_command(guest_command)
    return [
        "drawterm",
        "-h",
        configuration.cpu_endpoint,
        "-a",
        configuration.auth_endpoint,
        "-u",
        configuration.username,
        "-G",
        "-c",
        guest_command,
    ]


def parse_process_document(output: str) -> tuple[ProcessIdentity, ...]:
    text = output.strip()
    if not text:
        return ()
    try:
        document = json.loads(text)
    except json.JSONDecodeError as error:
        raise BaselineError(f"could not parse PowerShell process data: {error}") from error
    rows = document if isinstance(document, list) else [document]
    result: list[ProcessIdentity] = []
    for row in rows:
        if not isinstance(row, dict):
            raise BaselineError("PowerShell process data is not an object")
        try:
            result.append(
                ProcessIdentity(
                    pid=int(row["ProcessId"]),
                    parent_pid=int(row["ParentProcessId"]),
                    name=str(row["Name"]),
                    executable_path=(
                        str(row["ExecutablePath"])
                        if row.get("ExecutablePath") is not None
                        else None
                    ),
                    command_line=(
                        str(row["CommandLine"])
                        if row.get("CommandLine") is not None
                        else None
                    ),
                    creation_date=(
                        str(row["CreationDate"])
                        if row.get("CreationDate") is not None
                        else None
                    ),
                )
            )
        except (KeyError, TypeError, ValueError) as error:
            raise BaselineError("PowerShell process data is incomplete") from error
    return tuple(result)


def powershell_process_query(shell: str, field: str, pid: int) -> list[str]:
    if field not in {"ParentProcessId", "ProcessId"}:
        raise BaselineError(f"unsupported process query field: {field}")
    script = (
        "$ErrorActionPreference='Stop';"
        f"$items=@(Get-CimInstance Win32_Process -Filter \"{field} = {pid}\" | "
        "Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,"
        "CommandLine,CreationDate);"
        "ConvertTo-Json -Compress -InputObject $items"
    )
    return [shell, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", script]


def parse_forward_ports(command_line: str, address: str) -> tuple[int, ...]:
    matches = HOST_FORWARD_PATTERN.finditer(command_line)
    ports = {
        int(match.group("port"))
        for match in matches
        if match.group("address") == address
    }
    return tuple(sorted(ports))


def port_accepts(address: str, port: int, *, timeout: float = 0.4) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as connection:
        connection.settimeout(timeout)
        return connection.connect_ex((address, port)) == 0


def instance_inventory(instance: Path) -> dict[str, Any]:
    if not instance.is_dir() or instance.is_symlink():
        raise BaselineError(f"instance is not a real directory: {instance}")
    names = {entry.name for entry in instance.iterdir()}
    if names != INSTANCE_FILES:
        raise BaselineError(
            "instance contents differ from disk.qcow2 plus instance.json: "
            f"{sorted(names)}"
        )
    metadata_path = instance / "instance.json"
    try:
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise BaselineError(f"could not read instance metadata: {error}") from error
    if not isinstance(metadata, dict):
        raise BaselineError("instance metadata root is not an object")
    validate_instance_metadata(metadata)
    return metadata


def validate_instance_metadata(metadata: dict[str, Any]) -> None:
    if metadata.get("schema") != 1 or metadata.get("kind") != INSTANCE_KIND:
        raise BaselineError("unsupported P9QEMU instance metadata")
    runtime = metadata.get("runtime")
    if not isinstance(runtime, dict):
        raise BaselineError("instance metadata lacks a runtime object")
    if runtime.get("profile") != SUPPORTED_RUNTIME_PROFILE:
        raise BaselineError(
            "ready-image runtime profile is not qualified by this prototype: "
            f"{runtime.get('profile')!r}"
        )
    capabilities = runtime.get("capabilities")
    if not isinstance(capabilities, list) or not all(
        isinstance(capability, str) for capability in capabilities
    ):
        raise BaselineError("instance runtime capabilities are malformed")
    missing = REQUIRED_RUNTIME_CAPABILITIES - set(capabilities)
    if missing:
        raise BaselineError(
            f"ready image lacks required runtime capabilities: {sorted(missing)}"
        )


def normalize_guest_hook(content: bytes) -> bytes:
    if b"\x00" in content:
        raise BaselineError("guest startup hook contains NUL")
    try:
        text = content.decode("utf-8")
    except UnicodeDecodeError as error:
        raise BaselineError("guest startup hook is not UTF-8") from error
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    if "ndb/cs -4" not in normalized or "echo ipv6" in normalized:
        raise BaselineError("guest startup hook does not enforce the qualified cs policy")
    if not normalized.endswith("\n"):
        normalized += "\n"
    return normalized.encode("utf-8")


def cs_service_lines(process_output: str) -> tuple[str, ...]:
    return tuple(
        line
        for line in process_output.splitlines()
        if CS_PROCESS_PATTERN.search(line.rstrip())
    )


def stage_guest_hook(journal: Journal, source: Path) -> Path:
    try:
        content = normalize_guest_hook(source.read_bytes())
    except OSError as error:
        raise BaselineError(f"could not read guest customization source: {error}") from error
    destination = journal.run_dir / "cpurc.local"
    try:
        with destination.open("xb") as stream:
            stream.write(content)
    except OSError as error:
        raise BaselineError(f"could not stage guest customization: {error}") from error
    journal.record(
        "guest-hook-staged",
        source=str(source),
        staged=str(destination),
        sha256=hashlib.sha256(content).hexdigest(),
        bytes=len(content),
    )
    return destination


class Journal:
    def __init__(
        self,
        run_dir: Path,
        configuration: Configuration,
        commands: dict[str, str],
    ) -> None:
        self.run_dir = run_dir
        self.events_path = run_dir / "events.jsonl"
        self.state_path = run_dir / "state.json"
        self._state = "created"
        run_dir.mkdir()
        self.record(
            "run-created",
            configuration={
                **asdict(configuration),
                "manifest_url": redact_url(configuration.manifest_url),
                "vm_root": str(configuration.vm_root),
            },
            commands=commands,
        )

    def record(self, event: str, **fields: Any) -> None:
        entry = {
            "time_utc": datetime.now(UTC).isoformat(),
            "event": event,
            **fields,
        }
        with self.events_path.open("a", encoding="utf-8", newline="\n") as stream:
            stream.write(json.dumps(entry, sort_keys=True) + "\n")

    def transition(self, state: str, **fields: Any) -> None:
        self._state = state
        document = {
            "time_utc": datetime.now(UTC).isoformat(),
            "state": state,
            **fields,
        }
        temporary = self.state_path.with_suffix(".json.tmp")
        temporary.write_text(
            json.dumps(document, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
            newline="\n",
        )
        os.replace(temporary, self.state_path)
        self.record("state", **document)

    @property
    def state(self) -> str:
        return self._state


class Executor:
    def __init__(self, journal: Journal, password: str) -> None:
        self.journal = journal
        self.password = password

    def run(
        self,
        arguments: Sequence[str],
        *,
        label: str,
        timeout: float,
        drawterm: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        log_path = self.journal.run_dir / f"{label}.log"
        if log_path.exists():
            raise BaselineError(f"refusing to replace command log: {log_path}")
        environment = None
        if drawterm:
            environment = os.environ.copy()
            environment["PASS"] = self.password
        self.journal.record(
            "command-start",
            label=label,
            arguments=sanitize_arguments(arguments),
        )
        try:
            result = subprocess.run(
                list(arguments),
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=timeout,
                env=environment,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            self.journal.record("command-error", label=label, error=str(error))
            raise BaselineError(f"{label} could not complete: {error}") from error
        log_path.write_text(result.stdout, encoding="utf-8", newline="\n")
        self.journal.record(
            "command-end",
            label=label,
            returncode=result.returncode,
            log=str(log_path),
        )
        return result

    def require(
        self,
        arguments: Sequence[str],
        *,
        label: str,
        timeout: float,
        drawterm: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        result = self.run(
            arguments,
            label=label,
            timeout=timeout,
            drawterm=drawterm,
        )
        if result.returncode != 0:
            raise BaselineError(
                f"{label} exited with status {result.returncode}; "
                f"see {self.journal.run_dir / (label + '.log')}"
            )
        return result


def query_processes(
    executor: Executor,
    shell: str,
    field: str,
    pid: int,
    *,
    label: str,
) -> tuple[ProcessIdentity, ...]:
    result = executor.require(
        powershell_process_query(shell, field, pid),
        label=label,
        timeout=30,
    )
    return parse_process_document(result.stdout)


def process_scan_label(boot_number: int, scan: int, query_number: int) -> str:
    return (
        f"boot-{boot_number}-process-scan-{scan:03d}-"
        f"children-{query_number:03d}"
    )


def descendant_processes(
    executor: Executor,
    shell: str,
    root_pid: int,
    *,
    boot_number: int,
    scan: int,
) -> tuple[ProcessIdentity, ...]:
    pending = [root_pid]
    visited: set[int] = set()
    descendants: list[ProcessIdentity] = []
    query_number = 0
    while pending:
        parent = pending.pop(0)
        if parent in visited:
            continue
        visited.add(parent)
        query_number += 1
        children = query_processes(
            executor,
            shell,
            "ParentProcessId",
            parent,
            label=process_scan_label(boot_number, scan, query_number),
        )
        descendants.extend(children)
        pending.extend(child.pid for child in children)
        if len(descendants) > 32:
            raise BaselineError("owned process chain unexpectedly exceeds 32 descendants")
    return tuple(descendants)


def wait_for_qemu(
    executor: Executor,
    shell: str,
    live: LiveVm,
    configuration: Configuration,
    *,
    boot_number: int,
) -> ProcessIdentity:
    deadline = time.monotonic() + configuration.boot_timeout
    scan = 0
    while time.monotonic() < deadline:
        scan += 1
        if live.process.poll() is not None:
            raise BaselineError(
                f"p9qemu exited before QEMU was identified; see {live.start_log}"
            )
        descendants = descendant_processes(
            executor,
            shell,
            live.process.pid,
            boot_number=boot_number,
            scan=scan,
        )
        qemu = tuple(
            process for process in descendants if QEMU_NAME_PATTERN.fullmatch(process.name)
        )
        if len(qemu) > 1:
            raise BaselineError("owned process chain contains more than one QEMU process")
        if len(qemu) == 1:
            identity = qemu[0]
            command_line = identity.command_line or ""
            ports = parse_forward_ports(
                command_line, configuration.host_forward_address
            )
            if len(ports) != configuration.expected_forward_count:
                raise BaselineError(
                    "QEMU command line has an unexpected forward count: "
                    f"expected {configuration.expected_forward_count}, got {len(ports)}"
                )
            if not {configuration.cpu_port, configuration.auth_port}.issubset(ports):
                raise BaselineError("QEMU forward set omits the selected CPU or auth port")
            if configuration.acceleration == "whpx" and (
                "whpx,kernel-irqchip=off" not in command_line
            ):
                raise BaselineError("QEMU did not use the pinned WHPX compatibility profile")
            if configuration.acceleration == "tcg" and "-accel tcg" not in command_line:
                raise BaselineError("QEMU did not use the explicitly selected TCG profile")
            live.qemu = identity
            live.forward_ports = ports
            executor.journal.record(
                "process-chain",
                root_pid=live.process.pid,
                descendants=[asdict(process) for process in descendants],
                qemu_pid=identity.pid,
                forward_ports=list(ports),
            )
            return identity
        time.sleep(0.5)
    raise BaselineError("timed out waiting for the owned QEMU process")


def wait_for_ports(
    configuration: Configuration,
    ports: Sequence[int],
    *,
    accepting: bool,
    timeout: float,
) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        states = [
            port_accepts(configuration.host_forward_address, port) for port in ports
        ]
        if (all(states) if accepting else not any(states)):
            return
        time.sleep(0.5)
    condition = "accept connections" if accepting else "close"
    raise BaselineError(f"timed out waiting for selected forward ports to {condition}")


def wait_for_drawterm_marker(
    executor: Executor,
    configuration: Configuration,
    *,
    marker: str,
    label_prefix: str,
) -> None:
    deadline = time.monotonic() + configuration.boot_timeout
    attempt = 0
    while time.monotonic() < deadline:
        attempt += 1
        result = executor.run(
            drawterm_command(configuration, f"echo {marker}"),
            label=f"{label_prefix}-{attempt:02d}",
            timeout=configuration.command_timeout,
            drawterm=True,
        )
        if result.returncode == 0 and marker in result.stdout:
            return
        lowered = result.stdout.lower()
        if not all(fragment in lowered for fragment in RETRYABLE_DRAWTERM_TEXT):
            raise BaselineError(
                "Drawterm readiness failed with an unqualified error; "
                f"see {label_prefix}-{attempt:02d}.log"
            )
        time.sleep(1)
    raise BaselineError("timed out waiting for Drawterm readiness")


def wait_for_drawterm(
    executor: Executor,
    configuration: Configuration,
    *,
    boot_number: int,
) -> None:
    wait_for_drawterm_marker(
        executor,
        configuration,
        marker=f"P9_LOCAL_READY_{boot_number}",
        label_prefix=f"boot-{boot_number}-drawterm-ready",
    )


def launch_vm(
    executor: Executor,
    configuration: Configuration,
    *,
    boot_number: int,
) -> LiveVm:
    serial_log = executor.journal.run_dir / f"boot-{boot_number}.serial.log"
    start_log = executor.journal.run_dir / f"boot-{boot_number}.p9qemu.log"
    if serial_log.exists() or start_log.exists():
        raise BaselineError("refusing to replace an existing boot log")
    output = start_log.open("x", encoding="utf-8", newline="\n")
    arguments = start_command(
        configuration,
        configuration.candidate,
        serial_log=serial_log,
        dry_run=False,
    )
    executor.journal.record(
        "command-start",
        label=f"boot-{boot_number}-p9qemu",
        arguments=sanitize_arguments(arguments),
    )
    try:
        process = subprocess.Popen(
            arguments,
            stdout=output,
            stderr=subprocess.STDOUT,
        )
    except OSError as error:
        output.close()
        raise BaselineError(f"could not start p9qemu: {error}") from error
    live = LiveVm(
        process=process,
        output=output,
        start_log=start_log,
        serial_log=serial_log,
    )
    executor.journal.record(
        "p9qemu-started",
        boot=boot_number,
        pid=process.pid,
        start_log=str(start_log),
        serial_log=str(serial_log),
    )
    return live


def process_identity_is_alive(
    executor: Executor, shell: str, identity: ProcessIdentity, *, label: str
) -> bool:
    matches = query_processes(
        executor, shell, "ProcessId", identity.pid, label=label
    )
    return any(
        process.name == identity.name
        and process.creation_date == identity.creation_date
        for process in matches
    )


def wait_for_vm_exit(
    executor: Executor,
    shell: str,
    live: LiveVm,
    configuration: Configuration,
    *,
    boot_number: int,
) -> None:
    try:
        returncode = live.process.wait(timeout=configuration.shutdown_timeout)
    except subprocess.TimeoutExpired as error:
        raise BaselineError("timed out waiting for the owned p9qemu process") from error
    finally:
        live.output.close()
    executor.journal.record(
        "command-end",
        label=f"boot-{boot_number}-p9qemu",
        returncode=returncode,
        log=str(live.start_log),
    )
    if returncode != 0:
        raise BaselineError(f"p9qemu exited with status {returncode}")
    if live.qemu is None:
        raise BaselineError("QEMU process identity was not recorded")
    if process_identity_is_alive(
        executor,
        shell,
        live.qemu,
        label=f"boot-{boot_number}-qemu-postflight",
    ):
        raise BaselineError("the recorded QEMU process identity is still alive")
    wait_for_ports(
        configuration,
        live.forward_ports,
        accepting=False,
        timeout=configuration.shutdown_timeout,
    )


def halt_vm(
    executor: Executor,
    shell: str,
    live: LiveVm,
    configuration: Configuration,
    *,
    boot_number: int,
) -> None:
    result = executor.run(
        drawterm_command(configuration, GUEST_SHUTDOWN_COMMAND),
        label=f"boot-{boot_number}-fshalt",
        timeout=configuration.command_timeout,
        drawterm=True,
    )
    executor.journal.record(
        "fshalt-returned", boot=boot_number, returncode=result.returncode
    )
    wait_for_vm_exit(executor, shell, live, configuration, boot_number=boot_number)
    executor.require(
        start_command(
            configuration,
            configuration.candidate,
            serial_log=None,
            dry_run=True,
        ),
        label=f"boot-{boot_number}-halted-postflight",
        timeout=configuration.command_timeout,
    )


def install_guest_hook(
    executor: Executor, configuration: Configuration, hook: Path
) -> None:
    guest_source = windows_path_to_mnt_term(hook)
    destination = "/rc/bin/cpurc.local"
    exists = executor.run(
        drawterm_command(configuration, f"test -e {destination}"),
        label="guest-hook-exists",
        timeout=configuration.command_timeout,
        drawterm=True,
    )
    compare = f"cmp {destination} {rc_quote(guest_source)}"
    if exists.returncode == 0:
        same = executor.run(
            drawterm_command(configuration, compare),
            label="guest-hook-existing-compare",
            timeout=configuration.command_timeout,
            drawterm=True,
        )
        if same.returncode != 0:
            raise BaselineError(
                "guest already has an unrelated /rc/bin/cpurc.local; refusing to overwrite it"
            )
        return

    executor.require(
        drawterm_command(
            configuration,
            f"cp {rc_quote(guest_source)} {destination}",
        ),
        label="guest-hook-copy",
        timeout=configuration.command_timeout,
        drawterm=True,
    )
    executor.require(
        drawterm_command(configuration, f"chmod +x {destination}"),
        label="guest-hook-chmod",
        timeout=configuration.command_timeout,
        drawterm=True,
    )
    executor.require(
        drawterm_command(configuration, compare),
        label="guest-hook-compare",
        timeout=configuration.command_timeout,
        drawterm=True,
    )


def verify_guest_hook(
    executor: Executor, configuration: Configuration, hook: Path
) -> None:
    guest_source = windows_path_to_mnt_term(hook)
    executor.require(
        drawterm_command(
            configuration,
            f"cmp /rc/bin/cpurc.local {rc_quote(guest_source)}",
        ),
        label="verify-guest-hook",
        timeout=configuration.command_timeout,
        drawterm=True,
    )
    executor.require(
        drawterm_command(configuration, "test -e /srv/cs"),
        label="verify-cs-service",
        timeout=configuration.command_timeout,
        drawterm=True,
    )
    processes = executor.require(
        drawterm_command(configuration, "ps -a"),
        label="verify-processes",
        timeout=configuration.command_timeout,
        drawterm=True,
    )
    cs_lines = cs_service_lines(processes.stdout)
    if len(cs_lines) != 1:
        raise BaselineError(
            "expected exactly one running cs [/net] service after the startup hook"
        )
    executor.journal.record("guest-cs-verified", process_lines=list(cs_lines))


def validate_generated_guest_commands(
    configuration: Configuration, staged_hook: Path
) -> None:
    guest_source = windows_path_to_mnt_term(staged_hook)
    destination = "/rc/bin/cpurc.local"
    commands = (
        "echo P9_LOCAL_READY_1",
        f"test -e {destination}",
        f"cp {rc_quote(guest_source)} {destination}",
        f"chmod +x {destination}",
        f"cmp {destination} {rc_quote(guest_source)}",
        "test -e /srv/cs",
        "ps -a",
        GUEST_SHUTDOWN_COMMAND,
    )
    for command in commands:
        drawterm_command(configuration, command)


def create_run_dir(root: Path) -> Path:
    runs = root / "runs"
    if runs.exists() and (not runs.is_dir() or runs.is_symlink()):
        raise BaselineError(f"run-log parent is not a real directory: {runs}")
    runs.mkdir(exist_ok=True)
    if not runs.is_dir() or runs.is_symlink() or runs.resolve().parent != root:
        raise BaselineError(f"run-log parent escaped the selected VM root: {runs}")
    stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    run_dir = runs / f"{stamp}-{uuid4().hex[:8]}"
    if run_dir.exists():
        raise BaselineError(f"run-log destination already exists: {run_dir}")
    return run_dir


def print_plan(configuration: Configuration, commands: dict[str, str]) -> None:
    plan = {
        "mode": "plan-only; no P9QEMU, Drawterm, network, or VM action",
        "commands": commands,
        "manifest_url": redact_url(configuration.manifest_url),
        "candidate": str(configuration.candidate),
        "checkpoint": str(configuration.checkpoint),
        "host_forward_address": configuration.host_forward_address,
        "cpu_endpoint": configuration.cpu_endpoint,
        "auth_endpoint": configuration.auth_endpoint,
        "username": configuration.username,
        "acceleration": configuration.acceleration,
        "expected_forward_count": configuration.expected_forward_count,
        "persistent_guest_change": "/rc/bin/cpurc.local starts ndb/cs -4",
        "publication": "rename the verified halted candidate to the checkpoint",
    }
    print(json.dumps(plan, indent=2, sort_keys=True))


def execute(configuration: Configuration, commands: dict[str, str], hook: Path) -> Path:
    password = os.environ.get("PASS")
    if not password:
        raise BaselineError("create mode requires the current password in PASS")
    if not hook.is_file():
        raise BaselineError(f"guest customization source is missing: {hook}")

    run_dir = create_run_dir(configuration.vm_root)
    journal = Journal(run_dir, configuration, commands)
    executor = Executor(journal, password)
    shell = commands["powershell"]
    live: LiveVm | None = None
    boot_number = 0

    try:
        staged_hook = stage_guest_hook(journal, hook)
        validate_generated_guest_commands(configuration, staged_hook)
        executor.require(
            image_create_command(configuration, dry_run=True),
            label="image-create-preflight",
            timeout=configuration.image_timeout,
        )
        executor.require(
            image_create_command(configuration, dry_run=False),
            label="image-create",
            timeout=configuration.image_timeout,
        )
        metadata = instance_inventory(configuration.candidate)
        journal.transition("image-created", instance_metadata=metadata)

        for boot_number in (1, 2):
            executor.require(
                start_command(
                    configuration,
                    configuration.candidate,
                    serial_log=None,
                    dry_run=True,
                ),
                label=f"boot-{boot_number}-preflight",
                timeout=configuration.command_timeout,
            )
            live = launch_vm(
                executor, configuration, boot_number=boot_number
            )
            wait_for_qemu(
                executor,
                shell,
                live,
                configuration,
                boot_number=boot_number,
            )
            wait_for_ports(
                configuration,
                live.forward_ports,
                accepting=True,
                timeout=configuration.boot_timeout,
            )
            wait_for_drawterm(
                executor, configuration, boot_number=boot_number
            )
            journal.transition(f"boot-{boot_number}-ready")

            if boot_number == 1:
                install_guest_hook(executor, configuration, staged_hook)
                journal.transition("customized")
            else:
                verify_guest_hook(executor, configuration, staged_hook)
                journal.transition("verified")

            halt_vm(
                executor,
                shell,
                live,
                configuration,
                boot_number=boot_number,
            )
            live = None
            journal.transition(f"boot-{boot_number}-halted")

        instance_inventory(configuration.candidate)
        configuration.candidate.rename(configuration.checkpoint)
        journal.transition("published", checkpoint=str(configuration.checkpoint))
        executor.require(
            start_command(
                configuration,
                configuration.checkpoint,
                serial_log=None,
                dry_run=True,
            ),
            label="checkpoint-postflight",
            timeout=configuration.command_timeout,
        )
        journal.transition("complete", checkpoint=str(configuration.checkpoint))
        return run_dir
    except BaseException as error:
        if live is not None and live.process.poll() is None:
            journal.record(
                "failure-shutdown-attempt",
                boot=boot_number,
                p9qemu_pid=live.process.pid,
                qemu_pid=live.qemu.pid if live.qemu is not None else None,
            )
            try:
                wait_for_drawterm_marker(
                    executor,
                    configuration,
                    marker=f"P9_LOCAL_FAILURE_READY_{boot_number}",
                    label_prefix=f"failure-boot-{boot_number}-drawterm-ready",
                )
                executor.run(
                    drawterm_command(configuration, GUEST_SHUTDOWN_COMMAND),
                    label="failure-fshalt",
                    timeout=configuration.command_timeout,
                    drawterm=True,
                )
                live.process.wait(timeout=configuration.shutdown_timeout)
                live.output.close()
            except BaseException as shutdown_error:
                journal.record(
                    "failure-shutdown-incomplete", error=str(shutdown_error)
                )
        journal.transition(
            "failed",
            failed_from=journal.state,
            error=f"{type(error).__name__}: {error}",
            candidate_exists=configuration.candidate.exists(),
            checkpoint_exists=configuration.checkpoint.exists(),
        )
        raise


def positive_number(value: str) -> float:
    try:
        number = float(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be a positive number") from error
    if number <= 0:
        raise argparse.ArgumentTypeError("must be a positive number")
    return number


def port_number(value: str) -> int:
    try:
        number = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be a TCP port number") from error
    try:
        return require_port(number, "port")
    except BaselineError as error:
        raise argparse.ArgumentTypeError(str(error)) from error


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Plan and create an experimental local P9QEMU baseline."
    )
    commands = parser.add_subparsers(dest="mode", required=True)
    for name in ("plan", "create"):
        command = commands.add_parser(name)
        command.add_argument("--manifest-url", required=True)
        command.add_argument("--vm-root", required=True, type=Path)
        command.add_argument("--candidate-name", required=True)
        command.add_argument("--checkpoint-name", required=True)
        command.add_argument("--host-forward-address", required=True)
        command.add_argument("--cpu-port", required=True, type=port_number)
        command.add_argument("--auth-port", required=True, type=port_number)
        command.add_argument("--username", required=True)
        command.add_argument("--accel", required=True, choices=("whpx", "tcg"))
        command.add_argument("--expected-forward-count", type=int, default=7)
        command.add_argument("--boot-timeout", type=positive_number, default=300)
        command.add_argument(
            "--shutdown-timeout", type=positive_number, default=180
        )
        command.add_argument("--command-timeout", type=positive_number, default=30)
        command.add_argument("--image-timeout", type=positive_number, default=3600)
    return parser


def configuration_from_args(args: argparse.Namespace) -> Configuration:
    return validate_configuration(
        Configuration(
            manifest_url=args.manifest_url,
            vm_root=args.vm_root,
            candidate_name=args.candidate_name,
            checkpoint_name=args.checkpoint_name,
            host_forward_address=args.host_forward_address,
            cpu_port=args.cpu_port,
            auth_port=args.auth_port,
            username=args.username,
            acceleration=args.accel,
            expected_forward_count=args.expected_forward_count,
            boot_timeout=args.boot_timeout,
            shutdown_timeout=args.shutdown_timeout,
            command_timeout=args.command_timeout,
            image_timeout=args.image_timeout,
        )
    )


def run(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        configuration = configuration_from_args(args)
        commands = resolve_required_commands()
        if args.mode == "plan":
            print_plan(configuration, commands)
            return 0
        hook = Path(__file__).resolve().parent / "guest" / "cpurc.local"
        run_dir = execute(configuration, commands, hook)
        print(f"Verified private baseline: {configuration.checkpoint}")
        print(f"Run logs: {run_dir}")
        return 0
    except BaselineError as error:
        print(f"create_baseline.py: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("create_baseline.py: interrupted", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(run())
