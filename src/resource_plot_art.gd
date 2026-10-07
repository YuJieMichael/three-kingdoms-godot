class_name KingdomResourcePlotArt
extends RefCounted

const ATLAS: Texture2D = preload("res://assets/environment/suburb/resource-buildings.png")
const TYPES: Array[String] = ["farm", "lumber", "quarry", "mine"]

static func texture(id: String) -> Texture2D:
	var cell: int = TYPES.find(id)
	if cell < 0:
		return null
	var sprite: AtlasTexture = AtlasTexture.new()
	sprite.atlas = ATLAS
	var dimensions: Vector2 = ATLAS.get_size() / Vector2(5, 4)
	sprite.region = Rect2(Vector2(cell * dimensions.x, 0), dimensions)
	return sprite
