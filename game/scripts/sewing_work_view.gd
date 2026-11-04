class_name SewingWorkView
extends Node3D

# Only renders world-owned IDs. Stages and hand corrections never create stock,
# advance a job, charge a household or grant a result.
const SCENES := {
	"scissors":preload("res://game/scenes/props/sewing_scissors.tscn"),
	"needle":preload("res://game/scenes/props/sewing_needle.tscn"),
	"spool":preload("res://game/scenes/props/sewing_spool.tscn")}
const THREAD := preload("res://game/scenes/props/sewing_thread.tscn")
const WORKPIECE := preload("res://game/scenes/props/sewing_workpiece.tscn")
var simulation
var avatars: Dictionary = {}
var object_nodes: Dictionary = {}
var thread_node: Node3D

func setup(resident_avatars: Dictionary, sim) -> void:
	avatars=resident_avatars;simulation=sim
	if not is_instance_valid(thread_node):
		thread_node=THREAD.instantiate();thread_node.name="WorkingThread";add_child(thread_node)
	sync(0)

func object_node(id: String) -> Node3D:
	return object_nodes.get(id) as Node3D

func sync(_delta: float) -> void:
	if simulation==null or simulation.sewing==null: return
	var records: Dictionary=simulation.sewing.objects
	if is_instance_valid(thread_node):thread_node.visible=false
	for id in records:
		var record: Dictionary=records[id]
		var node:=object_node(id)
		if not is_instance_valid(node):
			var scene: PackedScene=SCENES.get(record.kind,WORKPIECE)
			node=scene.instantiate();node.name="Sewing_"+str(id).validate_node_name()
			node.set_meta("sewing_object_id",id);add_child(node);object_nodes[id]=node
		if node.has_method("set_stage"):
			node.set_stage(record.get("stage","fabric"))
			if node.has_method("set_progress"):
					node.set_progress(1.0 if record.get("stage","")=="finished" else clampf(float(record.get("sew_minutes",0))/float(simulation.sewing.config.sew_minutes),0,1))
		var desired:=Transform3D(Basis(Vector3.UP,float(record.get("yaw",0)))*Basis(Vector3.RIGHT,float(record.get("pitch",0))),record.position)
		var holder: String=record.get("holder","")
		var actor=avatars.get(holder)
		if is_instance_valid(actor) and is_instance_valid(actor.contacts):
			var motion: Dictionary=actor.contacts.interaction_result
			if motion.get("thread_active",false) and is_instance_valid(thread_node):
				thread_node.visible=true;thread_node.set_ends(to_local(motion.thread_needle_eye),to_local(motion.thread_anchor),.015)
			var transforms: Dictionary=motion.get("object_transforms",{})
			if transforms.get(id) is Transform3D: desired=transforms[id]
			var tool_visuals: Dictionary=motion.get("tool_visuals",{})
			if node.has_method("set_open"): node.set_open(float(tool_visuals.get(id,{}).get("open",0)))
		elif node.has_method("set_open"):
			node.set_open(0)
		node.global_transform=desired
		node.set_meta("holder",holder);node.set_meta("owner",record.get("owner",""));node.set_meta("container",record.get("container",""))
	for id in object_nodes.keys():
		if records.has(id):continue
		var stale: Node3D=object_nodes[id];object_nodes.erase(id);remove_child(stale);stale.queue_free()

static func person_summary(sim, p: Dictionary) -> String:
	if sim.sewing==null:return ""
	var finished:=0;var unfinished:=0
	for record in sim.sewing.objects.values():
		if record.get("owner","")!=p.id or record.get("kind","") in ["scissors","needle","spool"]:continue
		if record.get("stage","")=="finished":finished+=1
		elif record.get("material_used",false):unfinished+=1
	if finished==0 and unfinished==0:return ""
	return "布小物\n完成した巾着 %d点　作りかけ %d点"%[finished,unfinished]

static func activity_text(sim, p: Dictionary) -> String:
	if sim.sewing==null:return ""
	var session: Dictionary=sim.sewing.active_session()
	if session.is_empty() or p.id not in [session.a,session.b]:return ""
	var phase: String=session.phase
	if session.maker!=p.id:
		if p.moving:return "布小物づくりの場所へ向かう"
		return "完成した巾着を見ている" if phase=="show" else ("布小物づくりを見守っている" if phase in ["cut","sew"] else "相手の準備と片付けを待っている")
	if phase in ["cut","sew"]:
		var tool: String="はさみ" if phase=="cut" else "針"
		if session.tool_phase=="reach":return tool+"を取っている"
		if session.tool_phase=="return":return tool+"を戻している"
		return "布を裁っている" if phase=="cut" else "巾着を縫っている"
	var workpiece: Dictionary=sim.sewing.objects.get(session.object_id,{})
	var noun: String="巾着" if workpiece.get("stage","")=="finished" else ("作りかけ" if workpiece.get("material_used",false) else "布")
	return {"to_source":noun+"を取りに向かう","take":noun+"を手に取る","carry_to_table":noun+"を作業台へ運ぶ",
		"place":noun+"を作業台へ置く","lift_show":"完成した巾着を持ち上げる","show":"完成した巾着を見せている",
		"lower":"巾着を作業台へ置く","take_store":"巾着を手に取る","carry_to_store":"巾着を収納へ運ぶ","store":"巾着をしまっている"}.get(phase,"")
