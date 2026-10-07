@tool
class_name AssetExporter
extends RefCounted
## The lookup is NOT automatic, a new type needs its entry adding to HANDLERS
## or it silently exports as a plain file copy. GDScript has no runtime "load
## this script if it exists" that works under export/packing, so the dict is
## the explicit trade for that.

const HANDLERS: Dictionary = {
	"models": preload("res://addons/asset_manager/core/types/models/export.gd"),
	"hdris": preload("res://addons/asset_manager/core/types/hdris/export.gd"),
	"themes": preload("res://addons/asset_manager/core/types/themes/export.gd"),
	"materials": preload("res://addons/asset_manager/core/types/materials/export.gd"),
	"shaders": preload("res://addons/asset_manager/core/types/shaders/export.gd"),
	"effects": preload("res://addons/asset_manager/core/types/effects/export.gd"),
	"scenes": preload("res://addons/asset_manager/core/types/scenes/export.gd"),
	"unreal": preload("res://addons/asset_manager/core/types/unreal/export.gd"),
}
const DEFAULT_HANDLER := preload("res://addons/asset_manager/core/types/default/export.gd")

## Shared by every type handler so the result shape and the copy primitive
## live in one place. Fields:
##   copied_count: int
##   skipped_existing_count: int, already present at dest, left untouched
##   errors: Array[String]
##   copied_paths: Array[String], res:// paths (via ProjectSettings.
##     localize_path) of everything actually copied this call, for the
##     caller to update_file()/reimport_files() against instead of a broad
##     EditorFileSystem.scan()
static func new_result() -> Dictionary:
	return {
		"copied_count": 0,
		"skipped_existing_count": 0,
		"errors": [],
		"copied_paths": [],
	}

## Copies one file into dest_path, creating parent folders as needed, and
## records the outcome into result (mutated in place). Skips (not an error)
## if dest_path already exists, "Send to Project" is safe to run repeatedly,
## it never overwrites.
static func copy_one_file(source_path: String, dest_path: String, result: Dictionary) -> void:
	if not FileAccess.file_exists(source_path):
		result["errors"].append("Source file missing, skipped: " + source_path)
		return

	if FileAccess.file_exists(dest_path):
		result["skipped_existing_count"] += 1
		return

	var dest_dir := dest_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dest_dir):
		DirAccess.make_dir_recursive_absolute(dest_dir)

	var err := DirAccess.copy_absolute(source_path, dest_path)
	if err == OK:
		result["copied_count"] += 1
		result["copied_paths"].append(ProjectSettings.localize_path(dest_path))
	else:
		result["errors"].append("Failed to copy (" + str(err) + "): " + source_path)

## Mirrors the asset's path below its type root into dest_dir. Anything less
## collapses the variant folders packs use to organise themselves, and two
## sources landing on one destination means the second is silently skipped by
## copy_one_file's "already exists" check.
static func export_asset(source_path: String, dest_dir: String, type_id: String, workspace_path: String) -> Dictionary:
	var handler: Variant = HANDLERS.get(type_id, DEFAULT_HANDLER)
	var dest_path := match_existing_case(_compute_dest_path(source_path, dest_dir, type_id, workspace_path))
	return handler.export_asset(source_path, dest_path, type_id)

## Spells each folder of path the way it already exists on disk. On a
## case-insensitive filesystem "res://assets" lands in an existing "Assets"
## folder, while the references written into the copies would still say
## "assets": Godot warns on every load, and the paths break on case-sensitive
## platforms. Folders that don't exist yet keep the spelling given.
static func match_existing_case(path: String) -> String:
	var prefix := "res://" if path.begins_with("res://") else "/"
	var segments := path.trim_prefix(prefix).split("/", false)
	var current := prefix

	for i in segments.size():
		var dir := DirAccess.open(current)
		if dir == null:
			return current.path_join("/".join(segments.slice(i)))

		var wanted: String = segments[i]
		var on_disk := wanted
		if not dir.dir_exists(wanted) and not dir.file_exists(wanted):
			return current.path_join("/".join(segments.slice(i)))

		dir.include_hidden = true
		for entry in dir.get_directories() + dir.get_files():
			if entry == wanted:
				on_disk = entry
				break
			if entry.nocasecmp_to(wanted) == 0:
				on_disk = entry

		current = current.path_join(on_disk)

	return current

static func _compute_dest_path(source_path: String, dest_dir: String, type_id: String, workspace_path: String) -> String:
	var bucket_root := workspace_path.path_join(type_id)
	if not source_path.begins_with(bucket_root):
		return dest_dir.path_join(source_path.get_file())

	var relative := source_path.trim_prefix(bucket_root)
	if relative.begins_with("/"):
		relative = relative.substr(1)
	if relative.is_empty():
		return dest_dir.path_join(source_path.get_file())

	return dest_dir.path_join(relative)
