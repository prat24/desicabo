## RelayPeer — the web build's way online. Browsers cannot open the UDP sockets
## ENet needs, but they can hold a WebSocket open, so every player keeps one to
## the relay on the game's own server (deploy/relay/relay.py) and the relay
## hands each packet to the right player in the room.
##
## To the rest of the game this is just another MultiplayerPeer: the host is
## peer 1 and runs the game, each joiner is given an id by the relay, and
## SceneMultiplayer relays joiner-to-joiner messages through the host exactly as
## it does over ENet. Nothing that plays the game knows which one it is on.
class_name RelayPeer
extends MultiplayerPeerExtension

## Must match PROTOCOL_VERSION in relay.py.
const PROTOCOL_VERSION := 1
## Must match ROOM_CODE_LENGTH in relay.py.
const ROOM_CODE_LENGTH := 5
const HOST_PEER_ID := 1
## In front of every game packet: peer id (int32), channel, transfer mode. The
## id is the target on the way up and the sender on the way down.
const HEADER_SIZE := 6
## The relay closes any connection that sends a message bigger than this.
const MAX_PACKET_SIZE := 64 * 1024 - HEADER_SIZE
## How long the relay gets to answer before the attempt counts as failed.
const CONNECT_TIMEOUT_MSEC := 10000

## The relay let us in: `room_code` holds the code to share, or the one joined.
signal room_ready

var room_code := ""
## What went wrong, in words for the player — the relay's own when it gave one
## ("No game with that code."). Empty while all is well.
var failure_reason := ""

var socket := WebSocketPeer.new()
var hello := {}
var hello_sent := false
var status := MultiplayerPeer.CONNECTION_DISCONNECTED
var unique_id := 0
var connect_started_msec := 0
## Where and how the next packet goes, as SceneMultiplayer sets it before each one.
var send_target := 0
var send_channel := 0
var send_mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var refusing_new_connections := false
## Game packets waiting to be read, oldest first: [sender, channel, mode, payload].
var incoming: Array = []
## A join or leave that arrived behind game packets still waiting to be read —
## see _poll().
var held_control := ""


## Open a room for `player_count` players. OK means the attempt started: the
## code arrives on `room_ready`, a failure as the connection failing.
func host(url: String, player_count: int) -> Error:
	unique_id = HOST_PEER_ID
	return open(url, {"op": "host", "v": PROTOCOL_VERSION, "players": player_count})


## Join the room with this code. The relay hands out the id once it is in.
func join(url: String, code: String) -> Error:
	unique_id = 0
	return open(url, {"op": "join", "v": PROTOCOL_VERSION, "room": code})


func open(url: String, first_message: Dictionary) -> Error:
	socket.inbound_buffer_size = 256 * 1024
	socket.outbound_buffer_size = 256 * 1024
	var error := socket.connect_to_url(url)
	if error != OK:
		return error

	hello = first_message
	hello_sent = false
	failure_reason = ""
	status = MultiplayerPeer.CONNECTION_CONNECTING
	connect_started_msec = Time.get_ticks_msec()
	return OK


# ── Talking to the relay ──────────────────────────────────────────────────────

func _poll() -> void:
	if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return

	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and not hello_sent:
		socket.send_text(JSON.stringify(hello))
		hello_sent = true

	# SceneMultiplayer only reads packets once this returns, but someone joining
	# or leaving takes effect the moment it is handled. So a control message that
	# arrives behind game packets waits for the next poll, and the packets either
	# side of it are read on the right side of it.
	if not held_control.is_empty():
		var control := held_control
		held_control = ""
		on_control(control)

	while held_control.is_empty() and socket.get_available_packet_count() > 0:
		var packet := socket.get_packet()
		if socket.was_string_packet():
			if incoming.is_empty():
				on_control(packet.get_string_from_utf8())
			else:
				held_control = packet.get_string_from_utf8()
		elif packet.size() >= HEADER_SIZE and status == MultiplayerPeer.CONNECTION_CONNECTED:
			incoming.append([packet.decode_s32(0), packet.decode_u8(4), packet.decode_u8(5), packet.slice(HEADER_SIZE)])

	if state == WebSocketPeer.STATE_CLOSED and held_control.is_empty():
		on_closed()
	elif status == MultiplayerPeer.CONNECTION_CONNECTING \
			and Time.get_ticks_msec() - connect_started_msec > CONNECT_TIMEOUT_MSEC:
		failure_reason = "Could not reach the game server."
		_close()


