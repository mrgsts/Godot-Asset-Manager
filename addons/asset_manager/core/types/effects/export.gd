@tool
class_name EffectsExportHandler
extends RefCounted

## Exports a .tscn outside res:// plus everything it depends on.
## Used by effects, scenes (scenes/export.gd) and themes (themes/export.gd).

static func export_asset(source_path: String, dest_path: String, bucket: String = "effects") -> Dictionary:
	var result := AssetExporter.new_result()

	var pack_root := DependencyWalker.pack_root_for(source_path, bucket)
	var pack_dest_root := DependencyWalker.pack_dest_root_for(source_path, pack_root, dest_path)

	# Source file -> destination file, for every file this effect needs.
	var copy_map: Dictionary = {source_path: dest_path}
	DependencyWalker.collect_dependencies(source_path, pack_root, pack_dest_root, copy_map)

	for dep_source: String in copy_map:
		AssetExporter.copy_one_file(dep_source, str(copy_map[dep_source]), result)

	DependencyWalker.rewrite_dependencies(copy_map, pack_root, result)
	DependencyWalker.repoint_binaries(copy_map, pack_root, result)

	return result
