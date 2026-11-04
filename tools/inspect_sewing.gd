extends SceneTree

# Capture a naturally chosen sewing activity for a reproducible native-app
# inspection. No resident, routine, need, skill, proposal or RNG is rewritten.
var output := "res://builds/sewing-native/natural-town.json"
var seed_value := 711

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output=argument.trim_prefix("--output=")
		if argument.begins_with("--seed="): seed_value=int(argument.trim_prefix("--seed="))
	call_deferred("run")

func run() -> void:
	var sim=root.get_node("Sim")
	sim.set_process(false);sim.reset(seed_value,12)
	for minute in 12*1440:
		sim.advance_minutes(1)
		var session: Dictionary=sim.sewing.active_session()
		if session.is_empty() or session.phase!="sew" or session.tool_phase!="operate": continue
		var item: Dictionary=sim.sewing.objects[session.object_id]
		if int(item.sew_minutes)<5: continue
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		if not sim.save_game(output): push_error("Could not save the natural sewing town");quit(1);return
		var record={"scope":"Unmodified twelve-person natural simulation; native inspection entry point, not human playtesting.",
			"seed":seed_value,"elapsed":sim.elapsed,"clock":sim.clock_text(),"schema":SaveValidation.CURRENT_SCHEMA,
			"session":sim._encode(session),"item":sim._encode(item),"save_file":output}
		FileAccess.open(output.get_base_dir()+"/natural-capture.json",FileAccess.WRITE).store_string(JSON.stringify(record,"\t"))
		print("Natural sewing captured: %s, %s / %s, %s"%[sim.clock_text(),session.maker,session.viewer,output]);quit(0);return
	push_error("No natural sewing operation observed in the fixed twelve-day horizon")
	quit(1)
