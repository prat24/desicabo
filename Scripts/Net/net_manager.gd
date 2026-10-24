## Net — multiplayer plumbing, autoloaded as `Net`. One device hosts the game
## and the others join it; the host keeps its authority for the whole match
## (see GameManager, which drives every device from the host's copy of the
## game). Seats are handed out in join order and the host is always Player 1,
## so a two-player game is host = Player 1, joiner = Player 2.
##
## There are two ways to connect, and nothing above this file can tell them
## apart:
##
## - The phone app plays over ENet on the local network. Peers find each other
##   with a UDP broadcast, so joining is a tap on a game that was found rather
##   than typing an IP address on a phone keyboard.
## - The web build cannot: browsers have no UDP. It plays through the relay on
##   the server the page came from (see RelayPeer), and players find each other
##   by a room code the relay hands the host.
extends Node

## ENet port the host listens on for players.
const GAME_PORT := 8654
## Separate UDP port the host answers "who is hosting?" probes on.
const DISCOVERY_PORT := 8655
const DISCOVERY_QUERY := "DESICABO?"
const DISCOVERY_REPLY := "DESICABO!"
## How often a joining phone re-probes the network while the join list is open.
const PROBE_INTERVAL := 0.8
## A game that has not answered for this long has gone away, so it drops off
## the list rather than sitting there un-joinable.
const HOST_TIMEOUT := 3.0
## Four players at most, so the host plus three joiners.
const MAX_CLIENTS := 3
## Where the relay sits, beside the page the web build was loaded from.
const RELAY_PATH := "ws"

## The lobby changed: someone joined, left, or seats were handed out.
signal lobby_changed
## Everyone is here — each device should now load the game scene.
signal game_starting
## The list of games found on the network changed.
signal hosts_changed
## Could not get into a game, with a line to show the player.
signal join_failed(reason: String)
## An underway match cannot continue: the host quit, or a player dropped.
signal connection_lost(reason: String)

## False for hotseat games, which never touch any of this.
var is_online := false
var is_hosting := false
## True from the moment the table is full; joiners are turned away after it.
var game_running := false
## This device's player number, 1..player_count. 0 until the host assigns one.
var local_player := 0
var expected_players := 2
## peer id -> player number. The host is peer 1 and always Player 1.
var seats: Dictionary = {}
## seat -> the name that player chose, as the host has it (see display_name()).
var player_names: Dictionary = {}
## Host only: peer id -> name, as each player introduced themselves. Kept by
## peer rather than seat so a name that arrives before its seat is not lost.
var peer_names: Dictionary = {}
## Games found on the network: ip -> {"joined": int, "expected": int, "seen": float}.
var found_hosts: Dictionary = {}
## Web build only: the connection to the relay, and the code it gave this
## game — empty until the relay has answered, and always empty on a LAN.
var relay: RelayPeer
var room_code := ""

## Bound on the host while it waits for players, so probes get an answer.
var announce_socket: PacketPeerUDP
## Bound on a joining device while the join list is open.
var probe_socket: PacketPeerUDP
var probe_timer := 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(on_peer_connected)
	multiplayer.peer_disconnected.connect(on_peer_disconnected)
	multiplayer.connected_to_server.connect(on_connected_to_server)
	multiplayer.connection_failed.connect(on_connection_failed)
	multiplayer.server_disconnected.connect(on_server_disconnected)


func _process(delta: float) -> void:
	poll_announcements()
	poll_probes(delta)


# ── Starting and joining a game ───────────────────────────────────────────────

## Open this device up as the host. Returns "" on success, or a line to show
## the player when the port could not be opened.
func host_game(player_count: int) -> String:
	leave()
	expected_players = clampi(player_count, 2, 4)

	if uses_relay():
		relay = new_relay()
		if relay.host(relay_url(), expected_players) != OK:
			relay = null
			return "Could not reach the game server."
		multiplayer.multiplayer_peer = relay
	else:
		var peer := ENetMultiplayerPeer.new()
		if peer.create_server(GAME_PORT, MAX_CLIENTS) != OK:
			return "Could not open a game on this device."
		multiplayer.multiplayer_peer = peer

	is_online = true
	is_hosting = true
	local_player = 1
	seats = {1: 1}
	peer_names = {1: GameSettings.clean_name(GameSettings.player_name)}
	share_names()
	start_announcing()
	lobby_changed.emit()
	return ""


