class_name Locale
extends RefCounted
## The interface language, and the table it reads its sentences from.
##
## Sentences are not in this file and not in `app/render/`: they live in
## `res://i18n/<code>.tsv` so that adding a language is adding a file, and so
## that "no Chinese literal in the interface code" can be checked mechanically.
## The active language follows the browser on first run and a stored choice
## afterwards; the landing screen offers the switch.

const SUPPORTED: Array[String] = ["en", "zh-CN"]
const FALLBACK := "en"
const TABLE_PATH := "res://i18n/%s.tsv"
const STORE_PATH := "user://locale.txt"
const HEADER := "key\t"

static var _current := ""
static var _tables := {}


## Maps a browser tag such as `zh-Hans-CN` or `en-GB` onto a supported code.
static func normalize(tag: String) -> String:
	var lower := tag.to_lower().strip_edges()
	if lower.begins_with("zh"):
		return "zh-CN"
	if lower.begins_with("en"):
		return "en"
	return FALLBACK


## The active language. Reads the stored choice once, then the browser, then
## the fallback.
static func current() -> String:
	if _current != "":
		return _current
	var stored := _stored()
	_current = stored if SUPPORTED.has(stored) else _browser()
	return _current


static func set_current(code: String) -> void:
	var tag := normalize(code)
	_current = tag if SUPPORTED.has(tag) else FALLBACK
	var file := FileAccess.open(STORE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(_current)


## Forgets the in-memory language so the next `current()` re-reads the store.
## Tests use it to prove the choice survives a restart.
static func reload() -> void:
	_current = ""
	_tables.clear()


static func text(key: String) -> String:
	var rows := table(current())
	if rows.has(key):
		return String(rows[key])
	var fallback := table(FALLBACK)
	if fallback.has(key):
		return String(fallback[key])
	return key


static func table(code: String) -> Dictionary:
	if _tables.has(code):
		return _tables[code]
	var rows := {}
	# `zh-CN` is a language tag, `zh_CN.tsv` is the file it reads.
	var path := TABLE_PATH % code.replace("-", "_")
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			for line in file.get_as_text().split("\n", false):
				if line.begins_with(HEADER):
					continue
				var cut := line.find("\t")
				if cut <= 0:
					continue
				rows[line.substr(0, cut)] = line.substr(cut + 1)
	_tables[code] = rows
	return rows


static func _stored() -> String:
	if not FileAccess.file_exists(STORE_PATH):
		return ""
	var file := FileAccess.open(STORE_PATH, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text().strip_edges()


static func _browser() -> String:
	if OS.has_feature("web"):
		var raw = JavaScriptBridge.eval("navigator.language || ''")
		if raw != null:
			var tag := normalize(str(raw))
			if SUPPORTED.has(tag):
				return tag
	return FALLBACK
