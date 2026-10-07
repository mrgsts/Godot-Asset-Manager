@tool
class_name AssetLink
extends RefCounted

## Brings a whole folder in without copying it: a symlink goes into the bucket
## pointing at the folder where it already is, and the normal scan reads
## through it, recursively and tagged by folder like anything copied in. The
## same trick UnrealPack uses for exports, for any bucket. "Send to Project"
## still copies the files a user picks, so a project never depends on the link.
## On Windows a symlink can need Developer Mode or an elevated prompt; that
## surfaces as an error rather than a silent copy.

## Names that say nothing about what is inside, so the link is named after
## the folder above instead ("CraftPix/3D" links as "CraftPix").
const GENERIC_NAMES: PackedStringArray = [
	"2d", "3d", "assets", "asset", "models", "model", "files", "content",
	"export", "exports", "library", "packs", "pack", "downloads", "download",
	"source", "src", "data", "resources", "art",
]

static func suggest_name(folder: String) -> String:
	folder = folder.trim_suffix("/")
	var name := folder.get_file()
	if GENERIC_NAMES.has(name.to_lower()):
		var parent := folder.get_base_dir().get_file()
		if not parent.is_empty():
			return parent
	return name

## Which buckets the folder's files could fill, most files first. Like
## AssetAdd.candidate_types for a zip: by extension only, and never the
## fallback bucket or a type that decides for itself what counts.
static func candidate_types(folder: String) -> PackedStringArray:
	var counts: Dictionary = {}
	_count_extensions(folder, counts)

	var type_counts: Dictionary = {}
	for type_entry in AssetTypes.ALL:
		var type_id: String = type_entry["id"]
		if type_id == AssetTypes.FALLBACK_ID:
			continue
		for ext: String in type_entry.get("extensions", []):
			if counts.has(ext):
				type_counts[type_id] = type_counts.get(type_id, 0) + counts[ext]

	var found: Array = type_counts.keys()
	found.sort_custom(func(a: String, b: String) -> bool: return type_counts[a] > type_counts[b])

	var result := PackedStringArray()
	for type_id: String in found:
		result.append(type_id)
	return result

static func _count_extensions(dir_path: String, counts: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			pass
		elif dir.current_is_dir():
			_count_extensions(dir_path.path_join(name), counts)
		else:
			var ext := name.get_extension().to_lower()
			if not ext.is_empty():
				counts[ext] = counts.get(ext, 0) + 1
		name = dir.get_next()
	dir.list_dir_end()

## Empty on success, otherwise why not.
static func validate_name(bucket_root: String, link_name: String) -> String:
	if link_name.strip_edges().is_empty():
		return "Give the link a name."
	if not link_name.is_valid_filename():
		return "The name can't contain : / \\ ? * \" | % < >"
	var dest := bucket_root.path_join(link_name)
	if DirAccess.dir_exists_absolute(dest) or FileAccess.file_exists(dest):
		return "Something named \"%s\" is already there." % link_name
	return ""

## Empty on success, otherwise the error to show.
static func link(source_folder: String, bucket_root: String, link_name: String) -> String:
	var problem := validate_name(bucket_root, link_name)
	if not problem.is_empty():
		return problem

	# A link to a folder holding the workspace would have the scan walk into
	# itself forever.
	source_folder = source_folder.trim_suffix("/")
	if (bucket_root + "/").begins_with(source_folder + "/"):
		return "Can't link a folder that contains the workspace: " + source_folder

	if not DirAccess.dir_exists_absolute(bucket_root):
		DirAccess.make_dir_recursive_absolute(bucket_root)
	var dir := DirAccess.open(bucket_root)
	if dir == null:
		return "Could not open " + bucket_root

	var err := dir.create_link(source_folder, bucket_root.path_join(link_name))
	if err != OK:
		return "Failed to link (%s): %s" % [error_string(err), source_folder]
	return ""
