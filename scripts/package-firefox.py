"""Package readable Firefox source for Mozilla signing; installs nothing."""
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

root = Path(__file__).resolve().parents[1]
source = root / "firefox"
version = json.loads((source / "manifest.json").read_text(encoding="utf-8"))["version"]
output = root / "dist" / f"ts-browser-ext-firefox-{version}-unsigned.xpi"
output.parent.mkdir(exist_ok=True)
with ZipFile(output, "w", ZIP_DEFLATED) as archive:
    for file in sorted(source.rglob("*")):
        if file.is_file():
            archive.write(file, file.relative_to(source))
    for name in ("LICENSE", "PATENTS"):
        archive.write(root / name, name)
print(output)
