--[[
  BiSGuild :: Core/Consumes.lua - was this person ready when the boss pulled?

  Arn's definition (4 Oct 2026): a flask, OR a battle and a guardian elixir together, AND food.

  THE LIST IS LEARNED, NOT GUESSED, and this is the whole design. Every consumable check needs to
  know which auras ARE consumables, and the obvious way to write this file is to type out the
  flask and elixir spell ids from memory. That is the Earth Shield mistake wearing a new hat: on
  3 Oct a spell list was reasoned out of a build number and Arn had to say "i do have water
  shield". A wrong aura list does not error. It reports the whole raid at nought percent and looks
  exactly like data.

  So nothing ships with a list. `/bisg buffs` reads what the client actually calls the auras on
  YOU, with their ids, and `/bisg teach` writes them down. The numbers come from this guild's own
  client, and they are right the first time or they are visibly empty.

  WHICH IS WHY "NOT TAUGHT" IS nil AND NOT false. An empty list must never read as "nobody was
  prepared" - it must read as "the addon has not been told what a flask is". A percentage computed
  from nothing is the most confident kind of wrong, and it is the kind a council would act on.

  THE MOMENT IS THE PULL, not the kill. Food is lost on death, so checking at the kill would mark
  down exactly the people who died doing it. ENCOUNTER_START is the question "were you ready when
  this began", which is the one worth asking.
]]
local ADDON, ns = ...

local C = {}
ns.C = C

--- The kinds an aura can be. A kind the addon does not know is not written down.
---
--- `elixir` is the one the NAME can reach. Arn asked "cant we just check that stuff with the logs?"
--- - and the honest answer is that nothing in the client, log included, ever says "this is a flask".
--- What the client DOES say is what the thing is called, and "Flask of Relentless Assault" and
--- "Well Fed" classify themselves. Battle and guardian do not: "Elixir of Major Agility" and
--- "Elixir of Major Defense" read identically, and the difference is in the item, not the aura.
---
--- So the pair is counted instead of named. The game will not let two battle elixirs sit on one
--- person at once, nor two guardians - so TWO elixirs up at the same time is one of each by the
--- game's own rule, without this addon having to know which is which.
---
--- THAT IS AN ASSUMPTION ABOUT THE GAME, not a measurement, and it is the only one in this file.
--- It is written here so it can be argued with: if this client lets two of a kind stack, the pair
--- test is wrong and battle/guardian should be taught by hand instead, which still works.
C.KINDS = { flask = true, battle = true, guardian = true, food = true, elixir = true }

local function db() return ns.DB() end

--- spell id -> kind, as taught on this account.
function C.Taught()
    local d = db()
    d.taught = type(d.taught) == "table" and d.taught or {}
    return d.taught
end

--- Has anybody told this addon what a flask looks like yet?
--- Needs at least food AND one of (flask | battle+guardian) to be able to answer at all.
function C.Ready()
    local kinds, elixirs = {}, 0
    for _, kind in pairs(C.Taught()) do
        kinds[kind] = true
        if kind == "elixir" then elixirs = elixirs + 1 end
    end
    if not kinds.food then return false end
    if kinds.flask then return true end
    if kinds.battle and kinds.guardian then return true end
    return elixirs >= 2      -- the pair can only be counted once two are known
end

function C.Teach(spellID, kind)
    spellID = tonumber(spellID)
    if not spellID or not C.KINDS[kind] then return false end
    C.Taught()[spellID] = kind
    return true
end

--- WHAT THE CLIENT CALLS IT IS THE CLASSIFIER (4 Oct 2026). Arn: "cant we just check that stuff
--- with the logs?" Nothing in the client, log included, ever says "this is a flask" - but the
--- client does say what the thing is CALLED, and most of them name themselves.
---
--- These patterns are English and are not pretending otherwise. They are a SUGGESTION: `/bisg
--- learn` prints every guess and writes it down, and `/bisg buffs` shows what is on record, so a
--- wrong guess is visible in one line and `/bisg forget <id>` undoes it. A guild on another client
--- teaches by hand, which has worked from the start.
function C.Guess(name)
    name = tostring(name or "")
    if name:find("Well Fed", 1, true) then return "food" end
    if name:match("^Flask") then return "flask" end
    if name:find("Elixir", 1, true) then return "elixir" end
    return nil
end

