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

--- The four things an aura can be. A kind the addon does not know is not written down.
C.KINDS = { flask = true, battle = true, guardian = true, food = true }

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
    local kinds = {}
    for _, kind in pairs(C.Taught()) do kinds[kind] = true end
    if not kinds.food then return false end
    return kinds.flask == true or (kinds.battle == true and kinds.guardian == true)
end

function C.Teach(spellID, kind)
    spellID = tonumber(spellID)
    if not spellID or not C.KINDS[kind] then return false end
    C.Taught()[spellID] = kind
    return true
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

--- Was this unit prepared? Returns a table, or nil when the addon has not been taught enough to
--- have an opinion. nil is not "no" and must never be counted as one.
function C.Check(unit)
    if not C.Ready() then return nil end
    local flask = hasKind(unit, "flask")
    local battle = hasKind(unit, "battle")
    local guardian = hasKind(unit, "guardian")
    local food = hasKind(unit, "food")
    return {
        flask = flask, battle = battle, guardian = guardian, food = food,
        ok = ((flask or (battle and guardian)) and food) and true or false,
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
function C.Rate(name)
    local ready, counted = 0, 0
    for _, night in ipairs(ns.G.Nights()) do
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
