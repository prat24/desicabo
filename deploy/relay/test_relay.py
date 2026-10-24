#!/usr/bin/env python3
"""End-to-end tests for relay.py: starts a real relay on a spare port and talks
to it the way the game does. Needs the `websockets` package.

    python3 deploy/relay/test_relay.py
"""

import asyncio
import json
import os
import pathlib
import struct
import subprocess
import sys
import time

import websockets
from websockets.exceptions import ConnectionClosed

RELAY = pathlib.Path(__file__).with_name("relay.py")
PORT = 18765
URL = f"ws://127.0.0.1:{PORT}/ws"
ORIGIN = "http://localhost:8080"
HEADER = struct.Struct("<iBB")

failures = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"  [{detail}]"))
    if not ok:
        failures.append(name)


async def connect(origin=ORIGIN, forwarded_for=None):
    if forwarded_for is None:
        return await websockets.connect(URL, origin=origin)
    headers = {"X-Forwarded-For": forwarded_for}
    try:
        return await websockets.connect(URL, origin=origin, additional_headers=headers)
    except TypeError:  # websockets < 14
        return await websockets.connect(URL, origin=origin, extra_headers=headers)


async def hello(ws, **message):
    await ws.send(json.dumps({"v": 1, **message}))
    return json.loads(await asyncio.wait_for(ws.recv(), 3))


async def next_json(ws):
    return json.loads(await asyncio.wait_for(ws.recv(), 3))


async def close_of(ws):
    """Wait for the relay to hang up; returns (code, reason)."""
    try:
        while True:
            await asyncio.wait_for(ws.recv(), 10)
    except ConnectionClosed as closed:
        received = getattr(closed, "rcvd", None)
        if received is not None:
            return received.code, received.reason
        return getattr(closed, "code", None), getattr(closed, "reason", "")


async def run():
    # ── A room: host, joiners, routing ────────────────────────────────────────
    host = await connect()
    welcome = await hello(host, op="host", players=3)
    check("host gets id 1 and a code", welcome["op"] == "welcome" and welcome["id"] == 1 and len(welcome["room"]) == 5, welcome)
    code = welcome["room"]

    a = await connect()
    joined = await hello(a, op="join", room=code.lower())
    check("join works with a lowercase code", joined == {"op": "welcome", "id": 2, "room": code}, joined)
    check("host told who joined", await next_json(host) == {"op": "peer_joined", "id": 2})

    await host.send(HEADER.pack(2, 0, 2) + b"to-a")
    check("host -> joiner, stamped from 1", await a.recv() == HEADER.pack(1, 0, 2) + b"to-a")
    await a.send(HEADER.pack(99, 1, 0) + b"to-host")
    check("joiner -> host whatever the target, stamped from 2", await host.recv() == HEADER.pack(2, 1, 0) + b"to-host")

    b = await connect()
    check("second joiner gets id 3", (await hello(b, op="join", room=code))["id"] == 3)
    await next_json(host)

    await a.send(HEADER.pack(3, 0, 2) + b"sneaky")
    check("joiner cannot reach another joiner directly", (await host.recv())[:4] == struct.pack("<i", 2))
    try:
        await asyncio.wait_for(b.recv(), 0.5)
        check("...and the other joiner hears nothing", False)
    except asyncio.TimeoutError:
        check("...and the other joiner hears nothing", True)

    full = await connect()
    refused = await hello(full, op="join", room=code)
    check("full room refused", refused == {"op": "error", "reason": "That game is already full."}, refused)
    check("refusal reason also in the close frame", (await close_of(full))[1] == "That game is already full.")

    # ── Leaving ───────────────────────────────────────────────────────────────
    await host.send(json.dumps({"op": "kick", "id": 3}))
    check("kicked joiner closed with 4001", (await close_of(b))[0] == 4001)
    check("host told the kicked joiner left", await next_json(host) == {"op": "peer_left", "id": 3})

    await a.send(json.dumps({"op": "kick", "id": 1}))
    check("joiner sending control is closed 1008", (await close_of(a))[0] == 1008)
    check("host told that joiner left", await next_json(host) == {"op": "peer_left", "id": 2})

    d = await connect()
    await hello(d, op="join", room=code)
    await next_json(host)
    await host.close()
    check("host leaving closes the room", await close_of(d) == (4000, "The host left the game."))
    gone = await hello(await connect(), op="join", room=code)
    check("closed room's code is dead", gone.get("reason") == "No game with that code.", gone)

    # ── Bad requests ──────────────────────────────────────────────────────────
    try:
        await connect(origin="https://evil.example")
        check("other websites' pages refused", False)
    except Exception as error:
        check("other websites' pages refused", "403" in str(error), error)

    stale = await connect()
    await stale.send(json.dumps({"op": "host", "v": 0, "players": 2}))
    check("old protocol refused", "out of date" in (await next_json(stale))["reason"])
    for bad in [{"op": "host", "players": 5}, {"op": "host", "players": True}, {"op": "nope"}]:
        answer = await hello(await connect(), **bad)
        check(f"refused {bad}", answer == {"op": "error", "reason": "Bad request."}, answer)
    binary = await connect()
    await binary.send(b"\x00\x01binary")
    check("binary hello refused", (await next_json(binary))["reason"] == "Bad request.")

    # ── Limits ────────────────────────────────────────────────────────────────
    for _ in range(10):
        await hello(await connect(forwarded_for="203.0.113.7"), op="join", room="ZZZZZ")
    limited = await hello(await connect(forwarded_for="203.0.113.7"), op="join", room="ZZZZZ")
    check("too many wrong codes from one address", "Too many" in limited["reason"], limited)
    other = await hello(await connect(forwarded_for="203.0.113.8"), op="join", room="ZZZZZ")
    check("other addresses unaffected", other["reason"] == "No game with that code.", other)
    spoofed = await hello(await connect(forwarded_for="203.0.113.7, 198.51.100.9"), op="join", room="ZZZZZ")
    check("a forged X-Forwarded-For prefix is ignored", spoofed["reason"] == "No game with that code.", spoofed)

    await hello(await connect(forwarded_for="192.0.2.1"), op="host", players=2)
    await hello(await connect(forwarded_for="192.0.2.1"), op="host", players=2)
    third = await hello(await connect(forwarded_for="192.0.2.1"), op="host", players=2)
    check("third room from one address refused", "busy" in third.get("reason", ""), third)

    big = await connect()
    await hello(big, op="host", players=2)
    await big.send(b"\x00" * (70 * 1024))
    check("oversized message closed 1009", (await close_of(big))[0] == 1009)

    flood = await connect()
    await hello(flood, op="host", players=2)
    for _ in range(500):
        try:
            await flood.send(HEADER.pack(2, 0, 2) + b"x")
        except ConnectionClosed:
            break
    check("message flood closed 1008", await close_of(flood) == (1008, "Too much traffic."))

    silent = await connect()
    started = time.monotonic()
    timed_out = json.loads(await asyncio.wait_for(silent.recv(), 15))
    check("silent connection dropped after ~10s", timed_out["op"] == "error" and 9 < time.monotonic() - started < 12)


def main():
    relay = subprocess.Popen(
        [sys.executable, "-I", str(RELAY)],
        env={**os.environ, "DESICABO_ALLOWED_ORIGINS": ORIGIN, "DESICABO_RELAY_PORT": str(PORT)},
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(1.0)
    try:
        asyncio.run(run())
    finally:
        relay.terminate()
        try:
            relay.wait(timeout=20)
        except subprocess.TimeoutExpired:
            relay.kill()
    print("all passed" if not failures else f"{len(failures)} failed: {failures}")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
