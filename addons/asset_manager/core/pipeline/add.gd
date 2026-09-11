@tool
class_name AssetAdd
extends RefCounted

## Brings assets in from outside: a pack zip, or a single file already on disk.
## Reading a zip never writes anything, so the dialog can show what is inside
## before the user commits to it.

## Everything the dialog needs about a zip, or an "error" saying why not.
## Only the first preview is decoded here, so a pack shipping several doesn't
## hold the dialog open while they all load; the rest come through load_preview.
static func inspect(zip_path: String, type_id: String) -> Dictionary:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return {"error": "Could not open the archive."}

	var entries := reader.get_files()
	if entries.is_empty():
		reader.close()
		return {"error": "The archive is empty."}

	var info := ArchiveManifest.read(entries, type_id, zip_path.get_file())
	info["entries"] = entries

	var previews: PackedStringArray = info["previews"]
	info["preview_image"] = _read_preview(reader, previews[0]) if not previews.is_empty() else null
	reader.close()

	return info

## Which buckets a dropped file could belong to, best guess first. One entry
## means no question to ask; two or more means the extension is shared and only
## the user can say. Empty means nothing here is an asset.
## A zip is judged by what it holds, a loose file by AssetManagerContextMenu's
## own rule, which reads a .tres header rather than trusting the extension.
static func candidate_types(path: String) -> PackedStringArray:
	if path.get_extension().to_lower() != "zip":
		return AssetManagerContextMenu.buckets_for(path)

	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		return PackedStringArray()

	var entries := reader.get_files()
	reader.close()

	var counts: Dictionary = {}
	for entry in entries:
		if entry.ends_with("/") or ArchiveManifest.is_blocked(entry):
			continue
		var ext := entry.get_extension().to_lower()
		for type_entry in AssetTypes.ALL:
			var type_id: String = type_entry["id"]
			if type_id == AssetTypes.FALLBACK_ID:
				continue
			if type_entry.get("extensions", []).has(ext):
				counts[type_id] = counts.get(type_id, 0) + 1

	var found: Array = counts.keys()
	found.sort_custom(func(a: String, b: String) -> bool: return counts[a] > counts[b])

	var result := PackedStringArray()
	for type_id: String in found:
		result.append(type_id)
	return result

## One preview by path, for the ones inspect() left behind.
static func load_preview(zip_path: String, entry: String) -> Image:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return null

	var image := _read_preview(reader, entry)
	reader.close()
	return image

## Writes the archive's wanted files into the bucket. The chosen format is kept
## and its rivals dropped; everything else that survives the blocklist comes,
## since a texture or a .bin is needed by whatever references it.
## Returns AssetExporter's result shape, plus "skipped_format_count".
static func extract(zip_path: String, type_id: String, format: String, variant: String, dest_root: String) -> Dictionary:
	var result := AssetExporter.new_result()
	result["skipped_format_count"] = 0

	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		result["errors"].append("Could not open the archive: " + zip_path)
		return result

	var entries := reader.get_files()
	var info := ArchiveManifest.read(entries, type_id, zip_path.get_file())
	var root_prefix: String = info["root_prefix"]
	var rivals: Dictionary = info["formats"]
	var variants := ArchiveManifest.variants_for(entries, format)

	for entry in entries:
		if entry.ends_with("/") or ArchiveManifest.is_blocked(entry):
			continue

		var ext := entry.get_extension().to_lower()
		if rivals.has(ext) and ext != format:
			result["skipped_format_count"] += 1
			continue

		# The same files shipped at two sizes, or in two layouts: only the
		# chosen folder comes.
		if ext == format and not variant.is_empty() and entry.get_base_dir() != variant:
			if variants.has(entry.get_base_dir()):
				result["skipped_format_count"] += 1
				continue

		var below := _safe_relative(entry, root_prefix)
		if below.is_empty():
			result["errors"].append("Refused an unsafe path in the archive: " + entry)
			continue

		_write_one(reader, entry, dest_root.path_join(below), result)

	reader.close()
	return result

## Strips the wrapper folder, and refuses anything that would climb out of the
## destination: a zip can name "../" and nothing in ZIPReader stops it.
static func _safe_relative(entry: String, root_prefix: String) -> String:
	var below := entry.trim_prefix(root_prefix)
	if below.is_empty() or below.begins_with("/"):
		return ""
	for segment in below.split("/"):
		if segment == ".." or segment == ".":
			return ""
	return below

static func _write_one(reader: ZIPReader, entry: String, dest_path: String, result: Dictionary) -> void:
	if FileAccess.file_exists(dest_path):
		result["skipped_existing_count"] += 1
		return

	var dest_dir := dest_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dest_dir):
		DirAccess.make_dir_recursive_absolute(dest_dir)

	var bytes := reader.read_file(entry)
	if bytes.is_empty():
		result["errors"].append("Could not read from the archive: " + entry)
		return

	var file := FileAccess.open(dest_path, FileAccess.WRITE)
	if file == null:
		result["errors"].append("Could not write: " + dest_path)
		return

	file.store_buffer(bytes)
	file.close()
	result["copied_count"] += 1

## Loaded from the archive's bytes, so nothing is written to show a preview.
static func _read_preview(reader: ZIPReader, path: String) -> Image:
	if path.is_empty():
		return null

	var bytes := reader.read_file(path)
	if bytes.is_empty():
		return null

	var image := Image.new()
	var err := FAILED
	match path.get_extension().to_lower():
		"png":
			err = image.load_png_from_buffer(bytes)
		"jpg", "jpeg":
			err = image.load_jpg_from_buffer(bytes)
		"webp":
			err = image.load_webp_from_buffer(bytes)

	return image if err == OK else null
