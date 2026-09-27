class_name HudScreenFx
extends ColorRect
## Full-screen treatment of the 3D view, under the rest of the HUD:
## - low health: colour drains and a heartbeat plays;
## - dead: the picture greys out and darkens as the camera falls;
## - concussion (a grenade close by): a white flash that fades;
## - transitions: a fade from black at round start and on respawn.
## One screen-reading shader, so all of it composes in a single pass.

var _desat: float = 0.0
var _dark: float = 0.0
var _white: float = 0.0
var _black: float = 0.0
var _heartbeat_left: float = 0.0
var _was_alive: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float desat = 0.0;
uniform float dark = 0.0;
uniform float white = 0.0;
uniform float black = 0.0;
void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l) * vec3(1.0, 0.97, 0.95), desat);
	vec2 uv = SCREEN_UV - 0.5;
	c *= 1.0 - dark * (0.6 + length(uv) * 1.2);
	c = mix(c, vec3(1.0), white);
	c = mix(c, vec3(0.0), black);
	COLOR = vec4(c, 1.0);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	self.material = material
	EventBus.local_concussion.connect(func(strength: float) -> void:
		_white = maxf(_white, strength * 0.9))
	GameManager.state_changed.connect(func(_from: int, to: int) -> void:
		if to == GamePhase.Phase.BUY:
			fade_from_black())


func fade_from_black() -> void:
	_black = 1.0


func update_view(player: Player, delta: float) -> void:
	var alive := player != null and player.state.is_alive
	var low := alive and player.state.health <= 35
	var target_desat := 0.0
	var target_dark := 0.0
	if player != null and not alive:
		target_desat = 0.85
		target_dark = 0.35
	elif low:
		target_desat = lerpf(0.55, 0.2, clampf((player.state.health - 5) / 30.0, 0.0, 1.0))
		target_dark = 0.12
	_desat = move_toward(_desat, target_desat, delta * 1.2)
	_dark = move_toward(_dark, target_dark, delta * 1.2)
	_white = maxf(_white - delta * 0.9, 0.0)
	_black = maxf(_black - delta * 1.8, 0.0)
	if alive and not _was_alive:
		fade_from_black()
	_was_alive = alive

	if low:
		_heartbeat_left -= delta
		if _heartbeat_left <= 0.0:
			_heartbeat_left = lerpf(0.55, 0.95, clampf(player.state.health / 35.0, 0.0, 1.0))
			Audio.play(&"heartbeat", -4.0, 0.0)

	var m := material as ShaderMaterial
	m.set_shader_parameter(&"desat", _desat)
	m.set_shader_parameter(&"dark", _dark)
	m.set_shader_parameter(&"white", _white)
	m.set_shader_parameter(&"black", _black)
	visible = _desat > 0.001 or _dark > 0.001 or _white > 0.001 or _black > 0.001
