#!/usr/bin/env python3
"""Reproduce the bundled, noteless NET text from eBible's complete VPL archive."""
import hashlib
import io
from pathlib import Path
import urllib.request
import zipfile

URL = "https://ebible.org/Scriptures/engnet_vpl.zip"
ROOT = Path(__file__).resolve().parent.parent
with urllib.request.urlopen(URL, timeout=60) as response:
    archive_bytes = response.read()
with zipfile.ZipFile(io.BytesIO(archive_bytes)) as archive:
    data = archive.read("engnet_vpl.txt")
    about = archive.read("engnet_about.htm")
lines = data.decode("utf-8").splitlines()
books = {line.split(" ", 1)[0] for line in lines}
chapters = {(line.split(" ", 2)[0], line.split(" ", 2)[1].split(":")[0]) for line in lines}
if len(lines) != 31102 or len(books) != 66 or len(chapters) != 1189:
    raise SystemExit("Unexpected Bible structure; review the source before replacing the bundled text.")
if not lines[0].startswith("GEN 1:1 ") or not lines[-1].startswith("REV 22:21 "):
    raise SystemExit("Unexpected book order.")
(ROOT / "Sources/BibleCore/Resources/NETBible.txt").write_bytes(data)
(ROOT / "docs/NET-source.html").write_bytes(about)
print(f"Imported 66 books, 1,189 chapters, 31,102 verse addresses.\nText SHA-256: {hashlib.sha256(data).hexdigest()}")
