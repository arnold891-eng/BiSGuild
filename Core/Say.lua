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
    local nights = #G.Raided()
    if nights == 0 then
        ns.Print("no raid nights on record yet.")
        ns.Print("  %s", T.text("muted", "Attendance cannot be worked out backwards - it starts the"
            .. " first boss this addon sees die while you are in a group."))
        return
    end
    ns.Print("attendance over %s raid night(s):", T.text("accent", tostring(nights)))
    for _, r in ipairs(rows) do
        local colour = (r.pct >= 75 and "good") or (r.pct >= 50 and "gold") or "warn"
        ns.Print("  %-14s %s  %s", r.name, T.text(colour, r.pct .. "%"),
            T.text("muted", r.earned .. " of " .. r.raided))
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

function ns.Say(cmd)
    if cmd == "nights" then return nights() end
    if cmd == "me" then return me() end
    if cmd == "help" then
        ns.Print("version %s", ns.VERSION)
        ns.Print("  %s  everyone's attendance", ns.T.text("accent", "/bisg"))
        ns.Print("  %s  the raid nights themselves", ns.T.text("accent", "/bisg nights"))
        ns.Print("  %s  your own, night by night", ns.T.text("accent", "/bisg me"))
        return
    end
    return all()
end
