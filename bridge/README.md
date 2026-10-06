# Local canonical rules bridge

This prototype runs the preserved browser game's real JavaScript rules in Node.js. Godot draws the world and interface and sends allowlisted commands; it does not maintain a second economy implementation. The preserved source is in `vendor/legacy`, including the generated server runtime with hash `432f9fea6359c18a8d1e2655b09f97770718c3e676501c602c7897afd906a8b4`.

中文整体架构和迁移边界见 `docs/ARCHITECTURE.zh.md`。This is a separate Godot repository. The original browser repository and Pages remain at original commit `c7674df45b9595405e57907524e737e633b0ff63`; this project only vendors its rule snapshot. Source provenance is recorded in `vendor/legacy/provenance.json`.

Run with Node 20 or newer:

```sh
node bridge/server.mjs --port 8139 --data-dir .local/dev-save
```

The default server binds to `127.0.0.1`. The tokenless command is only for local development. Desktop launchers generate a secret and use `--token-file <path>` (or `--token <secret>`), `--port 0`, and `--ready-file <path>`. The ready file contains `{url,pid,protocol}` and never the token. It is removed on graceful shutdown. A save-directory process lock prevents multiple authorities for the same save.

Use `--web-dir build/web` to serve the exported Godot web files and APIs from the same origin. Resource paths, symlinks and private-directory overlap are checked. Web exports receive COOP/COEP headers. API aliases under `/api` work identically to the root API paths. Only loopback web origins are accepted by default; add an exact `--allowed-origin https://example.com` for a deliberate remote frontend. This local service is not a production multiplayer backend.

For an exported Windows desktop package, keep the entire `ThreeKingdoms.exe`/PCK, `runtime/node.exe`, and `rule-service` tree together. The native Godot client starts its packaged Node child with a generated token and an assigned port; the client save lives in its Godot user-data directory. For a same-origin web preview, run:

```sh
node bridge/server.mjs --port 17338 --data-dir .local/web-save --web-dir build/web
```

Open `http://127.0.0.1:17338/`. The web client derives its API URL as `location.origin + '/api'`. Browsers cannot spawn Node, so the web export must be served alongside this local service or a future compatible backend. If you configure a token, enter it in the client's connection settings. The current web preview service owns one local save, shared by clients connected to that service; it is not an account-per-player service.

## HTTP contract (protocol 1)

When a token is configured, every state and mutation request needs `Authorization: Bearer <token>` or `X-Bridge-Token`. `/health` exposes only readiness and protocol metadata. `/shutdown` always requires a configured, valid token, even in tokenless development mode. No token is accepted through URL query strings.

| Method | Path | Result |
|---|---|---|
| GET | `/health` | `{ok,protocol,runtimeHash,mode,authentication,authorityId}` |
| GET | `/state` | `{revision,state,view,serverTime,authorityId}` |
| GET | `/world` | `{width,height,home,tiles,marches,revision,serverTime,authorityId}` |
| GET | `/node?id=wild_29_34` | `{revision,node,serverTime,authorityId}`; hidden task targets are rejected |
| POST | `/command` | Updated state envelope, plus `{result,replayed}` |
| POST | `/import` | Updated state envelope, plus `{result,replayed}` |
| GET | `/export` | Bare canonical save JSON, compatible with the original browser export |
| POST | `/shutdown` | `{ok:true}`, then graceful shutdown |

Commands use JSON `{commandId,expectedRevision,type,args,sourceCity?}`. The original `executeGame` dispatcher enforces the existing rule whitelist. For example:

```json
{"commandId":"build_house_0001","expectedRevision":0,"type":"queueBuilding","args":[0,"house"]}
```

An import uses `{commandId,expectedRevision,state:<browser export object>}`. Current saves are strictly validated; supported older formats use the canonical migration and then strict validation. An invalid import never replaces the current save. Before a valid import, the previous bridge save is copied to `before-import.json`.

Writes are serialized, compare expected revision, and atomically replace `save.json` together with their receipt. The most recent **32 successful command IDs** are retained across restart. A retry with the same ID and payload returns its original result without a second mutation; key ordering is immaterial. Reusing that ID for a different payload fails. Older retries encounter their obsolete revision and cannot execute twice. The caller should create a fresh command ID for each intentional action and retain it when retrying that action.

Every save directory has a persisted `authorityId` UUID. It remains stable across restart and browser-save import and appears in health and state envelopes. It identifies the local authority, not a player account or credential. A client retaining an unconfirmed command must check this identity before resending that command to a service. Earlier schema-1 bridge headers without an identity are migrated once after their canonical save has passed validation.

The Godot client persists an unconfirmed operation in `user://pending-command.json` before sending it. It reconnects by reading health, verifies the saved authority, and retries the original request body with the original `commandId` and `expectedRevision`. It clears that pending record after a confirmed outcome. Client reconnection does not create a second purchase/build/train operation. A pending operation belonging to another authority stays blocked until the user returns to the original service.

