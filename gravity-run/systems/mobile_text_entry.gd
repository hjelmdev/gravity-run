extends Node

signal entry_submitted(field: String, value: String)

var is_mobile_web := false
var _poll_elapsed := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web"):
		is_mobile_web = bool(JavaScriptBridge.eval("Boolean(window.parent.GravityRunMobileInput && window.parent.GravityRunMobileInput.isMobile)", true))

func _process(delta: float) -> void:
	if not is_mobile_web:
		return
	_poll_elapsed += delta
	if _poll_elapsed < 0.1:
		return
	_poll_elapsed = 0.0
	var response: Variant = JavaScriptBridge.eval("window.parent.GravityRunMobileInput.takeResult()", true)
	if not response is String or response.is_empty():
		return
	var entry: Variant = JSON.parse_string(response)
	if entry is Dictionary:
		entry_submitted.emit(str(entry.get("field", "")), str(entry.get("value", "")))

func open(field: String, value: String, label: String, input_type: String = "text", max_length: int = 64, input_mode: String = "text", autocomplete: String = "off", autocapitalize: String = "sentences") -> bool:
	if not is_mobile_web:
		return false
	var request := JSON.stringify({"field": field, "value": value, "label": label, "type": input_type, "maxLength": max_length, "inputMode": input_mode, "autocomplete": autocomplete, "autocapitalize": autocapitalize})
	return bool(JavaScriptBridge.eval("window.parent.GravityRunMobileInput.open(%s)" % request, true))

func cancel() -> void:
	if is_mobile_web:
		JavaScriptBridge.eval("window.parent.GravityRunMobileInput.cancel()", true)
