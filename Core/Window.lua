--[[
  BiSGuild :: Core/Window.lua - the window, so nobody has to type a command.

  Arn, 5 Oct 2026: "give me a bis themed window for bis guild so i can copy and paste and not have
  to write out commands, also the warning can get lost easy in the chat, better to make them a pop
  up in the window where they can confirm with a button".

  THE OFFICERS' WINDOW SINCE 18 OCT 2026. Arn: "can we get rid of the fingerprint thing and just do
  a secret powershell feature just for us". Raiders read their logs in the notebook (the paste window
  below, which the terminal's LOG tab opens); this one is `/bisg window`, unadvertised. Its warning
  screen and the typed-out hash check (5-17 Oct) went with the fingerprint: the people who open it
  know where their copy came from.

  Nothing here is secure and nothing here casts: it is a text box and some labels. The command is
  an EditBox because a FontString cannot be selected - the same trick every export string in every
  addon uses, and the same one BiSMemories' journal uses for the album's path.

  The addon still cannot write a file or run anything. All this does is put the right words in
  front of the player with the paths already filled in. What runs the script is the player, in
  their own shell, having read what it is.
]]
local ADDON, ns = ...

local U = {}
ns.U = U

local W, H = 580, 400

local function T() return ns.T end

-- POWERSHELL'S OWN BLUE. Arn: "the more we make it look like a powershell window the better". The
-- colour is the first thing anybody recognises about that window, and it does a second job here:
-- the box that holds a shell command should not look like the rest of the addon, because it is not
-- part of the addon - it is a thing you are about to run on your computer.
local PS_BLUE = { 0.004, 0.141, 0.337, 0.98 }    -- #012456
local PS_FONT = "Fonts\\ARIALN.TTF"              -- the narrowest the client ships; the closest to a
                                                 -- console face without shipping a font of our own

--- ONE CLICK PUTS IT ON THE CLIPBOARD (5 Oct 2026). Arn: "when i click that blue part i should not
--- have to select and copy when i click it should copy to clipboard with a message saying copied".
---
--- I nearly told him addons cannot reach the clipboard, which is what it has always been. This
--- client has `CopyToClipboard` - nine clipboard names in the Forever census, two on TBC, and Attune
--- already calls it. Checking beat remembering again.
---
--- Feature-detected and never assumed: where the call is missing the line is still selected and
--- focused, which is the old behaviour and still works with Ctrl+C. The message says which of the
--- two just happened, because "copied" when nothing was copied is worse than no message at all.
--- ...AND IT IS PROTECTED. Within minutes of shipping the above (5 Oct 2026):
---
---     [ADDON_ACTION_FORBIDDEN] AddOn 'BiSGuild' tried to call the protected function 'UNKNOWN()'
---     [BiSGuild/Core/Window.lua]:54: in function 'Copy'
---
--- `CopyToClipboard` is in the census and addons may not call it. The fence proved the NAME exists;
--- it says nothing about permission, and I read "it is on both baselines" as "we may use it".
---
--- Worse, the guard I wrote for exactly this could not work: **a pcall around a forbidden call
--- returns CLEAN**. The refusal arrives later as an event, so `ok` was true, the window said
--- "copied", nothing was copied, and the player got a red error. This family measured that on
--- 3 Oct and wrote it down, and I did not apply it.
---
--- So the clipboard is out. Selecting the line and saying which key to press is what an addon may
--- do, and it is what every export string in every addon has always done.
function U.Copy()
    return false
end

--- A box whose whole contents select on one click. The point of the window.
local function copyBox(parent, width, console)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    e:SetFontObject("GameFontHighlightSmall")
    if console and e.SetFont then
        -- a narrow face and a flat white, the way a terminal prints: the game's gold-on-parchment
        -- would read as "a thing the addon is saying", which is the opposite of the point
        pcall(e.SetFont, e, PS_FONT, 12, "")
        e:SetTextColor(0.88, 0.92, 1, 1)
    end
    e:SetTextInsets(6, 6, 0, 0)
    local bg = e:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if console then
        bg:SetColorTexture(PS_BLUE[1], PS_BLUE[2], PS_BLUE[3], PS_BLUE[4])
    else
        bg:SetColorTexture(0.10, 0.09, 0.13, 0.95)
    end
    -- click anywhere in it and the whole line is selected, ready for Ctrl+C. Without this the
    -- player drags across a line longer than the box, which is exactly the fiddling to avoid.
    e:SetScript("OnMouseUp", function(self)
        self:HighlightText()
        self:SetFocus()
        -- the command box gets the same one-click copy; the logs box does not, because that one is
        -- for typing INTO and copying it would be a surprise
        if console then U.Flash(U.Copy()) end
    end)
    e:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return e
