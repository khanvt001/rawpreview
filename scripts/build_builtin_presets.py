#!/usr/bin/env python3
"""Packs the Emulsion Presets collection into the app's built-in preset file.

    /usr/bin/python3 scripts/build_builtin_presets.py [path/to/EmulsionPresets]

Reads `presets.json` (categories, names, descriptions) and every `.xmp` it
lists, keeps only the develop settings (`crs:` attributes, tone curves, the
complete nested `crs:Look`/profile references and ProcessVersion), applies the
renames in `RENAMED`, and writes:

- rawpreview/Resources/BuiltInPresets.json
- rawpreview/Resources/EmulsionPresets-LICENSE.txt (MIT requires the notice)

Rerun after updating the collection.
"""

import json
import math
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

CRS = "http://ns.adobe.com/camera-raw-settings/1.0/"
RDF = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"

# Bookkeeping attributes with no effect on the image.
SKIPPED = {"UUID", "Cluster", "HasSettings", "PresetType", "Name"}

# Upstream names these presets after real photographers. The app describes the
# look instead, so it doesn't appear to trade on a person's name. A new
# description is given only where the old one mentions the person or their work.
RENAMED = {
    "Alec Soth": {"name": "Quiet Muted Color"},
    "Alex Webb": {"name": "Layered Street Color"},
    "Ansel Adams Zone System": {"name": "Red Filter Skies B&W"},
    "Cindy Sherman": {
        "name": "Imagined Film Still",
        "description": "Film still aesthetic: Color that carries a black-and-white mood, as if these are production stills from movies that don't exist",
    },
    "David LaChapelle": {"name": "Hyperreal Pop Color"},
    "Fan Ho": {"name": "Geometric Light Shafts"},
    "Gregory Crewdson": {"name": "Cinematic Teal Shadows"},
    "Henri Cartier-Bresson": {
        "name": "Classic Street B&W",
        "description": "Moderate contrast: Neither dramatic nor flat. Natural tonal transitions.",
    },
    "Joel Meyerowitz": {
        "name": "Golden Seaside Haze",
        "description": "Seaside golden light: Warm, hazy, almost tangible — light you can feel.",
    },
    "Martin Parr": {"name": "Ring Flash Pop"},
    "McCurry Kodachrome": {
        "name": "Warm Earth Kodachrome",
        "description": "Kodachrome toning with a warm golden earth-tone portrait palette",
    },
    "Michael Kenna": {"name": "Long Exposure Calm"},
    "Nan Goldin": {"name": "Direct Flash Snapshot"},
    "Peter Lindbergh": {"name": "Floating Midtones"},
    "Saul Leiter": {"name": "Through the Glass"},
    "Sebastiao Salgado": {"name": "Luminous Highlights"},
    "Steve McCurry": {
        "name": "Warm Skin Cool Background",
        "description": "Warm and cool palette: Warm skin tones against cool/neutral backgrounds. The red-green contrast.",
    },
    "Tim Walker": {"name": "Soft Pastel Dream"},
    "Todd Hido": {"name": "Streetlight Night Cast"},
    "Vivian Maier": {"name": "Square Street Frame"},
    "William Eggleston": {"name": "Everyday Bold Color"},
}


def value(text, key=""):
    if key in {"Name", "UUID", "Version", "ProcessVersion", "CameraProfile"} or key.endswith("Digest"):
        return text
    if text.strip().lower() in ("true", "false"):
        return text.strip().lower() == "true"
    try:
        number = float(text)
    except ValueError:
        return text
    if not math.isfinite(number):
        return text
    return int(number) if number.is_integer() else number


def settings_from(path):
    root = ET.parse(path).getroot()
    description = next(
        d for d in root.iter(f"{{{RDF}}}Description")
        if any(key.startswith(f"{{{CRS}}}") for key in d.attrib) or any(child.tag.startswith(f"{{{CRS}}}") for child in d)
    )
    settings = {}
    for key, text in description.attrib.items():
        if key.startswith(f"{{{CRS}}}"):
            name = key[len(CRS) + 2:]
            if name not in SKIPPED:
                settings[name] = value(text, name)

    for child in description:
        if not child.tag.startswith(f"{{{CRS}}}"):
            continue
        name = child.tag[len(CRS) + 2:]
        if name.startswith("ToneCurve") and child.find(f"{{{RDF}}}Seq") is not None:
            points = []
            for item in child.iter(f"{{{RDF}}}li"):
                points += [value(part.strip()) for part in item.text.split(",")]
            settings[name] = points
        else:
            settings[name] = xml_value(child)
    return settings


def xml_value(element):
    for child in element:
        if child.tag in (f"{{{RDF}}}Seq", f"{{{RDF}}}Bag", f"{{{RDF}}}Alt"):
            items = child.findall(f"{{{RDF}}}li")
            if child.tag == f"{{{RDF}}}Alt":
                items.sort(key=lambda item: item.attrib.get("{http://www.w3.org/XML/1998/namespace}lang") != "x-default")
                return [(item.text or "") for item in items]
            return [xml_value(item) for item in items]
    resource = element.find(f"{{{RDF}}}Description")
    if resource is None:
        resource = element
    fields = {key[len(CRS) + 2:]: value(text, key[len(CRS) + 2:]) for key, text in resource.attrib.items() if key.startswith(f"{{{CRS}}}")}
    if f"{{{RDF}}}resource" in resource.attrib:
        fields["rdf:resource"] = resource.attrib[f"{{{RDF}}}resource"]
    for child in resource:
        if child.tag.startswith(f"{{{CRS}}}"):
            fields[child.tag[len(CRS) + 2:]] = xml_value(child)
    return fields if fields else value((resource.text or "").strip(), resource.tag.split("}")[-1])


def main():
    source = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "EmulsionPresets")
    output = Path(__file__).resolve().parents[1] / "rawpreview" / "Resources"
    output.mkdir(parents=True, exist_ok=True)

    index = json.loads((source / "presets.json").read_text(encoding="utf-8"))
    categories = {category["name"]: [] for category in index["categories"]}
    for entry in index["presets"]:
        renamed = RENAMED.get(entry["name"], {})
        name = renamed.get("name", entry["name"])
        settings = settings_from(source / entry["file"])
        if renamed:
            settings["Name"] = [name]    # The .xmp carries the old name too.
        categories.setdefault(entry["category"], []).append({
            "name": name,
            "description": renamed.get("description", entry.get("description", "")),
            "settings": settings,
        })

    missing = RENAMED.keys() - {entry["name"] for entry in index["presets"]}
    if missing:
        sys.exit(f"Not in the collection, update RENAMED: {sorted(missing)}")

    result = {
        "source": index.get("homepage", ""),
        "categories": [
            {"name": name, "presets": sorted(presets, key=lambda p: p["name"].lower())}
            for name, presets in categories.items() if presets
        ],
    }
    (output / "BuiltInPresets.json").write_text(
        json.dumps(result, ensure_ascii=False, separators=(",", ":"), sort_keys=True, allow_nan=False), encoding="utf-8"
    )
    (output / "EmulsionPresets-LICENSE.txt").write_text((source / "LICENSE").read_text(encoding="utf-8"), encoding="utf-8")
    print(f"{sum(len(c['presets']) for c in result['categories'])} presets in {len(result['categories'])} categories")


if __name__ == "__main__":
    main()
