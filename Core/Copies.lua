--[[
  BiSGuild :: Core/Copies.lua - is this copy whole, and is it the same as the guild's?

  Arn, 16 Oct 2026: "we can do it like face fusion and there are multiple places that need to match up
  for the hash to work, maybe we ask other guildies what version they are at to check etc and really
  lock it down".

  TWO CHECKS, AND WHAT EACH CAN AND CANNOT SEE.

  1. WHOLE. The game cannot read an addon's files - no addon can - so it cannot hash them. What it can
     see is which of our files actually ran, and which version each one says it is: every file ends by
     writing its version into ns.parts, and Core/Build.lua (written by Tools\stamp.ps1) lists every file
     that should have. A file missing, a file that broke while loading, or one left over from an older
     version, and the copy is not whole: its windows and its sharing switch off, and it says why. (The
     client skips a missing file without a word, which is exactly how a half-updated addon ends up
     "working" wrong.) The full byte-for-byte check is the PowerShell script's: it refuses to run on a
     copy that does not match Tools\manifest.txt.

  2. THE SAME AS THE GUILD'S. Each copy tells the guild its version and fingerprint at login, and the
     guild answers. A copy that differs from every guildmate's copy of the same version says so; an
     old copy hears that a newer one is about; officers can list who runs what (`/bisg copy`).

  WHAT NEITHER CAN DO, plainly: a wholly fake BiS Guild controls everything it shows you, this check
  included, and can tell the guild the real fingerprint. These catch the swapped file, the broken or
  half-updated install and the forgotten old copy - nearly every real case. The faked addon is caught
  only where it came from, which is why the warning says "CurseForge or your officers" first.

  THE CONVERSATION (MOD "GLOG", alongside Core/Share.lua - but believed from ANY guildmate, since all it
  says is "this is my copy"):

    BUILD |0.1.0|<64 hex>|?      at login, 20-40 s in: my copy - and what is yours?
    BUILD |0.1.0|<64 hex>|.      an answer. "x" added: this copy failed its own check.

  LEAN (standing order, 7 Oct): one line per login, and an ask is answered by at most a few: a copy
  waits 2-10 s and stands down once C.ENOUGH others carrying ITS fingerprint have already answered. A
  copy that spoke in the last C.QUIET seconds does not answer at all.
]]
local ADDON, ns = ...

local C = {}
ns.Copy = C

C.ENOUGH = 3                 -- answers carrying our fingerprint that make ours unnecessary
C.QUIET = 120                -- seconds after we last spoke in which we do not answer again
C.KEEP = 30 * 86400          -- a guildmate's copy is remembered this long
C.RECENT = 14 * 86400        -- and counted in the summary for this long

local function Now() return GetTime and GetTime() or 0 end
local function After(t, fn) if C_Timer and C_Timer.After then C_Timer.After(t, fn) end end
local function Short(name)
    if type(name) ~= "string" then return nil end
    return name:match("^([^%-]+)") or name
end

--------------------------------------------------------------------
-- 1. this copy
--------------------------------------------------------------------

function C.Mine() return type(ns.BUILD) == "table" and ns.BUILD or nil end

function C.Fingerprint()
    local b = C.Mine()
    local fp = b and b.fingerprint
    return type(fp) == "string" and fp:match("^%x+$") and #fp == 64 and fp:upper() or nil
end

