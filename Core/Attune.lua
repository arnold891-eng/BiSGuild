--[[
  BiSGuild :: Core/Attune.lua - who is attuned to Onyxia's Lair.

  Arn, 17 Oct 2026: "we dealt with alot of issues of people not being attunned to raid in tbc we
  want a window that keep track of what people are attuned to". His picks: BiS answers AND Attune's
  survey results, every BiS addon answering (the shared comm library), Onyxia's Lair only.

  STEP 0 - THE PROBE. The quest numbers below are the original game's. Forever renumbers some of its
  quests, and an answer built on a wrong number would be wrong for every guildmate at once. So before
  any of this ships to the comm library, `/bisg attune probe` prints, for every quest in both chains,
  the name THIS client gives the number and whether this character has done it, the Drakefire
  Amulet in the bags, and every completed quest whose name sounds like the chain - which finds a
  renumbered step. Nothing is sent anywhere; it only reads this character.
]]
local ADDON, ns = ...
local A = {}
ns.Attune = A

local function plain(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

-- the original game's numbers and names, to be confirmed on Forever by the probe (UNVERIFIED)
A.AMULET = 16309                       -- Drakefire Amulet: carrying it IS the attunement
A.CHAINS = {
  Horde = {
    { 4903, "Warlord's Command" }, { 4941, "Eitrigg's Wisdom" }, { 4974, "For The Horde!" },
    { 6566, "What the Wind Carries" }, { 6567, "The Champion of the Horde" },
    { 6568, "The Testament of Rexxar" }, { 6569, "Oculus Illusions" }, { 6570, "Emberstrife" },
    { 6584, "The Test of Skulls, Chronalis" }, { 6582, "The Test of Skulls, Scryer" },
    { 6583, "The Test of Skulls, Somnus" }, { 6585, "The Test of Skulls, Axtroz" },
    { 6601, "Ascension" }, { 6602, "Blood of the Black Dragon Champion" },
  },
  Alliance = {
    { 4182, "Dragonkin Menace" }, { 4183, "The True Masters" }, { 4184, "The True Masters" },
    { 4185, "The True Masters" }, { 4186, "The True Masters" }, { 4223, "The True Masters" },
    { 4224, "The True Masters" }, { 4241, "Marshal Windsor" }, { 4242, "Abandoned Hope" },
    { 4264, "A Crumpled Up Note" }, { 4282, "A Shred of Hope" }, { 4322, "Jail Break!" },
    { 6402, "Stormwind Rendezvous" }, { 6403, "The Great Masquerade" }, { 6501, "The Dragon's Eye" },
    { 6502, "Drakefire Amulet" },
  },
}
-- words a renumbered step would still carry in its name
A.WORDS = { "drake", "dragon", "rexxar", "skulls", "ascension", "masters", "windsor", "masquerade",
            "emberstrife", "eitrigg", "warlord", "oculus", "onyxia", "jail break", "shred of hope",
            "crumpled", "abandoned hope", "rendezvous", "black dragon" }

--- Has this character done quest `id`? true / false, or nil when the client will not say.
function A.Done(id)
  local QL = C_QuestLog
  if not (QL and QL.IsQuestFlaggedCompleted) then return nil end
  local ok, done = pcall(QL.IsQuestFlaggedCompleted, id)
  done = ok and plain(done)
  if done == nil then return nil end
  return done and true or false
end

--- The name this client gives quest `id`, or nil (and a request to load it) when it has not got it yet.
function A.Title(id)
  local QL = C_QuestLog
  if not (QL and QL.GetTitleForQuestID) then return nil end
  local ok, t = pcall(QL.GetTitleForQuestID, id)
  t = ok and plain(t)
  if type(t) == "string" and t ~= "" then return t end
  if QL.RequestLoadQuestByID then pcall(QL.RequestLoadQuestByID, id) end
  return nil
end

--- How many Drakefire Amulets are in the bags (and the bank), or nil when the client will not say.
function A.Amulets()
  local count = (C_Item and C_Item.GetItemCount) or GetItemCount
  if not count then return nil end
  local ok, n = pcall(count, A.AMULET, true)
  n = ok and plain(n)
  return type(n) == "number" and n or nil
end

local function sounds(t)
  t = t:lower()
  for _, w in ipairs(A.WORDS) do if t:find(w, 1, true) then return true end end
  return false
end

--- THE PROBE: lines to print. Pure reading; nothing is sent, nothing is saved.
function A.Probe()
  local T = ns.T
  local out, loading = {}, 0
  local function say(fmt, ...) out[#out + 1] = fmt:format(...) end
  local faction = UnitFactionGroup and plain(UnitFactionGroup("player")) or "?"
  local me = UnitName and plain(UnitName("player")) or "?"
  say("attune probe - Onyxia's Lair, %s (%s). Nothing is sent; it reads this character only.", tostring(me), tostring(faction))
  local itemName
  if C_Item and C_Item.GetItemNameByID then
    local ok, nm = pcall(C_Item.GetItemNameByID, A.AMULET)
    nm = ok and plain(nm)
    itemName = type(nm) == "string" and nm or nil
  end
  local n = A.Amulets()
  say("  item %d %s: %s", A.AMULET, itemName and ('"' .. itemName .. '"') or "(name not loaded)",
    n == nil and T.text("warn", "count hidden") or n > 0 and T.text("good", n .. " carried") or "none carried")
  for _, side in ipairs({ "Horde", "Alliance" }) do
    local done = 0
    say("  %s chain:", side)
    for _, q in ipairs(A.CHAINS[side]) do
      local id, want = q[1], q[2]
      local title, d = A.Title(id), A.Done(id)
      if d then done = done + 1 end
      if not title then loading = loading + 1 end
      local same = title and title:lower() == want:lower()
      say("    %d  %s  %s%s", id,
        title and (same and title or T.text("warn", title)) or T.text("muted", "(name loading)"),
        d == nil and T.text("warn", "?") or d and T.text("good", "done") or T.text("muted", "not done"),
        (title and not same) and T.text("warn", "  - expected " .. want) or "")
    end
    say("    %d of %d done", done, #A.CHAINS[side])
  end
  -- every completed quest whose name sounds like the chain: a renumbered step shows up here
  local QL = C_QuestLog
  if QL and QL.GetAllCompletedQuestIDs then
    local ok, ids = pcall(QL.GetAllCompletedQuestIDs)
    if ok and type(ids) == "table" then
      local known = {}
      for _, side in pairs(A.CHAINS) do for _, q in ipairs(side) do known[q[1]] = true end end
      local hits = {}
      for _, id in ipairs(ids) do
        id = plain(id)
        if type(id) == "number" and not known[id] then
          local t = A.Title(id)
          if t and sounds(t) then hits[#hits + 1] = ("%d %s"):format(id, t) end
        end
      end
      say("  %d quests done on this character; others that sound like the chain: %s", #ids,
        #hits > 0 and table.concat(hits, ", ") or "none")
    end
  end
  if loading > 0 then
    say("  %s", T.text("gold", ("%d name(s) still loading from the server - run /bisg attune probe once more"):format(loading)))
  end
  return out
end

function A.Slash(rest)
  local r = (rest or ""):lower()
  if r == "probe" then
    for _, line in ipairs(A.Probe()) do ns.Print("%s", line) end
    return true
  end
  ns.Print("attune: %s", ns.T.text("muted", "/bisg attune probe - check the Onyxia quests on this character"))
  return true
end

ns.parts["Core/Attune.lua"] = "0.1.0"
