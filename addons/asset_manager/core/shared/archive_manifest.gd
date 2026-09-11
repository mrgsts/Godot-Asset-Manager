@tool
class_name ArchiveManifest
extends RefCounted

## What a zip holds, judged before anything is written. Takes the entry list
## ZIPReader.get_files() returns and answers the questions the Add dialog asks:
## which formats are in here, what is junk, where does the preview live.
## Pure: no zip, no disk. A PackedStringArray in, a Dictionary out.

## Never wanted, whatever the type. DCC source files can't be opened by Godot,
## editor caches belong to the machine that made them, and .import/.uid name
## resources in a project that isn't this one.
const BLOCKED_EXTENSIONS: PackedStringArray = [
	"blend", "blend1", "max", "ma", "mb", "c4d", "spp", "sbs", "sbsar",
	"ztl", "zpr", "xcf", "psb", "sketch", "aseprite",
	"import", "uid", "tmp", "depren",
	"zip", "rar", "7z",
	"ds_store",
	# Model formats the plugin can't index, and the .mtl that goes with .obj.
	"obj", "mtl", "dae",
]

## Path fragments rather than extensions: a folder whose whole contents are junk.
const BLOCKED_FRAGMENTS: PackedStringArray = [
	"__MACOSX/", "/.godot/", ".godot/", "/.git/", ".git/",
	"Thumbs.db", "desktop.ini", ".DS_Store",
]

## Checked against the filename, and only near the top of the archive: packs put
## their preview at the root, while a theme's "icon-checked.png" is buried and
## is not a preview of anything.
const PREVIEW_HINTS: PackedStringArray = [
	"sample", "preview", "screenshot", "thumbnail", "thumb", "cover",
]
const PREVIEW_EXTENSIONS: PackedStringArray = ["png", "jpg", "jpeg", "webp"]
const PREVIEW_MAX_DEPTH: int = 1
const PREVIEW_LIMIT: int = 5

## Reads the entry list into everything the dialog needs.
##   root_prefix: the single wrapper folder to strip, "" when there is none
##   formats: {extension: count} for the type's own extensions, present ones only
##   others: every other extension that survives the blocklist, {ext: count}
##   blocked: how many entries the blocklist drops
##   previews: paths of the pack's preview images, best first, empty when none
##   is_project: the archive carries a project.godot or a plugin.cfg
static func read(entries: PackedStringArray, type_id: String, archive_name: String = "") -> Dictionary:
	var root_prefix := _wrapper_folder(entries)
	var type_extensions: Array = AssetTypes.get_by_id(type_id).get("extensions", [])

	var formats: Dictionary = {}
	var others: Dictionary = {}
	var blocked := 0
	var is_project := false

	for entry in entries:
		if entry.ends_with("/"):
			continue

		var file_name := entry.get_file()
		if file_name == "project.godot" or file_name == "plugin.cfg":
			is_project = true

		if is_blocked(entry):
			blocked += 1
			continue

		var ext := entry.get_extension().to_lower()
		if type_extensions.has(ext):
			formats[ext] = formats.get(ext, 0) + 1
		else:
			others[ext] = others.get(ext, 0) + 1

	return {
		"root_prefix": root_prefix,
		"formats": formats,
		"others": others,
		"blocked": blocked,
		"previews": _find_previews(entries, root_prefix, archive_name),
		"is_project": is_project,
	}

## Folders holding the same filenames as each other, for one chosen format.
## A pack shipping "PNG/Default/bag.png" and "PNG/Large (2x)/bag.png" is
## shipping one sprite twice, and only the paths say so: the extension is the
## same either way, and the folder names are the author's to invent.
## Returns {folder: count}, empty when nothing is duplicated.
static func variants_for(entries: PackedStringArray, format: String) -> Dictionary:
	var by_folder: Dictionary = {}
	var seen_names: Dictionary = {}

	for entry in entries:
		if entry.ends_with("/") or is_blocked(entry):
			continue
		if entry.get_extension().to_lower() != format:
			continue

		var folder := entry.get_base_dir()
		var file_name := entry.get_file()
		if not by_folder.has(folder):
			by_folder[folder] = {}
		by_folder[folder][file_name] = true

		if not seen_names.has(file_name):
			seen_names[file_name] = []
		seen_names[file_name].append(folder)

	# Only folders that repeat a filename found somewhere else are variants.
	var duplicated: Dictionary = {}
	for file_name: String in seen_names:
		var folders: Array = seen_names[file_name]
		if folders.size() < 2:
			continue
		for folder: String in folders:
			duplicated[folder] = by_folder[folder].size()

	return duplicated if duplicated.size() > 1 else {}

static func is_blocked(entry: String) -> bool:
	for fragment in BLOCKED_FRAGMENTS:
		if entry.contains(fragment):
			return true
	return BLOCKED_EXTENSIONS.has(entry.get_extension().to_lower())

## Most packs wrap everything in one folder named after themselves, which would
## otherwise nest as <pack>/<pack>/. Some don't: files sit at the root. So the
## wrapper is only stripped when there is exactly one top-level name and
## something lives below it.
static func _wrapper_folder(entries: PackedStringArray) -> String:
	var tops: Dictionary = {}
	var has_nesting := false

	for entry in entries:
		var first: String = entry.split("/")[0]
		tops[first] = true
		if tops.size() > 1:
			return ""
		if entry.contains("/") and not entry.trim_suffix("/").is_empty():
			has_nesting = true

	if tops.size() != 1 or not has_nesting:
		return ""
	return String(tops.keys()[0]) + "/"

## Best first: a hinted name ("Preview.png") over one named after the pack
## itself, and shallow over deep. Capped, since a pack can ship one render per
## model and those are a catalogue rather than previews of the pack.
static func _find_previews(entries: PackedStringArray, root_prefix: String, archive_name: String = "") -> PackedStringArray:
	var stem := archive_name.get_basename().to_lower()
	var scored: Array[Dictionary] = []

	for entry in entries:
		if entry.ends_with("/") or is_blocked(entry):
			continue
		if not PREVIEW_EXTENSIONS.has(entry.get_extension().to_lower()):
			continue

		var below := entry.trim_prefix(root_prefix)
		var depth := below.count("/")
		if depth > PREVIEW_MAX_DEPTH:
			continue

		# An exact match beats a name that merely contains the word, and earlier
		# hints beat later ones, so the list itself sets the preference.
		var name := below.get_file().to_lower()
		var score := 0
		for i in PREVIEW_HINTS.size():
			var hint := PREVIEW_HINTS[i]
			if name.get_basename() == hint:
				score = 100 - i
				break
			if name.contains(hint):
				score = 50 - i
				break
		# Packs whose files are all named after the pack put the preview there
		# too, with none of the extra the texture maps carry.
		if score == 0 and not stem.is_empty() and stem.begins_with(name.get_basename()):
			score = 20
		if score == 0 and depth > 0:
			continue
		score -= depth

		scored.append({"path": entry, "score": score})

	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		return String(a["path"]).naturalnocasecmp_to(String(b["path"])) < 0
	)

	var paths := PackedStringArray()
	for entry: Dictionary in scored.slice(0, PREVIEW_LIMIT):
		paths.append(entry["path"])
	return paths
