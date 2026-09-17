@tool
class_name TscnSceneLoader
extends RefCounted

## Loads a .tscn from an absolute filesystem path outside any res:// project.
## Mirrors Godot's own ResourceLoaderText (scene/resources/resource_format_text.cpp):
## generic ClassDB.instantiate(type) + obj.set(property, value) per resource/node,
## same as the engine does, not a hand-rolled per-type interpreter.
## ext_resource/sub_resource path= that starts with the pack's fake "res://<Root>/"
## prefix is resolved against the real folder the .tscn actually sits in on disk.

## Godot's text resource formats, same grammar as .tscn, so _load_resource_file
## can build any of them regardless of what the ext_resource claims the type is.
const TEXT_RESOURCE_EXTENSIONS: PackedStringArray = ["tres", "res"]


## Applies its own deferred writes before returning, but only on the main
## thread. Off-thread the batch is left for the caller to replay later, because
## some writes compile a shader as a side effect and that is not thread-safe:
##   obj.set("process_material", …)
##     -> GPUParticles3D::set_process_material
##     -> ParticleProcessMaterial::_update_shader
##     -> ShaderLanguage::compile   <- crashes when two threads are in it
## Node.is_accessible_from_caller_thread() permits the write (the node isn't in a
## tree yet), so nothing warns, the shader compiler underneath simply isn't
## guarded. Confirmed from a dev build's symbolicated stack.
## A flag that determines if this asset has a script.
static var scripts_skipped: bool = false

static func load_external(path: String, bucket: String) -> Node:
	return load_external_in_pack(path, PackPaths.find_pack_root(path.get_base_dir(), bucket))

## For a scene nested inside one already being loaded: the pack root is known,
## so it's passed down rather than derived again from a bucket name.
static func load_external_in_pack(path: String, pack_root: String) -> Node:
	scripts_skipped = false
	var batch := _begin_batch()
	var node := _load_external_inner(path, pack_root)
	_end_batch(batch)
	apply_deferred_writes(batch)
	return node

## load_external's counterpart for a standalone resource file rather than a
## scene: same pack-relative path resolution, no node tree.
static func load_resource_external(path: String, bucket: String) -> Resource:
	return _load_resource_file(path, PackPaths.find_pack_root(path.get_base_dir(), bucket))

static func _load_external_inner(path: String, pack_root: String) -> Node:

	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("AssetManager: could not read " + path)
		return null

	var base_dir := path.get_base_dir()

	var ext_resources: Dictionary = {}   # id -> resolved Resource
	var sub_resources: Dictionary = {}   # id -> resolved Resource
	var root: Node = null
	var node_by_path: Dictionary = {}    # "." / "Child" / "Child/Grand" -> Node

	var lines := text.split("\n")
	var i := 0
	while i < lines.size():
		var line: String = lines[i].strip_edges()

		if line.begins_with("[ext_resource"):
			var fields := _parse_tag_fields(line)
			var id: String = fields.get("id", "")
			var res := _load_ext_resource(fields, base_dir, pack_root)
			if res != null:
				ext_resources[id] = res

		elif line.begins_with("[sub_resource"):
			var fields := _parse_tag_fields(line)
			var type: String = fields.get("type", "")
			var id: String = fields.get("id", "")
			var obj: Object = ClassDB.instantiate(type) if ClassDB.class_exists(type) else null
			if obj == null:
				i = _skip_block(lines, i + 1)
				continue
			i = _apply_properties(lines, i + 1, obj, ext_resources, sub_resources) - 1
			sub_resources[id] = obj

		elif line.begins_with("[node"):
			var fields := _parse_tag_fields(line)
			var type: String = fields.get("type", "")
			var name: String = fields.get("name", "")
			var parent_path: String = fields.get("parent", "")
			# A node built from another scene has no type= at all, just
			# instance=ExtResource("id"), packs that compose effects out of
			# sub-scenes (showcase/demo scenes especially) are made almost
			# entirely of these, and skipping them leaves an empty root.
			var node: Node = null
			var is_edit := false
			if fields.has("instance"):
				node = _instantiate_scene_ref(fields["instance"], ext_resources)
			elif ClassDB.class_exists(type):
				node = ClassDB.instantiate(type)
			elif type.is_empty() and root != null:
				# Neither type nor instance: the block edits a node an instanced
				# scene already brought (an editable child), the way a prefab
				# assigns materials to the mesh inside its model.
				var owner_node := _find_node(root, node_by_path, parent_path)
				node = owner_node.get_node_or_null(NodePath(name)) if owner_node != null else null
				is_edit = node != null

			if node == null:
				i = _skip_block(lines, i + 1)
				continue

			if root == null:
				node.name = name
				root = node
				node_by_path["."] = root
			else:
				if not is_edit:
					node.name = name
					var parent: Node = _find_node(root, node_by_path, parent_path)
					(parent if parent != null else root).add_child(node)
				var full_path: String = name if parent_path == "." else parent_path + "/" + name
				node_by_path[full_path] = node

			i = _apply_properties(lines, i + 1, node, ext_resources, sub_resources) - 1

		i += 1

	return root

