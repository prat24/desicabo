# Self-hosting the web version

The phone app plays online over the local network (ENet plus a UDP broadcast
search). Browsers can't use UDP, so the web build connects to a small WebSocket
relay instead, served from the same origin as the game at `/ws`. The relay only
forwards packets between the host and the other players in a room. The host's
browser still runs the game, exactly as the host phone does on Wi-Fi. Players
join with a 5-character room code.

```
browser ──HTTPS──▶ web server ──▶ build/web (static files)
                        └─ /ws ──▶ relay (127.0.0.1:8765)
```

## Requirements

- Godot 4.7 with the Web export templates, to build.
- Python 3.11+ with [`websockets`](https://pypi.org/project/websockets/) 10.4
  or newer, for the relay. Debian's `python3-websockets` package works.
- A web server that serves the build and proxies `/ws` to the relay, over HTTPS.
  [Caddyfile](Caddyfile) is an example for Caddy 2.6+.

## Build

```bash
deploy/build_web.sh
```

This exports to `build/web/` and writes `.gz` copies of the large files for
servers that serve pre-compressed files. `deploy/publish.sh user@host:/path`
copies the build to a server with rsync.

## Relay

```bash
DESICABO_ALLOWED_ORIGINS=https://cabo.example.com python3 deploy/relay/relay.py
```

| Variable | Default | |
|---|---|---|
| `DESICABO_ALLOWED_ORIGINS` | *required* | Comma-separated origins allowed to connect, exactly as in the browser's address bar (scheme, host, port). |
| `DESICABO_RELAY_HOST` | `127.0.0.1` | Keep it on loopback, behind the web server. |
| `DESICABO_RELAY_PORT` | `8765` | |

To run it as a service, [desicabo-relay.service](desicabo-relay.service) is a
sandboxed systemd unit, with settings read from a file like
[relay/relay.env.example](relay/relay.env.example).

## Web server

Whatever serves the game must:

- serve `build/web/`, with `.wasm` files as `application/wasm`;
- proxy `/ws` (a WebSocket upgrade) to the relay;
- be reached over HTTPS, so the game connects with `wss://`.

The example [Caddyfile](Caddyfile) does all three. It also sets security
headers (including a Content-Security-Policy the game is known to work with)
and listens on loopback for use behind a TLS proxy such as `tailscale serve`.
Replace `:8090` with a domain name to let Caddy handle HTTPS itself.

The game finds the relay next to its own page (`…/index.html` → `…/ws`), so it
can be hosted at a sub-path too.

## Security

- There are no accounts. Anyone who can load the page can host a game, so
  consider keeping the site private (a VPN such as Tailscale, or the basic-auth
  block in the example Caddyfile).
- The relay never interprets game data. It accepts pages only from
  `DESICABO_ALLOWED_ORIGINS`, and limits:
  - room-code guessing to 10 wrong codes a minute per address;
  - messages to 64 KB, with a per-connection rate limit;
  - connections, and rooms per address;
  - idle handshakes.
- It trusts `X-Forwarded-For` only from proxies on loopback.
- Keep the relay and the web server on loopback, and expose only the HTTPS
  endpoint.

## Testing locally

```bash
python3 -m venv .venv && .venv/bin/pip install websockets
.venv/bin/python deploy/relay/test_relay.py
```

To play locally, run the relay and Caddy in two terminals, then open
<http://localhost:8090> in two browser windows:

```bash
DESICABO_ALLOWED_ORIGINS=http://localhost:8090 .venv/bin/python deploy/relay/relay.py
```

```bash
DESICABO_WEB_ROOT="$PWD/build/web" caddy run --config deploy/Caddyfile --adapter caddyfile
```

Keep both windows visible; browsers pause games in hidden tabs.

If you change the relay's message format, bump `PROTOCOL_VERSION` in both
`deploy/relay/relay.py` and `Scripts/Net/relay_peer.gd`.
