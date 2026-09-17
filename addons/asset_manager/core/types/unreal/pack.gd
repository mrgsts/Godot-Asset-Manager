@tool
class_name UnrealPack
extends RefCounted

## An Unreal2Godot export kept exactly as the exporter wrote it. The export is a
## whole Godot project: its res:// root holds Prefabs/, Shaders/, Engine/, the
## level scenes, and a folder named after the pack holding the Unreal content
## tree. Every file names the others by those res:// paths, so the library keeps
## the tree untouched and resolves paths against the project root instead of
## reorganising it into the other buckets.
## The content tree is whatever the Unreal project used, "Meshes/Props",
## "Mesh/CaveModules" or "Assets/Candle/Static_Mesh", so files are recognised by
## what they are, never by the folder they sit in.

const BUCKET: String = "unreal"
const PROJECT_FILE: String = PackPaths.PROJECT_FILE

## What tells an exported pack apart from any other Godot project.
const MARKER_DIRS: PackedStringArray = ["Prefabs", "Shaders"]

## Top-level folders nothing is catalogued from: engine stand-ins and generated
## shader graphs only matter as dependencies of what is.
const SKIPPED_DIRS: PackedStringArray = [".godot", "Engine", "Shaders"]

## Folders that only say "meshes are in here", skipped when a mesh takes its tag
## from the folder it sits in. Compared lowercased.
const GENERIC_MESH_FOLDERS: PackedStringArray = [
	"meshes", "mesh", "static_mesh", "static_meshes", "staticmesh", "staticmeshes",
	"models", "model", "assets", "geometry",
]

## Pack-root scenes that are plumbing for the levels rather than levels.
const NON_LEVEL_SCENES: PackedStringArray = ["WorldEnvironment.tscn"]

const MODEL_EXTENSIONS: PackedStringArray = GltfSceneLoader.MODEL_EXTENSIONS
const IMAGE_EXTENSIONS: PackedStringArray = ["png", "jpg", "jpeg", "webp", "tga", "bmp"]
const TEXT_EXTENSIONS: PackedStringArray = ["tscn", "tres"]

const KIND_PREFAB: String = "prefab"
const KIND_MESH: String = "mesh"
const KIND_MATERIAL: String = "material"
const KIND_LEVEL: String = "level"

## Exported packs get copied onto slow external drives by the gigabyte, a
## stray .DS_Store or an editor cache is never part of one.
const COPY_SKIPPED_FILES: PackedStringArray = [".DS_Store", "Thumbs.db", "desktop.ini"]

static func is_pack_root(dir_path: String) -> bool:
	if not FileAccess.file_exists(dir_path.path_join(PROJECT_FILE)):
		return false
	for marker in MARKER_DIRS:
		if not DirAccess.dir_exists_absolute(dir_path.path_join(marker)):
			return false
	return true

## Every pack at or below dir_path, not descending into a pack once found. A
## depth limit keeps a drop of some unrelated huge folder from walking all of it.
static func find_pack_roots(dir_path: String, max_depth: int = 3) -> PackedStringArray:
	var roots := PackedStringArray()
	_find_pack_roots(dir_path.rstrip("/"), max_depth, roots)
	return roots

static func _find_pack_roots(dir_path: String, depth_left: int, roots: PackedStringArray) -> void:
	if is_pack_root(dir_path):
		roots.append(dir_path)
		return
	if depth_left <= 0:
		return
	for sub in _subdirs(dir_path):
		if not sub.begins_with("."):
			_find_pack_roots(dir_path.path_join(sub), depth_left - 1, roots)

## "" when the file is not part of anything the library lists.
static func kind_of(file_path: String, pack_root: String) -> String:
	var relative := file_path.trim_prefix(pack_root.rstrip("/") + "/")
	var segments := relative.split("/")
	var ext := file_path.get_extension().to_lower()

	if segments.size() == 1:
		if ext == "tscn" and not NON_LEVEL_SCENES.has(segments[0]):
			return KIND_LEVEL
		return ""

	if SKIPPED_DIRS.has(segments[0]):
		return ""

	if ext == "tscn" and segments[0] == "Prefabs":
		return KIND_PREFAB
	if MODEL_EXTENSIONS.has(ext):
		return KIND_MESH
	if ext == "tres" and ResourceHeader.type_of(file_path).ends_with("Material"):
		return KIND_MATERIAL
	return ""

## Which of the regular previews shows a file from a pack. Decided by what the
## file is, so it needs no index lookup.
static func preview_type(file_path: String) -> String:
	var ext := file_path.get_extension().to_lower()
	if ext == "tscn":
		return "scenes"
	if MODEL_EXTENSIONS.has(ext):
		return "models"
	if ext == "tres":
		return "materials"
	return "other"