## A parent named in the file, or one that only exists inside an instanced scene
## (parent="Mesh" below an instanced model), which the file never declared.
static func _find_node(root: Node, node_by_path: Dictionary, node_path: String) -> Node:
	var known: Variant = node_by_path.get(node_path)
	if known != null:
		return known
	return root.get_node_or_null(NodePath(node_path))

static func _set_owner_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		if child != owner:
			child.owner = owner
		_set_owner_recursive(child, owner)

## Builds a node from an `instance=ExtResource("id")` reference. The referenced
## PackedScene is already loaded by the ext_resource pass above (via
## _load_resource_file), so this only has to look it up and instantiate it.
static func _instantiate_scene_ref(raw_ref: String, ext_resources: Dictionary) -> Node:
	var regex := RegEx.new()
	regex.compile('ExtResource\\("([^"]+)"\\)')
	var m := regex.search(raw_ref)
	if m == null:
		return null

	var resource: Variant = ext_resources.get(m.get_string(1))
	if resource is PackedScene:
		return (resource as PackedScene).instantiate()

	return null

static func _parse_tag_fields(tag_line: String) -> Dictionary:
	var fields: Dictionary = {}
	var inner := tag_line.trim_prefix("[").trim_suffix("]")
	# Spaces around "=" are legal, some exporters write [node name = "X" ...].
	var regex := RegEx.new()
	regex.compile('(\\w+)\\s*=\\s*"([^"]*)"|(\\w+)\\s*=\\s*([^\\s\\]]+)')
	for m in regex.search_all(inner):
		if m.get_string(1) != "":
			fields[m.get_string(1)] = m.get_string(2)
		else:
			fields[m.get_string(3)] = m.get_string(4)
	return fields

## Resources resolved during the current load_external, keyed by real path.
## A pack's scenes share textures and sub-scenes heavily, and nested scenes each
## re-resolve their own, measured at 384 texture loads for 107 distinct files.
## Reusing them is safe because nothing here mutates a loaded resource; the
## exception is PackedScene, which is instantiated per use rather than shared.
static var _resource_cache: Dictionary = {}
## Paths another thread is currently loading, so we wait instead of duplicating.
static var _in_flight: Dictionary = {}
## The cache is now written from several loader threads at once.
static var _cache_mutex: Mutex = Mutex.new()

## ResourceLoader.load() is the one thing here that isn't ours, it pulls in
## Godot's whole import/UID subsystem, which is not written for arbitrary
## threads. Everything else in this file builds objects directly.
## False keeps ResourceLoader.load() on the main thread only, preload_binaries()
## fills the cache first, so a worker finds what it needs already loaded.
const ALLOW_THREADED_RESOURCE_LOAD: bool = false

## Skip every ext_resource when off the main thread, so a threaded load builds
## nodes and nothing else. Debug aid for narrowing down what's unsafe off-thread.
const SKIP_EXT_RESOURCES_OFF_THREAD: bool = false

## Property writes collected during an off-thread load, replayed by
## apply_deferred_writes() once back on the main thread.
## thread_local in spirit, each worker loads one scene at a time, so a plain
## static would have them trampling each other. Keyed by thread id instead.
## Serialises the writes that aren't safe concurrently, see _apply_properties.
static var _mesh_mutex: Mutex = Mutex.new()

