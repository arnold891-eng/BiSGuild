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

--paste prints every raid on record as text for BiS Guild's import box (the Colab notebook uses it).
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
    # gear is always the next-to-last group: Forever writes talents, gear, auras; TBC (2.5.6) only gear,
    # auras - "< 3" read no TBC gear at all (found on Arn's Black Temple log, 17 Oct)
    if len(b) < 2:
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


# A LINE'S TIME, AS ONE NUMBER EVERY OFFICER AGREES ON (dev/NIGHTS.md, 17 Oct 2026). Forever and TBC
# both write "10/5/2026 18:32:28.909-7": the date, the year and the UTC offset. So two officers' logs
# of one raid line up to the second in any time zone. An older line without the year or the offset
# takes the year from the file name and is read as UTC - it still orders within its own log.
STAMP = re.compile(r"^(\d+)/(\d+)(?:/(\d{4}))? (\d+):(\d+):(\d+)(?:\.\d+)?(?:([+-])(\d+)(?::?(\d+))?)?$")


def when(head, year=2000):
    """(UTC epoch seconds, "YYYY-MM-DD" in the logger's own local time) of a line's time, or (None, "")."""
    import calendar
    m = STAMP.match(head.strip())
    if not m:
        return None, ""
    mo, d, y = int(m.group(1)), int(m.group(2)), int(m.group(3) or year)
    hh, mi, ss = int(m.group(4)), int(m.group(5)), int(m.group(6))
    off = 0
    if m.group(7):
        off = int(m.group(8)) * 3600 + int(m.group(9) or 0) * 60
        if m.group(7) == "-":
            off = -off
    try:
        local = calendar.timegm((y, mo, d, hh, mi, ss, 0, 0, 0))
    except (ValueError, OverflowError):
        return None, ""
    return local - off, "%04d-%02d-%02d" % (y, mo, d)


# WHAT A RAIDER BROUGHT TO ONE PULL, as one number (dev/NIGHTS.md): the same six things the night's
# totals count, kept per pull so two officers' copies can be merged kill by kill.
F_READY, F_FLASK, F_ELIXIR, F_FOOD, F_WEAPON, F_SEEN = 1, 2, 4, 8, 16, 32


