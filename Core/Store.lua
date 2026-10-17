--[[
  BiSGuild :: Core/Store.lua - the guild's raid record, kept by every member.

  Arn, 16 Oct 2026: "All this data we are getting is from my computer, how are other people going to
  get all this info, so if I miss one raid night what stops the addon from updating."

  So the record does not live in one officer's report file. It lives here, in BiSGuildDB.record,
  on every member's client (saved variables survive a restart on Forever again - Arn, 16 Oct:
  ForeverAuras no longer needs re-importing):

    record.nights[date] = { kills =, by =, raiders = { [name] = { present, ready, pulls, flask,
                            elixir, food, weapon, weaponSeen, pots, deaths } },
                            bosses = { [boss] = { pulls, kills, best, killers = { names } } } }
    record.gear[name]   = { date =, gear = { {id, ilvl, enchant, temp, gems}, ... 19 } }

  A report file is ONE way in (Import, on load); Core/Share.lua is the other. Both go through the
  same two rules: a date's fuller copy wins, and a raider's newer gear wins.

  The raider cards and boss pages are BUILT HERE from the record, by the same rules as the readers'
  build_cards / build_bosses (dev/logreport.py) - the suite holds the two against each other - so a
  night that arrived over the guild channel counts exactly like one imported from a log.

  KEPT UNDER `record`, NOT `nights`: Core/Init.lua clears `BiSGuildDB.nights` on every load, because
  that name belonged to the in-game collector removed on 5 Oct.
]]
local ADDON, ns = ...

local S = {}
ns.S = S

--- The gear slots in COMBATANT_INFO's order (dev/logreport.py SLOTS).
S.SLOTS = { "head", "neck", "shoulder", "shirt", "chest", "waist", "legs", "feet", "wrist", "hands",
            "finger1", "finger2", "trinket1", "trinket2", "back", "mainhand", "offhand", "ranged", "tabard" }
--- Which slots should carry an enchant - dev/gearcheck.txt, which the suite holds this to.
S.WANT = { "back", "chest", "wrist", "hands", "legs", "feet", "mainhand" }

S.FIELDS = { "present", "ready", "pulls", "flask", "elixir", "food", "weapon", "weaponSeen", "pots", "deaths" }

function S.Record()
    local d = ns.Books()                         -- this guild's books (Init.lua; alts in other guilds)
    local r = d.record
    if type(r) ~= "table" then r = {} d.record = r end
    if type(r.nights) ~= "table" then r.nights = {} end
    if type(r.gear) ~= "table" then r.gear = {} end
    return r
end

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

--- How much a copy of a night knows, as numbers compared in order: raiders, kills, boss pulls.
--- Two officers logging the same raid write the same night; the one whose log started later is
--- missing the first pulls, and the fuller copy is the truer one.
function S.Weight(n)
    if type(n) ~= "table" then return 0, 0, 0 end
    local pulls = 0
    for _, b in pairs(n.bosses or {}) do pulls = pulls + (tonumber(b.pulls) or 0) end
    return count(n.raiders), tonumber(n.kills) or 0, pulls
end

--- Is `a` a fuller copy than `b`? A tie keeps what is there - a night must not flip back and forth
--- between two equal copies every time somebody shares it.
function S.Fuller(a, b)
    if type(b) ~= "table" then return type(a) == "table" end
    local a1, a2, a3 = S.Weight(a)
    local b1, b2, b3 = S.Weight(b)
    if a1 ~= b1 then return a1 > b1 end
    if a2 ~= b2 then return a2 > b2 end
    return a3 > b3
end

--- A date is "YYYY-MM-DD" and nothing else: the key every copy files a night under.
function S.IsDate(s)
    return type(s) == "string" and s:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil
end

--- Take one night in. True when it changed the record.
function S.Put(date, night, by)
    if not S.IsDate(date) or type(night) ~= "table" or type(night.raiders) ~= "table" then return false end
    local rec = S.Record()
    if not S.Fuller(night, rec.nights[date]) then return false end
    night.by = by or night.by
    rec.nights[date] = night
    return true
end

--- Take one raider's gear in. Newer date wins; the same date keeps what is there.
function S.PutGear(name, date, gear)
    if type(name) ~= "string" or not S.IsDate(date) or type(gear) ~= "table" then return false end
    local rec = S.Record()
    local have = rec.gear[name]
    if have and type(have.date) == "string" and have.date >= date then return false end
    rec.gear[name] = { date = date, gear = gear }
    return true
end

--- The report file, folded into the record (on load). Returns how many nights and gear sets changed.
function S.Import(report)
    if type(report) ~= "table" then return 0, 0 end
    local me = UnitName and UnitName("player") or nil
    local n, g = 0, 0
    for date, night in pairs(type(report.nightly) == "table" and report.nightly or {}) do
        if S.Put(date, night, night.by or me) then n = n + 1 end
    end
    for name, c in pairs(type(report.cards) == "table" and report.cards or {}) do
        if type(c) == "table" and c.gear and S.PutGear(name, c.gearDate, c.gear) then g = g + 1 end
    end
    return n, g
end

