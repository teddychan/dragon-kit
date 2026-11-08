#!/usr/bin/env python3
"""Execute the documented Debug starter with synthetic app identities on macOS."""

import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import uuid


ROOT = Path(__file__).resolve().parent.parent


def starter_script():
    guide = (ROOT / "docs/STARTING-A-NEW-APP.md").read_text()
    section = guide.split("### `scripts/run.sh`", 1)[1]
    return section.split("```bash\n", 1)[1].split("\n```", 1)[0]


@unittest.skipUnless(sys.platform == "darwin", "The starter targets macOS and AppKit")
class DebugStarterTests(unittest.TestCase):
    def test_replaces_other_worktree_debug_without_touching_release(self):
        with tempfile.TemporaryDirectory(prefix="dragon-starter-") as temporary:
            root = Path(temporary)
            name = "DragonStarterFixture" + uuid.uuid4().hex
            bundle_id = "org.dragonkit.fixture." + uuid.uuid4().hex
            debug_name = name + " Debug"
            installed = Path("/Applications") / (debug_name + ".app")
            self.assertFalse(installed.exists())
            binary = root / "FixtureTarget"
            source = root / "Fixture.swift"
            source.write_text(
                "import AppKit\n"
                "let app = NSApplication.shared\n"
                "app.setActivationPolicy(.prohibited)\n"
                "app.run()\n"
            )
            subprocess.run(["swiftc", str(source), "-o", str(binary)], check=True)
            processes = []
            try:
                for label, identifier, display in [
                    ("other-worktree", bundle_id + ".debug", debug_name),
                    ("release", bundle_id, name),
                ]:
                    bundle = root / label / (display + ".app")
                    executable = bundle / "Contents/MacOS" / display
                    executable.parent.mkdir(parents=True)
                    shutil.copy2(binary, executable)
                    with (bundle / "Contents/Info.plist").open("wb") as handle:
                        plistlib.dump({
                            "CFBundleIdentifier": identifier,
                            "CFBundleName": display,
                            "CFBundleExecutable": display,
                            "CFBundlePackageType": "APPL",
                        }, handle)
                    processes.append(subprocess.Popen(
                        [str(executable)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                    ))

                probe = (
                    "import AppKit\n"
                    "print(NSRunningApplication.runningApplications("
                    "withBundleIdentifier: CommandLine.arguments[1]).count)\n"
                )
                for identifier in [bundle_id + ".debug", bundle_id]:
                    deadline = time.monotonic() + 5
                    while True:
                        registered = subprocess.run(
                            ["swift", "-", identifier], input=probe,
                            capture_output=True, text=True, check=True,
                        )
                        if registered.stdout.strip() == "1" or time.monotonic() >= deadline:
                            break
                        time.sleep(0.05)
                    self.assertEqual(registered.stdout.strip(), "1")

                checkout = root / "current-worktree"
                scripts = checkout / "scripts"
                scripts.mkdir(parents=True)
                app_inputs = checkout / "App"
                app_inputs.mkdir()
                original = {
                    "CFBundleIdentifier": bundle_id,
                    "CFBundleName": name,
                    "CFBundleExecutable": "FixtureTarget",
                    "CFBundleShortVersionString": "1.2.3",
                    "CFBundlePackageType": "APPL",
                    "SUFeedURL": "https://example.invalid/production.xml",
                }
                with (app_inputs / "Info.plist").open("wb") as handle:
                    plistlib.dump(original, handle)
                products = checkout / ".build/debug"
                products.mkdir(parents=True)
                shutil.copy2(binary, products / "FixtureTarget")
                script = starter_script().replace("<APP_DISPLAY>", name).replace(
                    "<BUNDLE_ID>", bundle_id
                ).replace("<TARGET>", "FixtureTarget")
                run_script = scripts / "run.sh"
                run_script.write_text(script)
                run_script.chmod(0o755)
                commands = root / "commands"
                commands.mkdir()
                real_swift = shutil.which("swift")
                doubles = {
                    "swift": (
                        "import os,sys\n"
                        "if sys.argv[1:2] == ['build']:\n"
                        "    if '--show-bin-path' in sys.argv: print(os.environ['FIXTURE_PRODUCTS'])\n"
                        "else: os.execv(os.environ['FIXTURE_SWIFT'], ['swift'] + sys.argv[1:])\n"
                    ),
                    "git": "import sys\nprint('42' if sys.argv[1] == 'rev-list' else '2026-11-08T00:00:00Z')\n",
                    "open": (
                        "import json,os,sys\n"
                        "from pathlib import Path\n"
                        "assert Path(sys.argv[-1]).is_dir()\n"
                        "Path(os.environ['FIXTURE_OPEN_LOG']).write_text(json.dumps(sys.argv[1:]))\n"
                    ),
                }
                for command, body in doubles.items():
                    path = commands / command
                    path.write_text("#!" + sys.executable + "\n" + body)
                    path.chmod(0o755)
                environment = dict(os.environ, PATH=str(commands) + os.pathsep + os.environ["PATH"],
                                   FIXTURE_PRODUCTS=str(products), FIXTURE_SWIFT=real_swift,
                                   FIXTURE_OPEN_LOG=str(root / "open.json"))
                result = subprocess.run([str(run_script)], cwd=checkout, env=environment,
                                        capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIsNotNone(processes[0].poll(), "Other-worktree Debug copy is still running")
                self.assertIsNone(processes[1].poll(), "Release copy was stopped")
                self.assertTrue(installed.is_dir(), "Debug copy was not installed canonically")
                self.assertFalse((products / (debug_name + ".app")).exists(),
                                 "A duplicate Debug bundle remains in the build directory")
                self.assertEqual(json.loads((root / "open.json").read_text()), ["-n", str(installed)])
                self.assertIn("path: " + str(installed), result.stdout)
                with (installed / "Contents/Info.plist").open("rb") as handle:
                    built = plistlib.load(handle)
                self.assertEqual(built["CFBundleIdentifier"], bundle_id + ".debug")
                self.assertEqual(built["CFBundleName"], debug_name)
                self.assertEqual(built["CFBundleExecutable"], debug_name)
                self.assertEqual(built["CFBundleShortVersionString"], "1.2.3")
                self.assertEqual(built["DragonBuildChannel"], "Debug")
                self.assertEqual(built["CFBundleVersion"], "42")
                self.assertNotIn("SUFeedURL", built)
                with (app_inputs / "Info.plist").open("rb") as handle:
                    self.assertEqual(plistlib.load(handle), original)
            finally:
                for process in processes:
                    if process.poll() is None:
                        process.terminate()
                    process.wait(timeout=5)
                if installed.exists():
                    shutil.rmtree(installed)


if __name__ == "__main__":
    unittest.main()
