#!/usr/bin/env python3
"""Merge Vietnamese translations into the String Catalog.

Usage: scripts/apply-translations.py <translations.json>

The input maps each English source key to its Vietnamese text. A key may
instead map to {"en": {"one": ..., "other": ...}, "vi": ...} to give the
English source singular and plural forms. Keys that are
not in the catalog are reported and skipped, so run scripts/sync-strings.sh
first. Removes keys that are no longer used in source, then prints the keys
that still lack a Vietnamese translation.
"""
import json
import sys
from pathlib import Path

CATALOG = Path(__file__).resolve().parent.parent / "TwanClean/Resources/Localizable.xcstrings"
LANGUAGE = "vi"


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    translations = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings = catalog["strings"]

    for key, value in translations.items():
        entry = strings.get(key)
        if entry is None:
            print(f"skipped (not in catalog): {key!r}", file=sys.stderr)
            continue
        localizations = entry.setdefault("localizations", {})
        if isinstance(value, dict):
            localizations["en"] = {
                "variations": {
                    "plural": {
                        form: {"stringUnit": {"state": "translated", "value": text}}
                        for form, text in value["en"].items()
                    }
                }
            }
            value = value["vi"]
        localizations[LANGUAGE] = {"stringUnit": {"state": "translated", "value": value}}

    # Keys no longer used in source are dropped rather than left stale.
    for key in [key for key, entry in strings.items() if entry.get("extractionState") == "stale"]:
        del strings[key]
        print(f"removed stale: {key!r}")

    CATALOG.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True).replace('": ', '" : ') + "\n",
        encoding="utf-8",
    )

    missing = [
        key
        for key, entry in strings.items()
        if entry.get("shouldTranslate", True)
        and LANGUAGE not in entry.get("localizations", {})
    ]
    for key in missing:
        print(f"missing {LANGUAGE}: {key!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
