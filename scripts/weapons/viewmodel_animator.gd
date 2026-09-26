class_name ViewmodelAnimator
extends Node
## Keyframed first-person animation: draw, reload, inspect, and the knife's
## slashes, stab and toss.
##
## Hand-authored here rather than imported: skeletal FPS animations only fit the
## rig they were made for, and this viewmodel is assembled from separate gun,
## hand and sleeve models. Each clip is a list of keys over normalised time,
## and each key sets any of these channels (missing ones hold at their rest
## value):
##   [code]pos[/code] / [code]rot[/code] - the gun's offset (metres) and rotation
##       (degrees, pitch/yaw/roll) about a pivot near its middle
##   [code]hand[/code] - how far the left hand has left its grip for the
##       magazine (0..1)
##   [code]mag[/code]  - how far the magazine has dropped out of the gun (0..1)
##   [code]open[/code] - how far the right hand has opened (0..1)
##   [code]spin[/code] / [code]lift[/code] - the knife's flip (degrees) and toss
##       height (metres) out of the hand
## Keys blend with smoothstep, so every motion eases in and out. [Weapon] owns
## one and drives it; it moves only the viewmodel node, the magazine, the
## knife's spin node and [ViewmodelArms]' hand controls - never gameplay.

## Sounds and moments a clip marks: [code]mag_out[/code], [code]mag_in[/code],
## [code]rack[/code], [code]shing[/code].
signal cue(name: StringName)

const MAG_DROP := 0.34

var _viewmodel: Node3D = null
var _rest := Transform3D.IDENTITY
var _pivot := Vector3.ZERO
var _arms: ViewmodelArms = null
var _mag: Node3D = null
var _mag_rest := Transform3D.IDENTITY
var _mag_grip_local := Vector3.ZERO
var _mag_hide_inserted: bool = false
var _spin: Node3D = null
var _spin_rest := Transform3D.IDENTITY
var _knife: bool = false

var _clip_name: StringName = &""
var _keys: Array = []
var _cues: Array = []
var _length: float = 0.0
var _t: float = 0.0
var _slash_flip: bool = false


func _init() -> void:
	# Before the arms read the pose this frame.
	process_priority = -10


## Points the animator at a freshly built viewmodel.
func setup(viewmodel: Node3D, model: Node3D, arms: ViewmodelArms, data: WeaponData) -> void:
	stop()
	_viewmodel = viewmodel
	_rest = Transform3D(Basis(), viewmodel.position)
	_arms = arms
	_knife = data != null and data.is_melee
	_mag = null
	_spin = null
	if model == null:
		return
	var hand := model.find_child("HandR", true, false) as Node3D
	var hand_at := ViewmodelArms._relative(hand, viewmodel).origin if hand != null else Vector3.ZERO
	_pivot = hand_at + Vector3(0, 0.04, -0.12)
	var mag_path: NodePath = model.get_meta(&"magazine", NodePath())
	if not mag_path.is_empty():
		_mag = model.get_node_or_null(mag_path) as Node3D
	if _mag != null:
		_mag_rest = _mag.transform
		_mag_hide_inserted = bool(model.get_meta(&"magazine_hidden", false))
		_mag_grip_local = _grip_point(_mag)
	_spin = model.find_child("Spin", true, false) as Node3D
	if _spin != null:
		_spin_rest = _spin.transform
	_apply(_pose_at_rest())


## The lower quarter of the magazine's mesh, in its own space: where the left
## hand takes hold of it.
static func _grip_point(mag: Node3D) -> Vector3:
	var box := AABB()
	var first := true
	for mesh in [mag] + mag.find_children("*", "MeshInstance3D", true, false):
		if not mesh is MeshInstance3D:
			continue
		var xf := ViewmodelArms._relative(mesh, mag) if mesh != mag else Transform3D.IDENTITY
		var b: AABB = xf * mesh.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var c := box.get_center()
	return Vector3(c.x, box.position.y + box.size.y * 0.3, c.z)


# --- Playback -----------------------------------------------------------------------

func is_playing(clip: StringName = &"") -> bool:
	return _clip_name != &"" and (clip == &"" or clip == _clip_name)


func stop() -> void:
	_clip_name = &""
	_keys = []
	if _viewmodel != null:
		_apply(_pose_at_rest())


func play_draw() -> float:
	if _knife:
		_play(&"draw", 0.62, _knife_draw_keys(), [[0.1, &"shing"]])
		return 0.45
	var length := 0.42
	_play(&"draw", length, [
		_k(0.0, Vector3(0.05, -0.3, 0.08), Vector3(-55, 12, -30)),
		_k(0.68, Vector3(0.0, 0.006, 0.0), Vector3(3, -1, 1.5)),
		_k(1.0, Vector3.ZERO, Vector3.ZERO),
	], [])
	return length * 0.8


