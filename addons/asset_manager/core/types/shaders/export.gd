@tool
class_name ShadersExportHandler
extends RefCounted

## Copies a .gdshader into the project and writes a small wrapper beside it
## (a .tres ShaderMaterial for spatial/canvas_item, a .tscn with the right
## subject node for particles/fog/sky) so the shader drops in ready to use
## rather than as raw code the user has to wire up.

static func export_asset(source_path: String, dest_path: String, _bucket: String = "") -> Dictionary:
	var result := AssetExporter.new_result()

	AssetExporter.copy_one_file(source_path, dest_path, result)
	if not FileAccess.file_exists(dest_path):
		return result

	_copy_includes(source_path, dest_path, result, {})

	var shader := Shader.new()
	shader.code = FileAccess.get_file_as_string(source_path)
	var mode := shader.get_mode()

	match mode:
		Shader.MODE_SPATIAL, Shader.MODE_CANVAS_ITEM:
			_write_material_tres(dest_path, result)
		Shader.MODE_PARTICLES:
			_write_particles_tscn(dest_path, result)
		Shader.MODE_FOG:
			_write_fog_tscn(dest_path, result)
		Shader.MODE_SKY:
			_write_sky_tscn(dest_path, result)
		_:
			pass

	return result

## An #include is left in the copied shader untouched: the paths these packs
## use are relative to the shader itself, so mirroring the include's position
## below the destination is enough for it to resolve. Recursive, since an
## include can include. Missing files are the pack's own problem and warned
## about rather than failing the export.
static func _copy_includes(source_path: String, dest_path: String, result: Dictionary, seen: Dictionary) -> void:
	var regex := RegEx.new()
	regex.compile('#include\\s+"([^"]+)"')

	var source_dir := source_path.get_base_dir()
	for m in regex.search_all(FileAccess.get_file_as_string(source_path)):
		var raw_path: String = m.get_string(1)
		var include_source := PackPaths.resolve_pack_path(raw_path, source_dir, source_dir)
		if include_source.is_empty() or not FileAccess.file_exists(include_source):
			push_warning("AssetManager: missing shader include, not exported: " + raw_path)
			continue
		if seen.has(include_source):
			continue
		seen[include_source] = true

		var include_dest := dest_path.get_base_dir().path_join(raw_path)
		AssetExporter.copy_one_file(include_source, include_dest, result)
		_copy_includes(include_source, include_dest, result, seen)

static func _companion_path(dest_path: String, new_extension: String) -> String:
	return dest_path.get_basename() + "." + new_extension

static func _write_material_tres(dest_path: String, result: Dictionary) -> void:
	var shader_filename := dest_path.get_file()
	var tres_path := _companion_path(dest_path, "tres")
	if FileAccess.file_exists(tres_path):
		result["skipped_existing_count"] += 1
		return

	var file := FileAccess.open(tres_path, FileAccess.WRITE)
	if not file:
		result["errors"].append("Failed to write companion .tres: " + tres_path)
		return

	file.store_line('[gd_resource type="ShaderMaterial" format=3 uid="%s"]' % ResourceUidText.generate())
	file.store_line("")
	file.store_line('[ext_resource type="Shader" path="./%s" id="1_shader"]' % shader_filename)
	file.store_line("")
	file.store_line("[resource]")
	file.store_line('shader = ExtResource("1_shader")')

	result["copied_count"] += 1
	result["copied_paths"].append(ProjectSettings.localize_path(tres_path))

