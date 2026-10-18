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
        # A NIGHT IS ONE RAID (dev/NIGHTS.md, 17 Oct): its key is the date and the instance
        ok("cards = {" in text and 'days = { "2026-10-16 409" }' in text, "the report carries the raids and the cards",
           re.search(r"days = [^\n]*", text) and re.search(r"days = [^\n]*", text).group(0))

        # EACH PULL IS KEPT: who stood in it and what they brought, as flags
        hist = logreport.read_history(path)
        entry = hist[os.path.basename(path)]
        kill = [p for p in entry["pulls"] if p["k"]][0]
        wipe = [p for p in entry["pulls"] if not p["k"]][0]
        fa, fb = kill["r"]["Alice"], kill["r"]["Bob"]
        ok(fa & logreport.F_FLASK and fa & logreport.F_FOOD and fa & logreport.F_WEAPON and fa & logreport.F_READY,
           "Alice at the kill: flask, food, oil - ready", fa)
        ok(fb == logreport.F_FOOD | logreport.F_SEEN, "Bob: food only, a bare main hand", fb)
        ok(kill["p"] == {"Alice": 1} and kill["d"] == {"Bob": 1}, "a potion and a death inside the pull", (kill["p"], kill["d"]))
        ok(wipe["r"] == {} and kill["e"] == 1 and kill["i"] == 409 and kill["ms"] == 245000,
           "the wipe counts nobody; the kill knows its boss, raid and length")
        ok(kill["t"] == 1792202400, "and its moment, in UTC (19:00 at -7 is 02:00 UTC next day)", kill["t"])

        nightly, gear_rec = logreport.build_record(hist)
        cards = logreport.build_cards(nightly, gear_rec, logreport.load_gearcheck())
        issues = [i["slot"] for i in cards["Alice"]["issues"]]
        ok(issues == ["chest"], "Alice's unenchanted chest is the one red flag", issues)
        ok(cards["Bob"]["issues"] == [], "Bob's gear is clean")
        ok(cards["Alice"]["attended"] == ["2026-10-16 409"] and cards["Alice"]["last"]["date"] == "2026-10-16 409",
           "the raid she attended, and her latest raid's numbers")

        # THE BOSS AS A TICKER (Arn, 16 Oct): kills, wipes, the fastest kill, who was there
        pages = logreport.build_bosses(nightly)
        b1 = pages.get("Boss One", {})
        ok(b1.get("kills") == 1 and b1.get("wipes") == 1 and b1.get("best") == 245000,
           "Boss One: one kill, one wipe, best 4:05", b1)
        ok(b1.get("killers") == {"Alice": 1, "Bob": 1} and b1.get("first") == "2026-10-16 409",
           "who was there for the kill, and the first-kill raid", b1.get("killers"))
        ok("bosses = {" in text, "the report carries the boss pages")

        # THE NIGHT AS ONE RECORD - what the addon keeps and shares (Arn, 16 Oct: "if I miss one raid
        # night what stops the addon from updating")
        nl = nightly.get("2026-10-16 409", {})
        ok(nl.get("kills") == 1 and set(nl.get("raiders", {})) == {"Alice", "Bob"},
           "the night: one kill, both raiders", nl.get("kills"))
        ok(nl.get("v") == 2 and nl.get("i") == 409 and len(nl.get("pulls", [])) == 2,
           "and it carries its pulls, so another officer's copy can be merged into it")
        ra, rb = nl["raiders"]["Alice"], nl["raiders"]["Bob"]
        ok(ra["present"] == 1 and ra["flask"] == 1 and ra["pots"] == 1 and rb["deaths"] == 1,
           "each raider's numbers ride in it", (ra, rb))
        nb = nl["bosses"].get("Boss One", {})
        ok(nb.get("pulls") == 2 and nb.get("kills") == 1 and nb.get("best") == 245000
           and nb.get("killers") == ["Alice", "Bob"], "and each boss, its killers in one order", nb)
        ok("nightly = {" in text, "the report carries the nights")

        # the report is Lua the client can load
        lua = r"C:\Program Files (x86)\Lua\5.1\luac.exe"
        if os.path.exists(lua):
            r = subprocess.run([lua, "-p", report], capture_output=True, text=True)
            ok(r.returncode == 0, "Data/Report.lua is valid Lua", r.stderr.strip())

        # THE GAME BUILDS THE SAME CARDS (Core/Store.lua rebuilds them from the nights, because a night
        # shared over the guild channel has no reader behind it)
        luaexe0 = r"C:\Program Files (x86)\Lua\5.1\lua.exe"
        if os.path.exists(luaexe0):
            r = subprocess.run([luaexe0, os.path.join(HERE, "store_matches.lua"), report,
                                os.path.join(os.path.dirname(HERE), "Core", "Store.lua")],
                               capture_output=True, text=True)
            ok(r.returncode == 0, "the game's cards and boss pages match the reader's", (r.stdout + r.stderr)[-600:])

        # THE PASTE (the Colab notebook, 17 Oct): what the reader prints, the game takes in - through
        # its own Store.lua and Share.lua, compared raid by raid with the report
        import io, contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            logreport.main(path, paste=True)
        printed = buf.getvalue()
        ok(logreport.PASTE_START in printed and logreport.PASTE_END in printed, "--paste prints the text between two markers")
        body = printed.split(logreport.PASTE_START, 1)[1].split(logreport.PASTE_END, 1)[0].strip()
        ok(body.startswith("BiSGuild paste 2") and "R~2026-10-16 409~2#409#" in body and "|" not in body,
           "the paste: its layout, one raid line, and not one '|' (a WoW edit box doubles them)", body[:120])
        pfile = os.path.join(root, "paste.txt")
        with open(pfile, "w", encoding="utf-8") as fh:
            fh.write(printed)                    # all of it, markers and table too: the game finds its part
        luaexe1 = r"C:\Program Files (x86)\Lua\5.1\lua.exe"
        if os.path.exists(luaexe1):
            repo = os.path.dirname(HERE)
            r = subprocess.run([luaexe1, os.path.join(HERE, "paste_matches.lua"), pfile, report,
                                os.path.join(repo, "Core", "Store.lua"), os.path.join(repo, "Core", "Share.lua")],
                               capture_output=True, text=True)
            ok(r.returncode == 0, "the game takes the paste in: every raid and gear set as the reader wrote them",
               (r.stdout + r.stderr)[-600:])

        # a re-run of the same log replaces its night, never doubles it
        logreport.main(path, write=True)
        ok(len(logreport.read_history(path)) == 1, "the same log twice is still one night")

        # TIME ZONES LINE UP (dev/NIGHTS.md): the same moment written at -7 and at +1
        t1, d1 = logreport.when("10/16/2026 19:00:00.000-7")
        t2, d2 = logreport.when("10/17/2026 03:00:00.000+1")
        ok(t1 == t2 and d1 == "2026-10-16" and d2 == "2026-10-17",
           "one moment, two officers' clocks: the same UTC second; each keeps its own date", (t1, t2))
        t3, _ = logreport.when("10/16 19:00:00.000", 2026)
        ok(t3 is not None, "an older line without year or offset still reads")

        # TWO RAIDS ON ONE DATE ARE TWO NIGHTS (the bug: they were added together, and someone at
        # one of them could miss "half the kills" and lose the night)
        def pull(t, e, b, inst, k, who):
            return {"t": t, "date": "2026-10-20", "e": e, "b": b, "i": inst, "k": k, "ms": 1000,
                    "r": {w: logreport.F_FOOD for w in who} if k else {}, "d": {}, "p": {}}
        h2 = {"x.txt": {"log": "x.txt", "date": "2026-10-20", "v": 2, "zonenames": {"409": "Molten Core", "249": "Onyxia's Lair"},
                        "gear": {}, "pulls": [pull(100, 1, "Lucifron", 409, 1, ["Ann", "Cid"]),
                                              pull(900, 2, "Magmadar", 409, 1, ["Ann", "Cid"]),
                                              pull(9000, 9, "Onyxia", 249, 1, ["Ann", "Dee"])]}}
        n2, _ = logreport.build_record(h2)
        ok(sorted(n2) == ["2026-10-20 249", "2026-10-20 409"], "MC and Onyxia the same evening: two nights", sorted(n2))
        ok(n2["2026-10-20 409"]["zone"] == "Molten Core" and n2["2026-10-20 249"]["kills"] == 1,
           "each named, each with its own kills")
        c2 = logreport.build_cards(n2, {}, [])
        ok(c2["Dee"]["attended"] == ["2026-10-20 249"] and c2["Cid"]["attended"] == ["2026-10-20 409"],
           "Dee came to Onyxia only and keeps that night; Cid to MC only and keeps his",
           (c2["Dee"]["attended"], c2["Cid"]["attended"]))
        # and the same instance twice: a boss that dies again is a second raid (a new lockout / team)
        h3 = {"y.txt": dict(h2["x.txt"], pulls=[pull(100, 1, "Lucifron", 409, 1, ["Ann"]),
                                                 pull(2000, 1, "Lucifron", 409, 1, ["Bo"])])}
        n3, _ = logreport.build_record(h3)
        ok(sorted(n3) == ["2026-10-20 409", "2026-10-20 409-2"], "a boss killed twice: two raids", sorted(n3))
        # a pull in two logs of the same PC (the client restarted mid-raid) counts once
        h4 = {"a.txt": dict(h2["x.txt"], log="a.txt", pulls=[pull(100, 1, "Lucifron", 409, 1, ["Ann"])]),
              "b.txt": dict(h2["x.txt"], log="b.txt", pulls=[pull(100, 1, "Lucifron", 409, 1, ["Ann"]),
                                                              pull(900, 2, "Magmadar", 409, 1, ["Ann"])])}
        n4, _ = logreport.build_record(h4)
        ok(list(n4) == ["2026-10-20 409"] and n4["2026-10-20 409"]["kills"] == 2,
           "the same pull in two logs: once; the raid has both bosses", n4.get("2026-10-20 409", {}).get("kills"))
        # a history entry from before 17 Oct (no pulls) stays a night of its date
        old = {"log": "o.txt", "date": "2026-10-01", "zones": "X", "kills": 1, "present": {"Ann": 1},
               "ready": {"Ann": 1}, "detail": {"Ann": {"pulls": 1}}, "bosses": {"X": {"pulls": 1, "kills": 1, "best": 0, "killers": ["Ann"]}}}
        n5, _ = logreport.build_record(dict(h2, **{"o.txt": old}))
        ok("2026-10-01" in n5 and n5["2026-10-01"]["kills"] == 1, "an old date-keyed night is kept as it was")

        # THE POWERSHELL ONE SAYS THE SAME (raiders run that one): the same log in a second scratch
        # client, both reports compared value by value
        ps = shutil.which("powershell") or shutil.which("pwsh")
        luaexe = r"C:\Program Files (x86)\Lua\5.1\lua.exe"
        if ps and os.path.exists(luaexe):
            root2 = tempfile.mkdtemp(prefix="bisguild-ps-")
            try:
                logs2 = os.path.join(root2, "Logs")
                addon2 = os.path.join(root2, "Interface", "AddOns", "BiSGuild")
                os.makedirs(logs2)
                os.makedirs(addon2)
                shutil.copy(path, logs2)
                # A WHOLE COPY, AS A RAIDER HAS IT. Since 16 Oct the script checks its own folder
                # against Tools/manifest.txt and stops on anything extra - and the repo has dev/ in
                # it. So the shipped files are copied into the scratch client and the script runs
                # from THERE (the repo must be stamped: Tools\stamp.ps1).
                repo = os.path.dirname(HERE)
                with open(os.path.join(repo, "Tools", "manifest.txt"), encoding="utf-8") as mf:
                    shipped = [ln.split(" ", 1)[1].strip() for ln in mf if " " in ln.strip()]
                for rel in shipped + ["Tools/manifest.txt", "Core/Build.lua"]:
                    dst = os.path.join(addon2, *rel.split("/"))
                    os.makedirs(os.path.dirname(dst), exist_ok=True)
                    shutil.copyfile(os.path.join(repo, *rel.split("/")), dst)
                script = os.path.join(addon2, "Tools", "logreport.ps1")
                r = subprocess.run([ps, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script,
                                    "-Logs", logs2], capture_output=True, text=True)
                ok(r.returncode == 0, "the PowerShell reader runs", (r.stdout + r.stderr)[-400:])
                cmp = subprocess.run([luaexe, os.path.join(HERE, "same_report.lua"), report,
                                      os.path.join(addon2, "Data", "Report.lua")],
                                     capture_output=True, text=True)
                ok(cmp.returncode == 0, "Python and PowerShell write the same report", cmp.stdout[-600:])
                # and the PowerShell one KEEPS what the Python one wrote into the history
                shutil.copy(logreport.history_path(path), os.path.join(root2, "WTF", "BiSGuild", "history.json"))
                subprocess.run([ps, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, "-Logs", logs2],
                               capture_output=True, text=True)
                h2 = open(os.path.join(root2, "WTF", "BiSGuild", "history.json"), encoding="utf-8").read()
                ok('"pulls"' in h2 and '"zonenames"' in h2 and "2623" in h2,
                   "the PowerShell reader carries the pulls and the gear through the history")

                # EVERY LOG NOT READ YET (Arn, 16 Oct: "there are 4 logs tho" - it read only the
                # newest). A second night's log, plus one with no kills at all, in the same folder:
                # one run reads both new ones, and a run after that reads nothing new. The second
                # night is a week earlier IN ITS LINES too - since 17 Oct the time inside the log, not
                # its file name, says which raid a pull belongs to.
                older = os.path.join(logs2, "WoWCombatLog-100926_190000.txt")
                with open(path, encoding="utf-8") as src, open(older, "w", encoding="utf-8") as dst:
                    dst.write(src.read().replace("10/16/2026 ", "10/9/2026 "))
                os.utime(older, (1, 1))                      # older than the first by its clock
                with open(os.path.join(logs2, "WoWCombatLog-101726_190000.txt"), "w", encoding="utf-8") as fh:
                    fh.write(T + 'SPELL_AURA_APPLIED,Player-1-A,"Alice",0x511,0x0,Player-1-A,"Alice",0x511,0x0,1,"x",0x1,BUFF\n')
                r = subprocess.run([ps, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, "-Logs", logs2],
                                   capture_output=True, text=True)
                h3 = open(os.path.join(root2, "WTF", "BiSGuild", "history.json"), encoding="utf-8").read()
                ok("2 logs not read yet" in r.stdout and "WoWCombatLog-100926_190000.txt" in h3,
                   "one run reads every log it has not read, oldest first", r.stdout[-400:])
                rep = open(os.path.join(addon2, "Data", "Report.lua"), encoding="utf-8").read()
                ok('days = { "2026-10-09 409", "2026-10-16 409" }' in rep, "and the report has both nights",
                   re.search(r"days = [^\n]*", rep) and re.search(r"days = [^\n]*", rep).group(0))
                r = subprocess.run([ps, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, "-Logs", logs2],
                                   capture_output=True, text=True)
                ok("read already" in r.stdout and "not read yet" not in r.stdout,
                   "a run after that has nothing new to read", r.stdout[-300:])
            finally:
                shutil.rmtree(root2, ignore_errors=True)
        else:
            print("skip PowerShell parity (no powershell or lua here)")
    finally:
        shutil.rmtree(root, ignore_errors=True)
    print("ALL OK" if fails == 0 else "%d FAILED" % fails)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
