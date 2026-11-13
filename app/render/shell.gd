class_name Shell
extends Control
## The visible shell: landing → plugin list → session → saves → notice.
##
## It decides what the player sees and which core call a click maps to; every
## rule decision stays in `core/`, so the engine is still testable without a
## window (B5a). Nothing here reads storage directly — saves and imported
## packages go through `SaveStore` and `PackageStore`.

const BUILTIN_DIR := "res://builtin"
const SLOT_COUNT := 3
## Save and Load side by side, plus the row's separations, measured once so the
## slot label can be told what width it may take.
const SLOT_BUTTONS_WIDTH := 152.0
## Slot previews are stored with the save, so they are clipped at write time.
const PREVIEW_CHARS := 24
# The narrowest a card cell may get before the label turns into a column of one
# word. The hand asks the window how many of these fit, which is the whole point
# of the layout: the number is measured, never declared.
const CARD_COLUMN_MIN := 190.0
# A card that shares a row has less width for its label, so the label is cut at
# this many characters once the hand wraps. A hand that fits on one row keeps
# the whole label.
const HAND_LABEL_CHARS := 18
## A card face is drawn beside its label, so it stays small enough for a
## narrow window to hold a hand of four (REQ-037).
const CARD_ICON_SIZE := 48.0
## A phone held upright is narrower than the desktop window the shell grew up
## in. Below this width the column gets one margin and every button a finger
## sized target; above it the window keeps the shape it always had (B118).
const NARROW_WIDTH := 600.0
const MIN_TOUCH := 44.0
const NARROW_MARGIN := 12
const WIDE_MARGIN := 24

const SCREEN_LANDING := "landing"
const SCREEN_PLUGINS := "plugins"
const SCREEN_SESSION := "session"
const SCREEN_SAVES := "saves"
const SCREEN_LOADS := "loads"
const SCREEN_NOTICE := "notice"
const SCREEN_WORLDS := "worlds"
## The world a package declares none of; its title comes from the interface.
const WORLD_OTHER := ""

## The window title carries the screen name. On the web build Godot maps it to
## `document.title`, which is the only piece of the interface a browser driver
## can read without OCR — the scene is one canvas, so button text is pixels.
## It is also honest for a player with many tabs open.
const TITLE_PREFIX := "Lethebar — "

var loader := PackageLoader.new()
## Saves and imported packages live in `user://`, which the web build keeps in
## IndexedDB: a slot survives a reload (TC-OFF-001/002/004). Tests swap both
## stores for the memory backend before `_ready()`.
var saves := SaveStore.new(FileBackend.new())
var memories := FileBackend.new()
var packages := PackageStore.new(FileBackend.new())

var screen := SCREEN_LANDING
## Empty means the list shows every pack; otherwise only one world's.
var _world_filter := ""
var session: Session = null
var entry: Dictionary = {}
var notice := {"code": "", "message": ""}
var builtin_ids: Array = []
## Tests hand the shell a viewport without opening one; a positive override
## stands in for the window size, so the narrow and wide paths are both
## exercised in the same suite (B118).
var size_override := Vector2.ZERO
## Where the loader stages a package while reading it. The browser keeps the
## default; tests point it at a writable res:// folder (SDD §3.1 keeps packages
## in memory, so this is the reader's scratch file, not storage).
var work_dir := "user://pkg"

var _heading: Label
var _sub: RichTextLabel
var _options: VBoxContainer
var _card_rows: Array = []
# A hand is laid out in rows of as many cards as the window fits, so a long hand
# wraps instead of pushing the menu below the fold (REQ-038). The cells are kept
# apart from the rows that hold them, because the rows are rebuilt whenever the
# width changes.
var _hand_box: VBoxContainer = null
var _hand_cells: Array = []
var _hand_columns := 0
# Zero means "ask the viewport"; a headless shell has no viewport, so the case
# hands the layout a width instead of guessing.
var _layout_width := 0.0
var _status: RichTextLabel
var _margin: MarginContainer
var _scroll: ScrollContainer
var _box: VBoxContainer
## One picture band sits between the heading and the prose: a wide slot for the
## scene (or its background fallback) and a narrow one on the right for a
## portrait. Both are hidden when empty, so a text-only pack keeps the layout it
## had before pictures existed (SDD §8.2 — an empty slot takes no space).
var _band: HBoxContainer
var _picture: TextureRect
var _portrait: TextureRect
var _audio: AudioStreamPlayer
var _picture_slots: Array = []
## Set while a desktop picker is open, so a second click does not stack dialogs.
var _picker: FileDialog = null
var _native: NativeUI = null
## The native build asks for a link in a dialog the engine owns; a page asks
## with `window.prompt`, which does not exist off the web.
var _link_dialog: AcceptDialog = null
var _link_url: LineEdit = null
## The long-press menu over the address field: a phone has no right click, and
## the engine's LineEdit does not surface the system paste menu on touch.
var _link_menu: PopupMenu = null
var _touch_started := 0
## The JS callback must stay referenced from here: assigning it to `window` alone
## lets the engine collect it, and the bridge then exists but never calls back.
var _import_callback: JavaScriptObject = null

## The slot whose save is still being folded into durable storage, or zero.
var _saving_slot := 0

## True while a package install is still being folded into durable storage.
var _writing := false

## Frames the browser gets before a write may be called saved. The engine folds
## `user://` into IndexedDB on a scheduled sync and does not expose it to the page,
## so the shell holds the label instead of guessing in seconds.
const FLUSH_MS := 1500
var _flush_started := 0

## The browser's answer to "did you keep the payload": the page shim publishes
## it on `window.lethebarCache`, the shell polls it the way it polls the locale.
var _cache_state: Dictionary = {}

## The notice is shown once per browser; a cleared profile shows it again.
const WELCOME_PATH := "user://welcome.txt"
var _welcome_seen := false

## What the landing screen shows, mirrored into `lethebarState` for the probe.
var _visible_notice := ""


func _ready() -> void:
	_build_chrome()
	resized.connect(_fit_text)
	_fit_text()
	_install_builtins()
	_connect_import_bridge()
	_connect_flush_bridge()
	_read_welcome()
	show_landing()


# --- screens ----------------------------------------------------------------

func show_landing() -> String:
	## First run starts here, and so does every later one. One line says what
	## this is — five first-time players asked exactly that while the screen
	## only described the architecture — then either a new story or the run the
	## player left. The list of stories lives one click away in "New game":
	## putting it here made every visit start with a menu (REQ-017).
	screen = SCREEN_LANDING
	_heading.text = Locale.text("app.name")
	_sub.text = "%s · v%s" % [Locale.text("app.tagline"), version_string()]
	_clear_options()
	_status.text = ""
	_world_filter = ""
	_options.add_child(_button(Locale.text("ui.new_game"), start_game))
	if not _saves_index().is_empty():
		_options.add_child(_button(Locale.text("ui.continue"), show_loads))
	if builtin_ids.is_empty():
		# Nothing to offer yet, so the screen has to contain the way out of that
		# state rather than a dead end.
		_status.text = Locale.text("ui.no_pack_yet")
		_options.add_child(_button(Locale.text("ui.install"), request_install))
	_options.add_child(_button(Locale.text("ui.install_link"), request_link_install))
	# The interface is translated, so the player needs a way to say "not my
	# language" without changing the browser.
	_options.add_child(_button(_language_label(), toggle_language))
	var fresh := notice_text()
	if fresh != "":
		_visible_notice = fresh
		# One line, above the buttons, never a modal: a first visit needs to know
		# that 42 MB is arriving and that switching tabs may waste it (REQ-031).
		_sub.text = "%s\n%s" % [_sub.text, fresh]
		_remember_welcome()
	elif _visible_notice != "":
		# The page answers the cache question a frame or two after the first
		# paint; the sentence it replaces must stay until the player leaves this
		# screen, or the notice would blink away in front of them.
		_sub.text = "%s\n%s" % [_sub.text, _visible_notice]
	_announce()
	return screen


func notice_text(web: bool = OS.has_feature("web")) -> String:
	## A failed cache write first (the player can act on it), then the size, once.
	if not web:
		return ""
	var error := String(_cache_state.get("error", ""))
	if error != "":
		return Locale.text("ui.cache_failed") % error
	if _welcome_seen:
		return ""
	var text := Locale.text("ui.first_visit") % payload_label(web)
	if _is_ios_safari():
		text = "%s %s" % [text, Locale.text("ui.install_hint")]
	return text


func payload_label(web: bool = OS.has_feature("web")) -> String:
	## The page publishes this build's exact size; a build without the shim keeps
	## the measured fallback rather than guessing small. A native build never
	## downloaded a payload, so it has no size to announce.
	if not web:
		return ""
	var bytes := int(_cache_state.get("bytes", 0))
	if bytes <= 0:
		return "42 MB"
	return "%.0f MB" % (float(bytes) / (1024.0 * 1024.0))