## Connect to a host found on the network (or typed in by hand) — or, in the
## web build, to the game with this room code. Returns "" if the attempt
## started — failure arrives later on `join_failed`.
func join_game(address: String) -> String:
	leave()

	if uses_relay():
		relay = new_relay()
		if relay.join(relay_url(), address.strip_edges().to_upper()) != OK:
			relay = null
			return "Could not reach the game server."
		multiplayer.multiplayer_peer = relay
	else:
		var peer := ENetMultiplayerPeer.new()
		if peer.create_client(address, GAME_PORT) != OK:
			return "Could not reach %s." % address
		multiplayer.multiplayer_peer = peer

	is_online = true
	is_hosting = false
	local_player = 0
	return ""


## Drop the connection and forget the lobby. Safe to call when offline, and the
## main menu does exactly that on the way in, so a finished or abandoned game
## never leaves a peer behind.
func leave() -> void:
	stop_announcing()
	stop_probing()

	var peer := multiplayer.multiplayer_peer
	if peer != null and not (peer is OfflineMultiplayerPeer):
		peer.close()
	multiplayer.multiplayer_peer = null

	is_online = false
	is_hosting = false
	game_running = false
	local_player = 0
	seats.clear()
	player_names.clear()
	peer_names.clear()
	relay = null
	room_code = ""


## The player number sitting at `peer_id`, or 0 for a peer with no seat.
func seat_of(peer_id: int) -> int:
	return int(seats.get(peer_id, 0))


## Every connected peer except this device, as {peer_id: seat}.
func remote_seats() -> Dictionary:
	var others: Dictionary = {}
	var own_id: int = multiplayer.get_unique_id() if is_online else 0
	for peer_id: int in seats:
		if peer_id != own_id:
			others[peer_id] = int(seats[peer_id])
	return others


func joined_count() -> int:
	return seats.size()


## What to call the player in `seat`: the name they chose, or "Player N" when
## they have not set one (and in any game that is not online).
func display_name(seat: int) -> String:
	var chosen := str(player_names.get(seat, ""))
	return chosen if not chosen.is_empty() else "Player %d" % seat


## Everyone seated so far, by name, in seat order.
func table_text() -> String:
	var names: Array[String] = []
	for seat in range(1, expected_players + 1):
		if seats.values().has(seat):
			names.append(display_name(seat))
	return ", ".join(names)


# ── Playing through the relay (web build) ─────────────────────────────────────

## Browsers cannot open the UDP sockets ENet and the network search use, so the
## web build always goes through the relay.
func uses_relay() -> bool:
	return OS.has_feature("web")


## The relay sits beside the page on the server it came from, so its address is
## the page's own: https://cabo.example/ → wss://cabo.example/ws, or, for a game
## served under a path next to other apps, https://games.example/cabo/ →
## wss://games.example/cabo/ws. A page served over HTTPS gets an encrypted
## connection to match.
func relay_url() -> String:
	var location: JavaScriptObject = JavaScriptBridge.get_interface("location")
	if location == null:
		return ""
	var origin := str(location.get("origin"))
	var path := str(location.get("pathname"))
	var directory := path.substr(0, path.rfind("/") + 1)
	var scheme := "wss://" if origin.begins_with("https://") else "ws://"
	return scheme + origin.get_slice("://", 1) + directory + RELAY_PATH


func new_relay() -> RelayPeer:
	var peer := RelayPeer.new()
	peer.room_ready.connect(on_room_ready)
	return peer


func on_room_ready() -> void:
	if relay:
		room_code = relay.room_code
		lobby_changed.emit()


