#!/usr/bin/env python3
"""BiSGuild :: dev/logreport.py - turn a WoW combat log into two numbers per raider.

Arn, 4 Oct 2026: "the logs also sit on my computer as a text file but every program that has ever
tried to open it crashes".

They crash because they read the whole thing first. His was 109 MB and 393,922 lines. This never
holds more than one line at a time, so the size stops mattering - a 2 GB log costs more seconds and
the same memory.

WHAT IT GETS OUT, and why it needs nothing else:

  * ENCOUNTER_START / ENCOUNTER_END carry the boss, the size and - on END - whether it died.
    A wipe is not a kill, and the log says which is which.
  * COMBATANT_INFO is written for every raider AT THE PULL, and its last bracket is their whole
    buff list as spell ids. That is attendance and consumables in the same line.
  * SPELL_AURA_APPLIED carries both the spell id AND its name, so the log NAMES ITS OWN IDS.
    Nothing here is a remembered flask list: "Flask of Relentless Assault" is in the file.

So both numbers come out of one pass over one file, with no website, no upload and no guessing.

    python dev/logreport.py <WoWCombatLog.txt> [--kills-only] [--paste]

--paste prints the one line to hand the addon.
"""

import re
import sys
from collections import defaultdict

# WHICH AURAS COUNT comes from consumables.txt beside this file, NOT from a rule here.
#
# The first version of this script matched "^Flask of" and reported half the raid at nought percent.
# The buff does not carry the item's name: "Flask of Chromatic Wonder" shows up as "Chromatic
# Wonder", and the Shattrath flasks as "Relentless Assault of Shattrath". A regex misses those and
# marks real flasks as nothing, which looks exactly like data.
#
# So the list is a file, seeded from a real log, and --review prints anything it has never been told
# about so it can be added rather than silently ignored.
import os

LIST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "consumables.txt")


def load_kinds(path=LIST):
    kinds = {}
    try:
        with open(path, "r", encoding="utf-8") as fh:
            for raw in fh:
                line = raw.split("#", 1)[0].strip()
                if not line:
                    continue
                parts = line.split(None, 1)
                # potion: a CAST inside a boss pull (health/mana potions, healthstones, runes) -
                # the old raid-prep sheet's rule; drunk between pulls does not count
                if len(parts) == 2 and parts[0] in ("flask", "elixir", "scroll", "food", "potion"):
                    kinds[parts[1].strip().lower()] = parts[0]
    except OSError:
        pass
    return kinds


def short(name):
    """Kumlust-Dreamscythe-US -> Kumlust."""
    return name.split("-", 1)[0].strip('"')


def brackets(body):
    """The top-level [...] groups of a COMBATANT_INFO line, in order: talents, gear, auras (Forever,
    measured 16 Oct 2026 on Arn's 5 Oct log). Nested (...) tuples stay inside their bracket."""
    out, depth, start = [], 0, None
    for i, ch in enumerate(body):
        if ch == "[":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0 and start is not None:
                out.append(body[start:i + 1])
                start = None
    return out


# THE SLOTS, in the order COMBATANT_INFO writes them (WoW's inventory order, 1-19)
SLOTS = ["head", "neck", "shoulder", "shirt", "chest", "waist", "legs", "feet", "wrist", "hands",
         "finger1", "finger2", "trinket1", "trinket2", "back", "mainhand", "offhand", "ranged", "tabard"]


def gear_of(body):
    """What a raider wore at the pull (Arn, 16 Oct: "type a raider name, show the gear they have").
    COMBATANT_INFO's gear bracket: 19 of (itemId, itemLevel, (permanent, temporary, onUse), (bonus
    ids), (gem ids)). The TEMPORARY enchant is the weapon's oil or stone - the old raid-prep sheet's
    weapon check, read from the same line. Returns [[id, ilvl, enchant, temp, gems], ...] or None."""
    import json
    b = brackets(body)
    if len(b) < 3:
        return None
    try:
        raw = json.loads(b[-2].replace("(", "[").replace(")", "]"))
    except ValueError:
        return None
    out = []
    for t in raw:
        if not isinstance(t, list) or len(t) < 2:
            out.append([0, 0, 0, 0, []])
            continue
        ench = t[2] if len(t) > 2 and isinstance(t[2], list) else []
        gems = t[4] if len(t) > 4 and isinstance(t[4], list) else []
        out.append([int(t[0] or 0), int(t[1] or 0), int(ench[0]) if len(ench) > 0 else 0,
                    int(ench[1]) if len(ench) > 1 else 0, [int(g) for g in gems if g]])
    return out if len(out) >= 16 else None