func _is_ios_safari() -> bool:
	## Only the iPhone and iPad need the home-screen hint; a browser that is
	## already installed runs in standalone mode and has nothing to add.
	if not OS.has_feature("web"):
		return false
	var answer := str(JavaScriptBridge.eval(
		"(/iPhone|iPad/.test(navigator.userAgent) && !navigator.standalone) ? 1 : 0", true
	))
	return answer == "1"


func _remember_welcome() -> void:
	if _welcome_seen:
		return
	_welcome_seen = true
	var file := FileAccess.open(WELCOME_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string("seen\n")
		file.close()


func _read_welcome() -> void:
	if _welcome_seen:
		return
	_welcome_seen = FileAccess.file_exists(WELCOME_PATH)


func show_loads() -> String:
	## `Continue` has no pack in hand, so it lists the saves themselves: one row
	## per non-empty slot, newest first, each opening that pack exactly where the
	## player stopped. Asking "which pack?" first would make "continue" a
	## three-click detour (A + names-only decision, 2026-11-02).
	screen = SCREEN_LOADS
	_heading.text = Locale.text("ui.continue")
	_sub.text = Locale.text("ui.continue_hint")
	_status.text = ""
	_clear_options()
	var rows := _saves_index()
	for row in rows:
		_options.add_child(
			_button(_save_label(row), resume_slot.bind(String(row["plugin"]), int(row["slot"])))
		)
	if rows.is_empty():
		_status.text = Locale.text("ui.nothing_saved")
	_options.add_child(_button(Locale.text("ui.back"), show_landing))
	_announce()
	return screen


var _ticked: Dictionary = {}
## The package whose remove control is waiting for its second press.
var _pending_remove := ""


func resume_slot(plugin_id: String, slot: int) -> Dictionary:
	## A save names its own plugin, so this is the only entry point that does not
	## start from a pack list. A slot that no longer makes sense in this build
	## (unknown scene, schema drift) is refused with its code, not half-loaded.
	var record: Dictionary = loader.registry.entry(plugin_id)
	if record.is_empty():
		open_notice("E-01", "pack %s is not installed" % plugin_id)
		return current_view()
	var result := saves.read(record, slot)
	if not bool(result.get("ok", false)):
		open_notice(String(result.get("code", "")), String(result.get("message", "")))
		return current_view()
	var layers: Array = []
	for name in (result["payload"].get("assembly", []) as Array):
		var layer_record: Dictionary = loader.registry.entry(String(name))
		if layer_record.is_empty():
			open_notice("E-02", "the save needs %s, which is not installed" % name)
			return current_view()
		layers.append(layer_record)
	var restored := saves.resume(
		record, result["payload"], {"locale": Locale.current(), "assembly": layers, "persist_backend": memories}
	)
	if restored == null:
		open_notice(
			SaveStore.CODE_NODE, "slot %d points at a scene this pack no longer has" % slot
		)
		return current_view()
	entry = record
	session = restored
	return enter_session()


func open_plugins() -> String:
	screen = SCREEN_PLUGINS
	if _world_filter == "":
		_heading.text = Locale.text("ui.all_packs")
	else:
		_heading.text = world_title(_world_filter)
	_sub.text = Locale.text("ui.packs_hint")
	_status.text = "" if not builtin_ids.is_empty() else Locale.text("ui.no_pack_installed")
	_clear_options()
	for plugin_id in builtin_ids:
		if _is_layer(plugin_id):
			continue
		if _world_filter != "" and world_of(plugin_id) != _world_filter:
			continue
		var row := _button(_pack_title(plugin_id), start_plugin.bind(plugin_id, ticked_for(plugin_id)))
		var meta := _meta_of(plugin_id)
		var line := pack_line(meta, Locale.current())
		if line != "":
			# A reader choosing between stories sees how long one takes and who it
			# was written for before opening it (REQ-045).
			row.tooltip_text = line
			var note := Label.new()
			note.text = line
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.add_theme_font_size_override("font_size", 13)
			_options.add_child(note)
		_options.add_child(row)
		_options.add_child(_remove_control(plugin_id))
		if packages.previous_version(plugin_id) != "":
			_options.add_child(_restore_control(plugin_id))
		for layer_id in layers_for(plugin_id):
			# Off by default: a layer changes the rules of the run, so a player
			# who never asked for one keeps the run the pack describes.
			var record: Dictionary = loader.registry.entry(layer_id)
			var manifest: Dictionary = record.get("manifest", {}) if record.get("manifest", null) is Dictionary else {}
			if ManifestSchema.layer_applied(String(manifest.get("layer", ""))):
				var tick := CheckBox.new()
				tick.text = _pack_title(layer_id)
				tick.button_pressed = (_ticked.get(plugin_id, []) as Array).has(layer_id)
				tick.pressed.connect(toggle_layer.bind(plugin_id, layer_id))
				_options.add_child(tick)
			else:
				# The declaration is real, the effect is not: say so instead of
				# offering a tick that would change nothing (B91).
				var pending := Label.new()
				pending.text = Locale.text("ui.layer_pending") % _pack_title(layer_id)
				pending.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				pending.add_theme_font_size_override("font_size", 13)
				_options.add_child(pending)
			_options.add_child(_remove_control(layer_id))
	_options.add_child(_button(Locale.text("ui.install"), request_install))
	_options.add_child(_button(Locale.text("ui.install_link"), request_link_install))
	_options.add_child(_button(Locale.text("ui.back"), show_landing))
	_announce()
	return screen


func layers_for(plugin_id: String) -> Array:
	## The layers installed against one pack, sorted so the page does not move
	## between visits. A layer names its target, so this is a lookup, not a guess.
	var found: Array = []
	for candidate in loader.registry.ids():
		var name := String(candidate)
		if name == plugin_id or not _is_layer(name):
			continue
		var manifest: Dictionary = loader.registry.entry(name).get("manifest", {})
		if String(manifest.get("target", "")) != plugin_id:
			continue
		found.append(name)
	found.sort()
	return found


func ticked_for(plugin_id: String) -> Array:
	## What the player ticked for this pack. Nothing is ticked until asked: a
	## layer changes the rules of a run, so the default is the run they had.
	return (_ticked.get(plugin_id, []) as Array).duplicate()


func toggle_layer(plugin_id: String, layer_id: String) -> String:
	## One tick, then the page redraws: the set is memory, not a setting. The save
	## it produces is the only record, which is what makes resume exact.
	var chosen: Array = _ticked.get(plugin_id, [])
	if chosen.has(layer_id):
		chosen.erase(layer_id)
	else:
		chosen.append(layer_id)
	_ticked[plugin_id] = chosen
	return open_plugins()


func _remove_control(plugin_id: String) -> Button:
	## The second press is the one that erases; there is no undo, so the first
	## press only names what would go.
	var label := Locale.text("ui.remove")
	if _pending_remove == plugin_id:
		label = Locale.text("ui.remove_confirm") % _pack_title(plugin_id)
	return _button(label, _remove_pressed.bind(plugin_id))


func _remove_pressed(plugin_id: String) -> void:
	if _pending_remove != plugin_id:
		_pending_remove = plugin_id
		open_plugins()
		_status.text = Locale.text("ui.remove_hint") % _pack_title(plugin_id)
		return
	remove_package(plugin_id)


func remove_package(plugin_id: String) -> void:
	## Removal erases the in-memory registry, the stored bytes and the row that
	## lists them in one step. Saves are not deleted: they are keyed by package,
	## so installing the same id and version again brings them back (B86).
	if not _is_layer(plugin_id) and not layers_for(plugin_id).is_empty():
		open_plugins()
		_status.text = Locale.text("ui.remove_layers_first") % _pack_title(plugin_id)
		return
	if session != null and String(session.plugin_id) == plugin_id:
		session = null
		entry = {}
	loader.registry.uninstall(plugin_id)
	packages.erase(plugin_id)
	packages.erase_previous(plugin_id)
	builtin_ids.erase(plugin_id)
	_ticked.erase(plugin_id)
	for pack_id in _ticked.keys():
		(_ticked[pack_id] as Array).erase(plugin_id)
	_pending_remove = ""
	open_plugins()


func _restore_control(plugin_id: String) -> Button:
	## One press: the previous version is the only rollback a player gets, so it
	## does not need the two-press confirmation removal uses (B103).
	return _button(
		Locale.text("ui.restore_previous") % packages.previous_version(plugin_id),
		restore_previous.bind(plugin_id),
	)


func restore_previous(plugin_id: String) -> void:
	## Re-import the bytes kept under `previous:<id>`. The version it replaces is
	## kept in turn, so pressing twice walks back and forth between two versions.
	var prior := packages.previous_of(plugin_id)
	var bytes := Marshalls.base64_to_raw(String(prior.get("bytes", "")))
	if bytes.is_empty():
		return
	var context := _context()
	context["allow_downgrade"] = true
	_after_install(loader.import_bytes(bytes, context))


func _is_layer(plugin_id: String) -> bool:
	## A layer is not a story: it has no scene of its own, so it never appears in
	## the list a player picks a story from (ADR-0013).
	var manifest: Dictionary = loader.registry.entry(plugin_id).get("manifest", {})
	return String(manifest.get("kind", "bundle")) == "layer"


func start_plugin(plugin_id: String, ticked: Array = []) -> Dictionary:
	## Opens a plugin and starts a session. A player never sees a package that
	## is not on this list, so a failure here is a defect, not a refusal.
	if _is_layer(plugin_id):
		# A layer changes the run of the pack it names; it has no story of its
		# own, so opening it would build a session on its placeholder node and
		# end immediately (REQ-042).
		open_notice("E-03", Locale.text("ui.layer_not_story") % plugin_id)
		return current_view()
	var record: Dictionary = loader.registry.entry(plugin_id)
	if record.is_empty():
		open_notice("E-01", "pack %s is not installed" % plugin_id)
		return current_view()
	entry = record
	var entries: Array = [record]
	if not ticked.is_empty():
		var joined: Dictionary = loader.assemble([plugin_id] + ticked)
		if not bool(joined.get("ok", false)):
			# Two layers writing one field is refused here, before a run exists
			# (V-35): a half-applied assembly is not a run a player can leave.
			open_notice(String(joined.get("code", "")), String(joined.get("message", "")))
			return current_view()
		entries = joined.get("entries", [])
	session = Session.create(entries[0], {
		"start_counter": 1,
		"locale": Locale.current(),
		"assembly": entries.slice(1),
		"persist_backend": memories,
	})
	if session == null:
		open_notice("E-02", "pack %s has no usable protocol" % plugin_id)
		return current_view()
	session.start()
	return enter_session()


func choose(index: int) -> Dictionary:
	if session == null:
		return current_view()
	session.choose(index)
	return enter_session()


func act(action_id: String) -> Dictionary:
	## One turn of a declared menu (REQ-026). The session decides whether the
	## action is allowed; the scene only redraws what the engine reports.
	if session == null:
		return current_view()
	session.act(action_id)
	return enter_session()


func play_card(card_id: String) -> Dictionary:
	## One turn played from the hand (REQ-036). The session decides whether the
	## cost can be paid; the scene only redraws what the engine reports.
	if session == null:
		return current_view()
	session.play_card(card_id)
	return enter_session()


func enter_session() -> Dictionary:
	_card_rows.clear()
	_hand_cells.clear()
	_hand_box = null
	screen = SCREEN_SESSION
	_heading.text = Locale.text("ui.playing")
	_clear_options()
	var view: Dictionary = current_view()
	var content: Dictionary = view.get("content", {})
	var cast := String(content.get("cast", ""))
	if cast != "" and String(content.get("view", "first")) != "first":
		# Who is in the story is said before the scene, and the ensemble view is
		# the one that keeps the roles in front of the reader (REQ-044).
		_sub.text = "%s\n%s" % [Locale.text("ui.cast_line") % cast, String(view.get("text", ""))]
	else:
		_sub.text = String(view.get("text", ""))
	if _sub.text == "":
		_sub.text = Locale.text("ui.no_scene")
	var choices: Array = view.get("choices", [])
	for index in choices.size():
		_options.add_child(_button(String(choices[index].get("label", "")), choose.bind(index)))
	# A package played through actions declares a menu instead of (or beside) its
	# choices. An action that cannot be taken stays visible: the player has to see
	# what is out of reach and why, so the reason becomes part of the label and
	# the button is disabled rather than hidden.
	var actions: Array = view.get("actions", [])
	var run_finished := bool(view.get("finished", false))
	if not run_finished:
		# A hand is drawn like the menu: a card that cannot be paid for stays
		# visible with the reason, because the player has to see what is out of
		# reach (REQ-036).
		for card in view.get("hand", []):
			var card_enabled := bool(card.get("enabled", false))
			var card_label := String(card.get("label", ""))
			var card_reason := String(card.get("reason", ""))
			if not card_enabled and card_reason != "":
				card_label = Locale.text("ui.blocked") % [card_label, card_reason]
			var card_button := _button(card_label, play_card.bind(String(card.get("id", ""))))
			card_button.disabled = not card_enabled
			card_button.set_meta("label", card_label)
			var icon_path := String(card.get("icon", ""))
			var face := _card_texture(icon_path, view) if icon_path != "" else null
			if face != null:
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 8)
				var picture := TextureRect.new()
				picture.texture = face
				picture.custom_minimum_size = Vector2(CARD_ICON_SIZE, CARD_ICON_SIZE)
				picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				row.add_child(picture)
				card_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(card_button)
				row.set_meta("full_label", card_label)
				_hand_cells.append(row)
			else:
				card_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				card_button.set_meta("full_label", card_label)
				_hand_cells.append(card_button)
			_card_rows.append({
				"id": String(card.get("id", "")),
				"has_icon": face != null,
				"path": icon_path,
			})
		if not _hand_cells.is_empty():
			_hand_box = VBoxContainer.new()
			_hand_box.add_theme_constant_override("separation", 6)
			_options.add_child(_hand_box)
			_fill_hand_rows()
		for action in actions:
			var enabled := bool(action.get("enabled", false))
			var label := String(action.get("label", ""))
			var reason := String(action.get("reason", ""))
			if not enabled and reason != "":
				label = Locale.text("ui.blocked") % [label, reason]
			var action_button := _button(label, act.bind(String(action.get("id", ""))))
			action_button.disabled = not enabled
			_options.add_child(action_button)
	var fail_reason := String(view.get("failReason", ""))
	if fail_reason != "":
		_sub.text = Locale.text("ui.run_over") % fail_reason
	if bool(view.get("finished", false)):
		_heading.text = Locale.text("ui.the_end")
		_options.add_child(_button(Locale.text("ui.saves"), open_saves))
		_options.add_child(_button(Locale.text("ui.choose_another"), open_plugins))
	else:
		_options.add_child(_button(Locale.text("ui.saves"), open_saves))
		_options.add_child(_button(Locale.text("ui.back_to_packs"), open_plugins))
	_status.text = _readout(view)
	_show_assets(view)
	_announce()
	return view