## Properties whose setters do something thread-unsafe underneath. See the note
## in _apply_properties for what each one does and why.
const SERIALISED_PROPERTIES: PackedStringArray = [
	"process_material",
	"material",
	"material_override",
	"shader",
	"_surfaces",
]

static var _deferred_by_thread: Dictionary = {}
static var _deferred_mutex: Mutex = Mutex.new()

## Which batch the calling thread is currently filling. A nested load keeps using
## its parent's batch, so a whole scene tree replays as one unit.
static var _batch_by_thread: Dictionary = {}
## batch -> the batch that was open when it started, restored when it ends
static var _batch_parent: Dictionary = {}
static var _next_batch_id: int = 0

## The list for the batch this thread is filling, created on first use.
static var _deferred_writes: Array:
	get:
		var tid := OS.get_thread_caller_id()
		_deferred_mutex.lock()
		var batch: int = int(_batch_by_thread.get(tid, -1))
		if batch == -1:
			_deferred_mutex.unlock()
			return []
		if not _deferred_by_thread.has(batch):
			_deferred_by_thread[batch] = []
		var list: Array = _deferred_by_thread[batch]
		_deferred_mutex.unlock()
		return list

## Claims a fresh batch for this thread, remembering whichever was open so it
## can be restored on _end_batch.
static func _begin_batch() -> int:
	var tid := OS.get_thread_caller_id()
	_deferred_mutex.lock()
	var previous: int = int(_batch_by_thread.get(tid, -1))
	_next_batch_id += 1
	var batch := _next_batch_id
	_batch_by_thread[tid] = batch
	_batch_parent[batch] = previous
	_deferred_mutex.unlock()
	return batch

static func _end_batch(batch: int) -> void:
	if batch == -1:
		return
	_deferred_mutex.lock()
	var previous: int = int(_batch_parent.get(batch, -1))
	_batch_parent.erase(batch)
	if previous == -1:
		_batch_by_thread.erase(OS.get_thread_caller_id())
	else:
		_batch_by_thread[OS.get_thread_caller_id()] = previous
	_deferred_mutex.unlock()

## Main thread only. Applies everything one load collected, in the order the
## file declared it, then discards that batch.
## Keyed per load, not per thread: a worker handles many effects in a row, so
## a thread-keyed list would mix one scene's writes into the next.
static func apply_deferred_writes(batch_id: int) -> void:
	_deferred_mutex.lock()
	var list: Array = _deferred_by_thread.get(batch_id, [])
	_deferred_by_thread.erase(batch_id)
	_deferred_mutex.unlock()

	for write in list:
		# Check by id, not by touching the reference, reading a freed object
		# out of the array is itself the error we're guarding against.
		if not is_instance_id_valid(write[3]):
			continue
		var obj: Object = write[0]
		obj.set(write[1], write[2])

## Sharing one Resource between threads is safe to *refcount* (SafeRefCount is
## atomic) but not safe to *use*, two threads packing and instantiating the same
## PackedScene will corrupt it.
const ALLOW_RESOURCE_CACHE: bool = true

static func _can_use_resource_loader() -> bool:
	return ALLOW_THREADED_RESOURCE_LOAD or Thread.is_main_thread()

## Binary resources (.material/.mesh/.res) have to go through ResourceLoader,
## which is roughly 70x slower called off the main thread, 73ms a call versus
## well under one. So they're loaded up front, on the main thread, and the
## threaded parse reads them from here instead of calling load() itself.
## Call preload_binaries(path) on the main thread before handing a file to a
## worker. Scenes not preloaded still work; they just pay the slow path.
static func preload_binaries(path: String, bucket: String, seen: Dictionary = {}) -> void:
	if seen.has(path):
		return
	seen[path] = true

	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return

	var base_dir := path.get_base_dir()
	var pack_root := PackPaths.find_pack_root(base_dir, bucket)

	var regex := RegEx.new()
	regex.compile('\\[ext_resource[^\\]]*path="([^"]+)"')
	for m in regex.search_all(text):
		var real_path := PackPaths.resolve_pack_path(m.get_string(1), base_dir, pack_root)
		if real_path.is_empty() or not FileAccess.file_exists(real_path):
			continue

		# Nested scenes bring their own binaries, and they're parsed on the
		# worker too, so walk into them here rather than discovering them late.
		if real_path.get_extension().to_lower() == "tscn":
			preload_binaries(real_path, bucket, seen)
			continue

		if not BinaryResource.is_binary(real_path):
			continue

		_cache_mutex.lock()
		var already := _resource_cache.has(real_path)
		_cache_mutex.unlock()
		if already:
			continue

		var loaded: Resource = load(real_path)
		if loaded != null:
			_cache_mutex.lock()
			_resource_cache[real_path] = loaded
			_cache_mutex.unlock()