GEARCHECK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gearcheck.txt")


def load_gearcheck(path=GEARCHECK):
    """Which slots should carry an enchant - DATA, like the consumables (gearcheck.txt): what Forever
    lets you enchant is the guild's call, not a rule in the code."""
    want = []
    try:
        with open(path, "r", encoding="utf-8") as fh:
            for raw in fh:
                line = raw.split("#", 1)[0].strip()
                parts = line.split()
                if len(parts) == 2 and parts[0] == "enchant" and parts[1] in SLOTS:
                    want.append(parts[1])
    except OSError:
        pass
    return want


def issues_of(gear, want):
    """The old sheet's red flags that a log can prove: an enchantable slot with an item and no
    enchant. (Cheap enchants and wrong gems need a Forever enchant/gem list nobody has written.)"""
    out = []
    if not gear:
        return out
    for slot in want:
        i = SLOTS.index(slot)
        if i < len(gear) and gear[i][0] and not gear[i][2]:
            out.append({"slot": slot, "item": gear[i][0], "what": "no enchant"})
    return out


def auras_of(line):
    """The spell ids in COMBATANT_INFO's last bracket: (caster, spellId, _) repeated."""
    start = line.rfind("[")
    end = line.rfind("]")
    if start == -1 or end == -1 or end < start:
        return []
    inner = line[start + 1:end]
    if not inner:
        return []
    parts = inner.split(",")
    out = []
    # triplets; a malformed tail is skipped rather than guessed at
    for i in range(1, len(parts), 3):
        try:
            out.append(int(parts[i]))
        except (ValueError, IndexError):
            pass
    return out


