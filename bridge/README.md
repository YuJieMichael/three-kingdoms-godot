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
| POST | `/quote` | Read-only canonical quotation for march, founding, transport or redeploy |
| POST | `/practice` | Isolated borrowed-army session; no campaign state or revision writes |
| POST | `/command` | Updated state envelope, plus `{result,replayed}` |
| POST | `/import` | Updated state envelope, plus `{result,replayed}` |
| GET | `/export` | Bare canonical save JSON, compatible with the original browser export |
| POST | `/shutdown` | `{ok:true}`, then graceful shutdown |

Quotations use JSON `{kind,args,requestId,sourceCity?}` with `kind` restricted to `march`, `foundCity`, `transport`, or `redeploy`. They return `{requestId,quote,revision,authorityId,serverTime}` plus shared identity fields where applicable. Quotes never commit a save, increment revision or write command receipts. Owned source cities, visible targets and private/shared capabilities are checked; commands recheck their native rules at execution time. A client must ignore stale request IDs and invalidate a quotation when its input changes.

Borrowed practice is local-only and uses `{requestId,action,sessionId?,revision?,scenario?,type?,args?}`. Start with `action:"start"` and one of `shield_archer`, `spear_cavalry`, `siege_guard`; the last uses the actual third-chapter `luo_gate` fortification. Fixture troop counts are clearly labelled practice values. Subsequent `order`, `round`, `end` actions require the returned session ID and practice revision. Orders allow only `setBattleOrders` or `setBattleOrder`; round invokes the native `battleRound`. The response is `{ok,requestId,authorityId,serverTime,practice}`; `practice` contains its session revision, battle, units, result and evidence review, or is null after end. The API also accepts the `/api/` prefix. Browser callers must use the same origin even if another origin is allowed for ordinary bridge endpoints.

Practice uses a fresh in-memory canonical runtime, never the player's save. Borrowed resources, troops, battle losses, experience, loot and conquests are discarded. It retains at most four sessions and 128 request receipts for 20 minutes of inactivity, clears on successful import/shutdown, and does not survive service restart. A repeated request ID with the same payload replays its receipt; changed payloads or stale practice revisions fail with 409. Retry the exact original request after an uncertain response and block new mutating practice actions until confirmed. A start carrying a live session ID and revision restarts/replaces that practice without adding another session; expired sessions require a fresh start. `action:"sync"` with the known session ID and a shaped revision reads its current projection/revision without invoking the runtime or changing battle state, and renews its idle TTL; this is the recovery for an explicit revision conflict. It also uses independent request receipts. Practice has no campaign CAS journal and must never update the client's campaign revision. Normal city timers continue while its window is open.

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

`queues` is a dictionary with array values: `{build:[],train:[],research:[],defense:[]}`. The canonical single research queue is wrapped as a one-element array in this view only. `objective` includes `id,title,description,reward,rewards,ready,action,args,route,target`. The optional runtime-backed sections `progression`, `heroes`, `warManagement`, `realmManagement` and `inventoryManagement` expose canonical quotes and command descriptors for the completed local management interfaces. No gameplay formula is reproduced by these views. `generals` includes real statistics, loyalty and busy/city/governor flags. `techs`, `inventory` and `shop` use native metadata and rule quotes. Shop prices use gems. Speedup inventory targets are real queue keys; use the `useSpeedup` command with `[itemId,target.key]`. `queueMetadata` lists keys and queue kinds from `Game.speedupTargets()`. `battle` is the unmodified canonical battle object, including player/enemy rows, positions and unit statistics, round, orders, events, log and result. `reports` is the canonical report array.

`market` contains its building `level` and four `resources` rows, each with `{id,name,buy,sell}`. Both quotes retain the complete native `Game.tradeQuote()` result: `{scale,room,stock,limit,reason,warning}`. Trading uses the original one-resource-for-one-gold rate and `trade` arguments `[resourceId,count,buyBoolean]`. Resource purchases may exceed storage capacity; gold capacity still limits sales. The client clamps oversized input to the quoted limit, while the service rejects quantities above the current authoritative limit. A stale quote cannot authorize a transaction.

`governance` contains `governorId`, population/capacity/free population, morale/unrest/tax, native `targetMorale`, `goldPerMinute`, `productionBoost`, `constructionFactor` and general `candidates`. Candidate `reason` matches `setGovernor` eligibility; a busy general also includes a general located in another city. `productionBoost` mirrors the canonical governor multiplier on outer-plot output only. `constructionFactor` is the native divisor from construction technology and governor politics. Base income and gold taxes do not acquire this production bonus. `setGovernor` takes `[generalId]`; `setTax` takes `[percentage]`, which the original engine rounds and bounds to 0–100. The target morale is `max(0,100-tax-unrest)` and changes over time, rather than changing current morale immediately.

