class_name FileBackend
extends SaveBackend
## Persistent storage under `user://store` (SDD §7.4).
##
## On the web build Godot backs `user://` with IndexedDB and syncs it on page
## hide, so a slot written before a reload is still there after one — which is
## what `TC-OFF-001`/`TC-OFF-002` ask for. On desktop the same calls write into
## the user data folder; nothing here is web-specific.
##
## Keys are opaque to the stores and are mapped to file names, so a key may not
## contain a path separator and is escaped before it becomes a file.

const DEFAULT_ROOT := "user://store"

var root: String


func _init(root_path: String = DEFAULT_ROOT) -> void:
	root = root_path
	DirAccess.make_dir_recursive_absolute(root)


func write(key: String, text: String) -> bool:
	var path := _path(key)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	# Godot's web filesystem is only durable once it has been flushed; a save the
	# player can see must survive the tab closing right after it (SDD §7.4).
	return FileAccess.file_exists(path)


func read(key: String) -> String:
	var path := _path(key)
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func erase(key: String) -> bool:
	var path := _path(key)
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(path) == OK


func keys() -> Array:
	var found: Array = []
	var directory := DirAccess.open(root)
	if directory == null:
		return found
	for name in directory.get_files():
		found.append(_unescape(name))
	found.sort()
	return found


func _path(key: String) -> String:
	return "%s/%s" % [root, _escape(key)]


func _escape(key: String) -> String:
	## Keys look like `save:sanguo:1`, and `:` is illegal in a Windows file name,
	## so anything outside a conservative set is percent-encoded. Percent itself
	## is outside the set, which keeps the mapping reversible.
	var out := ""
	for index in key.length():
		var character := key[index]
		if _is_plain(character):
			out += character
		else:
			out += "%%%02X" % character.unicode_at(0)
	return out


func _unescape(name: String) -> String:
	var out := ""
	var index := 0
	while index < name.length():
		var character := name[index]
		if character == "%" and index + 2 < name.length():
			out += String.chr(name.substr(index + 1, 2).hex_to_int())
			index += 3
		else:
			out += character
			index += 1
	return out


func _is_plain(character: String) -> bool:
	if character >= "a" and character <= "z":
		return true
	if character >= "A" and character <= "Z":
		return true
	if character >= "0" and character <= "9":
		return true
	return character == "." or character == "_" or character == "-"
