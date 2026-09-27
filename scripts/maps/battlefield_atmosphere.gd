class_name BattlefieldAtmosphere
extends Node3D
## everything that makes a map feel like part of a war instead of a range:
## dust, smoke columns, burning barrels, scorches, wind, distant artillery
## and firefights, a war-film grade and film grain.
##
## purely presentation, purely local - nothing collides or replicates
## (except the fire barrels, placed like any prop). a map adds one instance
## and calls the add_* helpers; _ready sets up the parts that need no placing.

## how often something booms in the distance / a firefight flares, seconds
## (randomized between the two values).
const BOOM_INTERVAL := Vector2(9.0, 22.0)
const BURST_INTERVAL := Vector2(4.0, 11.0)

var _fires: Array[Dictionary] = []
var _next_boom: float = 3.0
var _next_burst: float = 1.5
var _dust: CPUParticles3D = null
var _wind: AudioStreamPlayer = null
var _time: float = 0.0


func _ready() -> void:
	_add_dust_motes()
	_add_film_overlay()
	_wind = AudioStreamPlayer.new()
	_wind.stream = Audio._library.get(&"wind")
	_wind.volume_db = -20.0
	add_child(_wind)
	_wind.play()
	_grade_environment.call_deferred()


# --- Placement helpers (called by the map) -----------------------------------------------

## a column of smoke rising from somewhere beyond the walls.
func add_smoke_column(at: Vector3, scale: float = 1.0) -> void:
	var low := GraphicsQuality.current() == GraphicsQuality.Level.LOW
	var column := BattleFx.smoke_column(scale)
	if low:
		# big soft quads are the costliest thing here on a weak GPU.
		column.amount = 30
	add_child(column)
	column.position = at
	column.emitting = true
	# already billowing when the match starts, not just lighting up.
	column.restart()
	if low:
		return
	# a dull glow at the base, like something's still burning there.
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.45, 0.15)
	glow.light_energy = 2.0 * scale
	glow.omni_range = 14.0 * scale
	glow.shadow_enabled = false
	add_child(glow)
	glow.position = at + Vector3(0, 1.5, 0)


## flames, embers, smoke, flickering light and crackle at [param at] (top of
## a barrel or wreck).
func add_fire(at: Vector3, width: float = 0.5) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = at
	for emitter in [BattleFx.flames(width), BattleFx.embers(), BattleFx.fire_smoke()]:
		root.add_child(emitter)
		emitter.emitting = true
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.22)
	light.omni_range = 6.0
	light.shadow_enabled = false
	light.position = Vector3(0, 0.35, 0)
	root.add_child(light)
	var sound := AudioStreamPlayer3D.new()
	sound.stream = Audio._library.get(&"fire_crackle")
	sound.volume_db = -10.0
	sound.unit_size = 3.0
	sound.max_distance = 18.0
	root.add_child(sound)
	sound.play()
	_fires.append({"light": light, "seed": randf() * 100.0})


## a blast scorch (or, with [param stain], an oil stain) on whatever's below [param at].
func add_scorch(at: Vector3, size: float, stain: bool = false) -> void:
	var decal := Decal.new()
	decal.texture_albedo = BattleFx.stain_texture() if stain else BattleFx.scorch_texture()
	decal.size = Vector3(size, 1.0, size)
	decal.cull_mask = 1
	decal.upper_fade = 0.2
	decal.lower_fade = 0.2
	add_child(decal)
	decal.position = at + Vector3(0, 0.3, 0)
	decal.rotation.y = randf() * TAU


# --- Always-on parts ------------------------------------------------------------------------