## The relay's own words for what went wrong ("No game with that code.") when
## it gave any, since they tell the player more than a generic line could.
func relay_failure_or(fallback: String) -> String:
	if relay and not relay.failure_reason.is_empty():
		return relay.failure_reason
	return fallback


# ── Lobby ─────────────────────────────────────────────────────────────────────

func on_peer_connected(peer_id: int) -> void:
	if not is_hosting:
		return

	if game_running or seats.size() >= expected_players:
		rpc_id(peer_id, "net_turned_away", "That game is already full.")
		# Graceful, so the message above is flushed before the socket closes.
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return

	seats[peer_id] = next_free_seat()
	share_names()
	rpc("net_lobby_state", seats, expected_players, player_names)
	lobby_changed.emit()
	start_game_if_ready()


func on_peer_disconnected(peer_id: int) -> void:
	if not is_hosting:
		return
	peer_names.erase(peer_id)

	# Someone turned away at the door never had a seat, so their going changes
	# nothing — above all, it must not end a game that is already underway.
	if not seats.has(peer_id):
		return

	seats.erase(peer_id)
	if game_running:
		connection_lost.emit("A player left the game.")
		return

	share_names()
	rpc("net_lobby_state", seats, expected_players, player_names)
	lobby_changed.emit()


## Say who we are; the seat arrives from the host in net_lobby_state.
func on_connected_to_server() -> void:
	rpc_id(1, "net_introduce", GameSettings.player_name)


## A joiner's name, sent the moment it connects. Names come from other people's
## devices, so the host cleans each one before anyone sees it.
@rpc("any_peer", "call_remote", "reliable")
func net_introduce(raw_name: String) -> void:
	if not is_hosting or game_running:
		return

	peer_names[multiplayer.get_remote_sender_id()] = GameSettings.clean_name(raw_name)
	share_names()
	rpc("net_lobby_state", seats, expected_players, player_names)
	lobby_changed.emit()
	start_game_if_ready()


## Host side: rebuild the seat -> name table from who is seated and who has
## introduced themselves.
func share_names() -> void:
	player_names = {}
	for peer_id: int in seats:
		if peer_names.has(peer_id):
			player_names[int(seats[peer_id])] = peer_names[peer_id]


## The table is full and everyone at it has said who they are, so nobody's
## first turn shows them as "Player N".
func start_game_if_ready() -> void:
	if not game_running and seats.size() == expected_players and player_names.size() == expected_players:
		start_game()


func on_connection_failed() -> void:
	var reason := relay_failure_or("Could not join that game.")
	leave()
	join_failed.emit(reason)


func on_server_disconnected() -> void:
	var was_playing := game_running
	# The host has a server to lose only when it plays through the relay.
	var lost_relay := is_hosting
	leave()
	if lost_relay and was_playing:
		connection_lost.emit("Lost connection to the game server.")
	elif lost_relay:
		join_failed.emit("Lost connection to the game server.")
	elif was_playing:
		connection_lost.emit("The host left the game.")
	else:
		join_failed.emit("The host closed the game.")


## Lowest player number nobody holds — joiners fill in behind the host.
func next_free_seat() -> int:
	for seat in range(1, expected_players + 1):
		if not seats.values().has(seat):
			return seat
	return expected_players


@rpc("authority", "call_remote", "reliable")
func net_lobby_state(host_seats: Dictionary, host_expected: int, host_names: Dictionary) -> void:
	seats = host_seats
	expected_players = host_expected
	player_names = host_names
	local_player = seat_of(multiplayer.get_unique_id())
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func net_turned_away(reason: String) -> void:
	leave()
	join_failed.emit(reason)


func start_game() -> void:
	stop_announcing()
	rpc("net_start_game")


@rpc("authority", "call_local", "reliable")
func net_start_game() -> void:
	game_running = true
	GameConfig.player_count = expected_players
	game_starting.emit()


# ── Finding games on the network ──────────────────────────────────────────────

