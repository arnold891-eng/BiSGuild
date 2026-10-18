--[[
  BiSGuild :: Core/Loot.lua - the loot ledger, folded in from BiS Loot (16 Oct 2026).

  Arn: "more than likely BiS Guild will be installed by all the officers, and they won't download a
  single addon if BiS Guild can do it ... if they are going to install one thing it's the BiS Guild".
  And the history: "I was working on BiS Loot in TBC, and then Forever dropped, and then we made BiS
  Guild before the first dungeon".

  So the ledger lives here now: LibBiSLedger-1.0 (the core, lifted out of BiS Loot into _bisdev and
  embedded) keeps one ledger per guild, in that guild's books (ns.Books().loot) like the raid record.

    * /bisl status | last [n] | award <player> <item> [bis|up|os|de] [note] | save - BiS Loot's
      commands, the same words, so nobody's habit breaks.
    * BiSLootAPI (major 1) - the same API BiS Loot had, answered from this ledger, so a caller asks
      the same question whichever addon is installed.
    * BiS LOOT STILL INSTALLED: its saved lines are taken in at every login (a line already held is a
      dup - nothing doubles), and since it loads after us (B-i-S-G before B-i-S-L) its own /bisl and
      BiSLootAPI take over; ours steps aside. Once the import has happened the player is told, once,
      that BiS Loot can be removed.
]]
local ADDON, ns = ...

local LT = {}
ns.Loot = LT

LT.ledgers = {}               -- guild key -> ledger
LT.BAD_KEEP = 50

local function Lib() return _G.LibBiSLedger end

--- This guild's ledger, loaded from its books the first time it is asked for. Nil until the client
--- has named the guild (the books are per guild - Init.lua ns.Books).
function LT.Ledger()
    local key = ns.GuildKey()
    local lib = Lib()
    if not (key and lib) then return nil end
    local L = LT.ledgers[key]
    if L then return L end
    L = lib.New()
    local b = ns.Books()
    if type(b.loot) ~= "table" then b.loot = { lines = {}, meta = {} } end
    for _, line in ipairs(b.loot.lines or {}) do L:Accept(line, "file") end
    for id, m in pairs(b.loot.meta or {}) do
        if L.meta[id] then
            L.meta[id].w = math.max(L.meta[id].w, tonumber(m.w) or 0)
            L.meta[id].direct = L.meta[id].direct or m.direct == true
        end
    end
    L:OnEvent(function(ev, source) if LT.OnNew then LT.OnNew(ev, source) end end)
    LT.ledgers[key] = L
    return L
end