## Lives for a whole import rather than one effect: packs share textures across
## their scenes far more than within any single one, so a per-effect cache only
## caught a fraction of the reuse. The stage clears it when the run finishes,
## nothing on disk changes mid-import, so entries can't go stale during one.
static func clear_cache() -> void:
	_cache_mutex.lock()
	_resource_cache.clear()
	_in_flight.clear()
	_cache_mutex.unlock()
	PackPaths.clear_pack_files()

static func _load_ext_resource(fields: Dictionary, base_dir: String, pack_root: String) -> Resource:
	var type: String = fields.get("type", "unknown")

	var cache_key := PackPaths.resolve_pack_path(String(fields.get("path", "")), base_dir, pack_root) if ALLOW_RESOURCE_CACHE else ""

	# A cached PackedScene gets instantiate()d per use, and two threads doing that
	# to the same one at once is the sharing this cache is otherwise careful to
	# avoid. Nested scenes reload instead, they're expensive, but correct.
	if String(fields.get("type", "")) == "PackedScene":
		cache_key = ""

	# Threads that want the same file wait for whichever got there first, rather
	# than all loading it themselves. Without this the cache only helps once a
	# load has already finished, measured 149 loads of 22 distinct files.
	if not cache_key.is_empty():
		while true:
			_cache_mutex.lock()
			if _resource_cache.has(cache_key):
				var cached: Variant = _resource_cache[cache_key]
				_cache_mutex.unlock()
				return cached
			if not _in_flight.has(cache_key):
				_in_flight[cache_key] = true
				_cache_mutex.unlock()
				break
			_cache_mutex.unlock()
			OS.delay_msec(1)

	# Not locked here: _load_ext_resource_inner recurses into nested scenes, whose
	# property writes take _mesh_mutex, taking it here too would have a thread
	# waiting on a lock it already holds. The writes inside are what's guarded.
	var result := _load_ext_resource_inner(fields, base_dir, pack_root)

	if not cache_key.is_empty():
		_cache_mutex.lock()
		if result != null:
			_resource_cache[cache_key] = result
		_in_flight.erase(cache_key)
		_cache_mutex.unlock()

	return result

