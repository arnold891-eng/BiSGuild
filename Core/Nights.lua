--[[
  BiSGuild :: Core/Nights.lua - what a raid night is, and who was there for it.

  THE RULE, Arn's own words (4 Oct 2026): "if there were there for at least half the kills,
  sometimes life happens". So the NIGHT is the unit, not the boss. Turn up, stay for half of what
  died, and the night is yours - leaving at nine for a sick child costs nothing. A council that
  wanted stricter than that could compute it from what is stored here; this file only decides the
  headline.

  "At least half" is asked as `present * 2 >= total`, never `present >= total / 2`: three kills and
  one attendance is 1 vs 1.5, and floating point is not a thing to trust a person's raid record to.

  WHAT A NIGHT IS comes from BiSMemories, settled 0.4.0 and reused here on purpose: a run of kills
  with no three-hour gap in it. A clear that starts at eight and ends at twenty to one is ONE night,
  not two, and a break for dinner does not split it. Two addons that disagree about what night it
  was would be worse than either of them being wrong alone.

  NOTHING HERE READS THE CLIENT. Every function takes what it needs and returns an answer, so the
  suite can run a whole raid tier through it in a millisecond. Roster.lua does the client half.
]]
local ADDON, ns = ...

local G = {}
ns.G = G

G.GAP = 3 * 60 * 60     -- seconds of quiet that end a raid night (the same rule as BiSMemories)

local function db() return ns.DB() end

--- Every night on record, oldest first. Stored on the saved variables, never rebuilt.
function G.Nights()
    local d = db()
    d.nights = type(d.nights) == "table" and d.nights or {}
    return d.nights
end

--- The night a moment belongs to: the last one, if it is still within the gap, or a new one.
--- Returns the night and whether it had to be started.
function G.NightAt(at, zone)
    at = tonumber(at) or 0
    local nights = G.Nights()
    local last = nights[#nights]
    if last and (at - (tonumber(last.stop) or 0)) <= G.GAP then
        last.stop = at
        -- the zone of a night is where most of it happened; the first answer is kept unless the
        -- night had no zone at all, because a corpse run through a different zone is not a move
        if not last.zone and zone then last.zone = zone end
        return last, false
    end
    local night = { start = at, stop = at, zone = zone, kills = {} }
    nights[#nights + 1] = night
    return night, true
end

--- Write down a boss that died, and who was standing there when it did.
--- `who` is a plain list of short names - Roster.lua has already dropped anything secret.
function G.Record(boss, at, who, zone)
    if type(who) ~= "table" or #who == 0 then return nil, "nobody" end
    local night = G.NightAt(at, zone)
    night.kills[#night.kills + 1] = {
        boss = tostring(boss or "a boss"),
        at = tonumber(at) or 0,
        who = who,
    }
    return night, nil
end

--- How many kills a night had, and how many of them one person saw.
function G.Saw(night, name)
    local total, seen = 0, 0
    for _, kill in ipairs((night and night.kills) or {}) do
        total = total + 1
        for _, who in ipairs(kill.who or {}) do
            if who == name then seen = seen + 1 break end
        end
    end
    return seen, total
end

--- Did this person earn the night? At least half the kills.
--- A night where nothing died is nobody's night and nobody's absence - see G.Rate.
function G.Earned(night, name)
    local seen, total = G.Saw(night, name)
    if total == 0 then return false end
    return seen * 2 >= total
end

--- Someone's attendance: nights earned out of nights the GUILD raided.
---
--- The denominator counts only nights where something died. A night the raid formed and wiped all
--- evening is not an absence for the person who was there all of it, and counting it would punish
--- exactly the people who stayed.
---
--- Returns earned, raided, and the percentage as a whole number (nil when nothing is on record -
--- a person with no history has no attendance, which is not the same as nought percent).
function G.Rate(name, at)
    local earned, raided = 0, 0
    for _, night in ipairs(G.Settled(at)) do
        raided = raided + 1
        if G.Earned(night, name) then earned = earned + 1 end
    end
    if raided == 0 then return 0, 0, nil end
    return earned, raided, math.floor((earned / raided) * 100 + 0.5)
end

--- TONIGHT IS NOT PART OF THE RECORD (4 Oct 2026).
---
--- Arn, on why their log-based numbers being a raid behind never mattered: "obv someone that is
--- rolling on loot is here today". The person being voted on is standing in the raid by
--- definition, so tonight says nothing about them - what is being judged is whether they have been
--- turning up and coming prepared BEFORE this.
---
--- It is also the only honest way to count it. A night in progress has not finished having kills,
--- so "half of them" is not a question that can be answered yet: somebody at 1 of 1 reads as
--- having earned the night, and will not have if they leave and six more bosses die. Counting it
--- flatters whoever happens to be standing there when the council looks, which is everyone up for
--- the item.
---
--- A night is settled when it has kills in it and the quiet since its last one is longer than the
--- gap that ends a night - the same rule that decides what night a kill belongs to.
function G.Settled(at)
    at = tonumber(at) or (GetServerTime and GetServerTime()) or (time and time()) or 0
    local out = {}
    for _, night in ipairs(G.Nights()) do
        if #(night.kills or {}) > 0 and (at - (tonumber(night.stop) or 0)) > G.GAP then
            out[#out + 1] = night
        end
    end
    return out
end

--- The night in progress, if there is one. Shown beside the record, never inside it.
function G.Tonight(at)
    at = tonumber(at) or (GetServerTime and GetServerTime()) or (time and time()) or 0
    local nights = G.Nights()
    local last = nights[#nights]
    if last and #(last.kills or {}) > 0 and (at - (tonumber(last.stop) or 0)) <= G.GAP then
        return last
    end
    return nil
end

--- Everyone the addon has ever seen at a kill, with their rate. Best first, then by name, so the
--- same data always prints in the same order.
function G.Everyone()
    local seen = {}
    for _, night in ipairs(G.Nights()) do
        for _, kill in ipairs(night.kills or {}) do
            for _, who in ipairs(kill.who or {}) do seen[who] = true end
        end
    end
    local out = {}
    for name in pairs(seen) do
        local earned, raided, pct = G.Rate(name)
        out[#out + 1] = { name = name, earned = earned, raided = raided, pct = pct or 0 }
    end
    table.sort(out, function(a, b)
        if a.pct ~= b.pct then return a.pct > b.pct end
        return a.name < b.name
    end)
    return out
end

--- Nights that actually count, newest first - what a report shows.
function G.Raided()
    local out = {}
    for _, night in ipairs(G.Nights()) do
        if #(night.kills or {}) > 0 then out[#out + 1] = night end
    end
    table.sort(out, function(a, b) return (a.start or 0) > (b.start or 0) end)
    return out
end