def main(path, kills_only=True, paste=False, review=False, write=False, include_dungeons=False):
    kinds = load_kinds()
    if not kinds:
        print("consumables.txt is empty or missing - nothing can be judged. See %s" % LIST)
        return 2
    names = {}                       # spell id -> spell name, learned from the log itself
    guid_name = {}                   # player guid -> short name
    pulls = []                       # [{boss, kill, who: {guid: [auraIds]}}]
    cur = None

    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            # "10/4/2026 17:31:57.622-7  EVENT,..." - the event name is after the double space
            sep = line.find("  ")
            if sep == -1:
                continue
            body = line[sep + 2:].rstrip("\n")
            comma = body.find(",")
            event = body[:comma] if comma != -1 else body

            if event == "ENCOUNTER_START":
                # ENCOUNTER_START,<id>,"<name>",<difficulty>,<groupSize>,<instance>,...
                # The name is quoted and could contain a comma, so it is matched rather than split.
                #
                # A DUNGEON BOSS IS NOT A RAID NIGHT (5 Oct 2026). The addon learned this when Arn
                # said "there are no raids in wow forever yet" - and the reader never did, so a
                # five-man log would have produced attendance that looked exactly like real raid
                # data. groupSize is the honest line: 25 for Black Temple, 5 for a dungeon.
                m = re.match(r'ENCOUNTER_START,(\d+),"(.*?)",(-?\d+),(-?\d+)', body)
                if m:
                    boss, size = m.group(2), int(m.group(4))
                else:
                    f = body.split(",")
                    boss, size = (f[2].strip('"') if len(f) > 2 else "?"), 0
                cur = {"boss": boss, "size": size, "kill": False, "who": {}, "gear": {},
                       "deaths": defaultdict(int), "pots": defaultdict(int)}
                pulls.append(cur)

            elif event == "ENCOUNTER_END":
                f = body.split(",")
                if cur is not None:
                    cur["kill"] = len(f) > 5 and f[5].strip() == "1"
                    # ENCOUNTER_END,id,"name",difficulty,size,success,fightTime(ms)
                    try:
                        cur["ms"] = int(f[6]) if len(f) > 6 else 0
                    except ValueError:
                        cur["ms"] = 0
                cur = None

            elif event == "COMBATANT_INFO":
                if cur is not None:
                    guid = body.split(",")[1]
                    cur["who"][guid] = auras_of(body)
                    g = gear_of(body)
                    if g:
                        cur["gear"][guid] = g

            elif event == "UNIT_DIED":
                # UNIT_DIED,src..(4),destGUID,"destName",... - a raider dying INSIDE a pull
                f = body.split(",")
                if cur is not None and len(f) > 6 and f[5].startswith("Player-"):
                    cur["deaths"][f[5]] += 1
                    guid_name[f[5]] = short(f[6].strip('"'))

            elif event == "SPELL_CAST_SUCCESS":
                # ...,srcGUID,"srcName",..,spellId,"Spell Name" - a potion or healthstone used in a pull
                f = body.split(",")
                if len(f) > 10:
                    try:
                        names[int(f[9])] = f[10].strip('"')
                    except ValueError:
                        pass
                    if cur is not None and f[1].startswith("Player-")                             and kinds.get(f[10].strip('"').lower()) == "potion":
                        cur["pots"][f[1]] += 1
                        guid_name[f[1]] = short(f[2].strip('"'))

            elif event.startswith("SPELL_") and "_AURA_" in event:
                # ...,spellId,"Spell Name",school,TYPE - learn the name for the id
                f = body.split(",")
                if len(f) > 11:
                    try:
                        names[int(f[9])] = f[10].strip('"')
                    except ValueError:
                        pass
                    for guid_i, name_i in ((1, 2), (5, 6)):
                        g, n = f[guid_i], f[name_i].strip('"')
                        if g.startswith("Player-") and n:
                            guid_name[g] = short(n)

    counted = [p for p in pulls if p["kill"]] if kills_only else pulls
    dungeons = [p for p in counted if 0 < p.get("size", 0) <= 5]
    if not include_dungeons:
        counted = [p for p in counted if p not in dungeons]
    if not counted:
        print("no %s found in that log." % ("boss kills" if kills_only else "pulls"))
        if dungeons and not include_dungeons:
            print("  %d five-man boss kill(s) were left out - a dungeon boss is not a raid night."
                  % len(dungeons))
            print("  --dungeons counts them, which is useful for testing and wrong for a record.")
        return 1

    present = defaultdict(int)
    prepared = defaultdict(int)
    unknown = defaultdict(set)
    # THE RAIDER CARD'S NUMBERS (Arn, 16 Oct: "what we used to put into the raider sheet and lc
    # sheet"): per raider this night - each consumable on its own, the weapon's oil or stone, the
    # gear they wore, deaths and potions. Gear, deaths and potions read EVERY pull of the night (a
    # wipe is still a death and still a potion); the consumables stay on the kills, as before.
    detail = defaultdict(lambda: {"pulls": 0, "flask": 0, "elixir": 0, "food": 0, "weapon": 0,
                                  "weaponSeen": 0, "pots": 0, "deaths": 0, "gear": None})
    nightpulls = [p for p in pulls if include_dungeons or not (0 < p.get("size", 0) <= 5)]
    for p in nightpulls:
        for guid, n in p["deaths"].items():
            detail[guid_name.get(guid, guid)]["deaths"] += n
        for guid, n in p["pots"].items():
            detail[guid_name.get(guid, guid)]["pots"] += n
        for guid, g in p["gear"].items():
            detail[guid_name.get(guid, guid)]["gear"] = g        # the last pull's gear wins
    for p in counted:
        for guid, auras in p["who"].items():
            who = guid_name.get(guid, guid)
            present[who] += 1
            dt = detail[who]
            dt["pulls"] += 1
            g = p["gear"].get(guid)
            if g and len(g) > 15 and g[15][0]:
                dt["weaponSeen"] += 1
                if g[15][3]:
                    dt["weapon"] += 1
            flask = elixirs = food = 0
            for sid in auras:
                nm = names.get(sid, "id %d" % sid)
                kind = kinds.get(nm.lower())
                if kind == "food":
                    food += 1
                elif kind == "flask":
                    flask += 1
                elif kind == "elixir" or kind == "scroll":
                    # Arn, 4 Oct: scrolls count in TBC, to be decided for Forever. A scroll is worth
                    # an elixir towards the pair - somebody who brings scrolls instead of elixirs has
                    # still turned up prepared. consumables.txt is where that is changed.
                    elixirs += 1
                else:
                    unknown[nm].add(guid)
            if (flask or elixirs >= 2) and food:
                prepared[who] += 1
            dt["flask"] += 1 if flask else 0
            dt["elixir"] += 1 if (not flask and elixirs >= 2) else 0
            dt["food"] += 1 if food else 0

    if review:
        # EVERYTHING IT HAS NEVER BEEN TOLD ABOUT. A raid buff and an unlisted flask look the same
        # from here, so they are all printed and a person decides - that is the whole point of the
        # file. Rarest first: a buff twenty-four people have is the paladin's, one two people have
        # is something they bought.
        print("auras not in consumables.txt, rarest first:\n")
        for nm, gs in sorted(unknown.items(), key=lambda kv: len(kv[1])):
            print("  %-34s %d raider(s)" % (nm[:34], len(gs)))
        print("\nAdd the consumables to %s and run again." % LIST)
        return 0

    total = len(counted)
    zones = sorted({p["boss"] for p in counted})

    # THE RECORD, not just last night (5 Oct 2026). Arn: "how are we going to keep track of how
    # people are doing with attendance if it wipes the data when i reload?" The reload was never the
    # problem - Data/Report.lua is a file. The hole underneath the question was that each run read
    # one log and OVERWROTE the report, so it only ever said what happened last night.
    #
    # It lives in WTF: deploy.sh wipes the addon folder, and this client hands back no saved
    # variables at all, so those were the two places it could not go. One log is one night, keyed by
    # the log's filename, so re-running the same log replaces its night instead of counting it twice.
    nights = read_history(path)
    stamp = ""
    m = re.search(r"WoWCombatLog-(\d{2})(\d{2})(\d{2})_", os.path.basename(path))
    if m:
        stamp = "20%s-%s-%s" % (m.group(3), m.group(1), m.group(2))
    nights[os.path.basename(path)] = {
        "log": os.path.basename(path), "date": stamp,
        "zones": ", ".join(zones), "kills": total,
        "present": dict(present), "ready": dict(prepared),
        "detail": {who: dict(d) for who, d in detail.items()},
        "bosses": boss_night(nightpulls, guid_name),
    }
    write_history(path, nights)

    # A RAID DAY IS THE WHOLE DAY (Arn, 5 Oct: "i guess we can count a raid day as the whole day not
    # just 3 hr window some people run more than 3 hours").
    #
    # Stored per LOG, because that is what makes re-running the same log replace its entry instead
    # of counting it twice. Counted per DAY: logs from one date are added together first, so a
    # six-hour clear in one log and a client restarted halfway through a raid both come out as
    # exactly one night. Each key doing the job it is good at.
    days = {}
    for n in nights.values():
        key = n.get("date") or n["log"]        # an unparseable filename is its own day
        d = days.setdefault(key, {"kills": 0, "present": defaultdict(int), "ready": defaultdict(int)})
        d["kills"] += n["kills"]
        for who, saw in n["present"].items():
            d["present"][who] += saw
            d["ready"][who] += n["ready"].get(who, 0)

    # A NIGHT IS EARNED BY HALF ITS KILLS. present*2 >= kills, never present >= kills/2: three kills
    # and one attendance is 1 against 1.5, and a raid record does not go near floating point.
    earned, seen_pulls, ready_pulls = defaultdict(int), defaultdict(int), defaultdict(int)
    attended = defaultdict(list)                 # who -> the days they earned, for the raider card
    for key, d in sorted(days.items()):
        for who, saw in d["present"].items():
            if saw * 2 >= d["kills"]:
                earned[who] += 1
                attended[who].append(key)
            seen_pulls[who] += saw
            ready_pulls[who] += d["ready"][who]
    raided = max(1, len(days))

    rows = []
    for who in earned:
        rows.append((who, round(100 * earned[who] / raided),
                     round(100 * ready_pulls[who] / seen_pulls[who]) if seen_pulls[who] else 0))
    rows.sort(key=lambda r: (-r[1], -r[2], r[0]))
    cards = build_cards(nights, attended, load_gearcheck())
    bosscards = build_bosses(nights)

    label = "boss kill" if kills_only else "pull"
    print("this log: %d %s(s): %s" % (total, label, ", ".join(zones)))
    print("over %d raid night(s) on record:" % raided)
    print("%-16s %8s %9s" % ("", "attend", "consumes"))
    for who, att, con in rows:
        print("%-16s %7d%% %8d%%" % (who, att, con))

    if paste:
        print()
        print("BISGUILD1|" + "|".join("%s,%d,%d" % r for r in rows))

    if write:
        wrote = write_data(rows, total, zones, path, raided, cards, sorted(days), bosscards)
        print()
        if wrote:
            for w in wrote:
                print("written: %s" % w)
            print("/reload in the client and the numbers are there. Nothing to paste.")
        else:
            print("no BiSGuild addon folder found to write into - is it deployed?")
    return 0


