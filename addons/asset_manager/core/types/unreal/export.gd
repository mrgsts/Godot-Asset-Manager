@tool
class_name UnrealExportHandler
extends RefCounted

## Sends a file from an Unreal2Godot pack into a project with everything it needs,
## laid out below <export root>/<pack>/ exactly as the exporter laid it out.
## Packs are kept apart on purpose: every export has its own Prefabs/, Shaders/
## and Engine/ at the root, and two packs routinely ship different files under
## the same name there (SM_Bed.tscn, BasicShapeMaterial.tres), so merging them
## into one res:// would hand one pack the other's files.

static func export_asset(source_path: String, dest_path: String, bucket: String = UnrealPack.BUCKET) -> Dictionary:
	var result := AssetExporter.new_result()

	var pack_root := DependencyWalker.pack_root_for(source_path, bucket)
	var pack_dest_root := DependencyWalker.pack_dest_root_for(source_path, pack_root, dest_path)

	var copy_map: Dictionary = {source_path: dest_path}
	DependencyWalker.collect_dependencies(source_path, pack_root, pack_dest_root, copy_map)

	for dep_source: String in copy_map:
		AssetExporter.copy_one_file(dep_source, str(copy_map[dep_source]), result)

	DependencyWalker.rewrite_dependencies(copy_map, pack_root, result)
	DependencyWalker.repoint_binaries(copy_map, pack_root, result)

	_copy_import_settings(copy_map, result)
	_renew_header_uids(result["copied_paths"])

	return result

## The exporter's .import files carry settings a fresh import would not guess,
## normal maps flagged as such and VRAM compression, so they travel with their
## sources. Counted apart: the summary is about assets, not sidecars.
static func _copy_import_settings(copy_map: Dictionary, result: Dictionary) -> void:
	var sidecars := AssetExporter.new_result()
	for dep_source: String in copy_map:
		var sidecar := dep_source + ".import"
		if FileAccess.file_exists(sidecar):
			AssetExporter.copy_one_file(sidecar, str(copy_map[dep_source]) + ".import", sidecars)
	result["errors"].append_array(sidecars["errors"])

	# The import assigns a fresh uid where none is written, see _renew_header_uids.
	var uid_line := RegEx.new()
	uid_line.compile('(?m)^uid="[^"]*"\\n')
	for sidecar_path: String in sidecars["copied_paths"]:
		_rewrite(sidecar_path, func(text: String) -> String: return uid_line.sub(text, ""))

## The exporter derives uids from paths, so every pack gives WorldEnvironment.tscn,
## Prefabs/Plane.tscn and the rest the same uid: seven packs share 52 of them,
## and two packs sent into one project clash. References between the copies are
## already by path, so each copied scene or resource just takes a uid of its own.
static func _renew_header_uids(copied_paths: Array) -> void:
	var header_uid := RegEx.new()
	header_uid.compile('uid\\s*=\\s*"[^"]*"')
	for path: String in copied_paths:
		var ext := path.get_extension().to_lower()
		if ext != "tscn" and ext != "tres":
			continue
		_rewrite(path, func(text: String) -> String:
			var header_end := text.find("\n")
			var header := text.substr(0, header_end) if header_end != -1 else text
			if not (header.begins_with("[gd_scene") or header.begins_with("[gd_resource")):
				return text
			var renewed := header_uid.sub(header, 'uid="%s"' % ResourceUidText.generate())
			return renewed + text.substr(header.length())
		)

static func _rewrite(path: String, change: Callable) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return
	var changed: String = change.call(text)
	if changed == text:
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("AssetManager: could not renew uid in " + path)
		return
	file.store_string(changed)
	file.close()