end

function U.Build()
    if U.frame then return U.frame end
    if not CreateFrame then return nil end

    local f = CreateFrame("Frame", "BiSGuildWindow", UIParent)
    f:SetSize(W, H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    -- nearly solid (16 Oct): at 0.82 the terminal behind it read through its lower half
    bg:SetColorTexture(0, 0, 0, 0.96)

    local head = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head:SetPoint("TOPLEFT", 12, -10)
    head:SetText(T().text("accent", "BiS> Guild"))
    f.head = head

    -- THE BLINKING PROMPT. Arn: "the more we make it look like a powershell window the better
    -- blinking _ and everything". BiSTheme has carried exactly this since 8 Sep - the title IS the
    -- console - so the house kit does it rather than a second blinker living here.
    local theme = _G.BiSTheme
    if theme and theme.Console then
        f.con = theme.Console(head, { width = 150, size = 9 })
        f.con:Set("name", "Guild")
    end

    f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.note:SetPoint("TOPRIGHT", -34, -12)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() U.Hide() end)

    -- ESCAPE CLOSES IT, the house way (Arn: "esc does not close this window"). NOT via
    -- UISpecialFrames: that list is also what CloseAllWindows() empties, so a window added to it to
    -- get one keybind is SHUT every time the player opens their spellbook. Handle the key here and
    -- swallow only ESCAPE - propagate everything else, or typing stops reaching chat. Combat-safe
    -- (16 Oct, ADDON_ACTION_BLOCKED in a fight): Init.lua's ns.EscKeys.
    ns.EscKeys(f, function() U.Hide() end)

    -- 1. where the logs are
    local l1 = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l1:SetPoint("TOPLEFT", 12, -40)
    l1:SetText("1. Paste the path to your WoW " .. T().text("accent", "Logs") .. " folder:")

    f.logs = copyBox(f, W - 24)
    f.logs:SetPoint("TOPLEFT", 12, -58)
    f.logs:SetScript("OnEnterPressed", function(self)
        local ok, why = ns.P.SetLogs(self:GetText())
        if ok then U.Refresh() else U.Say(why == "not a logs folder"
            and "that does not end in \\Logs - I want the Logs folder itself" or "paste a path") end
        self:ClearFocus()
    end)

    -- 2. the command
    local l2 = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l2:SetPoint("TOPLEFT", 12, -92)
    l2:SetText("2. After a raid, run this, then " .. T().text("accent", "/reload") .. ":")
    f.l2 = l2

    -- THE TERMINAL LINE. A prompt to its left and a cursor blinking at its right, so it reads as a
    -- shell and not as a label. Three lines tall: the command is long, and a box that scrolls
    -- sideways is a box you cannot read before you run what is in it.
    f.cmdWrap = CreateFrame("Frame", nil, f)
    f.cmdWrap:SetPoint("TOPLEFT", 12, -108)
    f.cmdWrap:SetSize(W - 24, 44)
    local cwbg = f.cmdWrap:CreateTexture(nil, "BACKGROUND")
    cwbg:SetAllPoints()
    cwbg:SetColorTexture(PS_BLUE[1], PS_BLUE[2], PS_BLUE[3], PS_BLUE[4])

    f.prompt = f.cmdWrap:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.prompt:SetPoint("TOPLEFT", 6, -4)
    if f.prompt.SetFont then pcall(f.prompt.SetFont, f.prompt, PS_FONT, 12, "") end
    f.prompt:SetTextColor(0.98, 0.98, 0.55, 1)
    f.prompt:SetText("PS>")

    f.cmd = copyBox(f, W - 60, true)
    f.cmd:SetPoint("TOPLEFT", f.cmdWrap, "TOPLEFT", 32, -4)
    f.cmd:SetHeight(36)
    f.cmd:SetMultiLine(true)

    -- THE CURSOR. It blinks whether or not anything is in the box, the way a shell sits waiting -
    -- that is the whole of what Arn asked for, and it costs one FontString and a modulo.
    f.caret = f.cmdWrap:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.caret:SetPoint("BOTTOMLEFT", f.cmdWrap, "BOTTOMLEFT", 32, 5)
    if f.caret.SetFont then pcall(f.caret.SetFont, f.caret, PS_FONT, 12, "") end
    f.caret:SetTextColor(0.88, 0.92, 1, 1)
    f.caret:SetText("_")

    -- "selected - press Ctrl+C", over the top of the window
    f.flash = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.flash:SetPoint("TOP", f, "TOP", 0, -32)
    f.flash:Hide()

    f.cmdWrap:SetScript("OnUpdate", function(self, elapsed)
        self.t = (self.t or 0) + elapsed
        -- the copied notice fades itself out
        if f.flash and f.flashUntil then
            local left = f.flashUntil - (GetTime and GetTime() or 0)
            if left <= 0 then
                f.flash:Hide()
                f.flashUntil = nil
            else
                f.flash:SetAlpha(math.min(1, left))
            end
        end
        -- 2 Hz, the same rate the house console blinks at, so two BiS windows open at once do not
        -- blink against each other
        if f.caret then f.caret:SetAlpha(((self.t % 1) < 0.5) and 1 or 0) end
        if f.con and f.con.Paint then f.con:Paint() end
    end)

    -- the report
    f.report = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.report:SetPoint("TOPLEFT", 12, -204)
    f.report:SetPoint("BOTTOMRIGHT", -12, 34)   -- clear of the button along the bottom
    f.report:SetJustifyH("LEFT")
    f.report:SetJustifyV("TOP")

    -- THE BOSSES GO IN THE TOOLTIP (6 Oct 2026). "last: <every boss>" was one line: a full Black
    -- Temple night is nine names, ~930 px on a 556 px line, so it ran out of the window. The fit
    -- check caught it. One bar, one label: the line keeps the count, the hover keeps the names.
    -- Covers the report's two header lines.
    f.lastHit = CreateFrame("Frame", nil, f)
    f.lastHit:SetPoint("TOPLEFT", 12, -204)
    f.lastHit:SetSize(W - 24, 26)
    f.lastHit:EnableMouse(true)
    f.lastHit:SetScript("OnEnter", function(self)
        local r = ns.P.Report()
        if not (r and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(("Last raid: %d kill(s)"):format(tonumber(r.kills) or 0))
        for boss in tostring(r.zones or "?"):gmatch("[^,]+") do
            GameTooltip:AddLine((boss:gsub("^%s+", "")), 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    f.lastHit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    f.lastHit:Hide()

    -- THE OTHER WAY IN: no PowerShell at all (17 Oct 2026, the notebook)
    f.pasteBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.pasteBtn:SetSize(190, 20)
    f.pasteBtn:SetPoint("BOTTOMRIGHT", -12, 10)
    f.pasteBtn:SetText("Paste from the notebook")
    if f.pasteBtn.SetFrameLevel and f.GetFrameLevel then
        local lvl = f:GetFrameLevel()
        if type(lvl) == "number" then f.pasteBtn:SetFrameLevel(lvl + 12) end
    end
    f.pasteBtn:SetScript("OnClick", function() U.ShowPaste() end)

    f:Hide()
    U.frame = f
    return f
end

--------------------------------------------------------------------
-- THE PASTE WINDOW (17 Oct 2026). Arn: a notebook "so people can just drag and drop their log ...
-- hit run ... something to paste". The notebook (BiSGuild/notebook) reads the log on Google's
-- computer and prints text; this takes it in through Core/Share.lua X.ImportPaste - each raid merged
-- like an officer's copy. Its own window at the family's 1.43:1. The terminal's LOG tab opens it.
--------------------------------------------------------------------
U.PW, U.PH = 520, 364

-- THE LINK, IN THE WINDOW (Arn, 18 Oct: "in the logs we give them the link to go to the google code
-- thing"). An addon cannot open a browser, so it is a box: click, Ctrl+C, paste in the browser. The
-- CurseForge page carries the same link "so people can double check" - the suite holds the two equal.
U.NOTEBOOK = "https://colab.research.google.com/github/blankfer/BiSGuild/blob/main/dev/BiSGuild.ipynb"

function U.BuildPaste()
    if U.paste then return U.paste end
    if not CreateFrame then return nil end
    local p = CreateFrame("Frame", "BiSGuildPaste", UIParent)
    p:SetSize(U.PW, U.PH)
    p:SetPoint("CENTER")
    p:SetFrameStrata("DIALOG")
    p:EnableMouse(true)
    p:SetMovable(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", function(self) self:StartMoving() end)
    p:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 1)   -- solid: it opens over the terminal, whose rows read through 0.96 (Arn, 18 Oct)
    local head = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head:SetPoint("TOPLEFT", 12, -10)
    head:SetText(T().text("accent", "BiS> Guild") .. "  paste from the notebook")
    local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() p:Hide() end)
    ns.EscKeys(p, function() p:Hide() end)
    -- the raids on record, to archive a wrong one (U.ShowRaids)
    local list = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    list:SetSize(130, 20)
    list:SetPoint("TOPRIGHT", -36, -7)
    list:SetText("Raids on record")
    list:SetScript("OnClick", function() U.ShowRaids() end)
    p.listBtn = list

    local l1 = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l1:SetPoint("TOPLEFT", 12, -34)
    l1:SetText("1. Click the link, press " .. T().text("accent", "Ctrl+C") .. ", and paste it into your browser:")

    -- selects itself on a click; typing into it changes nothing (the link put back at once)
    local link = copyBox(p, U.PW - 24)
    link:SetPoint("TOPLEFT", 12, -50)
    link:SetTextColor(0.72, 0.5, 1, 1)
    link:SetText(U.NOTEBOOK)
    link:SetScript("OnTextChanged", function(self, userInput)
        if userInput and self:GetText() ~= U.NOTEBOOK then self:SetText(U.NOTEBOOK) self:HighlightText() end
    end)
    p.link = link

    local how = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    how:SetPoint("TOPLEFT", 12, -78)
    how:SetPoint("RIGHT", p, "RIGHT", -12, 0)
    how:SetJustifyH("LEFT")
    how:SetText("2. Press Run all, drop your combat log in, and copy the text it prints.\n"
        .. "3. Paste it below " .. T().text("accent", "(Ctrl+V)") .. " and press Import. Nothing runs on this computer.")

    local wrap = CreateFrame("Frame", nil, p)
    wrap:SetPoint("TOPLEFT", 12, -108)
    wrap:SetPoint("BOTTOMRIGHT", -12, 64)
    -- CLIPPED (Arn's first paste, 18 Oct: 14 KB of text ran down over the whole screen and over the
    -- buttons). The text is not for reading anyway - the line under the box says what was pasted.
    if wrap.SetClipsChildren then wrap:SetClipsChildren(true) end
    local wbg = wrap:CreateTexture(nil, "BACKGROUND")
    wbg:SetAllPoints()
    wbg:SetColorTexture(PS_BLUE[1], PS_BLUE[2], PS_BLUE[3], PS_BLUE[4])

    local box = CreateFrame("EditBox", nil, wrap)
    box:SetPoint("TOPLEFT", 6, -6)
    box:SetPoint("BOTTOMRIGHT", -6, 6)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    if box.SetMaxLetters then box:SetMaxLetters(0) end       -- a raid is thousands of letters
    if box.SetFont then pcall(box.SetFont, box, PS_FONT, 10, "") end
    box:SetTextColor(0.88, 0.92, 1, 1)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- what was pasted, said in words: the box shows a wall of text nobody reads
    box:SetScript("OnTextChanged", function(self, userInput)
        if not userInput or not p.status then return end
        local text = self:GetText() or ""
        local n = 0
        for _ in text:gmatch("[^\n]+") do n = n + 1 end
        if text:find("BiSGuild paste", 1, true) then
            p.status:SetText(T().text("accent", ("pasted: %d lines - press Import"):format(n)))
        elseif text ~= "" then
            p.status:SetText(T().text("muted", "that doesn't look like the notebook's text yet"))
        else
            p.status:SetText("")
        end
    end)
    p.box = box

    p.status = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.status:SetPoint("BOTTOMLEFT", 12, 40)
    p.status:SetPoint("RIGHT", p, "RIGHT", -12, 0)
    p.status:SetJustifyH("LEFT")
    p.status:SetText("")

    local import = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    import:SetSize(120, 22)
    import:SetPoint("BOTTOMLEFT", 12, 10)
    import:SetText("Import")
    import:SetScript("OnClick", function() U.DoPaste() end)
    p.import = import
    local clear = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    clear:SetSize(90, 22)
    clear:SetPoint("LEFT", import, "RIGHT", 8, 0)
    clear:SetText("Clear")
    clear:SetScript("OnClick", function() box:SetText("") p.status:SetText("") end)

    -- THE BAR (Arn, 18 Oct: "fake progress bars - to make it look like its doing something"). Beside
    -- the buttons, the family's chunky blocks in the accent: it fills while the window says what it
    -- is doing. Flavour: the import is already done when it starts.
    local bar = CreateFrame("Frame", nil, p)
    bar:SetSize(U.BAR_W, 14)
    bar:SetPoint("BOTTOMRIGHT", -12, 14)
    local bbg = bar:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints()
    bbg:SetColorTexture(0.08, 0.08, 0.10, 1)
    bar.blocks = {}
    local bw = (U.BAR_W - 2) / U.BAR_BLOCKS
    local ar, ag, ab = 0.72, 0.5, 1
    if T().rgb then ar, ag, ab = T().rgb("accent") end
    for i = 1, U.BAR_BLOCKS do
        local b = bar:CreateTexture(nil, "ARTWORK")
        b:SetSize(bw - 2, 10)
        b:SetPoint("LEFT", bar, "LEFT", 2 + (i - 1) * bw, 0)
        b:SetColorTexture(ar, ag, ab, 1)
        b:Hide()
        bar.blocks[i] = b
    end
    bar:Hide()
    p.bar = bar
    p:Hide()
    U.paste = p
    return p
end
U.BAR_W, U.BAR_BLOCKS, U.BAR_LEN = 250, 20, 1.8

--- How many who stood in this raid are not in the guild, of how many - or nil outside a guild (or
--- before the client has sent the roster), where there is nothing to compare with.
function U.Outsiders(night)
    local K = ns.K
    if not (K and K.Guild and K.Member and IsInGuild and IsInGuild()) then return nil end
    K._guildDirty = true
    if not next(K.Guild().members) then return nil end
    local seen, total, out = {}, 0, 0
    for _, pull in ipairs(type(night) == "table" and night.pulls or {}) do
        for who in pairs(type(pull.r) == "table" and pull.r or {}) do
            if not seen[who] then
                seen[who] = true
                total = total + 1
                if not K.Member(who) then out = out + 1 end
            end
        end
    end
    return out, total
end

--- Take the box's text in. The import happens HERE, at once; then the bar plays it out and the
--- window says what came in. A refusal is said at once - nothing to wait for.
function U.DoPaste()
    local p = U.BuildPaste()
    if not p then return nil end
    if p.run then return nil end                       -- one at a time
    local text = p.box:GetText() or ""
    local got, why = ns.X.ParsePaste(text)
    if not got then
        p.status:SetText(T().text("warn", why))
        return nil, why
    end
    -- MOSTLY NOT OUR GUILD? (Arn, 18 Oct: "maybe a check that says this has more people not in your
    -- guild") - a wrong log is usually somebody else's raid. Said, and taken only on a second press
    -- of Import with the same text: a pug-heavy raid of ours still gets in.
    if p.pending ~= text then
        for _, r in ipairs(got.raids) do
            local out, total = U.Outsiders(r[2])
            if out and total > 0 and out * 2 > total then
                p.pending = text
                local zone = (r[2].zone and r[2].zone ~= "") and r[2].zone or ("raid " .. tostring(r[2].i))
                p.status:SetText(T().text("gold", ("%s %s: %d of %d aren't in your guild - press Import again to take it anyway")
                    :format(r[1]:sub(1, 10), zone, out, total)))
                return nil, "outsiders"
            end
        end
    end
    p.pending = nil
    local archived = 0
    for _, r in ipairs(got.raids) do if ns.S.ArchivedAs(r[2]) then archived = archived + 1 end end
    local raids, gear, bad = ns.X.ImportPaste(text)
    if not raids then
        p.status:SetText(T().text("warn", gear))
        return nil, gear
    end
    local script = { "Reading the paste..." }
    for key in text:gmatch("R~([^~\n]+)~") do
        script[#script + 1] = "Raid " .. tostring(ns.S.Label(key) or key)
    end
    script[#script + 1] = ("Merging into the guild's record: %d new"):format(raids)
    script[#script + 1] = ("Gear: %d raider(s)"):format(gear)
    script[#script + 1] = "Done."
    p.run = { t = 0, script = script, said = 0, raids = raids, gear = gear, bad = bad, archived = archived }
    p.bar:Show()
    for _, b in ipairs(p.bar.blocks) do b:Hide() end
    p:SetScript("OnUpdate", function(self, elapsed) U.PasteStep(self, elapsed) end)
    return raids, gear, bad
end

--- One frame of the bar. OnUpdate runs only while the bar plays (lean: nothing ticks otherwise).
function U.PasteStep(p, elapsed)
    local r = p.run
    if not r then p:SetScript("OnUpdate", nil) return end
    r.t = r.t + (tonumber(elapsed) or 0)
    local frac = math.min(1, r.t / U.BAR_LEN)
    local lit = math.floor(frac * U.BAR_BLOCKS + 0.5)
    for i, b in ipairs(p.bar.blocks) do if i <= lit then b:Show() else b:Hide() end end
    local n = math.min(#r.script, math.floor(frac * #r.script) + 1)
    if n ~= r.said then
        r.said = n
        p.status:SetText(T().text("muted", r.script[n]))
    end
    if frac < 1 then return end
    p.run = nil
    p:SetScript("OnUpdate", nil)
    local said = ("%d raid(s) taken in, %d raider(s)' gear"):format(r.raids, r.gear)
    if r.raids == 0 and r.gear == 0 then said = "nothing new - this is already on record" end
    -- an archived raid is not let back in (Core/Store.lua) - say where it is, not "already on record"
    if (r.archived or 0) > 0 then
        said = said .. T().text("gold", ("  (%d archived - Raids on record restores it)"):format(r.archived))
    end
    if r.bad > 0 then said = said .. T().text("warn", ("  (%d line(s) could not be read)"):format(r.bad)) end
    p.status:SetText(T().text(r.bad > 0 and "gold" or "good", said))
    if r.raids > 0 then p.box:SetText("") end
    if ns.K and ns.K.Paint and ns.K.frame and ns.K.frame:IsShown() then pcall(ns.K.Paint) end
    if U.PaintRaids then U.PaintRaids() end
end

--------------------------------------------------------------------
-- RAIDS ON RECORD (18 Oct 2026). Arn: "a list to click it off where it archives it or something
-- incase someone accidently clicks a correct log". Every raid, newest first, with an x; the archived
-- ones below, greyed, with a restore. Nothing is ever deleted (Core/Store.lua S.Archive). An
-- officer's click goes to the whole guild (Core/Share.lua ARCH). Opened from the paste window.
--------------------------------------------------------------------
U.RAID_ROWS = 13

function U.BuildRaids()
    if U.raids then return U.raids end
    if not CreateFrame then return nil end
    local w = CreateFrame("Frame", "BiSGuildRaids", UIParent)
    w:SetSize(U.PW, U.PH)
    w:SetPoint("CENTER")
    w:SetFrameStrata("DIALOG")
    w:EnableMouse(true)
    w:SetMovable(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", function(self) self:StartMoving() end)
    w:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local bg = w:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 1)
    local head = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head:SetPoint("TOPLEFT", 12, -10)
    head:SetText(T().text("accent", "BiS> Guild") .. "  raids on record")
    local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() w:Hide() end)
    -- ESC steps back to the paste window, the way the terminal's ESC walks back
    ns.EscKeys(w, function() U.ShowPaste() end)
    local back = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    back:SetSize(130, 20)
    back:SetPoint("TOPRIGHT", -36, -7)
    back:SetText("Back to the paste")
    back:SetScript("OnClick", function() U.ShowPaste() end)
    w.back = back

    w.who = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.who:SetPoint("TOPLEFT", 12, -32)
    w.who:SetPoint("RIGHT", w, "RIGHT", -12, 0)
    w.who:SetJustifyH("LEFT")

    w.rows = {}
    for i = 1, U.RAID_ROWS do
        local row = CreateFrame("Frame", nil, w)
        row:SetSize(U.PW - 24, 20)
        row:SetPoint("TOPLEFT", 12, -52 - (i - 1) * 21)
        local rbg = row:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints()
        rbg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0.0)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", 6, 0)
        row.label:SetWidth(240)
        row.label:SetJustifyH("LEFT")
        row.sizes = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.sizes:SetPoint("LEFT", 252, 0)
        row.sizes:SetWidth(150)
        row.sizes:SetJustifyH("LEFT")
        row.btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.btn:SetSize(76, 18)
        row.btn:SetPoint("RIGHT", -2, 0)
        row.btn:SetScript("OnClick", function(self)
            local e = self:GetParent().entry
            if e then ns.X.SetArchived(e.key, not e.archived) U.PaintRaids() end
        end)
        row:Hide()
        w.rows[i] = row
    end
    w.offset = 0
    w:EnableMouseWheel(true)
    w:SetScript("OnMouseWheel", function(self, delta)
        self.offset = math.max(0, (self.offset or 0) - (delta > 0 and 3 or -3))
        U.PaintRaids()
    end)

    w.foot = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    w.foot:SetPoint("BOTTOMLEFT", 12, 12)
    w.foot:SetPoint("RIGHT", w, "RIGHT", -12, 0)
    w.foot:SetJustifyH("LEFT")
    w.foot:SetText("Archive files a raid away: nothing counts it, and Restore brings it back.")
    w:Hide()
    U.raids = w
    return w
end

local function plural(n, one) return n .. " " .. one .. (n == 1 and "" or "s") end

function U.PaintRaids()
    local w = U.raids
    if not (w and w:IsShown()) then return end
    local S, X = ns.S, ns.X
    local list = S.RaidList()
    w.offset = math.min(w.offset or 0, math.max(0, #list - U.RAID_ROWS))
    local live = 0
    for _, e in ipairs(list) do if not e.archived then live = live + 1 end end
    w.who:SetText(("%d on record, %d archived.  "):format(live, #list - live)
        .. T().text("muted", X.IsOfficer(X.Me()) and "You're an officer: archiving goes to the whole guild."
            or "Only your copy - an officer's archive goes to the guild."))
    for i, row in ipairs(w.rows) do
        local e = list[i + w.offset]
        row.entry = e
        if e then
            local n = type(e.night) == "table" and e.night or {}
            local raiders = 0
            for _ in pairs(type(n.raiders) == "table" and n.raiders or {}) do raiders = raiders + 1 end
            local colour = e.archived and "muted" or "ink"
            row.label:SetText(T().text(colour, S.Label(e.key) or e.key))
            row.sizes:SetText(T().text(e.archived and "muted" or "ink2", e.archived
                and ("archived" .. (e.by and (" by " .. e.by) or ""))
                or (plural(tonumber(n.kills) or 0, "kill") .. ", " .. plural(raiders, "raider"))))
            row.btn:SetText(e.archived and "Restore" or "Archive")
            row:Show()
        else
            row:Hide()
        end
    end
end

--- ONE OF OUR SMALL WINDOWS AT A TIME (Arn, 18 Oct: "we keep running into this problem where it opens
--- the window right on top of the otherone"). They share the screen's centre and the DIALOG strata, so
--- two open at once interleave their pieces. Whichever opens, the others step aside; it comes in front.
function U.Alone(keep)
    -- by name, not ipairs: a window never built is nil, and ipairs would stop at it
    for _, k in ipairs({ "frame", "paste", "raids" }) do
        local w = U[k]
        if w and w ~= keep and w:IsShown() then w:Hide() end
    end
    keep:Show()
    if keep.SetToplevel then keep:SetToplevel(true) end
    if keep.Raise then keep:Raise() end
end

function U.ShowRaids()
    local w = U.BuildRaids()
    if not w then return end
    w.offset = 0
    U.Alone(w)
    U.PaintRaids()
end

--- IN FRONT, ALONE (Arn's first paste, 18 Oct: it opened BEHIND the script window). The script
--- window steps aside - the paste is the other way in, not a part of it - and this one is raised.
function U.ShowPaste()
    local p = U.BuildPaste()
    if not p then return end
    U.Alone(p)
    p.box:SetFocus()
end

--- SAY IT WORKED, AND SAY WHICH. Arn asked for "a message saying copied" - and the honest message
--- depends on whether the client actually has the call, because "copied" when nothing was copied is
--- worse than silence. It fades on its own: a notice that needs dismissing is a second job.
U.FLASH_FOR = 2.5

function U.Flash(copied)
    local f = U.frame
    if not f then return end
    f.flashUntil = (GetTime and GetTime() or 0) + U.FLASH_FOR
    f.flashText = copied and "copied to the clipboard" or "selected - press Ctrl+C"
    if f.flash then
        f.flash:SetText(T().text(copied and "good" or "gold", f.flashText))
        f.flash:SetAlpha(1)
        f.flash:Show()
    end
end

--- A line in the header, where the chat frame cannot bury it.
function U.Say(msg)
    local f = U.frame
    if f and f.note then f.note:SetText(T().text("warn", tostring(msg or ""))) end
end

function U.Refresh()
    local f = U.frame
    if not f then return end
    local P = ns.P

    f.logs:SetText(P.Logs() or "")

    local cmd = P.Command()
    f.cmd:SetText(cmd or "")
    if not cmd then U.Say("tell me where your logs are first") end

    local r = P.Report()
    if not r then
        f.report:SetText(T().text("muted",
            "No report yet. Run the command above after a raid, then /reload."))
        f.note:SetText("")
        f.lastHit:Hide()
        return
    end
    f.lastHit:Show()
    -- OVER HOW MANY NIGHTS, not just the last one. A percentage with no denominator on screen is a
    -- percentage somebody will argue with, and they would be right to: 100% of one night is not a
    -- record.
    local over = (tonumber(r.nights) or 1)
    local lines = {
        T().text("accent", ("%d raid night(s) on record"):format(over)),
        T().text("muted", "last raid: " .. (r.kills or 0) .. " kill(s) - hover for the bosses"),
    }
    for i, row in ipairs(P.Rows()) do
        if i > 8 then lines[#lines + 1] = T().text("muted", "...and more, /bisg report for all") break end
        local a, c = row.attend or 0, row.consumes or 0
        lines[#lines + 1] = ("%-14s %s  %s"):format(row.name,
            T().text(a >= 75 and "good" or a >= 50 and "gold" or "warn", a .. "%"),
            T().text(c >= 90 and "good" or c >= 60 and "gold" or "warn", c .. "%"))
    end
    f.report:SetText(table.concat(lines, "\n"))
    f.note:SetText(T().text("muted", "attendance / consumes"))
end

function U.Show()
    local f = U.Build()
    if not f then return false end
    U.Refresh()
    -- IN FRONT, WHOLE (Arn, 16 Oct: "this windows kinda get overlapping"), and alone (18 Oct, U.Alone)
    U.Alone(f)
    return true
end

function U.Hide()
    if U.frame then U.frame:Hide() end
end

function U.Toggle()
    if U.frame and U.frame:IsShown() then U.Hide() return false end
    U.Show()
    return true
end
