"""Adds the current Rise.ipa to altstore-source.json as the newest version.

AltStore refuses to install if the source doesn't match the IPA exactly (version, build,
privacy permissions), so everything is read from the IPA itself, never typed by hand.

Run from this folder:  python update_source.py "What changed in this version"
Then publish the IPA as GitHub Release v<version> (the downloadURL below points there).
"""
import datetime
import json
import os
import plistlib
import sys
import zipfile

REPO = "HarveyK1/Rise-Alarm"
SOURCE = "altstore-source.json"
IPA = "Rise.ipa"
RAW = f"https://raw.githubusercontent.com/{REPO}/main"


def read_ipa():
    with zipfile.ZipFile(IPA) as z:
        plists = {n: plistlib.loads(z.read(n)) for n in z.namelist() if n.endswith(".app/Info.plist")
                  or n.endswith(".appex/Info.plist")}
    app = next(p for n, p in plists.items() if n.endswith(".app/Info.plist") and ".appex/" not in n)
    privacy = {}
    for p in plists.values():   # app + extensions
        privacy.update({k: v for k, v in p.items() if k.endswith("UsageDescription")})
    return app, privacy


def skeleton():
    return {
        "name": "Rise",
        "subtitle": "Alarm clock with wake-up missions",
        "description": "Rise: alarms you have to get up to turn off. Built from source at github.com/" + REPO,
        "iconURL": f"{RAW}/Rise/Icon.png",
        "website": f"https://github.com/{REPO}",
        "tintColor": "#FF9500",
        "apps": [{
            "name": "Rise",
            "bundleIdentifier": "app.risealarm.Rise",
            "developerName": "HarveyK1",
            "subtitle": "Alarm clock with wake-up missions",
            "localizedDescription": (
                "An alarm you have to get up to turn off. Wake-up missions (maths, shake, scan a code, "
                "memory tiles, typing, tap challenge, photo match, say the word), a lock-screen card, "
                "volume lock, gentle wake-up, backup siren, wake-up check, talking alarm, custom sounds, "
                "weather and wake-up streaks."),
            "iconURL": f"{RAW}/Rise/Icon.png",
            "tintColor": "#FF9500",
            "category": "utilities",
            "screenshots": [],
            "versions": [],
            "appPermissions": {"entitlements": [], "privacy": {}},
        }],
        "news": [],
    }


def main():
    notes = sys.argv[1] if len(sys.argv) > 1 else ""
    info, privacy = read_ipa()
    source = json.load(open(SOURCE, encoding="utf-8")) if os.path.exists(SOURCE) else skeleton()
    app = source["apps"][0]
    assert app["bundleIdentifier"] == info["CFBundleIdentifier"], "bundle id in source != IPA"
    version = info["CFBundleShortVersionString"]
    entry = {
        "version": version,
        "buildVersion": info["CFBundleVersion"],
        "date": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "localizedDescription": notes,
        "downloadURL": f"https://github.com/{REPO}/releases/download/v{version}/Rise.ipa",
        "size": os.path.getsize(IPA),
        "minOSVersion": info.get("MinimumOSVersion", "17.0"),
    }
    # Newest first; replace an entry for the same version if re-run.
    app["versions"] = [entry] + [v for v in app["versions"] if v["version"] != version]
    app["appPermissions"]["privacy"] = privacy   # must list every *UsageDescription in the IPA
    with open(SOURCE, "w", encoding="utf-8", newline="\n") as f:
        json.dump(source, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"{SOURCE}: v{version} (build {entry['buildVersion']}), {entry['size']} bytes, "
          f"{len(privacy)} privacy keys")


if __name__ == "__main__":
    main()
