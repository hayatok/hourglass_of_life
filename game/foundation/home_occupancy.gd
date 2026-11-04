class_name HomeOccupancy
extends RefCounted

# Claims describe admission/use at the executor's current location. This module
# never moves a resident, advances time, assigns an activity, or changes needs.
const SCHEMA := 1
const LIMIT := 64
var house_id := ""
var _household := ""
var _members: Array = []
var _rooms: Dictionary = {}
var _fixtures: Dictionary = {}
var _doors: Dictionary = {}
var _room_users: Dictionary = {}
var _fixture_users: Dictionary = {}
var _grants: Dictionary = {}
var _blocked_doors: Array = []

static func _id(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length()<=96 and value.strip_edges()==value

static func _whole(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value>=low and value<=high and value==int(value)

static func _ids(value: Variant) -> bool:
	if not value is Array or value.size()>LIMIT: return false
	var seen := {}
	for key in value:
		if not _id(key) or seen.has(key): return false
		seen[key] = true
	return true

static func _bounds(value: Variant) -> bool:
	if not value is Array or value.size()!=4: return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)) or absf(float(number))>1000: return false
	return value[2]>0 and value[3]>0

static func _same_keys(value: Variant, expected: Dictionary) -> bool:
	if not value is Dictionary or value.size()!=expected.size(): return false
	for key in expected:
		if not value.has(key): return false
	return true

func configure(plan: Variant) -> bool:
	if not plan is Dictionary or not plan.get("house") is Dictionary: return false
	if not _id(plan.house.get("id")) or not _id(plan.house.get("household")): return false
	for key in ["rooms","external_zones","fixtures","doors","residents"]:
		if not plan.get(key) is Array: return false
	if plan.rooms.is_empty() or plan.rooms.size()>128 or plan.external_zones.size()>32 or plan.fixtures.size()>512 or plan.doors.size()>256: return false
	var members: Array = []
	for resident in plan.residents:
		if not resident is Dictionary or not _id(resident.get("id")) or resident.id in members: return false
		members.append(resident.id)
	if members.is_empty() or members.size()>LIMIT: return false
	var rooms := {};var fixtures := {};var doors := {}
	for authored in plan.rooms:
		if not authored is Dictionary or not _id(authored.get("id")) or rooms.has(authored.id) or not _bounds(authored.get("bounds")): return false
		if not _ids(authored.get("allowed_residents")) or not _whole(authored.get("occupancy_limit"),1,LIMIT): return false
		if authored.get("private_scope","") not in ["household","parents","resident","exclusive_when_occupied","exclusive_while_changing"]: return false
		if authored.private_scope=="exclusive_when_occupied" and authored.occupancy_limit!=1: return false
		rooms[authored.id] = authored.duplicate(true)
	for authored in plan.external_zones:
		if not authored is Dictionary or not _id(authored.get("id")) or rooms.has(authored.id) or not _bounds(authored.get("bounds")): return false
		var room: Dictionary = authored.duplicate(true)
		room.allowed_residents = [];room.private_scope = "public";room.occupancy_limit = LIMIT
		rooms[room.id] = room
	for authored in plan.fixtures:
		if not authored is Dictionary or not _id(authored.get("id")) or fixtures.has(authored.id) or not rooms.has(authored.get("room","")): return false
		if not _whole(authored.get("capacity",1),1,LIMIT) or not _id(authored.get("owner",plan.house.household)): return false
		if authored.has("private") and not authored.private is bool: return false
		if authored.has("allowed_residents") and not _ids(authored.allowed_residents): return false
		if authored.has("use_via") and not _id(authored.use_via): return false
		fixtures[authored.id] = authored.duplicate(true)
	for key in fixtures:
		var seen := {};var current: String = key
		while not current.is_empty():
			if not fixtures.has(current) or seen.has(current) or fixtures[current].room!=fixtures[key].room: return false
			seen[current] = true;current = fixtures[current].get("use_via","")
	for authored in plan.doors:
		if not authored is Dictionary or not _id(authored.get("id")) or doors.has(authored.id): return false
		if not rooms.has(authored.get("room_a","")) or not rooms.has(authored.get("room_b","")) or authored.room_a==authored.room_b: return false
		doors[authored.id] = authored.duplicate(true)
	# Commit only after all authored references have been checked.
	house_id = plan.house.id;_household = plan.house.household;_members = members
	_rooms = rooms;_fixtures = fixtures;_doors = doors
	_room_users = {};_fixture_users = {};_grants = {};_blocked_doors = []
	for key in _rooms: _room_users[key] = [];_grants[key] = []
	for key in _fixtures: _fixture_users[key] = []
	return true

func _reply(status: String, reason: String, room: String = "", fixture: String = "") -> Dictionary:
	return {"status":status,"reason":reason,"room":room,"fixture":fixture}

func _permission(room: String, person: String, grants: Dictionary) -> bool:
	return _rooms[room].private_scope=="public" or person in _rooms[room].allowed_residents or person in grants[room]

func _fixture_permission(fixture: String, person: String) -> bool:
	var record: Dictionary = _fixtures[fixture]
	if record.has("allowed_residents") and person not in record.allowed_residents: return false
	return not record.get("private",false) or record.get("owner",_household) not in _members or record.owner==person

func _exclusive(fixture: String) -> bool:
	return _fixtures[fixture].get("private_scope","") in ["exclusive_when_occupied","exclusive_while_changing"]

