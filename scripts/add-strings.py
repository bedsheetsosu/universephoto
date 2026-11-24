#!/usr/bin/env python3
"""Adds English/German pairs to the string catalog, keeping its formatting.

Usage: scripts/add-strings.py '{"English key": "Deutscher Text", ...}'   (or a path to a JSON file)
Existing keys are left alone. Prints how many were added.
"""
import json, os, sys

catalog = os.path.join(os.path.dirname(__file__), "..", "Sources", "UniverseStudio", "Resources", "Localizable.xcstrings")
arg = sys.argv[1]
pairs = json.load(open(arg)) if os.path.exists(arg) else json.loads(arg)
text = open(catalog, encoding="utf-8").read()
existing = json.loads(text)["strings"]

def entry(key, de):
    unit = lambda v: {"stringUnit": {"state": "translated", "value": v}}
    body = {"extractionState": "manual", "generatesSymbol": False, "localizations": {"de": unit(de), "en": unit(key)}}
    lines = json.dumps(body, ensure_ascii=False, indent=2).split("\n")
    return "    " + json.dumps(key, ensure_ascii=False) + ": " + "\n".join([lines[0]] + ["    " + l for l in lines[1:]])

new = [entry(k, v) for k, v in pairs.items() if k not in existing]
if new:
    end = text.rstrip().rfind("\n  },")   # closing brace of "strings"
    head = text[:end].rstrip()
    text = head + ",\n" + ",\n".join(new) + text[end:]
    json.loads(text)   # still valid
    open(catalog, "w", encoding="utf-8").write(text)
print(f"added {len(new)}")
