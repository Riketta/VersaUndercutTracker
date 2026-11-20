# VUT (VersaUndercutTracker)

Own-auction queue tracker for the Classic Era (Camelot 1.60.1) auction house.
Watches your active listings and tells you the moment you are no longer first
in the commodity buyout queue - undercut, tied with newer sellers ahead of
you, sold out, running low, or expired - through chat, sound, screen flash
and toast channels.

## How it works

- **Owned polling** (`C_AuctionHouse.QueryOwnedAuctions`, ~10 s cadence):
  the owned snapshot diff is the lifecycle source of truth - new lots,
  partial sales (with gold, from the status-1 sale ledger), expiries,
  cancels, low-quantity percentages.
- **Commodity rotation** (`SendSearchQuery`, one query per ~8 s beat,
  rotating across owned items - the channel cost is constant regardless of
  inventory size; each item's latency is beat x item count): competitor rows
  in match order (price ASC, newest-first within a tier) produce the
  verdict: FIRST / TIED (N units ahead of you) / UNDERCUT (by X).
- **Item channel** (script item queries are gate-refused on this client):
  a per-session probe tries `RefreshItemSearchResults`; if the gate refuses,
  items degrade to passive reads of whatever results the client holds (the
  summary-click rotation is an explicit opt-in).
- **Alerts** are transition-only: entering a bad state alerts once (with a
  per-kind cooldown); recovering to first-in-queue gets a quiet notice.

## Quick start

1. Copy `VersaUndercutTracker/` into `Interface/AddOns`, enable, reload.
2. Open the auction house - monitoring runs only while it is open.
3. `/vut help` - status, manual scan, pause, settings, test alerts.

## Commands

```
/vut status                      session, lots, verdicts, channel state
/vut scan                        refresh owned + poll every commodity now
/vut pause | resume
/vut probe                       re-run the item refresh gate probe
/vut set owned 10                owned poll seconds (5..120)
/vut set commodity 8             per-item commodity beat (5..300)
/vut set rotation 30             item beat (10..600)
/vut set lowpct 25               low-quantity % threshold (0 = off)
/vut set items auto|passive|click|off
/vut set sound AUCTION_WINDOW_OPEN   SOUNDKIT symbolic name
/vut set soundfile Interface\\AddOns\\Mine\\ding.mp3   (or empty)
/vut set flash 1.5               flash seconds
/vut set toast 6                 toast seconds
/vut cooldown undercut 120       per-kind alert cooldown
/vut channel undercut.sound off  per-kind channel toggles
/vut test undercut               dispatch a test alert
```

The same surface is the `/run VUT.*` machine API (`VUT.Set`, `VUT.Status`,
`VUT.Test`, ...). Settings persist account-wide; quantity baselines and
verdicts are per-session (a fresh login re-anchors the low-quantity baseline
at whatever remains).

## Development

Hexagonal architecture (pure domain, ports as contracts, thin adapters,
single composition root). Gates: StyLua, luacheck (with boundary rules),
busted specs, TOC coverage, LuaLS strict - see `AGENTS.md` and `scripts/`.
`VUTProbe/` is the raw-payload dump probe used to pin the client's wire
behavior (see its README for the verified-facts log). The addon folder keeps
the full name `VersaUndercutTracker`; the addon itself is `VUT` (title,
`/vut`, `/run VUT.*`, `VUTDB`).