def main(path, kills_only=True, paste=False, review=False, write=False, include_dungeons=False):
    kinds = load_kinds()
    if not kinds:
        print("consumables.txt is empty or missing - nothing can be judged. See %s" % LIST)
        return 2
    names = {}                       # spell id -> spell name, learned from the log itself
    guid_name = {}                   # player guid -> short name
    zone_names = {}                  # instance id -> its name (ZONE_CHANGE)
    pulls = []                       # [{boss, kill, who: {guid: [auraIds]}}]
    cur = None
    fy = re.search(r"WoWCombatLog-\d{4}(\d{2})_", os.path.basename(path))
    year = 2000 + int(fy.group(1)) if fy else 2000

    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            # "10/4/2026 17:31:57.622-7  EVENT,..." - the event name is after the double space
            sep = line.find("  ")
            if sep == -1:
                continue
            body = line[sep + 2:].rstrip("\n")
            comma = body.find(",")
            event = body[:comma] if comma != -1 else body

            if event == "ZONE_CHANGE":
                # ZONE_CHANGE,<instance id>,"<name>",<difficulty> - what the instance is called
                zm = re.match(r'ZONE_CHANGE,(\d+),"(.*?)"', body)
                if zm and int(zm.group(1)) > 0:
                    zone_names[int(zm.group(1))] = zm.group(2)

            elif event == "ENCOUNTER_START":
                # ENCOUNTER_START,<id>,"<name>",<difficulty>,<groupSize>,<instance>,...
                # The name is quoted and could contain a comma, so it is matched rather than split.
                #
                # A DUNGEON BOSS IS NOT A RAID NIGHT (5 Oct 2026). The addon learned this when Arn
                # said "there are no raids in wow forever yet" - and the reader never did, so a
                # five-man log would have produced attendance that looked exactly like real raid
                # data. groupSize is the honest line: 25 for Black Temple, 5 for a dungeon.
                m = re.match(r'ENCOUNTER_START,(\d+),"(.*?)",(-?\d+),(-?\d+)(?:,(-?\d+))?', body)
                if m:
                    boss, size = m.group(2), int(m.group(4))
                    eid, inst = int(m.group(1)), int(m.group(5) or 0)
                else:
                    f = body.split(",")
                    boss, size = (f[2].strip('"') if len(f) > 2 else "?"), 0
                    eid, inst = 0, 0
                t, day = when(line[:sep], year)
                cur = {"boss": boss, "size": size, "kill": False, "who": {}, "gear": {},
                       "deaths": defaultdict(int), "pots": defaultdict(int),
                       "t": t if t is not None else 0, "date": day, "e": eid, "i": inst}
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

    # EACH PULL, KEPT (dev/NIGHTS.md, 17 Oct 2026). The night used to be totals only, which is why two
    # officers' copies could never be merged kill by kill. Now every pull of a raid boss is kept: its
    # time, raid, boss, whether it died, who stood in it and what each brought, who died and who drank.
    # The night's totals are DERIVED from these (derive), by the same rule the game uses.
    unknown = defaultdict(set)
    counted_ids = {id(p) for p in counted}
    nightpulls = [p for p in pulls if include_dungeons or not (0 < p.get("size", 0) <= 5)]
    log_pulls, log_gear = [], {}
    for p in nightpulls:
        r = {}
        if id(p) in counted_ids:
            for guid, auras in p["who"].items():
                who = guid_name.get(guid, guid)
                flask = elixirs = food = 0
                for sid in auras:
                    nm = names.get(sid, "id %d" % sid)
                    kind = kinds.get(nm.lower())
                    if kind == "food":
                        food += 1
                    elif kind == "flask":
                        flask += 1
                    elif kind == "elixir" or kind == "scroll":
                        # Arn, 4 Oct: scrolls count in TBC, to be decided for Forever. A scroll is
                        # worth an elixir towards the pair; consumables.txt is where that is changed.
                        elixirs += 1
                    else:
                        unknown[nm].add(guid)
                fl = 0
                if (flask or elixirs >= 2) and food:
                    fl |= F_READY
                if flask:
                    fl |= F_FLASK
                elif elixirs >= 2:
                    fl |= F_ELIXIR
                if food:
                    fl |= F_FOOD
                g = p["gear"].get(guid)
                if g and len(g) > 15 and g[15][0]:
                    fl |= F_SEEN
                    if g[15][3]:
                        fl |= F_WEAPON
                r[who] = fl
        for guid, g in p["gear"].items():
            log_gear[guid_name.get(guid, guid)] = [p["date"], g]        # the last pull's gear wins
        log_pulls.append({"t": p["t"], "date": p["date"], "e": p["e"], "b": p["boss"], "i": p["i"],
                          "k": 1 if p["kill"] else 0, "ms": p.get("ms", 0), "r": r,
                          "d": {guid_name.get(g, g): n for g, n in p["deaths"].items()},
                          "p": {guid_name.get(g, g): n for g, n in p["pots"].items()}})

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
    # variables at all, so those were the two places it could not go. Kept per LOG, so re-running the
    # same log replaces its entry instead of counting it twice.
    nights = read_history(path)
    stamp = ""
    m = re.search(r"WoWCombatLog-(\d{2})(\d{2})(\d{2})_", os.path.basename(path))
    if m:
        stamp = "20%s-%s-%s" % (m.group(3), m.group(1), m.group(2))
    nights[os.path.basename(path)] = {
        "log": os.path.basename(path), "date": stamp, "v": 2,
        "zones": ", ".join(zones), "zonenames": {str(k): v for k, v in zone_names.items()},
        "pulls": log_pulls, "gear": log_gear,
    }
    write_history(path, nights)

    # A NIGHT IS ONE RAID (dev/NIGHTS.md, 17 Oct). It was one DATE, and two raids on one date were
    # added together - someone at one of them could then miss "half the kills" and lose the night.
    nightly, gear = build_record(nights)
    days = sorted(nightly)

    # A NIGHT IS EARNED BY HALF ITS KILLS. present*2 >= kills, never present >= kills/2: three kills
    # and one attendance is 1 against 1.5, and a raid record does not go near floating point.
    earned, seen_pulls, ready_pulls = defaultdict(int), defaultdict(int), defaultdict(int)
    for key in days:
        night = nightly[key]
        for who, r in night["raiders"].items():
            if r["present"] > 0 and r["present"] * 2 >= night["kills"]:
                earned[who] += 1
            seen_pulls[who] += r["present"]
            ready_pulls[who] += r["ready"]
    raided = max(1, len(days))

    rows = []
    for who in earned:
        rows.append((who, round(100 * earned[who] / raided),
                     round(100 * ready_pulls[who] / seen_pulls[who]) if seen_pulls[who] else 0))
    rows.sort(key=lambda r: (-r[1], -r[2], r[0]))
    cards = build_cards(nightly, gear, load_gearcheck())
    bosscards = build_bosses(nightly)

    label = "boss kill" if kills_only else "pull"
    print("this log: %d %s(s): %s" % (total, label, ", ".join(zones)))
    print("over %d raid night(s) on record:" % raided)
    print("%-16s %8s %9s" % ("", "attend", "consumes"))
    for who, att, con in rows:
        print("%-16s %7d%% %8d%%" % (who, att, con))

    if paste:
        # THE PASTE (17 Oct 2026, the Colab notebook): every raid on record as text the game's import
        # box takes - the same layout officers share in game (Core/Share.lua EncodeRaid)
        print()
        print(PASTE_START)
        print(paste_text(nightly, gear))
        print(PASTE_END)

    if write:
        wrote = write_data(rows, total, zones, path, raided, cards, days, bosscards, nightly)
        print()
        if wrote:
            for w in wrote:
                print("written: %s" % w)
            print("/reload in the client and the numbers are there. Nothing to paste.")
        else:
            print("no BiSGuild addon folder found to write into - is it deployed?")
    return 0


