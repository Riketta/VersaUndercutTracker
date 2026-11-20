---@meta
-- VUT - outbound (driven) ports. The core drives these
-- contracts; implementations live in adapters/outbound and are wired in
-- bootstrap.lua. Documentation only: no runtime code, but the TOC lists the
-- file so the annotations load in game for tooling parity with CI.

--- Own-auction reads and refreshes. Script-side QueryOwnedAuctions passes the
--- fork's gate (verified: ~0.1s answer), so the owned channel needs no UI
--- involvement. read() returns SANITIZED OwnLot records - the adapter owns
--- commodity-ness resolution and boundary validation.
---@class OwnedAuctionsPort
---@field refresh fun(self: any): boolean fire QueryOwnedAuctions; rows land via OWNED_AUCTIONS_UPDATED
---@field read fun(self: any): OwnLot[] sanitized active + ledger records

--- Market competitor reads. Commodity queries pass the fork's gate from
--- script; item queries are REFUSED from script (verified) - the item paths
--- are best-effort surfaces whose availability the core probes at runtime:
--- refreshItem may pass for already-known keys (probe decides), and
--- clickItemScan drives the Blizzard summary row's own OnClick handler (the
--- proven gate-clean path). Injected nil-or-complete per method: the core
--- checks supportsItemClick before using the click path.
---@class MarketPort
---@field queryCommodity fun(self: any, itemID: number): boolean
---@field readCommodityRows fun(self: any, itemID: number): MarketRow[]
---@field refreshItem fun(self: any, itemKey: table): boolean attempt RefreshItemSearchResults (probe-gated)
---@field readItemRows fun(self: any, itemKey: table): ItemRow[]
---@field supportsItemClick (fun(self: any): boolean)|nil
---@field clickItemScan (fun(self: any, itemID: number): boolean, string|nil)|nil click the Auctions summary row for this itemID

--- Fan-out bus: routes one alert to the channel adapters enabled by
--- alert.routing. Channel adapters render; they never re-decide routing.
---@class NotifierPort
---@field dispatch fun(self: any, alert: AlertEvent)

--- Session clock (GetTime-based).
---@class ClockPort
---@field now fun(self: any): number

--- Item metadata (names for alerts; commodity-ness for owned-lot ingest).
---@class ItemInfoPort
---@field name fun(self: any, itemID: number): string|nil nil until resolved (#id fallback)
---@field isCommodity fun(self: any, itemKey: table): boolean|nil nil until the client has the data
---@field learnFromLink fun(self: any, itemID: number, itemLink: string|nil) seed an exact name from an item link

--- Settings persistence (account-wide SavedVariables). load() runs the blob
--- through Config.coerce - the blob is never trusted, never aliased.
---@class PersistencePort
---@field load fun(self: any): Settings
---@field save fun(self: any, settings: Settings)
