@tool
class_name UnrealImportRunner
extends RefCounted

## Scans the unreal/ bucket for Unreal2Godot exports, at any depth so packs can
## sit under a vendor folder, and lists what each one offers: prefabs, meshes,
## materials and levels. The pack's own layout is left alone.

static func run(bucket_root_path: String, type_entry: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for pack_root in UnrealPack.find_pack_roots(bucket_root_path):
		_scan_pack(pack_root, bucket_root_path, type_entry["id"], result)
	return result

static func _scan_pack(pack_root: String, bucket_root_path: String, type_id: String, result: Array[Dictionary]) -> void:
	# Vendor and pack name, the same folder tags every other bucket gets.
	var pack_tags := DefaultImportRunner._build_auto_tags(pack_root, bucket_root_path)

	for relative in UnrealPack.list_files(pack_root):
		var path := pack_root.path_join(relative)
		var kind := UnrealPack.kind_of(path, pack_root)
		if kind.is_empty():
			continue

		var tags: Array[String] = pack_tags.duplicate()
		var folder_tag := ""
		match kind:
			UnrealPack.KIND_MESH:
				folder_tag = UnrealPack.mesh_folder_tag(relative)
			UnrealPack.KIND_PREFAB:
				folder_tag = UnrealPack.mesh_folder_tag(UnrealPack.prefab_mesh_path(path))
		if not folder_tag.is_empty() and not tags.has(folder_tag):
			tags.append(folder_tag)

		result.append({
			"path": path,
			"type": type_id,
			"tags": tags,
			"subtype": [kind],
		})
