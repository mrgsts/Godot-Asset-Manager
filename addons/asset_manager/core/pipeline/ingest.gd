@tool
class_name AssetIngest
extends RefCounted

## Copies an asset from a project into the workspace: the mirror of export.gd.
## The picked file goes to the root of a new pack folder, its dependencies keep
## the layout they had in the project below it.

static func ingest_asset(source_path: String, bucket: String, folder_name: String, workspace_path: String, vendor: String = "") -> Dictionary:
	var result := AssetExporter.new_result()

	var absolute_source := ProjectSettings.globalize_path(source_path)
	if not FileAccess.file_exists(absolute_source):
		result["errors"].append("Source file missing: " + source_path)
		return result

	var bucket_root := workspace_path.path_join(bucket)
	if not vendor.is_empty():
		bucket_root = bucket_root.path_join(vendor)
	var pack_dest_root := bucket_root.path_join(folder_name)
	var dest_path := pack_dest_root.path_join(absolute_source.get_file())

	var project_root := ProjectSettings.globalize_path("res://").rstrip("/")
	var copy_map: Dictionary = {absolute_source: dest_path}
	DependencyWalker.collect_dependencies(absolute_source, project_root, pack_dest_root, copy_map)

	_trim_shared_parents(copy_map, project_root, pack_dest_root, absolute_source, dest_path)

	for dep_source: String in copy_map:
		AssetExporter.copy_one_file(dep_source, str(copy_map[dep_source]), result)

	var path_map := _bucket_relative_paths(copy_map, workspace_path.path_join(bucket))
	DependencyWalker.rewrite_dependencies(copy_map, project_root, result, path_map)
	DependencyWalker.repoint_binaries(copy_map, project_root, result, path_map)

	return result

## A copied file still names the project it came from, which describes nothing
## once it is in the library, so the paths are rewritten the way Send to Project
## rewrites them on the way out.
## They are written from the bucket down, vendor folder and pack name included:
## two packs by one vendor share their internal layout, so anything shorter
## names a file in both of them.
static func _bucket_relative_paths(copy_map: Dictionary, bucket_root: String) -> Dictionary:
	var path_map: Dictionary = {}
	for dep_source: String in copy_map:
		var dest := str(copy_map[dep_source])
		path_map[dep_source] = "res://" + dest.trim_prefix(bucket_root).trim_prefix("/")
	return path_map

## A project keeps assets under folders that mean nothing once the pack is on
## its own ("assets/effects/SomePack/"), so those get dropped. Only a folder
## every file shares is removed, which is why two files can never end up on the
## same path: whatever made them different is below the part being cut.
static func _trim_shared_parents(copy_map: Dictionary, project_root: String, pack_dest_root: String, source_path: String, dest_path: String) -> void:
	var relatives: Array[PackedStringArray] = []
	for dep_source: String in copy_map:
		relatives.append(dep_source.trim_prefix(project_root).trim_prefix("/").split("/"))

	var trim := 0
	while true:
		var shared := ""
		var same := true
		for parts in relatives:
			if parts.size() - trim <= 1:
				same = false
				break
			if shared.is_empty():
				shared = parts[trim]
			elif parts[trim] != shared:
				same = false
				break
		if not same:
			break
		trim += 1

	if trim == 0:
		return

	var i := 0
	for dep_source: String in copy_map:
		var below := "/".join(relatives[i].slice(trim))
		copy_map[dep_source] = pack_dest_root.path_join(below)
		i += 1

	copy_map[source_path] = dest_path
