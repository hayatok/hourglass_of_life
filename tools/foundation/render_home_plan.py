#!/usr/bin/env python3
"""Render the canonical home JSON and check static space, not game behavior.

Only Python's standard library is required. Internal door leaves are treated as
open for clearance checks; privacy, queuing, animation and daily life need their
own engine acceptance. The drawing never supplies a second coordinate source.
"""

from __future__ import annotations

import argparse
from collections import deque
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET


EPS = 1e-7
COLORS = {
    "living_kitchen_dining": "#f5e9ce", "bedroom": "#e7e5f3",
    "circulation": "#f0eee8", "entrance": "#ddd5c7",
    "toilet": "#e1eee6", "bathroom": "#dcecf3",
    "washroom_laundry": "#e4f0ef",
}


def inside(point, bounds, margin=0.0):
    x, z, width, depth = bounds
    return (x + margin - EPS <= point[0] <= x + width - margin + EPS
            and z + margin - EPS <= point[1] <= z + depth - margin + EPS)


def overlap(a, b):
    return (max(a[0], b[0]) < min(a[0] + a[2], b[0] + b[2]) - EPS
            and max(a[1], b[1]) < min(a[1] + a[3], b[1] + b[3]) - EPS)


def footprint(fixture):
    x, _, z = fixture["position"]
    width, _, depth = fixture["size"]
    return [x - width / 2, z - depth / 2, width, depth]


def expanded(bounds, radius):
    return [bounds[0] - radius, bounds[1] - radius,
            bounds[2] + 2 * radius, bounds[3] + 2 * radius]


def wall_sections(plan, wall):
    """Return actual solid segments after subtracting authored openings."""
    first, last = wall["start"], wall["end"]
    axis = 0 if abs(first[1] - last[1]) < EPS else 1
    fixed = first[1 - axis]
    low, high = sorted([first[axis], last[axis]])
    openings = []
    for door in plan["doors"]:
        if door["wall"] == wall["id"]:
            center = door["center"][0 if axis == 0 else 2]
            openings.append((center - door["width"] / 2,
                             center + door["width"] / 2))
    cursor = low
    result = []
    for begin, end in sorted(openings) + [(high, high)]:
        if begin > cursor + EPS:
            result.append(([cursor, fixed], [begin, fixed]) if axis == 0
                          else ([fixed, cursor], [fixed, begin]))
        cursor = max(cursor, end)
    return result


def wall_footprint(first, last, thickness):
    if abs(first[1] - last[1]) < EPS:
        return [min(first[0], last[0]), first[1] - thickness / 2,
                abs(last[0] - first[0]), thickness]
    return [first[0] - thickness / 2, min(first[1], last[1]),
            thickness, abs(last[1] - first[1])]


