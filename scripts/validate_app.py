#!/usr/bin/env python3
"""Static release checks for MUGHAL'S PURE WATER."""
from html.parser import HTMLParser
from pathlib import Path
import json
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HTML = ROOT / "index.html"
MANIFEST = ROOT / "manifest.webmanifest"
SW = ROOT / "SW.js"

class AppParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = []
        self.inline_scripts = []
        self.current_script = None
        self.local_refs = []
        self.onclick = []
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            self.ids.append(attrs["id"])
        for attr in ("src", "href"):
            value = attrs.get(attr, "")
            if value and not re.match(r"^(?:[a-z]+:|//|#|data:)", value, re.I):
                self.local_refs.append(value.split("?")[0].split("#")[0])
        if "onclick" in attrs:
            self.onclick.append(attrs["onclick"])
        if tag.lower() == "script" and not attrs.get("src"):
            self.current_script = []
    def handle_data(self, data):
        if self.current_script is not None:
            self.current_script.append(data)
    def handle_endtag(self, tag):
        if tag.lower() == "script" and self.current_script is not None:
            self.inline_scripts.append("".join(self.current_script))
            self.current_script = None

def fail(message):
    raise SystemExit("FAIL: " + message)

if not all(path.exists() for path in (HTML, MANIFEST, SW)):
    fail("required app shell file is missing")

source = HTML.read_text(encoding="utf-8")
parser = AppParser()
parser.feed(source)

if len(parser.ids) != len(set(parser.ids)):
    duplicates = sorted({x for x in parser.ids if parser.ids.count(x) > 1})
    fail("duplicate HTML IDs: " + ", ".join(duplicates))

declared = set(re.findall(r"\bfunction\s+([A-Za-z_$][\w$]*)\s*\(", source))
for handler in parser.onclick:
    match = re.match(r"\s*([A-Za-z_$][\w$]*)\s*\(", handler)
    if match and match.group(1) not in declared and match.group(1) not in {"alert", "confirm", "prompt"}:
        fail("onclick handler has no declared function: " + match.group(1))

for ref in parser.local_refs:
    if ref and not (ROOT / ref).resolve().exists():
        fail("missing local HTML asset: " + ref)

try:
    json.loads(MANIFEST.read_text(encoding="utf-8"))
except Exception as exc:
    fail("manifest JSON is invalid: " + str(exc))

js_files = [(SW.name, SW.read_text(encoding="utf-8"))]
js_files += [(f"inline-script-{i}.js", code) for i, code in enumerate(parser.inline_scripts) if code.strip()]
for name, code in js_files:
    with tempfile.NamedTemporaryFile("w", suffix=".js", encoding="utf-8", delete=False) as tmp:
        tmp.write(code)
        temp_path = Path(tmp.name)
    result = subprocess.run(["node", "--check", str(temp_path)], capture_output=True, text=True)
    temp_path.unlink(missing_ok=True)
    if result.returncode:
        fail(f"JavaScript syntax error in {name}: " + (result.stderr or result.stdout).strip())

for path in (HTML, MANIFEST, SW):
    if "kiswa" in path.read_text(encoding="utf-8").lower():
        fail("legacy Kiswa branding remains in " + path.name)

print("PASS: app shell files, unique IDs, local assets, onclick handlers, manifest JSON, inline JavaScript, Service Worker syntax, and legacy branding.")
