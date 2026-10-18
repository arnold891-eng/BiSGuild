# Nights per raid, merged kill by kill (17 Oct 2026)

Arn: "all the officers run the power shell and their logs are slightly different ... will BiS Guild
be able to determine all these happened at the same time and even though they're slightly
different, reconcile". Approved the same night ("yeah can do that"), on branch `feat/nights-per-raid`,
to be tried on a real raid log before release (0.2.0).

## What was wrong (0.1.x)

- A night was a DATE. Two raids on one date (two teams, MC then Onyxia) were ADDED into one night,
  and the attendance rule (present for half the kills) then used both raids' kills - someone at one
  of two raids could lose the night.
- Two officers' copies of a night were never merged: `S.Fuller` kept the fuller WHOLE copy, so a
  boss only the other officer saw was dropped.
- The record held totals only (per raider per night, per boss name) - nothing per kill, no times,
  no instance - so a boss-by-boss merge was impossible from what was saved.

## What the log gives (measured on Arn's logs, 17 Oct)

    10/5/2026 18:32:28.909-7  ENCOUNTER_START,3480,"Saltspine",1,5,2998        Forever 1.60.1
    9/29/2026 17:25:49.727-7  ENCOUNTER_START,601,"High Warlord Naj'entus",4,25,564,5   TBC 2.5.6
    10/5/2026 18:26:47.468-7  ZONE_CHANGE,2998,"Excavation Site: Wetlands",1

- every line's time has the date, the year and the UTC offset: one officer's log lines up with
  another's EXACTLY, in any time zone
- ENCOUNTER_START: encounter id, name, difficulty, group size, INSTANCE id
- ZONE_CHANGE: instance id and its NAME

## The model (v2)

A PULL - kept for every pull of a raid boss (dungeons left out unless --dungeons):

    { t = <UTC epoch of ENCOUNTER_START>, e = <encounter id>, b = "<boss>", i = <instance id>,
      k = 1|0 (killed), ms = <fight length>,
      r = { [name] = flags }    -- who stood in it (COMBATANT_INFO); counted pulls only
      d = { [name] = deaths },  p = { [name] = potions } }        -- every pull, wipes too

    flags: 1 ready (flask, or two elixirs/scrolls, AND food), 2 flask, 4 elixir pair (no flask),
           8 food, 16 weapon oil/stone, 32 main hand worn

A NIGHT is ONE RAID: the pulls of one instance, in time order, until a gap of more than 3 hours or
a boss already killed in it dies again (one lockout cannot kill a boss twice).

    key   = "YYYY-MM-DD <instance id>"  (date of the first pull, in the logger's own local time)
    night = { v = 2, i = <instance>, zone = "<instance name>", start = <UTC of first pull>,
              pulls = { PULL, ... },                      -- the truth
              kills, raiders, bosses }                    -- DERIVED from pulls, same shape as v1

Derivation (identical in logreport.py, logreport.ps1 and Core/Store.lua - the suites hold them to it):
- kills = counted pulls; raiders[n].present = counted pulls n stood in; .pulls = the same;
  .ready/.flask/.elixir/.food/.weapon/.weaponSeen = those flags over them; .pots/.deaths = sums over
  every pull; bosses[b] = { pulls = all pulls, kills, best = fastest kill ms, killers = sorted, one
  name per kill stood in }

## Merging two copies (Core/Store.lua)

The same raid = same instance, and at least one pull of the same encounter within 3 minutes (UTC).
The union of pulls: a pull in both copies counts once (the copy that saw more raiders in it wins
that pull); a pull in one copy only is added. Then derive again. Stored under the key already there.

Old (v1, date-keyed) nights stay as they are. A v2 night of date D removes a v1 night of D (the v1
one was every raid of D added together); a v1 night arriving for a date that has v2 nights is refused.

## Sharing (Core/Share.lua)

New commands, so 0.1.x copies ignore them: HAVE2 (key + pull count + a check number over the pull
times), WANT2, NIGHT2 (raider names once, then each pull compactly). A night someone else has MORE
or DIFFERENT pulls of is asked for and merged; merging both ways converges. v1 HAVE/WANT/NIGHT: no
longer sent; a v1 NIGHT is still taken under the rule above.

## The paste and the notebook (17 Oct 2026)

Arn: a notebook "so people can just drag and drop their log ... hit run ... something to paste".
`dev/BiSGuild.ipynb` (Colab; link on the CurseForge page) fetches `logreport.py` + its two lists from
the NEWEST RELEASE TAG on GitHub (never main), reads the uploaded logs (zip or txt) and prints
`logreport.paste_text`: `BiSGuild paste 2` / `R~key~<EncodeRaid>` / `G~name~date~<EncodeGear>` /
`END~lines~bytes` - "~" because a WoW edit box doubles "|", BYTES because Lua's # counts bytes (a
name with an accent broke the first real paste). In game `/bisg paste` (Core/Window.lua U.ShowPaste)
-> `X.ImportPaste` -> `S.Put` per raid. Held together by `dev/paste_matches.lua` (run from
`dev/test_logreport.py`). The notebook needs no account of ours; each officer runs it under their own
Google account. Change the notebook only when its own steps change - releases reach it by themselves.

## Readers

Keys sort as strings and still begin with the date, so the order holds. Anywhere a key is SHOWN it
goes through `S.Label(key)` ("2026-10-16 Black Temple"). Attendance counts raids, not dates.
BiSGuildAPI: `Nights()` / `Night(key)` answer keys; documented, version up.