Read endpoints settle elapsed time in a disposable rule projection without writing revision, resource balances or receipt history. A later successful command commits the corresponding native timer settlement. These are authoritative local-save semantics, not remote multiplayer authority.

Errors are `{error:{code,message},revision}` with HTTP 400 for invalid input or game rules, 401 for token failure, 403 for forbidden origins/hidden targets, 409 for revision/receipt/process-lock conflicts, and 500 for persistence/internal failures. A conflict requires a fresh state read before a new intentional command. Request bodies are limited to 16 MiB and must use `application/json`.

## Rendering DTO

`view` contains `res`, `gold`, `caps`, and `rates` (per minute), plus city and population information. `buildings` is an array with `id,name,site,level,cost,seconds,requirement,affordable,queue`; `buildingSlots` preserves all 36 actual slots. `buildOptions` lists available new-building types. `plots` contains all canonical outer plots, and `plotOptions` lists the four real production types. `units` includes `id,name,available,cost,seconds,requirement,unlocked,people,role,stats`. All costs, timings, requirements and statistics come from native Game functions.

`queues` is a dictionary with array values: `{build:[],train:[],research:[],defense:[]}`. The canonical single research queue is wrapped as a one-element array in this view only. `objective` includes `id,title,description,reward,ready,action,args,route`. `generals` includes real statistics, loyalty and busy/city/governor flags. `techs`, `inventory` and `shop` use native metadata and rule quotes. Shop prices use gems. Speedup inventory targets are real queue keys; use the `useSpeedup` command with `[itemId,target.key]`. `queueMetadata` lists keys and queue kinds from `Game.speedupTargets()`. `battle` is the unmodified canonical battle object, including player/enemy rows, positions and unit statistics, round, orders, events, log and result. `reports` is the canonical report array.

`market` contains its building `level` and four `resources` rows, each with `{id,name,buy,sell}`. Both quotes retain the complete native `Game.tradeQuote()` result: `{scale,room,stock,limit,reason,warning}`. Trading uses the original one-resource-for-one-gold rate and `trade` arguments `[resourceId,count,buyBoolean]`. Resource purchases may exceed storage capacity; gold capacity still limits sales. The client clamps oversized input to the quoted limit, while the service rejects quantities above the current authoritative limit. A stale quote cannot authorize a transaction.

`governance` contains `governorId`, population/capacity/free population, morale/unrest/tax, native `targetMorale`, `goldPerMinute`, `productionBoost`, `constructionFactor` and general `candidates`. Candidate `reason` matches `setGovernor` eligibility; a busy general also includes a general located in another city. `productionBoost` mirrors the canonical governor multiplier on outer-plot output only. `constructionFactor` is the native divisor from construction technology and governor politics. Base income and gold taxes do not acquire this production bonus. `setGovernor` takes `[generalId]`; `setTax` takes `[percentage]`, which the original engine rounds and bounds to 0–100. The target morale is `max(0,100-tax-unrest)` and changes over time, rather than changing current morale immediately.

`inn` contains `level,capacity,used,remaining,refreshReason,candidates`. Capacity is the realm's total recruitment-hall levels; usage includes owned generals and both wild and defeated captive pools. Candidate rows retain their canonical generated statistics and `price`, plus a gold-only `affordable` flag and the complete recruitment `reason` (room, total count, then gold). `refreshInn` takes no arguments and costs no gold; `recruit` takes `[candidateId]`. The successful command response supplies the actual recruited general statistics, which include the existing level and growth rules. All these actions use the existing whitelist, revision comparison and replay receipts.

The map preserves the existing 64 × 64 coordinates. Future task sites are represented as anonymous terrain with `hidden:true`, `selectable:false` and synthetic `unknown_x_y` IDs. Actual future target identities never appear in world tiles or the visible node list. Expansion into a larger authoritative world remains a separate migration. `marches` includes real expeditions, garrisons and intercity logistics, with frozen start/arrival timestamps and source-city information.

## Current boundary

This service exposes canonical private-save JSON to its authenticated local client and is deliberately loopback-only. It has no public player identities, multi-account authorization, global-world database, hosted Supabase project or Steamworks integration. The local token and authority UUID do not stand in for those systems. Keep private saves, ready files and token files outside the web resource tree. Public multiplayer needs a separate authenticated service and shared-world transaction model.

The original browser JSON import/export format is maintained. The Godot interface exposes the current migration's playable flows; retaining the full canonical save does not imply that every original system already has a finished native interface. Windows export and actual Windows-device playtesting are distinct validation steps.

`tests/fixtures/godot-view.json` is a fictional fresh-city DTO fixture produced through the actual runtime; it is not a player save or QA progression claim. Run the HTTP integration suite with:

```sh
node --test tests/bridge.test.cjs
```
