#!/usr/bin/env python3
"""Desi Cabo relay — lets the web build play online games through a server.

Browsers cannot open raw UDP sockets, so the web build cannot use the ENet
connection the phones use on a LAN. Instead every player opens one WebSocket to
this relay, and the relay passes packets between the host and the others in a
room. It never looks inside a game packet: the host's device still runs the
game and checks every move, exactly as it does over ENet.

A room is a star. The host is peer 1 and each joiner can only reach the host;
Godot's multiplayer layer already relays joiner-to-joiner messages through the
host (as it does over ENet), so nothing here has to.

Protocol, version 1. Text frames carry JSON control messages, binary frames
carry game packets.

    joiner/host -> relay   {"op": "host", "v": 1, "players": 2..4}
                           {"op": "join", "v": 1, "room": "ABCDE"}
    relay -> joiner/host   {"op": "welcome", "id": <peer id>, "room": "ABCDE"}
                           {"op": "error", "reason": "..."}   (then it closes)
    relay -> host          {"op": "peer_joined", "id": N}
                           {"op": "peer_left", "id": N}
    host -> relay          {"op": "kick", "id": N}

    binary, sent:      int32 LE target | u8 channel | u8 mode | payload
    binary, received:  int32 LE source | u8 channel | u8 mode | payload

A joiner's target is ignored — everything a joiner sends goes to the host.

Configuration comes from the environment (see relay.env.example):
    DESICABO_ALLOWED_ORIGINS  required; the site's origin, e.g. https://cabo.example.com
    DESICABO_RELAY_HOST       default 127.0.0.1 — keep it on loopback behind the web server
    DESICABO_RELAY_PORT       default 8765
"""

from __future__ import annotations

import asyncio
import collections
import json
import logging
import os
import secrets
import signal
import struct
import sys
import time

import websockets
from websockets.exceptions import ConnectionClosed

PROTOCOL_VERSION = 1
HOST_PEER_ID = 1
MIN_PLAYERS = 2
MAX_PLAYERS = 4

# Five characters with the look-alikes (0/O, 1/I) left out: about 33 million
# codes, and nothing a player has to squint at.
ROOM_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
ROOM_CODE_LENGTH = 5

# Game packets are a few hundred bytes; anything near this is not the game.
MAX_MESSAGE_BYTES = 64 * 1024
PACKET_HEADER = struct.Struct("<iBB")

# ── Limits. Sized for a few tables of friends on a small server. ──────────────
MAX_CONNECTIONS = 64
MAX_CONNECTIONS_PER_IP = 16
MAX_ROOMS = 16
MAX_ROOMS_PER_IP = 2
# A wrong room code costs one of these; it is what makes guessing codes useless.
FAILED_JOINS_PER_MINUTE = 10
# Seconds a new connection gets to say whether it is hosting or joining.
HELLO_TIMEOUT = 10.0
# A player whose connection stops taking packets for this long is dropped,
# rather than holding up everyone else in the room.
SEND_TIMEOUT = 10.0
# Per connection. Dealing and dragging come nowhere near these.
MESSAGE_RATE, MESSAGE_BURST = 100.0, 400.0
BYTE_RATE, BYTE_BURST = 256.0 * 1024, 1024.0 * 1024

# Proxies on this machine (the web server, a TLS proxy). Forwarded-for entries they
# added are trusted; anything further left is whatever the client claimed.
TRUSTED_PROXIES = {"127.0.0.1", "::1"}

CLOSE_NORMAL = 1000
CLOSE_POLICY = 1008
CLOSE_HOST_LEFT = 4000
CLOSE_KICKED = 4001

log = logging.getLogger("desicabo.relay")


class Budget:
    """Token bucket: refills at `rate` per second and holds at most `burst`."""

    def __init__(self, rate: float, burst: float) -> None:
        self.rate = rate
        self.burst = burst
        self.tokens = burst
        self.stamp = time.monotonic()

    def spend(self, amount: float) -> bool:
        now = time.monotonic()
        self.tokens = min(self.burst, self.tokens + (now - self.stamp) * self.rate)
        self.stamp = now
        if amount > self.tokens:
            return False
        self.tokens -= amount
        return True


