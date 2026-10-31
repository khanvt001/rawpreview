#!/usr/bin/env python3
"""Packs the Emulsion Presets collection into the app's built-in preset file.

    /usr/bin/python3 scripts/build_builtin_presets.py [path/to/EmulsionPresets]

Reads `presets.json` (categories, names, descriptions) and every `.xmp` it
lists, keeps only the develop settings (`crs:` attributes, tone curves, the
profile named in `crs:Look`), and writes:

- rawpreview/Resources/BuiltInPresets.json
- rawpreview/Resources/EmulsionPresets-LICENSE.txt (MIT requires the notice)

Rerun after updating the collection.
"""

import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

CRS = "http://ns.adobe.com/camera-raw-settings/1.0/"
RDF = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"

# Bookkeeping attributes with no effect on the image.
SKIPPED = {
    "UUID", "Cluster", "HasSettings", "PresetType", "Name", "Version", "ProcessVersion",
    "RequiresRenditionBehavior", "SupportsAmount", "SupportsColor", "SupportsMonochrome",
    "SupportsHighDynamicRange", "SupportsNormalDynamicRange", "SupportsSceneReferred",
    "SupportsOutputReferred",
}


def value(text):
    if text in ("True", "False"):
        return text == "True"
    try:
        number = float(text)
    except ValueError:
        return text
    return int(number) if number.is_integer() else number


def settings_from(path):
    root = ET.parse(path).getroot()
    description = next(
        d for d in root.iter(f"{{{RDF}}}Description")
        if any(key.startswith(f"{{{CRS}}}") for key in d.attrib)
    )
    settings = {}
    for key, text in description.attrib.items():
        if key.startswith(f"{{{CRS}}}"):
            name = key[len(CRS) + 2:]
            if name not in SKIPPED:
                settings[name] = value(text)

    for child in description:
        if not child.tag.startswith(f"{{{CRS}}}"):
            continue
        name = child.tag[len(CRS) + 2:]
        if name.startswith("ToneCurve"):
            points = []
            for item in child.iter(f"{{{RDF}}}li"):
                points += [value(part.strip()) for part in item.text.split(",")]
            settings[name] = points
        elif name == "Look":
            look = child.find(f"{{{RDF}}}Description")
            if look is not None and f"{{{CRS}}}Name" in look.attrib:
                settings.setdefault("CameraProfile", look.attrib[f"{{{CRS}}}Name"])
    return settings


def main():
    source = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "EmulsionPresets")
    output = Path(__file__).resolve().parents[1] / "rawpreview" / "Resources"
    output.mkdir(parents=True, exist_ok=True)

    index = json.loads((source / "presets.json").read_text(encoding="utf-8"))
    categories = {category["name"]: [] for category in index["categories"]}
    for entry in index["presets"]:
        categories.setdefault(entry["category"], []).append({
            "name": entry["name"],
            "description": entry.get("description", ""),
            "settings": settings_from(source / entry["file"]),
        })

    result = {
        "source": index.get("homepage", ""),
        "categories": [
            {"name": name, "presets": sorted(presets, key=lambda p: p["name"].lower())}
            for name, presets in categories.items() if presets
        ],
    }
    (output / "BuiltInPresets.json").write_text(
        json.dumps(result, ensure_ascii=False, separators=(",", ":"), sort_keys=True), encoding="utf-8"
    )
    (output / "EmulsionPresets-LICENSE.txt").write_text((source / "LICENSE").read_text(encoding="utf-8"), encoding="utf-8")
    print(f"{sum(len(c['presets']) for c in result['categories'])} presets in {len(result['categories'])} categories")


if __name__ == "__main__":
    main()
