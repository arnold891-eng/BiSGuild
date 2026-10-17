--[[
  BiSGuild :: Core/Share.lua - the raid record, shared over the guild channel.

  Arn, 16 Oct 2026: "if I miss one raid night what stops the addon from updating and working
  properly". Any officer who logs a raid can import the night; this file hands it to everyone else.

  THE CONVERSATION (MOD "GLOG", guild-scoped, nothing on a timer once it is quiet):

    HAVE  |261016.25.6,261009.24.7,...    an officer, 30-60 s after logging in and after an import:
                                          the newest dates they hold, each with raiders.kills
    WANT  |2026-10-16                     anyone whose copy of that date is missing or thinner
    NIGHT |2026-10-16|i|n|<part>          one officer answers; the night goes out in parts of 200
                                          characters, so EVERY member missing it takes the same copy
    GWANT |Name|2026-10-09                the terminal opened a raider: "anything newer than this?"
    GEAR  |Name|2026-10-16|i|n|<part>     one officer answers with that raider's newest gear

  WHO IS BELIEVED: only nights and gear from an OFFICER are taken in - a guild rank at or above
  `officerRank` (0 = guild master; default 1, `/bisg officers <n>`). Anyone in the guild could
  otherwise post a made-up night, and a record that anyone can write is not a record. Members keep
  the copy; officers are the ones who answer.

  ONE ANSWER, NOT TEN: an officer who hears a WANT waits 1-4 s, and stands down if another officer's
  first part for that date goes past first. A member who sees somebody else's WANT for a date it is
  missing too does not ask again - the answer is on the guild channel for everybody.

  LEAN (standing order, 7 Oct): LibBiSComm's one prefix carries about one message a second for every
  BiS addon together, so this file sends at most one part every 2 s through its own queue and never
  fills the shared outbox. A 25-raider night is about ten parts.
]]
local ADDON, ns = ...

local X = {}
ns.X = X