func open_saves() -> String:
	if session == null:
		return show_landing()
	screen = SCREEN_SAVES
	_heading.text = Locale.text("ui.save_slots")
	_sub.text = Locale.text("ui.slots_hint")
	_status.text = ""
	_clear_options()
	var rows: Array = saves.slots(entry)
	for index in SLOT_COUNT:
		var slot := index + 1
		var row: Dictionary = rows[index] if index < rows.size() else {}
		var description := Locale.text("ui.slot_empty") % slot
		if not bool(row.get("empty", true)):
			# Saves written before the preview cap still hold their long text, so
			# the clip happens on the way out as well as on the way in.
			description = Locale.text("ui.slot_filled") % [slot, _clip(String(row.get("preview", "")), PREVIEW_CHARS)]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var text := Label.new()
		text.text = description
		# A slot row has to leave room for Save and Load. Without wrapping the
		# label's minimum width is the whole sentence, which pushes both buttons
		# past the right edge in a narrow window — and then the player cannot
		# save or load at all. Wrapping plus a pinned width keeps the row inside.
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.custom_minimum_size = Vector2(_slot_text_width(), 0.0)
		line.add_child(text)
		line.add_child(_button("Save", save_to.bind(slot)))
		line.add_child(_button("Load", load_from.bind(slot)))
		_options.add_child(line)
	_options.add_child(_button(Locale.text("ui.back"), enter_session))
	_announce()
	return screen


func save_to(slot: int) -> Dictionary:
	if session == null:
		return current_view()
	var preview := _clip(String(current_view().get("text", "")), PREVIEW_CHARS)
	var result := saves.write(entry, slot, session.snapshot(), preview)
	open_saves()
	if not bool(result.get("ok", false)):
		_saving_slot = 0
		_status.text = Locale.text("ui.slot_failed") % [slot, String(result.get("code", ""))]
		return current_view()
	if bool(result.get("pending", false)):
		_saving_slot = slot
		_status.text = Locale.text("ui.saving")
		_announce()
		return current_view()
	_saving_slot = 0
	_status.text = Locale.text("ui.saved_to") % slot
	_announce()
	return current_view()


func poll_saves() -> void:
	## Called every frame. A save that is still being folded into IndexedDB says
	## so, then says it is saved; the slot list is not the place to guess, so the
	## label only changes when the backend answers.
	if _saving_slot < 1 and not _writing:
		return
	if not saves.settled():
		return
	if _writing:
		_writing = false
		_announce()
	if _saving_slot < 1:
		return
	_status.text = Locale.text("ui.saved_to") % _saving_slot
	_saving_slot = 0
	_announce()


