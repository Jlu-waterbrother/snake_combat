extends Node

@onready var world := $World
@onready var hud := $HUD

@export var available_player_skins: Array[Resource] = []
@export var available_player_skin_names: PackedStringArray = PackedStringArray()

var _is_paused: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_enforce_mobile_landscape_orientation()
	_install_mobile_web_orientation_adapt()
	hud.bind_world(world)
	hud.start_match_requested.connect(_on_start_match_requested)
	_configure_pre_match_skin_selection()

func _enforce_mobile_landscape_orientation() -> void:
	if not _is_touch_controls_environment():
		return
	var os_name: String = OS.get_name()
	if os_name != "Android" and os_name != "iOS":
		return
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)

func _install_mobile_web_orientation_adapt() -> void:
	if OS.get_name() != "Web":
		return
	if not _is_touch_controls_environment():
		return
	JavaScriptBridge.eval(
		"""(function () {
			if (window.__snakeCombatOrientationAdaptInstalled) {
				return;
			}
			window.__snakeCombatOrientationAdaptInstalled = true;
			const syncViewport = () => {
				const vv = window.visualViewport;
				const width = Math.round(vv ? vv.width : window.innerWidth);
				const height = Math.round(vv ? vv.height : window.innerHeight);
				const canvas = document.getElementById('canvas');
				if (canvas) {
					canvas.style.width = width + 'px';
					canvas.style.height = height + 'px';
				}
				window.dispatchEvent(new Event('resize'));
			};
			const tryEnableOrientationAuto = async () => {
				try {
					if (screen.orientation && screen.orientation.lock) {
						await screen.orientation.lock('any');
					}
				} catch (_err) {}
				syncViewport();
			};
			window.addEventListener('resize', syncViewport, { passive: true });
			window.addEventListener('orientationchange', syncViewport, { passive: true });
			if (window.visualViewport) {
				window.visualViewport.addEventListener('resize', syncViewport, { passive: true });
			}
			document.addEventListener('touchstart', tryEnableOrientationAuto, { passive: true });
			document.addEventListener('pointerdown', tryEnableOrientationAuto, { passive: true });
			document.addEventListener('visibilitychange', function () {
				if (!document.hidden) {
					syncViewport();
				}
			});
			syncViewport();
		}());""",
		true
	)

func _is_touch_controls_environment() -> bool:
	if DisplayServer.is_touchscreen_available():
		return true
	if OS.has_feature("mobile"):
		return true
	if OS.get_name() != "Web":
		return false
	var web_touch_value: Variant = JavaScriptBridge.eval(
		"('ontouchstart' in window) || ((navigator.maxTouchPoints || 0) > 0) || ((window.matchMedia && (window.matchMedia('(pointer: coarse)').matches || window.matchMedia('(hover: none)').matches)) || false) || (/Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent || ''))",
		true
	)
	if web_touch_value is bool:
		return web_touch_value
	return false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()

func _toggle_pause() -> void:
	_is_paused = not _is_paused
	if _is_paused:
		Input.action_release("turn_left")
		Input.action_release("turn_right")
		Input.action_release("aim_left")
		Input.action_release("aim_right")
		Input.action_release("aim_up")
		Input.action_release("aim_down")
		Input.action_release("boost")
	world.set_pause_state(_is_paused)
	get_tree().paused = _is_paused

func _configure_pre_match_skin_selection() -> void:
	if not hud.has_method("configure_pre_match_skins"):
		return

	var current_skin: Resource = null
	if world.has_method("get_player_skin"):
		var skin_value: Variant = world.call("get_player_skin")
		if skin_value is Resource:
			current_skin = skin_value

	var skin_options: Array[Resource] = []
	if available_player_skins.is_empty():
		if current_skin != null:
			skin_options.append(current_skin)
	else:
		for skin: Resource in available_player_skins:
			if skin != null:
				skin_options.append(skin)

	hud.call("configure_pre_match_skins", skin_options, available_player_skin_names, current_skin)

	var prefers_mouse_controls: bool = true
	if world.has_method("get_player_mouse_controls_enabled"):
		var mouse_control_value: Variant = world.call("get_player_mouse_controls_enabled")
		if mouse_control_value is bool:
			prefers_mouse_controls = mouse_control_value
	if hud.has_method("configure_pre_match_controls"):
		hud.call("configure_pre_match_controls", prefers_mouse_controls)

func _on_start_match_requested(selected_skin: Resource, use_mouse_controls: bool) -> void:
	if world.has_method("set_player_mouse_controls_enabled"):
		world.call("set_player_mouse_controls_enabled", use_mouse_controls)
	if selected_skin != null and world.has_method("set_player_skin"):
		world.call("set_player_skin", selected_skin)
	world.start_match()
