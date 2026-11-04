#!/usr/bin/env python3
"""Validate and draw authored household plans; not engine or gameplay acceptance.

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
import sys


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
    require(house["width"] > 0 and house["depth"] > 0, "House dimensions must be positive")
    rooms = {room["id"]: room for room in plan["rooms"]}
    zones = rooms | {zone["id"]: zone for zone in plan["external_zones"]}
    walls = {wall["id"]: wall for wall in plan["walls"]}
    fixtures = {item["id"]: item for item in plan["fixtures"]}
    require(len(rooms) == len(plan["rooms"]) and len(rooms) > 0,
            "Room IDs must be unique and nonempty")
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

    # Public exterior surfaces can meet without an invented wall/door. Actual
    # body support across their union is checked by design_paths below.
    for index, first in enumerate(plan['external_zones']):
        for second in plan['external_zones'][index+1:]:
            a, b = first['bounds'], second['bounds']
            dx = min(a[0]+a[2], b[0]+b[2])-max(a[0], b[0])
            dz = min(a[1]+a[3], b[1]+b[3])-max(a[1], b[1])
            if dx >= -EPS and dz >= -EPS and max(dx, dz) > 2*radius:
                graph[first['id']].append(second['id'])
                graph[second['id']].append(first['id'])
    require(reachable("outside", set(zones)) == set(zones),
            "The room graph is disconnected from the front entrance")
    sanitary = {"outside"} | {r["id"] for r in rooms.values() if r["type"] in ["entrance", "circulation", "toilet", "washroom_laundry", "bathroom"]}
    require(sanitary <= reachable("outside", sanitary),
            "Sanitary access requires crossing a living room or bedroom")

    for item in fixtures.values():
        key = item["id"]
        require(item["room"] in zones, f'{key}: nonexistent fixture room or outdoor zone')
        bounds = footprint(item)
        require(all(value > 0 for value in item["size"])
                and item["position"][1] >= 0
                and item["position"][1] + item["size"][1] <= house["wall_height"],
                f'{key}: invalid physical dimensions')
        if item["room"] not in zones:
            continue
        room = zones[item["room"]]["bounds"]
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
    for room_id, room in zones.items():
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

    members = {row["id"] for row in plan["residents"]}
    require(len(members) == len(plan["residents"]) and len(members) > 0, "Resident IDs must be explicit and distinct")
    beds = [fixtures[row["bed"]] for row in plan["residents"]]
    require(len({bed["id"] for bed in beds}) == len(members)
            and all(bed["type"] == "bed" and bed["owner"] == row["id"]
                    and bed["room"] == row["bedroom"] for bed, row in zip(beds, plan["residents"])),
            "Each family member needs a distinct assigned bed in the correct bedroom")
    require(len({row["dining_seat"] for row in plan["residents"]}) == len(members),
            "Residents must not share one dining reservation")
    errors.extend(_authored_contract_errors(plan))
    if errors:
        raise ValueError("Static floor-plan errors:\n- " + "\n- ".join(dict.fromkeys(errors)))
    return {"rooms": len(rooms), "walls": len(walls), "doors": len(door_ids),
            "fixtures": len(fixtures), "residents": len(beds),
            "body_radius_m": radius, "navigation_grid_m": grid_step,
            "scope": "Static clearance and connectivity with doors open; no engine or behavior acceptance"}



def _authored_contract_errors(plan):
    """Authoring constraints shared with the current spatial schema.

    These checks do not execute HomeNavigation, door animation or a person.
    The grid below is an independent design aid, never engine route acceptance.
    """
    errors = []
    house = plan['house']
    thick = house['wall_thickness']
    rooms = {r['id']: r for r in plan['rooms']}
    zones = rooms | {z['id']: z for z in plan['external_zones']}
    fixtures = {f['id']: f for f in plan['fixtures']}
    members = {r['id'] for r in plan['residents']}
    scopes = {'household', 'parents', 'resident', 'exclusive_when_occupied', 'exclusive_while_changing'}
    required_types = {'fridge', 'sink', 'stove', 'prep', 'dining_table', 'bed', 'storage',
                      'toilet', 'washbasin', 'bath', 'shower', 'washer', 'changing_space'}
    missing = required_types - {f['type'] for f in fixtures.values()}
    if missing:
        errors.append('Missing real household equipment: '+', '.join(sorted(missing)))
    if not {'entrance', 'circulation', 'toilet', 'bathroom', 'washroom_laundry'} <= {r['type'] for r in rooms.values()}:
        errors.append('Entrance, hall and independent sanitary spaces are required')
    for room in rooms.values():
        allowed = room.get('allowed_residents', [])
        if not allowed or not set(allowed) <= members or len(allowed) != len(set(allowed)):
            errors.append(room['id']+': allowed residents do not match household membership')
        if room.get('private_scope') not in scopes or not isinstance(room.get('occupancy_limit'), int) or room['occupancy_limit'] < 1:
            errors.append(room['id']+': missing admission/occupancy contract')
        if room['type'] in ['toilet', 'bathroom'] and (room['occupancy_limit'] != 1 or room['private_scope'] != 'exclusive_when_occupied'):
            errors.append(room['id']+': sanitary privacy must be exclusive')
        # A rectangular clear room must have a real enclosing wall along every
        # edge. Openings subtract wall pieces later; a room label alone cannot
        # supply a partition or invisible boundary.
        x, z, w, d = room['bounds']
        edges = [(0, z-thick/2, x, x+w), (0, z+d+thick/2, x, x+w),
                 (1, x-thick/2, z, z+d), (1, x+w+thick/2, z, z+d)]
        for axis, fixed, low, high in edges:
            intervals = []
            for wall in plan['walls']:
                a, b = wall['start'], wall['end']
                if abs(a[1-axis]-fixed) < EPS and abs(b[1-axis]-fixed) < EPS:
                    intervals.append(sorted([a[axis], b[axis]]))
            cursor = low
            for a, b in sorted(intervals):
                if a > cursor+EPS:
                    break
                if b >= cursor-EPS:
                    cursor = max(cursor, b)
            if cursor < high-EPS:
                errors.append(room['id']+': room edge has no complete authored wall')
    intervals = {}
    for door in plan['doors']:
        axis = 0 if door['axis'] == 'x' else 1
        c = door['center'][0 if axis == 0 else 2]
        opening = [c-door['width']/2, c+door['width']/2]
        intervals.setdefault(door['wall'], []).append((door['id'], 'opening', opening))
        if door['kind'] == 'sliding':
            pocket = door['pocket_interval']
            intervals[door['wall']].append((door['id'], 'pocket', pocket))
            for key in [door['room_a'], door['room_b']]:
                bounds = zones[key]['bounds']
                if pocket[0] < bounds[axis]-EPS or pocket[1] > bounds[axis]+bounds[axis+2]+EPS:
                    errors.append(door['id']+': pocket crosses a connected room corner')
        if door['kind'] == 'hinged':
            hinge, end = door['hinge'], door['open_end']
            if abs(math.dist([hinge[0], hinge[2]], [end[0], end[2]])-door['width']) > EPS:
                errors.append(door['id']+': hinge/open endpoint changes leaf width')
            closed_delta = [door['center'][0]-hinge[0], door['center'][2]-hinge[2]]
            open_delta = [end[0]-hinge[0], end[2]-hinge[2]]
            if abs(sum(a*b for a, b in zip(closed_delta, open_delta))) > EPS:
                errors.append(door['id']+': open leaf is not a quarter turn')
            swing = door['swing_clearance']
            bounds = zones[door['swing_room']]['bounds']
            if not inside(swing[:2], expanded(bounds, thick/2)) or not inside([swing[0]+swing[2], swing[1]+swing[3]], expanded(bounds, thick/2)):
                errors.append(door['id']+': leaf swing leaves its declared room')
    for rows in intervals.values():
        for index, (id_a, kind_a, a) in enumerate(rows):
            for id_b, kind_b, b in rows[index+1:]:
                if id_a != id_b and max(a[0], b[0]) < min(a[1], b[1])-EPS:
                    errors.append(f'{id_a}/{id_b}: {kind_a}/{kind_b} overlap within one wall')
    for resident in plan['residents']:
        id = resident['id']
        room = rooms[resident['bedroom']]
        seat = fixtures[resident['dining_seat']]
        if id not in room['allowed_residents'] or seat['type'] != 'dining_seat' or seat['owner'] != id:
            errors.append(id+': bedroom admission or assigned dining seat is inconsistent')
    volumes = {v['id']:v for v in house.get('volumes',[])}
    for room in rooms.values():
        if not volumes:
            continue
        volume = volumes.get(room.get('volume'))
        if not volume:
            errors.append(room['id']+': missing actual building volume')
            continue
        pieces = volume.get('footprint',[volume['bounds']] if 'bounds' in volume else [])
        bounds = room['bounds']
        if not any(inside(bounds[:2],p) and inside([bounds[0]+bounds[2],bounds[1]+bounds[3]],p) for p in pieces):
            errors.append(room['id']+': room leaves its actual building footprint')
    for fixture in fixtures.values():
        for reference in ['serves', 'use_via', 'support_fixture']:
            if reference in fixture and (fixture[reference] not in fixtures or fixtures[fixture[reference]]['room'] != fixture['room']):
                errors.append(fixture['id']+': invalid same-room '+reference)
        if fixture.get('private', False) and fixture['owner'] in members and fixture['owner'] not in zones[fixture['room']].get('allowed_residents', []):
            errors.append(fixture['id']+': owner cannot enter the fixture room')
    errors.extend(_art_intent_errors(plan))
    return errors


def _art_intent_errors(plan):
    """Validate spatial intent, not daylight, ventilation or art quality."""
    errors = []
    walls = {w['id']: w for w in plan['walls']}
    rooms = {r['id']: r for r in plan['rooms']}
    roof = plan['house'].get('roof', {})
    color = roof.get('color', '')
    if roof.get('shape') != 'gable' or roof.get('ridge_axis') not in ['x', 'z'] or not 0 < roof.get('rise', 0) < 5 or not 0 < roof.get('eaves', 0) < 1:
        errors.append('Roof needs a real gable orientation, rise and eaves')
    if len(color) != 7 or not color.startswith('#') or any(c not in '0123456789abcdefABCDEF' for c in color[1:]):
        errors.append('Roof color must be #RRGGBB')
    seen = set()
    for win in plan.get('windows', []):
        id = win['id']
        if id in seen:
            errors.append(id+': duplicate window ID')
        seen.add(id)
        if win['wall'] not in walls or win['room'] not in rooms:
            errors.append(id+': missing window room or wall')
            continue
        wall, room = walls[win['wall']], rooms[win['room']]
        a, b, c, bounds = wall['start'], wall['end'], win['center'], room['bounds']
        axis = 0 if abs(a[1]-b[1]) < EPS else 1
        horizontal = c[0 if axis == 0 else 2]
        fixed = c[2 if axis == 0 else 0]
        low, high = horizontal-win['width']/2, horizontal+win['width']/2
        sill, head = c[1]-win['height']/2, c[1]+win['height']/2
        if not (win['width'] > 0 and win['height'] > 0 and sill > 0 and head <= wall.get('height',plan['house']['wall_height'])+EPS):
            errors.append(id+': sill/head or window dimensions leave the wall')
        if abs(fixed-a[1-axis]) > EPS or low < min(a[axis], b[axis])-EPS or high > max(a[axis], b[axis])+EPS:
            errors.append(id+': window center/span leaves its authored wall')
        normal = 1-axis
        possible_edges = [bounds[normal]-plan['house']['wall_thickness']/2,
                          bounds[normal]+bounds[normal+2]+plan['house']['wall_thickness']/2]
        if not any(abs(edge-fixed) < EPS for edge in possible_edges) or low < bounds[axis]-EPS or high > bounds[axis]+bounds[axis+2]+EPS:
            errors.append(id+': window crosses a room corner or has the wrong wall')
        inward = [win['inward'][0], win['inward'][2]]
        room_center = [bounds[0]+bounds[2]/2, bounds[1]+bounds[3]/2]
        if abs(math.hypot(*inward)-1) > EPS or abs(inward[axis]) > EPS or sum((room_center[j]-[c[0],c[2]][j])*inward[j] for j in [0,1]) <= 0:
            errors.append(id+': inward normal does not face the room')
        if not isinstance(win.get('frosted'), bool):
            errors.append(id+': frosted must be explicit')
        if win['source'] == 'exterior_daylight' and not wall.get('exterior', False):
            errors.append(id+': interior borrowed light cannot be called an exterior window')
        if win['source'] == 'borrowed_light' and (not win['frosted'] or win.get('ventilation') != 'mechanical_extract_required'):
            errors.append(id+': interior sanitary glazing needs privacy and an explicit ventilation limitation')
        for door in plan['doors']:
            if door['wall'] != win['wall']:
                continue
            dc = door['center'][0 if axis == 0 else 2]
            if max(low, dc-door['width']/2) < min(high, dc+door['width']/2)-EPS and sill < door['height']-EPS:
                errors.append(id+'/'+door['id']+': window overlaps a door opening')
        for other in plan.get('windows', []):
            if other['id'] >= id or other['wall'] != win['wall']:
                continue
            oc = other['center'][0 if axis == 0 else 2]
            if max(low, oc-other['width']/2) < min(high, oc+other['width']/2)-EPS and max(sill,other['center'][1]-other['height']/2) < min(head,other['center'][1]+other['height']/2)-EPS:
                errors.append(id+'/'+other['id']+': windows overlap')
    for room in rooms.values():
        wins = [w for w in plan.get('windows', []) if w['room'] == room['id']]
        if room['type'] in ['bedroom', 'living_kitchen_dining'] and not any(w['source'] == 'exterior_daylight' for w in wins):
            errors.append(room['id']+': bedroom/LDK needs an authored exterior window')
        if room['type'] in ['toilet', 'bathroom'] and not any(w['frosted'] and w['center'][1]-w['height']/2 >= 1.8 for w in wins):
            errors.append(room['id']+': sanitary glazing must be high and frosted')
    for light in plan.get('ceiling_lights', []):
        if light['kind'] != 'pendant' or not 0 < light['at'][1] < plan['house']['wall_height'] or not any(inside([light['at'][0],light['at'][2]],r['bounds']) for r in rooms.values()):
            errors.append('Ceiling light leaves the room/ceiling envelope')
    if not plan.get('ceiling_lights'):
        errors.append('A dining ceiling light is required')
    return errors


def _segment_rect(first, last, rect):
    low, high = 0.0, 1.0
    for axis in [0, 1]:
        delta = last[axis]-first[axis]
        if abs(delta) < EPS:
            if first[axis] < rect[axis]-EPS or first[axis] > rect[axis]+rect[axis+2]+EPS:
                return False
        else:
            a = (rect[axis]-first[axis])/delta
            b = (rect[axis]+rect[axis+2]-first[axis])/delta
            low, high = max(low, min(a, b)), min(high, max(a, b))
            if low > high+EPS:
                return False
    return True


def design_paths(plan):
    """Static body-envelope flood fill, with open leaves and no moving people."""
    radius = plan['house']['design_body_radius']
    thickness = plan['house']['wall_thickness']
    step = .1
    floors = [z['bounds'] for z in plan['rooms']+plan['external_zones']]
    for door in plan['doors']:
        cx, _, cz = door['center']
        w, d = (door['width'],thickness) if door['axis']=='x' else (thickness,door['width'])
        floors.append([cx-w/2,cz-d/2,w,d])
    solids = [expanded(wall_footprint(a, b, thickness), radius)
              for wall in plan['walls'] for a, b in wall_sections(plan, wall)]
    solids += [expanded(footprint(f), radius) for f in plan['fixtures'] if f.get('blocking', True)]
    xmin, zmin = min(f[0] for f in floors), min(f[1] for f in floors)
    xmax, zmax = max(f[0]+f[2] for f in floors), max(f[1]+f[3] for f in floors)

    def on_floor(point):
        return all(any(inside([point[0]+dx, point[1]+dz], f) for f in floors)
                   for dx, dz in [(0, 0), (-radius, -radius), (-radius, radius), (radius, -radius), (radius, radius)])

    def point(cell):
        return [xmin+cell[0]*step, zmin+cell[1]*step]

    free = set()
    for iz in range(math.ceil((zmax-zmin)/step)+1):
        for ix in range(math.ceil((xmax-xmin)/step)+1):
            p = point((ix, iz))
            if on_floor(p) and not any(inside(p, s) for s in solids):
                free.add((ix, iz))

    def segment_clear(a, b):
        if any(_segment_rect(a, b, s) for s in solids):
            return False
        # A 1cm sample adds a conservative floor-envelope check at the house /
        # porch join; all exact rectangular obstacle intersections are above.
        count = max(1, math.ceil(math.dist(a, b)/.01))
        return all(on_floor([a[j]+(b[j]-a[j])*i/count for j in [0, 1]]) for i in range(count+1))

    def nearest(p, allowed):
        if not on_floor(p) or any(inside(p, s) for s in solids):
            return None
        cx, cz = round((p[0]-xmin)/step), round((p[1]-zmin)/step)
        candidates = [(x, z) for x in range(cx-2, cx+3) for z in range(cz-2, cz+3)
                      if (x, z) in allowed]
        candidates.sort(key=lambda c: math.dist(point(c), p))
        return next((c for c in candidates if segment_clear(p, point(c))), None)

    def flood(start, allowed):
        previous, queue = {start: None}, deque([start])
        while queue:
            cx, cz = queue.popleft()
            for other in [(cx-1, cz), (cx+1, cz), (cx, cz-1), (cx, cz+1)]:
                if other in allowed and other not in previous:
                    previous[other] = (cx, cz)
                    queue.append(other)
        return previous

    connection = plan['house']['street_connection']['approach']
    origin = [connection[0], connection[2]]
    result = {'grid_m': step, 'body_radius_m': radius, 'resident_access': {}, 'illustrations': []}
    for resident in plan['residents']:
        id = resident['id']
        forbidden = [r['bounds'] for r in plan['rooms'] if id not in r['allowed_residents']]
        allowed = {cell for cell in free if not any(inside(point(cell), b) for b in forbidden)}
        first = nearest(origin, allowed)
        if first is None:
            raise ValueError(id+': street connection cannot join the static body grid')
        previous = flood(first, allowed)
        targets = [f for f in plan['fixtures'] if f['room'] == 'outside' or
                   (id in next(r['allowed_residents'] for r in plan['rooms'] if r['id'] == f['room'])
                    and (not f.get('private', False) or f['owner'] not in {p['id'] for p in plan['residents']} or f['owner'] == id))]
        for fixture in targets:
            p = [fixture['interaction_point'][0], fixture['interaction_point'][2]]
            last = nearest(p, allowed)
            if last is None or last not in previous:
                raise ValueError(id+'/'+fixture['id']+': unreachable on static whole-house body grid')
            if fixture['id'] == resident['bed']:
                cells = []
                while last is not None:
                    cells.append(last)
                    last = previous[last]
                # Reduce only collinear samples, not collision geometry.
                path = [origin] + [point(c) for c in reversed(cells)] + [p]
                simplified = []
                for point_value in path:
                    while len(simplified) > 1:
                        a, b = simplified[-2:]
                        cross = (b[0]-a[0])*(point_value[1]-b[1])-(b[1]-a[1])*(point_value[0]-b[0])
                        if abs(cross) >= EPS or not segment_clear(a, point_value):
                            break
                        simplified.pop()
                    simplified.append(point_value)
                result['illustrations'].append({'resident': id, 'points': simplified})
        result['resident_access'][id] = [f['id'] for f in targets]
    return result


def render(plan, output, paths):
    """Generate the diagram directly from plan coordinates, without an engine."""
    ns = 'http://www.w3.org/2000/svg'
    ET.register_namespace('', ns)
    scale, left, top, legend = min(70,875/plan['house']['width']), 65, 95, 1010
    notes_height = sum(17*math.ceil(len(f)/48)+12 for f in plan['house']['design_features'])
    notes_top = max(top+(plan['house']['depth']+2.4)*scale+42, 970)
    height = math.ceil(max(notes_top+notes_height+55,
                           280+19*(len(plan['fixtures'])+len(plan['doors'])+len(plan.get('windows',[])))))
    width = 1560
    root = ET.Element('{'+ns+'}svg', {'width':str(width), 'height':str(height),
                                    'viewBox':f'0 0 {width} {height}', 'role':'img'})
    def node(parent, tag, **attrs):
        return ET.SubElement(parent, '{'+ns+'}'+tag,
                             {k.replace('_','-'):str(v) for k,v in attrs.items()})
    def text(x, y, value, **attrs):
        el = node(group, 'text', x=x, y=y, **attrs);el.text=value
    def pt(p):
        return [left+p[0]*scale, top+p[1]*scale]
    def line(a,b,**attrs):
        a,b=pt(a),pt(b)
        node(group,'line',x1=a[0],y1=a[1],x2=b[0],y2=b[1],**attrs)
    node(root,'title').text=plan['house']['label']+' — 実寸の初期間取り'
    node(root,'desc').text='JSON正本の部屋・壁開口・家具外形・接近点。開扉時の静的な候補動線であり、3D・実経路・日常生活の受入れを示さない。'
    node(root,'rect',width=width,height=height,fill='#faf8f1')
    group=node(root,'g',font_family='Hiragino Sans, Noto Sans CJK JP, Yu Gothic, sans-serif',fill='#473f32')
    house=plan['house']
    text(65,35,f"{house['label']}  |  {house['width']:g}m × {house['depth']:g}m・平屋",font_size=24,font_weight=700)
    text(65,60,'開扉・無人時の設計確認  ／  壁厚0.20m・体幅0.48m  ／  Godotの3D・経路・生活は未受入',font_size=14,fill='#75634b')
    for zone in plan['external_zones']:
        x,y=pt(zone['bounds'][:2]);b=zone['bounds']
        node(group,'rect',x=x,y=y,width=b[2]*scale,height=b[3]*scale,fill='#dfdfcf',stroke='#aaa594',stroke_dasharray='4 4')
    for room in plan['rooms']:
        x,y=pt(room['bounds'][:2]);b=room['bounds']
        node(group,'rect',x=x,y=y,width=b[2]*scale,height=b[3]*scale,fill=COLORS.get(room['type'],'#e4e0cf'))
    for index,route in enumerate(paths['illustrations']):
        value=' '.join(f'{pt(p)[0]:.2f},{pt(p)[1]:.2f}' for p in route['points'])
        node(group,'polyline',points=value,fill='none',stroke=['#b37044','#548981','#766c9b'][index%3],stroke_width=2,stroke_dasharray='5 5',stroke_opacity='.7')
    for wall in plan['walls']:
        for a,b in wall_sections(plan,wall):
            line(a,b,stroke='#665b4e',stroke_width=house['wall_thickness']*scale,stroke_linecap='butt')
    for door in plan['doors']:
        x,_,z=door['center'];w=door['width']/2
        a,b=([x-w,z],[x+w,z]) if door['axis']=='x' else ([x,z-w],[x,z+w])
        line(a,b,stroke='#367a86',stroke_width=1.3,stroke_dasharray='3 3')
        if door['kind']=='sliding':
            low,high=door['pocket_interval']
            a,b=([low,z],[high,z]) if door['axis']=='x' else ([x,low],[x,high])
            line(a,b,stroke='#a0c3c8',stroke_width=4)
        elif door['kind']=='hinged':
            a=[door['hinge'][0],door['hinge'][2]];b=[door['open_end'][0],door['open_end'][2]]
            line(a,b,stroke='#367a86',stroke_width=2)
            r=door['swing_clearance'];px,py=pt(r[:2])
            node(group,'rect',x=px,y=py,width=r[2]*scale,height=r[3]*scale,fill='none',stroke='#9ebfc3',stroke_dasharray='3 3')
        px,py=pt([x,z]);text(px+8,py-7,door['id'],font_size=10,fill='#367a86',paint_order='stroke',stroke='#faf8f1',stroke_width=3)
    walls={w['id']:w for w in plan['walls']}
    for win in plan.get('windows',[]):
        x,y,z=win['center'];half=win['width']/2
        wall=walls[win['wall']]
        horizontal=abs(wall['start'][1]-wall['end'][1])<EPS
        a,b=([x-half,z],[x+half,z]) if horizontal else ([x,z-half],[x,z+half])
        line(a,b,stroke='#d9edf0' if win['frosted'] else '#a4d2df',stroke_width=6)
        line(a,b,stroke='#367a86',stroke_width=1,stroke_dasharray='2 2' if win['source']=='borrowed_light' else 'none')
        px,py=pt([x,z]);text(px+7,py-8,win['id'],font_size=9,fill='#367a86',paint_order='stroke',stroke='#faf8f1',stroke_width=3)
    for i,f in enumerate(plan['fixtures'],1):
        r=footprint(f);x,y=pt(r[:2])
        color='#b9c9d5' if f['type']=='bed' else '#c4d6cf' if f['room'] in ['bathroom','toilet','washroom'] else '#d5bc94'
        node(group,'rect',x=x,y=y,width=r[2]*scale,height=r[3]*scale,rx=2,fill=color,stroke='#8f806c',stroke_width=1,
             stroke_dasharray='4 3' if not f.get('blocking',True) else 'none')
        px,py=pt([f['position'][0],f['position'][2]])
        text(px,py+3,f'F{i:02d}',font_size=9,text_anchor='middle',font_weight=650)
        approach=[f['interaction_point'][0],f['interaction_point'][2]]
        ax,az=pt(approach);node(group,'circle',cx=ax,cy=az,r=3,fill='#367a86',stroke='#fff',stroke_width=1)
        angle=math.radians(f['facing'])
        line(approach,[approach[0]+.22*math.sin(angle),approach[1]+.22*math.cos(angle)],stroke='#367a86',stroke_width=1)
    for r in plan['rooms']:
        x,y=pt(r['label_point'])
        text(x,y,r['label'],font_size=12,text_anchor='middle',font_weight=700,
             paint_order='stroke',stroke=COLORS.get(r['type'],'#e4e0cf'),stroke_width=4)
        text(x,y+16,f"{r['bounds'][2]*r['bounds'][3]:.1f} m²",font_size=10,text_anchor='middle',fill='#75634b')
    text(left+house['width']*scale+8,top-8,'北 ↑',font_size=14)
    connection=house['street_connection']['approach'];x,y=pt([connection[0],connection[2]])
    text(x,y+22,'街へ',font_size=12,text_anchor='middle')
    text(legend,100,'家具・設備',font_size=18,font_weight=700)
    for index,f in enumerate(plan['fixtures'],1):
        text(legend,105+index*19,f"F{index:02d}  {f['label']}",font_size=12)
    base=140+len(plan['fixtures'])*19
    text(legend,base,'扉・開口',font_size=18,font_weight=700)
    for index,d in enumerate(plan['doors'],1):
        text(legend,base+index*19,f"{d['id']}  {d['label']}  {d['width']:.2f}m",font_size=12)
    base+=35+len(plan['doors'])*19
    text(legend,base,'窓・採光',font_size=18,font_weight=700)
    for index,w in enumerate(plan.get('windows',[]),1):
        room=next(r['label'] for r in plan['rooms'] if r['id']==w['room'])
        kind='廊下側・曇り採光' if w['source']=='borrowed_light' else '外窓・曇り' if w['frosted'] else '外窓'
        text(legend,base+index*19,f"{w['id']}  {room}  {kind}",font_size=12)
    bottom=notes_top
    for feature in house['design_features']:
        # Split Japanese text into short visible lines without a font dependency.
        lines=[feature[n:n+48] for n in range(0,len(feature),48)]
        for j,value in enumerate(lines):
            text(65,bottom+j*17,value,font_size=12)
        bottom+=len(lines)*17+12
    text(65,height-26,'青点＝設備の接近点／薄青線＝戸袋／破線＝各住民が玄関から自分の寝床へ至る静的候補線。閉扉・他者・家具使用中の動作は別検証。',font_size=12,fill='#75634b')
    output.parent.mkdir(parents=True,exist_ok=True)
    ET.ElementTree(root).write(output,encoding='utf-8',xml_declaration=True)
    with output.open('ab') as f:f.write(b'\n')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('plans',nargs='*',type=Path,help='JSON plans; defaults to data/foundation/homes/*.json')
    parser.add_argument('--output-dir',type=Path,default=Path('docs/design/homes'))
    parser.add_argument('--no-svg',action='store_true')
    parser.add_argument('--resident-source',type=Path,default=Path('data/residents.json'))
    args=parser.parse_args()
    source=json.loads(args.resident_source.read_text(encoding='utf-8'))
    households={h['id']:set(h['members']) for h in source['households']}
    people={p['id']:p for p in source['residents']}
    paths=args.plans or sorted(Path('data/foundation/homes').glob('*.json'))
    if not paths:parser.error('No plans found')
    summaries=[]
    try:
        for path in paths:
            plan=json.loads(path.read_text(encoding='utf-8'))
            household=plan['house']['household']
            members={r['id'] for r in plan['residents']}
            if members != households.get(household):
                raise ValueError(str(path)+': resident membership differs from the existing household')
            for resident in plan['residents']:
                source_person=people[resident['id']]
                if resident['authored_age_years'] != source_person['age_years'] or resident['occupation'] != source_person['occupation']:
                    raise ValueError(str(path)+': age/occupation differs from current resident source')
            summary=check_plan(plan)
            routes=design_paths(plan)
            if not args.no_svg:
                render(plan,args.output_dir/(path.stem+'.svg'),routes)
            summaries.append({'input':str(path),'house':plan['house']['id'],
                              'geometry':summary,'static_access':{id:len(items) for id,items in routes['resident_access'].items()}})
    except (ValueError,KeyError,TypeError) as error:
        print(str(error),file=sys.stderr)
        return 1
    print(json.dumps({'scope':'Authored 2D geometry only; not Godot routes, 3D, motion or daily-life acceptance.',
                      'plans':summaries},ensure_ascii=False,indent=2))
    return 0


if __name__=='__main__':
    raise SystemExit(main())
