class_name SaveStore
extends RefCounted
## Save slots for one plugin at a time (SDD §7).
##
## Slots are namespaced by plugin `id`, so two plugins never share one (§7.1).
## A payload is the session snapshot plus the metadata a slot list needs; an
## unknown `saveSchema` is refused, never migrated (§7.3). The wall clock lives
## here and nowhere else: the play layer stays reproducible (TC-DET-001) while a
## save still records when it was written.

const MAX_SLOTS := 3
const PREVIEW_LIMIT := 60

const CODE_NOTHING := "SAVE-01"
const CODE_RANGE := "SAVE-02"
const CODE_EMPTY := "SAVE-03"
const CODE_UNREADABLE := "SAVE-04"
const CODE_SCHEMA := "SAVE-05"
const CODE_PLUGIN := "SAVE-06"
const CODE_WRITE := "SAVE-07"
const CODE_NODE := "SAVE-08"

var backend: SaveBackend

## A backend that keeps `user://` in memory may fold it into durable storage later:
## the browser writes through IndexedDB on a scheduled sync. `flush_request` asks
## the platform to fold it now and `flush_probe` answers whether it is folded.
## Both are optional; on a backend with nothing to flush a write is durable the
## moment `write` returns, which is every backend except the browser one.
var flush_request := Callable()
var flush_probe := Callable()

var _pending := false


func _init(source: SaveBackend = null) -> void:
	backend = source if source != null else MemoryBackend.new()


static func key_for(plugin_id: String, slot: int) -> String:
	return "save:%s:%d" % [plugin_id, slot]


func mark_writing() -> void:
	## A write that is not a save slot still needs the same gate: an installed
	## package lives in `user://` too, and a reload before IndexedDB folds it in
	## loses it exactly the same way.
	if not flush_request.is_valid():
		return
	flush_request.call()
	_pending = true


func settled() -> bool:
	## True when no write is waiting to become durable. Asking settles it: the
	## probe is the platform's answer, not a guess, so there is no timer here.
	if not _pending:
		return true
	if not flush_probe.is_valid():
		_pending = false
		return true
	_pending = not bool(flush_probe.call())
	return not _pending



func write(entry: Dictionary, slot: int, snapshot: Dictionary, preview: String = "") -> Dictionary:
	## Returns `{ok, code, message, slot}`. A failed write is reported as failed;
	## the caller must not tell the player the slot was saved.
	var issue := _range_issue(slot)
	if not issue.is_empty():
		return issue
	var plugin_id := String(entry.get("id", ""))
	if plugin_id == "" or snapshot.get("node", "") == "":
		return _problem(CODE_NOTHING, "nothing to save: no active session", slot)
	var payload := {
		"schema": int(snapshot.get("schema", 0)),
		"plugin": {"id": plugin_id, "version": String(entry.get("version", ""))},
		"node": String(snapshot.get("node", "")),
		"state": snapshot.get("state", {}).duplicate(true),
		"rng": int(snapshot.get("rng", 0)),
		"visited": snapshot.get("visited", []).duplicate(),
		"finished": bool(snapshot.get("finished", false)),
		"turn": int(snapshot.get("turn", 1)),
		"tick": int(snapshot.get("tick", 0)),
		"used": snapshot.get("used", {}).duplicate(true),
		"pools": snapshot.get("pools", {}).duplicate(true),
		"drawn": snapshot.get("drawn", []).duplicate(true),
		"preview": preview.left(PREVIEW_LIMIT),
		"savedAt": Time.get_datetime_string_from_system(true),
	}
	if not backend.write(key_for(plugin_id, slot), JSON.stringify(payload)):
		return _problem(CODE_WRITE, "slot %d was not written" % slot, slot)
	_pending = false
	if flush_request.is_valid():
		flush_request.call()
		_pending = flush_probe.is_valid() and not bool(flush_probe.call())
	return {"ok": true, "code": "", "message": "", "slot": slot, "pending": _pending}