X.MOD = "GLOG"
X.CHUNK = 200          -- characters of payload per part; the frame and the escapes stay under 250
X.GAP = 2              -- seconds between two of OUR parts (the lib's gap is 1 and shared)
X.MAX_PARTS = 30       -- a night longer than this is not a night, it is a flood
X.MAX_GEAR_PARTS = 4
X.HAVE_DATES = 18      -- newest dates in one HAVE line (12 characters each)
X.STALE = 120          -- a half-received night older than this is dropped

X.out = {}             -- our parts, waiting their turn
X.inbox = {}           -- [sender|kind|id] = { n =, got =, parts = {}, at = }
X.wanted = {}          -- [date] = true: a fuller copy exists and we do not have it yet
X.asked = {}           -- [date] = GetTime() somebody (us or anyone) asked; answers go to all
X.answering = {}       -- [kind|id] = true while we wait our turn to answer
X.started = {}         -- [kind|id] = GetTime() somebody's first part went past

local function Now() return GetTime and GetTime() or 0 end
local function Lib() return _G.LibBiSComm end
local function After(t, fn) if C_Timer and C_Timer.After then C_Timer.After(t, fn) end end
local function Short(name)
    if type(name) ~= "string" then return nil end
    return name:match("^([^%-]+)") or name
end

--------------------------------------------------------------------
-- who is an officer
--------------------------------------------------------------------

--- HOW FAR DOWN THE RANKS "OFFICER" GOES (Arn, 16 Oct, his roster: Guild Master, Officer, Veteran -
--- "but it's not always like that"). Every member's client has to agree on who is believed, and
--- members will never set anything, so the answer lives where every member can read it: a line in
--- the guild's Guild Information text, written once by the guild master -
---     BiSGuild officers: 2
--- counts ranks 0..2 (rank 0 is the guild master; the line is ranks DOWN from the top). Without the
--- line it is 1: the guild master and the rank under. `officerRank` in the saved variables is for
--- testing on one client only.
function X.OfficerRank()
    local n = tonumber(ns.DB().officerRank)
    if not n and GetGuildInfoText then
        local ok, text = pcall(GetGuildInfoText)
        if ok and type(text) == "string" then
            n = tonumber(text:lower():match("bisguild%s*officers%s*[:=]%s*(%d+)"))
        end
    end
    return n and n >= 0 and math.floor(n) or 1
end

--- The guild rank index of a name (0 = guild master), or nil for somebody not on the roster.
--- Rebuilt after GUILD_ROSTER_UPDATE, never per message.
function X.Rank(name)
    name = Short(name)
    if not name then return nil end
    if X._ranksDirty ~= false or not X._ranks then
        local ranks = {}
        local n = (GetNumGuildMembers and GetNumGuildMembers()) or 0
        for i = 1, n do
            local member, _, rankIndex = GetGuildRosterInfo(i)
            local s = Short(member)
            if s then ranks[s] = tonumber(rankIndex) end
        end
        X._ranks, X._ranksDirty = ranks, false
    end
    return X._ranks[name]
end

function X.IsOfficer(name)
    local r = X.Rank(name)
    return r ~= nil and r <= X.OfficerRank()
end

function X.Me() return Short(UnitName and UnitName("player") or nil) end

--------------------------------------------------------------------
-- a night and a gear set as text, and back
--------------------------------------------------------------------

-- Names and boss names may not carry the separators. A name that does is left out, not mangled:
-- a raider whose name came out wrong is a different raider.
local function clean(s) return type(s) == "string" and s ~= "" and not s:find("[:;#,%.|/]") end
local function int(v) return math.floor(tonumber(v) or 0) end

--- kills # Name:present.ready.pulls...deaths;... # Boss:pulls.kills.best:i,j,k;...
--- Killers are numbers into the raider list, which is sorted, so the same night is the same text.
function X.EncodeNight(night)
    local names = {}
    for name in pairs(night.raiders or {}) do if clean(name) then names[#names + 1] = name end end
    table.sort(names)
    local index, raiders = {}, {}
    for i, name in ipairs(names) do
        index[name] = i
        local r, vals = night.raiders[name], {}
        for k, f in ipairs(ns.S.FIELDS) do vals[k] = int(r[f]) end
        raiders[i] = name .. ":" .. table.concat(vals, ".")
    end
    local bosses = {}
    for boss in pairs(night.bosses or {}) do if clean(boss) then bosses[#bosses + 1] = boss end end
    table.sort(bosses)
    for i, boss in ipairs(bosses) do
        local b, who = night.bosses[boss], {}
        for _, k in ipairs(b.killers or {}) do if index[k] then who[#who + 1] = index[k] end end
        bosses[i] = ("%s:%d.%d.%d:%s"):format(boss, int(b.pulls), int(b.kills), int(b.best), table.concat(who, ","))
    end
    return int(night.kills) .. "#" .. table.concat(raiders, ";") .. "#" .. table.concat(bosses, ";")
end

local function split(s, sep)
    local out = {}
    if s == "" then return out end
    for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
    return out
end

function X.DecodeNight(s)
    if type(s) ~= "string" then return nil end
    local kills, rs, bs = s:match("^(%d+)#([^#]*)#([^#]*)$")
    if not kills then return nil end
    local night = { kills = tonumber(kills), raiders = {}, bosses = {} }
    local names = {}
    for _, entry in ipairs(split(rs, ";")) do
        local name, nums = entry:match("^([^:]+):([%d%.]+)$")
        if not name then return nil end
        local vals = split(nums, ".")
        if #vals ~= #ns.S.FIELDS then return nil end
        local r = {}
        for k, f in ipairs(ns.S.FIELDS) do r[f] = tonumber(vals[k]) or 0 end
        night.raiders[name] = r
        names[#names + 1] = name
    end
    for _, entry in ipairs(split(bs, ";")) do
        local boss, p, k, best, who = entry:match("^([^:]+):(%d+)%.(%d+)%.(%d+):([%d,]*)$")
        if not boss then return nil end
        local killers = {}
        for _, i in ipairs(split(who, ",")) do
            local name = names[tonumber(i) or 0]
            if name then killers[#killers + 1] = name end
        end
        table.sort(killers)
        night.bosses[boss] = { pulls = tonumber(p), kills = tonumber(k), best = tonumber(best), killers = killers }
    end
    return night
end

--- id.ilvl.enchant.temp.gem/gem;... - an empty slot is just 0
function X.EncodeGear(gear)
    local out = {}
    for i = 1, #ns.S.SLOTS do
        local g = gear[i]
        if type(g) == "table" and int(g[1]) ~= 0 then
            local gems = {}
            for _, gem in ipairs(type(g[5]) == "table" and g[5] or {}) do gems[#gems + 1] = int(gem) end
            out[i] = ("%d.%d.%d.%d.%s"):format(int(g[1]), int(g[2]), int(g[3]), int(g[4]), table.concat(gems, "/"))
        else
            out[i] = "0"
        end
    end
    return table.concat(out, ";")
end

function X.DecodeGear(s)
    if type(s) ~= "string" then return nil end
    local slots = split(s, ";")
    if #slots ~= #ns.S.SLOTS then return nil end
    local gear = {}
    for i, e in ipairs(slots) do
        if e == "0" then
            gear[i] = { 0, 0, 0, 0, {} }
        else
            local id, ilvl, ench, temp, gems = e:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)%.([%d/]*)$")
            if not id then return nil end
            local g = {}
            for _, gem in ipairs(split(gems, "/")) do g[#g + 1] = tonumber(gem) end
            gear[i] = { tonumber(id), tonumber(ilvl), tonumber(ench), tonumber(temp), g }
        end
    end
    return gear
end

--------------------------------------------------------------------
-- our queue: one part every X.GAP seconds
--------------------------------------------------------------------

function X.Send(cmd, ...)
    -- a copy that is not whole shares nothing but the fact (Core/Copies.lua)
    if ns.broken and cmd ~= "BUILD" then return end
    X.out[#X.out + 1] = { cmd, ... }
    X.Pump()
end

function X.Pump()
    if X._armed or #X.out == 0 then return end
    local lib = Lib()
    if not lib then wipe(X.out) return end
    local m = table.remove(X.out, 1)
    lib:SendTo("GUILD", X.MOD, unpack(m))
    X._armed = true
    After(X.GAP, function() X._armed = false; X.Pump() end)
end

--- One payload as parts. The parts are queued together, so nothing of ours goes between them.
function X.SendParts(cmd, head, text, max)
    local n = math.ceil(#text / X.CHUNK)
    if n < 1 then n = 1 end
    if n > max then return false end
    for i = 1, n do
        local part = text:sub((i - 1) * X.CHUNK + 1, i * X.CHUNK)
        local args = {}
        for _, h in ipairs(head) do args[#args + 1] = h end
        args[#args + 1] = i
        args[#args + 1] = n
        args[#args + 1] = part
        X.Send(cmd, unpack(args))
    end
    return true
end

--------------------------------------------------------------------
-- what we say
--------------------------------------------------------------------

local function compact(date) return date:sub(3, 4) .. date:sub(6, 7) .. date:sub(9, 10) end
local function expand(c)
    local y, m, d = c:match("^(%d%d)(%d%d)(%d%d)$")
    return y and ("20%s-%s-%s"):format(y, m, d) or nil
end

--- The HAVE line: newest dates first, each as yymmdd.raiders.kills.
function X.HaveLine()
    local dates, out = ns.S.Dates(), {}
    local nights = ns.S.Record().nights
    for i = #dates, math.max(1, #dates - X.HAVE_DATES + 1), -1 do
        local r, k = ns.S.Weight(nights[dates[i]])
        out[#out + 1] = ("%s.%d.%d"):format(compact(dates[i]), r, k)
    end
    return table.concat(out, ",")
end

--- Officers say what they hold. Members never do: nobody would believe them anyway.
function X.Announce()
    if not X.IsOfficer(X.Me()) then return false end
    local line, punct = X.HaveLine(), X.PunctHaveLine()
    if line ~= "" then X.Send("HAVE", line) end
    if punct ~= "" then X.Send("PHAVE", punct) end
    return line ~= "" or punct ~= ""
end


--- Ask for the newest date we are missing that nobody has asked for in the last 90 s.
function X.AskNext()
    local best
    for date in pairs(X.wanted) do
        local asked = X.asked[date]
        if not (asked and Now() - asked < 90) and (not best or date > best) then best = date end
    end
    if not best then return false end
    X.asked[best] = Now()
    X.Send("WANT", best)
    return true
end

function X.AskSoon()
    if X._askArmed then return end
    X._askArmed = true
    After(2 + math.random() * 4, function() X._askArmed = false; X.AskNext() end)
end

--- The raider terminal asks this when it opens a raider: is there gear newer than ours?
function X.WantGear(name)
    if not name then return false end
    local have = ns.S.Record().gear[name]
    X.Send("GWANT", name, have and have.date or "")
    return true
end

--------------------------------------------------------------------
-- what we hear
--------------------------------------------------------------------

X.handlers = {}

X.handlers.HAVE = function(sender, line)
    if not X.IsOfficer(sender) or type(line) ~= "string" then return end
    local nights = ns.S.Record().nights
    local any = false
    for entry in line:gmatch("[^,]+") do
        local c, r, k = entry:match("^(%d%d%d%d%d%d)%.(%d+)%.(%d+)$")
        local date = c and expand(c)
        if date then
            local mr, mk = ns.S.Weight(nights[date])
            r, k = tonumber(r), tonumber(k)
            if r > mr or (r == mr and k > mk) then
                X.wanted[date] = true
                any = true
            end
        end
    end
    if any then X.AskSoon() end
end

X.handlers.WANT = function(sender, date)
    if not ns.S.IsDate(date) then return end
    X.asked[date] = Now()                              -- somebody asked: we need not
    local night = ns.S.Record().nights[date]
    if not night or not X.IsOfficer(X.Me()) then return end
    local key = "NIGHT|" .. date
    if X.answering[key] then return end
    X.answering[key] = true
    local asked = Now()
    After(1 + math.random() * 3, function()
        X.answering[key] = nil
        if (X.started[key] or -1) >= asked then return end    -- another officer is already on it
        X.SendParts("NIGHT", { date }, X.EncodeNight(night), X.MAX_PARTS)
    end)
end

X.handlers.GWANT = function(sender, name, since)
    if type(name) ~= "string" then return end
    local g = ns.S.Record().gear[name]
    if not g or not X.IsOfficer(X.Me()) then return end
    if ns.S.IsDate(since) and since >= g.date then return end
    local key = "GEAR|" .. name
    if X.answering[key] then return end
    X.answering[key] = true
    local asked = Now()
    After(1 + math.random() * 3, function()
        X.answering[key] = nil
        if (X.started[key] or -1) >= asked then return end
        X.SendParts("GEAR", { name, g.date }, X.EncodeGear(g.gear), X.MAX_GEAR_PARTS)
    end)
end

--- A part arrives. Kept per sender, so two officers answering at once never splice.
local function collect(sender, kind, id, i, n, part, max)
    i, n = tonumber(i), tonumber(n)
    if not (i and n and i >= 1 and i <= n and n <= max) or type(part) ~= "string" then return nil end
    -- only an officer's first part stands the others down: a member's would silence the real answer
    if i == 1 and X.IsOfficer(sender) then X.started[kind .. "|" .. id] = Now() end
    for key, buf in pairs(X.inbox) do
        if Now() - buf.at > X.STALE then X.inbox[key] = nil end
    end
    local key = sender .. "|" .. kind .. "|" .. id
    local buf = X.inbox[key]
    if not buf or buf.n ~= n then
        buf = { n = n, got = 0, parts = {} }
        X.inbox[key] = buf
    end
    buf.at = Now()
    if not buf.parts[i] then buf.got = buf.got + 1 end
    buf.parts[i] = part
    if buf.got < n then return nil end
    X.inbox[key] = nil
    return table.concat(buf.parts)
end

X.handlers.NIGHT = function(sender, date, i, n, part)
    if not ns.S.IsDate(date) then return end
    local text = collect(sender, "NIGHT", date, i, n, part, X.MAX_PARTS)
    if not text or not X.IsOfficer(sender) then return end
    local night = X.DecodeNight(text)
    if not night then return end
    ns.S.Put(date, night, sender)
    X.wanted[date] = nil
    if X.asked[date] then X.asked[date] = nil end
    if next(X.wanted) then X.AskSoon() end
end

X.handlers.GEAR = function(sender, name, date, i, n, part)
    if type(name) ~= "string" or not ns.S.IsDate(date) then return end
    local text = collect(sender, "GEAR", name, i, n, part, X.MAX_GEAR_PARTS)
    if not text or not X.IsOfficer(sender) then return end
    local gear = X.DecodeGear(text)
    if gear then ns.S.PutGear(name, date, gear) end
end

--------------------------------------------------------------------
-- punctuality (Arn, 16 Oct: "share the punctuality with the other officers too")
--
--   PHAVE |1793840400.24,1793235600.22     an officer: the raids it holds a record for, and how many
--                                          people each (newest X.PUNCT_RAIDS)
--   PWANT |1793840400                      anyone holding fewer people for that raid
--   PUNC  |1793840400|i|n|<part>           one officer answers: name:o-600;name:l720;name:n;...
--                                          (o on time, minus = early; l late by seconds; n no-show)
-- Merged person by person on arrival (Logins.lua L.Merge), never replaced wholesale: two officers
-- each saw different logins, and both are true.
--------------------------------------------------------------------

X.PUNCT_RAIDS = 8
X.MAX_PUNCT_PARTS = 6

function X.PunctHaveLine()
    if not ns.Login then return "" end
    local starts, list = ns.Login.Starts(), {}
    for s, n in pairs(starts) do list[#list + 1] = { s, n } end
    table.sort(list, function(a, b) return a[1] > b[1] end)
    local out = {}
    for i = 1, math.min(#list, X.PUNCT_RAIDS) do out[i] = ("%d.%d"):format(list[i][1], list[i][2]) end
    return table.concat(out, ",")
end

function X.EncodePunct(start)
    local out = {}
    for key, p in pairs(ns.Login.Book()) do
        local v = p[start]
        if v and clean(key) then
            local code = v.noshow and "n" or (v.late and ("l" .. int(v.d)) or ("o" .. (v.d and int(v.d) or "")))
            out[#out + 1] = key .. ":" .. code
        end
    end
    table.sort(out)
    return table.concat(out, ";")
end

function X.DecodePunct(s)
    if type(s) ~= "string" then return nil end
    local out = {}
    for _, e in ipairs(split(s, ";")) do
        local key, kind, num = e:match("^([^:]+):([oln])(%-?%d*)$")
        if not key then return nil end
        local d = tonumber(num)
        if kind == "n" then out[key] = { noshow = true }
        elseif kind == "l" then out[key] = { late = true, d = d or 0 }
        else out[key] = { late = false, d = d } end
    end
    return out
end

X.punctWanted = {}            -- start -> true

X.handlers.PHAVE = function(sender, line)
    if not X.IsOfficer(sender) or type(line) ~= "string" or not ns.Login then return end
    local mine = ns.Login.Starts()
    local ask
    for entry in line:gmatch("[^,]+") do
        local s, n = entry:match("^(%d+)%.(%d+)$")
        s, n = tonumber(s), tonumber(n)
        if s and n and n > (mine[s] or 0) and not X.punctWanted[s] then
            X.punctWanted[s] = true
            ask = ask or {}
            ask[#ask + 1] = s
        end
    end
    for _, s in ipairs(ask or {}) do X.Send("PWANT", s) end
end

X.handlers.PWANT = function(sender, start)
    start = tonumber(start)
    if not start or not ns.Login or not X.IsOfficer(X.Me()) then return end
    if not ns.Login.Starts()[start] then return end
    local key = "PUNC|" .. start
    if X.answering[key] then return end
    X.answering[key] = true
    local asked = Now()
    After(1 + math.random() * 3, function()
        X.answering[key] = nil
        if (X.started[key] or -1) >= asked then return end
        X.SendParts("PUNC", { start }, X.EncodePunct(start), X.MAX_PUNCT_PARTS)
    end)
end

X.handlers.PUNC = function(sender, start, i, n, part)
    start = tonumber(start)
    if not start or not ns.Login then return end
    local text = collect(sender, "PUNC", tostring(start), i, n, part, X.MAX_PUNCT_PARTS)
    if not text or not X.IsOfficer(sender) then return end
    local got = X.DecodePunct(text)
    if not got then return end
    for key, v in pairs(got) do ns.Login.Merge(key, start, v) end
    X.punctWanted[start] = nil
end

--------------------------------------------------------------------
-- wiring
--------------------------------------------------------------------

function X.Boot()
    local lib = Lib()
    if not lib then return end
    lib:RegisterGuildMod(X.MOD)
    for cmd, fn in pairs(X.handlers) do lib:RegisterHandler(X.MOD, cmd, fn) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:SetScript("OnEvent", function(_, event, isLogin, isReload)
    if event == "GUILD_ROSTER_UPDATE" then
        X._ranksDirty = true
    elseif event == "PLAYER_ENTERING_WORLD" and (isLogin or isReload) then
        -- after the roster has had time to arrive, and spread out so a guild logging in for raid
        -- night does not all speak in the same second
        After(30 + math.random() * 30, X.Announce)
    end
end)

ns.parts["Core/Share.lua"] = "0.1.0"