static func _load_ext_resource_inner(fields: Dictionary, base_dir: String, pack_root: String) -> Resource:
	if SKIP_EXT_RESOURCES_OFF_THREAD and not Thread.is_main_thread():
		return null

	var type: String = fields.get("type", "")
	var raw_path: String = fields.get("path", "")
	var real_path := PackPaths.resolve_pack_path(raw_path, base_dir, pack_root)
	if real_path.is_empty() or not FileAccess.file_exists(real_path):
		push_warning("AssetManager: missing ext_resource (" + type + "): " + raw_path)
		return null

	match type:
		"Texture2D":
			# A Texture2D isn't necessarily an image file, procedural ones
			# (NoiseTexture2D, GradientTexture2D) are text resources describing
			# how to generate the pixels, which Image.load_from_file can't read
			# (ERR_FILE_UNRECOGNIZED) but the generic .tres path builds fine.
			if real_path.get_extension().to_lower() in TEXT_RESOURCE_EXTENSIONS:
				if BinaryResource.is_binary(real_path):
					if not _can_use_resource_loader():
						return null
					var loaded_tex := load(real_path)
					return loaded_tex
				return _load_resource_file(real_path, pack_root)
			# Only a pack's material maps can be shrunk: elsewhere a texture may
			# be cut up by pixel regions (atlases, sprite regions, styleboxes).
			var img := PreviewTextureCache.load_image(real_path) if UnrealPack.is_pack_root(pack_root) \
				else Image.load_from_file(real_path)
			return ImageTexture.create_from_image(img) if img else null
		"Shader":
			# A Shader ext_resource isn't always raw .gdshader source, a
			# VisualShader (node graph) is a text resource that extends Shader,
			# and feeding its .tres text to shader.code would just fail to compile.
			if real_path.get_extension().to_lower() in TEXT_RESOURCE_EXTENSIONS:
				return _load_resource_file(real_path, pack_root)
			var shader := Shader.new()
			shader.code = PackPaths.resolve_shader_includes(FileAccess.get_file_as_string(real_path), real_path, pack_root)
			return shader
		"Script":
			scripts_skipped = true
			push_warning("AssetManager: skipping script (not executed in preview): " + real_path)
			return null
		"PackedScene":
			# A model instanced straight into a scene (a prefab wrapping its
			# .glb) is a source file a project would import, not a .tscn.
			if GltfSceneLoader.MODEL_EXTENSIONS.has(real_path.get_extension().to_lower()):
				return _pack_model(real_path)
			# load_external applies its own writes before returning, which matters
			# here: this tree is packed and freed immediately, so anything left
			# deferred would point at freed nodes, and pack() would capture the
			# scene before its properties were set.
			var nested := load_external_in_pack(real_path, pack_root)
			if nested == null:
				return null

			# pack() only keeps descendants owned by the root (packed_scene.cpp
			# skips anything else), and nothing sets owner while parsing, so
			# without this the nested scene packs down to a bare root node.
			_set_owner_recursive(nested, nested)
			var packed := PackedScene.new()
			packed.pack(nested)
			nested.queue_free()
			return packed
		"FontFile":
			# A font ext_resource is usually the raw .ttf/.otf rather than a
			# Godot resource, which has no [gd_resource] header to parse.
			if real_path.get_extension().to_lower() in TEXT_RESOURCE_EXTENSIONS:
				return _load_resource_file(real_path, pack_root)
			var font := FontFile.new()
			font.load_dynamic_font(real_path)
			return font
		"Environment", "Resource", "ArrayMesh", "Material", "StyleBox":
			# .obj is a Wavefront file, not a Godot resource, the engine only
			# reads it through an editor-side importer, so parse it ourselves.
			if real_path.get_extension().to_lower() == "obj":
				return ObjMeshLoader.load_external(real_path)
			# These types get saved as either plain-text .tres (readable, same
			# grammar as .tscn) or Godot's compressed binary format (RSCC magic
			# bytes), only the text form can be hand-parsed; binary has no
			# decoder exposed to GDScript and can't go through load() either
			# (requires the file to be import-registered in an open project).
			if BinaryResource.is_binary(real_path):
				if not _can_use_resource_loader():
					return null
				var direct: Resource = load(real_path)
				if direct == null:
					push_warning("AssetManager: binary resource not supported: " + real_path)
				return direct
			return _load_resource_file(real_path, pack_root)
		"AudioStream":
			return _load_audio_file(real_path)
		_:
			# Any other resource saved as text builds the same way, whatever it
			# is (a level's CameraAttributesPractical, say).
			if real_path.get_extension().to_lower() in TEXT_RESOURCE_EXTENSIONS \
					and not BinaryResource.is_binary(real_path) \
					and ClassDB.is_parent_class(type, "Resource"):
				return _load_resource_file(real_path, pack_root)
			push_warning("AssetManager: unsupported ext_resource type: " + type)
			return null

## Owners are set for the same reason as a nested .tscn: pack() drops any node
## the root doesn't own, and the editable children a prefab reaches into
## ("Mesh") have to survive it.
static func _pack_model(real_path: String) -> PackedScene:
	var model := GltfSceneLoader.load_external(real_path)
	if model == null:
		push_warning("AssetManager: could not load model: " + real_path)
		return null

	_set_owner_recursive(model, model)
	var packed := PackedScene.new()
	packed.pack(model)
	model.free()
	return packed