## The folder a model sits in, as a tag: "Meshes/Props/x.glb" is "props",
## "Assets/Candle/Static_Mesh/x.glb" is "candle". Generic container folders are
## climbed past; "" when only those and the pack's own folder hold it.
## path is relative to the pack root, or a res:// path from inside the pack.
static func mesh_folder_tag(path: String) -> String:
	# split(.., false) drops empty segments: the exporter sometimes writes
	# "res:///Engine/..." (an extra slash), which trim_prefix leaves as a
	# leading "/" and a plain split would keep as a leading "" segment,
	# shifting every check below onto the wrong folder.
	var segments := path.trim_prefix("res://").split("/", false)
	if segments.is_empty():
		return ""
	# Engine stand-ins (the Plane prefab's BasicShapes/Plane.glb) say nothing
	# about the pack's content.
	if SKIPPED_DIRS.has(segments[0]):
		return ""
	# The last segment is the file, the first the folder named after the pack.
	for i in range(segments.size() - 2, 0, -1):
		var folder := segments[i].strip_edges().to_lower().replace(" ", "_")
		if not folder.is_empty() and not GENERIC_MESH_FOLDERS.has(folder):
			return folder
	return ""

## A prefab is its model plus collision, so it takes the model's folder tag.
static func prefab_mesh_path(prefab_path: String) -> String:
	for raw_path in _ext_resource_paths(prefab_path):
		if MODEL_EXTENSIONS.has(raw_path.get_extension().to_lower()):
			return raw_path
	return ""

## Every image a prefab, level or material reaches, followed through the scenes
## and materials in between. Text only, and res:// resolves straight against the
## pack's project root, so it is safe on a worker thread.
static func texture_paths(file_path: String) -> PackedStringArray:
	var found := PackedStringArray()
	var pack_root := root_for(file_path)
	if pack_root.is_empty():
		return found

	var seen: Dictionary = {}
	var pending: Array[String] = [file_path]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		if seen.has(current):
			continue
		seen[current] = true

		for raw_path in _ext_resource_paths(current):
			# A stray "res:///..." (an extra slash) leaves a leading "/" after
			# trim_prefix, which path_join would carry into the result as a
			# double slash.
			var dep := pack_root.path_join(raw_path.trim_prefix("res://").trim_prefix("/"))
			var ext := dep.get_extension().to_lower()
			if IMAGE_EXTENSIONS.has(ext):
				if not found.has(dep):
					found.append(dep)
			elif TEXT_EXTENSIONS.has(ext) and not seen.has(dep):
				pending.append(dep)
	return found

## The nearest folder above file_path holding a project.godot, "" when none.
static func root_for(file_path: String) -> String:
	var dir := file_path.get_base_dir()
	while not dir.is_empty():
		if FileAccess.file_exists(dir.path_join(PROJECT_FILE)):
			return dir
		var parent := dir.get_base_dir()
		if parent == dir:
			break
		dir = parent
	return ""

## ext_resource tags come first in a text scene or resource, so reading stops at
## the first block after them: a prefab's collision data or a shader graph below
## runs to thousands of lines.
static func _ext_resource_paths(file_path: String) -> PackedStringArray:
	var paths := PackedStringArray()
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return paths

	var regex := RegEx.new()
	regex.compile('path="([^"]+)"')

	while not file.eof_reached():
		var line := file.get_line()
		if line.begins_with("[sub_resource") or line.begins_with("[node") or line.begins_with("[resource"):
			break
		if not line.begins_with("[ext_resource"):
			continue
		var found := regex.search(line)
		if found:
			paths.append(found.get_string(1))

	file.close()
	return paths

## Relative paths of every file a pack carries into the library. The .godot
## cache is the importer's output for one machine, rebuilt wherever the pack is
## opened; the .import files beside each source are kept, they hold the import
## settings (VRAM compression, normal maps) the exporter chose.
static func list_files(pack_root: String) -> PackedStringArray:
	var files := PackedStringArray()
	_list_files(pack_root.rstrip("/"), "", files)
	return files

static func _list_files(root: String, relative_dir: String, into: PackedStringArray) -> void:
	var dir := DirAccess.open(root.path_join(relative_dir))
	if dir == null:
		return

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var relative := relative_dir.path_join(entry) if not relative_dir.is_empty() else entry
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_list_files(root, relative, into)
		elif not COPY_SKIPPED_FILES.has(entry):
			into.append(relative)
		entry = dir.get_next()
	dir.list_dir_end()

static func _subdirs(dir_path: String) -> PackedStringArray:
	var names := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return names
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	return names
