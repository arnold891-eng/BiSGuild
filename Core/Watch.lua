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
    if not R.InGroup() then return nil, "solo" end

    local who = R.Names()
    if #who == 0 then return nil, "nobody" end

    local night = G.Record(name, at, who, R.Zone())
    lastName, lastAt = name, at
    return night, nil
end

--- Only for the suite: a fresh file has seen no kills.
function W.Forget()
    lastName, lastAt = nil, -math.huge
end

function W.Start()
    local f = CreateFrame("Frame")
    f:RegisterEvent("BOSS_KILL")
    f:RegisterEvent("ENCOUNTER_END")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "BOSS_KILL" then
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
