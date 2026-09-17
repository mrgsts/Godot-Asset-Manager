@tool
class_name PreviewTextureCache
extends RefCounted

## A preview never shows a 4K map at 4K, but decoding one costs up to ~200ms: a
## level from a 4K texture pack took close to a minute to open, nearly all of it
## PNG decode. Large images are decoded once, shrunk and kept here; every later
## preview reads the small copy in a millisecond or two.
## Per machine, beside the settings, since it is only ever a cache. Keyed like
## the thumbnails, by path + mtime + size, so a changed texture is decoded again.
## Stateless and thread-safe: loaders call it from worker threads.

const MAX_SIZE: int = 1024
const CACHE_SUBDIR: String = "AssetManager/preview_textures"
const LOSSY: bool = true
const QUALITY: float = 0.9

static func load_image(path: String) -> Image:
	var cached := _cache_path(path)
	if not cached.is_empty() and FileAccess.file_exists(cached):
		var small := Image.load_from_file(cached)
		if small != null and not small.is_empty():
			return small

	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return image

	var longest := maxi(image.get_width(), image.get_height())
	if longest <= MAX_SIZE:
		return image

	var scale := float(MAX_SIZE) / float(longest)
	image.resize(
		maxi(1, int(image.get_width() * scale)),
		maxi(1, int(image.get_height() * scale)),
		Image.INTERPOLATE_BILINEAR
	)
	_store(image, cached)
	return image

## Decodes into the cache without keeping anything, for work spread over worker
## threads ahead of a main-thread load that would otherwise decode serially.
static func warm(path: String) -> void:
	var cached := _cache_path(path)
	if cached.is_empty() or FileAccess.file_exists(cached):
		return
	load_image(path)

static func _cache_path(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var size := file.get_length()
	file.close()

	var key := (path + "|" + str(FileAccess.get_modified_time(path)) + "|" + str(size)).md5_text()
	return OS.get_cache_dir().path_join(CACHE_SUBDIR).path_join(key.substr(0, 2)).path_join(key + ".webp")

## Written aside and renamed into place, two workers warming the same texture
## must never leave a half-written file for a reader to find.
static func _store(image: Image, cached: String) -> void:
	if cached.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(cached.get_base_dir())

	var to_save := image
	if image.get_format() != Image.FORMAT_RGBA8 and image.get_format() != Image.FORMAT_RGB8:
		to_save = image.duplicate() as Image
		to_save.convert(Image.FORMAT_RGBA8)

	var temp := "%s.%d.tmp" % [cached, OS.get_thread_caller_id()]
	if to_save.save_webp(temp, LOSSY, QUALITY) != OK:
		return
	DirAccess.rename_absolute(temp, cached)