## Standalone text resource files ([gd_resource type="X"] header) share the same
## ext_resource/sub_resource grammar as .tscn, reuse the same block-walking
## engine, just build the single top-level resource instead of a node tree.
static func _load_resource_file(real_path: String, pack_root: String) -> Resource:
	var text := FileAccess.get_file_as_string(real_path)
	if text.is_empty():
		return null

	var header_match := RegEx.new()
	header_match.compile('\\btype\\s*=\\s*"([^"]+)"')
	var m := header_match.search(text.split("\n")[0])
	if not m:
		push_warning("AssetManager: unrecognized resource header: " + real_path)
		return null
	var top_type := m.get_string(1)
	if not ClassDB.class_exists(top_type):
		push_warning("AssetManager: unknown resource type: " + top_type)
		return null

	var base_dir := real_path.get_base_dir()
	var ext_resources: Dictionary = {}
	var sub_resources: Dictionary = {}
	var top_obj: Resource = ClassDB.instantiate(top_type)

	var lines := text.split("\n")
	var i := 1
	while i < lines.size():
		var line: String = lines[i].strip_edges()

		if line.begins_with("[ext_resource"):
			var fields := _parse_tag_fields(line)
			var id: String = fields.get("id", "")
			var res := _load_ext_resource(fields, base_dir, pack_root)
			if res != null:
				ext_resources[id] = res

		elif line.begins_with("[sub_resource"):
			var fields := _parse_tag_fields(line)
			var type: String = fields.get("type", "")
			var id: String = fields.get("id", "")
			var obj: Object = ClassDB.instantiate(type) if ClassDB.class_exists(type) else null
			if obj == null:
				i = _skip_block(lines, i + 1)
				continue
			i = _apply_properties(lines, i + 1, obj, ext_resources, sub_resources) - 1
			sub_resources[id] = obj

		elif line.begins_with("[resource"):
			i = _apply_properties(lines, i + 1, top_obj, ext_resources, sub_resources) - 1

		i += 1

	return top_obj

## Audio has no raw-file decoder exposed to GDScript per format the way Image
## does, build the right AudioStream subtype from the extension and hand it
## the bytes directly (these load the data eagerly, no import step needed).
static func _load_audio_file(real_path: String) -> AudioStream:
	var ext := real_path.get_extension().to_lower()
	var bytes := FileAccess.get_file_as_bytes(real_path)
	match ext:
		"wav":
			return AudioStreamWAV.load_from_file(real_path)
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
		"mp3":
			var stream := AudioStreamMP3.new()
			stream.data = bytes
			return stream
		_:
			push_warning("AssetManager: unsupported audio extension: " + ext)
			return null

