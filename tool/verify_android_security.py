#!/usr/bin/env python3
"""Verify declared Android backup/privacy boundaries without external packages.

These checks validate source policy and XML wiring; they are not device tests.
"""
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
MAIN = ROOT / "android/app/src/main"
ANDROID = "{http://schemas.android.com/apk/res/android}"
DOMAINS = {"root", "file", "database", "sharedpref", "external"}


def check_exclusions(element):
    assert element is not None, "Missing backup/transfer policy element"
    assert not element.findall("include"), "Partial backup restore must stay disabled"
    exclusions = element.findall("exclude")
    assert len(exclusions) == len(DOMAINS), "Every application backup domain must be excluded"
    assert {item.get("domain") for item in exclusions} == DOMAINS
    assert all(item.get("path") == "." for item in exclusions)


def main():
    manifest = ET.parse(MAIN / "AndroidManifest.xml").getroot()
    app = manifest.find("application")
    assert app is not None
    assert app.get(ANDROID + "allowBackup") == "false"
    assert app.get(ANDROID + "usesCleartextTraffic") == "false"
    assert app.get(ANDROID + "fullBackupContent") == "@xml/backup_rules"
    assert app.get(ANDROID + "dataExtractionRules") == "@xml/data_extraction_rules"
    entry = app.find("activity")
    assert entry is not None and entry.get(ANDROID + "name") == ".MainActivity"
    link_routing = [item for item in entry.findall("meta-data")
                    if item.get(ANDROID + "name") == "flutter_deeplinking_enabled"]
    assert len(link_routing) == 1 and link_routing[0].get(ANDROID + "value") == "false"
    callbacks = [item for item in entry.findall("intent-filter")
                 if any(action.get(ANDROID + "name") == "android.intent.action.VIEW"
                        for action in item.findall("action"))]
    assert len(callbacks) == 1, "Keep one explicit native authentication callback"
    callback = callbacks[0]
    assert {item.get(ANDROID + "name") for item in callback.findall("category")} == {
        "android.intent.category.DEFAULT", "android.intent.category.BROWSABLE"}
    destinations = callback.findall("data")
    assert len(destinations) == 1 and destinations[0].attrib == {
        ANDROID + "scheme": "com.nexapos.app", ANDROID + "host": "auth",
        ANDROID + "path": "/callback"}, "Do not widen the callback URI filter"
    legacy = ET.parse(MAIN / "res/xml/backup_rules.xml").getroot()
    assert legacy.tag == "full-backup-content"
    check_exclusions(legacy)
    modern = ET.parse(MAIN / "res/xml/data_extraction_rules.xml").getroot()
    assert modern.tag == "data-extraction-rules"
    cloud = modern.find("cloud-backup")
    check_exclusions(cloud)
    assert cloud.get("disableIfNoEncryptionCapabilities") == "true"
    check_exclusions(modern.find("device-transfer"))
    activity = (MAIN / "kotlin/com/nexapos/nexapos/MainActivity.kt").read_text()
    secure_flag = "window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)"
    assert secure_flag in activity
    assert activity.index(secure_flag) < activity.index("super.onCreate(savedInstanceState)")
    assert "clearFlags" not in activity
    print("Android source backup/transfer exclusions, TLS default and secure window policy verified.")
    print("Exact com.nexapos.app://auth/callback registration uses the existing app_links handler.")
    print("Physical device behavior still requires platform acceptance testing.")


if __name__ == "__main__":
    main()