--- Everything wrong with this copy, as sentences; an empty list for a whole one.
function C.Problems()
    local out, b = {}, C.Mine()
    if not b then
        out[1] = "Core/Build.lua did not load"
        return out
    end
    if b.version ~= ns.VERSION then
        out[#out + 1] = ("Core/Build.lua is from %s, the TOC says %s"):format(tostring(b.version), tostring(ns.VERSION))
    end
    if not C.Fingerprint() then out[#out + 1] = "Core/Build.lua carries no fingerprint" end
    local parts = ns.parts or {}
    for _, p in ipairs(type(b.parts) == "table" and b.parts or {}) do
        local v = parts[p]
        if v == nil then
            out[#out + 1] = p .. " did not load"
        elseif v ~= ns.VERSION then
            out[#out + 1] = ("%s is from %s"):format(p, tostring(v))
        end
    end
    return out
end

--- Look once, after every file has loaded. A copy that is not whole stays switched off this session.
function C.Check()
    local p = C.Problems()
    if #p > 0 then ns.broken = p end
    return ns.broken == nil
end

--------------------------------------------------------------------
-- 2. the guild's copies
--------------------------------------------------------------------

function C.Book()
    local b = ns.Books()
    if type(b.copies) ~= "table" then b.copies = {} end
    return b.copies
end

local function numbers(v)
    local t = {}
    for n in tostring(v):gmatch("%d+") do t[#t + 1] = tonumber(n) end
    return t
end

--- Is version a newer than version b? 0.10.0 is newer than 0.9.3.
function C.Newer(a, b)
    local x, y = numbers(a), numbers(b)
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p > q end
    end
    return false
end

function C.Say(ask)
    if not (ns.X and IsInGuild and IsInGuild()) then return false end
    C.lastSent = Now()
    ns.X.Send("BUILD", ns.VERSION, C.Fingerprint() or "-", (ask and "?" or ".") .. (ns.broken and "x" or ""))
    return true
end

function C.AnswerSoon()
    if C.waiting then return end
    if C.lastSent and Now() - C.lastSent < C.QUIET then return end
    C.waiting, C.same = true, 0
    After(2 + math.random() * 8, function()
        C.waiting = nil
        if (C.same or 0) >= C.ENOUGH then return end      -- enough copies like ours have answered
        C.Say(false)
    end)
end

function C.Hear(sender, version, fp, flags)
    if type(version) ~= "string" or #version > 24 or not version:match("^[%w%.%-]+$") then return end
    if type(fp) ~= "string" or not (fp == "-" or (#fp == 64 and fp:match("^%x+$"))) then return end
    flags = type(flags) == "string" and flags or ""
    local name = Short(sender)
    -- guildmates only; never ourselves
    C.me = C.me or ns.X.Me()                   -- a name does not change in a session; asked once
    if not name or name == C.me or ns.X.Rank(name) == nil then return end
    fp = fp:upper()
    C.Book()[name] = { v = version, fp = fp, t = time(), x = flags:find("x", 1, true) and true or nil }
    if C.waiting and fp == C.Fingerprint() and version == ns.VERSION then C.same = (C.same or 0) + 1 end
    if flags:find("?", 1, true) then C.AnswerSoon() end
    C.Judge()
end

--- What the guild's copies look like next to ours, over the last C.RECENT seconds.
---   how: "match" same version and fingerprint · "differ" same version, other fingerprint ·
---        "older" / "newer" another version · "broken" a copy that failed its own check
function C.Summary()
    local mine = C.Fingerprint() or "-"
    local s = { match = 0, differ = 0, older = 0, newer = 0, broken = 0, list = {} }
    local now, book = time(), C.Book()
    for name, e in pairs(book) do
        if type(e) ~= "table" or type(e.t) ~= "number" or now - e.t > C.KEEP then
            book[name] = nil
        elseif now - e.t <= C.RECENT then
            local how
            if e.x then how = "broken"
            elseif e.v == ns.VERSION then how = (e.fp == mine) and "match" or "differ"
            elseif C.Newer(e.v, ns.VERSION) then how = "newer"
            else how = "older" end
            s[how] = s[how] + 1
            if how == "newer" and (not s.newest or C.Newer(e.v, s.newest)) then s.newest = e.v end
            s.list[#s.list + 1] = { name = name, v = e.v, how = how, t = e.t }
        end
    end
    table.sort(s.list, function(a, b)
        if a.how ~= b.how then return a.how < b.how end
        return a.name < b.name
    end)
    return s
end

--- Say it once a session, and only when it is worth saying.
function C.Judge()
    if C.toldOdd and C.toldOld then return end
    local s, T = C.Summary(), ns.T
    if not C.toldOdd and s.differ >= C.ENOUGH and s.match == 0 then
        C.toldOdd = true
        ns.Print("%s", T.text("warn", ("your copy of BiS Guild %s is not the same as %d guildmates' copies of %s.")
            :format(ns.VERSION, s.differ, ns.VERSION)))
        ns.Print("  %s", T.text("muted", "Unless you changed it yourself: delete the BiSGuild folder and install"
            .. " it again from CurseForge. /bisg copy says more."))
    end
    if not C.toldOld and s.newer >= 1 then
        C.toldOld = true
        ns.Print("%d guildmate(s) run BiS Guild %s - you have %s. %s", s.newer, tostring(s.newest), ns.VERSION,
            T.text("muted", "Update it from CurseForge."))
    end
end

local AGO = { { 86400, "d" }, { 3600, "h" }, { 60, "m" } }
local function ago(t)
    local d = math.max(0, time() - (t or 0))
    for _, u in ipairs(AGO) do if d >= u[1] then return math.floor(d / u[1]) .. u[2] .. " ago" end end
    return "just now"
end

--- `/bisg copy`: this copy, then the guild's, then - for officers - who runs something else.
function C.Report()
    local T, s = ns.T, C.Summary()
    ns.Print("this copy: %s, fingerprint %s", ns.VERSION, T.text("accent", C.Fingerprint() or "none"))
    if ns.broken then
        for _, p in ipairs(ns.broken) do ns.Print("  %s", T.text("warn", p)) end
    else
        ns.Print("  %s", T.text("good", "whole - every file loaded, all from " .. ns.VERSION))
    end
    ns.Print("  %s", T.text("muted", "That number is what this copy SAYS. The check that counts is the CurseForge"
        .. " page's own command and number - /bisg script shows where."))
    local seen = s.match + s.differ + s.older + s.newer + s.broken
    if seen == 0 then
        ns.Print("guild: no guildmate's copy heard from yet (they answer at login)")
        return s
    end
    ns.Print("guild, last 14 days: %s same as yours · %s different · %d older · %d newer%s",
        T.text("good", tostring(s.match)), s.differ > 0 and T.text("warn", tostring(s.differ)) or "0",
        s.older, s.newer, s.broken > 0 and (" · " .. T.text("warn", s.broken .. " broken")) or "")
    if ns.X and ns.X.IsOfficer(ns.X.Me()) then
        local WORDS = { differ = "same version, different files", older = "older", newer = "newer",
                        broken = "failed its own check" }
        local n = 0
        for _, e in ipairs(s.list) do
            if e.how ~= "match" then
                n = n + 1
                if n <= 20 then
                    ns.Print("  %s %s - %s, %s", e.name, e.v, e.how == "older" and WORDS.older
                        or T.text("warn", WORDS[e.how]), ago(e.t))
                end
            end
        end
        if n > 20 then ns.Print("  %s", T.text("muted", ("and %d more"):format(n - 20))) end
    end
    return s
end

--------------------------------------------------------------------
-- wiring
--------------------------------------------------------------------

if ns.X then ns.X.handlers.BUILD = C.Hear end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, event, a, b)
    if event == "ADDON_LOADED" and a == ADDON then
        C.Check()
    elseif event == "PLAYER_ENTERING_WORLD" and (a or b) then
        if ns.broken and not C.told then
            C.told = true
            ns.TellBroken()
        end
        After(20 + math.random() * 20, function() C.Say(true) end)
    end
end)

ns.parts["Core/Copies.lua"] = "0.1.0"