## Answer probes while the table is filling up. A device that cannot bind the
## port (another game already open on it) still hosts fine — joiners just have
## to type its address instead of tapping a found game.
func start_announcing() -> void:
	stop_announcing()
	if uses_relay():
		return
	var socket := PacketPeerUDP.new()
	if socket.bind(DISCOVERY_PORT) == OK:
		announce_socket = socket


func stop_announcing() -> void:
	if announce_socket:
		announce_socket.close()
		announce_socket = null


func poll_announcements() -> void:
	if announce_socket == null:
		return

	while announce_socket.get_available_packet_count() > 0:
		var message := announce_socket.get_packet().get_string_from_utf8()
		var from_ip := announce_socket.get_packet_ip()
		var from_port := announce_socket.get_packet_port()
		if message != DISCOVERY_QUERY or from_ip.is_empty():
			continue
		announce_socket.set_dest_address(from_ip, from_port)
		var reply := "%s|%d|%d" % [DISCOVERY_REPLY, seats.size(), expected_players]
		announce_socket.put_packet(reply.to_utf8_buffer())


## Start looking for games. The list arrives over `hosts_changed`.
func start_probing() -> void:
	stop_probing()
	found_hosts.clear()
	if uses_relay():
		return

	var socket := PacketPeerUDP.new()
	if socket.bind(0) != OK:
		# Some platforms refuse an ephemeral bind; take any free high port.
		var bound := false
		for attempt in range(20):
			if socket.bind(randi_range(49200, 49900)) == OK:
				bound = true
				break
		if not bound:
			return

	socket.set_broadcast_enabled(true)
	probe_socket = socket
	# Probe on the next frame rather than after a full interval.
	probe_timer = PROBE_INTERVAL
	hosts_changed.emit()


func stop_probing() -> void:
	if probe_socket:
		probe_socket.close()
		probe_socket = null


func poll_probes(delta: float) -> void:
	if probe_socket == null:
		return

	probe_timer += delta
	if probe_timer >= PROBE_INTERVAL:
		probe_timer = 0.0
		send_probes()

	var changed := false
	while probe_socket.get_available_packet_count() > 0:
		var parts := probe_socket.get_packet().get_string_from_utf8().split("|")
		var from_ip := probe_socket.get_packet_ip()
		if parts.size() != 3 or parts[0] != DISCOVERY_REPLY or from_ip.is_empty():
			continue
		var known: bool = found_hosts.has(from_ip)
		var entry := {
			"joined": int(parts[1]),
			"expected": int(parts[2]),
			"seen": current_time(),
		}
		changed = changed or not known or found_hosts[from_ip]["joined"] != entry["joined"]
		found_hosts[from_ip] = entry

	if expire_stale_hosts() or changed:
		hosts_changed.emit()


## Ask every address a host could be listening on. The subnet broadcast is
## worked out from this device's own addresses, since some networks drop
## packets aimed at 255.255.255.255, and the loopback covers two copies of the
## game running on one computer.
func send_probes() -> void:
	var query := DISCOVERY_QUERY.to_utf8_buffer()
	for address in probe_addresses():
		probe_socket.set_dest_address(address, DISCOVERY_PORT)
		probe_socket.put_packet(query)


func probe_addresses() -> Array[String]:
	var addresses: Array[String] = ["255.255.255.255", "127.0.0.1"]
	for local_address in IP.get_local_addresses():
		var parts := local_address.split(".")
		if parts.size() != 4 or local_address.begins_with("127."):
			continue
		var subnet_broadcast := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
		if not addresses.has(subnet_broadcast):
			addresses.append(subnet_broadcast)
	return addresses


func expire_stale_hosts() -> bool:
	var now := current_time()
	var dropped := false
	for ip: String in found_hosts.keys():
		if now - float(found_hosts[ip]["seen"]) > HOST_TIMEOUT:
			found_hosts.erase(ip)
			dropped = true
	return dropped


func current_time() -> float:
	return Time.get_ticks_msec() / 1000.0
