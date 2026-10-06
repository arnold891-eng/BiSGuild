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
--=============================================================================
-- The collector is gone (5 Oct 2026). Arn: "we can get rid of the attendence and consume check
-- lets do logs for that". The addon counted boss kills and who was standing there, which was a
-- SECOND source of truth against the combat log - and when two disagree, the one people believe is
-- the one on the website. Everything below tests the log report and the window instead.
--=============================================================================
local clock = 1000000
_G.GetServerTime = function() return clock end
_G.date = _G.date or os.date
local P = NS.P

H.section("nothing is collected in game any more")
do
    -- The addon used to count boss kills and who was there. It does not now, and the point of
    -- deleting it is that nothing is left half-wired: a watcher still registered for BOSS_KILL
    -- would be a second source of truth quietly disagreeing with the website.
    H.eq(NS.G, nil, "no night keeper")
    H.eq(NS.R, nil, "no roster reader")
    H.eq(NS.W, nil, "and nothing watching for a boss to die")

    for _, fr in ipairs(H.frames) do
        H.ok(not (fr._events and (fr._events.BOSS_KILL or fr._events.ENCOUNTER_END
                                  or fr._events.ENCOUNTER_START)),
             "no frame is still listening for an encounter")
    end

    -- and the record it used to keep is dropped rather than left to rot in saved variables where
    -- nothing can read it any more
    _G.BiSGuildDB.nights = { { kills = {} } }
    _G.BiSGuildDB.taught = { [1] = "flask" }
    fire("ADDON_LOADED", "BiSGuild")
    H.eq(_G.BiSGuildDB.nights, nil, "an old nights table is cleared on load")
    H.eq(_G.BiSGuildDB.taught, nil, "and the old consumables list with it")
end

