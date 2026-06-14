# mikrotik-sms-forwarder

Forwards incoming SMS from a MikroTik RouterOS LTE device to Matrix and Telegram, so messages arriving on a remote SIM can be read from anywhere.

It runs entirely on the router as a scheduled RouterOS script — no external server, no container. On each run it reads the modem inbox, decodes each message, posts it to the enabled channels, and removes it only after a successful delivery.

## How it works

1. `sms-config` holds the settings (which channels are on and their credentials). It is a separate script so the secrets live apart from the logic and survive logic updates.
2. `sms-forward` runs `sms-config`, then for every message in `/tool sms inbox`:
   - decodes the text from the `pdu` field rather than the `message` field — RouterOS replaces non-Latin characters with `?` in `message`, but the PDU is intact;
   - reassembles multi-part (concatenated) SMS by their UDH reference and drops the duplicate parts the modem sometimes stores;
   - formats the result as `[YYYY-MM-DD HH:MM] <sender>: <text>`;
   - tries every enabled channel and removes the parts from the inbox only once the message has been delivered in full.
3. A scheduler runs `sms-forward` every 10 minutes.

If delivery fails, the message stays in the inbox and is retried on the next run. A failed send creates nothing on the server, so retries do not duplicate a delivered message; the one exception is a partly-delivered multi-part message, whose already-sent parts repeat on the retry.

### Text and Unicode

Cyrillic and other non-Latin text arrives as UCS-2 (PDU data-coding `0x08`). RouterOS mangles raw UTF-8 passed through `/tool fetch`, so the body is built with `\uXXXX` JSON escapes (plain ASCII on the wire) and the receiving chat renders the native characters. Latin/GSM-7 messages (`0x00`) are taken from the decoded `message` field.

`/tool fetch` truncates a long `http-data` body when it carries many escape sequences, which corrupts the JSON and the server rejects it. Messages are therefore split into chunks of at most 100 UTF-16 units; a long SMS shows up as a few consecutive messages, and the inbox parts are removed only after all chunks are delivered.

## Requirements

- A MikroTik device with an LTE modem and SMS reception enabled (`/tool sms set receive-enabled=yes`).
- Outbound HTTPS from the device to the channels you enable.
- At least one channel:
  - **Matrix** — a bot account and an **unencrypted** room (the script posts over plain client-server HTTP and does not do E2EE).
  - **Telegram** — a bot (from @BotFather) added to the target chat.

## Setup

### 1. Channels

**Matrix** — register a bot account, create an unencrypted room, and invite the bot. Take the room id (`!…:server`) and a bot access token; a password login returns the token:

```
curl -XPOST https://matrix.org/_matrix/client/v3/login \
  -d '{"type":"m.login.password","user":"BOT","password":"PASS"}'
```

**Telegram** — create a bot with @BotFather and add it to the target chat. Send any message there, then read the chat id from `getUpdates`:

```
curl https://api.telegram.org/bot<TOKEN>/getUpdates
```

Take `result[].message.chat.id` — negative for groups, `-100…` for supergroups and channels.

### 2. Config

Copy `routeros/sms-config.example.rsc` to `sms-config.rsc` and fill in the real values:

```
:global matrixEnabled true
:global mxHs "matrix.org"
:global mxRoom "!ROOMID:matrix.org"
:global mxToken "BOT_ACCESS_TOKEN"

:global telegramEnabled true
:global tgToken "BOT_TOKEN"
:global tgChat "-100CHATID"
```

Turn a channel off with its `*Enabled` flag. RouterOS does not allow underscores in script variable names — keep the camelCase names as they are.

### 3. Install on the device

Upload both files to the router, then load them as named scripts and add the scheduler:

```
/system script add name=sms-config policy=read,write,policy,test source=[/file get sms-config.rsc contents]
/system script add name=sms-forward policy=read,write,policy,test source=[/file get sms-forward.rsc contents]
/system scheduler add name=sms-forward interval=10m policy=read,write,policy,test on-event="/system script run sms-forward"
```

The `policy` flags must match across the scripts and the scheduler: a scheduler can only run a named script whose policies it fully holds, so a scheduler with fewer policies than the script fails with `not enough permissions`.

To change settings later, edit `sms-config` only; `sms-forward` reads it on every run.

## Layout

```
routeros/sms-forward.rsc          the forwarder
routeros/sms-config.example.rsc   settings template (copy to sms-config.rsc)
```

## License

MIT — see [LICENSE](LICENSE).
