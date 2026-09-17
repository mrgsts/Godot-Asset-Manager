@tool
extends RefCounted

## Thumbnails for files inside Unreal2Godot packs, drawn the way the matching
## regular type draws them: a mesh as a model, a prefab or level as a scene, a
## material on a sphere. Scenes and materials load on the main thread, their
## loader builds textures and compiles shaders while parsing.

const MODELS := preload("res://addons/asset_manager/core/types/models/thumb.gd")

const SPHERE_RADIUS: float = 0.5

static func work_kind() -> int:
	return ThumbnailStage.WORK_VIEWPORT

static func reuses_main_viewport() -> bool:
	return true

## Runs on workers. A scene or material can't be built here, but the texture
## decode that dominates building one can, so the main-thread load that follows
## finds every map already shrunk in the preview cache.
static func prepare(path: String) -> Variant:
	if _is_model(path):
		return MODELS.prepare(path)
	for texture_path in UnrealPack.texture_paths(path):
		PreviewTextureCache.warm(texture_path)
	return null

static func build_subject(prepared: Variant, path: String) -> Node3D:
	if _is_model(path):
		return MODELS.build_subject(prepared, path)
	if path.get_extension().to_lower() == "tres":
		return _material_subject(path)
	return _scene_subject(path)

static func render_prepared(prepared: Variant, viewport: ThumbnailViewport, path: String) -> Image:
	var subject := build_subject(prepared, path)
	if subject == null:
		return null
	return await viewport.capture(subject)

static func _is_model(path: String) -> bool:
	return UnrealPack.MODEL_EXTENSIONS.has(path.get_extension().to_lower())

static func _scene_subject(path: String) -> Node3D:
	var node := TscnSceneLoader.load_external(path, UnrealPack.BUCKET)
	if node == null:
		return null
	if not (node is Node3D):
		node.free()
		return null
	return node as Node3D

static func _material_subject(path: String) -> Node3D:
	var material := TscnSceneLoader.load_resource_external(path, UnrealPack.BUCKET) as Material
	if material == null:
		return null

	var mesh := SphereMesh.new()
	mesh.radius = SPHERE_RADIUS
	mesh.height = SPHERE_RADIUS * 2.0

	var subject := MeshInstance3D.new()
	subject.mesh = mesh
	subject.material_override = material
	return subject
