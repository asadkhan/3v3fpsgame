class_name GraphicsQuality
extends RefCounted
## rendering presets, applied to a map's WorldEnvironment and sun.
##
## the expensive stuff (SDFGI bounced light, screen-space indirect light,
## volumetric haze, ambient occlusion) makes the world look real but costs a
## weak GPU a lot - on an Intel UHD laptop the full set runs 12fps, Low runs
## 60. player picks a level, or AUTO picks one from the GPU type.
##
## stored in video/graphics_quality (GameConfig).

enum Level { AUTO = -1, LOW = 0, MEDIUM = 1, HIGH = 2, ULTRA = 3 }

const NAMES := {
	Level.AUTO: "AUTO", Level.LOW: "LOW", Level.MEDIUM: "MEDIUM", Level.HIGH: "HIGH", Level.ULTRA: "ULTRA",
}


## the level in effect: the saved choice, or the automatic one
static func current() -> int:
	var chosen: int = GameConfig.get_setting("video/graphics_quality", Level.AUTO)
	return automatic() if chosen == Level.AUTO else chosen


## low for integrated graphics, high for a dedicated card
static func automatic() -> int:
	# device type alone isn't enough: under D3D12 an Intel UHD reports itself
	# as discrete. Intel graphics other than Arc are integrated regardless of
	# what the driver claims.
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	var intel_integrated := adapter.contains("intel") and not adapter.contains("arc")
	if RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU \
			or intel_integrated:
		return Level.LOW
	return Level.HIGH


## applies the current level to every environment and sun under root
static func apply(root: Node) -> void:
	var level := current()
	for node in root.find_children("*", "WorldEnvironment", true, false):
		var env := (node as WorldEnvironment).environment
		if env == null:
			continue
		env.ssao_enabled = level >= Level.MEDIUM
		env.ssil_enabled = level >= Level.HIGH
		env.volumetric_fog_enabled = level >= Level.HIGH
		env.sdfgi_enabled = level >= Level.ULTRA
		# bounce light only: SDFGI's own sky term reads the HDR sky way too
		# bright and turns shaded ground silver. sky light already comes in
		# as ambient.
		env.sdfgi_read_sky_light = false
		env.sdfgi_energy = 2.5
		env.glow_enabled = true
	for node in root.find_children("*", "DirectionalLight3D", true, false):
		var sun := node as DirectionalLight3D
		sun.directional_shadow_max_distance = 60.0 if level == Level.LOW else 110.0
		sun.shadow_blur = 1.0 if level == Level.LOW else 1.2