class Member:
    def __init__(self, ws, ip: str, peer_id: int) -> None:
        self.ws = ws
        self.ip = ip
        self.peer_id = peer_id
        self.messages = Budget(MESSAGE_RATE, MESSAGE_BURST)
        self.bytes = Budget(BYTE_RATE, BYTE_BURST)


class Room:
    def __init__(self, code: str, players: int, host: Member) -> None:
        self.code = code
        self.players = players
        self.host = host
        self.members: dict[int, Member] = {HOST_PEER_ID: host}
        self.next_peer_id = HOST_PEER_ID + 1
        self.open = True

    def is_full(self) -> bool:
        return len(self.members) >= self.players

    def add(self, ws, ip: str) -> Member:
        member = Member(ws, ip, self.next_peer_id)
        self.next_peer_id += 1
        self.members[member.peer_id] = member
        return member


class RelayError(Exception):
    """Ends a connection before it is in a room, with a line for the player."""


class Relay:
    def __init__(self) -> None:
        self.rooms: dict[str, Room] = {}
        self.connections = 0
        self.connections_by_ip: collections.Counter[str] = collections.Counter()
        self.failed_joins: dict[str, collections.deque[float]] = {}
        # Closes run in the background so one slow socket never stalls a room;
        # asyncio only keeps weak references to tasks, so they are held here.
        self.background: set[asyncio.Task] = set()

    # ── Connections ───────────────────────────────────────────────────────────

    async def handle(self, ws) -> None:
        ip = client_ip(ws)
        if self.connections >= MAX_CONNECTIONS or self.connections_by_ip[ip] >= MAX_CONNECTIONS_PER_IP:
            await refuse(ws, "The server is busy. Try again in a minute.")
            return

        self.connections += 1
        self.connections_by_ip[ip] += 1
        try:
            await self.serve(ws, ip)
        except ConnectionClosed:
            pass
        finally:
            self.connections -= 1
            self.connections_by_ip[ip] -= 1
            if self.connections_by_ip[ip] <= 0:
                del self.connections_by_ip[ip]

    async def serve(self, ws, ip: str) -> None:
        try:
            hello = await self.read_hello(ws)
            if hello["op"] == "host":
                room, member = self.open_room(ws, ip, hello)
            else:
                room, member = self.join_room(ws, ip, hello)
        except RelayError as error:
            await refuse(ws, str(error))
            return

        try:
            await ws.send(json.dumps({"op": "welcome", "id": member.peer_id, "room": room.code}))
            if member is not room.host:
                await self.deliver(room.host, json.dumps({"op": "peer_joined", "id": member.peer_id}))
            await self.relay_messages(room, member)
        finally:
            self.leave(room, member)

    async def read_hello(self, ws) -> dict:
        try:
            raw = await asyncio.wait_for(ws.recv(), HELLO_TIMEOUT)
        except asyncio.TimeoutError:
            raise RelayError("Timed out. Reload the page and try again.") from None
        try:
            hello = json.loads(raw) if isinstance(raw, str) else None
        except ValueError:
            hello = None
        if not isinstance(hello, dict) or hello.get("op") not in ("host", "join"):
            raise RelayError("Bad request.")
        if hello.get("v") != PROTOCOL_VERSION:
            raise RelayError("This page is out of date. Reload it and try again.")
        return hello

    # ── Rooms ─────────────────────────────────────────────────────────────────

    def open_room(self, ws, ip: str, hello: dict) -> tuple[Room, Member]:
        players = hello.get("players")
        if type(players) is not int or not MIN_PLAYERS <= players <= MAX_PLAYERS:
            raise RelayError("Bad request.")
        hosted_here = sum(1 for room in self.rooms.values() if room.host.ip == ip)
        if len(self.rooms) >= MAX_ROOMS or hosted_here >= MAX_ROOMS_PER_IP:
            raise RelayError("The server is busy. Try again in a minute.")

        code = new_room_code()
        while code in self.rooms:
            code = new_room_code()
        room = Room(code, players, Member(ws, ip, HOST_PEER_ID))
        self.rooms[code] = room
        log.info("room %s opened for %d players (%d open)", code, players, len(self.rooms))
        return room, room.host

    def join_room(self, ws, ip: str, hello: dict) -> tuple[Room, Member]:
        if not self.may_try_joining(ip):
            raise RelayError("Too many wrong codes. Wait a minute and try again.")

        code = hello.get("room")
        room = self.rooms.get(code.strip().upper()) if isinstance(code, str) else None
        if room is None:
            self.record_failed_join(ip)
            raise RelayError("No game with that code.")
        if room.is_full():
            raise RelayError("That game is already full.")

        member = room.add(ws, ip)
        log.info("room %s: peer %d joined (%d/%d)", room.code, member.peer_id, len(room.members), room.players)
        return room, member

    def leave(self, room: Room, member: Member) -> None:
        if room.members.get(member.peer_id) is not member:
            return
        del room.members[member.peer_id]

        if member is room.host:
            room.open = False
            self.rooms.pop(room.code, None)
            for other in list(room.members.values()):
                self.close_later(other, CLOSE_HOST_LEFT, "The host left the game.")
            room.members.clear()
            log.info("room %s closed (%d open)", room.code, len(self.rooms))
        elif room.open:
            self.send_later(room.host, json.dumps({"op": "peer_left", "id": member.peer_id}))
            log.info("room %s: peer %d left", room.code, member.peer_id)

    def may_try_joining(self, ip: str) -> bool:
        attempts = self.failed_joins.get(ip)
        if attempts is None:
            return True
        cutoff = time.monotonic() - 60.0
        while attempts and attempts[0] < cutoff:
            attempts.popleft()
        if not attempts:
            del self.failed_joins[ip]
            return True
        return len(attempts) < FAILED_JOINS_PER_MINUTE

    def record_failed_join(self, ip: str) -> None:
        # Bounded, so a flood of addresses cannot grow this without limit.
        if ip not in self.failed_joins and len(self.failed_joins) >= 10_000:
            self.failed_joins.clear()
        attempts = self.failed_joins.setdefault(ip, collections.deque(maxlen=FAILED_JOINS_PER_MINUTE))
        attempts.append(time.monotonic())

    # ── Traffic ───────────────────────────────────────────────────────────────

    async def relay_messages(self, room: Room, member: Member) -> None:
        async for message in member.ws:
            if not (member.messages.spend(1) and member.bytes.spend(len(message))):
                log.warning("room %s: peer %d sent too much, dropping it", room.code, member.peer_id)
                await member.ws.close(CLOSE_POLICY, "Too much traffic.")
                return
            if isinstance(message, str):
                if not self.on_control(room, member, message):
                    await member.ws.close(CLOSE_POLICY, "Bad request.")
                    return
            else:
                await self.on_packet(room, member, message)

    def on_control(self, room: Room, member: Member, message: str) -> bool:
        """Only the host has anything to say once a room is open: who to drop."""
        try:
            control = json.loads(message)
        except ValueError:
            return False
        if member is not room.host or not isinstance(control, dict) or control.get("op") != "kick":
            return False

        target = room.members.get(control.get("id")) if type(control.get("id")) is int else None
        if target is not None and target is not room.host:
            self.close_later(target, CLOSE_KICKED, "Removed from the game by the host.")
        return True

    async def on_packet(self, room: Room, member: Member, packet: bytes) -> None:
        if len(packet) < PACKET_HEADER.size:
            return
        target, channel, mode = PACKET_HEADER.unpack_from(packet)
        if member is room.host:
            recipient = room.members.get(target) if target != HOST_PEER_ID else None
        else:
            recipient = room.host
        if recipient is None:
            # Somebody who just left; Godot hears about it from peer_left.
            return

        forwarded = bytearray(packet)
        PACKET_HEADER.pack_into(forwarded, 0, member.peer_id, channel, mode)
        await self.deliver(recipient, bytes(forwarded))

    async def deliver(self, recipient: Member, data) -> None:
        try:
            await asyncio.wait_for(recipient.ws.send(data), SEND_TIMEOUT)
        except ConnectionClosed:
            pass
        except asyncio.TimeoutError:
            log.warning("peer %d stopped reading, dropping it", recipient.peer_id)
            self.close_later(recipient, CLOSE_POLICY, "Connection too slow.")

    def send_later(self, recipient: Member, data) -> None:
        self.run_in_background(self.deliver(recipient, data))

    def close_later(self, member: Member, code: int, reason: str) -> None:
        self.run_in_background(member.ws.close(code, reason))

    def run_in_background(self, coroutine) -> None:
        task = asyncio.ensure_future(coroutine)
        self.background.add(task)
        task.add_done_callback(self.background.discard)