def boss_night(nightpulls, guid_name):
    """A BOSS IS A TICKER (Arn, 16 Oct: "we type in a boss name, it's like its own company ticker -
    who and how many times they have downed the boss"). This night's pulls, kills, fastest kill, and
    who stood in each kill."""
    out = {}
    for p in nightpulls:
        b = out.setdefault(p["boss"], {"pulls": 0, "kills": 0, "best": 0, "killers": []})
        b["pulls"] += 1
        if p["kill"]:
            b["kills"] += 1
            ms = p.get("ms", 0)
            if ms and (not b["best"] or ms < b["best"]):
                b["best"] = ms
            for guid in p["who"]:
                b["killers"].append(guid_name.get(guid, guid))
    return out


def build_bosses(nights):
    """ONE PAGE PER BOSS from every night on record: kills, wipes, the nights it died, the first
    kill, the fastest, and how many times each raider was there for the kill."""
    pages = {}
    for n in sorted(nights.values(), key=lambda n: (n.get("date") or n["log"])):
        date = n.get("date") or n["log"]
        for boss, b in (n.get("bosses") or {}).items():
            pg = pages.setdefault(boss, {"kills": 0, "wipes": 0, "best": 0, "first": None,
                                         "nights": [], "killers": {}})
            pg["kills"] += b["kills"]
            pg["wipes"] += b["pulls"] - b["kills"]
            if b["kills"]:
                pg["first"] = pg["first"] or date
                if date not in pg["nights"]:
                    pg["nights"].append(date)
            if b.get("best") and (not pg["best"] or b["best"] < pg["best"]):
                pg["best"] = b["best"]
            for who in b.get("killers", []):
                pg["killers"][who] = pg["killers"].get(who, 0) + 1
    return pages


