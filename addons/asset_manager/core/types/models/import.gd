@tool
class_name ModelsImportRunner
extends RefCounted

## The default recursive walk, then three things store-bought packs need:
## - A .fbx with a .glb/.gltf of the same name beside it is the source of that
##   conversion, so only the converted file is listed. The FBX usually points
##   at textures on the author's machine and previews untextured anyway.
## - Folders made for Unity ("Rig_unity", "RIG_FULL_UNITY", "House_unity") are
##   skipped: the same models also ship rigged for Unreal, which is what Godot
##   imports cleanly, so they would only be listed twice.
## - Tags are built from cleaned folder names: punctuation becomes "_" and
##   storefront words go, so "Battle Tower 3D Low Poly Pack" tags
##   "battle_tower" and "free-environment-props-3d-low-poly-models" tags
##   "environment_props". A variant folder like "RIG_PARTS_UNREAL" splits into
##   "rig" and "parts" so each can be filtered on its own.

const CONVERTED_EXTENSIONS: PackedStringArray = ["glb", "gltf"]
const SKIPPED_FOLDER_WORD: String = "unity"

## Dropped from inside a folder name, never a tag of their own. The engine
## and "ordinar" (static, unrigged) words come in every spelling packs use:
## "rig_unrial", "unral_better_export", "HOUSE_0RDINAR_FULL".
const STOREFRONT_WORDS: PackedStringArray = [
	"3d", "low", "poly", "lowpoly", "pack", "packs", "model", "models",
	"asset", "assets", "free", "game", "fbx", "export", "better",
	"unreal", "unrial", "unral", "ordinar", "0rdinar", "ordinary",
]

## A folder named only from these is a variant of the same models, listed as
## one tag per word.
const VARIANT_WORDS: PackedStringArray = ["full", "parts", "rig", "shells", "house"]

static func run(bucket_root_path: String, type_entry: Dictionary) -> Array[Dictionary]:
	var scanned := DefaultImportRunner.run(bucket_root_path, type_entry)

	var listed: Dictionary = {}
	for entry in scanned:
		listed[entry["path"]] = true

	var result: Array[Dictionary] = []
	for entry in scanned:
		var path: String = entry["path"]
		var relative_dir := path.get_base_dir().trim_prefix(bucket_root_path).trim_prefix("/")
		if _in_skipped_folder(relative_dir) or _has_converted_sibling(path, listed):
			continue
		entry["tags"] = build_tags(relative_dir)
		result.append(entry)
	return result

static func _in_skipped_folder(relative_dir: String) -> bool:
	return relative_dir.to_lower().contains(SKIPPED_FOLDER_WORD)

static func _has_converted_sibling(path: String, listed: Dictionary) -> bool:
	if path.get_extension().to_lower() != "fbx":
		return false
	var base := path.get_basename()
	for ext in CONVERTED_EXTENSIONS:
		if listed.has(base + "." + ext):
			return true
	return false

static func build_tags(relative_dir: String) -> Array[String]:
	var tags: Array[String] = []
	if relative_dir.is_empty():
		return tags

	for segment in relative_dir.split("/"):
		if segment.begins_with("."):
			continue
		var words := _words(segment)
		var kept: PackedStringArray = []
		for word in words:
			if not STOREFRONT_WORDS.has(word):
				kept.append(word)
		if kept.is_empty():
			continue

		var candidates: PackedStringArray = []
		if Array(kept).all(func(word: String) -> bool: return VARIANT_WORDS.has(word)):
			candidates = kept
		else:
			candidates.append("_".join(kept))

		for tag in candidates:
			if not DefaultImportRunner._is_noise(tag) and not tags.has(tag):
				tags.append(tag)
	return tags

## Lowercase alphanumeric runs: "Elven Runes, Stones" -> elven, runes, stones.
static func _words(segment: String) -> PackedStringArray:
	var words: PackedStringArray = []
	var current := ""
	for character in segment.to_lower():
		var code := character.unicode_at(0)
		var is_word_char := (code >= 48 and code <= 57) or (code >= 97 and code <= 122) or code > 127
		if is_word_char:
			current += character
		elif not current.is_empty():
			words.append(current)
			current = ""
	if not current.is_empty():
		words.append(current)
	return words
