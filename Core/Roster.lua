--[[
  BiSGuild :: Core/Roster.lua - who is standing here, as plain names.

  The only file that asks the client anything. Nights.lua decides what the answer means.

  A NAME CAN BE A SECRET VALUE. Measured 4 Oct 2026 on WoW Forever, the same day LibBiSComm was
  fixed for it: `UnitName` can hand back a value that is TRUTHY and errors the moment anything
  reads it - a match, a comparison, or being used as a table key, which is exactly what an
  attendance list does with every name it takes. A roster that took one would not be a wrong
  attendance record; it would be a red error in the middle of a boss kill, which is the worst
  possible moment to be the addon that broke.

  `lib.Short` already answers nil for a secret (minor 7) and strips the realm, so it is the one
  door used here. Without the lib - a client where it failed to load - the fallback does the same
  two tests itself rather than trusting the name.

  A dropped name is a person not recorded for that kill. That is the honest outcome: we do not know
  who they were, and guessing would put a wrong name in somebody's raid record.
]]
local ADDON, ns = ...

local R = {}
ns.R = R

local function Secret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

--- A name we can actually use, or nil.
function R.Short(name)
    local lib = _G.LibBiSComm
    if lib and lib.Short then return lib.Short(name) end
    if name == nil or Secret(name) or type(name) ~= "string" then return nil end
    return string.match(name, "^([^%-]+)") or name
end

--- Is the player in a raid or party right now?
function R.InGroup()
    if IsInRaid and IsInRaid() then return true end
    if IsInGroup and IsInGroup() then return true end
    return false
end

--- Everyone in the group, as plain short names, the player included.
---
--- Walks raid1..N when in a raid and party1..N plus the player otherwise, because `GetNumGroupMembers`
--- counts differently in the two and a five-man that loses its leader must not lose a name.
--- Offline and dead both count: a corpse at the boss was at the boss, and attendance is about
--- turning up, not about surviving.
function R.Names()
    local out, seen = {}, {}
    local function add(name)
        local short = R.Short(name)
        if short and not seen[short] then
            seen[short] = true
            out[#out + 1] = short
        end
    end

    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if IsInRaid and IsInRaid() then
        for i = 1, n do add(UnitName and UnitName("raid" .. i)) end
    else
        for i = 1, math.max(0, n - 1) do add(UnitName and UnitName("party" .. i)) end
        add(UnitName and UnitName("player"))
    end
    table.sort(out)
    return out
end

--- Where this is happening, for the night's label. A hidden zone is written as nil rather than as
--- the word the client refused to say - BiSMemories 0.5.1 learned that one the hard way.
function R.Zone()
    local z = GetRealZoneText and GetRealZoneText()
    if z == nil or Secret(z) or type(z) ~= "string" or z == "" then return nil end
    return z
end
