class_name PackageLimits
extends RefCounted
## The install-time envelope a package is held to (ADR-0009, REQ-030).
##
## Every number here is also published in `docs/decisions/0009-package-trust.md`
## and `SECURITY.md`. The test reads these constants rather than a second copy, so
## the three cannot drift without one of them failing.
##
## The envelope is measured on what the engine can actually see. Godot 4.7's
## `ZIPReader` exposes files and bytes, not declared sizes, so there is no
## compression-ratio rule: the unpacked total already bounds the expansion, and a
## ratio would only be a second way to say the same thing.

## The archive itself, compressed. The largest built-in package is 74 KB.
const MAX_ZIP_BYTES := 8 * 1024 * 1024

## How many files an archive may hold. More than this is an archive, not a plugin.
const MAX_ENTRIES := 500

## One file, unpacked: a picture or a soundtrack, not a bundle of them.
const MAX_ENTRY_BYTES := 4 * 1024 * 1024

## Everything unpacked. The engine keeps referenced assets in memory while a
## scene plays, and a phone should not hold more than this.
const MAX_UNPACKED_BYTES := 32 * 1024 * 1024

## The same shape the repository tree check uses, so a package cannot carry a
## path that Windows, macOS and the web export disagree about.
const PATH_PATTERN := "^[a-z0-9][a-z0-9._/-]*$"

## Longest edge of a picture the renderer will accept.
const MAX_TEXTURE_EDGE := 4096

## Largest audio entry, and how long it may play.
const MAX_AUDIO_BYTES := 2 * 1024 * 1024
const MAX_AUDIO_SECONDS := 60.0


static func describe_bytes(count: int) -> String:
	## Megabytes with one decimal: the messages are read by package authors.
	return "%.1f MB" % (float(count) / (1024.0 * 1024.0))


static func archive_problem(zip_bytes: int) -> String:
	if zip_bytes <= MAX_ZIP_BYTES:
		return ""
	return "the package is %s, and the limit is %s" % [
		describe_bytes(zip_bytes), describe_bytes(MAX_ZIP_BYTES),
	]


static func entries_problem(count: int) -> String:
	if count <= MAX_ENTRIES:
		return ""
	return "the package holds %d entries, and the limit is %d" % [count, MAX_ENTRIES]


static func path_problem(path: String) -> String:
	if path.contains(".."):
		return "the path %s climbs out of the package" % path
	if path.begins_with("/"):
		return "the path %s is absolute" % path
	if path.contains("\\"):
		return "the path %s uses a backslash" % path
	if _regex(PATH_PATTERN).search(path) == null:
		return "the path %s is outside the allowed shape (lowercase letters, digits, dot, underscore, dash, slash)" % path
	return ""


static func entry_problem(path: String, size: int) -> String:
	if size <= MAX_ENTRY_BYTES:
		return ""
	return "%s is %s, and one entry may be at most %s" % [
		path, describe_bytes(size), describe_bytes(MAX_ENTRY_BYTES),
	]


static func total_problem(total: int) -> String:
	if total <= MAX_UNPACKED_BYTES:
		return ""
	return "the package unpacks to %s, and the limit is %s" % [
		describe_bytes(total), describe_bytes(MAX_UNPACKED_BYTES),
	]


static func texture_problem(path: String, size: Vector2i) -> String:
	## A picture whose header could not be read reports `Vector2i.ZERO` and is not
	## refused here; the renderer already degrades unknown bytes to a placeholder.
	if size == Vector2i.ZERO:
		return ""
	if size.x <= MAX_TEXTURE_EDGE and size.y <= MAX_TEXTURE_EDGE:
		return ""
	return "%s is %dx%d, and an edge may be at most %d px" % [
		path, size.x, size.y, MAX_TEXTURE_EDGE,
	]


static func audio_problem(path: String, bytes: int, seconds: float) -> String:
	if bytes > MAX_AUDIO_BYTES:
		return "%s is %s, and audio may be at most %s" % [
			path, describe_bytes(bytes), describe_bytes(MAX_AUDIO_BYTES),
		]
	if seconds > MAX_AUDIO_SECONDS:
		return "%s plays for %.1f seconds, and audio may be at most %.0f seconds" % [
			path, seconds, MAX_AUDIO_SECONDS,
		]
	return ""


static func texture_size(bytes: PackedByteArray) -> Vector2i:
	## PNG and JPEG only, read from the header. Anything else reports zero.
	if bytes.size() >= 24 and bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
		return Vector2i(_be32(bytes, 16), _be32(bytes, 20))
	if bytes.size() >= 4 and bytes[0] == 0xFF and bytes[1] == 0xD8:
		var index := 2
		while index + 9 < bytes.size():
			if bytes[index] != 0xFF:
				index += 1
				continue
			var marker := bytes[index + 1]
			var length := (bytes[index + 2] << 8) + bytes[index + 3]
			if marker >= 0xC0 and marker <= 0xCF and marker != 0xC4 and marker != 0xC8 and marker != 0xCC:
				return Vector2i(
					(bytes[index + 7] << 8) + bytes[index + 8],
					(bytes[index + 5] << 8) + bytes[index + 6],
				)
			index += 2 + length
		return Vector2i.ZERO
	return Vector2i.ZERO


static func wav_seconds(bytes: PackedByteArray) -> float:
	## A canonical RIFF/WAVE header (44 bytes before the data). Anything else
	## reports zero and is bounded by the byte cap alone.
	if bytes.size() < 44:
		return 0.0
	if not (bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[2] == 0x46 and bytes[3] == 0x46):
		return 0.0
	if not (bytes[8] == 0x57 and bytes[9] == 0x41 and bytes[10] == 0x56 and bytes[11] == 0x45):
		return 0.0
	var byte_rate := _le32(bytes, 28)
	if byte_rate <= 0:
		return 0.0
	return float(bytes.size() - 44) / float(byte_rate)


static func _be32(bytes: PackedByteArray, offset: int) -> int:
	return (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3]


static func _le32(bytes: PackedByteArray, offset: int) -> int:
	return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24)


static func _regex(pattern: String) -> RegEx:
	var regex := RegEx.new()
	regex.compile(pattern)
	return regex
