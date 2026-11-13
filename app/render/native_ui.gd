class_name NativeUI
extends RefCounted

## The iOS plugin, when the export carries it. A desktop or web build has no
## such class, so `available()` is false and the shell keeps the engine's own
## widgets. Tests pass a stand-in object to the constructor.

signal url_entered(url: String)
signal url_cancelled
signal zip_picked(path: String)
signal zip_cancelled
signal url_opened(path: String)

const PLUGIN_CLASS := "LethebarNative"

var _plugin: Object = null


func _init(plugin: Object = null) -> void:
	_plugin = plugin
	if _plugin == null and ClassDB.class_exists(PLUGIN_CLASS):
		_plugin = ClassDB.instantiate(PLUGIN_CLASS)
	_connect()


func available() -> bool:
	return _plugin != null


func ask_for_url(
	title: String,
	message: String,
	placeholder: String,
	confirm: String,
	cancel: String,
	initial: String = "",
) -> void:
	## A system alert brings its own text field: the edit menu, the magnifier and
	## the paste prompt are the platform's, not ours.
	if _plugin == null:
		return
	_plugin.ask_for_url(title, message, placeholder, confirm, cancel, initial)


func pick_zip() -> void:
	## The system document picker reaches Files and iCloud; the engine dialog
	## only ever sees the app sandbox.
	if _plugin == null:
		return
	_plugin.pick_zip()


func _connect() -> void:
	if _plugin == null:
		return
	var pairs := [
		["url_entered", _on_url_entered],
		["url_cancelled", _on_url_cancelled],
		["zip_picked", _on_zip_picked],
		["zip_cancelled", _on_zip_cancelled],
		["url_opened", _on_url_opened],
	]
	for pair in pairs:
		if _plugin.has_signal(pair[0]):
			_plugin.connect(pair[0], pair[1])


func _on_url_entered(url: String) -> void:
	url_entered.emit(url)


func _on_url_cancelled() -> void:
	url_cancelled.emit()


func _on_zip_picked(path: String) -> void:
	zip_picked.emit(path)


func _on_zip_cancelled() -> void:
	zip_cancelled.emit()


func _on_url_opened(path: String) -> void:
	## A document opened from Files or Messages: the system hands us the file,
	## the shell decides what to do with it.
	url_opened.emit(path)
