# VersaProbe

Throwaway diagnostic addon for the VersaUndercutTracker R&D phase. It dumps
the raw `C_AuctionHouse` payloads behind the Auctions tab (own lots, per-item
listings, browse rows, lifecycle events) to chat so we can pin the exact wire
shapes before writing the real adapters.

Read-only: event registration + API reads + `print`. No hooks, no frame
writes, no protected calls. Not part of the shipped addon; excluded from
packaging.

## Install

Copy the `VersaProbe` folder into the game's `Interface/AddOns` directory,
enable it in the addon list (per character), reload.

Recommended before capturing: `/console scriptErrors 1`.

## Usage

- `/vp help` — command list
- `/vp on` / `/vp off` — passive event dumps master switch (default on)
- `/vp sys` — also log `CHAT_MSG_SYSTEM` lines (sold/expired system messages)

## Capture checklist

Verified so far (2026-11 sessions):

- Commodity/item search row shapes; self-marking via `owners={"player"}` +
  `containsOwnerItem`/`numOwnerItems`; merged multi-owner rows.
- Commodity match order: price ASC, NEWEST first within a tier (user
  confirmed: last placed sells first - the delivered row order IS the match
  order; no reversal in the queue math).
- Owned list: `status 0=Active, 1=Sold`; Sold rows are a per-sale ledger
  (buyoutAmount = qty x unit price there, while Active commodity rows carry
  the UNIT price); Sold rows can repeat an auctionID; row order unstable;
  `GetOwnedAuctionTypes` counts Active keys only.
- `QueryOwnedAuctions` from script: PASS (~0.1s answer).
- Empty `SendBrowseQuery` from script: PASS (first 500 rows; paging beyond
  page 1 stalled in our probe - the browse channel is DROPPED from the
  tracker design, commodities use direct search instead).
- `AUCTION_CANCELED` payload (e.g. 110) is NOT an auctionID on this fork;
  `AUCTION_HOUSE_AUCTION_CREATED` did not fire on a commodity post; a
  `THROTTLED_MESSAGE_DROPPED` fired right after a cancel - the owned-snapshot
  diff is the lifecycle source of truth, events are hints only.

Still nice to capture (optional):

1. **COMMODITY_PURCHASED** - fire on the seller when a real sale happens with
   the probe loaded and the AH open (sale-ledger Sold rows already cover
   this; the event would be a bonus).
2. **Item undercut shape** - alt posts an item cheaper than the circlet;
   click the circlet in the summary; `/vp queuei`.
3. **Stacked item lot** - whether owned `buyoutAmount` is total or per-unit
   for non-commodity stacks (commodities confirmed per-unit on Active rows).
