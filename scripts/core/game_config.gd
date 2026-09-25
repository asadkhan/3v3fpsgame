extends Node
## Player-owned preferences, saved to [code]user://settings.cfg[/code].
## Registered as the [code]GameConfig[/code] autoload.
##
## This holds only settings the player controls: audio levels, mouse
## sensitivity, field of view. Anything that is part of the game's design -
## weapon damage, ability cooldowns, how many rounds a match lasts - belongs
## in [code]res://data/[/code] as a [Resource], not here. The test is simple:
## would a player expect to change this in an options menu? If not, it is
## game data, not config.
##
## Settings live in one dictionary so saving and loading stay generic. The
## properties below are typed views onto that dictionary, so you get both
## [code]GameConfig.mouse_sensitivity[/code] and
## [code]GameConfig.get_setting("input/mouse_sensitivity")[/code] from a
## single source of truth.

const SETTINGS_PATH := "user://settings.cfg"

## Fires after [method load_settings] finishes, and once on startup.
signal settings_loaded

## Fires after [method save_settings] succeeds.
signal settings_saved

## Fires whenever any value is changed, including by [method set_setting].
signal setting_changed(key: String, value: Variant)

## Every setting, its default, and its type. The type is needed because
## [ConfigFile] stores everything as a string.
var _settings: Dictionary = {
	"audio/master_volume": {"default": 0.8, "type": TYPE_FLOAT},
	"input/mouse_sensitivity": {"default": 0.4, "type": TYPE_FLOAT},
	"input/invert_mouse_y": {"default": false, "type": TYPE_BOOL},
	"video/field_of_view": {"default": 90.0, "type": TYPE_FLOAT},
	"video/fullscreen": {"default": false, "type": TYPE_BOOL},
}


func _ready() -> void:
	load_settings()


# --- Typed access -------------------------------------------------------
# Properties are views onto _settings, so assigning to one goes through
# set_setting() and still fires setting_changed + saves.

var master_volume: float:
	get: return get_setting("audio/master_volume")
	set(value): set_setting("audio/master_volume", value)

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


# --- Generic access -----------------------------------------------------

## Reads a setting, falling back to its default if the key is unknown.
func get_setting(key: String, fallback: Variant = null) -> Variant:
	if not _settings.has(key):
		if fallback == null:
			push_warning("GameConfig: unknown setting '%s'" % key)
		return fallback
	return _settings[key]["value"]


## Writes a setting, fires [signal setting_changed] and saves to disk.
## Returns false if the key is unknown.
func set_setting(key: String, value: Variant) -> bool:
	if not _settings.has(key):
		push_warning("GameConfig: unknown setting '%s'" % key)
		return false
	_settings[key]["value"] = value
	setting_changed.emit(key, value)
	save_settings()
	return true


# --- Persistence --------------------------------------------------------

## Fills [member _settings] with the defaults, then overwrites anything that
## was saved previously. Safe to call more than once.
func load_settings() -> void:
	var config := ConfigFile.new()
	_reset_to_defaults()

	var error := config.load(SETTINGS_PATH)
	if error != OK:
		# No save file yet. That is the normal first-run case, not a problem.
		settings_loaded.emit()
		return

	for key in _settings:
		if not config.has_section_key("settings", key):
			continue
		_settings[key]["value"] = _coerce(config.get_value("settings", key), _settings[key]["type"])

	settings_loaded.emit()


## Writes the current values to [code]user://settings.cfg[/code].
func save_settings() -> void:
	var config := ConfigFile.new()
	for key in _settings:
		config.set_value("settings", key, _settings[key]["value"])

	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_error("GameConfig: could not save settings (%s)" % error_string(error))
		return
	settings_saved.emit()


## Puts every value back to its default. Does not save; call
## [method save_settings] afterwards to make it stick.
func reset_to_defaults() -> void:
	_reset_to_defaults()
	for key in _settings:
		setting_changed.emit(key, _settings[key]["value"])


func _reset_to_defaults() -> void:
	for key in _settings:
		_settings[key]["value"] = _settings[key]["default"]


## [ConfigFile] gives everything back as a string, so "0.5" has to become
## 0.5 and "1" has to become true rather than the string "1".
func _coerce(value: Variant, type: int) -> Variant:
	match type:
		TYPE_FLOAT:
			return float(value)
		TYPE_INT:
			return int(value)
		TYPE_BOOL:
			return bool(value)
		_:
			return value