def check_plan(plan):
    errors = []

    def require(condition, message):
        if not condition:
            errors.append(message)

    house = plan["house"]
    radius = house["design_body_radius"]
    thickness = house["wall_thickness"]
    require(house["width"] == 12 and house["depth"] == 10,
            "The declared foundation home must remain 12m x 10m")
    rooms = {room["id"]: room for room in plan["rooms"]}
    zones = rooms | {zone["id"]: zone for zone in plan["external_zones"]}
    walls = {wall["id"]: wall for wall in plan["walls"]}
    fixtures = {item["id"]: item for item in plan["fixtures"]}
    require(len(rooms) == len(plan["rooms"]) and len(rooms) >= 8,
            "Room IDs must be unique and include real living/service spaces")
    require(len(walls) == len(plan["walls"]) and len(fixtures) == len(plan["fixtures"]),
            "Wall and fixture IDs must be unique")
    for room in rooms.values():
        bounds = room["bounds"]
        require(bounds[2] > 0 and bounds[3] > 0, f'{room["id"]}: zero-size room')
        require(inside(bounds[:2], house["bounds"], thickness)
                and inside([bounds[0] + bounds[2], bounds[1] + bounds[3]],
                           house["bounds"], thickness),
                f'{room["id"]}: clear bounds leave the external wall envelope')
    room_list = list(rooms.values())
    for index, room in enumerate(room_list):
        for other in room_list[index + 1:]:
            require(not overlap(room["bounds"], other["bounds"]),
                    f'{room["id"]}/{other["id"]}: overlapping room interiors')

    graph = {key: [] for key in zones}
    portals = {key: [] for key in zones}
    door_ids = set()
    for door in plan["doors"]:
        key = door["id"]
        require(key not in door_ids, f'{key}: duplicate portal ID')
        door_ids.add(key)
        require(door["wall"] in walls, f'{key}: missing wall')
        if door["wall"] not in walls:
            continue
        wall = walls[door["wall"]]
        first, last = wall["start"], wall["end"]
        require(abs(first[0] - last[0]) < EPS or abs(first[1] - last[1]) < EPS,
                f'{key}: this first floor plan requires axis-aligned walls')
        axis = 0 if door["axis"] == "x" else 1
        center = [door["center"][0], door["center"][2]]
        low, high = center[axis] - door["width"] / 2, center[axis] + door["width"] / 2
        require(abs(first[1 - axis] - last[1 - axis]) < EPS
                and abs(first[1 - axis] - center[1 - axis]) < EPS,
                f'{key}: opening center/axis does not match its wall')
        require(min(first[axis], last[axis]) - EPS <= low < high
                <= max(first[axis], last[axis]) + EPS,
                f'{key}: opening extends past wall endpoints')
        require(door["width"] > 2 * radius and 0 < door["height"] <= house["wall_height"],
                f'{key}: opening has no body clearance or invalid height')
        for room_id in [door["room_a"], door["room_b"]]:
            require(room_id in zones, f'{key}: nonexistent connected room {room_id}')
            if room_id not in zones:
                continue
            bounds = zones[room_id]["bounds"]
            normal = 1 - axis
            edge_match = any(abs(edge - center[normal]) <= EPS for edge in
                             [bounds[normal] - thickness / 2,
                              bounds[normal] + bounds[normal + 2] + thickness / 2])
            require(edge_match and bounds[axis] - EPS <= low
                    and high <= bounds[axis] + bounds[axis + 2] + EPS,
                    f'{key}: opening is not on the shared wall of {room_id}')
            approach = door["approaches"][room_id]
            require(inside([approach[0], approach[2]], bounds, radius),
                    f'{key}/{room_id}: no standing clearance at portal approach')
            portals[room_id].append([approach[0], approach[2]])
        if door["room_a"] in graph and door["room_b"] in graph:
            graph[door["room_a"]].append(door["room_b"])
            graph[door["room_b"]].append(door["room_a"])
        if door["kind"] == "sliding":
            pocket = door["pocket_interval"]
            require(abs(pocket[1] - pocket[0] - door["width"]) < EPS
                    and min(first[axis], last[axis]) <= pocket[0] < pocket[1]
                    <= max(first[axis], last[axis])
                    and (pocket[1] <= low + EPS or pocket[0] >= high - EPS),
                    f'{key}: sliding panel has no complete pocket beside opening')
        if door["kind"] == "hinged":
            require(all(not overlap(door["swing_clearance"], footprint(item))
                        for item in fixtures.values() if item.get("blocking", True)),
                    f'{key}: furniture blocks the declared door swing')
            require(all(not inside([point[0], point[2]],
                                   expanded(door["swing_clearance"], radius))
                        for point in door["approaches"].values()),
                    f'{key}: a waiting resident occupies the door swing envelope')

    def reachable(start, allowed):
        seen, queue = {start}, deque([start])
        while queue:
            for other in graph[queue.popleft()]:
                if other in allowed and other not in seen:
                    seen.add(other)
                    queue.append(other)
        return seen

    require(reachable("outside", set(zones)) == set(zones),
            "The room graph is disconnected from the front entrance")
    sanitary = {"outside", "entrance", "hall", "toilet", "washroom", "bathroom"}
    require(sanitary <= reachable("outside", sanitary),
            "Sanitary access requires crossing a living room or bedroom")

    for item in fixtures.values():
        key = item["id"]
        require(item["room"] in rooms, f'{key}: nonexistent fixture room')
        bounds = footprint(item)
        require(all(value > 0 for value in item["size"])
                and item["position"][1] >= 0
                and item["position"][1] + item["size"][1] <= house["wall_height"],
                f'{key}: invalid physical dimensions')
        room = rooms[item["room"]]["bounds"]
        require(inside(bounds[:2], room)
                and inside([bounds[0] + bounds[2], bounds[1] + bounds[3]], room),
                f'{key}: fixture leaves its room or occupies wall thickness')
        point = [item["interaction_point"][0], item["interaction_point"][2]]
        require(inside(point, room, radius), f'{key}: approach has no room-side body clearance')
        for other in fixtures.values():
            if other["room"] == item["room"] and other.get("blocking", True):
                require(not inside(point, expanded(footprint(other), radius)),
                        f'{key}: approach blocked by {other["id"]}')
        if "use_via" in item:
            require(item["use_via"] in fixtures, f'{key}: missing linked use fixture')
    solid_items = [item for item in fixtures.values() if item.get("blocking", True)]
    for index, item in enumerate(solid_items):
        for other in solid_items[index + 1:]:
            require(not overlap(footprint(item), footprint(other)),
                    f'{item["id"]}/{other["id"]}: overlapping solid fixtures')

    # Grid flood-fill per room checks every authored fixture approach against
    # portal landings, rather than accepting a connected room label alone.
    grid_step = 0.05
    for room_id, room in rooms.items():
        x, z, width, depth = room["bounds"]
        blocked = [expanded(footprint(item), radius) for item in solid_items
                   if item["room"] == room_id]
        valid = set()
        for iz in range(math.floor((depth - 2 * radius) / grid_step) + 1):
            for ix in range(math.floor((width - 2 * radius) / grid_step) + 1):
                point = [x + radius + ix * grid_step, z + radius + iz * grid_step]
                if not any(inside(point, rect) for rect in blocked):
                    valid.add((ix, iz))

        def cell(point):
            return (round((point[0] - x - radius) / grid_step),
                    round((point[1] - z - radius) / grid_step))

        seeds = [cell(point) for point in portals[room_id]]
        require(all(point in valid for point in seeds), f'{room_id}: blocked portal landing')
        if not seeds or seeds[0] not in valid:
            continue
        seen, queue = {seeds[0]}, deque([seeds[0]])
        while queue:
            cx, cz = queue.popleft()
            for other in [(cx + 1, cz), (cx - 1, cz), (cx, cz + 1), (cx, cz - 1)]:
                if other in valid and other not in seen:
                    seen.add(other)
                    queue.append(other)
        require(all(point in seen for point in seeds), f'{room_id}: portal landings disconnected by furniture')
        for item in fixtures.values():
            if item["room"] == room_id:
                approach = item["interaction_point"]
                require(cell([approach[0], approach[2]]) in seen,
                        f'{item["id"]}: approach unreachable from room portal')

    solid_walls = [expanded(wall_footprint(first, last, thickness), radius)
                   for wall in walls.values() for first, last in wall_sections(plan, wall)]
    blocked_world = solid_walls + [expanded(footprint(item), radius) for item in solid_items]
    for flow in plan["circulation"]:
        for first, last in zip(flow["points"], flow["points"][1:]):
            samples = max(1, math.ceil(math.dist(first, last) / 0.02))
            for index in range(samples + 1):
                point = [first[axis] + (last[axis] - first[axis]) * index / samples for axis in [0, 1]]
                require(not any(inside(point, rect) for rect in blocked_world),
                        f'{flow["id"]}: illustrated circulation intersects a solid body envelope')
                if errors and errors[-1].startswith(flow["id"] + ":"):
                    break

    require({row["id"] for row in plan["residents"]} == {"nagisa", "ryo", "rin"},
            "The three original family IDs must be explicit")
    beds = [fixtures[row["bed"]] for row in plan["residents"]]
    require(len({bed["id"] for bed in beds}) == 3
            and all(bed["type"] == "bed" and bed["owner"] == row["id"]
                    and bed["room"] == row["bedroom"] for bed, row in zip(beds, plan["residents"])),
            "Each family member needs a distinct assigned bed in the correct bedroom")
    require(len({row["dining_seat"] for row in plan["residents"]}) == 3,
            "Three residents must not share one dining reservation")
    if errors:
        raise ValueError("Static floor-plan errors:\n- " + "\n- ".join(dict.fromkeys(errors)))
    return {"rooms": len(rooms), "walls": len(walls), "doors": len(door_ids),
            "fixtures": len(fixtures), "residents": len(beds),
            "body_radius_m": radius, "navigation_grid_m": grid_step,
            "scope": "Static clearance and connectivity with doors open; no engine or behavior acceptance"}