def build_cards(nights, attended, want):
    """ONE CARD PER RAIDER, from every night on record: the gear from the latest night they were
    seen in, its red flags, the nights they attended, their latest night's consumables, and deaths
    and potions over the whole record."""
    cards = {}
    for n in sorted(nights.values(), key=lambda n: (n.get("date") or n["log"])):
        date = n.get("date") or n["log"]
        for who, d in (n.get("detail") or {}).items():
            c = cards.setdefault(who, {"deaths": 0, "pots": 0, "last": None, "gear": None, "gearDate": None})
            c["deaths"] += d.get("deaths", 0)
            c["pots"] += d.get("pots", 0)
            if d.get("pulls"):
                c["last"] = {k: d.get(k, 0) for k in
                             ("pulls", "flask", "elixir", "food", "weapon", "weaponSeen", "pots", "deaths")}
                c["last"]["date"] = date
            if d.get("gear"):
                c["gear"], c["gearDate"] = d["gear"], date
    for who, c in cards.items():
        c["attended"] = list(attended.get(who, []))
        c["issues"] = issues_of(c["gear"], want)
    return cards


def history_path(log_path):
    """`<client>/WTF/BiSGuild/history.json` - the one place a deploy does not wipe and a loader this
    client does not run cannot lose."""
    logs_dir = os.path.dirname(os.path.abspath(log_path))
    client = os.path.dirname(logs_dir)
    return os.path.join(client, "WTF", "BiSGuild", "history.json")


def read_history(log_path):
    """Every night on record, keyed by the log it came from. A half-written or hand-edited file is
    started over rather than crashing the run: the numbers are rebuildable from the logs, and a tool
    that dies on its own cache is worse than one that forgets."""
    import json
    try:
        with open(history_path(log_path), "r", encoding="utf-8") as fh:
            got = json.load(fh)
        return {n["log"]: n for n in got.get("nights", []) if n.get("log")}
    except (OSError, ValueError, KeyError, TypeError):
        return {}


def write_history(log_path, nights):
    import json
    p = history_path(log_path)
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8") as fh:
            json.dump({"version": 1, "nights": sorted(nights.values(), key=lambda n: n["log"])},
                      fh, indent=1)
    except OSError as e:
        print("could not write the history (%s): this run counts only itself" % e)


def lua_str(s):
    return '"%s"' % str(s).replace("\\", "\\\\").replace('"', '\\"')


