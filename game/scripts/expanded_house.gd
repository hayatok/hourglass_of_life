@tool
extends TownBuilding

# Existing terrain has cut-outs for the original homes. Keep the added home's
# floor above that terrain without altering any of the original town geometry.
func _ready() -> void:
	super._ready()
	if parts.has("Floor"): parts.Floor.position.y = .04
