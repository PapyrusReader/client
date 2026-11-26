# /// script
# requires-python = ">=3.10"
# dependencies = ["uiautomator2==3.7.1"]
# ///

"""Exercise an installed debug build on a disposable Android emulator, then run Monkey."""

import argparse
import json
import re
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path

import uiautomator2

PACKAGE = "com.papyrus.reader"
BOOK = "Frankenstein"
FIXTURE = Path(__file__).resolve().parents[1] / "app/test/data/book1.epub"


class Emulator:
    def __init__(self, serial):
        self.serial = serial
        self.ui = uiautomator2.connect(serial)
        self.ui.jsonrpc.setConfigurator({"waitForIdleTimeout": 100})

    def adb(self, *args):
        return subprocess.check_output(["adb", "-s", self.serial, *args], text=True).strip()

    def shell(self, *args):
        return self.adb("shell", *map(str, args))

    def tree(self):
        return ET.fromstring(self.ui.dump_hierarchy(root_in_active=True))

    def screenshot(self, path):
        with path.open("wb") as screen:
            subprocess.run(
                ["adb", "-s", self.serial, "exec-out", "screencap", "-p"],
                stdout=screen,
                check=True,
            )

    def find(self, pattern, timeout=35, *, different_from=None):
        deadline = time.monotonic() + timeout
        labels = []
        while time.monotonic() < deadline:
            labels = []
            for node in self.tree().iter("node"):
                for attribute in ("text", "content-desc"):
                    value = node.get(attribute, "")
                    if value:
                        labels.append(value)
                    if (
                        value != different_from
                        and re.search(pattern, value, re.IGNORECASE)
                        and node.get("enabled") == "true"
                    ):
                        return node, value
            time.sleep(0.25)
        raise RuntimeError(f"Missing {pattern!r}. Visible labels: {labels}")

    def tap(self, pattern):
        node, value = self.find(pattern)
        deadline = time.monotonic() + 8
        while True:
            time.sleep(0.3)
            settled, value = self.find(pattern)
            if settled.get("bounds") == node.get("bounds"):
                break
            if time.monotonic() >= deadline:
                raise RuntimeError(f"Control kept moving: {value}")
            node = settled
        left, top, right, bottom = map(int, re.findall(r"\d+", node.get("bounds")))
        self.shell("input", "tap", (left + right) // 2, (top + bottom) // 2)
        print(f"Tapped {value}", flush=True)

    def timer_id(self):
        journal = self.shell("run-as", PACKAGE, "cat", "shared_prefs/reading-timer-notification.xml")
        state = ET.fromstring(journal).findtext("string[@name='state']")
        return json.loads(state)["base"]["id"]

    def launch(self):
        self.shell("am", "start", "-W", "-n", f"{PACKAGE}/.MainActivity")

    def cold_restart(self):
        self.shell("input", "keyevent", "KEYCODE_HOME")
        self.shell("am", "force-stop", PACKAGE)
        self.launch()

    def show_controls(self):
        try:
            self.find(r"Chapter \d+ of", timeout=4)
        except RuntimeError:
            width, height = map(int, re.findall(r"(\d+)x(\d+)", self.shell("wm", "size"))[-1])
            self.shell("input", "tap", width // 2, height // 2)
        return self.find(r"Chapter \d+ of")[1]

    def open_saved_book(self):
        self.tap(BOOK)
        self.tap(r"^Continue$")
        return self.show_controls()


def exercise(device):
    device.adb("push", str(FIXTURE), "/sdcard/Download/PapyrusJourney.epub")
    device.shell(
        "am",
        "broadcast",
        "-a",
        "android.intent.action.MEDIA_SCANNER_SCAN_FILE",
        "-d",
        "file:///sdcard/Download/PapyrusJourney.epub",
    )
    device.shell("pm", "grant", PACKAGE, "android.permission.POST_NOTIFICATIONS")
    device.launch()
    device.tap(r"^Continue offline$")
    device.tap(r"^Add book$")
    device.tap("Import digital books")
    device.tap("Browse files")
    file_pattern = r"^PapyrusJourney\.epub$"
    try:
        device.find(file_pattern, timeout=2)
    except RuntimeError:
        device.tap("Show roots")
        device.tap(re.escape(device.shell("getprop", "ro.product.model")))
        try:
            device.find(file_pattern, timeout=2)
        except RuntimeError:
            device.tap(r"^Download$")
    device.tap(file_pattern)
    device.find(r"PapyrusJourney\.epub")
    device.tap(r"^Import$")
    device.tap(r"^Done$")
    device.tap(BOOK)
    device.tap(r"^Read$")
    initial = device.show_controls()
    device.tap(r"^Next$")
    saved = device.find(r"Chapter \d+ of", different_from=initial)[1]
    device.tap(r"^Back$")
    device.find(r"^Continue$")
    device.shell("svc", "wifi", "disable")
    device.shell("svc", "data", "disable")
    try:
        device.cold_restart()
        restored = device.open_saved_book()
        if saved != restored:
            raise RuntimeError(f"Reading position changed from {saved!r} to {restored!r}")
        device.tap(r"^Back$")
        device.cold_restart()
        verify_timer_recovery(device)
    finally:
        device.shell("svc", "data", "enable")
        device.shell("svc", "wifi", "enable")


def verify_timer_recovery(device):
    device.tap("Library sections")
    device.tap(r"^Timer$")
    device.tap("Choose a book")
    device.tap(BOOK)
    device.tap(r"^Start$")
    device.find(r"^Pause$")
    session_id = device.timer_id()
    device.shell("input", "keyevent", "KEYCODE_HOME")
    device.shell("cmd", "statusbar", "expand-notifications")
    try:
        device.find(r"^Pause$", timeout=4)
    except RuntimeError:
        device.tap(r"Expand( notification)?$")
    device.tap(r"^Pause$")
    device.find(r"^Resume$")
    device.shell("cmd", "statusbar", "collapse")
    device.cold_restart()
    device.tap("Library sections")
    device.tap(r"^Timer$")
    device.find(BOOK)
    device.tap(r"^Resume$")
    device.find(r"^Pause$")
    if device.timer_id() != session_id:
        raise RuntimeError("Resume created a different timer session")
    device.tap(r"^Pause$")
    device.tap("Library sections")
    device.tap(r"^Books(\s|$)")
    device.open_saved_book()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--events", type=int, default=1000)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    device = Emulator(args.device)
    if device.shell("getprop", "ro.kernel.qemu") != "1":
        parser.error("Use a disposable emulator with a freshly installed Papyrus debug build.")
    args.output.mkdir(parents=True, exist_ok=True)
    metadata = {
        "seed": args.seed,
        "events": args.events,
        "build": device.shell("getprop", "ro.build.fingerprint"),
        "fixture": FIXTURE.name,
        "revision": subprocess.check_output(
            ["git", "-C", str(FIXTURE.parent), "rev-parse", "HEAD"], text=True
        ).strip(),
    }
    (args.output / "run.json").write_text(json.dumps(metadata, indent=2))
    try:
        exercise(device)
        device.screenshot(args.output / "reader-start.png")
        (args.output / "reader-start.xml").write_text(ET.tostring(device.tree(), encoding="unicode"))
        command = [
            "adb",
            "-s",
            device.serial,
            "shell",
            "monkey",
            "-p",
            PACKAGE,
            "-s",
            str(args.seed),
            "--pct-syskeys",
            "0",
            "--throttle",
            "100",
            "--monitor-native-crashes",
            "-v",
            "-v",
            str(args.events),
        ]
        result = subprocess.run(
            command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=False
        )
        output = result.stdout
        (args.output / "monkey.log").write_text(output)
        completed = re.search(rf"^Events injected: {args.events}$", output, re.MULTILINE)
        crashed = re.search(r"// (CRASH|NOT RESPONDING)|Monkey aborted", output)
        if result.returncode or not completed or crashed:
            raise RuntimeError("Monkey reported a failure. See monkey.log.")
    finally:
        (args.output / "logcat.txt").write_text(device.adb("logcat", "-d", "-t", "10000"))
        device.screenshot(args.output / "screen.png")


if __name__ == "__main__":
    main()
