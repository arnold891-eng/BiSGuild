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
H.eq(_G.LibBiSComm.MINOR, 12, "LibBiSComm minor 12")
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

--=============================================================================
-- DOES EVERY LABEL FIT ITS WINDOW (6 Oct 2026, ported from BiSTools). Arn found labels running out
-- of a BiSTools window with that suite green, and asked for "a check for cut offs or overflows that
-- happens often". Every shown label inside the window is measured where it actually STARTS -
-- following what it is pinned to: the window's edge, a frame, another label - and must end inside.
--
-- WIDTH, CALIBRATED ON THE CLIENT, NOT GUESSED: capitals and digits 0.75 px per point, lowercase
-- 0.55, spaces and punctuation 0.3 (BiSTools, from Arn's screenshots). Inline |T..:w:h|t textures
-- take their width, colour escapes none. The mock's own GetStringWidth (0.6 flat) stays as it is:
-- BiSTheme's T.Fit trims by it, and changing it changes what the addon draws.
--=============================================================================
local function lineWidth(t, size)
    local tex = 0
    t = t:gsub("|T[^|]-:(%d+):%d+[^|]*|t", function(w) tex = tex + tonumber(w) return "" end)
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local px = 0
    for ch in t:gmatch(".") do
        if ch:match("[%u%d]") then px = px + 0.75 elseif ch:match("%l") then px = px + 0.55 else px = px + 0.3 end
    end
    return px * size + tex
end
-- A "\n" is a new line, not a character: the widest LINE is the label's width. (BiSTools has no
-- multi-line labels; this window's warning is one.)
local function widest(text, size)
    local best, bestLine = 0, ""
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        local w = lineWidth(line, size)
        if w > best then best, bestLine = w, line end
    end
    return best, bestLine
end
local function hasL(p) return p:find("LEFT") ~= nil end
local function hasR(p) return p:find("RIGHT") ~= nil end

-- left edge and width of any region, in px from the window's left; nil when it cannot be followed.
-- FRAMES ARE FOLLOWED, not assumed to span the window: the warning hangs off two corners, a button
-- off one corner and its own size. A frame with no anchor at all spans the window, as in BiSTools.
local box
local function edgeX(rel, relPoint, root, depth)
    local l, w = box(rel, root, depth + 1)
    if not l then return nil end
    if hasL(relPoint) then return l elseif hasR(relPoint) then return l + w end
    return l + w / 2
end
box = function(r, root, depth)
    depth = depth or 0
    if r == root then return 0, root._w end
    if r == nil or r == _G.UIParent or depth > 10 then return nil end
    if r._all then return box(r._parent, root, depth + 1) end
    local pts = r._points
    if not pts or #pts == 0 then
        if r._isLabel or r._isTexture then return nil end
        return 0, root._w
    end
    local lp, rp, mid
    for _, p in ipairs(pts) do
        if hasL(p.point) then lp = lp or p elseif hasR(p.point) then rp = rp or p else mid = mid or p end
    end
    local L, R
    if lp then L = edgeX(lp.rel or r._parent, lp.relPoint, root, depth) if not L then return nil end L = L + lp.x end
    if rp then R = edgeX(rp.rel or r._parent, rp.relPoint, root, depth) if not R then return nil end R = R + rp.x end
    -- ANCHORED BOTH SIDES = BOUNDED: the anchors set the width, not the text
    if L and R then return L, R - L end
    local w = r._w
    if r._isLabel and not w then w = (widest(r._text, r._size or 9)) end
    w = w or 0
    if L then return L, w end
    if R then return R - w, w end
    local c = edgeX(mid.rel or r._parent, mid.relPoint, root, depth)
    if not c then return nil end
    return c + mid.x - w / 2, w
end
local function insideShown(r, root)
    if r._shown == false then return false end
    local p = r._parent
    while p do
        if p._shown == false then return false end
        if p == root then return true end
        p = p._parent
    end
    return false
end
local function plain(t) return (tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
-- the font a button's own label draws in: UIPanelButtonTemplate's NormalFont is GameFontNormal
local BUTTON_SIZE = { UIPanelButtonTemplate = H.FONT_SIZE.GameFontNormal }

local function fitsIn(root, what)
    local width, bad, measured = root._w, {}, 0
    for _, fs in ipairs(H.labels) do
        if fs._text ~= "" and insideShown(fs, root) then
            local l, span = box(fs, root)
            if l then
                measured = measured + 1
                local need, line = widest(fs._text, fs._size or 9)
                -- A LABEL PINNED LEFT AND RIGHT (or given a width) is bounded by its span. The code
                -- breaks those lines itself with "\n" and never asks for word wrap, so a line wider
                -- than the span is one the client wraps or clips where nobody planned it: measured.
                local pl, pr = false, false
                for _, p in ipairs(fs._points or {}) do
                    if hasL(p.point) then pl = true elseif hasR(p.point) then pr = true end
                end
                local bounded = fs._w ~= nil or (pl and pr)
                if bounded and need > span + 1 then
                    bad[#bad + 1] = ("%q needs %d px, its span is %d"):format(plain(line), need, span)
                elseif l < -1 or l + span > width + 1 then
                    bad[#bad + 1] = ("%q needs %d px from %d, the window is %d"):format(plain(line), need, l, width)
                end
            end
        end
    end
    -- A BUTTON'S WORDS are a label too: centred on the button, and must fit the button
    for _, b in ipairs(H.frames) do
        local size = BUTTON_SIZE[b._template]
        if size and b._text ~= "" and insideShown(b, root) then
            local l, bw = box(b, root)
            if l then
                measured = measured + 1
                local need = lineWidth(b._text, size)
                if need > bw + 1 then
                    bad[#bad + 1] = ("button %q needs %d px, the button is %d"):format(plain(b._text), need, bw)
                elseif l < -1 or l + bw > width + 1 then
                    bad[#bad + 1] = ("button %q sits %d..%d, the window is %d"):format(plain(b._text), l, l + bw, width)
                end
            end
        end
    end
    H.ok(measured > 0, what .. ": the fit check measured something (a check that sees nothing proves nothing)")
    H.ok(#bad == 0, what .. ": every label fits - " .. table.concat(bad, "; "))
    H.say(("  (fit) %s: %d label(s) measured"):format(what, measured))
    return measured
end

H.section("every label fits the window")
do
    local U = NS.U
    local f = U.Build()
    local tick = f.cmdWrap._scripts.OnUpdate
    local function show()
        U.Show()
        -- the console fades its words in on the ticker, by the CLOCK: run a second of it, as the
        -- client would before anybody reads the window
        for _ = 1, 4 do H.clock = H.clock + 0.3 tick(f.cmdWrap, 0.3) end
        U.TypeNow()
    end
    P.SetLogs("C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs")
    _G.BiSGuildReport = nil

    -- empty: the warning, nothing answered, no report
    U.agreed, U.hash = nil, nil
    show()
    fitsIn(f, "the warning, fresh")

    -- the warning with the hash check typed out, and the "press Ctrl+C" notice from clicking it
    U.hash = true
    show()
    f.hashLine._scripts.OnMouseUp(f.hashLine)
    fitsIn(f, "the warning with the hash check open")

    -- past the warning, no report yet
    U.agreed, U.hash = true, nil
    show()
    fitsIn(f, "the command, no report yet")

    -- past the warning with no logs folder: the header note asks for it
    _G.BiSGuildDB.logs = nil
    show()
    fitsIn(f, "the command, no logs folder")
    P.SetLogs("C:\\Program Files (x86)\\World of Warcraft\\_anniversary_\\Logs")

    -- POPULATED, WITH THE LONGEST REAL THINGS IT WILL SHOW. A full Black Temple night is nine
    -- encounters, and logreport writes them all into `zones` (ENCOUNTER_START's names, sorted).
    -- Forever names carry a surname ("Name Surname"); a first name may be 12 letters.
    _G.BiSGuildReport = {
        written = 1791182045, kills = 9, nights = 12,
        zones = "Gurtogg Bloodboil, High Warlord Naj'entus, Illidan Stormrage, Mother Shahraz, "
             .. "Reliquary of Souls, Shade of Akama, Supremus, Teron Gorefiend, The Illidari Council",
        rows = {},
    }
    local names = { "Kumlustrande Stormwhisper", "Belbearr Ironhide", "Interrup Moonfallow",
                    "Hrsalinge Duskbringer", "Overlordwyn Blackthorne", "Kurki Saltmarsh",
                    "Thundermaul Highcrest", "Feathermoon Wildmantle", "Ashenvalea Grimstone",
                    "Dreamscythe Vandermolen" }
    for i, n in ipairs(names) do
        _G.BiSGuildReport.rows[i] = { name = n, attend = 100 - i * 7, consumes = 100 - i * 9 }
    end
    show()
    fitsIn(f, "the report, a full Black Temple night, long Forever names")

    -- the bosses did not vanish: they moved off the line and into the hover
    H.ok(f.lastHit:IsShown(), "with a report, the header lines can be hovered")
    do
        local tip, real = {}, _G.GameTooltip
        _G.GameTooltip = setmetatable({
            SetText = function(_, t) tip[#tip + 1] = t end,
            AddLine = function(_, t) tip[#tip + 1] = t end,
        }, { __index = real })
        f.lastHit._scripts.OnEnter(f.lastHit)
        _G.GameTooltip = real
        local all = table.concat(tip, "\n")
        H.eq(#tip, 10, "the hover says the kills, then one line per boss", all)
        H.ok(all:find("High Warlord Naj'entus", 1, true) and all:find("The Illidari Council", 1, true),
             "every boss is named there", all)
    end
    _G.BiSGuildReport = nil
    show()
    H.ok(not f.lastHit:IsShown(), "and with no report there is nothing to hover")

    U.Hide()
    U.agreed, U.hash = nil, nil
    _G.BiSGuildReport = nil
end

--=============================================================================
-- THE GUILD'S RECORD (16 Oct 2026). Arn: "All this data we are getting is from my computer, how are
-- other people going to get all this info, so if I miss one raid night what stops the addon from
-- updating". Every member keeps the nights; officers share them over the guild channel.
--=============================================================================
local function deq(a, b, skip)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not (skip and skip[k]) and not deq(v, b[k]) then return false end end
    for k in pairs(b) do if not (skip and skip[k]) and a[k] == nil then return false end end
    return true
end
local function raider(present, pulls, deaths)
    return { present = present, ready = present, pulls = pulls, flask = pulls, elixir = 0, food = pulls,
             weapon = 0, weaponSeen = pulls, pots = 1, deaths = deaths or 0 }
end
local function bigNight()
    local n = { kills = 8, raiders = {}, bosses = {} }
    local names = {}
    for i = 1, 25 do
        local name = ("Raider%02d"):format(i)
        names[#names + 1] = name
        n.raiders[name] = raider(8, 11, i % 3)
    end
    for b = 1, 8 do
        n.bosses[("Boss Number %d"):format(b)] = { pulls = 2, kills = 1, best = 180000 + b, killers = names }
    end
    return n
end
local S, X = NS.S, NS.X

H.section("the record: a report folds in, the fuller copy of a date wins")
do
    _G.BiSGuildDB.record = nil
    local gear = {}
    for i = 1, 19 do gear[i] = { 1000 + i, 30, i == 5 and 0 or 7, 0, {} } end
    local report = {
        rows = {},
        nightly = {
            ["2026-10-09"] = { kills = 3, raiders = { Alice = raider(3, 4), Bob = raider(1, 2, 1) }, bosses = {} },
            ["2026-10-16"] = { kills = 2, raiders = { Alice = raider(2, 3) },
                               bosses = { ["Boss One"] = { pulls = 3, kills = 2, best = 245000, killers = { "Alice" } } } },
        },
        cards = { Alice = { gear = gear, gearDate = "2026-10-16" } },
    }
    local n, g = S.Import(report)
    H.eq(n, 2, "both nights taken in")
    H.eq(g, 1, "and Alice's gear")
    H.eq(S.Record().nights["2026-10-16"].by, "Kumlust", "a night says who imported it")
    H.eq(select(1, S.Import(report)), 0, "the same report twice changes nothing")

    -- Bob was there for 1 of 3 kills on the 9th: not half, so not his night
    local cards = S.Cards()
    H.ok(deq(cards.Alice.attended, { "2026-10-09", "2026-10-16" }), "Alice earned both nights")
    H.ok(deq(cards.Bob.attended, {}), "Bob, at one kill of three, earned neither")
    H.eq(cards.Alice.last.date, "2026-10-16", "her latest night's numbers")
    H.eq(cards.Bob.deaths, 1, "deaths add up over the record")
    H.eq(#cards.Alice.issues, 1, "her unenchanted chest is the one red flag")
    H.eq(cards.Alice.issues[1].slot, "chest", "on the chest")
    H.eq(S.Bosses()["Boss One"].best, 245000, "the boss page has its fastest kill")

    -- a thinner copy of the 16th (somebody's log started late) does not replace a fuller one
    H.ok(not S.Put("2026-10-16", { kills = 1, raiders = { Alice = raider(1, 1) }, bosses = {} }, "Late"),
         "a thinner copy is refused")
    H.ok(S.Put("2026-10-16", { kills = 2, raiders = { Alice = raider(2, 3), Cara = raider(2, 3) }, bosses = {} }, "Full"),
         "a fuller copy wins")
    H.ok(not S.Put("2026-10-16", { kills = 2, raiders = { Alice = raider(2, 3), Dan = raider(2, 3) }, bosses = {} }, "Tie"),
         "an equal copy does not flip it back and forth")
    H.ok(not S.Put("16 Oct", { kills = 1, raiders = {} }), "a date that is not a date is refused")

    H.ok(not S.PutGear("Alice", "2026-10-09", gear), "older gear does not replace newer")

    -- Init clears the old collector's `nights` on every load; the record is under another name
    fire("ADDON_LOADED", "BiSGuild")
    H.eq(#S.Dates(), 2, "a reload keeps the record")
end

H.section("a night on the wire: small, and the same night after")
do
    local night = bigNight()
    local text = X.EncodeNight(night)
    local parts = math.ceil(#text / X.CHUNK)
    H.say(("   a 25-raider, 8-boss night: %d characters, %d parts"):format(#text, parts))
    H.ok(parts <= 12, "a full raid night is a dozen parts at most: " .. parts)
    H.ok(deq(X.DecodeNight(text), night), "and decodes to the same night")
    H.eq(X.DecodeNight("garbage"), nil, "garbage decodes to nothing")
    H.eq(X.DecodeNight("1#Bob:1.2#"), nil, "a raider short of numbers is refused")

    local gear = {}
    for i = 1, 19 do gear[i] = i == 18 and { 0, 0, 0, 0, {} } or { 30000 + i, 66, 2500 + i, i == 16 and 2623 or 0, i == 1 and { 4001, 4002 } or {} } end
    local gtext = X.EncodeGear(gear)
    H.ok(#gtext <= 2 * X.CHUNK, "a raider's gear is two parts at most: " .. #gtext)
    H.ok(deq(X.DecodeGear(gtext), gear), "and decodes to the same gear")
end

H.section("sharing: officers answer, members are not believed")
do
    local ROSTER = { { "Kumlust-Dreamscythe", 1 }, { "Bigboss", 0 }, { "Memberguy", 4 } }
    local realNum, realInfo = _G.GetNumGuildMembers, _G.GetGuildRosterInfo
    _G.GetNumGuildMembers = function() return #ROSTER end
    _G.GetGuildRosterInfo = function(i) local r = ROSTER[i] return r[1], "rank", r[2] end
    lib._guildDirty = true
    X._ranksDirty = true

    H.ok(X.IsOfficer("Kumlust") and X.IsOfficer("Bigboss"), "ranks 0 and 1 are officers")
    H.ok(not X.IsOfficer("Memberguy") and not X.IsOfficer("Stranger"), "a member and a stranger are not")
    -- a guild laid out differently says so once, in the Guild Information text every member reads
    _G.GetGuildInfoText = function() return "Raids Tue/Thu 8pm\nBiSGuild officers: 4\nBe nice" end
    H.eq(X.OfficerRank(), 4, "the guild's info text moves the cutoff")
    H.ok(X.IsOfficer("Memberguy"), "and rank 4 counts then")
    _G.GetGuildInfoText = function() return "no line here" end
    H.eq(X.OfficerRank(), 1, "without the line: the guild master and the rank under")
    _G.GetGuildInfoText = nil

    local function drain()
        for _ = 1, 40 do H.clock = H.clock + 2 H.RunTimers() end
    end
    local function ours(cmd)
        local out = {}
        for _, w in ipairs(H.wire) do
            if w.channel == "GUILD" and w.msg:find("|GLOG|" .. cmd .. "|", 1, true) then out[#out + 1] = w end
        end
        return out
    end
    local function hear(sender, w) lib:OnMessage("BiS", w.msg, "GUILD", sender) end

    drain()
    H.wire = {}
    -- an officer with nights says so; the line fits one message
    H.ok(X.Announce(), "an officer announces what they hold")
    drain()
    local have = ours("HAVE")
    H.eq(#have, 1, "in one line")
    H.ok(have[1] and have[1].msg:find("261016.2.2", 1, true), "newest first, with raiders and kills", have[1] and have[1].msg)

    -- somebody missing the 16th hears it and asks - once
    local mine = S.Record()
    _G.BiSGuildDB.record = { nights = {}, gear = {} }
    H.wire = {}
    hear("Memberguy", have[1])
    drain()
    H.eq(#ours("WANT"), 0, "a member's HAVE is not worth asking about")
    hear("Bigboss", have[1])
    drain()
    local want = ours("WANT")
    H.eq(#want, 1, "an officer's HAVE: the missing night is asked for, once")
    H.ok(want[1] and want[1].msg:find("2026-10-16", 1, true), "the newest missing date first")

    -- the officer answers: a part every two seconds, every part under the client's limit
    _G.BiSGuildDB.record = mine
    H.wire = {}
    X.handlers.WANT("Memberguy", "2026-10-16")
    drain()
    local parts = ours("NIGHT")
    H.ok(#parts >= 1, "the officer answers the WANT: " .. #parts .. " part(s)")
    local long = 0
    for _, w in ipairs(parts) do long = math.max(long, #w.msg) end
    H.ok(long <= 250, "every part fits the 255-byte limit: " .. long)

    -- the parts, heard by a member with nothing: the same night arrives
    local sent = mine.nights["2026-10-16"]
    _G.BiSGuildDB.record = { nights = {}, gear = {} }
    for _, w in ipairs(parts) do hear("Memberguy", w) end
    H.eq(S.Record().nights["2026-10-16"], nil, "from a member it is not taken in")
    for _, w in ipairs(parts) do hear("Bigboss", w) end
    H.ok(deq(S.Record().nights["2026-10-16"], sent, { by = true }), "from an officer it arrives whole")
    H.eq(S.Record().nights["2026-10-16"].by, "Bigboss", "and says who sent it")

    -- ONE ANSWER, NOT TEN: an officer who hears another officer's first part stands down
    _G.BiSGuildDB.record = mine
    H.wire = {}
    X.handlers.WANT("Memberguy", "2026-10-16")
    hear("Bigboss", parts[1])
    drain()
    H.eq(#ours("NIGHT"), 0, "another officer already answering: we stay quiet")

    -- a member never answers, even holding the night
    ROSTER[1][2] = 4
    X._ranksDirty = true
    H.wire = {}
    X.handlers.WANT("Bigboss", "2026-10-16")
    drain()
    H.eq(#ours("NIGHT"), 0, "a member holding the night does not answer")
    H.ok(not X.Announce(), "nor announce")
    ROSTER[1][2] = 1
    X._ranksDirty = true

    -- gear: asked for by name, answered only when ours is newer
    H.wire = {}
    X.handlers.GWANT("Memberguy", "Alice", "2026-10-16")
    drain()
    H.eq(#ours("GEAR"), 0, "nothing newer than what they have: no answer")
    X.handlers.GWANT("Memberguy", "Alice", "")
    drain()
    local gparts = ours("GEAR")
    H.ok(#gparts >= 1 and #gparts <= 2, "their gear goes out in one or two parts: " .. #gparts)
    local had = mine.gear.Alice
    _G.BiSGuildDB.record = { nights = {}, gear = {} }
    for _, w in ipairs(gparts) do hear("Bigboss", w) end
    H.ok(S.Record().gear.Alice and deq(S.Record().gear.Alice.gear, had.gear), "and arrives whole")

    _G.BiSGuildDB.record = mine
    _G.GetNumGuildMembers, _G.GetGuildRosterInfo = realNum, realInfo
    lib._guildDirty = true
    X._ranksDirty = true
    H.wire = {}
end

--=============================================================================
-- THE RAIDER TERMINAL (16 Oct 2026). Arn: "type in a raider name, show all the gear they have ...
-- what their attendance is, how much they consume" and "we type in a boss name, it's like its own
-- company ticker".
--=============================================================================
H.section("the terminal: what a typed line asks for")
do
    local K = NS.K
    local cards = { Kumlust = {}, Kumlance = {}, Margo = {}, Alice = {} }
    local bosses = { ["Ragnaros"] = {}, ["Magmadar"] = {} }
    local function p(line) return { K.Parse(line, cards, bosses) } end
    H.ok(deq(p("kumlust"), { "raider", "Kumlust" }), "a bare name, any case")
    H.ok(deq(p("KUMLUST <RAIDER> GO"), { "raider", "Kumlust" }), "the Bloomberg way works too")
    H.ok(deq(p("RAGNAROS <BOSS> GO"), { "boss", "Ragnaros" }), "and for a boss")
    H.ok(deq(p("rag"), { "boss", "Ragnaros" }), "the start of a name, when only one starts so")
    H.ok(deq(p("margo"), { "raider", "Margo" }), "a name ending in 'go' is not a GO")
    H.ok(deq(p("bosses"), { "bosses" }) and deq(p("<raider> go"), { "raiders" }), "the lists by word")
    local kind, offer = K.Parse("kum", cards, bosses)
    H.eq(kind, nil, "two raiders start with kum: not a guess")
    H.ok(deq(offer, { "Kumlance", "Kumlust" }), "but both are offered", offer and table.concat(offer, ","))
    H.eq(K.Parse("ma <boss>", cards, bosses), "boss", "<boss> narrows to bosses: Magmadar, not Margo")
    H.eq(K.Clock(245000), "4:05", "a kill time reads m:ss")
    H.eq(K.Clock(0), "-", "no kill, no time")
    H.ok(math.abs(K.W / K.H - 1.43) < 0.01, "the window is the family's 1.43:1")
end

H.section("the terminal: the raider card and the boss ticker")
do
    local K = NS.K
    local saved = _G.BiSGuildDB.record
    local gear = {}
    for i = 1, 19 do gear[i] = { 1000 + i, 30, (i == 5) and 0 or 9, 0, {} } end
    gear[18] = { 0, 0, 0, 0, {} }
    _G.BiSGuildDB.record = {
        nights = {
            ["2026-10-09"] = { kills = 2, raiders = { Alice = raider(2, 3), Bob = raider(2, 3, 2) },
                               bosses = { ["Boss One"] = { pulls = 3, kills = 1, best = 250000, killers = { "Alice", "Bob" } } } },
            ["2026-10-16"] = { kills = 2, raiders = { Alice = raider(2, 2) },
                               bosses = { ["Boss One"] = { pulls = 1, kills = 1, best = 245000, killers = { "Alice" } } } },
        },
        gear = { Alice = { date = "2026-10-16", gear = gear } },
    }
    _G.GetItemInfo = function(id) if id == 1001 then return "Helm of Testing", nil, 4 end return nil end

    -- empty first: the window says what to do instead of showing blank tables
    local rec = _G.BiSGuildDB.record
    _G.BiSGuildDB.record = { nights = {}, gear = {} }
    K.page = nil
    local f = K.Show()
    H.ok(f and f:IsShown(), "the terminal opens")
    H.eq(K.page, "raiders", "it opens on the raiders")
    H.ok(f.pages.raiders.panel.hint:IsShown(), "an empty list says why")
    H.ok(f.pages.raiders.panel.hint:GetText():find("LOG", 1, true), "and where the nights come from")
    -- Arn, 16 Oct: clicking BOSSES on a fresh install did "nothing" - it must open its own page
    f.keys.bosses:Click()
    H.eq(K.page, "bosses", "the BOSSES tab opens the bosses, even empty")
    H.ok(f.pages.bosses:IsShown() and not f.pages.raiders:IsShown(), "and the page changes")
    H.ok(f.pages.bosses.panel.hint:IsShown(), "with its own why")
    _G.BiSGuildDB.record = rec

    f.keys.raiders:Click()
    H.eq(K.page, "raiders", "the RAIDERS tab")
    H.ok(not f.pages.raiders.panel.hint:IsShown(), "with nights, no hint")
    local row1 = f.pages.raiders.grid.rows[1]
    H.eq(row1.key, "Alice", "best attendance first")
    H.eq(row1.cells[2]:GetText(), "100%", "Alice made both nights")
    H.eq(f.pages.raiders.grid.rows[2].cells[2]:GetText(), "50%", "Bob one of two")
    H.ok(not f.pages.raiders.grid.rows[3]:IsShown(), "and no empty rows show")
    H.eq(row1.cells[6]:GetText(), "1 no enchant", "Alice's gear: one flag")
    H.eq(f.pages.raiders.grid.rows[2].cells[6]:GetText(), "no gear seen",
         "Bob has no gear on record: not 'clean' - nobody saw it")

    H.wire = {}
    row1:Click()
    H.eq(K.page, "raider", "clicking a row opens the card")
    H.eq(K.key, "Alice", "Alice's")
    local rc = f.pages.raider
    H.eq(rc.gear.rows[1].cells[2]:GetText(), "Helm of Testing", "the armory names the item")
    H.eq(rc.gear.rows[2].cells[2]:GetText(), "item 1002", "or says its number until the client knows it")
    H.eq(rc.gear.rows[5].cells[4]:GetText(), "no enchant", "the unenchanted chest is flagged")
    H.eq(rc.gear.rows[18].cells[2]:GetText(), "-", "an empty slot is a dash")

    -- HOVER FOR THE ITEM, ENCHANT INCLUDED (Arn: "the tooltip come out, ideally with the enchant")
    local tipped
    _G.GameTooltip = { SetOwner = function() end, Show = function() end, Hide = function() tipped = "hidden" end,
                       SetHyperlink = function(_, l) tipped = l end }
    rc.gear.rows[2]:Fire("OnEnter")
    H.eq(tipped, "item:1002:9", "hovering the neck: the game's tooltip, with her enchant in it")
    rc.gear.rows[2]:Fire("OnLeave")
    H.eq(tipped, "hidden", "and it goes away")
    tipped = nil
    rc.gear.rows[18]:Fire("OnEnter")
    H.eq(tipped, nil, "an empty slot has no tooltip")
    local linked
    _G.ChatEdit_InsertLink = function(l) linked = l end
    _G.GetItemInfo = function(id)
        if id == 1001 then return "Helm of Testing", nil, 4 end
        if id == "item:1002:9" then return "Neck", "|cff1eff00|Hitem:1002:9|h[Neck]|h|r", 2 end
    end
    _G.IsShiftKeyDown = function() return false end
    rc.gear.rows[2]:Click()
    H.eq(linked, nil, "a plain click links nothing")
    _G.IsShiftKeyDown = function() return true end
    rc.gear.rows[2]:Click()
    H.ok(linked and linked:find("item:1002:9", 1, true), "shift-click puts the link in chat", linked)
    _G.GameTooltip, _G.ChatEdit_InsertLink, _G.IsShiftKeyDown = nil, nil, nil
    _G.GetItemInfo = function(id) if id == 1001 then return "Helm of Testing", nil, 4 end return nil end
    H.ok(rc.attLine:GetText():find("2 of 2 nights", 1, true), "attendance in words", rc.attLine:GetText())
    H.ok(rc.consLines[1]:GetText():find("2 of 2 pulls", 1, true), "her flask on the latest night", rc.consLines[1]:GetText())
    H.eq(rc.lootLines[1]:GetText(), "BiS Loot has not run on this client", "no ledger: says so")
    for _ = 1, 3 do H.clock = H.clock + 2 H.RunTimers() end
    local asked = false
    for _, w in ipairs(H.wire) do if w.msg:find("|GLOG|GWANT|Alice|", 1, true) then asked = true end end
    H.ok(asked, "opening a card asks officers for newer gear")

    -- loot won, straight from BiS Loot's ledger
    _G.BiSLootDB = { lines = {
        table.concat({ "1", "Kumlust", "1", "0", "1700000000", "award", "MC", "Boss One", "1001", "Alice", "MS", "hand", "", "", "sum" }, "\t"),
        table.concat({ "1", "Kumlust", "2", "x", "1700000100", "award", "MC", "Boss One", "1003", "Bob", "MS", "hand", "", "", "sum" }, "\t"),
    } }
    K.Go("alice")
    H.ok(rc.lootLines[1]:GetText():find("Helm of Testing", 1, true), "her loot from the ledger", rc.lootLines[1]:GetText())
    H.eq(rc.lootLines[2]:GetText(), "", "and only hers")
    _G.BiSLootDB = nil

    -- the boss ticker
    K.Go("BOSS ONE <BOSS> GO")
    H.eq(K.page, "boss", "a boss name opens its page")
    local bp = f.pages.boss
    H.ok(bp.statLines[1]:GetText():find("2", 1, true), "two kills", bp.statLines[1]:GetText())
    H.ok(bp.statLines[4]:GetText():find("4:05", 1, true), "the fastest", bp.statLines[4]:GetText())
    H.eq(bp.statLines[5]:GetText(), "first kill   2026-10-09", "the first kill")
    H.eq(bp.grid.rows[1].key, "Alice", "most kills first")
    H.eq(bp.grid.rows[1].cells[2]:GetText(), "2", "Alice was there for both")
    H.ok(f.tick:GetText():find("BOSS ONE DOWN 4:05", 1, true), "the ticker carries the newest night", f.tick:GetText())

    -- a miss says what it could have meant
    K.Go("bo")
    H.ok(f.status:GetText():find("did you mean", 1, true), "a near miss offers names", f.status:GetText())

    -- THE LISTS SCROLL (Arn's first real report: 34 raiders, 27 rows, everyone after Rollsy gone)
    local keep = _G.BiSGuildDB.record.nights["2026-10-09"].raiders
    for i = 1, 40 do keep[("Zed%02d"):format(i)] = raider(1, 1) end
    f.keys.raiders:Click()
    local grid, panel = f.pages.raiders.grid, f.pages.raiders.panel
    H.ok(panel.right:GetText():find("rows 1-27 of 42", 1, true), "the corner says which rows show", panel.right:GetText())
    panel:Fire("OnMouseWheel", -1)
    H.eq(grid.offset, 3, "the wheel moves three rows")
    for _ = 1, 20 do panel:Fire("OnMouseWheel", -1) end
    H.eq(grid.offset, 15, "and stops at the last row")
    H.eq(grid.rows[27].cells[1]:GetText(), "Zed40", "the last raider is reachable")
    for _ = 1, 20 do panel:Fire("OnMouseWheel", 1) end
    H.eq(grid.offset, 0, "and back to the top")
    for i = 1, 40 do keep[("Zed%02d"):format(i)] = nil end
    K.Paint()
    H.eq(panel.right:GetText(), "2 raiders, 2 nights", "a list that fits says nothing about rows")

    -- THE LOG TAB PUTS ITS WINDOW IN FRONT, WHOLE (Arn, 16 Oct: "this windows kinda get
    -- overlapping" - the terminal's ticker drew across the log window)
    local uf = NS.U.Build()
    local raised, top = false, false
    uf.Raise = function() raised = true end
    uf.SetToplevel = function(_, v) top = v end
    f.keys.log:Click()
    H.ok(uf:IsShown() and raised and top, "the LOG tab raises the log window over the terminal")
    NS.U.Hide()
    uf.Raise, uf.SetToplevel = nil, nil

    -- NO FUNCTION KEYS (Arn: "i have stuff keybound to those keys")
    local before = K.page
    f.cmd:Fire("OnKeyDown", "F2")
    H.eq(K.page, before, "F2 does nothing here - it is the raider's keybind")
    f.keys.bosses:Click()
    H.eq(K.page, "bosses", "the tab does it")
    f.cmd:SetText("alice")
    f.cmd:Fire("OnEnterPressed")
    H.eq(K.key, "Alice", "typing a name and Enter")
    H.eq(f.cmd:GetText(), "", "and the line clears for the next one")

    -- ESC: the line gives up the keyboard first, then the window closes
    H.ok(f.cmd:HasFocus(), "the command line has the keyboard while open")
    f.cmd:Fire("OnEscapePressed")
    H.ok(not f.cmd:HasFocus(), "the first ESC hands the keyboard back")
    f:Fire("OnKeyDown", "ESCAPE")
    H.ok(not f:IsShown(), "the next closes the window")

    -- /bisg opens it; /bisg <name> opens a card
    _G.SlashCmdList.BISGUILD("")
    H.ok(f:IsShown(), "a bare /bisg opens the terminal")
    _G.SlashCmdList.BISGUILD("")
    H.ok(not f:IsShown(), "and closes it")
    _G.SlashCmdList.BISGUILD("bob")
    H.ok(f:IsShown() and K.key == "Bob", "/bisg bob opens Bob's card")
    K.Hide()

    _G.GetItemInfo = nil
    _G.BiSGuildDB.record = saved
end

-- WHAT AN OPEN WINDOW COSTS, IN CLIENT CALLS (7 Oct 2026). BiSHealing asked the client ~630,000
-- things a second and every suite was green; Arn: "make sure stuff like this does not happen".
-- The window ticks every frame while it is open (the cursor, the prompt, the typing). A second of
-- frames is held to a budget with the family's counter.
H.section("what a second of the open window costs")
do
    local Cost = dofile("../_bisdev/dev/cost.lua")
    local U = NS.U
    local f = U.Build()
    U.Show()
    local tick = f.cmdWrap._scripts.OnUpdate
    for _ = 1, 30 do H.clock = H.clock + 0.1 tick(f.cmdWrap, 0.1) end     -- settled, typed out
    local n, by = Cost.Count(function()
        for _ = 1, 60 do H.clock = H.clock + 1 / 60 tick(f.cmdWrap, 1 / 60) end
    end)
    H.say(("   cost: open window, 1 s = %d calls (%s)"):format(n, Cost.Top(by, 3)))
    H.ok(n <= 120, "a second of the open window asks the client at most two things a frame: " .. n,
         Cost.Top(by, 4))

    -- a second of the open terminal: the ticker slides one SetPoint a frame
    local K = NS.K
    local kf = K.Show("raiders")
    local tick = kf._scripts.OnUpdate
    local nk, byk = Cost.Count(function()
        for _ = 1, 60 do H.clock = H.clock + 1 / 60 tick(kf, 1 / 60) end
    end)
    H.say(("   cost: open terminal, 1 s = %d calls (%s)"):format(nk, Cost.Top(byk, 3)))
    H.ok(nk <= 120, "a second of the open terminal: at most two client calls a frame: " .. nk, Cost.Top(byk, 4))
    K.Hide()

    -- hearing a whole 25-raider night from an officer: the roster is read once, not once a part
    local text = NS.X.EncodeNight(bigNight())
    local parts, N = {}, math.ceil(#text / NS.X.CHUNK)
    for i = 1, N do parts[i] = text:sub((i - 1) * NS.X.CHUNK + 1, i * NS.X.CHUNK) end
    local saved = _G.BiSGuildDB.record
    _G.BiSGuildDB.record = { nights = {}, gear = {} }
    local realNum, realInfo = _G.GetNumGuildMembers, _G.GetGuildRosterInfo
    _G.GetNumGuildMembers = function() return 1 end
    _G.GetGuildRosterInfo = function() return "Bigboss", "rank", 0 end
    NS.X._ranksDirty = true
    local n2, by2 = Cost.Count(function()
        for i = 1, N do NS.X.handlers.NIGHT("Bigboss", "2026-10-23", i, N, parts[i]) end
    end)
    H.say(("   cost: hearing a %d-part night = %d calls (%s)"):format(N, n2, Cost.Top(by2, 3)))
    H.ok(NS.S.Record().nights["2026-10-23"] ~= nil, "the night arrived")
    H.ok(n2 <= 4 * N, "hearing a night costs a few client calls a part: " .. n2, Cost.Top(by2, 4))
    _G.BiSGuildDB.record = saved
    _G.GetNumGuildMembers, _G.GetGuildRosterInfo = realNum, realInfo
    NS.X._ranksDirty = true
end

H.report()
