--[[
  BiSGuild :: Core/Init.lua - made by _bisdev/new-addon.sh (the house skeleton).

  What every BiS addon starts with, already wired and tested:
    * ns.T      the palette, resolved PER CALL (BiSTheme loads after us, alphabetically)
    * ns.VERSION the TOC's ## Version and nothing else's
    * ns.Print  one chat line with the addon's name in the accent colour
    * BiSGuildDB SavedVariables with defaults filled on ADDON_LOADED
    * the shared BiS channel (LibBiSComm): registered, booted, its off switch remembered
    * /bisg - says hello: version, comm on/off, peers. Replace it with the real addon.
]]
local ADDON, ns = ...

local HEX = {
  ink = "ece8f6", muted = "968ead", accent = "b980ff", good = "4fd0cf", warn = "f08cb0", gold = "e5c04a",
}
local T = {}
ns.T = T
T.hex = HEX
function T.rgb(name)
  local real = _G.BiSTheme
  if real and real.hex and real.hex[name] and real.rgb then return real.rgb(name) end
  local hex = HEX[name] or HEX.ink
  return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end
function T.text(name, s)
  local real = _G.BiSTheme
  if real and real.hex and real.hex[name] and real.text then return real.text(name, s) end
  return "|cff" .. (HEX[name] or HEX.ink) .. tostring(s) .. "|r"
end

ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version"))
  or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or "dev"

function ns.Print(fmt, ...)
  local msg = select("#", ...) > 0 and fmt:format(...) or fmt
  DEFAULT_CHAT_FRAME:AddMessage(T.text("accent", ADDON) .. " " .. msg)
end

ns.DEFAULTS = { comm = true }
local function db()
  BiSGuildDB = type(BiSGuildDB) == "table" and BiSGuildDB or {}
  for k, v in pairs(ns.DEFAULTS) do
    if BiSGuildDB[k] == nil then BiSGuildDB[k] = v end
  end
  return BiSGuildDB
end
ns.DB = db

--- ESC FOR A WINDOW, SAFE IN COMBAT (16 Oct 2026). Arn opened the terminal mid-fight and got
--- ADDON_ACTION_BLOCKED: SetPropagateKeyboardInput is protected in combat. So:
---   * in combat it is never called - the keyboard is switched on when combat ends instead;
---   * ESC still runs `onEscape` in combat; the game may open its menu too (a key cannot be held back
---     in combat), which is harmless;
---   * the "swallow this ESC" is undone a moment later, so the NEXT key never vanishes and a fight
---     starting right after can never leave every key swallowed.
local function locked() return InCombatLockdown and InCombatLockdown() end
function ns.EscKeys(f, onEscape)
    local function arm()
        if locked() then return false end
        f:EnableKeyboard(true)
        f:SetPropagateKeyboardInput(true)
        return true
    end
    f:SetScript("OnKeyDown", function(self, key)
        if key ~= "ESCAPE" then
            if not locked() then self:SetPropagateKeyboardInput(true) end
            return
        end
        if not locked() then
            self:SetPropagateKeyboardInput(false)
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function() if not locked() then self:SetPropagateKeyboardInput(true) end end)
            end
        end
        onEscape()
    end)
    if not arm() then
        local w = CreateFrame("Frame")
        w:RegisterEvent("PLAYER_REGEN_ENABLED")
        w:SetScript("OnEvent", function(self) if arm() then self:UnregisterAllEvents() end end)
    end
end

-- the shared BiS channel: no setting of this addon may gate it; only /biscomm off does,
-- and that choice survives a logout here
ns.Comm = {}
function ns.Comm.Boot()
  local lib = _G.LibBiSComm
  if not lib then return end
  lib:RegisterAddon(ADDON, ns.VERSION)
  if db().comm == false then lib:SetEnabled(false) end
  if db().commShare == false and lib.SetSharing then lib:SetSharing(false) end   -- /biscomm share off (minor 12)
  lib:Boot()
end
function ns.Comm.Save()
  local lib = _G.LibBiSComm
  if lib then db().comm = lib:Enabled() end
  if lib and lib.Sharing then db().commShare = lib:Sharing() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGOUT")
f:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name == ADDON then
    db()
    ns.Comm.Boot()
    -- THE ADDON WATCHES NOTHING NOW (5 Oct 2026). Arn: "we can get rid of the attendence and
    -- consume check lets do logs for that". It used to count boss kills and who was standing
    -- there, which was a SECOND source of truth against the combat log - and when two sources
    -- disagree, the one people believe is the one on the website. One source, or arguments.
    --
    -- The nights it had already written down are dropped rather than left to rot in the saved
    -- variables, where they would outlive every piece of code that could read them.
    local d = db()
    if d.nights ~= nil then d.nights = nil end
    if d.taught ~= nil then d.taught = nil end       -- and the consumables list, gone the same way
    -- THE RECORD (16 Oct): the report file is folded into the guild's record, which every member
    -- keeps and Core/Share.lua shares - so the numbers survive a deploy and a missed night
    if ns.S then ns.S.Import(_G.BiSGuildReport) end
    if ns.X then ns.X.Boot() end
  elseif event == "PLAYER_LOGOUT" then
    ns.Comm.Save()
  end
end)

SLASH_BISGUILD1 = "/bisg"
SlashCmdList.BISGUILD = function(input)
  -- the command is lowercased, the REST is not: a spell id does not care, but this is the shape
  -- that stored "/memories now Killed Baron Silverlaine" as lower case in BiSMemories (0.5.3)
  local raw = tostring(input or "")
  local cmd, rest = raw:match("^%s*(%S*)%s*(.-)%s*$")
  if ns.Say then return ns.Say(cmd:lower(), rest) end
  local lib = _G.LibBiSComm
  ns.Print("hello - version %s, BiS comm %s, %d peer(s)", ns.VERSION,
    (lib and lib:Enabled()) and T.text("good", "on") or T.text("warn", "off"), lib and lib:Count() or 0)
end