static func _write_particles_tscn(dest_path: String, result: Dictionary) -> void:
	var shader_filename := dest_path.get_file()
	var tscn_path := _companion_path(dest_path, "tscn")
	if FileAccess.file_exists(tscn_path):
		result["skipped_existing_count"] += 1
		return

	var file := FileAccess.open(tscn_path, FileAccess.WRITE)
	if not file:
		result["errors"].append("Failed to write companion .tscn: " + tscn_path)
		return

	file.store_line('[gd_scene format=3 uid="%s"]' % ResourceUidText.generate())
	file.store_line("")
	file.store_line('[ext_resource type="Shader" path="./%s" id="1_shader"]' % shader_filename)
	file.store_line("")
	file.store_line('[sub_resource type="ShaderMaterial" id="ShaderMaterial_1"]')
	file.store_line('shader = ExtResource("1_shader")')
	file.store_line("")
	file.store_line('[sub_resource type="SphereMesh" id="SphereMesh_1"]')
	file.store_line("radius = 0.1")
	file.store_line("height = 0.2")
	file.store_line("")
	file.store_line('[node name="%s" type="GPUParticles3D"]' % dest_path.get_basename().get_file().capitalize().replace(" ", ""))
	file.store_line("emitting = true")
	file.store_line("amount = 16")
	file.store_line('process_material = SubResource("ShaderMaterial_1")')
	file.store_line('draw_pass_1 = SubResource("SphereMesh_1")')

	result["copied_count"] += 1
	result["copied_paths"].append(ProjectSettings.localize_path(tscn_path))

static func _write_fog_tscn(dest_path: String, result: Dictionary) -> void:
	var shader_filename := dest_path.get_file()
	var tscn_path := _companion_path(dest_path, "tscn")
	if FileAccess.file_exists(tscn_path):
		result["skipped_existing_count"] += 1
		return

	var file := FileAccess.open(tscn_path, FileAccess.WRITE)
	if not file:
		result["errors"].append("Failed to write companion .tscn: " + tscn_path)
		return

	file.store_line('[gd_scene format=3 uid="%s"]' % ResourceUidText.generate())
	file.store_line("")
	file.store_line('[ext_resource type="Shader" path="./%s" id="1_shader"]' % shader_filename)
	file.store_line("")
	file.store_line('[sub_resource type="FogMaterial" id="FogMaterial_1"]')
	file.store_line('shader = ExtResource("1_shader")')
	file.store_line("")
	file.store_line('[node name="%s" type="FogVolume"]' % dest_path.get_basename().get_file().capitalize().replace(" ", ""))
	file.store_line("size = Vector3(2, 2, 2)")
	file.store_line('material = SubResource("FogMaterial_1")')

	result["copied_count"] += 1
	result["copied_paths"].append(ProjectSettings.localize_path(tscn_path))

static func _write_sky_tscn(dest_path: String, result: Dictionary) -> void:
	var shader_filename := dest_path.get_file()
	var tscn_path := _companion_path(dest_path, "tscn")
	if FileAccess.file_exists(tscn_path):
		result["skipped_existing_count"] += 1
		return

	var file := FileAccess.open(tscn_path, FileAccess.WRITE)
	if not file:
		result["errors"].append("Failed to write companion .tscn: " + tscn_path)
		return

	file.store_line('[gd_scene format=3 uid="%s"]' % ResourceUidText.generate())
	file.store_line("")
	file.store_line('[ext_resource type="Shader" path="./%s" id="1_shader"]' % shader_filename)
	file.store_line("")
	file.store_line('[sub_resource type="ShaderMaterial" id="ShaderMaterial_1"]')
	file.store_line('shader = ExtResource("1_shader")')
	file.store_line("")
	file.store_line('[sub_resource type="Sky" id="Sky_1"]')
	file.store_line('sky_material = SubResource("ShaderMaterial_1")')
	file.store_line("")
	file.store_line('[sub_resource type="Environment" id="Environment_1"]')
	file.store_line("background_mode = 2")
	file.store_line('sky = SubResource("Sky_1")')
	file.store_line("")
	file.store_line('[node name="%s" type="WorldEnvironment"]' % dest_path.get_basename().get_file().capitalize().replace(" ", ""))
	file.store_line('environment = SubResource("Environment_1")')

	result["copied_count"] += 1
	result["copied_paths"].append(ProjectSettings.localize_path(tscn_path))
