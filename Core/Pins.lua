--[[
  BiSGuild :: Core/Pins.lua - guildmates' dots on the game's own world map.

  Arn, 16 Oct 2026: guildmates on the world map, and "the problem is not everyone is going to install
  OpenMap". So the dots go on Blizzard's world map through HereBeDragons-Pins - the library Questie
  and BiS Tools' farm pins draw with - and any map addon that shows that library's pins shows them
  too (OpenMap's changelog says it does). Nobody needs anything but BiS Guild.

  WHERE THE DOTS COME FROM: LibBiSComm's shared spots (minor 12) - every BiS addon sends its player's
  spot on the guild channel while they move, outside instances. A guildmate without a BiS addon has
  no dot; the terminal's WHERE list still shows their zone from the roster. Your own position is the
  game's arrow, not a dot.

  ON THE ZONE MAP AND ONE LEVEL UP (HBD_PINS_WORLDMAP_SHOW_PARENT), as BiS Tools' farm pins, which
  Arn has seen land right. Not the whole world: OpenMap's notes (16 Oct) say this library's continent
  and world positions come out wrong on Forever.

  ONE FRAME PER PIN, never shared with the minimap (BiS Tools learned it 6 Oct: the library re-parents
  a pin into whichever map draws it, and a frame on two maps shows on neither).

  `/bisg dots off` takes them all away; `/bisg dots on` brings them back.
]]
local ADDON, ns = ...

local M = {}
ns.Pins = M

M.SIZE = 9
M.SWEEP = 30            -- seconds: stale spots are dropped by the lib; this notices they went
M.pins = {}             -- sender -> { frame, map, x, y }
M.pool = {}

local function HBD() return LibStub and LibStub("HereBeDragons-Pins-2.0", true) end
local function Lib() return _G.LibBiSComm end

function M.On() return ns.DB().mapDots ~= false end

local function NewPin()
    local b = table.remove(M.pool)
    if b then return b end
    b = CreateFrame("Button", nil, UIParent)
    b:SetSize(M.SIZE, M.SIZE)
    b.tex = b:CreateTexture(nil, "OVERLAY")
    b.tex:SetAllPoints()
    b.edge = b:CreateTexture(nil, "BORDER")
    b.edge:SetPoint("TOPLEFT", -1, 1)
    b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    b.edge:SetColorTexture(0, 0, 0, 1)
    b:SetScript("OnEnter", function(self)
        local tip = _G.GameTooltip
        if not (tip and self.who) then return end
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:AddLine(self.who)
        local m = ns.K and ns.K.Member(self.who)
        if m then
            tip:AddLine(("level %s  %s"):format(tostring(m.level or "?"), tostring(m.rank or "")), 1, 1, 1)
            if m.zone then tip:AddLine(m.zone, 0.7, 0.7, 0.7) end
        end
        tip:AddLine("BiS Guild", 0.73, 0.5, 1)
        tip:Show()
    end)
    b:SetScript("OnLeave", function() if _G.GameTooltip then _G.GameTooltip:Hide() end end)
    b:SetScript("OnClick", function(self)
        if self.who and ns.K and ns.K.Show then ns.K.Show(self.who .. " <raider>") end
    end)
    return b
end

local function Release(H, sender)
    local p = M.pins[sender]
    if not p then return end
    if H then H:RemoveWorldMapIcon(M, p.frame) end
    p.frame.who = nil
    p.frame:Hide()
    M.pool[#M.pool + 1] = p.frame
    M.pins[sender] = nil
end

function M.Clear()
    local H = HBD()
    for sender in pairs(M.pins) do Release(H, sender) end
end

--- Draw what the lib knows now. Answers how many pins are up, for the suite and `/bisg dots`.
function M.Update()
    local H, lib = HBD(), Lib()
    if not (H and lib and lib.Spots) or not M.On() then M.Clear() return 0 end
    local seen, n = {}, 0
    local colours = _G.RAID_CLASS_COLORS
    for sender, s in pairs(lib:Spots()) do
        if type(sender) == "string" and type(s) == "table" and s.map and s.x and s.y then
            seen[sender] = true
            local p = M.pins[sender]
            if p and (p.map ~= s.map or p.x ~= s.x or p.y ~= s.y) then
                H:RemoveWorldMapIcon(M, p.frame)
                p.placed = false
            end
            if not p then
                p = { frame = NewPin() }
                M.pins[sender] = p
            end
            if not p.placed then
                local b = p.frame
                b.who = sender
                local m = ns.K and ns.K.Member(sender)
                local cc = m and m.class and colours and colours[m.class]
                if cc then b.tex:SetColorTexture(cc.r, cc.g, cc.b, 1) else b.tex:SetColorTexture(0.93, 0.91, 0.96, 1) end
                p.map, p.x, p.y = s.map, s.x, s.y
                p.placed = H:AddWorldMapIconMap(M, b, s.map, s.x, s.y, _G.HBD_PINS_WORLDMAP_SHOW_PARENT) and true or false
            end
            if p.placed then n = n + 1 end
        end
    end
    for sender in pairs(M.pins) do
        if not seen[sender] then Release(H, sender) end
    end
    M.count = n
    return n
end

--- A spot arrived: draw within the second, not once per message (a guild moving together sends many).
function M.Soon()
    if M._armed then return end
    M._armed = true
    if C_Timer and C_Timer.After then
        C_Timer.After(1, function() M._armed = false M.Update() end)
    else
        M._armed = false
        M.Update()
    end
end

function M.Boot()
    local lib = Lib()
    if not lib or M._booted then return end
    M._booted = true
    if lib.RegisterCallback then lib:RegisterCallback("SPOT", function() M.Soon() end) end
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(M.SWEEP, function() M.Update() end) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() M.Boot() M.Update() end)

ns.parts["Core/Pins.lua"] = "0.1.0"
