extends SceneTree
var main
var checks := 0
var failed: Array[String] = []
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, label: String) -> void:
 checks += 1
 if not ok: failed.append(label);push_error(label)
func run() -> void:
 expect(FileAccess.file_exists("res://data/residents.json"),"Resident definitions included in release pack")
 expect(FileAccess.file_exists("res://game/assets/models/haru/face-layout.json"),"Haru eye layout included as a non-resource JSON")
 main = load("res://game/scenes/main.tscn").instantiate();root.add_child(main)
 await process_frame
 var sim = root.get_node("Sim")
 sim.set_process(false);main.set_process(false)
 sim.reset(711,12);main._start_play();sim.running = false
 expect(sim.people.size()==12 and main.avatars.size()==12,"All twelve residents instantiate from the actual exported pack")
 var model = main.avatars.haru.jrpg
 var capabilities: Dictionary = model.capabilities()
 expect(capabilities.contract_errors.is_empty(),"Exported skin, 35 bones, nine clips and eye layout satisfy the runtime contract")
 expect(capabilities.source_model.ends_with("haru/CH_Haru.glb"),"Haru uses the dedicated JRPG model")
 expect(capabilities.facial_controls==["Blink","TiredEyes"],"Export retains the two declared eye controls")
 expect(capabilities.material_mode=="TEXTURE_TOON","Export retains texture toon mode")
 var has_atlas := false
 for material in model.body_materials:
  var tex = material.get_shader_parameter("base_palette")
  has_atlas = has_atlas or (tex is Texture2D and tex.get_width()==2048 and tex.get_height()==2048)
 expect(has_atlas,"Exported resident uses the 2K source atlas rather than the old palette")
 model.animator.play("sleep",0);model.animator.advance(.01);model._process(.01)
 var closed: bool = not model.body_materials.is_empty()
 for material in model.body_materials: closed = closed and is_equal_approx(float(material.get_shader_parameter("blink")),1.0)
 expect(closed,"Sleep closes the real exported eye shader")
 model.animator.play("walk",0);model.animator.advance(.01);model._process(.01)
 var open: bool = not model.body_materials.is_empty()
 for material in model.body_materials: open = open and float(material.get_shader_parameter("blink"))<.1
 expect(open,"Leaving sleep restores open eyes in the exported shader")
 model.prepare_lods()
 expect(model.lod_resources_loaded==2,"Export contains both compatible distance LODs")
 for level in [0,1,2,0]:expect(model.set_lod(level),"Exported LOD%d loads with compatible skin"%level)
 var report := {"source_revision":"3885558f2c55f5391c57532fc77bbc523cc608c8","scope":"Actual bundled PCK loaded by matching Godot 4.7.2, external verification script. Native app launch is checked separately; does not invoke save/load.","checks":checks,"failed":failed,"capabilities":capabilities,"engine":Engine.get_version_info()}
 var file := FileAccess.open(get_script().resource_path.get_base_dir().path_join("packaged-smoke.json"),FileAccess.WRITE)
 file.store_string(JSON.stringify(report,"\t")+"\n");file.close()
 main.free()
 print("Packaged checkpoint smoke: %d passed, %d failed"%[checks-failed.size(),failed.size()])
 quit(0 if failed.is_empty() else 1)
