#!/usr/bin/env python3
"""Exercise real Sparkle installation and signature failures using disposable apps."""
import functools
import http.server
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import tempfile
import threading
import uuid

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)
APP = ROOT / "dist/Ruller.app"
assert APP.is_dir(), "Run make build first"
TOOLS = Path(subprocess.check_output(["bash", "scripts/sparkle-tools.sh"], text=True).strip())


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def plist(path, changes):
    info = plistlib.loads(path.read_bytes()) if path.exists() else {}
    info.update(changes)
    path.write_bytes(plistlib.dumps(info))


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


# Installer helpers should operate in an ordinary temporary directory, outside
# macOS's protected Documents/Desktop locations.
with tempfile.TemporaryDirectory(prefix="ruller-update-test-", dir="/private/tmp") as temp:
    stage = Path(temp)
    harness = stage / "Harness.app"
    (harness / "Contents/MacOS").mkdir(parents=True)
    frameworks = harness / "Contents/Frameworks"
    run("ditto", APP / "Contents/Frameworks", frameworks)
    exe = harness / "Contents/MacOS/Harness"
    env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(stage / "clang-cache"))
    run("swiftc", "-target", f"{platform.machine()}-apple-macosx13.0", "-parse-as-library",
        "-F", frameworks, "-framework", "Sparkle", "-framework", "AppKit",
        "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
        "Tests/UpdateIntegration/Harness.swift", "-o", exe, env=env)
    plist(harness / "Contents/Info.plist", {
        "CFBundleIdentifier": "local.ruller.integration.harness." + uuid.uuid4().hex,
        "CFBundleExecutable": "Harness", "CFBundlePackageType": "APPL",
        "CFBundleName": "Ruller Update Test", "CFBundleVersion": "1", "LSUIElement": True,
        "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
    })
    run("bash", "scripts/sign-app.sh", harness)
    key = stage / "test-key"
    public_key = subprocess.check_output([str(exe), "--make-test-key", str(key)], text=True).strip()
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(QuietHandler, directory=str(stage)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        for scenario in ("install", "archive-tamper", "feed-tamper"):
            case = stage / scenario
            downloads = case / "downloads"
            downloads.mkdir(parents=True)
            bundle_id = "local.ruller.integration." + uuid.uuid4().hex
            url = f"http://127.0.0.1:{server.server_port}/{scenario}/downloads/"
            host = case / "installed/Ruller.app"
            new = case / "new/Ruller.app"
            for app, build in ((host, "1000"), (new, "1001")):
                run("ditto", APP, app)
                plist(app / "Contents/Info.plist", {
                    "CFBundleIdentifier": bundle_id, "CFBundleVersion": build,
                    "CFBundleShortVersionString": "1.0.0" if build == "1000" else "1.0.1",
                    "SUPublicEDKey": public_key, "SUFeedURL": url + "appcast.xml",
                    "SUEnableAutomaticChecks": False,
                    "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
                })
                run("bash", "scripts/sign-app.sh", app)
            archive = downloads / (bundle_id + ".zip")
            run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", new, archive)
            # Keep the old and new test bundle out of Launch Services discovery.
            shutil.rmtree(new.parent)
            run(TOOLS / "bin/generate_appcast", "--ed-key-file", key,
                "--download-url-prefix", url, "--maximum-deltas", "0", downloads)
            if scenario == "archive-tamper":
                # ZIP still extracts correctly, but its Ed25519 signature must fail.
                with archive.open("ab") as output:
                    output.write(b"tampered")
            elif scenario == "feed-tamper":
                feed = downloads / "appcast.xml"
                contents = feed.read_bytes()
                assert b"<title>" in contents
                feed.write_bytes(contents.replace(b"<title>", b"<title>tampered ", 1))
            print(f"\n=== {scenario} ===", flush=True)
            run(exe, host, "install" if scenario == "install" else "reject", timeout=70)
            installed = plistlib.loads((host / "Contents/Info.plist").read_bytes())
            assert installed["CFBundleVersion"] == ("1001" if scenario == "install" else "1000")
            run("codesign", "--verify", "--deep", "--strict", host)
            if scenario == "install":
                run(exe, host, "latest", timeout=70)
            # Isolated Sparkle preferences and cache can be removed after each fixture.
            subprocess.run(["defaults", "delete", bundle_id], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            shutil.rmtree(Path.home() / "Library/Caches" / bundle_id, ignore_errors=True)
        print("\nPASS: actual installation, archive tampering, and signed-feed tampering")
    finally:
        server.shutdown()