func _process(_delta: float) -> void:
	poll_saves()
	_poll_cache_state()


func _poll_cache_state() -> void:
	## The shim answers once per load; until it does, the notice cannot know
	## whether the browser kept the payload, so the shell keeps asking rather than
	## blocking the first frame on a round trip to the worker.
	if bool(_cache_state.get("ready", false)) or not OS.has_feature("web"):
		return
	var raw := str(JavaScriptBridge.eval("JSON.stringify(window.lethebarCache || null)", true))
	if raw.is_empty() or raw == "null":
		return
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_cache_state = parsed
	_cache_state["ready"] = true
	if screen == SCREEN_LANDING:
		show_landing()


func load_from(slot: int) -> Dictionary:
	if session == null:
		return current_view()
	var result := saves.read(entry, slot)
	if not bool(result.get("ok", false)):
		open_notice(String(result.get("code", "")), String(result.get("message", "")))
		return current_view()
	session = saves.resume(entry, result["payload"], {"persist_backend": memories})
	return enter_session()


func open_notice(code: String, message: String) -> String:
	screen = SCREEN_NOTICE
	notice = {"code": code, "message": message}
	_heading.text = Locale.text("ui.failed_heading")
	_sub.text = "%s: %s" % [code, message]
	_status.text = Locale.text("ui.failed_hint")
	_clear_options()
	_options.add_child(_button(Locale.text("ui.back_to_packs"), open_plugins))
	_announce()
	return screen


func try_import(bytes: PackedByteArray) -> Dictionary:
	## Shared by the import button and by tests: a rejected package reports its
	## code on screen and leaves the installed packs untouched (V-01…V-09).
	return _after_install(loader.import_bytes(bytes, _context()))


func install_from_url(url: String, expected_sha256: String, fetch: Callable) -> Dictionary:
	## A package that arrives over the wire. When a digest is given,
	## `PackageLoader.import_url` hashes the bytes before anything is written, so
	## a truncated download or a wrong digest stops here with V-43. An empty
	## digest trusts the transport; the package still has to pass every check in
	## `import_bytes`, and a refusal is shown the same way as a bad file.
	if url.strip_edges().is_empty():
		open_notice("V-01", Locale.text("ui.link_refused"))
		return current_view()
	return _after_install(loader.import_url(url, expected_sha256, _context(), fetch))


func _after_install(result: Dictionary) -> Dictionary:
	## One epilogue for every way a package can arrive. A refusal is a screen,
	## not an exception: the code and the message are what the player reads.
	if String(result.get("status", "")) != "installed":
		var code := String(result.get("code", "V-01"))
		var message := String(result.get("message", ""))
		open_notice(code, message)
		# The view is what the screen shows; the code and the message are what a
		# caller needs in order to say what happened without reading pixels.
		var refused := current_view()
		refused["code"] = code
		refused["message"] = message
		refused["install"] = "refused"
		return refused
	var record: Dictionary = result["entry"]
	var plugin_id := String(record.get("id", ""))
	var already := builtin_ids.has(plugin_id)
	var stored_version := packages.stored_version(plugin_id)
	if not already:
		builtin_ids.append(plugin_id)
	packages.persist(record)
	saves.mark_writing()
	_writing = true
	entry = record
	session = Session.create(entry, {"start_counter": 1, "locale": Locale.current(), "persist_backend": memories})
	session.start()
	var view := enter_session()
	view["install"] = "already" if already and stored_version == String(record.get("version", "")) else "installed"
	return view


# --- installing a pack ------------------------------------------------------

func request_install() -> void:
	## The browser has no file system to browse: the only way to a player's disk
	## is an `<input type="file">`, which `infra/export_web.py` injects next to the
	## canvas and wires to `window.lethebarReceiveFile`. Desktop builds open a
	## native dialog instead, so the same button works when the project runs in
	## the editor.
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.lethebarAskForFile && window.lethebarAskForFile();", true)
		return
	if native().available():
		native().pick_zip()
		return
	if _picker != null and is_instance_valid(_picker):
		_picker.popup_centered_ratio(dialog_ratio(0.6))
		return
	_picker = _make_picker()
	add_child(_picker)
	_picker.popup_centered_ratio(dialog_ratio(0.6))


func _make_picker() -> FileDialog:
	## Built apart from `request_install` so a test can read the flags without
	## opening a platform dialog.
	var picker := FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	## On a phone Godot has no window to draw: the native branch hands the job to
	## the platform's document picker (UIDocumentPicker on iOS).
	picker.use_native_dialog = true
	picker.add_filter("*.zip", "Plugin package")
	picker.file_selected.connect(_on_file_chosen)
	picker.canceled.connect(_on_picker_closed)
	return picker


func request_link_install() -> void:
	## A browser has no file system and no dialog of its own, so the address is
	## asked for with a prompt. The digest is optional: on a phone there is no
	## keyboard path to a 64-character hex string, and the package still has to
	## pass every check in `import_bytes`.
	if not OS.has_feature("web"):
		if native().available():
			native().ask_for_url(
				Locale.text("ui.install_link"),
				Locale.text("ui.link_trust"),
				Locale.text("ui.link_ask"),
				Locale.text("ui.install"),
				Locale.text("ui.back"),
				"",
				Locale.text("ui.paste"),
			)
			return
		_open_link_dialog()
		return
	var url := String(JavaScriptBridge.eval(
		"window.prompt(%s) || ''" % JSON.stringify(Locale.text("ui.link_ask")), true
	)).strip_edges()
	if url.is_empty():
		return
	var fetch := func(address: String) -> PackedByteArray:
		return await Downloader.fetch(self, address)
	install_from_url(url, "", fetch)


func _open_link_dialog() -> void:
	## A native build has no page prompt: the address is asked for in a dialog
	## the engine owns, so the same install path works on a phone. The digest is
	## not asked for: a phone keyboard has no path to 64 hex characters, and the
	## package still has to pass every check in `import_bytes`.
	if _link_dialog != null and is_instance_valid(_link_dialog):
		_link_dialog.popup_centered_ratio(dialog_ratio(0.5))
		return
	_link_dialog = AcceptDialog.new()
	_link_dialog.title = Locale.text("ui.install_link")
	_link_dialog.ok_button_text = Locale.text("ui.install")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_link_url = LineEdit.new()
	_link_url.placeholder_text = Locale.text("ui.link_ask")
	box.add_child(_link_url)
	var trust := Label.new()
	trust.text = Locale.text("ui.link_trust")
	trust.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(trust)
	_attach_text_menu(_link_url)
	if is_narrow():
		_link_url.custom_minimum_size.y = MIN_TOUCH
	_link_dialog.add_child(box)
	_link_dialog.confirmed.connect(_confirm_link_install)
	add_child(_link_dialog)
	_link_dialog.popup_centered_ratio(0.5)


func _confirm_link_install() -> void:
	var address := _link_url.text.strip_edges()
	if address.is_empty():
		return
	var fetch := func(target: String) -> PackedByteArray:
		return await Downloader.fetch(self, target)
	install_from_url(address, "", fetch)


func _attach_text_menu(field: LineEdit) -> void:
	## Touch has no right click: a long press opens the four commands a text
	## field needs, over the engine's own clipboard.
	_link_menu = PopupMenu.new()
	_link_menu.name = "TextMenu"
	_link_menu.add_item(Locale.text("ui.paste"), 0)
	_link_menu.add_item(Locale.text("ui.copy"), 1)
	_link_menu.add_item(Locale.text("ui.cut"), 2)
	_link_menu.add_item(Locale.text("ui.select_all"), 3)
	_link_menu.id_pressed.connect(
		func(id: int) -> void: _text_menu_action(field, id)
	)
	field.add_child(_link_menu)
	field.gui_input.connect(
		func(event: InputEvent) -> void: _on_text_touch(field, event)
	)


