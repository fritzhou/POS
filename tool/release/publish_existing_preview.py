#!/usr/bin/env python3
"""Transfer the four audited preview files; never build or publish a release."""

import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

REPOSITORY = "fritzhou/POS"
TAG = "v0.1.0-preview"
BUILD_COMMIT = "8d4e25c17142ebf9c6c60b8293b501e7a50388bd"
RELEASE_ID = 411846473
EXPECTED = {
    "NexaPOS-Android.apk": (
        95578513,
        "72c2b3c54c8f612ad7b43bdd9764eb7cb27f3e1eebf3da5a7fd3362fc87dae4c",
    ),
    "NexaPOS-Windows-Portable.zip": (
        32439152,
        "1ef886f3f7ecf9545f263e980317f12b91f6a3dd069b4da5c563c5cd0ab68267",
    ),
    "NexaPOS-Windows-Setup.exe": (
        25549899,
        "4c6cd4f822d8eb503e012173291f4bb48934dd4ebde19ed4648e072031e0519e",
    ),
    "NexaPOS-Build-Report.txt": (
        5355,
        "7745c8691e0e164949134bf2719f0974119ce3c0f79b8cf1dc860354db40b968",
    ),
}


def api(endpoint):
    result = subprocess.run(
        ["gh", "api", endpoint], check=True, capture_output=True, text=True
    )
    return json.loads(result.stdout)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def verify_file(path):
    size, digest = EXPECTED[path.name]
    require(path.is_file() and not path.is_symlink(), "Missing regular asset file")
    require(path.stat().st_size == size, "Asset size mismatch: " + path.name)
    require(hashlib.file_digest(path.open("rb"), "sha256").hexdigest() == digest,
            "Asset checksum mismatch: " + path.name)


def verify_release(release):
    require(release["id"] == RELEASE_ID, "Unexpected release ID")
    require(release["name"] == "NexaPOS Preview", "Unexpected release title")
    require(release["tag_name"] == TAG, "Unexpected release tag")
    require(release["target_commitish"] == BUILD_COMMIT, "Unexpected build commit")
    require(release["draft"] is True and release["prerelease"] is True,
            "Release must remain a draft pre-release")
    assets = release["assets"]
    require(len({a["name"] for a in assets}) == len(assets), "Duplicate release asset")
    for asset in assets:
        require(asset["name"] in EXPECTED, "Unexpected release asset")
        size, digest = EXPECTED[asset["name"]]
        require(asset["size"] == size and asset.get("digest") == "sha256:" + digest,
                "Remote asset checksum mismatch: " + asset["name"])


def main():
    require(os.environ.get("GITHUB_REPOSITORY") == REPOSITORY, "Unexpected repository")
    require(os.environ.get("GITHUB_REF") == "refs/heads/release/builds", "Unexpected branch")
    directory = Path(os.environ["PREVIEW_DIRECTORY"])
    manifest = json.loads(os.environ["BLOB_MANIFEST"])
    require(isinstance(manifest, dict) and set(manifest) == {
        "NexaPOS-Android.apk", "NexaPOS-Build-Report.txt"
    }, "Unexpected blob manifest files")

    for name, chunks in manifest.items():
        require(isinstance(chunks, list) and 1 <= len(chunks) <= 30, "Invalid chunk count")
        total = 0
        with (directory / name).open("wb") as output:
            for chunk in chunks:
                require(isinstance(chunk, dict) and set(chunk) == {"sha", "size"},
                        "Invalid chunk metadata")
                require(isinstance(chunk["sha"], str) and
                        re.fullmatch(r"[0-9a-f]{40}", chunk["sha"]), "Invalid blob SHA")
                require(type(chunk["size"]) is int and 0 < chunk["size"] <= 4194304,
                        "Invalid blob size")
                blob = api(f"repos/{REPOSITORY}/git/blobs/{chunk['sha']}")
                require(blob["encoding"] == "base64" and blob["sha"] == chunk["sha"],
                        "Unexpected blob response")
                data = base64.b64decode(blob["content"])
                require(len(data) == chunk["size"] == blob["size"], "Blob size mismatch")
                git_digest = hashlib.sha1(
                    f"blob {len(data)}\0".encode() + data
                ).hexdigest()
                require(git_digest == chunk["sha"], "Blob checksum mismatch")
                total += len(data)
                require(total <= EXPECTED[name][0], "Too much asset data")
                output.write(data)
        verify_file(directory / name)

    # The prior Windows CI artifact also contains validation evidence. Only these
    # four explicitly allowed files are attached to the public release.
    for name in EXPECTED:
        verify_file(directory / name)
    release = api(f"repos/{REPOSITORY}/releases/{RELEASE_ID}")
    verify_release(release)
    existing = {asset["name"] for asset in release["assets"]}
    missing = [str(directory / name) for name in EXPECTED if name not in existing]
    if missing:
        subprocess.run(
            ["gh", "release", "upload", TAG, "--repo", REPOSITORY, *missing],
            check=True,
        )
    release = api(f"repos/{REPOSITORY}/releases/{RELEASE_ID}")
    verify_release(release)
    require({asset["name"] for asset in release["assets"]} == set(EXPECTED),
            "Incomplete release asset set")
    print("All four existing assets uploaded with verified SHA-256 checksums.")
    print("No application build ran. Release remains a draft pre-release for final review.")


if __name__ == "__main__":
    main()
