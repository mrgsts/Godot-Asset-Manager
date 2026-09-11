@tool
class_name VendorPrefixes
extends RefCounted

## Reads the vendor out of a pack's filename, so two packs by one author land
## under one folder rather than side by side at the bucket root.
## A suggestion only: the dialog shows what it found and the user can change it.

## Folder name the vendor gets, and the lowercase fragments that identify it in
## a filename. Longest match wins, so "kaylousberg" beats "kay".
const KNOWN: Dictionary = {
	"Kenney": ["kenney"],
	"KayKit": ["kaykit", "kaylousberg"],
	"Quaternius": ["quaternius"],
	"Poly Haven": ["polyhaven", "poly_haven"],
	"ambientCG": ["ambientcg"],
	"Tiny Treats": ["tinytreats", "tiny_treats"],
	"Synty": ["synty"],
	"Poly Pizza": ["polypizza", "poly_pizza"],
}

## Everything a pack name carries that is not part of its own name: the vendor,
## a version, a format or licence marker, an archive suffix.
const NOISE: PackedStringArray = [
	"standard", "extended", "commercial", "personal", "free", "pack",
	"assets", "asset", "kit", "bundle", "collection", "unity", "unreal",
	"godot", "fbx", "gltf", "glb", "obj", "blend",
]

## Returns {vendor, name}. Vendor is "" when nothing is recognised, and the
## name is then the filename cleaned up but otherwise untouched.
static func read(file_name: String) -> Dictionary:
	var stem := file_name.get_basename()
	var haystack := stem.to_lower()

	var vendor := ""
	var matched := ""
	for name: String in KNOWN:
		for alias: String in KNOWN[name]:
			if haystack.contains(alias) and alias.length() > matched.length():
				matched = alias
				vendor = name

	return {"vendor": vendor, "name": _clean_name(stem, matched)}

## Drops the vendor, any version tail and the words every pack shares, so
## "kenney_city-kit-industrial_2.0" reads as "city-kit-industrial".
static func _clean_name(stem: String, matched_prefix: String) -> String:
	var working := stem
	if not matched_prefix.is_empty():
		var at := working.to_lower().find(matched_prefix)
		if at != -1:
			working = working.substr(0, at) + working.substr(at + matched_prefix.length())

	var parts: Array[String] = []
	for raw in working.replace("_", " ").replace("[", " ").replace("]", " ").split(" ", false):
		var part: String = raw.strip_edges()
		if part.is_empty() or NOISE.has(part.to_lower()):
			continue
		# A version tail ("2.0", "v1", "1.7.0") names the download, not the pack.
		if part.trim_prefix("v").replace(".", "").is_valid_int():
			continue
		parts.append(part)

	var name := "_".join(parts).strip_edges()
	return name if not name.is_empty() else stem
