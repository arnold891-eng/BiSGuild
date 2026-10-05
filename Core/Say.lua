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
    local C = ns.C
    ns.Print("over %s finished raid night(s):", T.text("accent", tostring(nights)))
    for _, r in ipairs(rows) do
        local colour = (r.pct >= 75 and "good") or (r.pct >= 50 and "gold") or "warn"
        -- written out, not `C and C.Rate(...)`: an `and` keeps only the FIRST return value, so the
        -- percentage would have been nil every time and the column would silently never appear
        local cpct
        if C then local _, _, p = C.Rate(r.name) cpct = p end
        local con = (cpct ~= nil)
            and ("  " .. T.text(cpct >= 90 and "good" or cpct >= 60 and "gold" or "warn",
                 "consumes " .. cpct .. "%"))
            or ""
        ns.Print("  %-14s %s  %s%s", r.name, T.text(colour, r.pct .. "%"),
            T.text("muted", r.earned .. " of " .. r.raided), con)
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

--- `/bisg buffs` - what the client actually calls what is on you, with ids.
---
--- This exists because the alternative was typing a flask list from memory, which is how a spell
--- list gets reasoned out of a build number and comes out wrong. Buff yourself the way you would
--- for a raid, run this, and the addon learns THIS client's ids rather than somebody's recollection.
local function buffs()
    local C, T = ns.C, ns.T
    local list = C.Auras("player")
    if #list == 0 then
        ns.Print("nothing on you the client will list.")
        return
    end
    ns.Print("what is on you right now:")
    for _, a in ipairs(list) do
        local kind = C.Taught()[a.id]
        ns.Print("  %-6d %-28s %s", a.id, a.name,
            kind and T.text("good", kind) or T.text("muted", "not taught"))
    end
    ns.Print("  %s", T.text("muted",
        "|cffb980ff/bisg teach <id> flask|battle|guardian|food|r to write one down."))
end

--- `/bisg teach <id> <kind>` and `/bisg forget <id>`.
local function teach(rest)
    local C, T = ns.C, ns.T
    local id, kind = tostring(rest or ""):match("^(%d+)%s+(%a+)$")
    if not id then
        ns.Print("%s", T.text("muted", "/bisg teach <spell id> flask|battle|guardian|food"))
        return
    end
    kind = kind:lower()
    if not C.Teach(id, kind) then
        ns.Print("%s is not one of flask, battle, guardian, food.", kind)
        return
    end
    ns.Print("%s is a %s.", T.text("accent", id), T.text("good", kind))
    if not C.Ready() then
        ns.Print("  %s", T.text("muted", "Still not enough to judge anyone: food is needed, plus"
            .. " a flask or both elixir kinds. Until then consumables read as unknown, not as nought."))
    end
end

--- `/bisg consumes` - the readiness table, or an honest refusal.
local function consumes()
    local C, G, T = ns.C, ns.G, ns.T
    if not C.Ready() then
        ns.Print("consumables: %s", T.text("warn", "nothing taught yet"))
        ns.Print("  %s", T.text("muted", "Buff up the way you would for a raid, then"
            .. " |cffb980ff/bisg buffs|r. Nothing is guessed here - an invented flask list would"
            .. " report the whole raid at nought percent and look exactly like data."))
        return
    end
    local rows, any = {}, false
    for _, r in ipairs(G.Everyone()) do
        local ready, counted, pct = C.Rate(r.name)
        if pct ~= nil then
            any = true
            rows[#rows + 1] = { name = r.name, pct = pct, ready = ready, counted = counted }
        end
    end
    if not any then
        ns.Print("consumables: %s", T.text("muted", "no pulls judged yet - it reads at the pull,"
            .. " so the next boss is the first one counted."))
        return
    end
    table.sort(rows, function(a, b)
        if a.pct ~= b.pct then return a.pct > b.pct end
        return a.name < b.name
    end)
    ns.Print("consumables, at the pull:")
    for _, r in ipairs(rows) do
        local colour = (r.pct >= 90 and "good") or (r.pct >= 60 and "gold") or "warn"
        ns.Print("  %-14s %s  %s", r.name, T.text(colour, r.pct .. "%"),
            T.text("muted", r.ready .. " of " .. r.counted .. " pull(s)"))
    end
end

function ns.Say(cmd, rest)
    if cmd == "nights" then return nights() end
    if cmd == "me" then return me() end
    if cmd == "buffs" then return buffs() end
    if cmd == "learn" then
        local C, T = ns.C, ns.T
        local got, unknown = C.Learn()
        if #got == 0 then
            ns.Print("nothing on you names itself as a consumable.")
        else
            ns.Print("learned from what is on you:")
            for _, a in ipairs(got) do
                ns.Print("  %-6d %-28s %s", a.id, a.name, T.text("good", a.kind))
            end
        end
        for _, a in ipairs(unknown) do
            ns.Print("  %-6d %-28s %s", a.id, a.name, T.text("muted", "not recognised"))
        end
        ns.Print("  %s", T.text("muted", C.Ready()
            and "That is enough to judge a pull. |cffb980ff/bisg buffs|r shows the whole list."
            or "Still not enough - food is needed, plus a flask or two elixirs."))
        return
    end
    if cmd == "teach" then return teach(rest) end
    if cmd == "consumes" or cmd == "consumables" then return consumes() end
    if cmd == "forget" then
        local id = tostring(rest or ""):match("^(%d+)$")
        if id and ns.C.Forget(id) then ns.Print("%s forgotten.", id)
        else ns.Print("/bisg forget <spell id>") end
        return
    end
    if cmd == "help" then
        ns.Print("version %s", ns.VERSION)
        ns.Print("  %s  everyone's attendance", ns.T.text("accent", "/bisg"))
        ns.Print("  %s  the raid nights themselves", ns.T.text("accent", "/bisg nights"))
        ns.Print("  %s  your own, night by night", ns.T.text("accent", "/bisg me"))
        ns.Print("  %s  who turns up prepared", ns.T.text("accent", "/bisg consumes"))
        ns.Print("  %s  what is on you, with ids", ns.T.text("accent", "/bisg buffs"))
        ns.Print("  %s", ns.T.text("muted", "/bisg teach <id> flask|battle|guardian|food"))
        return
    end
    return all()
end
