@tool
class_name GltfSceneLoader
extends RefCounted

## Builds a node tree from a .glb/.gltf/.fbx outside res://, without the import
## step a project would run. Safe off the main thread: GLTFDocument's only shared
## state is its document-extension list, mutexed (gltf_document.cpp:6965), and
## embedded-texture creation goes through RenderingServer::texture_2d_create
## (rendering_server_default.h:147), which pushes onto the command queue when
## called off the render thread.

const MODEL_EXTENSIONS: PackedStringArray = ["glb", "gltf", "fbx"]

static func load_external(path: String) -> Node3D:
	var state := GLTFState.new()
	state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED

	var err: int = FAILED
	var node: Node = null

	if path.get_extension().to_lower() == "fbx":
		var fbx := FBXDocument.new()
		err = fbx.append_from_file(path, state)
		if err == OK:
			node = fbx.generate_scene(state)
	else:
		var gltf := GLTFDocument.new()
		err = gltf.append_from_file(path, state)
		if err == OK:
			node = gltf.generate_scene(state)

	if err != OK or node == null:
		return null

	# GLTF hands back ImporterMeshInstance3D, which carries no drawable mesh.
	return _convert_importer_meshes(node) as Node3D

static func _convert_importer_meshes(node: Node) -> Node:
	if not is_instance_valid(node):
		return node

	var result: Node = node

	if node.get_class() == "ImporterMeshInstance3D":
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = node.name
		if node is Node3D:
			mesh_instance.transform = (node as Node3D).transform

		var importer_mesh: Variant = node.get("mesh")
		if importer_mesh != null and importer_mesh.has_method("get_mesh"):
			mesh_instance.mesh = importer_mesh.get_mesh()

		for child in node.get_children():
			node.remove_child(child)
			mesh_instance.add_child(child)

		var parent := node.get_parent()
		if parent != null:
			var index := node.get_index()
			parent.remove_child(node)
			parent.add_child(mesh_instance)
			parent.move_child(mesh_instance, index)
		node.free()

		result = mesh_instance

	for child in result.get_children():
		_convert_importer_meshes(child)

	return result