def render(plan, output):
    scale, left, top = 78, 80, 85
    ET.register_namespace("", "http://www.w3.org/2000/svg")
    namespace = "http://www.w3.org/2000/svg"

    def node(parent, tag, **attrs):
        return ET.SubElement(parent, f"{{{namespace}}}{tag}",
                             {key.replace("_", "-"): str(value) for key, value in attrs.items()})

    def text(parent, x, y, value, **attrs):
        item = node(parent, "text", x=x, y=y, **attrs)
        item.text = value
        return item

    def point(p):
        return left + p[0] * scale, top + p[1] * scale

    def line(parent, first, last, **attrs):
        x1, y1 = point(first); x2, y2 = point(last)
        return node(parent, "line", x1=x1, y1=y1, x2=x2, y2=y2, **attrs)

    svg = ET.Element(f"{{{namespace}}}svg", {"width":"1450", "height":"1160", "viewBox":"0 0 1450 1160", "role":"img"})
    node(svg, "title").text = "小川家 12m×10m 平屋の初期間取り"
    node(svg, "desc").text = "JSON正本から生成。中央廊下で寝室とLDK、水回りを分ける8室。扉の開口と接近点、家具外形、開扉時の人動線を表示。実生活機能の完成を示すものではない。"
    node(svg, "rect", width=1450, height=1160, fill="#faf9f5")
    group = node(svg, "g", font_family="Hiragino Sans, Noto Sans CJK JP, Yu Gothic, sans-serif", fill="#28313b")
    text(group, 80, 32, "小川家  |  12m × 10m・平屋", font_size=24, font_weight=700)
    text(group, 80, 54, "初期実装用の空間設計  ·  内法寸法 / 壁厚 0.20m / 南側玄関", font_size=13, fill="#606872")
    defs = node(svg, "defs")
    for key, color in [("approach", "#347c9a")] + [(flow["id"], flow["color"]) for flow in plan["circulation"]]:
        marker = node(defs, "marker", id="arrow_"+key, markerWidth=6, markerHeight=6,
                      refX=5, refY=3, orient="auto", markerUnits="strokeWidth")
        node(marker, "path", d="M0,0 L6,3 L0,6 Z", fill=color)
    for zone in plan["external_zones"]:
        x, y = point(zone["bounds"][:2])
        node(group, "rect", x=x, y=y, width=zone["bounds"][2]*scale,
             height=zone["bounds"][3]*scale, fill="#e7e3d8", stroke="#b6b0a3", stroke_dasharray="4 4")
    for room in plan["rooms"]:
        x, y = point(room["bounds"][:2])
        node(group, "rect", x=x, y=y, width=room["bounds"][2]*scale,
             height=room["bounds"][3]*scale, fill=COLORS.get(room["type"], "#e7e5f3"))
    for flow in plan["circulation"]:
        points = " ".join(f"{point(p)[0]:.2f},{point(p)[1]:.2f}" for p in flow["points"])
        node(group, "polyline", points=points, fill="none", stroke=flow["color"],
             stroke_width=3, stroke_dasharray="7 5", stroke_opacity=".8", marker_end="url(#arrow_"+flow["id"]+")")
    for wall in plan["walls"]:
        for first, last in wall_sections(plan, wall):
            line(group, first, last, stroke="#4d5661", stroke_width=plan["house"]["wall_thickness"]*scale, stroke_linecap="butt")
    for door in plan["doors"]:
        cx, _, cz = door["center"]; half = door["width"]/2
        first, last = ([cx-half, cz], [cx+half, cz]) if door["axis"] == "x" else ([cx, cz-half], [cx, cz+half])
        line(group, first, last, stroke="#55768b", stroke_width=1.3, stroke_dasharray="3 3")
        if door["kind"] == "sliding":
            low, high = door["pocket_interval"]
            p1, p2 = ([low, cz], [high, cz]) if door["axis"] == "x" else ([cx, low], [cx, high])
            line(group, p1, p2, stroke="#d3e0e7", stroke_width=4)
        elif door["kind"] == "hinged":
            hinge = [door["hinge"][0], door["hinge"][2]]
            opened = [door["open_end"][0], door["open_end"][2]]
            closed = last
            line(group, hinge, opened, stroke="#55768b", stroke_width=2)
            a = [closed[0]-hinge[0], closed[1]-hinge[1]]
            b = [opened[0]-hinge[0], opened[1]-hinge[1]]
            sweep = 1 if a[0]*b[1]-a[1]*b[0]>0 else 0
            sx, sy = point(closed); ex, ey = point(opened)
            node(group, "path", d=f"M{sx},{sy} A{door['width']*scale},{door['width']*scale} 0 0 {sweep} {ex},{ey}",
                 fill="none", stroke="#55768b", stroke_width=1, stroke_dasharray="3 3")
        px, py = point([cx, cz])
        text(group, px + (10 if door["axis"] == "z" else 0), py - 9, door["id"],
             font_size=11, fill="#31536a", text_anchor="start" if door["axis"]=="z" else "middle",
             paint_order="stroke", stroke="#faf9f5", stroke_width=3)
    for index, fixture in enumerate(plan["fixtures"], 1):
        key = f"F{index:02d}"
        rect = footprint(fixture); x, y = point(rect[:2])
        color = "#c5dfe5" if fixture["room"] in ["toilet", "bathroom", "washroom"] else "#dac8ae"
        if fixture["type"] == "bed": color="#c2cde0"
        node(group, "rect", x=x, y=y, width=rect[2]*scale, height=rect[3]*scale,
             rx=3, fill=color, stroke="#807b74", stroke_width=1,
             stroke_dasharray="4 3" if not fixture.get("blocking", True) else "none")
        cx, cy = point([fixture["position"][0], fixture["position"][2]])
        text(group, cx, cy+4, key, text_anchor="middle", font_size=11, font_weight=600,
             paint_order="stroke", stroke=color, stroke_width=2)
        approach = [fixture["interaction_point"][0], fixture["interaction_point"][2]]
        ax, ay = point(approach)
        node(group, "circle", cx=ax, cy=ay, r=3.2, fill="#347c9a", stroke="#fff", stroke_width=1)
        angle = math.radians(fixture["facing"])
        facing = [approach[0]+.28*math.sin(angle), approach[1]+.28*math.cos(angle)]
        line(group, approach, facing, stroke="#347c9a", stroke_width=1.2, marker_end="url(#arrow_approach)")
    for room in plan["rooms"]:
        x, y = point(room["label_point"])
        size = 13 if room["id"] in ["hall", "entrance", "toilet", "washroom", "bathroom"] else 16
        text(group, x, y, room["label"], text_anchor="middle", font_size=size, font_weight=650,
             paint_order="stroke", stroke=COLORS.get(room["type"], "#e7e5f3"), stroke_width=5)
        area = room["bounds"][2]*room["bounds"][3]
        text(group, x, y+16, f"{area:.1f} m²", text_anchor="middle", font_size=11, fill="#616873")
    line(group, [0, -.22], [12, -.22], stroke="#757d84", stroke_width=1)
    for x in [0,12]: line(group, [x,-.32], [x,-.12], stroke="#757d84", stroke_width=1)
    text(group, left+6*scale, top-21, "12.00 m", text_anchor="middle", font_size=12)
    line(group, [-.36,0], [-.36,10], stroke="#757d84", stroke_width=1)
    text(group, left-42, top+5*scale, "10.00 m", text_anchor="middle", font_size=12,
         transform=f"rotate(-90 {left-42} {top+5*scale})")
    text(group, left+12*scale+12, top-15, "北 ↑", font_size=14, font_weight=700)
    text(group, *point([6.5,11.65]), "南側の通りへ", font_size=12, text_anchor="middle", fill="#606872")
    legend_x = 1070
    text(group, legend_x, 102, "家具・設備", font_size=17, font_weight=700)
    for index, fixture in enumerate(plan["fixtures"],1):
        text(group, legend_x, 122+(index-1)*21, f"F{index:02d}  {fixture['label']}", font_size=13)
    base = 122+len(plan["fixtures"])*21+20
    text(group, legend_x, base, "扉・開口", font_size=17, font_weight=700)
    for index, door in enumerate(plan["doors"]):
        text(group, legend_x, base+24+index*21,
             f"{door['id']}  {door['label']}  {door['width']:.2f}m", font_size=12)
    notes = ["青点＋矢印 = 接近位置と本人の向き", "扉点線 = 閉扉位置 / 弧 = 開閉の余白",
             "引戸の薄線 = 戸袋。家具寸法は外形。", "動線は開扉・入室許可がある場合の設計。",
             "生活行動・扉制御・姿勢の完成証拠ではない。"]
    for index, note in enumerate(notes):
        text(group, legend_x, base+212+index*19, note, font_size=11, fill="#606872")
    for index, flow in enumerate(plan["circulation"]):
        y = 1030+index*22
        node(group, "line", x1=80, y1=y-4, x2=120, y2=y-4, stroke=flow["color"], stroke_width=3, stroke_dasharray="7 5")
        text(group, 134, y, flow["label"], font_size=12)
    output.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(svg).write(output, encoding="utf-8", xml_declaration=True)
    with output.open("ab") as file:
        file.write(b"\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=Path("data/foundation/ogawa-home.json"))
    parser.add_argument("--output", type=Path, default=Path("docs/design/ogawa-home-layout.svg"))
    args = parser.parse_args()
    plan = json.loads(args.input.read_text(encoding="utf-8"))
    summary = check_plan(plan)
    render(plan, args.output)
    print(json.dumps({"output":str(args.output), "static_geometry":summary}, ensure_ascii=False))


if __name__ == "__main__":
    main()
