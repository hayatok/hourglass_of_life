"""Strict source preflight for selected CMU ASF/AMC captures, without a DCC.

This parses source units/channels only. It does not certify a retargeted pose,
floor/prop contact, or natural animation. Finger/thumb channels are deliberately
excluded: CMU says these joints were added for editing, not actually captured.
"""
from pathlib import Path
import json
import math

UNCAPTURED = {"lfingers", "rfingers", "lthumb", "rthumb"}


def numbers(text):
    values = [float(value) for value in text.split()]
    if not all(math.isfinite(value) for value in values):
        raise ValueError("Non-finite source channel")
    return values


def parse_asf(text):
    sections = {}
    current = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith(":"):
            key, *remainder = line[1:].split(maxsplit=1)
            current = key
            sections[current] = [remainder[0]] if remainder else []
        elif current:
            sections[current].append(line)
    units = dict(line.split(maxsplit=1) for line in sections.get("units", []))
    root = dict(line.split(maxsplit=1) for line in sections.get("root", []))
    if sections.get("version") != ["1.10"] or units.get("angle") != "deg" or root.get("axis") != "XYZ":
        raise ValueError("Unsupported source angle or root axis convention")
    scale = float(units.get("length", "nan"))
    if not math.isfinite(scale) or scale <= 0:
        raise ValueError("Invalid ASF length convention")
    # CMU's own info.php: stored inches scaled by :units length (usually .45).
    metres = .0254 / scale
    order = root.get("order", "").lower().split()
    if order != ["tx", "ty", "tz", "rx", "ry", "rz"]:
        raise ValueError("Unsupported root channels")
    origin = numbers(root.get("position", ""))
    orientation = numbers(root.get("orientation", ""))
    if len(origin) != 3 or len(orientation) != 3:
        raise ValueError("Invalid calibrated root rest transform")
    bones = {}
    bone = None
    ids = set()
    for line in sections.get("bonedata", []):
        if line == "begin":
            if bone is not None:
                raise ValueError("Nested bone block")
            bone = {"dof": []}
        elif line == "end":
            if bone is None or not {"name", "id", "direction", "length_m", "axis_degrees", "axis_order"} <= bone.keys():
                raise ValueError("Incomplete bone block")
            if bone["name"] in bones or bone["id"] in ids:
                raise ValueError("Duplicate bone name/id")
            if abs(sum(value * value for value in bone["direction"]) - 1) > .0001:
                raise ValueError("Bone direction is not normalized")
            bones[bone["name"]] = bone
            ids.add(bone["id"])
            bone = None
        elif bone is not None:
            key, *rest = line.split(maxsplit=1)
            value = rest[0] if rest else ""
            if key == "id":
                bone[key] = int(value)
            elif key == "name":
                bone[key] = value
            elif key == "direction":
                bone[key] = numbers(value)
                if len(bone[key]) != 3:
                    raise ValueError("Bad direction vector")
            elif key == "length":
                bone["length_m"] = float(value) * metres
                if not math.isfinite(bone["length_m"]) or bone["length_m"] <= 0:
                    raise ValueError("Bad bone length")
            elif key == "axis":
                parts = value.split()
                if len(parts) != 4 or parts[-1] != "XYZ":
                    raise ValueError("Unsupported bone axis convention")
                bone["axis_degrees"] = numbers(" ".join(parts[:3]))
                bone["axis_order"] = parts[-1]
            elif key == "dof":
                bone[key] = value.split()
                if len(set(bone[key])) != len(bone[key]) or any(channel not in {"rx", "ry", "rz"} for channel in bone[key]):
                    raise ValueError("Unsupported bone channel")
    if bone is not None or not bones:
        raise ValueError("Unterminated or empty skeleton")
    parents = {}
    for line in sections.get("hierarchy", []):
        if line in {"begin", "end"}:
            continue
        parent, *children = line.split()
        if parent != "root" and parent not in bones:
            raise ValueError("Unknown parent")
        for child in children:
            if child not in bones or child in parents:
                raise ValueError("Unknown or multiply-parented child")
            parents[child] = parent
    if set(parents) != set(bones):
        raise ValueError("Disconnected skeleton")
    for name in bones:
        seen = set()
        at = name
        while at != "root":
            if at in seen:
                raise ValueError("Cyclic skeleton")
            seen.add(at)
            at = parents[at]
    return {"bones": bones, "parents": parents, "metres_per_source_unit": metres,
            "root_order": order, "root_axis": root["axis"],
            "root_origin_m": [value * metres for value in origin], "root_orientation_degrees": orientation}


def parse_amc(text, skeleton, fps):
    if not isinstance(fps, (int, float)) or not math.isfinite(fps) or fps <= 0:
        raise ValueError("Catalog frame rate is required")
    expected = {name: bone["dof"] for name, bone in skeleton["bones"].items() if bone["dof"]}
    expected["root"] = skeleton["root_order"]
    headers = set()
    frames = []
    channels = None

    def finish():
        if channels is None:
            return
        if set(channels) != set(expected):
            raise ValueError("Missing/extra channels in fully specified frame")
        frames.append({"root_translation_m": [value * skeleton["metres_per_source_unit"] for value in channels["root"][:3]],
                       "rotation_channels_rad": {name: [math.radians(value) for value in (values[3:] if name == "root" else values)]
                                                 for name, values in channels.items() if name not in UNCAPTURED}})

    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith(":"):
            headers.add(line)
        elif line.isdecimal():
            finish()
            if int(line) != len(frames) + 1:
                raise ValueError("Frames are not contiguous from 1")
            channels = {}
        else:
            if channels is None:
                raise ValueError("Channel before first frame")
            name, *rest = line.split(maxsplit=1)
            if name not in expected or name in channels or not rest:
                raise ValueError("Unknown/duplicate channel")
            values = numbers(rest[0])
            if len(values) != len(expected[name]):
                raise ValueError("Channel count differs from calibrated skeleton")
            channels[name] = values
    finish()
    if not {":FULLY-SPECIFIED", ":DEGREES"} <= headers or not frames:
        raise ValueError("Unsupported or empty AMC")
    return {"frames": frames, "fps": fps, "seconds": len(frames) / fps,
            "uncaptured_channels_ignored": sorted(UNCAPTURED)}


def main():
    root = Path(__file__).resolve().parents[3]
    source = root / "assets/motion-sources/cmu"
    skeleton = parse_asf((source / "79.asf").read_text())
    descriptions = {"79_10": "chopping onions", "79_13": "mixing batter",
                    "79_23": "putting on a jacket", "79_25": "moving heavy box", "79_42": "eating soup"}
    rows = []
    for key, description in descriptions.items():
        clip = parse_amc((source / (key + ".amc")).read_text(), skeleton, 60)
        rows.append({"id": key, "description": description, "frames": len(clip["frames"]), "fps": clip["fps"], "seconds": clip["seconds"]})
    print(json.dumps({"scope": "Original channel/unit preflight, not target animation or contact acceptance.",
                      "bones": len(skeleton["bones"]), "metres_per_source_unit": skeleton["metres_per_source_unit"], "clips": rows}, indent=2))


if __name__ == "__main__":
    main()
