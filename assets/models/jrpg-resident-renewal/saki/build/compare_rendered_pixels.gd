extends SceneTree
# Direct decoded-image comparison, recorded as one visual regression group.
# No rendering, simulation stepping, fingerprints, or per-frame assertion count.
const ROOT_PATH := "res://assets/models/jrpg-resident-renewal/saki/review/texture-eyes/"
const CURRENT := "res://assets/models/haru-cute-pilot/review/godot/texture-eyes/"
func _initialize() -> void:
	var scenarios := {};var total_pixels_changed := 0;var maximum := 0.0
	for name in ["open-lod0","blink-lod0","blink-lod1","blink-lod2","tired-lod0","sleep"]:
		var old := Image.load_from_file(ROOT_PATH+"haru-reference/"+name+".png")
		var current := Image.load_from_file(CURRENT+name+".png")
		if old==null or current==null or old.is_empty() or current.is_empty():
			push_error("Missing rendered reference image: "+name);quit(1);return
		old.convert(Image.FORMAT_RGBA8);current.convert(Image.FORMAT_RGBA8)
		if old.get_size()!=current.get_size():
			push_error("Rendered reference dimensions differ: "+name);quit(1);return
		var a := old.get_data();var b := current.get_data();var changed := 0;var error := 0.0
		if a!=b:
			for offset in range(0,a.size(),4):
				var pixel_error := 0
				for channel in 4: pixel_error=maxi(pixel_error,absi(a[offset+channel]-b[offset+channel]))
				if pixel_error>0: changed+=1;error=maxf(error,pixel_error/255.0)
		scenarios[name]={"width":old.get_width(),"height":old.get_height(),"changed_pixels":changed,"maximum_channel_error":error}
		total_pixels_changed+=changed;maximum=maxf(maximum,error)
	var result := {"scope":"Same r3 Haru geometry, pose, camera and lighting; stable-commit shader versus current optional-chart shader.","method":"Decode PNG to RGBA8 and compare actual pixel channels directly. No SHA/file-identity test.","scenarios":scenarios,"total_changed_pixels":total_pixels_changed,"maximum_channel_error":maximum,"assertions_added":0,"interpretation":"One rendered regression comparison group, not six new tests."}
	FileAccess.open(ROOT_PATH+"rendered-pixel-comparison.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t")+"\n")
	print("RENDERED_PIXEL_COMPARISON changed=",total_pixels_changed," max_error=",maximum," assertion_count=0")
	quit()