`inn` contains `level,capacity,used,remaining,refreshReason,candidates`. Capacity is the realm's total recruitment-hall levels; usage includes owned generals and both wild and defeated captive pools. Candidate rows retain their canonical generated statistics and `price`, plus a gold-only `affordable` flag and the complete recruitment `reason` (room, total count, then gold). `refreshInn` takes no arguments and costs no gold; `recruit` takes `[candidateId]`. The successful command response supplies the actual recruited general statistics, which include the existing level and growth rules. All these actions use the existing whitelist, revision comparison and replay receipts.

The map preserves the existing 64 × 64 coordinates. Future task sites are represented as anonymous terrain with `hidden:true`, `selectable:false` and synthetic `unknown_x_y` IDs. Actual future target identities never appear in world tiles or the visible node list. Expansion into a larger authoritative world remains a separate migration. `marches` includes real expeditions, garrisons and intercity logistics, with frozen start/arrival timestamps and source-city information.

## Current boundary

### Additional local gameplay projections

`view.campaign` exposes canonical `WarOrders` routes, currently unlocked targets, public military intelligence, classic tactical-condition attempts, cooldowns, merit and native `war.exchange` offers. It opens after `north_keep` in private PVE; shared rooms receive no private target list. Targets are board entries, not invented world-map coordinates. Dispatch still uses the native march quote, `occupy` mode and automatic return; native battle settlement awards merit once.

`heroes.owned[].specialization` includes the original GeneralGrowth profile, stat bonus and four route training quotes. `trainGeneralSkill` takes `[heroId,routeId,key]`; the existing native rule validates mutually exclusive routes, levels, availability and payment. No training formula is copied into the DTO.

`realmManagement.templates[].quotes.fill/replace` include a `key` binding the canonical plan, city, affected field levels and reserve. The private service accepts `applyPlotTemplate [templateId,mode,key]`, settles time before checking the key and returns `PLAN_CHANGED` if the preview no longer matches. Original two-argument clients remain compatible. The room dispatcher currently uses only the original rule; it does not enforce this additional preview key.

Private `exchangeCopper` also accepts quoted `growth_prepare_<office|noble>_<rank>_<jewel>` offers for the actor's next rank, after conquering `camp`. Their caps equal the native rank requirement; current stock already sufficient for that promotion blocks the corresponding stage offer. The new fixed prices are **prototype design**: pearl40, coral80, glass120, amber160, agate200, crystal240, jadeite280, jade320, nightPearl400 copper per jewel. The first noble's coral continues to use the previous five-per-save `growth_coral` offer; native daily exchange remains separate. Jewels enter shared inventory and can be spent on other native systems; spent quotas do not replenish.

Optional save-wide `growthSupport` v1 remains accepted as `{version:1,coralExchanged}`. First stage purchase upgrades it to `{version:2,coralExchanged,preparation:{[offerId]:count}}`, retaining the existing coral count. The adapter validates known current/historical ranks and count caps before import/load and after its mutation. The same serialized revision check and persisted replay receipt protect exchanges; no quota resets on day rollover or city switching. The canonical vendor snapshot remains unchanged. These additions received parser/static review only in this batch, without functional execution.

The private `bridge/server.mjs` service exposes canonical private-save JSON to its authenticated local client and is deliberately loopback-only. It has no public player identities, multi-account authorization, global-world database, hosted Supabase project or Steamworks integration. The local token and authority UUID do not stand in for those systems. Keep private saves, ready files and token files outside the web resource tree. The separate account-bound room service described below does not change private-save import/export.

The original browser JSON import/export format is maintained. The Godot interface exposes the current migration's playable flows; retaining the full canonical save does not imply that every original system already has a finished native interface. Windows export and actual Windows-device playtesting are distinct validation steps.

`tests/fixtures/godot-view.json` is a fictional fresh-city DTO fixture produced through the actual runtime; it is not a player save or QA progression claim. Run the HTTP integration suite with:

```sh
node --test tests/bridge.test.cjs
```


## Local room lobby (0.5.0)

`node scripts/start-rooms.mjs --data-dir .local/rooms --web-dir build/web` starts a separate loopback service on17343. `/lobby` serves create/join/resume; `--native-only` serves only room APIs for the Godot `--lobby=http://127.0.0.1:17343` entry. Original private and four-account services remain separate.

POST `/lobby/create` uses `{requestId,roomName,capacity,playerName}`; `/lobby/join` uses `{requestId,inviteCode,playerName}`; `/lobby/resume` uses `{roomId,recoveryKey}`. Capacity is1–8; request/invite/access/recovery capabilities are64 lowerhex characters. Room IDs use `room_` plus32 hex; member IDs use `member_` plus32 hex. Signup retries must keep the same request ID and exact original JSON body. A mismatched reuse is409.

Success returns `{ok,protocol,room,seat,actor,authorityId,accessToken,recoveryKey,inviteCode}`. Public room metadata contains IDs, names, capacity and initial seat groups; only the enrolling/recovering member receives their own session. Invite codes claim vacant seats; recovery requires the room ID and that member's own recovery key. Nicknames cannot recover an existing seat.

