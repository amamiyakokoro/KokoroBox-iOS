#!/usr/bin/env python3
"""Preserve target entitlements in a certificate-free archive for Xcode export."""

import argparse
import json
import plistlib
import re
import subprocess
import tempfile
from pathlib import Path


def expand(value, settings):
    if isinstance(value, str):
        for _ in range(20):
            if not re.search(r"\$\([^)]+\)", value):
                return value
            value = re.sub(r"\$\(([^)]+)\)", lambda m: settings[m[1]], value)
        raise ValueError(f"Unresolved build setting: {value}")
    if isinstance(value, list):
        return [expand(item, settings) for item in value]
    if isinstance(value, dict):
        return {key: expand(item, settings) for key, item in value.items()}
    return value


def sign(bundle, entitlements=None):
    command = ["codesign", "--force", "--sign", "-", "--timestamp=none"]
    if entitlements:
        command += ["--entitlements", str(entitlements), "--generate-entitlement-der"]
    subprocess.run(command + [str(bundle)], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("build_settings", type=Path)
    args = parser.parse_args()
    info_path = args.archive / "Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    app = args.archive / "Products" / info["ApplicationProperties"]["ApplicationPath"]
    settings_by_product = {}
    for target in json.loads(args.build_settings.read_text()):
        settings = target["buildSettings"]
        product = settings.get("FULL_PRODUCT_NAME")
        if product:
            settings_by_product[product] = settings

    bundles = sorted(app.rglob("*.appex")) + [app]
    # Sign nested libraries before their enclosing extensions and app.
    nested_code = list(app.rglob("*.framework")) + list(app.rglob("*.dylib"))
    for bundle in sorted(nested_code, key=lambda p: len(p.parts), reverse=True):
        sign(bundle)

    with tempfile.TemporaryDirectory() as temporary:
        for bundle in bundles:
            settings = settings_by_product[bundle.name]
            bundle_info = plistlib.loads((bundle / "Info.plist").read_bytes())
            if bundle_info["CFBundleIdentifier"] != settings["PRODUCT_BUNDLE_IDENTIFIER"]:
                raise ValueError(f"Bundle identifier mismatch: {bundle}")
            source = Path(settings["SRCROOT"]) / settings["CODE_SIGN_ENTITLEMENTS"]
            entitlements = expand(plistlib.loads(source.read_bytes()), settings)
            team = settings["DEVELOPMENT_TEAM"]
            entitlements["application-identifier"] = f"{team}.{settings['PRODUCT_BUNDLE_IDENTIFIER']}"
            entitlements["com.apple.developer.team-identifier"] = team
            path = Path(temporary) / f"{bundle.name}.plist"
            path.write_bytes(plistlib.dumps(entitlements))
            sign(bundle, path)
            result = subprocess.run(
                ["codesign", "--display", "--entitlements", "-", "--xml", str(bundle)],
                check=True, capture_output=True,
            )
            if plistlib.loads(result.stdout) != entitlements:
                raise ValueError(f"Entitlements changed while signing: {bundle}")
            subprocess.run(["codesign", "--verify", "--strict", str(bundle)], check=True)
            print(f"Preserved entitlements: {bundle.name}", flush=True)

    info["ApplicationProperties"]["SigningIdentity"] = "-"
    info["ApplicationProperties"]["Team"] = settings_by_product[app.name]["DEVELOPMENT_TEAM"]
    info_path.write_bytes(plistlib.dumps(info))


if __name__ == "__main__":
    main()