static func _apply_properties(lines: PackedStringArray, start_i: int, obj: Object, ext_resources: Dictionary, sub_resources: Dictionary) -> int:
	var i := start_i
	while i < lines.size():
		var line: String = lines[i].strip_edges()
		if line.begins_with("[") or (line.is_empty() and i + 1 < lines.size() and lines[i + 1].strip_edges().begins_with("[")):
			break
		if line.is_empty():
			i += 1
			continue

		var eq := line.find(" = ")
		if eq == -1:
			i += 1
			continue

		var prop_name := line.substr(0, eq)
		var value_str := line.substr(eq + 3)

		# Multi-line values (e.g. ArrayMesh _surfaces = [{...}] spanning many
		# lines), keep appending lines until brackets/braces/parens balance,
		# same idea as Godot's own tokenizer, before handing to str_to_var().
		while not _is_balanced(value_str) and i + 1 < lines.size():
			i += 1
			value_str += "\n" + lines[i]

		var value: Variant = _parse_value(value_str, ext_resources, sub_resources)
		# Only NODE writes are deferred, obj.set() on a node reaches into
		# transforms, visibility and notifications. Resources are plain data
		# and write fine anywhere, they also can't be postponed: a
		# ShaderMaterial only accepts shader_parameter/* once its shader is
		# assigned, and a sub-resource referenced by another must already
		# hold its values when that reference is resolved.
		#
		# SERIALISED_PROPERTIES are the writes that can't happen off-thread at
		# all, even on resources:
		#   - ShaderLanguage::compile is not thread-safe and nothing guards it.
		#     A dev build's stack showed two workers inside it via:
		#       set("process_material") -> ParticleProcessMaterial::_update_shader
		#         -> shader_create_from_code -> ShaderLanguage::compile  <- crash
		#   - ArrayMesh._surfaces pushes mesh_initialize, blend_shape_count,
		#     then one mesh_add_surface per surface, as SEPARATE commands
		#     (rendering_server_default.h:363-386). Two threads doing that at
		#     once interleave their pushes into one queue, and a mesh_initialize
		#     landing between another mesh's add_surface calls corrupts both.
		#     texture_2d_create is a single push, which is why it's fine
		#     off-thread and this isn't.
		var needs_serialising := not Thread.is_main_thread() and prop_name in SERIALISED_PROPERTIES

		# Checked before the Node deferral, so a node property that compiles a
		# shader is serialised here rather than replayed later. Nested scenes
		# are packed inside the loader and never see their deferred writes.
		if needs_serialising:
			_mesh_mutex.lock()
			obj.set(prop_name, value)
			_mesh_mutex.unlock()
		elif obj is Node and not Thread.is_main_thread():
			_deferred_writes.append([obj, prop_name, value, obj.get_instance_id()])
		else:
			obj.set(prop_name, value)
		i += 1
	return i

static func _is_balanced(s: String) -> bool:
	# The native counts are the fast path for the megabyte-long vertex arrays,
	# which never hold a string.
	if not s.contains("\""):
		return s.count("[") == s.count("]") \
			and s.count("(") == s.count(")") \
			and s.count("{") == s.count("}")
	return _is_balanced_outside_strings(s)

## A string value can span lines and carry " = " and brackets of its own, a
## VisualShader expression node stores its whole GLSL body that way. Only what
## sits outside quotes counts, and an open quote means the value goes on.
static func _is_balanced_outside_strings(s: String) -> bool:
	var depth := 0
	var in_string := false
	var escaped := false
	for c in s:
		if in_string:
			if escaped:
				escaped = false
			elif c == "\\":
				escaped = true
			elif c == "\"":
				in_string = false
			continue
		match c:
			"\"":
				in_string = true
			"[", "(", "{":
				depth += 1
			"]", ")", "}":
				depth -= 1
	return depth <= 0 and not in_string

static func _parse_value(value_str: String, ext_resources: Dictionary, sub_resources: Dictionary) -> Variant:
	var placeholders: Dictionary = {}

	var ext_re := RegEx.new()
	ext_re.compile('ExtResource\\("([^"]+)"\\)')
	for m in ext_re.search_all(value_str):
		var token := "__EXTRES_%d__" % placeholders.size()
		placeholders[token] = ext_resources.get(m.get_string(1))
		value_str = value_str.replace(m.get_string(0), "\"%s\"" % token)

	var sub_re := RegEx.new()
	sub_re.compile('SubResource\\("([^"]+)"\\)')
	for m in sub_re.search_all(value_str):
		var token := "__SUBRES_%d__" % placeholders.size()
		placeholders[token] = sub_resources.get(m.get_string(1))
		value_str = value_str.replace(m.get_string(0), "\"%s\"" % token)

	var result: Variant = str_to_var(value_str)
	if result == null:
		return placeholders.values()[0] if placeholders.size() == 1 else value_str

	return _replace_placeholders(result, placeholders)

static func _replace_placeholders(value: Variant, placeholders: Dictionary) -> Variant:
	if value is String and placeholders.has(value):
		return placeholders[value]
	if value is Array:
		var out := []
		for item in value:
			out.append(_replace_placeholders(item, placeholders))
		return out
	if value is Dictionary:
		var out := {}
		for key in value:
			out[_replace_placeholders(key, placeholders)] = _replace_placeholders(value[key], placeholders)
		return out
	return value

static func _skip_block(lines: PackedStringArray, start_i: int) -> int:
	var i := start_i
	while i < lines.size() and not lines[i].strip_edges().begins_with("["):
		i += 1
	return i
