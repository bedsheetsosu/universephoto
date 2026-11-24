#!/usr/bin/env python3
"""Lists L("…") keys used in the apps that have no English entry in Translations.swift,
and English entries that are no longer used. Exit code 1 if something is missing."""
import pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent
lit = r'"((?:[^"\\]|\\.)*)"'
used = set()
for d in ["Host", "Client", "Packages/TafelKit/Sources"]:
    for f in (root / d).rglob("*.swift"):
        if f.name in ("Translations.swift",):
            continue
        for m in re.finditer(r'\bL\(\s*' + lit, f.read_text()):
            used.add(m.group(1))
kit = root / "Packages/TafelKit/Sources/TafelKit"
def keys(path):
    return set(m.group(1) for m in re.finditer(r'^\s*' + lit + r'\s*:\s*"', path.read_text(), re.M))
failed = False
for f in sorted([kit / "Translations.swift"] + list(kit.glob("Translations+*.swift"))):
    known = keys(f)
    missing = sorted(used - known)
    unused = sorted(known - used - {"Sprache"})
    for k in missing:
        print(f"{f.name}: MISSING:", k)
    for k in unused:
        print(f"{f.name}: unused: ", k)
    print(f"{f.name}: {len(used)} keys used, {len(missing)} missing, {len(unused)} unused")
    failed |= bool(missing)
sys.exit(1 if failed else 0)