# ── Helpers ───────────────────────────────────────────────────────────────────

def new_room_code() -> str:
    return "".join(secrets.choice(ROOM_CODE_ALPHABET) for _ in range(ROOM_CODE_LENGTH))


async def refuse(ws, reason: str) -> None:
    """Tell the player why, then hang up. The reason rides in the close frame
    too, in case the browser drops the message on its way to closing."""
    try:
        await ws.send(json.dumps({"op": "error", "reason": reason}))
        await ws.close(CLOSE_NORMAL, reason)
    except ConnectionClosed:
        pass


def request_headers(ws):
    # websockets 13+ keeps the handshake on `request`; older releases (the one
    # Debian 12 ships) on `request_headers`.
    request = getattr(ws, "request", None)
    return request.headers if request is not None else ws.request_headers


def client_ip(ws) -> str:
    """The player's address. The proxies in front of the relay each append the
    address they saw to X-Forwarded-For, so the chain is read right to left and
    the first hop that is not one of them is the player."""
    peer = ws.remote_address[0] if ws.remote_address else "unknown"
    chain = []
    for header in request_headers(ws).get_all("X-Forwarded-For"):
        chain.extend(hop.strip() for hop in header.split(","))
    chain.append(peer)
    for hop in reversed(chain):
        if hop and hop not in TRUSTED_PROXIES:
            return hop
    return peer