# ------------------------------------------------------------------ the paste
# Arn, 17 Oct 2026: a notebook "so people can just drag and drop their log ... hit run ... something to
# paste". The text a person pastes into BiS Guild's import box (Core/Share.lua X.ImportPaste):
#
#   BiSGuild paste 2
#   R~<key>~<raid, as Core/Share.lua X.EncodeRaid writes it>      one line per raid
#   G~<name>~<date>~<gear, as X.EncodeGear writes it>              one line per raider's newest gear
#   END~<lines>~<characters>                                       so a cut-off paste is caught
#
# "~", NOT "|": a WoW edit box doubles every "|" it is given (it is the client's escape character),
# and nothing in a raid or a gear line ever uses "~".
#
# The "2" is the paste's layout: a copy of BiS Guild that knows an older layout refuses a newer one
# ("update BiS Guild") rather than guessing. These encoders are the game's, rule for rule - the suite
# decodes this file's output in the game's own Lua (dev/test_logreport.py).
PASTE_VERSION = 2
PASTE_START = "----- copy everything from the next line to the END line -----"
PASTE_END = "----- end -----"
_SEPS = set(":;#,.|/~")


def _clean(s):
    return isinstance(s, str) and s != "" and not (set(s) & _SEPS)


def _int(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return 0


def encode_raid(night):
    """Core/Share.lua X.EncodeRaid, character for character."""
    pulls = night.get("pulls") or []
    names, bosses = set(), set()
    for p in pulls:
        for t in (p.get("r"), p.get("d"), p.get("p")):
            for who in (t or {}):
                if _clean(who):
                    names.add(who)
        b = str(p.get("b") or "")
        if _clean(b):
            bosses.add(b)
    names, bosses = sorted(names), sorted(bosses)
    index = {w: i + 1 for i, w in enumerate(names)}
    bindex = {b: i + 1 for i, b in enumerate(bosses)}

    def lst(t):
        return ",".join(sorted("%d.%d" % (index[w], _int(v)) for w, v in (t or {}).items() if w in index))

    out = []
    for p in pulls:
        bi = bindex.get(str(p.get("b") or ""))
        if bi:
            out.append("%d.%d.%d.%d.%d:%s:%s:%s" % (_int(p.get("t")), _int(p.get("e")), _int(p.get("k")),
                                                    _int(p.get("ms")), bi, lst(p.get("r")), lst(p.get("d")),
                                                    lst(p.get("p"))))
    zone = str(night.get("zone") or "").replace("#", "")
    return "2#%d#%d#%s#%s#%s#%s" % (_int(night.get("i")), _int(night.get("start")), ";".join(names),
                                    ";".join(bosses), ";".join(out), zone)


def encode_gear(gear):
    """Core/Share.lua X.EncodeGear: id.ilvl.enchant.temp.gem/gem per slot, "0" for an empty one."""
    out = []
    for i in range(19):
        g = gear[i] if i < len(gear) else None
        if g and _int(g[0]) != 0:
            gems = "/".join(str(_int(x)) for x in (g[4] if len(g) > 4 and g[4] else []))
            out.append("%d.%d.%d.%d.%s" % (_int(g[0]), _int(g[1]), _int(g[2]), _int(g[3]), gems))
        else:
            out.append("0")
    return ";".join(out)


def paste_text(nightly, gear):
    """Every raid on record (whole-date nights from before 17 Oct are not pasted) and every raider's
    newest gear, as the import box takes them."""
    lines = ["BiSGuild paste %d" % PASTE_VERSION]
    for key in sorted(nightly):
        night = nightly[key]
        if night.get("v") == 2:
            lines.append("R~%s~%s" % (key, encode_raid(night)))
    for who in sorted(gear):
        date, g = gear[who]
        if _clean(who) and g:
            lines.append("G~%s~%s~%s" % (who, date, encode_gear(g)))
    body = lines[1:]
    # BYTES, not characters: the game counts with Lua's #, and "Slapchôp" is eight letters but nine
    # bytes (Arn's Black Temple log, 17 Oct - the first real paste came out "damaged")
    lines.append("END~%d~%d" % (len(body), sum(len(l.encode("utf-8")) for l in body)))
    return "\n".join(lines)


NIGHT_FIELDS = ("present", "ready", "pulls", "flask", "elixir", "food", "weapon", "weaponSeen", "pots", "deaths")
RAID_GAP = 3 * 3600          # a longer gap than this between two pulls starts another raid


def group_raids(pulls):
    """THE PULLS OF EVERY LOG ON RECORD, AS RAIDS (dev/NIGHTS.md). In time order, one instance at a
    time; a new raid starts on another instance, after a gap of more than RAID_GAP, or when a boss
    already killed in this raid dies again - one lockout cannot kill a boss twice. A pull in two logs
    of this PC (the same time, the same boss) counts once."""
    seen, ordered = {}, []
    for p in sorted(pulls, key=lambda p: (p["t"], p["e"], p["b"], -p["k"])):
        sig = (p["t"], p["e"], p["b"])
        if sig in seen and seen[sig] != p.get("log"):
            continue                       # this very pull, from another log
        seen[sig] = p.get("log")
        ordered.append(p)
    raids, cur = [], None
    for p in ordered:
        boss = p["e"] or p["b"]
        if (cur is None or p["i"] != cur["i"] or p["t"] - cur["last"] > RAID_GAP
                or (p["k"] and boss in cur["killed"])):
            cur = {"i": p["i"], "date": p["date"], "start": p["t"], "last": p["t"],
                   "killed": set(), "pulls": []}
            raids.append(cur)
        cur["pulls"].append(p)
        cur["last"] = p["t"]
        if p["k"]:
            cur["killed"].add(boss)
    return raids


def derive(pulls):
    """A NIGHT'S TOTALS FROM ITS PULLS - the same rule as Core/Store.lua S.Derive, so a night merged in
    the game counts exactly like one read here. A pull counts if it died (or, with --all-pulls, if
    anybody stood in it); the consumables ride the counted pulls, deaths and potions every pull."""
    kills, raiders, bosses = 0, {}, {}

    def raider(who):
        return raiders.setdefault(who, {k: 0 for k in NIGHT_FIELDS})

    for p in pulls:
        b = bosses.setdefault(p["b"], {"pulls": 0, "kills": 0, "best": 0, "killers": []})
        b["pulls"] += 1
        if p["k"]:
            b["kills"] += 1
            if p["ms"] and (not b["best"] or p["ms"] < b["best"]):
                b["best"] = p["ms"]
            b["killers"].extend(p["r"].keys())
        if p["k"] or p["r"]:
            kills += 1
            for who, fl in p["r"].items():
                r = raider(who)
                r["present"] += 1
                r["pulls"] += 1
                r["ready"] += 1 if fl & F_READY else 0
                r["flask"] += 1 if fl & F_FLASK else 0
                r["elixir"] += 1 if fl & F_ELIXIR else 0
                r["food"] += 1 if fl & F_FOOD else 0
                r["weapon"] += 1 if fl & F_WEAPON else 0
                r["weaponSeen"] += 1 if fl & F_SEEN else 0
        for who, n in p["d"].items():
            raider(who)["deaths"] += n
        for who, n in p["p"].items():
            raider(who)["pots"] += n
    for b in bosses.values():
        b["killers"].sort()               # one order, so both readers and every copy say the same
    return {"kills": kills, "raiders": raiders, "bosses": bosses}


def build_record(nights):
    """EVERY RAID ON RECORD, AND EVERY RAIDER'S NEWEST GEAR - what Data/Report.lua hands the game.

    Key: "YYYY-MM-DD <instance id>" (the date of the raid's first pull, in the logger's own time), "-2"
    after it for a second raid of the same instance that date. A history entry from before 17 Oct has
    no pulls: it stays a night of its whole DATE, as it was, unless that date has raids now."""
    pulls, zone_names, gear, legacy = [], {}, {}, []
    for n in sorted(nights.values(), key=lambda n: n["log"]):
        if n.get("v") == 2:
            pulls.extend(dict(p, log=n["log"]) for p in (n.get("pulls") or []))
            zone_names.update({int(k): v for k, v in (n.get("zonenames") or {}).items()})
            for who, dg in (n.get("gear") or {}).items():
                if who not in gear or dg[0] >= gear[who][0]:
                    gear[who] = [dg[0], dg[1]]
        else:
            legacy.append(n)
    nightly = {}
    for raid in group_raids(pulls):
        key = "%s %d" % (raid["date"], raid["i"])
        k, nth = key, 1
        while k in nightly:
            nth += 1
            k = "%s-%d" % (key, nth)
        night = derive(raid["pulls"])
        night.update({"v": 2, "i": raid["i"], "start": raid["start"],
                      "zone": zone_names.get(raid["i"], ""),
                      "pulls": [{f: p[f] for f in ("t", "e", "b", "k", "ms", "r", "d", "p")}
                                for p in raid["pulls"]]})
        nightly[k] = night
    for date, night in build_nightly_v1(legacy).items():
        if not any(k.startswith(date + " ") for k in nightly):
            nightly[date] = night
    for n in sorted(legacy, key=lambda n: (n.get("date") or n["log"])):
        date = n.get("date") or n["log"]
        for who, d in (n.get("detail") or {}).items():
            if d.get("gear") and (who not in gear or date >= gear[who][0]):
                gear[who] = [date, d["gear"]]
    return nightly, gear


def build_bosses(nightly):
    """ONE PAGE PER BOSS from every night on record (Core/Store.lua S.Bosses, the same rule): kills,
    wipes, the nights it died, the first kill, the fastest, and how many kills each raider stood in."""
    pages = {}
    for key in sorted(nightly):
        for boss, b in (nightly[key].get("bosses") or {}).items():
            pg = pages.setdefault(boss, {"kills": 0, "wipes": 0, "best": 0, "first": None,
                                         "nights": [], "killers": {}})
            pg["kills"] += b["kills"]
            pg["wipes"] += b["pulls"] - b["kills"]
            if b["kills"]:
                pg["first"] = pg["first"] or key
                if not pg["nights"] or pg["nights"][-1] != key:
                    pg["nights"].append(key)
            if b.get("best") and (not pg["best"] or b["best"] < pg["best"]):
                pg["best"] = b["best"]
            for who in b.get("killers", []):
                pg["killers"][who] = pg["killers"].get(who, 0) + 1
    return pages


def build_nightly_v1(nights):
    """A HISTORY ENTRY FROM BEFORE 17 OCT (no pulls): its whole date as one night, the old rule. Logs
    from one date are added together."""
    out = {}
    for n in sorted(nights, key=lambda n: (n.get("date") or n["log"])):
        date = n.get("date") or n["log"]
        d = out.setdefault(date, {"kills": 0, "raiders": {}, "bosses": {}})
        d["kills"] += n["kills"]
        detail = n.get("detail") or {}
        for who in set(n["present"]) | set(detail):
            r = d["raiders"].setdefault(who, {k: 0 for k in NIGHT_FIELDS})
            r["present"] += n["present"].get(who, 0)
            r["ready"] += n["ready"].get(who, 0)
            for k in NIGHT_FIELDS[2:]:
                r[k] += (detail.get(who) or {}).get(k, 0)
        for boss, b in (n.get("bosses") or {}).items():
            pb = d["bosses"].setdefault(boss, {"pulls": 0, "kills": 0, "best": 0, "killers": []})
            pb["pulls"] += b["pulls"]
            pb["kills"] += b["kills"]
            if b.get("best") and (not pb["best"] or b["best"] < pb["best"]):
                pb["best"] = b["best"]
            pb["killers"].extend(b.get("killers", []))
    for d in out.values():
        for pb in d["bosses"].values():
            pb["killers"].sort()
    return out


def build_cards(nightly, gear, want):
    """ONE CARD PER RAIDER from every night on record (Core/Store.lua S.Cards, the same rule): the
    nights they earned, their latest night's consumables, deaths and potions over the whole record,
    their newest gear and its red flags."""
    cards = {}

    def card(who):
        return cards.setdefault(who, {"deaths": 0, "pots": 0, "last": None, "gear": None,
                                      "gearDate": None, "attended": [], "issues": []})

    for key in sorted(nightly):
        night = nightly[key]
        for who, r in night["raiders"].items():
            c = card(who)
            c["deaths"] += r.get("deaths", 0)
            c["pots"] += r.get("pots", 0)
            if r.get("pulls"):
                c["last"] = {k: r.get(k, 0) for k in NIGHT_FIELDS[2:]}
                c["last"]["date"] = key
            if r.get("present", 0) > 0 and r["present"] * 2 >= night["kills"]:
                c["attended"].append(key)
    for who, (date, g) in gear.items():
        c = card(who)
        c["gear"], c["gearDate"] = g, date
        c["issues"] = issues_of(g, want)
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


def write_data(rows, kills, zones, log_path=None, nights=1, cards=None, days=None, bosses=None, nightly=None):
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
    # every raid day as one record: what the addon keeps and shares with the guild
    body.append("    nightly = %s," % lua_val(nightly or {}, "    "))
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
