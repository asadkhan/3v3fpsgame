extends Node
## player preferences, saved to user://settings.cfg. the GameConfig autoload.
##
## only stuff the player controls: audio, sensitivity, fov. game design
## values (damage, cooldowns, round count) belong in res://data/ as a
## Resource instead - if it wouldn't show up in an options menu, it's not
## config.
##
## settings live in one dictionary so save/load stay generic. the typed
## properties below are just views onto it.

const SETTINGS_PATH := "user://settings.cfg"

## Fires after [method load_settings] finishes, and once on startup.
signal settings_loaded

## Fires after [method save_settings] succeeds.
signal settings_saved

## Fires whenever any value is changed, including by [method set_setting].
signal setting_changed(key: String, value: Variant)

## every setting, its default, and its type (needed since ConfigFile stores
## everything as a string).
var _settings: Dictionary = {
	"audio/master_volume": {"default": 0.8, "type": TYPE_FLOAT},
	"audio/music_volume": {"default": 0.6, "type": TYPE_FLOAT},
	"input/mouse_sensitivity": {"default": 0.4, "type": TYPE_FLOAT},
	"input/invert_mouse_y": {"default": false, "type": TYPE_BOOL},
	"video/field_of_view": {"default": 90.0, "type": TYPE_FLOAT},
	"video/fullscreen": {"default": false, "type": TYPE_BOOL},
	"player/display_name": {"default": "", "type": TYPE_STRING},
	"input/aim_toggle": {"default": false, "type": TYPE_BOOL},
	"video/head_bob": {"default": true, "type": TYPE_BOOL},
	## GraphicsQuality.Level enum value; -1 auto-picks from the GPU.
	"video/graphics_quality": {"default": -1, "type": TYPE_INT},
}


func _ready() -> void:
	load_settings()


# --- Typed access -------------------------------------------------------
# properties go through set_setting() so assigning still fires
# setting_changed and saves.

var master_volume: float:
	get: return get_setting("audio/master_volume")
	set(value): set_setting("audio/master_volume", value)

var music_volume: float:
	get: return get_setting("audio/music_volume")
	set(value): set_setting("audio/music_volume", value)

var mouse_sensitivity: float:
	get: return get_setting("input/mouse_sensitivity")
	set(value): set_setting("input/mouse_sensitivity", value)

var invert_mouse_y: bool:
	get: return get_setting("input/invert_mouse_y")
	set(value): set_setting("input/invert_mouse_y", value)

var field_of_view: float:
	get: return get_setting("video/field_of_view")
	set(value): set_setting("video/field_of_view", value)

var fullscreen: bool:
	get: return get_setting("video/fullscreen")
	set(value): set_setting("video/fullscreen", value)

## camera bob while moving. off helps with motion sickness; weapon still bobs.
var head_bob: bool:
	get: return get_setting("video/head_bob")
	set(value): set_setting("video/head_bob", value)

## right mouse toggles aiming instead of holding it.
var aim_toggle: bool:
	get: return get_setting("input/aim_toggle")
	set(value): set_setting("input/aim_toggle", value)

## name shown to other players. empty until picked - see
## NetworkManager.local_display_name for the fallback.
var display_name: String:
	get: return get_setting("player/display_name")
	set(value): set_setting("player/display_name", value)


# --- Generic access -----------------------------------------------------

## reads a setting, falls back to fallback if the key is unknown.
func get_setting(key: String, fallback: Variant = null) -> Variant:
	if not _settings.has(key):
		if fallback == null:
			push_warning("GameConfig: unknown setting '%s'" % key)
		return fallback
	return _settings[key]["value"]


## writes a setting, fires setting_changed and saves to disk. returns false
## if the key is unknown.
##
## save = false skips the disk write, for a slider being dragged fast -
## call save_settings once it settles.
func set_setting(key: String, value: Variant, save: bool = true) -> bool:
	if not _settings.has(key):
		push_warning("GameConfig: unknown setting '%s'" % key)
		return false
	_settings[key]["value"] = value
	setting_changed.emit(key, value)
	if save:
		save_settings()
	return true


# --- Persistence --------------------------------------------------------

## fills _settings with defaults, then overwrites with anything saved.
## safe to call more than once.
func load_settings() -> void:
	var config := ConfigFile.new()
	_reset_to_defaults()

	var error := config.load(SETTINGS_PATH)
	if error != OK:
		# no save file yet - normal on first run.
		settings_loaded.emit()
		return

	for key in _settings:
		if not config.has_section_key("settings", key):
			continue
		_settings[key]["value"] = _coerce(config.get_value("settings", key), _settings[key]["type"])

	settings_loaded.emit()


## writes the current values to user://settings.cfg.
func save_settings() -> void:
	var config := ConfigFile.new()
	for key in _settings:
		config.set_value("settings", key, _settings[key]["value"])

	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_error("GameConfig: could not save settings (%s)" % error_string(error))
		return
	settings_saved.emit()


## puts every value back to default. doesn't save - call save_settings after.
func reset_to_defaults() -> void:
	_reset_to_defaults()
	for key in _settings:
		setting_changed.emit(key, _settings[key]["value"])


func _reset_to_defaults() -> void:
	for key in _settings:
		_settings[key]["value"] = _settings[key]["default"]


## ConfigFile hands everything back as a string, so "0.5" needs to become
## 0.5 and "1" needs to become true, not the string "1".
func _coerce(value: Variant, type: int) -> Variant:
	match type:
		TYPE_FLOAT:
			return float(value)
		TYPE_INT:
			return int(value)
		TYPE_BOOL:
			return bool(value)
		TYPE_STRING:
			return str(value)
		_:
			return value