--- Write this guild's ledger back into its books (logout, /bisl save).
function LT.Save()
    local key = ns.GuildKey()
    local L = key and LT.ledgers[key]
    if not L then return nil end
    local b = ns.Books()
    local meta = {}
    for id, m in pairs(L.meta) do meta[id] = { w = m.w, direct = m.direct or nil } end
    local bad = {}
    for i = math.max(1, #L.bad - LT.BAD_KEEP + 1), #L.bad do bad[#bad + 1] = L.bad[i] end
    b.loot = { lines = L:Lines(), meta = meta, bad = bad, importedFromBiSLoot = b.loot and b.loot.importedFromBiSLoot }
    return L:Verify()
end

--- BiS LOOT'S LINES, TAKEN IN. Its saved table is only there while BiS Loot is installed and enabled,
--- so this runs at every login: a line already held answers "dup" and nothing doubles; a checksum that
--- fails stays out (the ledger's own rule). Answers how many lines were new.
function LT.ImportBiSLoot()
    local L = LT.Ledger()
    local old = _G.BiSLootDB
    if not (L and type(old) == "table") then return 0 end
    local new = 0
    for _, list in ipairs({ old.lines or {}, old.snapshot or {} }) do
        for _, line in ipairs(list) do
            if L:Accept(line, "file") == "new" then new = new + 1 end
        end
    end
    local b = ns.Books()
    if new > 0 or not (b.loot and b.loot.importedFromBiSLoot) then
        LT.Save()
        if not b.loot.importedFromBiSLoot then
            b.loot.importedFromBiSLoot = true
            ns.Print("BiS Loot's ledger is now kept by BiS Guild (%d line(s) taken in) - BiS Loot can be removed.",
                L.count)
        end
    end
    return new
end

--------------------------------------------------------------------
-- /bisl - BiS Loot's words, kept (it steps aside if BiS Loot itself is loaded: it loads after us)
--------------------------------------------------------------------

local function Me() return (UnitName and UnitName("player")) or "?" end

function LT.Status()
    local L = LT.Ledger()
    if not L then ns.Print("the ledger is not ready yet - the guild is still being named") return end
    local v = L:Verify()
    ns.Print("%d events from %d authors - %s", v.events, v.authors,
        v.ok and ns.T.text("good", "every chain whole") or ns.T.text("warn", ("%d bad, %d forks, %d gaps"):format(v.bad, v.forks, #v.gaps)))
    for _, g in ipairs(v.gaps) do ns.Print("  gap: %s #%d-%d missing", g.author, g.from, g.to) end
    return v
end

function LT.Last(n)
    local L = LT.Ledger()
    if not L then return end
    n = tonumber(n) or 10
    local evs = L:Events()
    if #evs == 0 then ns.Print("the ledger is empty") return end
    for i = 1, math.min(n, #evs) do
        local ev = evs[i]
        local m = L.meta[ev.id] or {}
        ns.Print("%s %s %s %s %s %s%s", ns.T.text("muted", date("%m-%d %H:%M", ev.t)), ns.T.text("accent", ev.kind),
            ev.who ~= "" and ev.who or "-", ev.item ~= "" and ev.item or "-", ev.resp ~= "" and ns.T.text("gold", ev.resp) or "",
            ns.T.text("muted", "by " .. ev.author), m.direct and "" or ns.T.text("warn", " (hearsay)"))
    end
end

--- /bisl award <player> <item link or name> [resp] [note...]
function LT.Award(rest)
    local L = LT.Ledger()
    if not L then return end
    local who, item, resp, note = rest:match("^(%S+)%s+(|c%x+|H.-|h%[.-%]|h|r)%s*(%S*)%s*(.*)$")
    if not who then who, item, resp, note = rest:match("^(%S+)%s+(%S+)%s*(%S*)%s*(.*)$") end
    if not who or not item then ns.Print("usage: /bisl award <player> <item> [bis|up|os|de] [note]") return end
    local ev, why = L:Add(Me(), { kind = "award", who = who, item = item, resp = resp, note = note, by = "hand", raid = "", boss = "" })
    if not ev then ns.Print("refused: %s", tostring(why)) return end
    LT.Save()
    ns.Print("award #%d: %s -> %s %s", ev.seq, ev.item, ev.who, ev.resp ~= "" and ns.T.text("gold", ev.resp) or "")
    return ev
end

function LT.Slash(msg)
    msg = tostring(msg or ""):gsub("^%s+", "")
    local word, rest = msg:match("^(%S*)%s*(.*)$")
    word = (word or ""):lower()
    if word == "" or word == "status" or word == "verify" then return LT.Status()
    elseif word == "last" then return LT.Last(rest)
    elseif word == "award" then return LT.Award(rest)
    elseif word == "save" then
        local v = LT.Save()
        ns.Print("saved %d lines", v and v.events or 0)
        return v
    end
    ns.Print("/bisl status | last [n] | award <player> <item> [bis|up|os|de] [note] | save")
end

SLASH_BISLOOT1, SLASH_BISLOOT2, SLASH_BISLOOT3 = "/bisl", "/bl", "/bisloot"
SlashCmdList.BISLOOT = function(msg) LT.Slash(msg) end

--------------------------------------------------------------------
-- BiSLootAPI, answered from this ledger (major 1, version 1 - the same calls and answers BiS Loot's
-- API.lua gives; _bisdev/docs/apis.md). Read-only copies; nothing here writes the ledger.
--   Ready() AwardsTo(name) AwardsFor(item) AwardsFrom(boss) Recent(n) Health()
--   RegisterCallback(owner, "BiSLoot_Award", fn(award)) / UnregisterCallback(owner, event)
-- If BiS Loot itself is installed it loads after us and its own BiSLootAPI replaces this one.
--------------------------------------------------------------------

local API = { major = 1, version = 1, provider = "BiSGuild" }
BiSLootAPI = API

function API.Ready()
    if not (LT.Ledger() and ns.loaded) then return nil, "not ready" end
    return true
end

local function nz(s) if type(s) == "string" and s ~= "" then return s end return nil end
local function ItemId(item)
    if type(item) == "number" then return item end
    if type(item) ~= "string" then return nil end
    return tonumber(item:match("item:(%d+)")) or tonumber(item)
end
local function Copy(ev)
    local m = LT.Ledger().meta[ev.id] or {}
    return { id = ev.id, item = nz(ev.item), itemId = ItemId(ev.item), who = nz(ev.who), boss = nz(ev.boss),
             raid = nz(ev.raid), resp = nz(ev.resp), note = nz(ev.note), t = ev.t, author = ev.author,
             witnessed = m.direct == true }
end
local function Awards(keep, n)
    local out = {}
    for _, ev in ipairs(LT.Ledger():Events(function(ev) return ev.kind == "award" and (not keep or keep(ev)) end)) do
        out[#out + 1] = Copy(ev)
        if n and #out >= n then break end
    end
    return out
end
local function Whole(name) return ((name:match("^([^%-]+)") or name)):lower() end
local function First(name) return (name:match("^([^%-%s]+)") or name):lower() end

function API.AwardsTo(name)
    local ok, why = API.Ready()
    if not ok then return nil, why end
    if type(name) ~= "string" or name == "" then return nil, "no name" end
    local whole, first, single = Whole(name), First(name), not name:find(" ", 1, true)
    return Awards(function(ev)
        if type(ev.who) ~= "string" or ev.who == "" then return false end
        if Whole(ev.who) == whole then return true end
        return (single or not ev.who:find(" ", 1, true)) and First(ev.who) == first
    end)
end

function API.AwardsFor(item)
    local ok, why = API.Ready()
    if not ok then return nil, why end
    local id = ItemId(item)
    local word = type(item) == "string" and (item:match("%[(.-)%]") or item):lower() or nil
    if not id and not word then return nil, "no item" end
    return Awards(function(ev)
        if id and ItemId(ev.item) == id then return true end
        local nm = type(ev.item) == "string" and (ev.item:match("%[(.-)%]") or ev.item):lower() or nil
        return not id and word ~= nil and nm == word
    end)
end

function API.AwardsFrom(boss)
    local ok, why = API.Ready()
    if not ok then return nil, why end
    if type(boss) ~= "string" or boss == "" then return nil, "no boss" end
    local b = boss:lower()
    return Awards(function(ev) return type(ev.boss) == "string" and ev.boss:lower() == b end)
end

function API.Recent(n)
    local ok, why = API.Ready()
    if not ok then return nil, why end
    n = math.max(1, math.min(200, math.floor(tonumber(n) or 20)))
    return Awards(nil, n)
end

function API.Health()
    local ok, why = API.Ready()
    if not ok then return nil, why end
    local v = LT.Ledger():Verify()
    return { events = v.events, authors = v.authors, ok = v.ok, forks = v.forks, gaps = #(v.gaps or {}), bad = v.bad }
end

local owners = {}
function API.RegisterCallback(owner, event, fn)
    if owner == nil or type(event) ~= "string" or type(fn) ~= "function" then
        error("BiSLootAPI.RegisterCallback(owner, event, fn)", 2)
    end
    owners[event] = owners[event] or {}
    owners[event][owner] = fn
end
function API.UnregisterCallback(owner, event)
    if owners[event] then owners[event][owner] = nil end
end
function LT.OnNew(ev, source)
    if not (ev and ev.kind == "award" and ns.loaded and source ~= "file") then return end
    for _, fn in pairs(owners.BiSLoot_Award or {}) do pcall(fn, Copy(ev)) end
end

--------------------------------------------------------------------
-- wiring
--------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_GUILD_UPDATE")
f:RegisterEvent("PLAYER_LOGOUT")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGOUT" then LT.Save() return end
    -- the guild may be named only after login: try again when it is
    if LT.Ledger() and not LT.imported then
        LT.imported = true
        LT.ImportBiSLoot()
    end
end)

ns.parts["Core/Loot.lua"] = "0.1.1"