func _on_text_touch(field: LineEdit, event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touch_started = Time.get_ticks_msec()
			return
		if Time.get_ticks_msec() - _touch_started >= 500:
			_show_text_menu(field)
		return
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_RIGHT:
			_show_text_menu(field)


func _show_text_menu(field: LineEdit) -> void:
	if _link_menu == null or not is_instance_valid(_link_menu):
		return
	_link_menu.position = Vector2i(field.get_screen_position() + Vector2(0, field.size.y))
	_link_menu.popup()


func _text_menu_action(field: LineEdit, id: int) -> void:
	match id:
		0:
			_paste_into(field, DisplayServer.clipboard_get())
		1:
			DisplayServer.clipboard_set(field.get_selected_text())
		2:
			DisplayServer.clipboard_set(field.get_selected_text())
			field.delete_text(field.get_selection_from_column(), field.get_selection_to_column())
		3:
			field.select_all()
	if _link_menu != null and is_instance_valid(_link_menu):
		_link_menu.hide()


func _paste_into(field: LineEdit, text: String) -> void:
	if text.is_empty():
		return
	field.insert_text_at_caret(text)
	field.caret_column = field.text.length()


func _on_picker_closed() -> void:
	if _picker != null and is_instance_valid(_picker):
		_picker.queue_free()
	_picker = null


func _on_file_chosen(path: String) -> void:
	_on_picker_closed()
	install_from_bytes(FileAccess.get_file_as_bytes(path))


func native() -> NativeUI:
	## Built once and kept: the plugin's signals arrive asynchronously, long
	## after the button that asked for them was pressed.
	if _native == null:
		_native = NativeUI.new()
		if _native.available():
			_native.zip_picked.connect(_on_file_chosen)
			_native.zip_cancelled.connect(_on_picker_closed)
			_native.url_entered.connect(_on_native_url)
			_native.url_opened.connect(_on_file_opened)
			_native.downloaded.connect(_on_native_downloaded)
			_native.download_failed.connect(_on_native_download_failed)
	return _native


func _on_native_url(url: String) -> void:
	var address := url.strip_edges()
	if address.is_empty():
		return
	if native().available():
		native().download(address)
		return
	var fetch := func(target: String) -> PackedByteArray:
		return await Downloader.fetch(self, target)
	install_from_url(address, "", fetch)


func _on_native_downloaded(path: String) -> void:
	_on_file_chosen(path)


func _on_native_download_failed(reason: String) -> void:
	open_notice("V-01", "could not download the package: %s" % reason)


func _on_file_opened(path: String) -> void:
	## A package opened from Files or Messages: iOS already copied it into our
	## storage, so it takes the same road as a file the picker returned.
	_on_file_chosen(path)


func _connect_import_bridge() -> void:
	## The injected input hands the chosen file back as base64, because a
	## JavaScript string is the only thing `JavaScriptBridge` carries. Decoding
	## lives here rather than in JavaScript so the base64 path is covered by the
	## headless suite (`_case_import_control`).
	if not OS.has_feature("web"):
		return
	var window := JavaScriptBridge.get_interface("window")
	_import_callback = JavaScriptBridge.create_callback(_on_file_picked)
	window.lethebarReceiveFile = _import_callback


func _on_file_picked(arguments: Array) -> void:
	if arguments.is_empty():
		return
	install_from_base64(String(arguments[0]))

func _connect_flush_bridge() -> void:
	## The browser keeps `user://` in memory and folds it into IndexedDB on a
	## scheduled sync. The export does not expose that sync to the page, so the
	## shell cannot ask for it; what it can do is stop claiming success until the
	## engine has had time to run it. The wait is measured in wall time, not in
	## frames, and it is bounded: a write never reports a slot as saved before
	## the engine had a chance to fold it in.
	if not OS.has_feature("web"):
		return
	saves.flush_request = func() -> void:
		_flush_started = Time.get_ticks_msec()
	saves.flush_probe = func() -> bool:
		## Wall time, not frames: a headless browser draws far faster than sixty
		## frames a second, so a frame budget would be a fraction of the window the
		## storage layer actually needs.
		return Time.get_ticks_msec() - _flush_started >= FLUSH_MS


func install_from_base64(encoded: String) -> Dictionary:
	## What the browser bridge calls. Kept separate from the byte entry point so a
	## test can drive the decode step without a browser.
	return install_from_bytes(Marshalls.base64_to_raw(encoded))


func install_from_bytes(bytes: PackedByteArray) -> Dictionary:
	## One entry for the button, the dialog and the tests. A file the player
	## picked is not more trusted than one that shipped: it goes through the same
	## V-01…V-09 checks and a refusal leaves the installed packs alone.
	return try_import(bytes)


# --- read-only accessors (tests and the smoke probe) ------------------------

func screen_name() -> String:
	return screen


func screen_title() -> String:
	## What the browser tab says. The probe waits for `plugins` here after it
	## clicks "New game", so the title is part of the contract, not decoration.
	return TITLE_PREFIX + screen


func version_string() -> String:
	## The product version, in one place: `app/project.godot` sets it and this
	## reads it back. A build that somehow lost the setting still reports the
	## three-part shape rather than an empty string, so the assertion below and
	## the browser probe both have something to compare against.
	var raw := String(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	if raw.is_empty():
		return "0.0.0"
	return raw


func _language_label() -> String:
	## `Language: English` while English is active, so the button names the
	## language the player is reading rather than the one it switches to.
	var suffix := "zh" if Locale.current() == "zh-CN" else "en"
	return "%s: %s" % [Locale.text("ui.language"), Locale.text("ui.lang_" + suffix)]


func toggle_language() -> void:
	## Two languages, so the switch is a toggle. The choice is stored by
	## `Locale`, which means a reload keeps it (B8).
	var next := "en" if Locale.current() == "zh-CN" else "zh-CN"
	Locale.set_current(next)
	match screen:
		SCREEN_PLUGINS:
			open_plugins()
		SCREEN_SESSION:
			enter_session()
		SCREEN_SAVES:
			open_saves()
		SCREEN_LOADS:
			show_loads()
		_:
			show_landing()


func slot_previews() -> Array:
	## Three entries, `""` for an empty slot. The probe uses the first one to
	## tell "the save landed" from "the click missed", and to check after a
	## reload that the slot came back (TC-OFF-002).
	var out: Array = []
	if entry.is_empty():
		return out
	for row in saves.slots(entry):
		out.append("" if bool(row.get("empty", true)) else String(row.get("preview", "")))
	return out


func _announce() -> void:
	DisplayServer.window_set_title(screen_title())
	if OS.has_feature("web"):
		# Godot's web build does not forward window titles to the document, so the
		# tab title stays as exported. Mirror what a driver needs onto one global:
		# which screen is up, which packs are installed, which slots hold a save.
		# Reading it is the only way to assert on a canvas without OCR; every
		# change it reports was still caused by a real click.
		var state := {
			"screen": screen,
			"version": version_string(),
			"locale": Locale.current(),
			"packs": builtin_ids.duplicate(),
			"stories": _story_list(),
			"worlds": _world_list(),
			"world": _world_filter,
			"saves": _saves_index(),
			"slots": slot_previews(),
			"pictures": _picture_slots.duplicate(),
			"status": "" if _status == null else _status.text,
			"saving": _saving_slot > 0 or _writing,
			"notice": _visible_notice if screen == SCREEN_LANDING else "",
			"cache": {
				"controlled": bool(_cache_state.get("controlled", false)),
				"stored": _cache_state.get("stored", []),
				"error": String(_cache_state.get("error", "")),
			},
		}
		JavaScriptBridge.eval("window.lethebarState = %s;" % JSON.stringify(state), true)
	# Layout is only settled after the frame that added the buttons, so the hit
	# boxes are published one idle frame later. A wrong box makes a click miss,
	# and the assertion on `lethebarState` still has to pass, so this cannot
	# turn a broken screen into a green run.
	call_deferred("_publish_hits")


func _fit_text() -> void:
	## Wrapped text keeps asking for the width of its narrowest column, which
	## grows the whole column far past the window (the probe caught every button
	## sitting below the fold). Pinning the minimum width to the window solves it:
	## the labels then measure their height against the width they really have.
	# A resized window changes how many cards fit a row, so the hand is re-wrapped
	# before anything is measured against it.
	if _hand_box != null and hand_columns() != _hand_columns:
		_fill_hand_rows()
	var width := maxf(get_viewport_rect().size.x - 48.0, 120.0)
	# The picture band takes a share of the window instead of a fixed 180 px: at
	# 484 px that fixed height pushed the last button below the fold (the probe's
	# screenshot caught it). A share keeps the picture and every button on screen.
	var height := get_viewport_rect().size.y
	# The picture band takes a share of the window, capped by what the text and
	# the buttons leave over. A plain share was enough while the text was Chinese;
	# English wraps to more lines and pushed the last button below the fold (the
	# probe named it: "Back to packs"). Sizing against the other rows keeps every
	# button on screen in both languages.
	var band_share := clampf(height * 0.30, 96.0, 260.0)
	var others := 0.0
	if _box != null:
		for child in _box.get_children():
			var row := child as Control
			if row == null or row == _band or not row.visible:
				continue
			others += row.get_combined_minimum_size().y
		others += float(_box.get_child_count() - 1) * _box.get_theme_constant("separation")
	var room := height - others - 8.0
	_band.custom_minimum_size = Vector2(0.0, clampf(minf(band_share, room), 0.0, 260.0))
	for label in [_sub, _status]:
		if label != null:
			(label as Control).custom_minimum_size = Vector2(width, 0.0)
	# Slot rows hold the same kind of label, but they share the row with two
	# buttons, so they get what is left rather than the full width.
	var slot_width := _slot_text_width()
	for child in _options.get_children():
		if child is HBoxContainer and child.get_child_count() > 0:
			var first := child.get_child(0)
			if first is Label:
				(first as Control).custom_minimum_size = Vector2(slot_width, 0.0)


func _slot_text_width() -> float:
	## Window width minus the margins minus the two buttons on the right.
	return maxf(get_viewport_rect().size.x - 48.0 - SLOT_BUTTONS_WIDTH, 96.0)


func _clip(text: String, limit: int) -> String:
	## Previews are stored, so the cap belongs at write time; the ellipsis keeps
	## it obvious that a longer scene is behind the slot.
	if text.length() <= limit:
		return text
	return text.left(limit) + "…"


func _publish_hits() -> void:
	if not OS.has_feature("web"):
		return
	_fit_text()
	# The labels just changed width, so their height (and every button below
	# them) moves on the next frame; publishing before that would hand the
	# driver yesterday's boxes.
	await get_tree().process_frame
	var hits: Array = []
	# Fractions of the viewport, not pixels: the browser scales the canvas to the
	# window, so the driver converts with `window.innerWidth` and stays correct
	# on any window size.
	var size := get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_collect_hits(_options, hits, size)
	JavaScriptBridge.eval("window.lethebarHits = %s;" % JSON.stringify(hits), true)


func _collect_hits(node: Node, hits: Array, size: Vector2) -> void:
	if node is Button and (node as Button).is_visible_in_tree():
		var button := node as Button
		var rect := button.get_global_rect()
		hits.append({
			"label": button.text,
			"fx": (rect.position.x + rect.size.x / 2.0) / size.x,
			"fy": (rect.position.y + rect.size.y / 2.0) / size.y,
			# Extents too: a button half below the fold still has its centre on
			# screen, so the centre alone cannot tell a reachable button from a
			# clipped one. The probe checks that the whole box is inside.
			"fw": rect.size.x / size.x,
			"fh": rect.size.y / size.y,
		})
	for child in node.get_children():
		_collect_hits(child, hits, size)


func current_view() -> Dictionary:
	if session == null:
		if screen == SCREEN_NOTICE:
			return {"node": "", "text": _sub.text, "choices": [], "state": {}, "finished": false, "warnings": [], "code": notice["code"]}
		return {"node": "", "text": "", "choices": [], "state": {}, "finished": false, "warnings": []}
	var view: Dictionary = session.view()
	if screen == SCREEN_NOTICE:
		view["code"] = notice["code"]
	return view


func visible_text() -> String:
	## Everything a player can read on the current screen, buttons included: the
	## stranger-path case asserts on what is visible, not on internal state.
	var parts: Array = []
	if _heading != null:
		parts.append(_heading.text)
	if _sub != null:
		parts.append(_sub.text)
	for child in _options.get_children():
		if child is Button:
			parts.append((child as Button).text)
		elif child is Label:
			parts.append((child as Label).text)
		elif child is HBoxContainer:
			for inner in child.get_children():
				if inner is Label:
					parts.append((inner as Label).text)
				elif inner is Button:
					parts.append((inner as Button).text)
	if _status != null:
		parts.append(_status.text)
	return "\n".join(parts)


# --- construction -----------------------------------------------------------

func _build_chrome() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	_margin = margin
	# A phone held upright has less height than a desktop window: a column that
	# does not fit has to scroll, or its last button is simply not reachable.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	_scroll = scroll
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_box = box
	_heading = Label.new()
	_heading.add_theme_font_size_override("font_size", 28)
	box.add_child(_heading)
	# The picture band is built once and then filled per scene; an empty band
	# collapses to zero height so text-only packs look exactly as they did.
	_band = HBoxContainer.new()
	_band.add_theme_constant_override("separation", 12)
	_band.visible = false
	box.add_child(_band)
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picture.custom_minimum_size = Vector2(0.0, 0.0)
	_band.add_child(_picture)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.custom_minimum_size = Vector2(160.0, 0.0)
	_band.add_child(_portrait)
	_audio = AudioStreamPlayer.new()
	box.add_child(_audio)
	# `Label` with autowrap reports the height of its narrowest column as its
	# minimum size, which grew the whole column to ~1300 px and pushed every
	# button below a 484 px viewport (caught by the probe's hit boxes, not by
	# looking at the screen). `RichTextLabel` with `fit_content` measures against
	# the width it is actually given, so the column stays the size of the window.
	_sub = RichTextLabel.new()
	_sub.bbcode_enabled = false
	_sub.scroll_active = false
	_sub.fit_content = true
	_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_sub)
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 6)
	box.add_child(_options)
	_status = RichTextLabel.new()
	_status.bbcode_enabled = false
	_status.scroll_active = false
	_status.fit_content = true
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_color_override("default_color", Color(0.7, 0.7, 0.7))
	box.add_child(_status)
	_apply_metrics()


