from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


MODULE_PATH = Path(__file__).resolve().parents[1] / "create_baseline.py"
SPEC = importlib.util.spec_from_file_location("create_baseline", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
create_baseline = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = create_baseline
SPEC.loader.exec_module(create_baseline)


class ConfigurationTests(unittest.TestCase):
    def configuration(self, root: Path, **overrides):
        values = {
            "manifest_url": "https://example.test/releases/image.json",
            "vm_root": root,
            "candidate_name": "scratch-baseline-001",
            "checkpoint_name": "checkpoint-010-network-private",
            "host_forward_address": "127.0.0.50",
            "cpu_port": 17019,
            "auth_port": 17567,
            "username": "glenda",
            "acceleration": "whpx",
            "expected_forward_count": 7,
            "boot_timeout": 300,
            "shutdown_timeout": 180,
            "command_timeout": 30,
            "image_timeout": 3600,
        }
        values.update(overrides)
        return create_baseline.Configuration(**values)

    def test_valid_configuration_is_rooted_in_existing_vm_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            configuration = create_baseline.validate_configuration(
                self.configuration(root)
            )
            self.assertEqual(configuration.candidate.parent, root.resolve())
            self.assertEqual(configuration.checkpoint.parent, root.resolve())

    def test_rejects_path_traversal_name(self):
        with tempfile.TemporaryDirectory() as temporary:
            configuration = self.configuration(
                Path(temporary), candidate_name="..\\outside"
            )
            with self.assertRaisesRegex(create_baseline.BaselineError, "simple"):
                create_baseline.validate_configuration(configuration)

    def test_rejects_existing_candidate(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "scratch-baseline-001").mkdir()
            with self.assertRaisesRegex(create_baseline.BaselineError, "replace"):
                create_baseline.validate_configuration(self.configuration(root))

    def test_rejects_default_loopback_lane(self):
        with tempfile.TemporaryDirectory() as temporary:
            configuration = self.configuration(
                Path(temporary), host_forward_address="127.0.0.1"
            )
            with self.assertRaisesRegex(create_baseline.BaselineError, "reserved"):
                create_baseline.validate_configuration(configuration)

    def test_rejects_noncanonical_loopback(self):
        with tempfile.TemporaryDirectory() as temporary:
            configuration = self.configuration(
                Path(temporary), host_forward_address="127.000.000.050"
            )
            with self.assertRaises(create_baseline.BaselineError):
                create_baseline.validate_configuration(configuration)

    def test_rejects_url_user_information(self):
        with tempfile.TemporaryDirectory() as temporary:
            configuration = self.configuration(
                Path(temporary), manifest_url="https://user@example.test/image.json"
            )
            with self.assertRaisesRegex(create_baseline.BaselineError, "user"):
                create_baseline.validate_configuration(configuration)


class CommandTests(unittest.TestCase):
    def setUp(self):
        self.configuration = create_baseline.Configuration(
            manifest_url="https://example.test/image.json?token=secret",
            vm_root=Path(r"C:\vm\ocaml"),
            candidate_name="scratch-001",
            checkpoint_name="checkpoint-010-private",
            host_forward_address="127.0.0.50",
            cpu_port=17019,
            auth_port=17567,
            username="glenda",
            acceleration="whpx",
            expected_forward_count=7,
            boot_timeout=300,
            shutdown_timeout=180,
            command_timeout=30,
            image_timeout=3600,
        )

    def test_start_command_is_explicit(self):
        command = create_baseline.start_command(
            self.configuration,
            self.configuration.candidate,
            serial_log=Path(r"C:\logs\serial.log"),
            dry_run=False,
        )
        self.assertEqual(command[0], "p9qemu")
        self.assertIn("--instance", command)
        self.assertIn("--host-forward-address", command)
        self.assertIn("127.0.0.50", command)
        self.assertIn("--accel", command)
        self.assertIn("whpx", command)
        self.assertNotIn("auto", command)

    def test_drawterm_command_uses_complete_endpoints(self):
        command = create_baseline.drawterm_command(self.configuration, "echo ready")
        self.assertEqual(command[0], "drawterm")
        self.assertIn("tcp!127.0.0.50!17019", command)
        self.assertIn("tcp!127.0.0.50!17567", command)
        self.assertNotIn("secret", " ".join(command))

    def test_rejects_long_drawterm_command(self):
        with self.assertRaisesRegex(create_baseline.BaselineError, "qualified limit"):
            create_baseline.drawterm_command(self.configuration, "x" * 128)

    def test_url_credentials_are_redacted_from_arguments(self):
        command = create_baseline.image_create_command(
            self.configuration, dry_run=True
        )
        rendered = " ".join(create_baseline.sanitize_arguments(command))
        self.assertIn("?<redacted>", rendered)
        self.assertNotIn("secret", rendered)

    def test_rc_quote_doubles_single_quotes(self):
        self.assertEqual(create_baseline.rc_quote("a'b"), "'a''b'")

    def test_windows_path_maps_to_drawterm_mount(self):
        mapped = create_baseline.windows_path_to_mnt_term(
            Path(r"C:\Users\example\file.rc")
        )
        self.assertEqual(mapped, "/mnt/term/C:/Users/example/file.rc")

    @patch.object(create_baseline.time, "sleep", return_value=None)
    def test_failure_readiness_retries_before_shutdown(self, _sleep):
        calls = []

        class FakeExecutor:
            def run(self, arguments, *, label, timeout, drawterm):
                calls.append((arguments, label, timeout, drawterm))
                if len(calls) == 1:
                    return subprocess.CompletedProcess(
                        arguments, 1, "drawterm: p9any authentication failed: hung up\n"
                    )
                return subprocess.CompletedProcess(
                    arguments, 0, "P9_LOCAL_FAILURE_READY_2\n"
                )

        create_baseline.wait_for_drawterm_marker(
            FakeExecutor(),
            self.configuration,
            marker="P9_LOCAL_FAILURE_READY_2",
            label_prefix="failure-boot-2-drawterm-ready",
        )
        self.assertEqual(
            [call[1] for call in calls],
            [
                "failure-boot-2-drawterm-ready-01",
                "failure-boot-2-drawterm-ready-02",
            ],
        )


class ProcessTests(unittest.TestCase):
    def test_process_scan_labels_are_unique_across_boots(self):
        first = create_baseline.process_scan_label(1, 1, 1)
        second = create_baseline.process_scan_label(2, 1, 1)
        self.assertEqual(first, "boot-1-process-scan-001-children-001")
        self.assertEqual(second, "boot-2-process-scan-001-children-001")
        self.assertNotEqual(first, second)

    def test_parses_one_process_object(self):
        output = (
            '{"ProcessId":42,"ParentProcessId":7,"Name":"qemu-system-x86_64.exe",'
            '"ExecutablePath":"C:\\\\qemu.exe","CommandLine":"qemu",'
            '"CreationDate":"20260801010101.000000-000"}'
        )
        processes = create_baseline.parse_process_document(output)
        self.assertEqual(len(processes), 1)
        self.assertEqual(processes[0].pid, 42)

    def test_parses_selected_forward_ports_without_hardcoding_map(self):
        command_line = (
            "qemu -net user,"
            "hostfwd=tcp:127.0.0.50:17019-:17019,"
            "hostfwd=tcp:127.0.0.50:17567-:567,"
            "hostfwd=tcp:127.0.0.51:18000-:80"
        )
        ports = create_baseline.parse_forward_ports(command_line, "127.0.0.50")
        self.assertEqual(ports, (17019, 17567))

    def test_powershell_query_rejects_arbitrary_field(self):
        with self.assertRaisesRegex(create_baseline.BaselineError, "unsupported"):
            create_baseline.powershell_process_query(
                "powershell.exe", "CommandLine", 42
            )


class InstanceMetadataTests(unittest.TestCase):
    def metadata(self, **runtime_overrides):
        runtime = {
            "profile": create_baseline.SUPPORTED_RUNTIME_PROFILE,
            "capabilities": sorted(create_baseline.REQUIRED_RUNTIME_CAPABILITIES),
        }
        runtime.update(runtime_overrides)
        return {
            "schema": 1,
            "kind": create_baseline.INSTANCE_KIND,
            "runtime": runtime,
        }

    def test_accepts_supported_runtime_profile(self):
        create_baseline.validate_instance_metadata(self.metadata())

    def test_rejects_another_runtime_profile(self):
        with self.assertRaisesRegex(create_baseline.BaselineError, "not qualified"):
            create_baseline.validate_instance_metadata(
                self.metadata(profile="some-future-profile")
            )

    def test_rejects_missing_drawterm_capability(self):
        capabilities = sorted(
            create_baseline.REQUIRED_RUNTIME_CAPABILITIES - {"drawterm"}
        )
        with self.assertRaisesRegex(create_baseline.BaselineError, "drawterm"):
            create_baseline.validate_instance_metadata(
                self.metadata(capabilities=capabilities)
            )


class GuestHookTests(unittest.TestCase):
    def test_hook_uses_deterministic_cs_option_not_toggle(self):
        hook = MODULE_PATH.parent / "guest" / "cpurc.local"
        content = hook.read_text(encoding="utf-8")
        self.assertIn("ndb/cs -4", content)
        self.assertNotIn("echo ipv6", content)
        self.assertTrue(content.endswith("\n"))

    def test_hook_normalization_converts_crlf_and_adds_final_newline(self):
        normalized = create_baseline.normalize_guest_hook(
            b"#!/bin/rc\r\nndb/cs -4"
        )
        self.assertEqual(normalized, b"#!/bin/rc\nndb/cs -4\n")

    def test_shutdown_uses_the_qualified_cpu_namespace_recipe(self):
        command = create_baseline.GUEST_SHUTDOWN_COMMAND
        self.assertIn("bind -b '#S' /dev", command)
        self.assertIn("9fs 9fat /dev/sd00/9fat", command)
        self.assertTrue(command.endswith("fshalt"))
        self.assertLess(len(command.encode("utf-8")), 128)

    def test_finds_cs_service_after_ndb_cs_rewrites_its_process_arguments(self):
        output = (
            "glenda 187 0:00 0:00 296K Pread cs [/net]\n"
            "glenda 239 0:00 0:00 440K Pread dns [/net]\n"
        )
        self.assertEqual(
            create_baseline.cs_service_lines(output),
            ("glenda 187 0:00 0:00 296K Pread cs [/net]",),
        )

    def test_does_not_treat_an_unrelated_cs_string_as_the_service(self):
        output = "glenda 10 0:00 0:00 100K Await rc [echo cs [/net]]\n"
        self.assertEqual(create_baseline.cs_service_lines(output), ())


class JournalTests(unittest.TestCase):
    def configuration(self, root: Path):
        return create_baseline.Configuration(
            manifest_url="https://example.test/image.json",
            vm_root=root,
            candidate_name="scratch-001",
            checkpoint_name="checkpoint-010-private",
            host_forward_address="127.0.0.50",
            cpu_port=17019,
            auth_port=17567,
            username="glenda",
            acceleration="whpx",
            expected_forward_count=7,
            boot_timeout=300,
            shutdown_timeout=180,
            command_timeout=30,
            image_timeout=3600,
        )

    def test_run_directory_is_unique_and_contained(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            first = create_baseline.create_run_dir(root)
            first.mkdir()
            second = create_baseline.create_run_dir(root)
            self.assertEqual(first.parent, root / "runs")
            self.assertEqual(second.parent, root / "runs")
            self.assertNotEqual(first, second)

    def test_journal_records_state_without_manifest_query_credentials(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            run_dir = create_baseline.create_run_dir(root)
            configuration = self.configuration(root)
            configuration = create_baseline.Configuration(
                **{
                    **create_baseline.asdict(configuration),
                    "manifest_url": "https://example.test/image.json?token=secret",
                }
            )
            journal = create_baseline.Journal(
                run_dir,
                configuration,
                {"p9qemu": "p9qemu.exe", "drawterm": "drawterm.exe"},
            )
            journal.transition("verified", checkpoint="checkpoint-010-private")
            state = json.loads(journal.state_path.read_text(encoding="utf-8"))
            events = journal.events_path.read_text(encoding="utf-8")
            self.assertEqual(state["state"], "verified")
            self.assertNotIn("secret", events)


if __name__ == "__main__":
    unittest.main()