H.section("no report is not an empty report")
do
    _G.BiSGuildReport = nil
    H.eq(P.Report(), nil, "with no file written there is no report")
    H.eq(P.Of("Kumlust"), nil, "and nobody has numbers from it")
    H.eq(#P.Rows(), 0, "and the list is empty rather than erroring")

    -- THE FILE IS NAMED IN THE TOC AND IS NOT IN GIT. A fresh install has none, and deploy.sh
    -- wipes the game folder before copying, so a deploy removes it too. Looking broken at that
    -- moment is the easy mistake; saying what to run is the fix.
    _G.BiSGuildDB.logs = nil
    local before = #said
    _G.SlashCmdList.BISGUILD("report")
    local said1 = table.concat(said, "\n", before + 1, #said)
    H.ok(said1:find("/bisg logs", 1, true) ~= nil,
         "with no report AND no logs folder it asks for the folder", said1)

    -- once it knows where the logs are, the next step is the script and it says so
    P.SetLogs("C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs")
    before = #said
    _G.SlashCmdList.BISGUILD("report")
    local said2 = table.concat(said, "\n", before + 1, #said)
    H.ok(said2:find("/bisg script", 1, true) ~= nil,
         "and once it knows, it points at the script instead", said2)
    _G.BiSGuildDB.logs = nil
end

--=============================================================================
-- THE WINDOW. Arn: "give me a bis themed window for bis guild so i can copy and paste and not have
-- to write out commands, also the warning can get lost easy in the chat, better to make them a pop
-- up in the window where they can confirm with a button".
--
-- The second half is the safety one. A caution printed into chat competes with loot rolls and zone
-- changes and scrolls away while you read it. A warning you must press a button to get past cannot
-- scroll away - and the press is a deliberate act rather than something that happened above the
-- thing you copied.
--=============================================================================
H.section("the window, and the warning you cannot scroll past")
do
    local U = NS.U
    H.ok(U ~= nil, "there is a window")
    P.SetLogs("C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs")
    U.agreed, U.hash = nil, nil

    local f = U.Build()
    H.ok(f ~= nil, "it builds")
    U.Refresh()

    -- THE ONE THAT MATTERS: the command must not be anywhere a player can take it from until the
    -- warning has been answered. Showing it greyed, or beside the warning, is a warning you get
    -- past by looking slightly to the left.
    H.eq(f.cmd:GetText(), "", "the command is EMPTY until the warning is answered")
    H.ok(f.warn:IsShown(), "and the warning is over the top of it")

    -- press the button
    f.warn.__ok = nil
    U.agreed = true
    U.Refresh()
    H.ok(f.warn:IsShown() == false, "answering it puts the warning away")
    H.ok(f.cmd:GetText():find("logreport.ps1", 1, true) ~= nil,
         "and only THEN is the command there", f.cmd:GetText())
    H.ok(f.cmd:GetText():find("_anniversary_\\Logs", 1, true) ~= nil,
         "with the paths already filled in - nothing to type")
    -- the command box never had the prompt in its text; a test so it never gains one
    H.ok(f.cmd:GetText():find("PS>", 1, true) == nil,
         "and no prompt in the copyable text here either", f.cmd:GetText())
    H.eq(f.prompt:GetText(), "PS>", "the prompt beside it is a label")

    -- THE HASH CHECK LIVES INSIDE THE WARNING, and types itself out. Arn's screenshot, 5 Oct: it
    -- was a box on the window BEHIND, so pressing the button printed it straight through the
    -- warning's own words - the "one bar, one label" shape, in a new place.
    H.eq(f.hashLine:GetText(), "", "the hash check is not shown until asked for")
    U.hash = true
    U.Refresh()
    H.ok(U.typeTarget and U.typeTarget:find("Get-FileHash", 1, true) ~= nil,
         "asked for, it is there", tostring(U.typeTarget))
    H.ok(U.typeTarget:find(P.ScriptPath(), 1, true) ~= nil,
         "and checks the same file the command runs")
    -- THE PROMPT IS A LABEL, NOT PART OF THE TEXT (5 Oct 2026). It used to be inside the copied
    -- string, so pasting into PowerShell gave:
    --
    --     PS> : The term 'PS>' is not recognized as the name of a cmdlet
    --
    -- Whatever is in that box is what somebody runs. A decoration that travels with the thing being
    -- copied is not a decoration, it is a bug with a font.
    H.ok(U.typeTarget:find("PS>", 1, true) == nil,
         "the prompt is NOT in the copyable text", U.typeTarget)
    H.ok(U.typeTarget:match("^Get%-FileHash") ~= nil,
         "the line starts with the command itself", U.typeTarget)
    H.eq(f.hashPrompt:GetText(), "PS>", "the prompt is a label beside it, so it still reads as a shell")


    -- it ARRIVES a character at a time rather than appearing
    H.ok(#f.hashLine:GetText() < #U.typeTarget, "it starts unfinished")
    U.Type(0.2)
    local part = f.hashLine:GetText()
    H.ok(#part > 0 and #part < #U.typeTarget, "and fills in", part)
    H.ok(part:sub(-1) == "_", "with a cursor on the end while it types", part)
    U.Type(10)
    H.eq(f.hashLine:GetText(), U.typeTarget, "until it is all there, with no cursor left on it")

    -- A LINE YOU CANNOT TAKE IS A DEAD END (5 Oct 2026). Arn, looking at exactly this: "what do i
    -- do with this". It was a FontString - readable, unselectable - and it said nothing about
    -- itself. Both halves were the bug.
    H.ok(f.hashLine.HighlightText ~= nil, "the hash line can be selected, so it can be copied")
    H.ok(f.hashLine._scripts.OnMouseUp ~= nil, "clicking it does something")
    H.ok(f.hashWhat:GetText():find("PowerShell", 1, true) ~= nil,
         "and it SAYS what to do with it", f.hashWhat:GetText())
    H.ok(f.hashWhat:GetText():find("CurseForge", 1, true) ~= nil,
         "including the only comparison that counts")

    -- ONE CLICK COPIES IT (5 Oct 2026). Arn: "when i click that blue part i should not have to
    -- select and copy when i click it should copy to clipboard with a message saying copied".
    --
    -- I nearly said addons cannot reach the clipboard, which is what it has always been - this
    -- client has CopyToClipboard, and Attune already calls it. The mock is the client's shape: a
    -- plain global that takes the text.
    -- THE CLIPBOARD IS PROTECTED, AND BEING IN THE CENSUS DID NOT MEAN WE COULD USE IT (5 Oct
    -- 2026). CopyToClipboard is on both baselines, the fence passed, and the client answered:
    --
    --   [ADDON_ACTION_FORBIDDEN] AddOn 'BiSGuild' tried to call the protected function 'UNKNOWN()'
    --
    -- The fence proves a NAME exists. It says nothing about permission.
    --
    -- And the guard written for this could not work: a pcall around a forbidden call returns CLEAN.
    -- The refusal arrives later as an event, so the window said "copied" while nothing had been,
    -- and the player got a red error on top. Measured on 3 Oct, written down, not applied.
    do
        -- a client that HAS the call must still not be called: the suite fails if anything reaches
        -- for it, which is the only way this stays out
        local reached = false
        local realCopy = _G.CopyToClipboard
        _G.CopyToClipboard = function() reached = true end

        U.TypeOut(U.typeTarget)
        f.hashLine._scripts.OnMouseUp(f.hashLine)
        H.eq(f.hashLine:GetText(), U.typeTarget, "clicking it finishes the typing at once")
        H.eq(reached, false, "and NEVER calls the protected clipboard function")
        H.ok(f.flash:GetText():find("Ctrl+C", 1, true) ~= nil,
             "it says which key to press instead", f.flash:GetText())
        H.ok(f.flash:GetText():find("copied", 1, true) == nil,
             "and never claims it copied, because it did not")

        f.cmd._scripts.OnMouseUp(f.cmd)
        H.eq(reached, false, "the command box does not reach for it either")

        _G.CopyToClipboard = realCopy
    end

    -- A FINISHED ANIMATION MUST STOP TOUCHING ITS TEXT (5 Oct 2026). Arn: "i cant select it it
    -- shows selected for a split second and then unselects. maybe our blinking _". Right about the
    -- cause, wrong about which part: the typewriter ran every frame and re-set the same finished
    -- string forever, and SetText on an EditBox CLEARS THE SELECTION - so the highlight the click
    -- put there was gone a frame later.
    --
    -- An animation that keeps running after it has finished is not idle; it is holding the thing it
    -- drew.
    do
        local sets = 0
        local realSet = f.hashLine.SetText
        f.hashLine.SetText = function(self, t) sets = sets + 1 return realSet(self, t) end

        U.TypeOut("PS> a line to finish")
        U.Type(10)                      -- finished
        local afterFinish = sets
        U.Type(0.1) U.Type(0.1) U.Type(0.1)
        H.eq(sets, afterFinish, "once typed, more ticks do not touch the text at all")

        -- and a NEW line must still be written even if the cache is warm
        U.TypeOut("PS> a different line")
        U.Type(10)
        H.ok(sets > afterFinish, "but a new line is still typed out")
        H.eq(f.hashLine:GetText(), "PS> a different line", "and lands in full")

        -- TypeNow must leave the cache agreeing, or the next tick rewrites and unselects again
        U.TypeOut("PS> finished by a click")
        U.TypeNow()
        local afterNow = sets
        U.Type(0.1) U.Type(0.1)
        H.eq(sets, afterNow, "a line finished by clicking is not rewritten either")

        f.hashLine.SetText = realSet
    end

    -- NOTHING MAY PRINT THROUGH THE WARNING. The box that did is empty and hidden now, and the
    -- warning sits above anything the window makes after it.
    H.eq(f.hashBox:GetText(), "", "the old box behind the warning stays empty")
    H.ok(f.warn:GetFrameLevel() > f:GetFrameLevel(),
         "and the warning is above the window, so nothing can draw over its words")

    -- a person who wants to copy the line should never wait on a flourish
    U.TypeOut("PS> something long enough to still be typing")
    U.TypeNow()
    H.eq(f.hashLine:GetText(), U.typeTarget, "and it can be finished instantly")

    -- IT SHOULD LOOK LIKE A SHELL (5 Oct 2026). Arn: "the more we make it look like a powershell
    -- window the better blinking _ and everything". Not only taste: the box holding a command you
    -- are about to run on your own computer should NOT look like the rest of the addon, because it
    -- is not part of it.
    H.ok(f.prompt ~= nil and f.prompt:GetText() == "PS>", "there is a prompt, not a label")
    H.ok(f.caret ~= nil and f.caret:GetText() == "_", "and a cursor")
    H.ok(f.cmdWrap ~= nil and f.cmdWrap._scripts.OnUpdate ~= nil, "which is driven by a ticker")

    -- the blink: half a second lit, half dark, at the rate the house console uses so two BiS
    -- windows open together do not blink against each other
    local tick = f.cmdWrap._scripts.OnUpdate
    f.cmdWrap.t = 0
    tick(f.cmdWrap, 0.1)
    local lit = f.caret:GetAlpha()
    tick(f.cmdWrap, 0.5)
    local dark = f.caret:GetAlpha()
    H.ok(lit == 1 and dark == 0, "the cursor blinks",
         tostring(lit) .. "/" .. tostring(dark))
    tick(f.cmdWrap, 0.5)
    H.eq(f.caret:GetAlpha(), 1, "and comes back - it is a blink, not a fade-out")

    -- ESCAPE CLOSES IT, AND THERE IS A WAY BACK (5 Oct 2026). Arn: "also no way to go back from
    -- this screen and esc does not close this window". Pressing "I understand" was ONE-WAY, so the
    -- warning and the hash check - the only safety on the page - could be read once per session and
    -- never again.
    H.ok(f._scripts.OnKeyDown ~= nil, "the window handles keys itself")
    U.Show()
    f._scripts.OnKeyDown(f, "ESCAPE")
    H.eq(f:IsShown(), false, "escape closes it")
    U.Show()
    f._scripts.OnKeyDown(f, "A")
    H.eq(f:IsShown(), true, "and any other key is left alone, so typing still reaches chat")

    U.agreed = true
    U.Refresh()
    H.ok(f.back:IsShown(), "once past the warning there is a way back to it")
    f.back._scripts.OnClick(f.back)
    H.ok(f.warn:IsShown(), "and it goes back")
    H.eq(f.cmd:GetText(), "", "with the command put away again")
    H.ok(f.back:IsShown() == false, "and no button back to where you already are")

    -- A DECISION IS NOT REMEMBERED. Running a script is a decision, and one made last Tuesday is
    -- not one made now - so a fresh session puts the warning back.
    U.agreed, U.hash = nil, nil
    U.Refresh()
    H.ok(f.warn:IsShown(), "a new session asks again")
    H.eq(f.cmd:GetText(), "", "and the command is gone again with it")

    -- no logs folder: the window says so rather than offering an empty command
    _G.BiSGuildDB.logs = nil
    U.agreed = true
    U.Refresh()
    H.eq(f.cmd:GetText(), "", "with no logs folder there is no command to copy")
    P.SetLogs("C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs")
    U.agreed, U.hash = nil, nil
end

H.section("the warning, and the fingerprint")
do
    -- Arn, 4 Oct: "we need a big warning that you are about to run a powershell make sure no one
    -- sent you this copy". "Paste this into PowerShell" is how people get robbed, and nothing in
    -- this addon can tell a good script from a bad one - so the warning is not optional decoration,
    -- it is the feature.
    H.ok(type(P.SCRIPT_SHA) == "string", "the shipped script's hash is carried in the addon")
    H.eq(#P.SCRIPT_SHA, 64, "a SHA-256 is 64 characters", tostring(#P.SCRIPT_SHA))
    H.ok(P.SCRIPT_SHA:match("^%x+$") ~= nil, "and nothing but hex")

    -- AND IT IS THE HASH OF THE SCRIPT WE ACTUALLY SHIP (5 Oct 2026). It was not: Arn ran the check,
    -- got BBFE79CF..., and the window said 64E58A59.... The one number on that page whose entire job
    -- is to match did not match, which is worse than having no check at all - a player who compares
    -- and sees a mismatch concludes they have been given a doctored addon.
    --
    -- "Lua 5.1 cannot compute SHA-256" was why this was never enforced, and it was simply untrue:
    -- no bitwise operators, so the 32-bit work is arithmetic. dev/sha256.lua, checked against the
    -- published NIST vectors every run, because a hash written from memory and never verified is
    -- precisely the thing that looks right and is not. (Mine was wrong the first time: `a * 2^(32-n)`
    -- overflows a double. The vectors caught it in one run.)
    do
        local sha = dofile(HERE .. "/sha256.lua")
        H.eq(sha(""):lower(), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
             "the hasher agrees with the published answer for an empty file")
        H.eq(sha("abc"):lower(), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
             "and for \"abc\"")

        local fh = io.open(HERE .. "/../Tools/logreport.ps1", "rb")
        H.ok(fh ~= nil, "the shipped script is where the addon says it is")
        if fh then
            local body = fh:read("*a")
            fh:close()
            H.eq(sha(body):upper(), P.SCRIPT_SHA:upper(),
                 "and P.SCRIPT_SHA is the hash of it - run Tools\\stamp.ps1 if this is red")
        end
    end

    P.SetLogs("C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs")
    local before = #said
    _G.SlashCmdList.BISGUILD("script")
    local out = table.concat(said, "\n", before + 1, #said)

    H.ok(out:find("PowerShell", 1, true) ~= nil, "it says the word PowerShell")
    H.ok(out:find("anything you can do", 1, true) ~= nil, "and what that means")
    H.ok(out:find("do not run", 1, true) ~= nil, "and says not to run a copy somebody sent you")
    H.ok(out:find("CurseForge", 1, true) ~= nil, "and where a trustworthy copy comes from")
    H.ok(out:find("Get-FileHash", 1, true) ~= nil, "it gives the command to check the file")
    H.ok(out:find(P.SCRIPT_SHA, 1, true) ~= nil, "and shows what this copy claims")

    -- ARN FOUND THE HOLE (4 Oct): "won't someone that steals the zip can just write code to put up
    -- whatever hash is the most correct tho?" Yes - whoever changes the script changes this
    -- constant with it, and then both ends of the check agree. A check an attacker controls both
    -- ends of is WORSE than none, because it manufactures confidence. The addon must say so.
    H.ok(out:find("proves nothing on its own", 1, true) ~= nil,
         "and says plainly that the two agreeing proves nothing on its own", out)
    H.ok(out:find("faked number here too", 1, true) ~= nil,
         "because a faked addon would fake this number as well")

    -- THE WARNING MUST COME FIRST. A caution printed under the command is one people scroll past
    -- having already copied the line.
    local warnAt = out:find("PowerShell", 1, true)
    local cmdAt = out:find("%-ExecutionPolicy")
    H.ok(warnAt and cmdAt and warnAt < cmdAt, "and all of it comes BEFORE the command itself")

    -- the file it tells you to hash must be the file the command runs
    local script = P.ScriptPath()
    H.ok(script and out:find(script, 1, true) ~= nil,
         "the file to check is the same path the command runs", tostring(script))
    _G.BiSGuildDB.logs = nil
end

H.section("told where the logs are, once")
do
    _G.BiSGuildDB.logs = nil
    H.eq(P.Logs(), nil, "nothing known to start with")
    H.eq(P.Command(), nil, "and no command can be built")

    H.eq(P.SetLogs("C:\\Program Files (x86)\\World of Warcraft\\_anniversary_"), nil,
         "the WoW folder is refused - it is the Logs folder we want")
    H.eq(P.SetLogs(""), nil, "and so is nothing")

    local set = P.SetLogs("C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs")
    H.ok(set ~= nil, "the Logs folder is taken")

    -- A TRAILING SLASH WOULD MOVE THE WOW FOLDER UP A LEVEL, and the command would point at a
    -- folder with no addon in it. Pasted paths carry one often.
    P.SetLogs("C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs\\")
    H.eq(P.Logs(), "C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs",
         "a trailing slash is trimmed")
    -- and so are the quotes Windows adds when you copy a path
    P.SetLogs('"C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs"')
    H.eq(P.Logs(), "C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs",
         "and the quotes Windows wraps a copied path in")

    local cmd = P.Command()
    H.ok(cmd:find("logreport.ps1", 1, true) ~= nil, "the command names the script", cmd)
    H.ok(cmd:find("AddOns\\BiSGuild\\Tools", 1, true) ~= nil,
         "and finds the addon from the logs path alone - one answer reaches everything")
    H.ok(cmd:find("_anniversary_\\Logs", 1, true) ~= nil, "and passes the logs folder to it")
    H.ok(cmd:find("_anniversary_\\Interface", 1, true) ~= nil,
         "the script sits beside Logs in the SAME client folder, not a level up")

    -- A SHALLOW PATH STILL WORKS (5 Oct 2026). Arn set `x:\logs`, was told "logs folder
    -- remembered", and then /bisg script said "tell me where your logs are first" - the derivation
    -- went up TWO levels and re-appended the flavour, so anything shallower matched nothing and the
    -- addon denied knowing a folder it had just confirmed. Logs and Interface are siblings; one
    -- level is the whole answer.
    P.SetLogs("x:\\logs")
    H.eq(P.Logs(), "x:\\logs", "a short path is remembered")
    local short = P.ScriptPath()
    H.ok(short ~= nil, "and the script path still resolves from it", tostring(short))
    H.eq(short, "x:\\Interface\\AddOns\\BiSGuild\\Tools\\logreport.ps1",
         "one level up, then Interface", tostring(short))
    H.ok(P.Command() ~= nil, "so the command can be built")

    -- and when it genuinely cannot be worked out, it must not say "tell me where your logs are" at
    -- somebody who just told it
    _G.BiSGuildDB.logs = "Logs"
    local before2 = #said
    _G.SlashCmdList.BISGUILD("script")
    local out2 = table.concat(said, "\n", before2 + 1, #said)
    H.ok(out2:find("cannot work out where WoW is", 1, true) ~= nil,
         "a folder it cannot use is said to BE a folder it cannot use", out2)
    H.ok(out2:find("tell me where your logs are first", 1, true) == nil,
         "and not called missing when it was given")

    P.SetLogs("C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs")

    _G.SlashCmdList.BISGUILD("script")
    H.ok(said[#said - 1]:find("powershell", 1, true) ~= nil
         or said[#said - 2]:find("powershell", 1, true) ~= nil, "/bisg script prints it")

    _G.BiSGuildDB.logs = nil
    _G.SlashCmdList.BISGUILD("script")
    H.ok(said[#said]:find("/bisg logs", 1, true) ~= nil,
         "and asks for the folder first when it does not know", said[#said])
end

H.section("a report that was written")
do
    -- exactly the shape logreport.py writes
    _G.BiSGuildReport = {
        written = 1791182045, kills = 2, nights = 7, zones = "Illidan Stormrage",
        rows = {
            { name = "Belbearr", attend = 100, consumes = 0 },
            { name = "Kumlust", attend = 100, consumes = 100 },
            { name = "Interrup", attend = 50, consumes = 100 },
        },
    }
    H.ok(P.Report() ~= nil, "the report is read")
    H.eq(P.Of("Kumlust").consumes, 100, "one person's numbers come back")
    H.eq(P.Of("NotInRaid"), nil, "somebody not in it has none")

    local rows = P.Rows()
    H.eq(rows[1].name, "Kumlust", "best attendance first")
    H.eq(rows[2].name, "Belbearr", "a tie on attendance breaks on consumes, best first")
    H.eq(rows[3].name, "Interrup", "then lower attendance, however good their consumes")

    local before = #said
    _G.SlashCmdList.BISGUILD("report")
    local printed = table.concat(said, "\n", before + 1, #said)
    H.ok(printed:find("Kumlust", 1, true) ~= nil, "/bisg report prints the people in it")
    H.ok(printed:find("Illidan Stormrage", 1, true) ~= nil, "and says which bosses it came from")

    -- A PERCENTAGE NEEDS ITS DENOMINATOR ON SCREEN (5 Oct 2026). Arn asked how anyone keeps track
    -- of attendance over time - and the answer only means something if the window says how many
    -- nights it is over. 100% of one night is not a record, and somebody will argue with it.
    NS.U.Show()
    local shown = NS.U.frame.report:GetText()
    H.ok(shown:find("7 raid night", 1, true) ~= nil,
         "the window says how many nights the numbers are over", shown)
    NS.U.Hide()
    H.ok(printed:find("100%", 1, true) ~= nil, "with the percentages")

    -- a half-written or hand-mangled file must not take the addon down with it
    _G.BiSGuildReport = { written = 1, kills = 1 }
    H.eq(P.Report(), nil, "a report with no rows is no report")
    _G.BiSGuildReport = "not a table"
    H.eq(P.Report(), nil, "and neither is something that is not a table")
    _G.BiSGuildReport = nil
end

_G.UnitName = realUnitName

H.report()