func on_control(text: String) -> void:
	var message: Variant = JSON.parse_string(text)
	if not message is Dictionary:
		return

	match message.get("op"):
		"welcome":
			unique_id = int(message.get("id", 0))
			room_code = str(message.get("room", ""))
			status = MultiplayerPeer.CONNECTION_CONNECTED
			if unique_id != HOST_PEER_ID:
				peer_connected.emit(HOST_PEER_ID)
			room_ready.emit()
		"peer_joined":
			if unique_id == HOST_PEER_ID:
				peer_connected.emit(int(message.get("id", 0)))
		"peer_left":
			if unique_id == HOST_PEER_ID:
				peer_disconnected.emit(int(message.get("id", 0)))
		"error":
			failure_reason = str(message.get("reason", ""))


## The socket is gone. SceneMultiplayer sees the status drop and reports it as
## the connection failing (still connecting) or the server going away.
func on_closed() -> void:
	if failure_reason.is_empty():
		failure_reason = socket.get_close_reason()
	if failure_reason.is_empty():
		failure_reason = "Lost connection to the game server." \
			if status == MultiplayerPeer.CONNECTION_CONNECTED else "Could not reach the game server."
	status = MultiplayerPeer.CONNECTION_DISCONNECTED
	incoming.clear()


# ── MultiplayerPeer ───────────────────────────────────────────────────────────

func _put_packet_script(payload: PackedByteArray) -> Error:
	if status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	if payload.size() > MAX_PACKET_SIZE:
		return ERR_OUT_OF_MEMORY

	var packet := PackedByteArray()
	packet.resize(HEADER_SIZE)
	packet.encode_s32(0, send_target)
	packet.encode_u8(4, send_channel)
	packet.encode_u8(5, send_mode)
	packet.append_array(payload)
	return socket.send(packet)


func _get_packet_script() -> PackedByteArray:
	if incoming.is_empty():
		return PackedByteArray()
	return incoming.pop_front()[3]


func _get_available_packet_count() -> int:
	return incoming.size()


func _get_packet_peer() -> int:
	return incoming[0][0] if not incoming.is_empty() else 0


func _get_packet_channel() -> int:
	return incoming[0][1] if not incoming.is_empty() else 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	var mode: int = incoming[0][2] if not incoming.is_empty() else MultiplayerPeer.TRANSFER_MODE_RELIABLE
	return mode as MultiplayerPeer.TransferMode


func _get_max_packet_size() -> int:
	return MAX_PACKET_SIZE


func _set_target_peer(peer: int) -> void:
	send_target = peer


func _set_transfer_channel(channel: int) -> void:
	send_channel = channel


func _get_transfer_channel() -> int:
	return send_channel


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	send_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return send_mode


func _get_unique_id() -> int:
	return unique_id


func _is_server() -> bool:
	return unique_id == HOST_PEER_ID


## True, so SceneMultiplayer passes joiner-to-joiner messages through the host
## the way it does over ENet; the relay itself only ever connects each joiner to
## the host.
func _is_server_relay_supported() -> bool:
	return true


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return status


func _set_refuse_new_connections(enable: bool) -> void:
	refusing_new_connections = enable


func _is_refusing_new_connections() -> bool:
	return refusing_new_connections


## The host asks the relay to drop a player; the relay reports them gone with
## peer_left, as it would if they had left on their own.
func _disconnect_peer(peer: int, _force: bool) -> void:
	if unique_id == HOST_PEER_ID and peer != HOST_PEER_ID:
		socket.send_text(JSON.stringify({"op": "kick", "id": peer}))
	elif peer == HOST_PEER_ID:
		_close()


func _close() -> void:
	socket.close()
	status = MultiplayerPeer.CONNECTION_DISCONNECTED
	incoming.clear()
	held_control = ""
