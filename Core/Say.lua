--[[
  BiSGuild :: Core/Say.lua - reading the record back.

  A number nobody can check is a number nobody should act on, so every line here can be opened up:
  the percentage, then the nights behind it, then the kills behind those. The first argument a
  council has will be somebody saying "that is not right" - and they will be right often enough
  that the addon has to be able to show its working.
]]
local ADDON, ns = ...





function ns.Say(cmd, rest)
    -- THE WINDOW IS THE FRONT DOOR (5 Oct 2026). Arn: "give me a bis themed window for bis guild so
    -- i can copy and paste and not have to write out commands". A bare `/bisg` opens it; everything
    -- that was a command still is one, for anybody who prefers them.
    --
    -- THE TERMINAL IS THE FRONT DOOR NOW (16 Oct 2026, the raider terminal). The script window is
    -- still one key away (F3 LOG) and still `/bisg window`.
    if cmd == "" and ns.K and ns.K.Toggle then
        ns.K.Toggle()
        return
    end
    -- `/bisg dots on|off`: guildmates on the world map (Core/Pins.lua)
    -- `/bisg logins on|off`: "X just logged in - invite?" (Core/Logins.lua)
    if cmd == "logins" and ns.Login then
        local r = rest:lower()
        if r == "on" or r == "off" then ns.DB().logins = (r == "on") end
        ns.Print("login pop-up for the pasted roster: %s%s. %s", ns.Login.On() and ns.T.text("good", "on")
            or ns.T.text("warn", "off"), ns.Login.Armed() and " (armed now)" or "",
            ns.T.text("muted", "/bisg logins on | off"))
        return
    end
    if cmd == "dots" and ns.Pins then
        local r = rest:lower()
        if r == "on" or r == "off" then ns.DB().mapDots = (r == "on") end
        local n = ns.Pins.Update()
        ns.Print("guildmates on the world map: %s - %d dot(s) now. %s", ns.Pins.On() and ns.T.text("good", "on")
            or ns.T.text("warn", "off"), n, ns.T.text("muted", "/bisg dots on | off"))
        return
    end
    -- `/bisg mapwhy`: what the WHERE map's last drawing got from the game (16 Oct: Zephras Isle fog)
    if cmd == "mapwhy" and ns.Where then
        local w = ns.Where.why
        if not w then ns.Print("the WHERE map has not drawn yet - open it first") return end
        ns.Print("map %s: %d base tile(s); explored pieces: call %s, %d record(s), %d piece(s)%s", tostring(w.map),
            w.base, tostring(w.call), w.records, w.explored, w.hidden and ", HIDDEN by the client" or "")
        return
    end
    if cmd == "terminal" or cmd == "t" then
        if ns.K then ns.K.Show(rest ~= "" and rest or nil) end
        return
    end
    if cmd == "window" or cmd == "show" then
        if ns.U and ns.U.Show then ns.U.Show() end
        return
    end
    -- `/bisg logs <path>` - told once, remembered. `/bisg script` prints the command.
    if cmd == "logs" then
        local P, T = ns.P, ns.T
        if rest == "" then
            local have = P.Logs()
            ns.Print("logs folder: %s", have and T.text("good", have) or T.text("warn", "not set"))
            ns.Print("  %s", T.text("muted", "/bisg logs <paste the path to your Logs folder>."
                .. " In WoW's own folder, beside WTF and Interface. Ends in \\Logs."))
            return
        end
        local ok, why = P.SetLogs(rest)
        if not ok then
            ns.Print("%s", why == "not a logs folder"
                and "that does not end in \\Logs - I want the Logs folder itself."
                or "paste the path after the command.")
            return
        end
        ns.Print("logs folder remembered: %s", T.text("good", ok))
        ns.Print("  %s", T.text("muted", "Now |cffb980ff/bisg script|r for the line to run."))
        return
    end

    if cmd == "script" then
        local P, T = ns.P, ns.T
        local line = P.Command()
        if not line then
            -- TWO DIFFERENT PROBLEMS, TWO DIFFERENT SENTENCES (5 Oct 2026). Arn set a folder, was
            -- told it was remembered, and then got "tell me where your logs are first" - which is
            -- the addon calling him a liar about something it had just confirmed. If a folder IS
            -- known and the command still cannot be built, say THAT.
            if P.Logs() then
                ns.Print("I have %s but cannot work out where WoW is from it.", T.text("accent", P.Logs()))
                ns.Print("  %s", T.text("muted", "It should be the Logs folder inside a client"
                    .. " folder - the one with Interface and WTF beside it."))
            else
                ns.Print("tell me where your logs are first: %s", T.text("accent", "/bisg logs <path>"))
            end
            return
        end
        -- THE WARNING COMES FIRST AND IS NOT POLITE ABOUT IT (Arn, 4 Oct). "Paste this into
        -- PowerShell" is how people get robbed. A script can do anything the person running it can
        -- do, and nothing in this addon can tell a good one from a bad one - so the only honest
        -- thing is to say where the risk is and let them decide, loudly, every time.
        ns.Print("%s", T.text("warn", "READ THIS BEFORE YOU RUN IT"))
        ns.Print("  %s", T.text("warn", "This runs a PowerShell script. A script can do anything"
            .. " you can do on this computer - read your files, change them, send them away."))
        ns.Print("  %s", T.text("muted", "Only run it if you got BiSGuild from CurseForge or from"
            .. " your own officers. If somebody sent you a copy, do not run this - not even if they"
            .. " seem helpful. That is the one check that actually matters."))
        -- ARN FOUND THE HOLE, 4 Oct: "won't someone that steals the zip can just write code to put
        -- up whatever hash is the most correct tho?" Yes. Whoever changes the script changes this
        -- number with it, and then both sides of the check agree and the player feels safe.
        --
        -- A check an attacker controls both ends of is WORSE than no check, because it manufactures
        -- confidence. So the number below is not presented as proof of anything: the comparison
        -- that counts is against the CurseForge page, which is the one thing they cannot edit.
        -- THE WHOLE ADDON, CHECKED BY A LINE THAT IS NOT OURS (16 Oct 2026, Core/Copies.lua): the
        -- check is plain PowerShell hashing the folder itself, and the CurseForge page carries the
        -- same line - which is the copy to take it from.
        ns.Print("  %s", T.text("muted", "To check this copy, take the check line from our CurseForge page"
            .. " (this is the same line), run it, and compare the answer with the number on that page -"
            .. " NOT with the number below:"))
        ns.Print("%s", P.CheckCommand() or "...")
        ns.Print("  %s %s", T.text("muted", "this copy says"), T.text("accent", P.Fingerprint() or "no fingerprint"))
        ns.Print("  %s", T.text("warn", "A faked addon would show you a faked number here too, so"
            .. " these two agreeing proves nothing on its own. Only the CurseForge page does."))
        ns.Print("  %s", T.text("muted", "The script also checks every file itself and will not run on a"
            .. " copy that does not match. /bisg copy: how your copy compares with your guild's."))
        ns.Print(" ")
        ns.Print("then, after a raid, this - and /reload:")
        ns.Print("%s", line)
        ns.Print("  %s", T.text("muted", "It reads only the NEWEST log, not all of them, and writes"
            .. " the numbers straight into the addon. Nothing is pasted back in here."))
        return
    end

    if cmd == "report" or cmd == "log" then
        local P, T = ns.P, ns.T
        local r = P.Report()
        if not r then
            ns.Print("no log report loaded.")
            if P.Command() then
                ns.Print("  %s", T.text("muted", "Run |cffb980ff/bisg script|r for the line to"
                    .. " paste into PowerShell, then /reload."))
            else
                ns.Print("  %s", T.text("muted", "Tell me where your logs are once with"
                    .. " |cffb980ff/bisg logs <path>|r, then |cffb980ff/bisg script|r."))
            end
            return
        end
        ns.Print("from the combat log: %s (%d kill(s))", r.zones or "?", r.kills or 0)
        for _, row in ipairs(P.Rows()) do
            local a, c = row.attend or 0, row.consumes or 0
            ns.Print("  %-14s %s  %s", row.name,
                T.text(a >= 75 and "good" or a >= 50 and "gold" or "warn", a .. "%"),
                T.text(c >= 90 and "good" or c >= 60 and "gold" or "warn", "consumes " .. c .. "%"))
        end
        return
    end
    if cmd == "help" then
        ns.Print("version %s", ns.VERSION)
        ns.Print("  %s  the raider terminal: type a raider or a boss", ns.T.text("accent", "/bisg"))
        ns.Print("  %s  straight to one raider or boss", ns.T.text("accent", "/bisg <name>"))
        ns.Print("  %s  the log window: paste a path, copy a command", ns.T.text("accent", "/bisg window"))
        ns.Print("  %s  guildmates' dots on the world map", ns.T.text("accent", "/bisg dots on | off"))
        ns.Print("  %s  'X just logged in - invite?' for the pasted roster", ns.T.text("accent", "/bisg logins on | off"))
        ns.Print("  %s  attendance and consumes from the combat log", ns.T.text("accent", "/bisg report"))
        ns.Print("  %s  where your logs are (once)", ns.T.text("accent", "/bisg logs <path>"))
        ns.Print("  %s  the line to run after a raid", ns.T.text("accent", "/bisg script"))
        return
    end
    -- ANYTHING ELSE IS THE REPORT. There used to be an `all()` here reading the addon's own
    -- attendance; the addon does not keep any now, so the report IS the answer to "how is everyone
    -- doing" and there is nothing else it could have meant.
    --
    -- Unless it is a name on the record (16 Oct): `/bisg kumlust` opens his card in the terminal.
    if ns.K and ns.S then
        local name = (rest ~= "" and (cmd .. " " .. rest)) or cmd
        local kind = ns.K.Parse(name, ns.S.Cards(), ns.S.Bosses())
        if kind == "raider" or kind == "boss" then
            ns.K.Show(name)
            return
        end
    end
    return ns.Say("report")
end

ns.parts["Core/Say.lua"] = "0.1.0"
