# VUT - agent rules

Own-auction queue tracker for the Classic Era (Camelot 1.60.1) auction house:
undercut / tied / sold-out / low-quantity alerts through chat, sound, flash
and toast channels. Hexagonal core, strict type gates, zero taint surface.

## Verified wire facts (do not re-litigate - pinned by specs or probes)

All verified in game on the target client (2026-11, VUTProbe dumps +
AuctiMogger's fork evidence on the same build):

1. **Own listings are self-marked** in search results: `owners` contains the
   literal `"player"`, plus `containsOwnerItem` / `containsAccountItem` /
   `numOwnerItems`. No name matching anywhere.
2. **Commodity match order**: `unitPrice` ASC, and within a price tier the
   NEWEST listing sells first ("last placed sells first" - the delivered row
   order IS the buy order; no reversal). This is the cancel/repost-
   jump-the-queue behavior. Row shape depends on the query's
   `separateOwnerItems` flag (3rd arg of SendSearchQuery): `false` MERGES
   same-price owners into tier rows (own units ride inside via
   `numOwnerItems` - the UI "grouped" first-click view of cached results);
   `true` (what the Auctions tab sends - AuctionsItems/AuctionsCommodities
   contexts) returns per-listing rows with the own listing separate at its
   queue position (the UI "detailed" second-click view; observed in game:
   first click refreshes the cached shape in place via HasSearchResults ->
   RefreshItemSearchResults, second click re-queries). VUT queries with
   `true`; positions are row-granular in that shape.
3. **Owned list** (`GetOwnedAuctionInfo`): `status 0=Active, 1=Sold`; the
   status-1 rows are a per-sale LEDGER (qty + gold; `buyoutAmount = qty x
   unit price` there), can repeat an auctionID, and vanish eventually.
   ACTIVE commodity rows carry the UNIT price in `buyoutAmount` (verified:
   60-lot at 954). Row order is unstable between queries. `GetOwnedAuctionTypes`
   ACTIVE keys only. The ledger SURVIVES reloads server-side: the first
   FULL owned snapshot (`HasFullOwnedAuctionResults`) of a session baselines it
   silently (no replay of pre-session sales as alerts; only growth after the
   baseline is a sale). Partial `OWNED_AUCTIONS_UPDATED` payloads are NEVER
   ingested - a partial baseline replayed late-arriving rows as sold alerts
   (observed in game). `PLAYER_LOGIN` fires an early script-side owned query so
   the baseline settles before the AH opens; the AH-open refresh is the
   fallback.
4. **Gates** (script-context): `QueryOwnedAuctions` PASSES (~0.1s answer).
   Commodity `SendSearchQuery` PASSES (wire doc: 100 searches/min cap).
   Item `SendSearchQuery`/`QueryItem` are REFUSED (empty result sets).
   Blizzard-handler clicks (`button:Click()`) answer for items.
5. **Event quirks**: `AUCTION_CANCELED`'s payload is NOT an auctionID
   (garbage value observed); the `CancelAuction` post-hook argument is
   equally untrustworthy; `AUCTION_HOUSE_AUCTION_CREATED` did not fire on
   a commodity post; `AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED` fires around
   UI actions too. Consequence: the owned-snapshot DIFF is the lifecycle
   source of truth; events are hints only. Cancels are attributed by a
   TIME WINDOW (closures and new ledger rows within ~10s of a cancel
   request classify as canceled, and in-window ledger rows never alert as
   sold) - id matching is only a bonus. Ledger dedup counts SIGNATURE
   OCCURRENCES: identical (auctionID, qty, gold) rows coexist for repeat
   partial sales of one listing; growth, not presence, is the sale signal.
6. **Browse full read** (empty `SendBrowseQuery`) works from script but paging
   stalled at page 1 in our probe; the channel is NOT used. Favorites are
   untouched by policy.
7. **ItemKeyInfo field names**: this fork returns `itemName` (retail spells
   it `name`) - the name chain reads both. Display names resolve: own-lot
   itemLink seeds first (free, exact), then GetItemKeyInfo, then
   C_Item.GetItemInfo; cold misses queue a server request and re-resolve on
   ITEM_KEY_ITEM_INFO_RECEIVED (unpaced re-probes are a request flood).
   Own ITEM lots carry the full hyperlink; commodity records do not.

Still to verify in game: `separateOwnerItems=true` commodity queries from
script still pass the gate and return the separated shape; `RefreshItemSearchResults` from script for held keys
(the core probes it once per session - `/vut probe` re-runs); stacked ITEM
lot `buyoutAmount` total-vs-unit; `COMMODITY_PURCHASED` seller-side payload
(the ledger already covers sales).

## Structure

```
VersaUndercutTracker/          the addon folder (full name; TOC title is VUT)
  domain/                      pure Lua, NO game API (luacheck-enforced)
    types.lua                  boundary validators, key identity, money
    config.lua                 settings defaults/clamps, untrusted coercion
    ownlist.lua                owned-snapshot diff state machine + ledger
    queue.lua                  match-order verdicts (commodity/item)
    alerts.lua                 severity map, cooldown gate, message text
    core.lua                   orchestration (driven beats, transitions)
  ports/                       @meta contract docs only (inbound/outbound)
  adapters/outbound/           ah_owned, ah_market, notify_* (chat/sound/
                              flash/toast/bus), savedvars, clock, item_info
  adapters/inbound/           events (sole AH event registrar + cancel
                              post-hook), timer driver, console API, slash
  bootstrap.lua                composition root (ADDON_LOADED; only place
                              that instantiates adapters and injects ports)
VUTProbe/                      dev-only dump probe (packaged separately)
spec/                          busted specs (pure domain; run via shim)
scripts/                       gates: run_tests.lua (busted shim),
                              check_toc.lua, assert_lls_clean.lua,
                              bootstrap-tools.sh, ci_local.sh
```

Naming: the addon is `VUT` everywhere - TOC title, `_G.VUT` namespace,
`VUTDB` SavedVariables, `/vut` slash, `/run VUT.*` machine API, `VUTProbe`
dev addon. The FOLDER (and TOC filename, and the ADDON_LOADED name) keep the
full name `VersaUndercutTracker`. Never use the old `Versa` prefix
elsewhere.

Hexagonal rules (CI-enforced via `.luacheckrc` file rules):
- `domain/` and `ports/` get NO game globals beyond the `VUT` namespace.
- Adapters validate raw game payloads into domain types at the boundary
  (`Types.sanitize*`); malformed input is dropped, never repaired inside.
- The core owns POLICY (what to poll, when to alert, verdict transitions);
  adapters own MECHANICS (wire sends, frames, timers, persistence).
- Alert wording lives in `domain/alerts.lua`; channel adapters only render
  what `alert.routing` enables.
- Everything notified/alerted flows through the NotifierBus with routing
  decided by the domain config - channels never re-decide.

## Taint posture

Read-only plus cosmetic writes on OWN frames only. The only interactions with
Blizzard objects: event registration, `hooksecurefunc` POST-hooks
(`C_AuctionHouse.CancelAuction`), reading `AuctionHouseFrame` data APIs, and
`button:Click()` on rendered Auctions summary rows (runs Blizzard's own
handler - the proven gate-clean path; never call frame mixin methods from
addon context, the search gate refuses those queries). Flash/toast frames are
ours; nothing touches shared fade/flash tables or Blizzard containers.

## Gates (every change, before commit)

```
bash scripts/bootstrap-tools.sh   # once: StyLua 2.6.0 + LuaLS 3.19.1
bash scripts/ci_local.sh          # stylua --check, tests, TOC, LLS
```

- StyLua formatting is canonical (spaces, indent 4, double quotes, col 120,
  Unix line endings) - never hand-format.
- LuaLS `--checklevel=Warning`: ZERO reported problems.
- luacheck clean; a new game global goes into BOTH `.luacheckrc` and
  `.luarc.json` allowlists in the same change.
- Every pure-logic change ships specs; the full local gate must pass.
- `## Interface:` in the TOC matches the target client (`16001, 120100`).
- In-game validation with `/console scriptErrors 1` after touching anything
  near Blizzard frames; taint errors surface late and silently.

## Conventions

- Lua 5.1 (no `goto`, `unpack` not `table.unpack`).
- Session clock via `ClockPort:now()` (GetTime); baselines, cooldown stamps
  and verdicts are SESSION state by design - only settings persist
  (account-wide `VUTDB`, settings only, coerced on load).
- The `/run VUT.*` machine API and `/vut` slash share the console adapter;
  every settings write goes through `Config.coerce` on a candidate copy,
  mutates the shared table in place, persists, then restarts timers.
- Alert kinds: undercut, tied, sold, expired, canceled, lowqty, noactive,
  recovered. Market alerts are transition-only plus worsening (a deeper
  undercut or more units/listings ahead of an existing tie re-alerts,
  cooldown-gated; improvements stay quiet); sold alerts dedup closure-vs-ledger
  by quantity tag.
