#!/usr/bin/env python3
"""BiSGuild :: dev/test_logreport.py - the log reader on a made-up raid night.

    python dev/test_logreport.py

Two raiders, one 25-man boss kill. Alice: flask, food, an oiled main hand, an unenchanted chest, a
mana potion inside the pull. Bob: food only, a bare main hand, and he dies. Every number the raider
card shows (Arn, 16 Oct: "type a raider name, show the gear they have ... attendance ... how much they
consume") is checked against what was put in. Runs in a scratch folder - never the real history.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import logreport  # noqa: E402

T = "10/16/2026 19:00:00.000-7  "


def gear(chest_ench, mh_temp):
    slots = []
    for i in range(1, 20):
        ench = (0, 0, 0)
        if i == 5:
            ench = (chest_ench, 0, 0)
        elif i in (7, 8, 9, 10, 15):             # legs, feet, wrist, hands, back: all enchanted
            ench = (800 + i, 0, 0)
        elif i == 16:
            ench = (8721, mh_temp, 0)
        item = 0 if i == 18 else 1000 + i
        slots.append("(%d,30,(%d,%d,%d),(),())" % ((item,) + ench))
    return "[" + ",".join(slots) + "]"


def combatant(guid, gear_s, auras):
    trip = ",".join("%s,%d,1" % (guid, a) for a in auras)
    return (T + "COMBATANT_INFO,%s,0,10,10,10,10,10,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,100,100,"
            "[(1,2,3)],(0,0,0,0),%s,[%s],1,0,0,0" % (guid, gear_s, trip))


def aura(guid, name, sid, sname):
    return T + 'SPELL_AURA_APPLIED,%s,"%s",0x511,0x0,%s,"%s",0x511,0x0,%d,"%s",0x1,BUFF' % (
        guid, name, guid, name, sid, sname)


LOG = [
    aura("Player-1-A", "Alice", 1001, "Flask of Pure Death"),
    aura("Player-1-A", "Alice", 1002, "Well Fed"),
    aura("Player-1-B", "Bob", 1002, "Well Fed"),
    T + 'ENCOUNTER_START,1,"Boss One",3,25,409',            # a wipe first
    T + 'ENCOUNTER_END,1,"Boss One",3,25,0,61000',
    T + 'ENCOUNTER_START,1,"Boss One",3,25,409',
    combatant("Player-1-A", gear(0, 2623), [1001, 1002]),
    combatant("Player-1-B", gear(908, 0), [1002]),
    T + 'SPELL_CAST_SUCCESS,Player-1-A,"Alice",0x511,0x0,0000000000000000,nil,0x0,0x0,17531,"Restore Mana",0x1',
    T + 'UNIT_DIED,0000000000000000,nil,0x80000000,0x80000000,Player-1-B,"Bob",0x511,0x0',
    T + 'ENCOUNTER_END,1,"Boss One",3,25,1,245000',
]

fails = 0


def ok(cond, what, got=None):
    global fails
    if cond:
        print("ok   " + what)
    else:
        fails += 1
        print("FAIL " + what + ("" if got is None else "   [%s]" % (got,)))


def main():
    root = tempfile.mkdtemp(prefix="bisguild-")
    try:
        logs = os.path.join(root, "Logs")
        addon = os.path.join(root, "Interface", "AddOns", "BiSGuild")
        os.makedirs(logs)
        os.makedirs(addon)
        path = os.path.join(logs, "WoWCombatLog-101626_190000.txt")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("\n".join(LOG) + "\n")

        # the gear line, as Forever writes it (measured on Arn's 5 Oct log)
        g = logreport.gear_of(combatant("Player-1-A", gear(0, 2623), [1001]).split("  ", 1)[1])
        ok(g is not None and len(g) == 19, "COMBATANT_INFO's gear bracket: 19 slots", g and len(g))
        ok(g[15][2] == 8721 and g[15][3] == 2623, "main hand: its enchant, and the oil as the temporary one", g and g[15])
        ok(g[17][0] == 0, "an empty ranged slot reads as no item")

        rc = logreport.main(path, write=True)
        ok(rc == 0, "a 25-man kill reads", rc)
        report = os.path.join(addon, "Data", "Report.lua")
        text = open(report, encoding="utf-8").read()
        ok("cards = {" in text and 'days = { "2026-10-16" }' in text, "the report carries the raid days and the cards")

        hist = logreport.read_history(path)
        night = hist[os.path.basename(path)]
        a, b = night["detail"]["Alice"], night["detail"]["Bob"]
        ok(a["flask"] == 1 and a["food"] == 1 and a["weapon"] == 1 and a["pots"] == 1,
           "Alice: flask, food, oil, one potion in the pull", a)
        ok(b["flask"] == 0 and b["food"] == 1 and b["weapon"] == 0 and b["deaths"] == 1,
           "Bob: food only, a bare weapon, one death", b)

        cards = logreport.build_cards(hist, {"Alice": ["2026-10-16"]}, logreport.load_gearcheck())
        issues = [i["slot"] for i in cards["Alice"]["issues"]]
        ok(issues == ["chest"], "Alice's unenchanted chest is the one red flag", issues)
        ok(cards["Bob"]["issues"] == [], "Bob's gear is clean")
        ok(cards["Alice"]["attended"] == ["2026-10-16"] and cards["Alice"]["last"]["date"] == "2026-10-16",
           "the night she attended, and her latest night's numbers")

        # THE BOSS AS A TICKER (Arn, 16 Oct): kills, wipes, the fastest kill, who was there
        pages = logreport.build_bosses(hist)
        b1 = pages.get("Boss One", {})
        ok(b1.get("kills") == 1 and b1.get("wipes") == 1 and b1.get("best") == 245000,
           "Boss One: one kill, one wipe, best 4:05", b1)
        ok(b1.get("killers") == {"Alice": 1, "Bob": 1} and b1.get("first") == "2026-10-16",
           "who was there for the kill, and the first-kill date", b1.get("killers"))
        ok("bosses = {" in text, "the report carries the boss pages")

        # the report is Lua the client can load
        lua = r"C:\Program Files (x86)\Lua\5.1\luac.exe"
        if os.path.exists(lua):
            r = subprocess.run([lua, "-p", report], capture_output=True, text=True)
            ok(r.returncode == 0, "Data/Report.lua is valid Lua", r.stderr.strip())

        # a re-run of the same log replaces its night, never doubles it
        logreport.main(path, write=True)
        ok(len(logreport.read_history(path)) == 1, "the same log twice is still one night")
    finally:
        shutil.rmtree(root, ignore_errors=True)
    print("ALL OK" if fails == 0 else "%d FAILED" % fails)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
