extends Node
class_name SfxAudioDiagnosticCapture

const DiagnosticsExport := preload("res://systems/multiplayer_v2/v2_diagnostics_export.gd")
const CAPTURE_DURATION_SECONDS := 12.0

var _capture_active := false
var _capture_started_usec := -1
var _capture_seed := -1
var _capture_generator_version := -1
var _capture_duration_seconds := CAPTURE_DURATION_SECONDS
var _report: Dictionary = {}
var _download_button: Button

static func is_requested() -> bool:
	if not OS.has_feature("web"):
		return false
	var mode := str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('singleplayer_capture') || ''"))
	return mode == "audio"

func start_capture(seed_value: int, generator_version: int, duration_seconds := CAPTURE_DURATION_SECONDS) -> bool:
	if _capture_active or duration_seconds <= 0.0:
		return false
	_capture_seed = seed_value
	_capture_generator_version = generator_version
	_capture_duration_seconds = duration_seconds
	_capture_started_usec = Time.get_ticks_usec()
	_capture_active = true
	_report.clear()
	SfxController.begin_diagnostic_capture()
	get_tree().create_timer(_capture_duration_seconds, true, false, true).timeout.connect(_finish_capture.bind("duration_complete"))
	return true

func is_capture_active() -> bool:
	return _capture_active

func record_callback_timing(callback_name: String, delta_seconds: float, simulation_tick: int) -> void:
	if _capture_active:
		SfxController.record_callback_timing(callback_name, delta_seconds, simulation_tick)

func record_coin_sweep(details: Dictionary) -> void:
	if _capture_active:
		SfxController.record_coin_sweep("singleplayer", details)

func finish_for_test(reason := "test_complete") -> Dictionary:
	_finish_capture(reason)
	return _report.duplicate(true)

func report_for_test() -> Dictionary:
	return _report.duplicate(true)

func _finish_capture(reason: String) -> void:
	if not _capture_active:
		return
	_capture_active = false
	var audio_diagnostics := SfxController.finish_diagnostic_capture()
	audio_diagnostics["capture_reason"] = reason
	var ended_usec := Time.get_ticks_usec()
	_report = {
		"session": {
			"network_mode": "singleplayer",
			"capture_mode": "audio_only",
			"build_id": str(ProjectSettings.get_setting("application/config/version", "unknown")),
			"godot_version": Engine.get_version_info(),
			"started_monotonic_usec": _capture_started_usec,
			"ended_monotonic_usec": ended_usec
		},
		"run": {"seed": _capture_seed, "generator_version": _capture_generator_version},
		"capture": {"duration_seconds_requested": _capture_duration_seconds, "duration_usec_actual": maxi(ended_usec - _capture_started_usec, 0), "screenshots_enabled": false, "frame_readback_count": 0},
		"browser": _browser_context_snapshot(),
		"audio_diagnostics": audio_diagnostics
	}
	_show_download_button()

func _browser_context_snapshot() -> Dictionary:
	if not OS.has_feature("web"):
		return {"available": false, "reason": "not_web"}
	var raw: Variant = JavaScriptBridge.eval("(()=>{const probe=window.__gravityRunAudioContextProbe;let audio=null;try{audio=typeof probe==='function'?probe():null}catch(e){audio={probe_error:String(e)}}return JSON.stringify({available:true,visibility:document.visibilityState,focused:document.hasFocus(),user_agent:String(navigator.userAgent||'').slice(0,192),platform:String(navigator.platform||'').slice(0,80),viewport:{width:innerWidth,height:innerHeight,dpr:devicePixelRatio},audio_context:audio===null?{state:'not_exposed_by_godot_web_driver',output_timestamp_available:false}:audio})})()", true)
	var parsed: Variant = JSON.parse_string(str(raw))
	return parsed if parsed is Dictionary else {"available": true, "audio_context": {"state": "probe_unavailable", "output_timestamp_available": false}}

func _show_download_button() -> void:
	if is_instance_valid(_download_button) or not is_inside_tree():
		return
	var layer := CanvasLayer.new()
	layer.name = "AudioDiagnosticsDownload"
	layer.layer = 90
	add_child(layer)
	_download_button = Button.new()
	_download_button.text = tr("Download audio diagnostics")
	_download_button.tooltip_text = tr("Download a bounded audio and timing report. No screenshots are included.")
	_download_button.custom_minimum_size = Vector2(280.0, 48.0)
	_download_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_download_button.position = Vector2(14.0, -62.0)
	_download_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_download_button.pressed.connect(_download_report)
	layer.add_child(_download_button)

func _download_report() -> void:
	if _report.is_empty():
		return
	var filename := "singleplayer_audio_diagnostics_%d.json" % Time.get_unix_time_from_system()
	_download_button.text = DiagnosticsExport.save_report(_report, filename)

func _exit_tree() -> void:
	if _capture_active:
		_capture_active = false
		SfxController.finish_diagnostic_capture()
