class_name KingdomResourcePlotArt
extends RefCounted

const ATLAS: Texture2D = preload("res://assets/environment/suburb/resource-buildings.png")
const TYPES: Array[String] = ["farm", "lumber", "quarry", "mine"]
static var _open_land: Dictionary = {}

static func open_land(index: int) -> Texture2D:
	var key: String = "plain_a" if index % 2 == 0 else "plain_b"
	if _open_land.has(key):
		return _open_land[key]
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world-terrain-art-atlas.json"))
	var row: Array = metadata.get("regions", {}).get(key, [])
	if row.size() != 4:
		return null
	var sprite: AtlasTexture = AtlasTexture.new()
	sprite.atlas = load(str(metadata.get("texture", ""))) as Texture2D
	sprite.region = Rect2(float(row[0]),float(row[1]),float(row[2]),float(row[3]))
	sprite.filter_clip = true
	_open_land[key] = sprite
	return sprite

static func texture(id: String) -> Texture2D:
	var cell: int = TYPES.find(id)
	if cell < 0:
		return null
	var sprite: AtlasTexture = AtlasTexture.new()
	sprite.atlas = ATLAS
	var dimensions: Vector2 = ATLAS.get_size() / Vector2(5, 4)
	sprite.region = Rect2(Vector2(cell * dimensions.x, 0), dimensions)
	return sprite