func read(entry: Dictionary, slot: int) -> Dictionary:
	## Returns `{ok, code, message, payload}`. On refusal the stored bytes are
	## left alone: no partial load, no migration (SDD §7.3).
	var issue := _range_issue(slot)
	if not issue.is_empty():
		return issue
	var plugin_id := String(entry.get("id", ""))
	var raw := backend.read(key_for(plugin_id, slot))
	if raw == "":
		return _problem(CODE_EMPTY, "slot %d is empty" % slot, slot)
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		return _problem(CODE_UNREADABLE, "slot %d holds no readable save" % slot, slot)
	var payload: Dictionary = parsed

	var declared := int(entry.get("manifest", {}).get("saveSchema", 0))
	var found: Variant = payload.get("schema", null)
	if not ManifestSchema.is_integer(found):
		return _problem(CODE_UNREADABLE, "slot %d has no schema version" % slot, slot)
	if int(found) != declared:
		return _problem(CODE_SCHEMA, "save schema %d does not match plugin schema %d" % [int(found), declared], slot)

	var owner: Variant = payload.get("plugin", null)
	var owner_id := ""
	var owner_version := ""
	if owner is Dictionary:
		owner_id = String(owner.get("id", ""))
		owner_version = String(owner.get("version", ""))
	elif owner is String:
		owner_id = owner
		owner_version = String(payload.get("version", ""))
	else:
		return _problem(CODE_UNREADABLE, "slot %d names no plugin" % slot, slot)
	if owner_id != plugin_id:
		return _problem(CODE_PLUGIN, "slot %d belongs to plugin %s, not %s" % [slot, owner_id, plugin_id], slot)

	return {
		"ok": true,
		"code": "",
		"message": "",
		"slot": slot,
		"payload": {
			"schema": int(found),
			"plugin": {"id": owner_id, "version": owner_version},
			"node": String(payload.get("node", "")),
			"state": payload.get("state", {}),
			"rng": int(payload.get("rng", 0)),
			"visited": payload.get("visited", []),
			"finished": bool(payload.get("finished", false)),
			"turn": int(payload.get("turn", 1)),
			"tick": int(payload.get("tick", 0)),
			"used": payload.get("used", {}),
			"pools": payload.get("pools", {}),
			"drawn": payload.get("drawn", []),
			"preview": String(payload.get("preview", "")),
			"savedAt": String(payload.get("savedAt", "")),
		},
	}


func slots(entry: Dictionary) -> Array:
	## One row per slot for the save screen, empty rows included.
	var rows: Array = []
	for slot in range(1, MAX_SLOTS + 1):
		var result := read(entry, slot)
		var ok := bool(result["ok"])
		rows.append({
			"slot": slot,
			"ok": ok,
			"empty": not ok and String(result["code"]) == CODE_EMPTY,
			"code": String(result["code"]),
			"message": String(result["message"]),
			"node": String(result["payload"]["node"]) if ok else "",
			"preview": String(result["payload"]["preview"]) if ok else "",
			"savedAt": String(result["payload"]["savedAt"]) if ok else "",
		})
	return rows


func resume(entry: Dictionary, payload: Dictionary) -> Session:
	## Rebuilds a session from a payload that already passed `read`. The RNG and
	## the visited list travel with the save, so the run stays reproducible.
	var session := Session.create(entry)
	if session == null:
		return null
	var node := String(payload.get("node", ""))
	if node == "" or not session.nodes.has(node):
		session.reject(CODE_NODE, "save points at node %s which the plugin does not have" % node)
		return null
	session.current = node
	session.state = payload.get("state", {}).duplicate(true)
	session.rng = int(payload.get("rng", 1))
	session.visited = payload.get("visited", []).duplicate()
	session.finished = bool(payload.get("finished", false))
	session.turn = int(payload.get("turn", 1))
	session.tick = int(payload.get("tick", 0))
	session.used = payload.get("used", {}) if payload.get("used", null) is Dictionary else {}
	session.drawn = payload.get("drawn", []) if payload.get("drawn", null) is Array else []
	session.restore_pools(payload.get("pools", {}))
	return session


func _range_issue(slot: int) -> Dictionary:
	if slot < 1 or slot > MAX_SLOTS:
		return _problem(CODE_RANGE, "slot %d is outside 1-%d" % [slot, MAX_SLOTS], slot)
	return {}


func _problem(code: String, message: String, slot: int) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "slot": slot, "payload": {}}
