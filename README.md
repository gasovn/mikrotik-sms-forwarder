# mikrotik-sms-forwarder

Forwards incoming SMS from a MikroTik RouterOS LTE device to a Matrix room, so messages arriving on a remote SIM can be read from anywhere.

It runs entirely on the router as a scheduled RouterOS script — no external server, no container. On each run it reads the modem inbox, decodes each message, posts it to Matrix, and removes it only after a successful delivery.

## How it works

1. `sms-config` holds the settings (Matrix homeserver, room, bot token, channel flags). It is a separate script so the secrets live apart from the logic and survive logic updates.
2. `sms-forward` runs `sms-config`, then for every message in `/tool sms inbox`:
   - decodes the text from the `pdu` field rather than the `message` field — RouterOS replaces non-Latin characters with `?` in `message`, but the PDU is intact;
   - reassembles multi-part (concatenated) SMS by their UDH reference and drops the duplicate parts the modem sometimes stores;
   - formats the result as `[YYYY-MM-DD HH:MM] <sender>: <text>`;
   - delivers it to every enabled channel and removes the parts from the inbox only after the whole message has been delivered.
3. A scheduler runs `sms-forward` every 10 minutes.

If delivery fails, the message stays in the inbox and is retried on the next run. A failed send creates nothing on the server, so retrying does not duplicate an already-delivered message.

### Text and Unicode

Cyrillic and other non-Latin text arrives as UCS-2 (PDU data-coding `0x08`). RouterOS mangles raw UTF-8 passed through `/tool fetch`, so the body is built with `\uXXXX` JSON escapes (plain ASCII on the wire) and Matrix renders the native characters. Latin/GSM-7 messages (`0x00`) are taken from the decoded `message` field.

`/tool fetch` truncates a long `http-data` body when it carries many escape sequences, which corrupts the JSON and the server rejects it. Messages are therefore split into chunks of at most 100 UTF-16 units; a long SMS shows up as a few consecutive Matrix messages, and the inbox parts are removed only after all chunks are delivered.

## Requirements

- A MikroTik device with an LTE modem and SMS reception enabled (`/tool sms set receive-enabled=yes`).
- Outbound HTTPS from the device to the Matrix homeserver.
- A Matrix account for the bot and an **unencrypted** room (the script posts over plain client-server HTTP and does not do E2EE).

## Setup

### 1. Matrix

- Register a separate bot account on your homeserver.
- Create an unencrypted room and invite the bot (and yourself).
- Get the bot's access token and the room id (`!…:server`). A password login returns the token:

```
curl -XPOST https://matrix.org/_matrix/client/v3/login \
  -d '{"type":"m.login.password","user":"BOT","password":"PASS"}'
```

### 2. Config

Copy `routeros/sms-config.example.rsc` to `sms-config.rsc` and fill in the real values:

```
:global matrixEnabled true
:global mxHs "matrix.org"
:global mxRoom "!ROOMID:matrix.org"
:global mxToken "BOT_ACCESS_TOKEN"

:global telegramEnabled false
:global tgWorkerUrl ""
:global tgSecret ""
```

RouterOS does not allow underscores in script variable names — keep the camelCase names as they are.

### 3. Install on the device

Upload both files to the router, then load them as named scripts and add the scheduler:

```
/system script add name=sms-config policy=read,write,policy,test source=[/file get sms-config.rsc contents]
/system script add name=sms-forward policy=read,write,policy,test source=[/file get sms-forward.rsc contents]
/system scheduler add name=sms-forward interval=10m policy=read,write,policy,test on-event="/system script run sms-forward"
```

The `policy` flags must match across the scripts and the scheduler: a scheduler can only run a named script whose policies it fully holds, so a scheduler with fewer policies than the script fails with `not enough permissions`.

To change settings later, edit `sms-config` only; `sms-forward` reads it on every run.

## Telegram

A second channel is wired in but disabled (`telegramEnabled false`). Direct delivery to Telegram is not always reachable (it is blocked on some networks), so it is meant to go through a relay with foreign egress — e.g. a Cloudflare Worker that accepts `POST {"text":"…"}` with an `X-Auth` header and forwards to the Bot API. Set `tgWorkerUrl` / `tgSecret` and flip the flag once such a relay exists.

## Layout

```
routeros/sms-forward.rsc          the forwarder
routeros/sms-config.example.rsc   settings template (copy to sms-config.rsc)
```

## License

MIT — see [LICENSE](LICENSE).
