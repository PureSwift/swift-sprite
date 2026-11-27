#!/usr/bin/env python3
"""Download and extract Kodeco's 2D Apple Games by Tutorials, edition 3.0.

Source and license: https://github.com/kodecocodes/deprecated-books
Only Python's standard library is required. Downloaded material stays outside git.
"""

import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import stat
import tempfile
import time
import urllib.error
import urllib.request
import zipfile


URL = "https://cdn.raywenderlich.com/deprecated-books/igt1/2D_Apple_Games_by_Tutorials_3.0.zip"
SHA256 = "eec0cb2944695fd8f864c6f233d6fc59b52dc8cafb04c51a0eb065f8cf6ae998"
REPO = Path(__file__).resolve().parent.parent
SAMPLES = (
    "12-beginning-tile-maps/final/PestControl/PestControl/GameScene.sks",
    "12-beginning-tile-maps/final/PestControl/PestControl/TileSets.sks",
    "13-intermediate-tile-maps/final/PestControl/PestControl/TileSets.sks",
    "16-particle-systems/final/DropCharge/DropCharge/Particles/Lava.sks",
)


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def download(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(3):
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as output:
                temporary = Path(output.name)
                request = urllib.request.Request(URL, headers={"User-Agent": "swift-sprite-tutorial-fetcher"})
                with urllib.request.urlopen(request, timeout=60) as response:
                    shutil.copyfileobj(response, output, length=1024 * 1024)
            if digest(temporary) != SHA256:
                raise ValueError("Downloaded tutorial ZIP has an unexpected SHA-256 checksum")
            os.replace(temporary, path)
            return
        except (OSError, urllib.error.URLError):
            if attempt == 2:
                raise
            time.sleep(2 ** attempt)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)


def validate_samples(directory):
    for relative in SAMPLES:
        with (directory / relative).open("rb") as source:
            archive = plistlib.load(source)
        if archive.get("$archiver") != "NSKeyedArchiver" or not archive.get("$objects"):
            raise ValueError(f"Invalid tutorial sample archive: {relative}")


def extract(archive, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        marker = destination / ".tutorial-sha256"
        if not marker.is_file() or marker.read_text().strip() != SHA256:
            raise ValueError(f"Refusing to replace an existing unrecognized directory: {destination}")
        validate_samples(destination)
        print(f"Tutorial already extracted: {destination}")
        return
    with tempfile.TemporaryDirectory(dir=destination.parent, prefix="tutorial-") as staging:
        with zipfile.ZipFile(archive) as source:
            for entry in source.infolist():
                path = PurePosixPath(entry.filename)
                if path.is_absolute() or ".." in path.parts or "\\" in entry.filename:
                    raise ValueError(f"Unsafe ZIP entry: {entry.filename}")
                if stat.S_ISLNK(entry.external_attr >> 16):
                    raise ValueError(f"Unsupported ZIP symbolic link: {entry.filename}")
            source.extractall(staging)
        staged = Path(staging)
        validate_samples(staged)
        (staged / ".tutorial-sha256").write_text(SHA256 + "\n")
        staged.rename(destination)
    print(f"Tutorial extracted and sample archives verified: {destination}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path,
                        default=REPO / ".build/tutorials/2D_Apple_Games_by_Tutorials_3.0.zip",
                        help="ZIP cache path; downloaded if missing")
    parser.add_argument("--destination", type=Path,
                        default=REPO / ".build/tutorials/2d-apple-games-3",
                        help="Extraction directory")
    args = parser.parse_args()
    if not args.archive.exists():
        print(f"Downloading {URL}", flush=True)
        download(args.archive)
    if digest(args.archive) != SHA256:
        raise ValueError(f"Tutorial ZIP checksum mismatch: {args.archive}; remove it and retry")
    extract(args.archive, args.destination)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        raise SystemExit(f"Tutorial setup failed: {error}")