def game_roots(log_path=None):
    """Where the report goes.

    THE CLIENT THE LOG CAME FROM, AND NOWHERE ELSE (5 Oct 2026). This used to write into every
    installed client; Arn read a Forever dungeon log and it overwrote the Black Temple report
    sitting in TBC. A client's raid record is about that client's raids, and quietly replacing one
    set of numbers with an unrelated set is the worst thing a tool like this can do, because the
    numbers still look right.

    `Logs` and `Interface` are siblings inside the client folder, so the log's own path says which
    client it belongs to. The wow-path.txt fallback is only for a log given from somewhere else.
    """
    if log_path:
        logs_dir = os.path.dirname(os.path.abspath(log_path))
        if os.path.basename(logs_dir).lower() == "logs":
            d = os.path.join(os.path.dirname(logs_dir), "Interface", "AddOns", "BiSGuild")
            if os.path.isdir(d):
                return [d]

    here = os.path.dirname(os.path.abspath(__file__))
    bisdev = os.path.join(here, "..", "..", "_bisdev", "wow-path.txt")
    base = os.environ.get("BISWOW")
    if not base:
        try:
            with open(bisdev, "r", encoding="utf-8") as fh:
                base = fh.read().strip()
        except OSError:
            return []
    out = []
    try:
        for flavour in os.listdir(base):
            d = os.path.join(base, flavour, "Interface", "AddOns", "BiSGuild")
            if os.path.isdir(d):
                out.append(d)
    except OSError:
        pass
    return out


def lua_val(v, ind=""):
    """Any of the card's values as Lua: numbers, strings, lists, string-keyed tables."""
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, (list, tuple)):
        return "{ " + ", ".join(lua_val(x, ind) for x in v) + " }"
    if isinstance(v, dict):
        inner = ind + "    "
        parts = []
        for k in sorted(v, key=str):
            if v[k] is None:
                continue
            key = k if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", str(k)) else "[%s]" % lua_str(k)
            parts.append("%s%s = %s," % (inner, key, lua_val(v[k], inner)))
        return "{\n" + "\n".join(parts) + "\n" + ind + "}"
    return lua_str(v)


def write_data(rows, kills, zones, log_path=None, nights=1, cards=None, days=None, bosses=None):
    """Write Data/Report.lua into each installed copy.

    Arn: "am I expected to copy and paste a whole 108mb of text into a text box in wow?" No - and
    nor should the 410-character summary be pasted. The client loads any file its TOC names, so the
    numbers are handed over as a file and /reload is the whole import.

    It is deliberately NOT written into the repo: raid data is not source, and `deploy.sh` wipes the
    game folder before copying, so a deploy clears it until this runs again.
    """
    import time as _t
    body = [
        "-- Written by BiSGuild/dev/logreport.py. Do not edit: the next run replaces it.",
        "-- Raid data, not source. It is gitignored and a deploy removes it.",
        "BiSGuildReport = {",
        "    written = %d," % int(_t.time()),
        "    kills = %d," % kills,
        "    nights = %d," % nights,
        "    zones = %s," % lua_str(", ".join(zones)),
        "    rows = {",
    ]
    for name, att, con in rows:
        body.append("        { name = %s, attend = %d, consumes = %d }," % (lua_str(name), att, con))
    body.append("    },")
    # the raid days on record, and one card per raider (BiSGuild's raider terminal reads these)
    body.append("    days = %s," % lua_val(list(days or [])))
    body.append("    cards = %s," % lua_val(cards or {}, "    "))
    body.append("    bosses = %s," % lua_val(bosses or {}, "    "))
    body.append("}")
    text = "\n".join(body) + "\n"

    done = []
    for root in game_roots(log_path):
        d = os.path.join(root, "Data")
        try:
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, "Report.lua"), "w", encoding="utf-8") as fh:
                fh.write(text)
            done.append(os.path.join(d, "Report.lua"))
        except OSError as e:
            print("could not write into %s: %s" % (d, e))
    return done


if __name__ == "__main__":
    # A raider called Slapchôp came out as "Slapch?p" on a Windows console, and a name the council
    # cannot read is a name they cannot match to a person.
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(args[0],
                  kills_only="--all-pulls" not in sys.argv,
                  paste="--paste" in sys.argv,
                  review="--review" in sys.argv,
                  write="--write" in sys.argv,
                  include_dungeons="--dungeons" in sys.argv))