--- THE REPORT GOES TO ITS OWN GUILD (16 Oct 2026, Arn: "some people have alts in other guilds"). The
--- report file sits in the client folder, the same for every character; the books are per guild. So
--- a report is filed into this character's guild only when its raiders are that guild's - at least
--- S.MATCH of them on its roster - and only once the client has named the guild and sent its roster.
--- Once per guild per session.
S.MATCH = 0.2
S.imported = {}

function S.ReportFits(report)
    local K = ns.K
    if not (K and K.Guild) then return false end
    K._guildDirty = true
    local members = K.Guild().members
    local names, n, hit = {}, 0, 0
    for _, night in pairs(type(report.nightly) == "table" and report.nightly or {}) do
        for name in pairs(type(night.raiders) == "table" and night.raiders or {}) do names[name] = true end
    end
    for name in pairs(names) do
        n = n + 1
        if members[K.NameKey(name)] then hit = hit + 1 end
    end
    return n > 0 and hit >= math.max(1, math.ceil(n * S.MATCH))
end

function S.ImportWhenReady()
    local key = ns.GuildKey()
    local report = _G.BiSGuildReport
    if not key or type(report) ~= "table" or S.imported[key] then return false end
    local guilded = IsInGuild and IsInGuild()
    if guilded and ((GetNumGuildMembers and GetNumGuildMembers()) or 0) == 0 then return false end  -- not yet
    S.imported[key] = true
    if guilded and not S.ReportFits(report) then return false end
    S.Import(report)
    return true
end

--- Every date on record, oldest first.
function S.Dates()
    local out = {}
    for date in pairs(S.Record().nights) do out[#out + 1] = date end
    table.sort(out)
    return out
end

--- THE NIGHT IS EARNED BY HALF ITS KILLS (Arn, 4 Oct: "if they were there for at least half the
--- kills, sometimes life happens") - present*2 >= kills, the readers' rule, never a fraction.
function S.Earned(night, name)
    local r = night and night.raiders and night.raiders[name]
    local present = r and tonumber(r.present) or 0
    return present > 0 and present * 2 >= (tonumber(night.kills) or 0)
end

function S.Issues(gear)
    local out = {}
    if type(gear) ~= "table" then return out end
    for _, slot in ipairs(S.WANT) do
        for i, s in ipairs(S.SLOTS) do
            if s == slot then
                local g = gear[i]
                if type(g) == "table" and (tonumber(g[1]) or 0) ~= 0 and (tonumber(g[3]) or 0) == 0 then
                    out[#out + 1] = { slot = slot, item = g[1], what = "no enchant" }
                end
            end
        end
    end
    return out
end

--- ONE CARD PER RAIDER from the record (dev/logreport.py build_cards): the nights they earned, their
--- latest night's consumables, deaths and potions over the whole record, their newest gear and its
--- red flags.
function S.Cards()
    local rec = S.Record()
    local cards = {}
    for _, date in ipairs(S.Dates()) do
        local night = rec.nights[date]
        for name, r in pairs(night.raiders or {}) do
            local c = cards[name]
            if not c then
                c = { deaths = 0, pots = 0, attended = {}, issues = {} }
                cards[name] = c
            end
            c.deaths = c.deaths + (tonumber(r.deaths) or 0)
            c.pots = c.pots + (tonumber(r.pots) or 0)
            if (tonumber(r.pulls) or 0) > 0 then
                local last = { date = date }
                for i = 3, #S.FIELDS do last[S.FIELDS[i]] = tonumber(r[S.FIELDS[i]]) or 0 end
                c.last = last
            end
            if S.Earned(night, name) then c.attended[#c.attended + 1] = date end
        end
    end
    for name, g in pairs(rec.gear) do
        local c = cards[name]
        if not c then
            c = { deaths = 0, pots = 0, attended = {}, issues = {} }
            cards[name] = c
        end
        c.gear, c.gearDate = g.gear, g.date
        c.issues = S.Issues(g.gear)
    end
    return cards
end

--- ONE PAGE PER BOSS from the record (dev/logreport.py build_bosses): kills, wipes, the nights it
--- died, the first kill, the fastest, and how many kills each raider stood in.
function S.Bosses()
    local rec = S.Record()
    local pages = {}
    for _, date in ipairs(S.Dates()) do
        for boss, b in pairs(rec.nights[date].bosses or {}) do
            local pg = pages[boss]
            if not pg then
                pg = { kills = 0, wipes = 0, best = 0, nights = {}, killers = {} }
                pages[boss] = pg
            end
            local kills = tonumber(b.kills) or 0
            pg.kills = pg.kills + kills
            pg.wipes = pg.wipes + (tonumber(b.pulls) or 0) - kills
            if kills > 0 then
                pg.first = pg.first or date
                if pg.nights[#pg.nights] ~= date then pg.nights[#pg.nights + 1] = date end
            end
            local best = tonumber(b.best) or 0
            if best > 0 and (pg.best == 0 or best < pg.best) then pg.best = best end
            for _, who in ipairs(b.killers or {}) do pg.killers[who] = (pg.killers[who] or 0) + 1 end
        end
    end
    return pages
end

ns.parts["Core/Store.lua"] = "0.1.0"
