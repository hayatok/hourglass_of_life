extends SceneTree
# Data/material contract for optional UV charts; no game actors use the trial layout.
const CAST := "res://assets/models/jrpg-resident-renewal/"
const OUT := CAST+"saki/review/texture-eyes/optional-chart-contract.json"
var checks:=0
var failures:Array[String]=[]
func _initialize() -> void: call_deferred("run")
func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok: failures.append(message);push_error(message)
func bad(model:JrpgResidentModel,layout:Dictionary,message:String) -> void:
	model.face_layout=layout
	expect(not model.import_contract_errors().is_empty(),message)
	expect(model.capabilities().facial_controls.is_empty(),"Invalid layout cannot advertise UV controls: "+message)
func run() -> void:
	var model:=load("res://game/scenes/characters/haru.tscn").instantiate() as JrpgResidentModel
	root.add_child(model);model.set_process(false);model.animator.speed_scale=0
	var original:=model.face_layout.duplicate(true)
	var material:=ShaderMaterial.new();material.shader=load("res://game/assets/models/haru/haru_texture_eyes.gdshader")
	expect(model.capabilities().eye_charts==2 and model.capabilities().eyelid_method=="compress","Haru retains the default two-chart compression contract")
	model._configure_texture_eyes(material)
	expect(material.get_shader_parameter("extra_eye_count")==0 and material.get_shader_parameter("eyelid_occlusion")==false,"Default layout initializes optional material state as disabled")
	var profiles:Dictionary={}
	for resident in ["saki","tomo","yui"]:
		var layout:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(CAST+resident+"/build/face-layout-candidate.json"))
		model.face_layout=layout
		expect(model.import_contract_errors().is_empty(),resident+" raw calibration satisfies the runtime layout contract")
		var before:=JSON.stringify(layout)
		model._configure_texture_eyes(material)
		var extra:int=1 if resident=="saki" else 0
		expect(model.capabilities().eye_charts==2+extra and model.capabilities().facial_controls==["Blink","TiredEyes"],"Additional charts do not invent extra physical eyes or facial controls")
		expect(material.get_shader_parameter("extra_eye_count")==extra and material.get_shader_parameter("eyelid_occlusion")==bool(extra),resident+" chart count and eyelid method reach the actual shader")
		if extra>0:
			for pair in [["center","extra_eye_center"],["axis_x","extra_eye_x"],["axis_y","extra_eye_y"],["skin_uv","extra_eye_skin"]]:
				var value:Array=layout.additional_eye_patches[0][pair[0]]
				expect(material.get_shader_parameter(pair[1])[0]==Vector2(value[0],value[1]),"The core uploads the exact additional-chart "+pair[0]+" calibration")
		expect(JSON.stringify(layout)==before,"Uploading "+resident+" uniforms does not mutate profile data")
		profiles[resident]=model.capabilities()
	var valid_extra:Dictionary=original.eyes.left.duplicate(true);valid_extra.eye="left"
	var invalid:=original.duplicate(true);invalid.additional_eye_patches={};bad(model,invalid,"Extra charts require an array")
	invalid=original.duplicate(true);invalid.additional_eye_patches=[{}];bad(model,invalid,"Extra charts identify their physical eye")
	invalid=original.duplicate(true);var patch:=valid_extra.duplicate(true);patch.erase("center");invalid.additional_eye_patches=[patch];bad(model,invalid,"Extra chart missing UV center is rejected")
	invalid=original.duplicate(true);patch=valid_extra.duplicate(true);patch.axis_y=patch.axis_x.duplicate();invalid.additional_eye_patches=[patch];bad(model,invalid,"Extra chart with a zero determinant is rejected")
	invalid=original.duplicate(true);patch=valid_extra.duplicate(true);patch.axis_x=[NAN,0.1];invalid.additional_eye_patches=[patch];bad(model,invalid,"Nonfinite UV calibration is rejected")
	invalid=original.duplicate(true);invalid.additional_eye_patches=[valid_extra,valid_extra,valid_extra,valid_extra,valid_extra];bad(model,invalid,"More than four extra charts is rejected before upload")
	invalid=original.duplicate(true);invalid.eyelid_method="unknown";bad(model,invalid,"Unknown eyelid algorithm is rejected")
	var four:=original.duplicate(true);four.additional_eye_patches=[valid_extra,valid_extra,valid_extra,valid_extra];model.face_layout=four
	expect(model.import_contract_errors().is_empty(),"The documented extra-chart upper bound is supported")
	model._configure_texture_eyes(material)
	expect(material.get_shader_parameter("extra_eye_count")==4 and material.get_shader_parameter("extra_eye_center").size()==4,"Maximum chart data is safely uploaded to the bounded shader arrays")
	model.face_layout=original;model._configure_texture_eyes(material)
	expect(material.get_shader_parameter("extra_eye_count")==0 and not material.get_shader_parameter("eyelid_occlusion"),"Configuring a default layout clears previous resident options")
	var empty:=true
	for value in material.get_shader_parameter("extra_eye_center"): empty=empty and value==Vector2.ZERO
	expect(empty,"Unused chart slots are cleared instead of retaining another resident's UVs")
	expect(FileAccess.get_sha256("res://game/assets/models/haru/CH_Haru.glb")=="1fe9857d04300aee6de13d905f34a8ec86630bc0b86008f1095a908faf47b7cf","Haru source GLB remains unchanged")
	FileAccess.open(OUT,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"profiles":profiles,"scope":"Layout validation and actual ShaderMaterial upload; trial calibrations are not attached to Haru geometry."},"\t")+"\n")
	print("OPTIONAL_EYE_CHART_CONTRACT ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