func viewport_size() -> Vector2:
	## The window the shell reflows for. Tests hand it a size instead of opening
	## one, so both the narrow and the wide path run without a display (B118).
	if size_override.x > 0.0 and size_override.y > 0.0:
		return size_override
	return get_viewport_rect().size


func is_narrow() -> bool:
	return viewport_size().x < NARROW_WIDTH


func dialog_ratio(wide: float) -> float:
	## A dialog that takes half a desktop window leaves a phone with two
	## characters per line; on a narrow window it takes the width it can get.
	return 1.0 if is_narrow() else wide


func _apply_metrics() -> void:
	## One place decides the padding, the heading size and the gap between rows.
	## Called when the chrome is built and again whenever the window changes, so
	## rotating the phone re-measures instead of keeping the old width.
	if _margin == null:
		return
	var inset := _safe_insets()
	var pad := float(NARROW_MARGIN if is_narrow() else WIDE_MARGIN)
	_margin.add_theme_constant_override("margin_left", int(pad + inset.x))
	_margin.add_theme_constant_override("margin_top", int(pad + inset.y))
	_margin.add_theme_constant_override("margin_right", int(pad + inset.z))
	_margin.add_theme_constant_override("margin_bottom", int(pad + inset.w))
	if _heading != null:
		_heading.add_theme_font_size_override("font_size", 24 if is_narrow() else 28)
	if _box != null:
		_box.add_theme_constant_override("separation", 10 if is_narrow() else 12)


func _safe_insets() -> Vector4:
	## A notch and the home indicator live outside the safe area. Desktop
	## reports none, so the same call is harmless there.
	if not (OS.has_feature("ios") or OS.has_feature("android")):
		return Vector4.ZERO
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	if screen.x <= 0 or screen.y <= 0:
		return Vector4.ZERO
	var scale := float(screen.x) / maxf(viewport_size().x, 1.0)
	return Vector4(
		float(safe.position.x) / scale,
		float(safe.position.y) / scale,
		float(screen.x - safe.end.x) / scale,
		float(screen.y - safe.end.y) / scale,
	)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _margin != null:
		_apply_metrics()


func _install_builtins() -> void:
	builtin_ids.clear()
	for path in _builtin_packages():
		var bytes := FileAccess.get_file_as_bytes(path)
		var result := loader.import_bytes(bytes, _context())
		if String(result.get("status", "")) == "installed":
			builtin_ids.append(String(result["entry"]["id"]))
	# Packages the player imported come back from storage, so a reload does not
	# silently drop a pack they installed (TC-OFF-004). Built-ins are shipped in
	# the pack file and are never stored, so the two lists cannot collide by
	# accident — the `has` check only guards a pack that ships built in later.
	for plugin_id in packages.restore_into(loader, _context()):
		var restored := String(plugin_id)
		if not builtin_ids.has(restored):
			builtin_ids.append(restored)


func _builtin_packages() -> Array:
	## The shell reads the staged directory instead of naming packages: adding a
	## genre must not require editing the render layer, or the point of the plugin
	## layer is lost the moment a second pack ships (B5b card, deviation recorded).
	var found: Array = []
	var directory := DirAccess.open(BUILTIN_DIR)
	if directory == null:
		return found
	for name in directory.get_files():
		if name.ends_with(".zip"):
			found.append("%s/%s" % [BUILTIN_DIR, name])
	found.sort()
	return found


func start_game() -> String:
	## A repository is cut by world (ADR-0010), so several worlds need one screen
	## between the landing page and the packs; a single world keeps the click
	## count a one-theme repository has today (ADR-0012).
	if worlds().size() > 1:
		return show_worlds()
	return open_plugins()


func show_worlds() -> String:
	screen = SCREEN_WORLDS
	_heading.text = Locale.text("ui.choose_world")
	_sub.text = Locale.text("ui.worlds_hint")
	_status.text = ""
	_world_filter = ""
	_clear_options()
	for row in worlds():
		_options.add_child(_button(String(row["title"]), open_world.bind(String(row["id"]))))
	_options.add_child(_button(Locale.text("ui.install"), request_install))
	_options.add_child(_button(Locale.text("ui.install_link"), request_link_install))
	_options.add_child(_button(Locale.text("ui.back"), show_landing))
	_announce()
	return screen