## fine dust hanging in the sunlight around whoever's watching.
func _add_dust_motes() -> void:
	var p := CPUParticles3D.new()
	p.amount = 90
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(9, 3, 9)
	p.direction = Vector3(1, 0.1, 0.3)
	p.spread = 40.0
	p.gravity = Vector3(0.12, -0.02, 0.05)
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.25
	var quad := QuadMesh.new()
	quad.size = Vector2(0.012, 0.012)
	p.mesh = quad
	p.material_override = BattleFx.particle_material(MuzzleFlashMesh.glow_texture(), true)
	p.color_ramp = BattleFx._ramp([Color(1, 0.92, 0.78, 0.0), Color(1, 0.92, 0.78, 0.35), Color(1, 0.92, 0.78, 0.0)])
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.emitting = true
	_dust = p


## film grain and a soft vignette over the 3d view, under the hud.
func _add_film_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float grain = 0.045;
uniform float vignette = 0.42;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + TIME * 17.0) * 43758.5453); }
void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float v = smoothstep(0.35, 1.05, length(uv) * 1.25) * vignette;
	float n = hash(floor(FRAGCOORD.xy / 1.5)) - 0.5;
	// grain: specks of light and dark, vignette darkens over it.
	float g = abs(n) * grain * 2.0;
	COLOR = vec4(vec3(step(0.0, n) * (1.0 - step(g, v))), max(g, v));
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	rect.material = material
	layer.add_child(rect)


## war-film grade on the map's environment: teal shadows, warm highlights,
## a bit less saturation, firmer contrast. done as a lookup table so it
## costs nothing per frame.
func _grade_environment() -> void:
	var world := get_parent().find_child("WorldEnvironment", true, false) as WorldEnvironment
	if world == null or world.environment == null:
		return
	var n := 17
	var images: Array[Image] = []
	for b in n:
		var img := Image.create(n, n, false, Image.FORMAT_RGB8)
		for g in n:
			for r in n:
				img.set_pixel(r, g, _grade(Color(r / (n - 1.0), g / (n - 1.0), b / (n - 1.0))))
		images.append(img)
	var lut := ImageTexture3D.new()
	lut.create(Image.FORMAT_RGB8, n, n, n, false, images)
	world.environment.adjustment_enabled = true
	world.environment.adjustment_color_correction = lut


static func _grade(c: Color) -> Color:
	var luma := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
	# slightly desaturated.
	var out := Color(lerpf(luma, c.r, 0.86), lerpf(luma, c.g, 0.86), lerpf(luma, c.b, 0.86))
	# split toning: cool shadows, warm highlights.
	var shadow := 1.0 - smoothstep(0.0, 0.5, luma)
	var high := smoothstep(0.45, 1.0, luma)
	out.r += -0.025 * shadow + 0.035 * high
	out.g += 0.004 * shadow + 0.012 * high
	out.b += 0.03 * shadow - 0.04 * high
	# gentle s-curve.
	for i in 3:
		var v: float = out[i]
		out[i] = clampf(v + (v - 0.5) * 0.12 * (1.0 - absf(v - 0.5) * 2.0), 0.0, 1.0)
	return out


# --- Per frame ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	var camera := get_viewport().get_camera_3d()
	if camera != null and _dust != null:
		_dust.global_position = camera.global_position
	for fire in _fires:
		var t: float = _time * 9.0 + fire.seed
		(fire.light as OmniLight3D).light_energy = 1.6 + sin(t) * 0.25 + sin(t * 2.7) * 0.2 + randf() * 0.25

	_next_boom -= delta
	if _next_boom <= 0.0:
		_next_boom = randf_range(BOOM_INTERVAL.x, BOOM_INTERVAL.y)
		_distant(&"distant_boom", -4.0)
	_next_burst -= delta
	if _next_burst <= 0.0:
		_next_burst = randf_range(BURST_INTERVAL.x, BURST_INTERVAL.y)
		_distant(&"distant_burst", -8.0)


## a sound from somewhere far off in a random direction, heard through the
## listener so it comes from one side.
func _distant(sound: StringName, volume_db: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var angle := randf() * TAU
	var at := camera.global_position + Vector3(cos(angle), 0.3, sin(angle)) * 40.0
	Audio.play_at(sound, at, volume_db, 0.12, 400.0)