func play_reload(duration: float) -> void:
	if _knife:
		return
	# Brought up and in, rolled onto its side, so the magazine well faces the
	# camera for the swap.
	var tilt := Vector3(-0.08, 0.075, 0.03)
	var tilt_rot := Vector3(14, 12, 30)
	var slap := Vector3(-0.08, 0.09, 0.03)
	_play(&"reload", duration, [
		_k(0.0, Vector3.ZERO, Vector3.ZERO),
		_k(0.14, tilt, tilt_rot, {"hand": 1.0}),
		_k(0.24, tilt, tilt_rot + Vector3(2, 0, 2), {"hand": 1.0, "mag": 0.3}),
		_k(0.4, tilt, tilt_rot, {"hand": 1.0, "mag": 1.0}),
		_k(0.5, tilt, tilt_rot, {"hand": 1.0, "mag": 1.0}),
		_k(0.64, tilt, tilt_rot + Vector3(-2, 0, 0), {"hand": 1.0, "mag": 0.22}),
		_k(0.7, slap, tilt_rot + Vector3(4, 0, -3), {"hand": 1.0, "mag": 0.0}),
		_k(0.8, tilt, tilt_rot, {"hand": 0.0}),
		_k(0.86, tilt + Vector3(0, 0, 0.02), tilt_rot + Vector3(-5, 0, 6)),
		_k(1.0, Vector3.ZERO, Vector3.ZERO),
	], [[0.2, &"mag_out"], [0.69, &"mag_in"], [0.85, &"rack"]])


func play_inspect() -> void:
	if _knife:
		_play(&"inspect", 3.4, _knife_inspect_keys(), [[0.47, &"shing"]])
		return
	_play(&"inspect", 3.6, [
		_k(0.0, Vector3.ZERO, Vector3.ZERO),
		_k(0.16, Vector3(-0.1, 0.06, 0.07), Vector3(10, 55, -16)),
		_k(0.42, Vector3(-0.1, 0.066, 0.075), Vector3(7, 61, -19)),
		_k(0.58, Vector3(-0.06, 0.07, 0.06), Vector3(14, -22, 54)),
		_k(0.82, Vector3(-0.058, 0.074, 0.058), Vector3(16, -26, 58)),
		_k(1.0, Vector3.ZERO, Vector3.ZERO),
	], [])


## A light knife swing, alternating direction each time.
func play_slash() -> void:
	_slash_flip = not _slash_flip
	var s := 1.0 if _slash_flip else -1.0
	var wind := Vector3(0.06, 0.05, 0.02) if _slash_flip else Vector3(-0.14, 0.07, 0.02)
	var through := Vector3(-0.28, -0.07, -0.08) if _slash_flip else Vector3(0.1, -0.09, -0.08)
	_play(&"slash", 0.5, [
		_k(0.0, Vector3.ZERO, Vector3.ZERO),
		_k(0.2, wind, Vector3(12, -35 * s, -48 * s)),
		_k(0.42, through, Vector3(-12, 68 * s, 72 * s)),
		_k(0.6, through * 0.6, Vector3(-6, 40 * s, 40 * s)),
		_k(1.0, Vector3.ZERO, Vector3.ZERO),
	], [])


## The heavy stab: drawn back, driven forward.
func play_stab() -> void:
	_play(&"stab", 0.95, [
		_k(0.0, Vector3.ZERO, Vector3.ZERO),
		_k(0.3, Vector3(0.03, -0.03, 0.13), Vector3(22, -6, -14)),
		_k(0.42, Vector3(-0.07, 0.03, -0.3), Vector3(-14, 6, 4)),
		_k(0.6, Vector3(-0.06, 0.025, -0.26), Vector3(-12, 5, 4)),
		_k(1.0, Vector3.ZERO, Vector3.ZERO),
	], [])


func _knife_draw_keys() -> Array:
	# Up from below, flipping end over end into the grip.
	return [
		_k(0.0, Vector3(0.06, -0.3, 0.05), Vector3(-40, 20, -40), {"spin": -540.0, "open": 0.8, "lift": 0.05}),
		_k(0.55, Vector3(0.0, 0.012, 0.0), Vector3(4, 0, 2), {"spin": -40.0, "open": 0.6, "lift": 0.02}),
		_k(0.72, Vector3.ZERO, Vector3(1, 0, 0), {"spin": 0.0, "open": 0.0}),
		_k(1.0, Vector3.ZERO, Vector3.ZERO),
	]