--- `/bisg learn` - read your own buffs and write down everything that names itself.
--- Returns what it learned and what it could not place.
function C.Learn()
    local got, unknown = {}, {}
    for _, a in ipairs(C.Auras("player")) do
        local kind = C.Guess(a.name)
        if kind and C.Teach(a.id, kind) then
            got[#got + 1] = { id = a.id, name = a.name, kind = kind }
        elseif not C.Taught()[a.id] then
            unknown[#unknown + 1] = a
        end
    end
    return got, unknown
end

function C.Forget(spellID)
    spellID = tonumber(spellID)
    if not spellID then return false end
    C.Taught()[spellID] = nil
    return true
end

--- Every helpful aura on a unit, as { id =, name = }.
---
--- The index walk is the only reader that can list auras it was not already told about, which is
--- exactly what teaching needs - but it HARD ERRORS inside an instance on Forever (measured
--- 3 Oct, BiSHealing). So it is wrapped, and a refusal is an empty list rather than a broken pull.
--- Reading by id is what works under that lockdown, and that is what the checking path uses once
--- the list exists.
function C.Auras(unit)
    local out = {}
    local byIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    for i = 1, 40 do
        local id, name
        if byIndex then
            local ok, a = pcall(byIndex, unit, i, "HELPFUL")
            if not ok then break end
            if type(a) ~= "table" then break end
            id, name = a.spellId, a.name
        elseif UnitBuff then
            local ok, n, _, _, _, _, _, _, _, _, sid = pcall(UnitBuff, unit, i)
            if not ok then break end
            if n == nil then break end
            id, name = sid, n
        else
            break
        end
        if tonumber(id) then out[#out + 1] = { id = tonumber(id), name = tostring(name or "?") } end
    end
    return out
end

--- Does this unit have a given kind up? Asked by id, which is the reader that survives a lockdown.
local function hasKind(unit, want)
    local taught = C.Taught()
    local byID = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
    for spellID, kind in pairs(taught) do
        if kind == want then
            if byID then
                local ok, a = pcall(byID, unit, spellID)
                if ok and type(a) == "table" then return true end
            else
                for _, aura in ipairs(C.Auras(unit)) do
                    if aura.id == spellID then return true end
                end
            end
        end
    end
    return false
end

--- How many DISTINCT auras taught as `elixir` are up. Two is the pair - see C.KINDS.
local function elixirCount(unit)
    local n = 0
    local byID = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
    local walked
    for spellID, kind in pairs(C.Taught()) do
        if kind == "elixir" then
            if byID then
                local ok, a = pcall(byID, unit, spellID)
                if ok and type(a) == "table" then n = n + 1 end
            else
                walked = walked or C.Auras(unit)
                for _, aura in ipairs(walked) do
                    if aura.id == spellID then n = n + 1 break end
                end
            end
        end
    end
    return n
end

--- Was this unit prepared? Returns a table, or nil when the addon has not been taught enough to
--- have an opinion. nil is not "no" and must never be counted as one.
function C.Check(unit)
    if not C.Ready() then return nil end
    local flask = hasKind(unit, "flask")
    local battle = hasKind(unit, "battle")
    local guardian = hasKind(unit, "guardian")
    local food = hasKind(unit, "food")
    local pair = (battle and guardian) or (elixirCount(unit) >= 2)
    return {
        flask = flask, battle = battle, guardian = guardian, food = food, pair = pair,
        ok = ((flask or pair) and food) and true or false,
    }
end

--- Everyone in the raid, at this moment: name -> true/false. nil when nothing can be judged.
function C.Snapshot()
    if not C.Ready() then return nil end
    local R = ns.R
    if not (R and R.InRaid()) then return nil end
    local out = {}
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    for i = 1, n do
        local unit = "raid" .. i
        local name = R.Short(UnitName and UnitName(unit))
        if name then
            local got = C.Check(unit)
            if got then out[name] = got.ok end
        end
    end
    return out
end

--- Someone's consumable record: pulls they were ready for, out of pulls they were there for.
--- Returns ready, counted, and the percentage - or nil when nothing has ever been judged, which
--- is the honest answer for a guild that has not taught the addon its flasks.
--- Tonight is left out for the same reason it is left out of attendance: the person being voted on
--- is standing in the raid, so tonight says nothing about them. See G.Settled.
function C.Rate(name, at)
    local ready, counted = 0, 0
    for _, night in ipairs(ns.G.Settled(at)) do
        for _, kill in ipairs(night.kills or {}) do
            local seen = kill.ready
            if type(seen) == "table" and seen[name] ~= nil then
                counted = counted + 1
                if seen[name] == true then ready = ready + 1 end
            end
        end
    end
    if counted == 0 then return 0, 0, nil end
    return ready, counted, math.floor((ready / counted) * 100 + 0.5)
end
