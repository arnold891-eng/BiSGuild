--[[
  BiSGuild :: Core/Looks.lua - WHAT GUILDMATES LOOK LIKE, for the WHERE map's little figures.

  Arn, 18-19 Oct 2026: "the BiS guild map thing can be 3d models too" - "actual size so very tiny maybe
  like 10 pixels max" - "store the data of what they are wearing when they party or raid and are near
  us and keep that until next time we see them". Measured on Forever (BiS Shell's Test-Model, 19 Oct):
  a model frame CANNOT build a body from a race and sex (no SetCustomRace) - so a guildmate across the
  world is drawn as a STAND-IN: a plain townsperson of their race and sex, by display id (16 of 16
  drew in game). At 10 pixels a stand-in is the person.

  - Their race and sex are SAVED whenever the client can tell: they are in your party or raid, or you
    target them. Kept by their whole roster name until you see them again. Nobody sends anything, and
    they need no BiS addon for this part (only for the spot itself).
  - Only guildmates are kept. A race the table does not know (Forever has races of its own) is not
    kept - their dot stays a dot.
  - It asks on group and target changes only, at most 41 units - never on a timer.
]]
local ADDON, ns = ...
local K = ns.K

local L = {}
ns.Looks = L

-- the stand-ins, { man, woman }, by UnitRace's file name; each race and sex read from Wowhead's
-- model-viewer data (Character.Race / Gender), the same table as BiS Shell's Test-Model -Folk
L.FOLK = {
  Human = { 1291, 5444 }, Orc = { 5705, 5706 }, Dwarf = { 3434, 3066 }, NightElf = { 5440, 5439 },
  Scourge = { 5449, 8190 }, Tauren = { 5486, 5487 }, Gnome = { 7028, 7119 }, Troll = { 4072, 4358 },
}

local function hidden(v)
  if v == nil or not issecretvalue then return false end
  local ok, yes = pcall(issecretvalue, v)
  return (not ok) or yes == true
end
local function plain(v) if hidden(v) then return nil end return v end

function L.DB()
  local db = ns.DB()
  if type(db.looks) ~= "table" then db.looks = {} end
  return db.looks
end

--- A unit's whole name ("Name Surname"): GetUnitName has the surname on Forever, UnitName may not.
local function wholeName(unit)
  local n
  if GetUnitName then
    local ok, v = pcall(GetUnitName, unit, false)
    if ok then n = plain(v) end
  end
  if type(n) ~= "string" or n == "" then
    local ok, v = pcall(UnitName, unit)
    n = ok and plain(v) or nil
  end
  if type(n) ~= "string" or n == "" then return nil end
  return n:match("^([^%-]+)") or n
end

--- Note one unit's race and sex, if it is a guildmate (or you) the table knows how to draw.
function L.Note(unit)
  if not (UnitExists and UnitExists(unit)) then return false end
  if UnitIsPlayer and not UnitIsPlayer(unit) then return false end
  local name = wholeName(unit)
  if not name then return false end
  local m = K.Member(name)
  if not m and unit ~= "player" then return false end            -- guildmates only
  local okR, _, race = pcall(UnitRace, unit)
  local okS, sex = pcall(UnitSex, unit)
  race = okR and plain(race) or nil
  sex = okS and plain(sex) or nil
  if not (L.FOLK[race] and (sex == 2 or sex == 3)) then return false end
  local key = m and m.key or name:lower()
  local db = L.DB()
  local was = db[key]
  local look = { race = race, sex = sex == 3 and 2 or 1, at = (GetServerTime and GetServerTime()) or 0 }
  db[key] = look
  return not was or was.race ~= look.race or was.sex ~= look.sex
end

--- Everyone the client can tell about right now: you, your group, your target.
function L.Scan()
  local changed = 0
  if L.Note("player") then changed = changed + 1 end
  local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
  local raid = IsInRaid and IsInRaid()
  for i = 1, raid and n or math.max(0, n - 1) do
    if L.Note((raid and "raid" or "party") .. i) then changed = changed + 1 end
  end
  if L.Note("target") then changed = changed + 1 end
  return changed
end

--- The stand-in's display id for a name (whole or first), or nil: never seen, or a race we can't draw.
function L.Display(name)
  if type(name) ~= "string" then return nil end
  local m = K.Member(name)
  local look = L.DB()[m and m.key or (name:match("^([^%-]+)") or name):lower()]
  local folk = look and L.FOLK[look.race]
  return folk and folk[look.sex] or nil
end

--- Your own stand-in, straight from the client (your first name may not be your roster name).
function L.Mine()
  local okR, _, race = pcall(UnitRace, "player")
  local okS, sex = pcall(UnitSex, "player")
  race = okR and plain(race) or nil
  sex = okS and plain(sex) or nil
  local folk = L.FOLK[race]
  return folk and (sex == 2 or sex == 3) and folk[sex == 3 and 2 or 1] or nil
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_TARGET_CHANGED" then pcall(L.Note, "target") return end
  pcall(L.Scan)
end)
L.events = f
