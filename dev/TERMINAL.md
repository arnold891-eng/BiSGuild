# BiS Guild - the raider terminal (plan, 16 Oct 2026)

Arn, 16 Oct: a Bloomberg Terminal for the guild. "I want to type a raider name, show all the gear they
have and what gear they need for BiS, what their attendance is, how much they consume - what we used
to put into the raider sheet and LC sheet." The references are his two old pages - Heathens Loot
Council (roster armory, loot history, where BiS drops, officer sheet) and Heathens Raid Prep (consumes,
gear issues, cooldowns, deaths per night) - and the Terminal's layout: tickers, panels, typed
`<NAME> <TYPE> GO` commands, function keys. Built in BiSTheme colours: borrow the shape, not the look.

## Shape (borrowed from Bloomberg's API: services, topics, fields)

- **Topics**: a raider (`KUMLUST <RAIDER> GO`), a boss (`RAGNAROS <BOSS> GO` - "it's like its own
  company ticker"), a rank.
- **Providers** answer fields for a topic, one per source, so a new source never changes a panel:
  the log report (gear, issues, attendance, consumes, deaths, boss kills), BiS Loot's ledger (loot
  won, drops per boss), LibBiSComm (live map spots, who's online), the guild roster (rank, class),
  later BiS lists.

## Steps

1. **Log reader** - DONE 16 Oct (dev/logreport.py + Tools/logreport.ps1, parity-tested by
   dev/test_logreport.py + dev/same_report.lua): per raider - gear from COMBATANT_INFO (19 slots: id,
   ilvl, enchant, temporary enchant = weapon oil, gems), "no enchant" flags (dev/gearcheck.txt),
   attended nights, consumes (flask / elixirs / food / weapon / in-pull potions), deaths; per boss -
   kills, wipes, first kill, best time (ENCOUNTER_END ms), who was there. Written into Data/Report.lua
   as `days`, `cards`, `bosses` beside the old `rows`.
2. **The terminal window**: the raider card (armory + attendance + consumes + issues + loot), the boss
   page, a ticker along the top, function keys for views, a WHERE panel (guild map spots from
   LibBiSComm - "a map too showing where all the raiders are at").
3. **Sharing** - BUILT 16 Oct, not yet seen in game (Core/Store.lua keeps `BiSGuildDB.record`,
   Core/Share.lua talks "GLOG" on the guild channel; officers = guild rank index <= 1, `officerRank`;
   a 25-raider night is 8 parts, one every 2 s). Arn: "all this data is from my computer - if I miss one raid night what stops it":
   any raider who logs writes the same lines for the whole raid, so any officer can import a night;
   BiS Guild shares nights over LibBiSComm and every member keeps them in BiSGuildDB (saved variables
   survive restarts again - Arn, 16 Oct: ForeverAuras no longer needs re-importing). Merge by date;
   the same night from two loggers counts once (the fuller copy). Late joiners catch up from whoever
   has more. Officers' history.json stays the backup.
4. **Invites from the terminal** (Arn: "it'll plug into or use its own invite to raid module like
   BiS Tools"): BiS Tools' party list, rank waves and confirm list when it is loaded, BiS Guild's own
   otherwise; plus an IMPORT box for a Discord raid tool's roster code ("someone can import a code to
   build a roster and one click invites them").
5. **BiS lists** - later (Arn chose "later, from a site"): wowsims exports pasted in per raider, and/or
   lists shipped as data with releases (the Loon's BiS way). Then the armory gets BiS / want / won tags
   and the boss page "gear we still need from it".

## Open questions

- ~~Enchant ids 8481-8486~~ ANSWERED 16 Oct: Forever's leatherworking armor kits (Arn's screenshot:
  "Mystic Medium Armor Kit", item 252436 - spell power +2 and armor +16 on chest, legs, hands or
  feet), so they are real enchants and "no enchant" is right to pass them. Later: a list of
  raid-worthy enchant ids would let the card say "kit only" - the old sheet's cheap-enchant column.
- Potion spell names in consumables.txt are the classic ones, unverified on Forever until a raid log.
