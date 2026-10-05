--[[
  BiSGuild :: Core/Watch.lua - the two events that mean a boss died.

  BOTH, because neither is reliable alone and they overlap. `BOSS_KILL` does not fire for every
  encounter on every client, and `ENCOUNTER_END` carries a success flag that is the only way to
  tell a kill from a wipe. BiSMemories watches the same pair for the same reason; this file is the
  second user of that measurement, not a fresh guess.

  A WIPE IS NOT A KILL. `ENCOUNTER_END` fires either way and `success` is the difference. An
  attendance record that counted wipes would reward the night the raid threw itself at a boss for
  three hours exactly as much as the night it cleared - and would hand the people who left before
  the wipes a better record than the people who stayed for them.

  THE SAME BOSS TWICE. Both events can fire for one kill, so a kill inside SETTLE seconds of the
  last one with the same name is the same kill. Not a timestamp equality test: the two events
  arrive on different frames.
]]
local ADDON, ns = ...

local W = {}
ns.W = W

W.SETTLE = 30     -- seconds; two reports of one boss inside this are one kill

local lastName, lastAt = nil, -math.huge

local function now()
    return (GetServerTime and GetServerTime()) or (time and time()) or 0
end

--- A boss died. Returns the night it went into, or nil and why not.
function W.Kill(name, at)
    at = tonumber(at) or now()
    name = tostring(name or "a boss")

    if name == lastName and (at - lastAt) < W.SETTLE then return nil, "already" end

    local R, G = ns.R, ns.G
    if not (R and G) then return nil, "not loaded" end
    -- A RAID GROUP, NOT ANY GROUP (4 Oct 2026). Arn: "there are no raids in wow forever yet" - and
    -- the first thing that told me was that dungeons still have bosses. `InGroup` was true for a
    -- five-man, so a Blackfathom run would have built raid nights out of dungeon bosses, and on
    -- Forever that is the ONLY thing it would ever have recorded. Even on TBC it rots the number
    -- quietly: a Tuesday heroic counting the same as Black Temple.
    --
    -- `IsInRaid` is the honest line. A guild that raids converts to a raid group to do it, and a
    -- five-man never is one.
    if not R.InRaid() then return nil, "not a raid" end

    local who = R.Names()
    if #who == 0 then return nil, "nobody" end

    local night = G.Record(name, at, who, R.Zone())
    -- THE PULL'S ANSWER, not this moment's. Food is lost on death, so judging readiness at the
    -- kill would mark down precisely the people who died doing it. W.Pull() took the reading when
    -- the fight began; if it never fired - a client with no ENCOUNTER_START, a boss that does not
    -- raise one - there is no reading, and no reading is nil rather than a row of failures.
    if night and W.pulled then
        night.kills[#night.kills].ready = W.pulled
    end
    W.pulled = nil
    lastName, lastAt = name, at
    return night, nil
end

--- The fight began: who was ready. Held until the boss dies, then written onto the kill.
function W.Pull()
    local C = ns.C
    W.pulled = C and C.Snapshot() or nil
    return W.pulled
end

--- Only for the suite: a fresh file has seen no kills.
function W.Forget()
    lastName, lastAt = nil, -math.huge
    W.pulled = nil
end

function W.Start()
    local f = CreateFrame("Frame")
    f:RegisterEvent("BOSS_KILL")
    f:RegisterEvent("ENCOUNTER_END")
    f:RegisterEvent("ENCOUNTER_START")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "ENCOUNTER_START" then
            W.Pull()
        elseif event == "BOSS_KILL" then
            local _, name = ...
            W.Kill(name)
        elseif event == "ENCOUNTER_END" then
            local _, name, _, _, success = ...
            if success ~= 1 and success ~= true then return end     -- a wipe is not a kill
            W.Kill(name)
        end
    end)
    W.events = f
    return f
end
