class_name ResidentPortraits
extends RefCounted

# The original eight people share a painted lineup; the four renewed bodies have
# their own portrait. Rin's lower head position needs its own crop.
const REGIONS = {
	"nagisa":Rect2(30,30,200,235), "ryo":Rect2(240,0,200,235),
	"rin":Rect2(440,220,200,235), "osamu":Rect2(615,20,200,235),
	"fumi":Rect2(840,40,200,235), "maho":Rect2(1060,30,200,235),
	"ritsu":Rect2(1280,0,200,235), "aoi":Rect2(1505,10,200,235)}

static func texture(id: String, face_crop: bool = true) -> Texture2D:
	var path := "res://game/assets/ui/portraits/%s.png"%id
	if ResourceLoader.exists(path):
		var source: Texture2D = load(path)
		if not face_crop: return source
		var atlas := AtlasTexture.new()
		atlas.atlas = source
		var size := source.get_size()
		atlas.region = Rect2(size.x*.18,size.y*.08,size.x*.64,size.y*.60)
		return atlas
	if not REGIONS.has(id): return null
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://game/assets/ui/residents.png")
	atlas.region = REGIONS[id]
	return atlas
