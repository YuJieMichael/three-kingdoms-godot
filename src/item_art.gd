class_name KingdomItemArt
extends RefCounted

static var _paths: Dictionary = {}
static var _textures: Dictionary = {}

static func texture(id: String) -> Texture2D:
	if _paths.is_empty():
		_paths = JSON.parse_string(FileAccess.get_file_as_string("res://data/item-art.json"))
	if not _paths.has(id):
		return null
	if not _textures.has(id):
		_textures[id] = load(str(_paths[id])) as Texture2D
	return _textures[id]