func open_world(world_id: String) -> String:
	## The pack list is the same screen either way; only the filter differs, so
	## a pack is never reachable through one route and missing from the other.
	_world_filter = world_id
	return open_plugins()


func world_of(plugin_id: String) -> String:
	var manifest: Dictionary = loader.registry.entry(plugin_id).get("manifest", {})
	return String(ManifestSchema.collection_of(manifest).get("id", ""))


func worlds() -> Array:
	## Sorted by world id: the order on screen, and in `lethebarState`, is the
	## same on every visit, which is what makes a driver's click repeatable.
	var buckets: Dictionary = {}
	for plugin_id in builtin_ids:
		if _is_layer(plugin_id):
			# A layer is a patch, not a place: counting it here put an empty
			# world in front of a one-world repository (B91).
			continue
		var world_id := world_of(plugin_id)
		if not buckets.has(world_id):
			buckets[world_id] = []
		(buckets[world_id] as Array).append(plugin_id)
	var ids := buckets.keys()
	ids.sort()
	var out: Array = []
	for world_id in ids:
		out.append({"id": String(world_id), "title": world_title(String(world_id)), "packs": buckets[world_id]})
	return out


func world_title(world_id: String) -> String:
	## The world's name is the package's, like the pack's own title: the engine
	## never invents one. Packs that describe the same world may word it
	## differently (W-04); the lowest id decides, so the answer is stable.
	if world_id == WORLD_OTHER:
		return Locale.text("ui.world_other")
	var candidates: Array = []
	for plugin_id in builtin_ids:
		if world_of(plugin_id) == world_id:
			candidates.append(plugin_id)
	candidates.sort()
	for plugin_id in candidates:
		var manifest: Dictionary = loader.registry.entry(plugin_id).get("manifest", {})
		var names: Variant = ManifestSchema.collection_of(manifest).get("names", {})
		if names is Dictionary:
			var localized := String((names as Dictionary).get(Locale.current(), ""))
			if not localized.is_empty():
				return localized
	for plugin_id in candidates:
		var manifest: Dictionary = loader.registry.entry(plugin_id).get("manifest", {})
		var default_locale := String(manifest.get("defaultLocale", ""))
		var names: Variant = ManifestSchema.collection_of(manifest).get("names", {})
		if names is Dictionary:
			var written := String((names as Dictionary).get(default_locale, ""))
			if not written.is_empty():
				return written
	return world_id


func _meta_of(plugin_id: String) -> Dictionary:
	## The meta block of an installed package, or nothing when it declared none.
	var record: Dictionary = loader.registry.entry(plugin_id)
	if record.is_empty():
		return {}
	return MetaLayer.of(record.get("manifest", {}))


static func pack_line(meta: Dictionary, locale: String) -> String:
	## What a list row says about a story it has not opened (REQ-045): the pitch in
	## the reader's language, then how long a run takes. A package that declared
	## nothing gets an empty row rather than a placeholder.
	var pitch := MetaLayer.pitch(meta, locale)
	var minutes := MetaLayer.length_line(meta)
	if pitch == "" and minutes == "":
		return ""
	if minutes == "":
		return pitch
	return "%s · %s min" % [pitch, minutes]


func _pack_title(plugin_id: String) -> String:
	## The player sees the pack's own name, never the protocol it happens to
	## speak: `sanguo — turn_based@1, 0.1.0` looked like a turn-based strategy
	## game and made a first-time player expect internal affairs and troop
	## recruitment (TC-UX-001 finding). Protocol and version stay in the
	## manifest, the log and the error codes, where a developer looks for them.
	var record: Dictionary = loader.registry.entry(plugin_id)
	var manifest: Dictionary = record.get("manifest", {})
	var names: Variant = manifest.get("names", null)
	if names is Dictionary:
		var localized := String(names.get(Locale.current(), ""))
		if not localized.is_empty():
			return localized
	var title := String(manifest.get("name", ""))
	return title if not title.is_empty() else plugin_id


func _world_list() -> Array:
	## Ids and titles only: the driver clicks a world by the name a player reads.
	var rows: Array = []
	for row in worlds():
		rows.append({"id": String(row["id"]), "title": String(row["title"])})
	return rows


func _story_list() -> Array:
	## Published through `lethebarState` so a browser driver can click a story by
	## the name a player reads instead of guessing at button order. `pictures`
	## says how many pictures the pack declares, so a driver that wants to prove
	## a picture was drawn opens a story that has one instead of whichever comes
	## first (a story with no art draws no band, which is correct, not a defect).
	var stories: Array = []
	for plugin_id in builtin_ids:
		stories.append({
			"id": plugin_id,
			"title": _pack_title(plugin_id),
			"pictures": _declared_pictures(loader.registry.entry(plugin_id)),
		})
	return stories


func _declared_pictures(record: Dictionary) -> int:
	var count := 0
	for asset in record.get("manifest", {}).get("assets", []):
		if asset is Dictionary and String(asset.get("type", "")) == "texture":
			count += 1
	return count


func _saves_index() -> Array:
	## Every non-empty slot in this browser, newest first. `Continue` needs the
	## saves themselves rather than a pack, because the player remembers the run
	## and not which pack it came from.
	var rows: Array = []
	for plugin_id in builtin_ids:
		var record: Dictionary = loader.registry.entry(plugin_id)
		for row in saves.slots(record):
			if bool(row.get("empty", true)):
				continue
			rows.append({
				"plugin": plugin_id,
				"title": _pack_title(plugin_id),
				"slot": int(row.get("slot", 0)),
				"preview": String(row.get("preview", "")),
				"savedAt": String(row.get("savedAt", "")),
			})
	rows.sort_custom(func(left, right): return String(left["savedAt"]) > String(right["savedAt"]))
	return rows


func _save_label(row: Dictionary) -> String:
	## `<title> · Slot <n> — <preview> · <hh:mm>`, with the clock in the
	## player's own time zone (B8 keeps every word here in the catalogue).
	var label := Locale.text("ui.slot_head") % [String(row.get("title", "")), int(row.get("slot", 0))]
	var preview := _clip(String(row.get("preview", "")), PREVIEW_CHARS)
	if preview != "":
		label += " — " + preview
	var clock := _local_clock(String(row.get("savedAt", "")))
	# The time of day is what tells two saves apart, and the player reads their own.
	if clock != "":
		label += " · " + clock
	return label


func _local_clock(saved_at: String) -> String:
	## `savedAt` is recorded in UTC (`Time.get_datetime_string_from_system(true)`),
	## so printing its time of day told a player in UTC+8 that a 14:20 save happened
	## at 06:20. Convert to this machine's offset before showing it.
	if saved_at.length() < 19:
		return ""
	var utc_seconds := int(Time.get_unix_time_from_datetime_string(saved_at.substr(0, 19)))
	if utc_seconds <= 0:
		return ""
	var bias_minutes := int(Time.get_time_zone_from_system().get("bias", 0))
	var local := Time.get_datetime_dict_from_unix_time(utc_seconds + bias_minutes * 60)
	return "%02d:%02d" % [int(local.get("hour", 0)), int(local.get("minute", 0))]


func _clear_options() -> void:
	for child in _options.get_children():
		_options.remove_child(child)
		child.queue_free()
	_hide_pictures()


func _hide_pictures() -> void:
	## Called by every screen rebuild: a picture belongs to one scene, so leaving
	## the scene takes it away. The band itself only shows when a slot is filled.
	_picture_slots.clear()
	if _band == null:
		return
	_picture.texture = null
	_portrait.texture = null
	_picture.visible = false
	_portrait.visible = false
	_band.visible = false
	if _audio != null:
		_audio.stop()


func card_rows() -> Array:
	## What the last scene drew for the hand, one entry per card: the id, whether
	## a picture was drawn, and the path the card named (REQ-037). The headless
	## smoke test reads it because a decoded texture has no text to assert on.
	return _card_rows


func set_layout_width(width: float) -> void:
	## A headless shell has a viewport of zero, so geometry that reads the window
	## would measure nothing. The case hands the layout a width instead; the game
	## never calls this and keeps reading the viewport.
	_layout_width = maxf(width, 0.0)
	_fill_hand_rows()


func hand_columns() -> int:
	## How many cards a row holds at the current width. Measured, not declared:
	## a narrow window keeps one card per row, a wide one takes several.
	var width := _layout_width_available()
	return clampi(int(floor(width / CARD_COLUMN_MIN)), 1, 12)


func hand_row_count() -> int:
	## Rows the hand currently occupies. Zero when no hand is drawn.
	if _hand_box == null:
		return 0
	return _hand_box.get_child_count()


func _layout_width_available() -> float:
	if _layout_width > 0.0:
		return _layout_width
	var pad := float(NARROW_MARGIN * 2 if is_narrow() else WIDE_MARGIN * 2)
	return maxf(viewport_size().x - pad, CARD_COLUMN_MIN)


