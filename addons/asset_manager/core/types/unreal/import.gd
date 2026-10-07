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
	# Vendor folder only ("Synty/Vintage_Environment" tags "synty"): the pack
	# root's own name is whatever the fab.com listing was called, which says
	# nothing about the content and can run to a whole sentence, so it is
	# replaced per file below by content_root_tag instead of tagged here.
	var vendor_tags := DefaultImportRunner._build_auto_tags(pack_root.get_base_dir(), bucket_root_path)

	for relative in UnrealPack.list_files(pack_root):
		var path := pack_root.path_join(relative)
		var kind := UnrealPack.kind_of(path, pack_root)
		if kind.is_empty():
			continue

		var tags: Array[String] = vendor_tags.duplicate()
		var content_tag := ""
		var folder_tag := ""
		match kind:
			UnrealPack.KIND_MESH:
				content_tag = UnrealPack.content_root_tag(relative, pack_root)
				folder_tag = UnrealPack.mesh_folder_tag(relative)
			UnrealPack.KIND_MATERIAL:
				content_tag = UnrealPack.content_root_tag(relative, pack_root)
			UnrealPack.KIND_PREFAB:
				var mesh_path := UnrealPack.prefab_mesh_path(path)
				content_tag = UnrealPack.content_root_tag(mesh_path, pack_root)
				folder_tag = UnrealPack.mesh_folder_tag(mesh_path)
		if not content_tag.is_empty() and not tags.has(content_tag):
			tags.append(content_tag)
		if not folder_tag.is_empty() and not tags.has(folder_tag):
			tags.append(folder_tag)

		result.append({
			"path": path,
			"type": type_id,
			"tags": tags,
			"subtype": [kind],
		})