async def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    # websockets notes every connection opening and closing, which the room log
    # already covers. Its refusals stay: "connection rejected (403 Forbidden)"
    # means a page whose origin is not in DESICABO_ALLOWED_ORIGINS tried to
    # connect — usually a typo in that setting.
    logging.getLogger("websockets.server").addFilter(
        lambda record: record.getMessage() not in ("connection open", "connection closed")
    )

    origins = [origin.strip() for origin in os.environ.get("DESICABO_ALLOWED_ORIGINS", "").split(",") if origin.strip()]
    if not origins:
        log.error("DESICABO_ALLOWED_ORIGINS is not set: give it the site's origin, e.g. https://cabo.example.com")
        sys.exit(1)
    host = os.environ.get("DESICABO_RELAY_HOST", "127.0.0.1")
    port = int(os.environ.get("DESICABO_RELAY_PORT", "8765"))

    loop = asyncio.get_running_loop()
    stop = loop.create_future()
    for signum in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(signum, lambda: stop.done() or stop.set_result(None))

    relay = Relay()
    async with websockets.serve(
        relay.handle,
        host,
        port,
        # Only pages served from our own site may open a connection, so no other
        # website a player has open can reach the relay through their browser.
        origins=origins,
        max_size=MAX_MESSAGE_BYTES,
        max_queue=32,
        compression=None,
        ping_interval=20,
        ping_timeout=20,
        close_timeout=5,
    ):
        log.info("relay listening on %s:%d for %s", host, port, ", ".join(origins))
        await stop
    log.info("relay stopped")


if __name__ == "__main__":
    asyncio.run(main())
