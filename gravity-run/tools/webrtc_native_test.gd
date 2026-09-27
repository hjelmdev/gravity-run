extends SceneTree

func _initialize() -> void:
	var peer := WebRTCPeerConnection.new()
	var error: int = peer.initialize({"iceServers": []})
	if error != OK:
		push_error("Native WebRTC peer initialization failed: %d" % error)
		quit(1)
		return
	var channel: WebRTCDataChannel = peer.create_data_channel("native-test", {"ordered": true})
	if channel == null:
		push_error("Native WebRTC data-channel creation failed.")
		peer.close()
		quit(1)
		return
	peer.close()
	print("Native WebRTC extension test passed.")
	quit(0)