func _fill_hand_rows() -> void:
	## Rebuilds the rows from the cells. Called when the scene is drawn and again
	## whenever the width changes, so a resized window re-wraps the same cards in
	## the same order instead of keeping yesterday's columns.
	if _hand_box == null:
		return
	for child in _hand_box.get_children():
		_hand_box.remove_child(child)
		child.queue_free()
	var columns := hand_columns()
	var rows := int(ceil(float(_hand_cells.size()) / float(columns)))
	var row: HBoxContainer = null
	_hand_columns = columns
	for index in _hand_cells.size():
		if index % columns == 0:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			_hand_box.add_child(row)
		var cell := _hand_cells[index] as Control
		if cell == null:
			continue
		# Every cell shares the row evenly, so a long label wraps inside its own
		# column instead of taking width from its neighbours.
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var full := String(cell.get_meta("full_label", ""))
		var button := _cell_button(cell)
		if button != null and full != "":
			button.text = _clip(full, HAND_LABEL_CHARS) if rows > 1 else full
		# A cell that was never parented cannot be reparented, and a re-wrap has
		# to work from either state: the first draw adds, a resize reparents.
		if cell.get_parent() == null:
			row.add_child(cell)
		else:
			cell.reparent(row)


func _cell_button(cell: Control) -> Button:
	## The button a hand cell holds, whether the cell is the button itself or a
	## row of a picture and the button.
	if cell is Button:
		return cell as Button
	for part in cell.get_children():
		if part is Button:
			return part as Button
	return null


func _card_texture(path: String, view: Dictionary) -> Texture2D:
	## A card picture is drawn beside its label and never on the scene band.
	## Missing or undecodable bytes keep the label and leave one warning; a card
	## that names a picture nobody declared never gets this far (V-39).
	var data: Dictionary = entry.get("data", {})
	var stored: Dictionary = data.get("assets", {}) if data.get("assets", {}) is Dictionary else {}
	var bytes: Variant = stored.get(path, null)
	if not bytes is PackedByteArray or (bytes as PackedByteArray).is_empty():
		_warn(view, "R-01", "card icon has no bytes: %s" % path)
		return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK and image.load_jpg_from_buffer(bytes) != OK:
		_warn(view, "R-01", "card icon did not decode: %s" % path)
		return null
	return ImageTexture.create_from_image(image)


func _show_assets(view: Dictionary) -> void:
	## Fills the picture slots a scene declares. A slot with no bytes, an unknown
	## slot name, or bytes that do not decode all end the same way: the slot keeps
	## a placeholder, one warning is recorded, and the story goes on (SDD §8.2).
	var data: Dictionary = entry.get("data", {})
	var stored: Dictionary = data.get("assets", {}) if data.get("assets", {}) is Dictionary else {}
	var declared: Variant = view.get("assets", [])
	if not declared is Array:
		return
	for asset in declared:
		if not asset is Dictionary:
			continue
		var asset_type := String(asset.get("type", ""))
		var slot := String(asset.get("slot", _default_slot(asset_type)))
		var path := String(asset.get("path", ""))
		if slot == "scene" or slot == "background":
			_set_slot(_picture, stored, path, slot, view)
		elif slot == "portrait":
			_set_slot(_portrait, stored, path, slot, view)
		elif slot == "audio":
			_set_audio(stored, path, view)
		elif slot == "card":
			# A card face belongs beside its label in the hand, not in the scene
			# band, so the band skips it instead of warning (REQ-037).
			continue
		else:
			_warn(view, "R-01", "unknown asset slot skipped: %s" % slot)


func _default_slot(asset_type: String) -> String:
	## A pack that names no slot still gets sensible placement: pictures become
	## the scene slot, sound becomes audio, and text is drawn as prose already.
	if asset_type == "audio":
		return "audio"
	if asset_type == "text":
		return "text"
	return "scene"


func _set_slot(
	control: TextureRect, stored: Dictionary, path: String, slot: String, view: Dictionary
) -> void:
	var bytes: Variant = stored.get(path, null)
	var texture: Texture2D = null
	if bytes is PackedByteArray and not bytes.is_empty():
		var image := Image.new()
		if image.load_png_from_buffer(bytes) == OK or image.load_jpg_from_buffer(bytes) == OK:
			texture = ImageTexture.create_from_image(image)
	if texture == null:
		var placeholder := PlaceholderTexture2D.new()
		placeholder.size = Vector2(320.0, 180.0)
		texture = placeholder
		_warn(view, "R-01", "asset missing or unreadable, placeholder shown: %s" % path)
	control.texture = texture
	control.visible = true
	_band.visible = true
	if not _picture_slots.has(slot):
		_picture_slots.append(slot)


func _set_audio(stored: Dictionary, path: String, view: Dictionary) -> void:
	var bytes: Variant = stored.get(path, null)
	if bytes is PackedByteArray and not bytes.is_empty():
		var stream := AudioStreamWAV.load_from_buffer(bytes)
		if stream != null:
			_audio.stream = stream
			_audio.play()
			return
	_warn(view, "R-01", "sound missing or unreadable, skipped: %s" % path)


func _warn(view: Dictionary, code: String, message: String) -> void:
	if session == null:
		return
	session.warnings.append({"code": code, "message": message, "fatal": false})


func _button(label: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = label
	if is_narrow():
		button.custom_minimum_size = Vector2(0.0, MIN_TOUCH)
	button.pressed.connect(handler)
	return button


func _readout(view: Dictionary) -> String:
	var parts: Array = []
	var state: Dictionary = view.get("state", {})
	var labels: Dictionary = view.get("labels", {})
	for key in state:
		# A declared resource may carry labels: the number stays the state, the
		# label is what a reader sees (engine-bricks §1).
		var shown := String(labels.get(key, ""))
		parts.append("%s %s" % [key, shown if shown != "" else str(state[key])])
	if view.has("progress"):
		var progress: Dictionary = view["progress"]
		parts.append(Locale.text("ui.steps") % [int(progress.get("steps", 0)), int(progress.get("nodes", 0))])
	if view.has("turn"):
		# A package with a phase machine has a turn and a rank; both are the
		# engine's numbers, the scene only reads them (REQ-026).
		parts.append(Locale.text("ui.turn_rank") % [int(view.get("turn", 0)), String(view.get("rank", ""))])
	if view.has("drawn") and not (view["drawn"] as Array).is_empty():
		# What a run has drawn is a fact the player can act on: an action may wait
		# on it, so the scene says it (REQ-027).
		var items: Array = view["drawn"]
		var names := PackedStringArray()
		for item in items:
			names.append(String(item))
		parts.append(Locale.text("ui.drawn") % ", ".join(names))
	if String((view.get("content", {}) as Dictionary).get("density", "normal")) != "sparse":
		if view.has("situation"):
			# How the run stands, read from the same view the buttons use (REQ-033):
			# the time left, who is leaned toward, who is pushed against, what is
			# close to its floor. Every number came from the package, not from here.
			var reading: Dictionary = view["situation"]
			var entity_labels := _entity_labels(view)
			if reading.has("turnsLeft"):
				parts.append(Locale.text("ui.turns_left") % int(reading["turnsLeft"]))
			if reading.has("leaning"):
				var leaned := String(reading["leaning"])
				parts.append(Locale.text("ui.leaning") % String(entity_labels.get(leaned, leaned)))
			if reading.has("friction"):
				var pushed := String(reading["friction"])
				parts.append(Locale.text("ui.friction") % String(entity_labels.get(pushed, pushed)))
			if reading.has("tight"):
				var tight := String(reading["tight"])
				parts.append(Locale.text("ui.tight") % String(labels.get(tight, tight)))
	if parts.is_empty():
		return ""
	var content_for_arc: Dictionary = view.get("content", {})
	if String(content_for_arc.get("density", "normal")) == "dense" and String(content_for_arc.get("stage", "")) != "":
		# The dense readout says which stage of the arc this turn belongs to, and
		# which turn started it (REQ-044).
		parts.append(Locale.text("ui.arc_stage") % [
			String(content_for_arc.get("stage", "")), int(content_for_arc.get("stageTurn", 0)),
		])
	return " · ".join(parts)


func _entity_labels(view: Dictionary) -> Dictionary:
	## The scene shows the label a package gave an entity, and falls back to the
	## id so a missing label is still something the player can read.
	var out := {}
	for entity in view.get("factions", []):
		if not (entity is Dictionary):
			continue
		out[String(entity.get("id", ""))] = String(entity.get("label", entity.get("id", "")))
	return out


func _context() -> Dictionary:
	## The loader validates the engine range against the running build, never
	## against a number written down here — a package that needs a newer engine
	## must be refused by the shell the player actually has (V-05).
	var info := Engine.get_version_info()
	return {
		"engine_version": "%d.%d.%d" % [int(info["major"]), int(info["minor"]), int(info["patch"])],
		"work_dir": work_dir,
	}
