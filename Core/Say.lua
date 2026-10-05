--[[
  BiSGuild :: Core/Say.lua - reading the record back.

  A number nobody can check is a number nobody should act on, so every line here can be opened up:
  the percentage, then the nights behind it, then the kills behind those. The first argument a
  council has will be somebody saying "that is not right" - and they will be right often enough
  that the addon has to be able to show its working.
]]
local ADDON, ns = ...

local function when(at)
    at = tonumber(at) or 0
    if at == 0 or not date then return "?" end
    local ok, s = pcall(date, "%a %d %b", at)
    return (ok and type(s) == "string") and s or "?"
end

--- `/bisg` - everyone, best first.
local function all()
    local G, T = ns.G, ns.T
    local rows = G.Everyone()
    local nights = #G.Settled()
    local tonight = G.Tonight()
    if nights == 0 then
        if tonight then
            ns.Print("tonight is the first night on record - %d kill(s) so far.", #tonight.kills)
            ns.Print("  %s", T.text("muted", "It joins the record when it ends. The record is what"
                .. " happened BEFORE tonight: whoever is rolling is standing here either way."))
            return
        end
        ns.Print("no raid nights on record yet.")
        ns.Print("  %s", T.text("muted", "Attendance cannot be worked out backwards - it starts the"
            .. " first boss this addon sees die while you are in a group."))
        return
    end
    ns.Print("over %s finished raid night(s):", T.text("accent", tostring(nights)))
    for _, r in ipairs(rows) do
        local colour = (r.pct >= 75 and "good") or (r.pct >= 50 and "gold") or "warn"
        ns.Print("  %-14s %s  %s", r.name, T.text(colour, r.pct .. "%"),
            T.text("muted", r.earned .. " of " .. r.raided))
    end
    if tonight then
        ns.Print("  %s", T.text("muted", "Tonight (" .. #tonight.kills .. " kill(s)) is NOT in"
            .. " these numbers - it joins when it ends. Whoever is rolling is here either way;"
            .. " the record is what they did before."))
    end
    ns.Print("  %s", T.text("muted", "A night is earned by being there for at least half its"
        .. " kills. |cffb980ff/bisg nights|r for the nights themselves."))
end

--- `/bisg nights` - the nights behind the numbers, newest first.
local function nights()
    local G, T = ns.G, ns.T
    local list = G.Raided()
    if #list == 0 then ns.Print("no raid nights on record yet.") return end
    for i, night in ipairs(list) do
        if i > 10 then
            ns.Print("  %s", T.text("muted", "...and " .. (#list - 10) .. " more"))
            break
        end
        ns.Print("%s %s  %s", T.text("accent", night.zone or "somewhere"), when(night.start),
            T.text("muted", #night.kills .. " kill(s), " .. #(night.kills[1] and night.kills[1].who or {}) .. " there"))
    end
end

--- `/bisg me` - one person's working, shown in full.
local function me()
    local G, R, T = ns.G, ns.R, ns.T
    local name = R.Short(UnitName and UnitName("player"))
    if not name then ns.Print("the client will not say who you are right now.") return end
    local earned, raided, pct = G.Rate(name)
    if pct == nil then ns.Print("no raid nights on record yet.") return end
    ns.Print("%s: %s - %d of %d night(s)", name, T.text("accent", pct .. "%"), earned, raided)
    for _, night in ipairs(G.Raided()) do
        local seen, total = G.Saw(night, name)
        local got = G.Earned(night, name)
        ns.Print("  %s %s  %s", when(night.start), T.text("muted", (night.zone or "somewhere")),
            T.text(got and "good" or "warn", seen .. "/" .. total))
    end
end

function ns.Say(cmd, rest)
    if cmd == "nights" then return nights() end
    if cmd == "me" then return me() end
    if cmd == "report" or cmd == "log" then
        local P, T = ns.P, ns.T
        local r = P.Report()
        if not r then
            ns.Print("no log report loaded.")
            ns.Print("  %s", T.text("muted", "Run |cffb980ffBiSGuild/dev/logreport.py <your combat"
                .. " log> --write|r and /reload. Nothing is pasted - it writes a file the client"
                .. " loads. A deploy clears it until the script runs again."))
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
        ns.Print("  %s  everyone's attendance", ns.T.text("accent", "/bisg"))
        ns.Print("  %s  the raid nights themselves", ns.T.text("accent", "/bisg nights"))
        ns.Print("  %s  your own, night by night", ns.T.text("accent", "/bisg me"))
        ns.Print("  %s  attendance and consumes from the combat log", ns.T.text("accent", "/bisg report"))
        return
    end
    return all()
end
