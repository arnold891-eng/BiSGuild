-- BiSGuild headless suite (made by _bisdev/new-addon.sh). Run from the addon root:
--   lua5.1 dev/tests.lua        or, from the AddOns folder: _bisdev/check.sh BiSGuild
local HERE = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local H = dofile(HERE .. "/kit.lua")   -- Nebbinator's strict harness (dev/harness.lua), verbatim
local ROOT = os.getenv("BISGUILD") or (HERE .. "/..")
local FILES = H.TOC(ROOT, "BiSGuild.toc")

-- every global this addon may create; anything else is a leak and a red test
local ALLOWED = {
    BiSGuildDB = true, SLASH_BISGUILD1 = true,
    HARNESS = true, print = true, BiSTheme = true, LibBiSComm = true, SLASH_BISCOMM1 = true,
}
local function Load()
    local before = {}
    for k in pairs(_G) do before[k] = true end
    local NS = {}
    for _, rel in ipairs(FILES) do
        local chunk, err = loadfile(ROOT .. "/" .. rel)
        if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
        chunk("BiSGuild", NS)
    end
    H.leaked = {}
    for k in pairs(_G) do
        if not before[k] and not ALLOWED[k] then H.leaked[#H.leaked + 1] = tostring(k) end
    end
    table.sort(H.leaked)
    return NS
end
local TOC_VERSION
do
    local fh = assert(io.open(ROOT .. "/BiSGuild.toc", "r"))
    for line in fh:lines() do TOC_VERSION = TOC_VERSION or line:match("^## Version:%s*(%S+)") end
    fh:close()
end
_G.GetAddOnMetadata = function(_, key) return key == "Version" and TOC_VERSION or nil end
local function fire(event, ...)
    for _, fr in ipairs(H.frames) do
        if fr._events[event] and fr._scripts.OnEvent then fr._scripts.OnEvent(fr, event, ...) end
    end
end
local function bytes(p) local fh = io.open(p, "rb") if not fh then return nil end local s = fh:read("*a") fh:close() return s end
local function strip(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local said = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) said[#said + 1] = strip(m) end }

--------------------------------------------------------------------
H.section("load")
local NS = Load()
H.eq(#H.leaked, 0, "no accidental globals", table.concat(H.leaked, ", "))
H.eq(NS.VERSION, TOC_VERSION, "version is the TOC's")
fire("ADDON_LOADED", "BiSGuild")
H.ok(type(_G.BiSGuildDB) == "table" and _G.BiSGuildDB.comm == true, "SavedVariables shaped with defaults on first load")

H.section("embedded libs are canon (drift fences)")
H.eq(_G.LibBiSComm.MINOR, 7, "LibBiSComm minor 7")
local function listed(rel) for _, f in ipairs(FILES) do if f == rel then return true end end return false end
H.ok(listed("Libs/BiSTheme/Console.lua"), "TOC lists the Console embed")
H.ok(listed("Libs/LibBiSComm-1.0/LibBiSComm-1.0.lua"), "TOC lists the comm embed")
do
    local canon = bytes((os.getenv("BISTHEME") or (ROOT .. "/../BiSTheme")) .. "/Console.lua")
    if canon then H.ok(bytes(ROOT .. "/Libs/BiSTheme/Console.lua") == canon, "Console.lua byte-identical to canon")
    else H.say("  (note) no canon BiSTheme beside the checkout - bytes fence skipped") end
    local lib = bytes((os.getenv("BISDEV") or (ROOT .. "/../_bisdev")) .. "/LibBiSComm-1.0/LibBiSComm-1.0.lua")
    if lib then H.ok(bytes(ROOT .. "/Libs/LibBiSComm-1.0/LibBiSComm-1.0.lua") == lib, "LibBiSComm byte-identical to _bisdev")
    else H.say("  (note) no _bisdev beside the checkout - lib bytes fence skipped") end
end

H.section("the shared BiS channel")
local lib = _G.LibBiSComm
H.ok(lib._booted and lib:Enabled(), "comm booted and on")
H.eq(lib.addons.BiSGuild, TOC_VERSION, "registered with the TOC version")

H.section("/bisg")
H.ok(type(_G.SlashCmdList.BISGUILD) == "function", "slash registered")
H.eq(_G.SLASH_BISGUILD1, "/bisg", "as /bisg")
_G.SlashCmdList.BISGUILD("help")
H.ok(said[1] and said[1]:find(TOC_VERSION, 1, true) ~= nil, "help says the version", said[1])

H.section("the off switch survives a logout")
lib:SetEnabled(false)
fire("PLAYER_LOGOUT")
H.eq(_G.BiSGuildDB.comm, false, "off is saved")
lib:SetEnabled(true)
fire("PLAYER_LOGOUT")
H.eq(_G.BiSGuildDB.comm, true, "on is saved")

--=============================================================================
-- ATTENDANCE. Arn's rule, 4 Oct 2026: "if there were there for at least half the kills, sometimes
-- life happens". The night is the unit; half its kills earns it.
--
-- THE MOCK HAD TO BE TAUGHT THE RAID FIRST. The house kit answers "Kumlust" to UnitName for every
-- unit, which would make a 25-man look like one person twenty-five times over and every one of
-- these tests pass for the wrong reason. H.raid is the real list; the client answers per unit.
--=============================================================================
local G, R, W = NS.G, NS.R, NS.W

local realUnitName = _G.UnitName
_G.UnitName = function(unit)
    if unit == "player" then return "Kumlust" end
    local i = tostring(unit):match("^raid(%d+)$") or tostring(unit):match("^party(%d+)$")
    return i and H.raid[tonumber(i)] or nil
end
_G.GetRealZoneText = function() return "Black Temple" end
local clock = 1000000
_G.GetServerTime = function() return clock end
-- the client has `date`; the harness does not, and a stub that is LESS capable than the client
-- hides the formatting instead of testing it
_G.date = _G.date or os.date

local function reset()
    _G.BiSGuildDB.nights = {}
    W.Forget()
end

H.section("what a night is")
do
    reset()
    H.inRaid = true
    H.raid = { "Kumlust", "Ariar", "Gruxz" }

    W.Kill("Najentus", 1000)
    W.Kill("Supremus", 1000 + 600)
    H.eq(#G.Nights(), 1, "two kills ten minutes apart are one night")

    -- THE MIDNIGHT LESSON, borrowed from BiSMemories 0.4.0: a clear that ends after midnight is
    -- still one night. A calendar day would cut this raid in half and orphan its last two bosses.
    W.Kill("Illidari Council", 1000 + (5 * 60 * 60))
    H.eq(#G.Nights(), 2, "a five-hour gap is a new night")
    W.Kill("Illidan", 1000 + (5 * 60 * 60) + (2 * 60 * 60))
    H.eq(#G.Nights(), 2, "but a two-hour break inside it is not - dinner does not split a night")
end

H.section("at least half the kills")
do
    reset()
    H.inRaid = true

    -- four kills; each person sees a different number of them
    H.raid = { "Kumlust", "Ariar", "Gruxz", "Bruma" };  W.Kill("One", 100)
    H.raid = { "Kumlust", "Ariar", "Gruxz" };           W.Kill("Two", 200)
    H.raid = { "Kumlust", "Ariar" };                    W.Kill("Three", 300)
    H.raid = { "Kumlust" };                             W.Kill("Four", 400)

    local night = G.Nights()[1]
    H.eq(#night.kills, 4, "four kills in the night")

    H.eq(G.Earned(night, "Kumlust"), true,  "4 of 4 earns it")
    H.eq(G.Earned(night, "Ariar"),   true,  "3 of 4 earns it")
    H.eq(G.Earned(night, "Gruxz"),   true,  "2 of 4 earns it - exactly half IS at least half")
    H.eq(G.Earned(night, "Bruma"),   false, "1 of 4 does not")
    H.eq(G.Earned(night, "Nobody"),  false, "and somebody who never turned up does not")
end

H.section("an odd number of kills")
do
    -- THE REASON IT IS ASKED AS present*2 >= total. Three kills and one attendance is 1 against
    -- 1.5, and a person's raid record is not a thing to hand to floating point.
    reset()
    H.inRaid = true
    H.raid = { "Kumlust", "Ariar" };  W.Kill("One", 100)
    H.raid = { "Kumlust", "Ariar" };  W.Kill("Two", 200)
    H.raid = { "Kumlust" };           W.Kill("Three", 300)

    local night = G.Nights()[1]
    H.eq(G.Earned(night, "Ariar"), true, "2 of 3 earns it")
    H.raid = { "Kumlust" }
    H.eq(G.Earned(night, "Ghost"), false, "0 of 3 does not")

    reset()
    H.raid = { "Kumlust", "Ariar" };  W.Kill("One", 100)
    H.raid = { "Kumlust" };           W.Kill("Two", 200)
    H.raid = { "Kumlust" };           W.Kill("Three", 300)
    H.eq(G.Earned(G.Nights()[1], "Ariar"), false, "1 of 3 does not - half of three is not one")
end

H.section("a wipe is not a kill")
do
    reset()
    H.inRaid = true
    H.raid = { "Kumlust", "Ariar" }
    -- through `fire`, which only delivers to a frame that REGISTERED the event: calling the
    -- handler by hand would pass with the registration taken straight back out
    fire("ENCOUNTER_END", 601, "Illidan", 3, 25, 0)
    H.eq(#G.Nights(), 0, "an encounter that ended in a wipe is written down nowhere")

    fire("ENCOUNTER_END", 601, "Illidan", 3, 25, 1)
    H.eq(#G.Nights(), 1, "the kill is - so the addon did ask for ENCOUNTER_END in the first place")
    H.eq(#G.Nights()[1].kills, 1, "once")

    -- BOTH events fire for one kill on some clients. Counted twice, a two-boss night becomes a
    -- four-boss night and everyone's half moves.
    fire("BOSS_KILL", 601, "Illidan")
    H.eq(#G.Nights()[1].kills, 1, "and the other event for the same boss does not make it two")
end

H.section("a name the client will not say")
do
    -- 4 Oct 2026, the same day LibBiSComm was fixed for it: UnitName can hand back a SECRET VALUE,
    -- which is truthy and errors when read. An attendance list uses every name as a table key, so
    -- one secret would be a red error in the middle of a boss kill.
    local secretMeta = {
        __concat = function() error("secret value: refused", 0) end,
        __index = function() error("secret value: refused", 0) end,
        __tostring = function() error("secret value: refused", 0) end,
    }
    local function secret() return setmetatable({}, secretMeta) end
    local realSecret = _G.issecretvalue
    _G.issecretvalue = function(v) return getmetatable(v) == secretMeta end

    reset()
    H.inRaid = true
    H.raid = { "Kumlust", secret(), "Ariar" }

    local ok = pcall(W.Kill, "Najentus", 100)
    H.ok(ok, "a secret name in the raid does not throw at the boss kill")
    local night = G.Nights()[1]
    H.ok(night ~= nil, "the kill is still recorded")
    H.eq(#night.kills[1].who, 2, "with the two names we can read, and not the one we cannot")
    H.eq(G.Earned(night, "Kumlust"), true, "the readable ones keep their night")

    _G.issecretvalue = realSecret
end

H.section("tonight is not part of the record")
do
    -- 4 Oct 2026. Arn, on why their log-based numbers being a raid behind never mattered: "obv
    -- someone that is rolling on loot is here today". The person being voted on is standing in the
    -- raid by definition, so tonight says nothing about them - and a night still having kills
    -- cannot answer "half of them" yet. Counting it flatters everyone up for the item.
    reset()
    H.inRaid = true
    H.raid = { "Kumlust", "Ariar" }
    clock = 500000
    W.Kill("One", clock)                        -- a night, right now

    H.eq(#G.Settled(clock), 0, "a night in progress is not settled")
    H.ok(G.Tonight(clock) ~= nil, "it is tonight")
    local _, _, pct = G.Rate("Kumlust", clock)
    H.eq(pct, nil, "and nobody has a percentage from it")

    -- four hours later the night is over and joins the record
    local later = clock + (4 * 60 * 60)
    H.eq(#G.Settled(later), 1, "once the quiet is longer than the gap it settles")
    H.eq(G.Tonight(later), nil, "and is no longer tonight")
    local earned, raided
    earned, raided, pct = G.Rate("Kumlust", later)
    H.eq(earned, 1, "now it counts") H.eq(raided, 1, "as one night") H.eq(pct, 100, "100%")

    _G.SlashCmdList.BISGUILD("")
    H.ok(said[#said]:find("tonight", 1, true) ~= nil or said[#said - 1]:find("tonight", 1, true) ~= nil,
         "/bisg says tonight is excluded rather than hiding it", said[#said])
end

H.section("the percentage")
do
    reset()
    H.inRaid = true
    -- night one: both there for everything
    H.raid = { "Kumlust", "Ariar" };  W.Kill("One", 100)
    -- night two: Ariar misses it entirely
    H.raid = { "Kumlust" };           W.Kill("Two", 100 + (4 * 60 * 60))
    -- both nights are long finished as far as `clock` is concerned
    local earned, raided, pct = G.Rate("Kumlust")
    H.eq(earned, 2, "two nights earned") H.eq(raided, 2, "of two raided") H.eq(pct, 100, "100%")

    earned, raided, pct = G.Rate("Ariar")
    H.eq(earned, 1, "one night earned") H.eq(raided, 2, "of the same two") H.eq(pct, 50, "50%")

    local _, _, none = G.Rate("NeverSeen")
    H.eq(none, 0, "somebody who has never been seen is nought, not nil, once nights exist")

    local rows = G.Everyone()
    H.eq(#rows, 2, "two people on record")
    H.eq(rows[1].name, "Kumlust", "best first")
end

H.section("nights that do not count")
do
    -- A NIGHT WHERE NOTHING DIED IS NOBODY'S ABSENCE. Counting it would punish exactly the people
    -- who stayed for three hours of wipes.
    reset()
    H.inRaid = true
    H.raid = { "Kumlust" }
    W.Kill("One", 100)
    G.NightAt(100 + (10 * 60 * 60), "Black Temple")   -- a night that started and killed nothing
    H.eq(#G.Nights(), 2, "the empty night is on record")
    local _, raided = G.Rate("Kumlust")
    H.eq(raided, 1, "but it is not counted against anyone")
    H.eq(#G.Raided(), 1, "and a report does not show it")
end

H.section("only a raid is a raid night")
do
    reset()
    H.inRaid = false
    local night, why = W.Kill("Najentus", 100)
    H.eq(night, nil, "a boss killed alone is not a raid night")
    H.eq(why, "not a raid", "and it says so", tostring(why))
    H.eq(#G.Nights(), 0, "nothing written down")

    -- A FIVE-MAN HAS BOSSES TOO (4 Oct 2026). Arn: "there are no raids in wow forever yet" - so on
    -- that client a dungeon would be the only thing this ever recorded, and raid attendance would
    -- be made entirely of Blackfathom runs. On TBC it rots the number more quietly: a Tuesday
    -- heroic counting exactly as much as Black Temple.
    local realInGroup = _G.IsInGroup
    _G.IsInGroup = function() return true end       -- in a party...
    H.inRaid = false                                -- ...but not a raid
    H.raid = { "Kumlust", "Ariar" }
    night, why = W.Kill("Aku'mai", 200)
    H.eq(night, nil, "a dungeon boss in a party is not a raid night")
    H.eq(why, "not a raid", "and it says why", tostring(why))
    H.eq(#G.Nights(), 0, "still nothing written down")
    _G.IsInGroup = realInGroup

    H.inRaid = true
    W.Kill("Najentus", 300)
    H.eq(#G.Nights(), 1, "a raid group is")
end

H.section("reading it back")
do
    reset()
    H.inRaid = true
    H.raid = { "Kumlust", "Ariar" }
    W.Kill("Najentus", 100)
    _G.SlashCmdList.BISGUILD("")
    H.ok(said[#said] ~= nil, "/bisg prints something")
    _G.SlashCmdList.BISGUILD("nights")
    H.ok(said[#said]:find("Black Temple", 1, true) ~= nil, "/bisg nights names the place", said[#said])
    _G.SlashCmdList.BISGUILD("me")
    H.ok(said[#said] ~= nil, "/bisg me prints the working")

    reset()
    _G.SlashCmdList.BISGUILD("")
    H.ok(said[#said]:find("backwards", 1, true) ~= nil,
         "with nothing on record it says attendance cannot be worked out backwards", said[#said])
end

--=============================================================================
-- CONSUMABLES. Arn's definition: a flask, OR a battle and a guardian elixir together, AND food.
--
-- The list is LEARNED, never shipped. Typing flask ids from memory is how a spell list gets
-- reasoned out of a build number and comes out wrong - and a wrong aura list does not error, it
-- reports the whole raid at nought percent and looks exactly like data.
--=============================================================================
local C = NS.C

-- the client's buff reader, taught the real shape: an aura has an id, and the walk STOPS at the
-- first empty slot rather than running to forty
local BUFFS = {}
_G.C_UnitAuras = nil
-- UnitBuff's real shape on 2.5.x: name, icon, count, debuffType, duration, expirationTime,
-- unitCaster, canStealOrPurge, nameplateShowPersonal, spellId - so the id is the TENTH return and
-- not the eleventh. One slot out and every id reads back nil, which is a mock that quietly says
-- "nobody has anything" while the client says otherwise.
_G.UnitBuff = function(unit, i)
    local a = (BUFFS[unit] or {})[i]
    if not a then return nil end
    return a.name, "icon", 1, nil, 3600, 0, "player", false, false, a.id
end

local FLASK, BATTLE, GUARDIAN, FOOD = 17628, 33721, 39625, 33263

H.section("nothing taught is not nought percent")
do
    reset()
    _G.BiSGuildDB.taught = {}
    H.eq(C.Ready(), false, "an addon with no list cannot judge anybody")
    H.eq(C.Check("raid1"), nil, "and says nil, which is not false")
    H.eq(C.Snapshot(), nil, "a whole raid reads as nil too")

    -- THE ONE THAT MATTERS. An empty list reporting 0% is the most confident kind of wrong, and
    -- it is the kind a loot council would act on.
    local _, _, pct = C.Rate("Kumlust")
    H.eq(pct, nil, "and a rate from no judgements is nil, never 0")

    _G.SlashCmdList.BISGUILD("consumes")
    H.ok(said[#said - 1]:find("nothing taught", 1, true) ~= nil
         or said[#said]:find("guessed", 1, true) ~= nil,
         "/bisg consumes says so in words rather than printing zeroes", said[#said])
end

H.section("half a list is still no list")
do
    _G.BiSGuildDB.taught = {}
    C.Teach(FLASK, "flask")
    H.eq(C.Ready(), false, "a flask alone cannot answer - food is part of the definition")
    C.Teach(FOOD, "food")
    H.eq(C.Ready(), true, "flask and food can")

    _G.BiSGuildDB.taught = {}
    C.Teach(FOOD, "food")
    C.Teach(BATTLE, "battle")
    H.eq(C.Ready(), false, "one elixir kind and food cannot - the pair is the point")
    C.Teach(GUARDIAN, "guardian")
    H.eq(C.Ready(), true, "both kinds and food can")

    H.eq(C.Teach(123, "beer"), false, "a kind the addon does not know is refused")
end

H.section("flask OR the pair, AND food")
do
    _G.BiSGuildDB.taught = {}
    C.Teach(FLASK, "flask") C.Teach(BATTLE, "battle")
    C.Teach(GUARDIAN, "guardian") C.Teach(FOOD, "food")

    BUFFS.raid1 = { { id = FLASK, name = "Flask" }, { id = FOOD, name = "Food" } }
    H.eq(C.Check("raid1").ok, true, "flask and food is ready")

    BUFFS.raid1 = { { id = BATTLE, name = "B" }, { id = GUARDIAN, name = "G" }, { id = FOOD, name = "F" } }
    H.eq(C.Check("raid1").ok, true, "both elixirs and food is ready")

    BUFFS.raid1 = { { id = BATTLE, name = "B" }, { id = FOOD, name = "F" } }
    H.eq(C.Check("raid1").ok, false, "one elixir and food is not - the pair is the whole point")

    BUFFS.raid1 = { { id = FLASK, name = "Flask" } }
    H.eq(C.Check("raid1").ok, false, "a flask with no food is not")

    BUFFS.raid1 = { { id = FOOD, name = "F" } }
    H.eq(C.Check("raid1").ok, false, "food alone is not")

    BUFFS.raid1 = {}
    H.eq(C.Check("raid1").ok, false, "and nothing at all certainly is not")
end

H.section("read at the pull, not at the kill")
do
    -- FOOD IS LOST ON DEATH. Judging at the kill would mark down exactly the people who died
    -- doing it, which is the opposite of what the number is for.
    reset()
    H.inRaid = true
    H.raid = { "Kumlust", "Ariar" }
    BUFFS.raid1 = { { id = FLASK, name = "Flask" }, { id = FOOD, name = "F" } }
    BUFFS.raid2 = { { id = FLASK, name = "Flask" }, { id = FOOD, name = "F" } }

    fire("ENCOUNTER_START", 601, "Illidan", 3, 25)
    -- both die; their food is gone by the time the boss falls
    BUFFS.raid1 = {}
    BUFFS.raid2 = {}
    fire("ENCOUNTER_END", 601, "Illidan", 3, 25, 1)

    local kill = G.Nights()[1].kills[1]
    H.ok(type(kill.ready) == "table", "the pull's reading is on the kill")
    H.eq(kill.ready.Kumlust, true, "and it is what they had when it STARTED, not when it ended")

    -- asked from four hours later, so the night has settled: tonight is never in the record
    local after = clock + (4 * 60 * 60)
    H.eq(C.Rate("Kumlust"), 0, "while the night is still running it counts for nothing")
    local ready, counted, pct = C.Rate("Kumlust", after)
    H.eq(ready, 1, "one ready pull") H.eq(counted, 1, "of one judged") H.eq(pct, 100, "100%")
end

H.section("a pull nobody watched")
do
    -- No ENCOUNTER_START - an older client, or a boss that raises none. That is NOT everybody
    -- failing; it is nobody being judged.
    reset()
    H.inRaid = true
    H.raid = { "Kumlust" }
    BUFFS.raid1 = {}
    fire("BOSS_KILL", 601, "Najentus")
    local kill = G.Nights()[1].kills[1]
    H.eq(kill.ready, nil, "a kill with no pull reading carries none")
    local _, counted, pct = C.Rate("Kumlust")
    H.eq(counted, 0, "and it is counted against nobody")
    H.eq(pct, nil, "the rate stays nil")
end

H.section("the name is the classifier")
do
    -- Arn: "cant we just check that stuff with the logs?" Nothing in the client, log included, ever
    -- says "this is a flask" - but the client says what it is CALLED, and most of them name
    -- themselves. English patterns, and a suggestion rather than a verdict: every guess is printed.
    H.eq(C.Guess("Flask of Relentless Assault"), "flask", "a flask names itself")
    H.eq(C.Guess("Elixir of Major Agility"), "elixir", "so does an elixir")
    H.eq(C.Guess("Elixir of Major Defense"), "elixir", "both kinds the same way")
    H.eq(C.Guess("Well Fed"), "food", "and food")
    H.eq(C.Guess("Blessing of Kings"), nil, "a buff that is not a consumable is left alone")

    -- BATTLE AND GUARDIAN ARE NOT IN THE NAME, which is why the pair is COUNTED, not named: the
    -- game will not let two battle elixirs sit on one person, so two elixirs is one of each.
    _G.BiSGuildDB.taught = {}
    C.Teach(FOOD, "food") C.Teach(BATTLE, "elixir")
    H.eq(C.Ready(), false, "one elixir known is not enough to count a pair")
    C.Teach(GUARDIAN, "elixir")
    H.eq(C.Ready(), true, "two are")

    BUFFS.raid1 = { { id = BATTLE, name = "E1" }, { id = FOOD, name = "F" } }
    H.eq(C.Check("raid1").ok, false, "one elixir up and food is not ready")
    BUFFS.raid1 = { { id = BATTLE, name = "E1" }, { id = GUARDIAN, name = "E2" }, { id = FOOD, name = "F" } }
    H.eq(C.Check("raid1").ok, true, "two elixirs up and food is")

    -- /bisg learn does the four at once
    _G.BiSGuildDB.taught = {}
    BUFFS.player = {
        { id = FLASK, name = "Flask of Relentless Assault" },
        { id = FOOD, name = "Well Fed" },
        { id = 12345, name = "Blessing of Kings" },
    }
    _G.SlashCmdList.BISGUILD("learn")
    H.eq(_G.BiSGuildDB.taught[FLASK], "flask", "learn writes the flask down")
    H.eq(_G.BiSGuildDB.taught[FOOD], "food", "and the food")
    H.eq(_G.BiSGuildDB.taught[12345], nil, "and leaves the paladin buff alone")
    H.eq(C.Ready(), true, "one command is enough to start judging")
end

H.section("teaching from your own buffs")
do
    _G.BiSGuildDB.taught = {}
    BUFFS.player = { { id = FLASK, name = "Flask of Relentless Assault" } }
    _G.SlashCmdList.BISGUILD("buffs")
    H.ok(said[#said - 1]:find("Flask of Relentless Assault", 1, true) ~= nil
         or said[#said]:find("Flask of Relentless Assault", 1, true) ~= nil,
         "/bisg buffs names what the CLIENT calls it", said[#said - 1])

    _G.BiSGuildDB.taught = {}
    _G.SlashCmdList.BISGUILD("teach 17628 flask")
    H.eq(_G.BiSGuildDB.taught[17628], "flask", "teach writes it down")
    _G.SlashCmdList.BISGUILD("forget 17628")
    H.eq(_G.BiSGuildDB.taught[17628], nil, "forget takes it away")
end

_G.UnitName = realUnitName

H.report()
