"""Verify release ABIs, native compression, Flutter assets and APK identity."""

import re
import subprocess
import sys
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


release = Path(sys.argv[1])
aapt = sys.argv[2]
abis = {"arm64-v8a", "x86_64"}
packages = {
    "app-release.apk": abis,
    "prepdesk-arm64-v8a.apk": {"arm64-v8a"},
    "prepdesk-x86_64.apk": {"x86_64"},
    "prepdesk-play.aab": abis,
}

universal_libraries = set()
universal_assets = set()
universal_identity = None
for name, expected_abis in packages.items():
    path = release / name
    is_bundle = path.suffix == ".aab"
    prefix = "base/" if is_bundle else ""
    with ZipFile(path) as archive:
        libraries = {
            entry.filename.removeprefix(prefix): entry
            for entry in archive.infolist()
            if entry.filename.startswith(f"{prefix}lib/") and entry.filename.endswith(".so")
        }
        actual_abis = {library.split("/")[1] for library in libraries}
        if actual_abis != expected_abis:
            sys.exit(f"{name}: expected {sorted(expected_abis)}, found {sorted(actual_abis)}")
        if not is_bundle:
            if any(entry.compress_type != ZIP_DEFLATED for entry in libraries.values()):
                sys.exit(f"{name}: native libraries must be compressed for GitHub distribution")
            assets = {
                entry.filename for entry in archive.infolist()
                if entry.filename.startswith("assets/flutter_assets/") and not entry.is_dir()
            }
            badging = subprocess.check_output([aapt, "dump", "badging", str(path)], text=True)
            identity = re.match(r"package: name='[^']+' versionCode='[^']+' versionName='[^']+'", badging)
            if identity is None:
                sys.exit(f"{name}: could not read Android package identity")
            if universal_identity is None:
                universal_identity = identity[0]
                universal_libraries = set(libraries)
                universal_assets = assets
            if identity[0] != universal_identity or assets != universal_assets:
                sys.exit(f"{name}: package identity or Flutter assets differ from the universal APK")
        expected_libraries = {
            library for library in universal_libraries if library.split("/")[1] in expected_abis
        }
        if libraries.keys() != expected_libraries:
            sys.exit(f"{name}: native library names differ from the universal APK")
    print(f"{name}: {path.stat().st_size / 1_000_000:.2f} MB ({', '.join(sorted(actual_abis))})")