func room_status(room: String, person: String) -> Dictionary:
	if not _rooms.has(room) or not _id(person): return _reply("unreachable","部屋または住人を識別できない。",room)
	if not _permission(room,person,_grants): return _reply("private","入室にはこの部屋の許可が必要。",room)
	var users: Array = _room_users[room]
	if person not in users and users.size()>=int(_rooms[room].occupancy_limit): return _reply("occupied","部屋の利用が終わるまで待つ。",room)
	for key in _fixtures:
		if _fixtures[key].room==room and _exclusive(key):
			for user in _fixture_users[key]:
				if user!=person: return _reply("occupied","身支度や私的な利用が終わるまで外で待つ。",room)
	return _reply("ready","入室できる。",room)

func can_enter(room: String, person: String) -> bool:
	return room_status(room,person).status=="ready"

func _bundle(fixture: String) -> Array:
	var result: Array = [];var current := fixture
	while not current.is_empty():
		result.append(current);current = _fixtures[current].get("use_via","")
	return result

func fixture_status(fixture: String, person: String) -> Dictionary:
	if not _fixtures.has(fixture) or not _id(person): return _reply("unreachable","設備または住人を識別できない。","",fixture)
	var room: String = _fixtures[fixture].room
	var entry := room_status(room,person)
	if entry.status!="ready": entry.fixture = fixture;return entry
	for key in _bundle(fixture):
		if not _fixture_permission(key,person): return _reply("private","他の人の私物や寝床は使えない。",room,fixture)
		if person not in _fixture_users[key] and _fixture_users[key].size()>=int(_fixtures[key].get("capacity",1)):
			return _reply("occupied","設備が空くまで待つ。",room,fixture)
		if _exclusive(key):
			for user in _room_users[room]:
				if user!=person: return _reply("occupied","同室の人が退室してから私的に利用する。",room,fixture)
	return _reply("ready","設備を利用できる。",room,fixture)

func reserve_room(room: String, person: String) -> Dictionary:
	var result := room_status(room,person)
	if result.status!="ready" or person in _room_users[room]: return result
	release_person(person)
	_room_users[room].append(person)
	return result

func reserve_fixture(fixture: String, person: String) -> Dictionary:
	var result := fixture_status(fixture,person)
	if result.status!="ready": return result
	var bundle := _bundle(fixture)
	var held: Array = []
	for key in _fixture_users:
		if person in _fixture_users[key]: held.append(key)
	if held.size()==bundle.size() and bundle.all(func(key): return key in held): return result
	# No callbacks between validation and commit; a failed request retains the
	# prior claims. The executor alone decides when a real arrival occurs.
	release_person(person)
	_room_users[result.room].append(person)
	for key in bundle: _fixture_users[key].append(person)
	return result

func release_person(person: String) -> void:
	for users in _room_users.values(): users.erase(person)
	for users in _fixture_users.values(): users.erase(person)

func grant_room(room: String, person: String, allowed: bool) -> bool:
	if not _rooms.has(room) or not _id(person): return false
	# Authored membership is not erased by revoking an additional visitor grant.
	if person in _rooms[room].allowed_residents or _rooms[room].private_scope=="public": return true
	if not allowed and person in _room_users[room]: return false
	if allowed and person not in _grants[room] and _grants[room].size()>=LIMIT: return false
	if allowed and person not in _grants[room]: _grants[room].append(person)
	elif not allowed: _grants[room].erase(person)
	return true

func door_status(door: String, _person: String = "") -> Dictionary:
	if not _doors.has(door): return {"status":"unreachable","reason":"扉を識別できない。"}
	return {"status":"blocked" if door in _blocked_doors else "ready","reason":"扉が通行止めになっている。" if door in _blocked_doors else "開閉を実行できる扉。"}

func set_door_blocked(door: String, blocked: bool) -> bool:
	if not _doors.has(door): return false
	if blocked and door not in _blocked_doors: _blocked_doors.append(door)
	elif not blocked: _blocked_doors.erase(door)
	return true

func snapshot() -> Dictionary:
	return {"schema":SCHEMA,"house_id":house_id,"room_users":_room_users.duplicate(true),"fixture_users":_fixture_users.duplicate(true),"grants":_grants.duplicate(true),"blocked_doors":_blocked_doors.duplicate()}

func restore(data: Variant) -> bool:
	if house_id.is_empty() or not data is Dictionary or data.size()!=6 or not _whole(data.get("schema"),SCHEMA,SCHEMA) or data.get("house_id")!=house_id: return false
	if not _same_keys(data.get("room_users"),_rooms) or not _same_keys(data.get("fixture_users"),_fixtures) or not _same_keys(data.get("grants"),_rooms) or not _ids(data.get("blocked_doors")): return false
	for key in data.blocked_doors:
		if not _doors.has(key): return false
	for room in _rooms:
		if not _ids(data.grants[room]) or not _ids(data.room_users[room]) or data.room_users[room].size()>int(_rooms[room].occupancy_limit): return false
	var locations := {};var held := {}
	for room in _rooms:
		for person in data.room_users[room]:
			if locations.has(person) or not _permission(room,person,data.grants): return false
			locations[person] = room
	for key in _fixtures:
		var users = data.fixture_users[key]
		if not _ids(users) or users.size()>int(_fixtures[key].get("capacity",1)): return false
		for person in users:
			if locations.get(person,"")!=_fixtures[key].room or not _fixture_permission(key,person): return false
			if not held.has(person): held[person] = []
			held[person].append(key)
			if _exclusive(key) and (data.room_users[_fixtures[key].room].size()!=1 or users.size()!=1): return false
	for person in held:
		var complete_bundle := false
		for key in held[person]:
			var bundle := _bundle(key)
			if bundle.size()==held[person].size() and bundle.all(func(item): return item in held[person]): complete_bundle = true;break
		if not complete_bundle: return false
	_room_users = data.room_users.duplicate(true);_fixture_users = data.fixture_users.duplicate(true)
	_grants = data.grants.duplicate(true);_blocked_doors = data.blocked_doors.duplicate()
	return true