func _knife_inspect_keys() -> Array:
	# Show one face, toss it end over end, catch, show the other face.
	return [
		_k(0.0, Vector3.ZERO, Vector3.ZERO),
		_k(0.14, Vector3(-0.12, 0.08, 0.05), Vector3(0, 70, 12)),
		_k(0.32, Vector3(-0.12, 0.085, 0.052), Vector3(3, 76, 14)),
		_k(0.4, Vector3(-0.1, 0.07, 0.04), Vector3(-8, 20, 0), {"open": 0.3}),
		_k(0.46, Vector3(-0.1, 0.06, 0.04), Vector3(-10, 15, 0), {"open": 1.0, "lift": 0.14, "spin": 200.0}),
		_k(0.55, Vector3(-0.1, 0.05, 0.04), Vector3(-6, 15, 0), {"open": 1.0, "lift": 0.02, "spin": 360.0}),
		_k(0.6, Vector3(-0.09, 0.055, 0.04), Vector3(-4, 10, 0), {"open": 0.0, "spin": 360.0}),
		_k(0.74, Vector3(-0.08, 0.075, 0.05), Vector3(10, -34, 42), {"spin": 360.0}),
		_k(0.88, Vector3(-0.08, 0.078, 0.052), Vector3(12, -38, 46), {"spin": 360.0}),
		_k(1.0, Vector3.ZERO, Vector3.ZERO, {"spin": 360.0}),
	]


static func _k(t: float, pos: Vector3, rot: Vector3, extra := {}) -> Dictionary:
	var key := {"t": t, "pos": pos, "rot": rot}
	key.merge(extra)
	return key


func _play(clip: StringName, length: float, keys: Array, cues: Array) -> void:
	_clip_name = clip
	_keys = keys
	_cues = cues.duplicate()
	_length = maxf(length, 0.05)
	_t = 0.0


func _process(delta: float) -> void:
	if _viewmodel == null or not is_instance_valid(_viewmodel):
		return
	if _clip_name == &"":
		return
	_t += delta / _length
	while not _cues.is_empty() and _t >= float(_cues[0][0]):
		var name: StringName = _cues.pop_front()[1]
		cue.emit(name)
	if _t >= 1.0:
		_clip_name = &""
		_apply(_pose_at_rest())
		return
	_apply(_sample(_t))


# --- Evaluation -------------------------------------------------------------------

func _pose_at_rest() -> Dictionary:
	return {"pos": Vector3.ZERO, "rot": Vector3.ZERO, "hand": 0.0, "mag": 0.0, "open": 0.0,
		"spin": 0.0, "lift": 0.0}


## The pose [param t] of the way through the clip: each channel eased between
## the keys either side of it.
func _sample(t: float) -> Dictionary:
	var pose := _pose_at_rest()
	for channel in pose.keys():
		var prev: Dictionary = {}
		var next: Dictionary = {}
		for key: Dictionary in _keys:
			if not key.has(channel) and not (channel in ["hand", "mag", "open", "spin", "lift"]):
				continue
			if float(key.t) <= t:
				prev = key
			elif next.is_empty():
				next = key
		var a: Variant = prev.get(channel, pose[channel]) if not prev.is_empty() else pose[channel]
		if next.is_empty() or prev.is_empty():
			pose[channel] = a
			continue
		var b: Variant = next.get(channel, pose[channel])
		var span := float(next.t) - float(prev.t)
		var u := smoothstep(0.0, 1.0, (t - float(prev.t)) / maxf(span, 0.0001))
		pose[channel] = lerp(a, b, u)
	return pose


func _apply(pose: Dictionary) -> void:
	if _viewmodel == null:
		return
	var rot: Vector3 = pose.rot
	var basis := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	_viewmodel.transform = Transform3D(basis, _rest.origin + (pose.pos as Vector3) + _pivot - basis * _pivot)

	if _mag != null and is_instance_valid(_mag):
		var drop: float = pose.mag
		var parent := _mag.get_parent() as Node3D
		var to_parent := ViewmodelArms._relative(parent, _viewmodel).basis.inverse()
		var offset := to_parent * (Vector3(0, -1, 0.12).normalized() * MAG_DROP * drop)
		_mag.transform = Transform3D(_mag_rest.basis, _mag_rest.origin + offset)
		if _mag_hide_inserted:
			_mag.visible = drop > 0.04

	if _arms != null and is_instance_valid(_arms):
		var hand: float = pose.hand if _mag != null else 0.0
		_arms.left_weight = hand
		if hand > 0.0 and _mag != null:
			var grip := ViewmodelArms._relative(_mag, _viewmodel) * _mag_grip_local
			var frame := Transform3D(ViewmodelArms._grip_basis("vertical"), grip)
			_arms.left_override = frame
		_arms.grip_open[0] = pose.open

	if _spin != null and is_instance_valid(_spin):
		var parent_basis := ViewmodelArms._relative(_spin.get_parent(), _viewmodel).basis
		var lift := parent_basis.inverse() * Vector3(0, float(pose.lift), 0)
		var spin := Basis(Vector3.RIGHT, deg_to_rad(float(pose.spin)))
		_spin.transform = Transform3D(spin * _spin_rest.basis, _spin_rest.origin + lift)