Bearer credentials select the live member and room on the server, with unique persisted member authority IDs. Existing state/world/node/command envelopes have public `room` metadata, and canonical shared rules execute in the corresponding room realm. Rooms cannot import/export private saves or accept browser shutdown. The server does not allow a public host bind.

The private `rooms.json` atomically commits room registry, credentials, candidate MemoryStore worlds and original request receipts. Startup validates persisted data and preserves corrupt files. Existing private/four-account data directories are rejected. Automatic settlement runs while the service is open; restart catches overdue marches. This does not implement hosted accounts, cross-machine identity or Steamworks.

The lobby retains an uncertain signup request only in the current window's memory. It warns that closing/refreshing can lose recovery of a committed but unconfirmed new seat. Clients do not persist signup or login credentials. In-game noncredential command journals retain the existing per-authority/member replay semantics.

## Account-bound room service (0.6.0-dev.1)

This development preview adds Supabase Auth and private PostgreSQL storage to the existing canonical room service. The original private bridge, four-account rehearsal and local 0.5 recovery-key rooms remain separate and compatible. The 0.5/presentation merge checkpoint `e5f5c6c` is pushed to the independent repository; no real game Supabase project or public Node deployment has been opened or verified.

| Method | Path | Account-mode result |
|---|---|---|
| GET | `/auth/config` | `{enabled:true}`; local mode returns `false` |
| POST | `/auth/login` | `{email,password}` → `{ok,sessionToken,user:{id,email}}` and a Web session cookie |
| GET | `/auth/me` | `{ok,user}` after fresh provider verification |
| POST | `/auth/logout` | Empty JSON body; revoke this opaque session |
| GET | `/lobby/mine` | `{ok,rooms:[{room,seat,actor,authorityId}]}` without room credentials |
| POST | `/lobby/account-resume` | `{roomId}` → the authenticated account's existing member session |
| GET | `/readyz` | Public `{ok,settlement}`; 503 when durable storage or settlement is unavailable |

The server derives account identity from Supabase `getUser`, never from request fields or `user_metadata`. Provider access/refresh tokens remain in server RAM. Clients receive an opaque 64-hex session, supplied through `X-Account-Session` by native clients or a same-origin `HttpOnly; Secure; SameSite=Strict` cookie by Web clients. Every protected lobby/game request rechecks the provider. Native account sessions are not persisted; restarting the service requires a fresh login, then the same account can recover its permanent room seat.

`Authorization: Bearer <room accessToken>` remains required for game APIs and must belong to the verified account. Create/join retain the 0.5 JSON shapes but bind the permanent member to that account. A repeated join by the same account returns its original seat before capacity checks. Cloud mode disables recovery-key `/lobby/resume`; an invite or room bearer cannot replace account authentication. Room metadata never publishes account IDs or credentials.

Protected requests may include `X-Expected-Account: <previously verified user.id>` as an account-context precondition. It is checked against the fresh verified identity, not used as authority. A mismatch returns `ACCOUNT_CHANGED` with 401 before enrollment, receipt replay or game access. Web/native clients retain this expected account with an uncertain request, so another tab changing the cookie cannot move the retry to a different account. Logout checks the same precondition before revoking RAM authorization or clearing the cookie; a mismatch leaves the other account signed in. The header remains optional for API compatibility.

`startRoomsServer({cloudAccount:{auth,publicOrigin,limits},storageFactory})` uses the injected store; the production launcher creates Auth with a publishable key and opens `game_private.room_worlds` through a server-only database connection. PostgreSQL saves each namespace's members, credentials, canonical room worlds and receipts in one transaction. A dedicated session holds the namespace's advisory lock. Lost connection/lock or an uncertain COMMIT stops reads and writes; restart reloads committed receipts instead of falling back to JSON. Backups retain the namespace and checksum, require private output paths, and restore only while the game service is stopped.

Production requires Node 24, an exact HTTPS public origin, verified database TLS with a direct/session connection, a closed email allowlist, and a separate persistent Node host. The launcher cannot select the loopback test Auth provider or local JSON fallback. Request and room limits, HTTPS proxy/systemd/container examples, readiness and backup tools are prepared in [online service instructions](../docs/ONLINE-SERVICE.zh.md). The separate Free game organization/project is configured; real database credentials, Auth/service verification and public Node hosting remain pending. The user has paused cloud integration to complete local gameplay. These files are a deployment foundation, not evidence of a live service.

Local evidence uses real temporary PostgreSQL 17.10 and a test-only loopback Supabase REST provider. `tests/cloud-bridge.test.cjs` checks account/origin/context boundaries; `tests/postgres-room-store.test.cjs` checks actual SQL persistence, locking and failure behavior; `tests/cloud-postgres.test.cjs` covers offline winning raids, return delivery and exact retry across restarts. Production code does not import these fixtures. Run the complete Node suite after `npm ci` with `npm test`.
