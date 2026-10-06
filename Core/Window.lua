--[[
  BiSGuild :: Core/Window.lua - the window, so nobody has to type a command.

  Arn, 5 Oct 2026: "give me a bis themed window for bis guild so i can copy and paste and not have
  to write out commands, also the warning can get lost easy in the chat, better to make them a pop
  up in the window where they can confirm with a button".

  Both halves of that are right, and the second one is the important one.

  THE WARNING WAS IN THE WRONG PLACE. A caution printed into the chat frame competes with loot
  rolls, zone changes and somebody saying "haha" - it scrolls away while you are reading it. A
  warning you must press a button to get past cannot scroll away, and the press is a deliberate act
  rather than a thing that happened above the thing you copied. So the command is not shown AT ALL
  until the warning has been answered.

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
    e:SetScript("OnMouseUp", function(self) self:HighlightText() self:SetFocus() end)
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
    bg:SetColorTexture(0, 0, 0, 0.82)

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

    -- 2. the command, hidden behind the warning
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

    f.cmdWrap:SetScript("OnUpdate", function(self, elapsed)
        self.t = (self.t or 0) + elapsed
        -- 2 Hz, the same rate the house console blinks at, so two BiS windows open at once do not
        -- blink against each other
        if f.caret then f.caret:SetAlpha(((self.t % 1) < 0.5) and 1 or 0) end
        if f.con and f.con.Paint then f.con:Paint() end
        U.Type(elapsed)
    end)

    -- THE WARNING, over the top of the command and not beside it. It is a child of the window so
    -- it moves with it, and it covers the command box so the words cannot be copied before the
    -- warning has been answered. A caution you can ignore by looking slightly to the left is a
    -- caution that does not work.
    local warn = CreateFrame("Frame", nil, f)
    warn:SetPoint("TOPLEFT", 8, -86)
    warn:SetPoint("BOTTOMRIGHT", -8, 8)
    warn:EnableMouse(true)                      -- swallows clicks aimed at what is underneath
    -- AND NOTHING DRAWS THROUGH IT. Children of the window made after this one were drawing on top
    -- - the hash box printed straight through the warning's words (Arn's screenshot, 5 Oct). A
    -- warning anything can print over is not covering anything.
    if warn.SetFrameLevel and f.GetFrameLevel then
        local lvl = f:GetFrameLevel()
        if type(lvl) == "number" then warn:SetFrameLevel(lvl + 10) end
    end
    local wbg = warn:CreateTexture(nil, "BACKGROUND")
    wbg:SetAllPoints()
    wbg:SetColorTexture(0.12, 0.02, 0.05, 0.97)

    local wt = warn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    wt:SetPoint("TOPLEFT", 14, -12)
    wt:SetText(T().text("warn", "This runs a PowerShell script on your computer"))

    local wb = warn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    wb:SetPoint("TOPLEFT", 14, -34)
    wb:SetPoint("RIGHT", warn, "RIGHT", -14, 0)
    wb:SetJustifyH("LEFT")
    wb:SetJustifyV("TOP")
    wb:SetText(
        "A script can do anything you can do on this computer - read your files, change them, send\n"
        .. "them away.\n\n"
        .. T().text("accent", "Only run it if you got BiSGuild from CurseForge or from your own officers.")
        .. "\nIf somebody sent you a copy, do not run it - not even if they seem helpful. Where you\n"
        .. "got it is the check that actually matters.\n\n"
        .. "You can also compare this copy against the hash on our CurseForge page. A faked addon\n"
        .. "would show you a faked hash here too, so that check only means something against the\n"
        .. "page - never against the number this window shows you.")

    local okb = CreateFrame("Button", nil, warn, "UIPanelButtonTemplate")
    okb:SetSize(190, 22)
    okb:SetPoint("BOTTOMLEFT", 14, 14)
    okb:SetText("I understand - show the command")
    okb:SetScript("OnClick", function()
        U.agreed = true
        U.Refresh()
    end)

    local hashb = CreateFrame("Button", nil, warn, "UIPanelButtonTemplate")
    hashb:SetSize(150, 22)
    hashb:SetPoint("LEFT", okb, "RIGHT", 8, 0)
    hashb:SetText("Show me the hash check")
    hashb:SetScript("OnClick", function() U.hash = not U.hash U.Refresh() end)
    f.warn = warn

    -- THE HASH CHECK LIVES INSIDE THE WARNING. It was a box on the window behind, so pressing the
    -- button printed it through the warning's own words. It belongs here anyway: it is part of
    -- this conversation, not part of the window underneath.
    --
    -- AND IT TYPES ITSELF OUT. Arn: "make it type it out like powershell". A line that simply
    -- appears is a line the eye skips; one that arrives a character at a time is one you watch -
    -- which is the right behaviour for the only instruction on this page that is a real check.
    -- WHAT TO DO WITH IT. Arn, looking at the typed line: "what do i do with this". It said nothing
    -- about itself and - worse - it was a FontString, which cannot be selected. A line of shell you
    -- can read and cannot copy is a dead end dressed as an instruction.
    f.hashWhat = warn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.hashWhat:SetPoint("BOTTOMLEFT", 14, 86)
    f.hashWhat:SetPoint("RIGHT", warn, "RIGHT", -14, 0)
    f.hashWhat:SetJustifyH("LEFT")
    f.hashWhat:SetText("")

    -- AN EDITBOX, so it can be taken. Clicking it finishes the typing at once and selects the whole
    -- line: nobody should wait on a flourish, and nobody should drag across a path to copy it.
    f.hashLine = CreateFrame("EditBox", nil, warn)
    f.hashLine:SetPoint("BOTTOMLEFT", 14, 44)
    f.hashLine:SetPoint("RIGHT", warn, "RIGHT", -14, 0)
    f.hashLine:SetHeight(38)
    f.hashLine:SetMultiLine(true)
    f.hashLine:SetAutoFocus(false)
    f.hashLine:SetTextInsets(6, 6, 2, 2)
    if f.hashLine.SetFont then pcall(f.hashLine.SetFont, f.hashLine, PS_FONT, 12, "") end
    f.hashLine:SetTextColor(0.88, 0.92, 1, 1)
    local hbg = f.hashLine:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    hbg:SetColorTexture(PS_BLUE[1], PS_BLUE[2], PS_BLUE[3], PS_BLUE[4])
    f.hashLine:SetScript("OnMouseUp", function(self)
        U.TypeNow()
        self:HighlightText()
        self:SetFocus()
    end)
    f.hashLine:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    f.hashLine:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.hashLine:SetText("")
    f.hashLine:Hide()

    -- the hash line, shown under the command once asked for
    f.hashLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hashLabel:SetPoint("TOPLEFT", 12, -160)
    f.hashBox = copyBox(f, W - 24, true)
    f.hashBox:SetPoint("TOPLEFT", 12, -176)

    -- the report
    f.report = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.report:SetPoint("TOPLEFT", 12, -204)
    f.report:SetPoint("BOTTOMRIGHT", -12, 10)
    f.report:SetJustifyH("LEFT")
    f.report:SetJustifyV("TOP")

    f:Hide()
    U.frame = f
    return f
end

--- TYPED OUT, A CHARACTER AT A TIME. Arn: "make it type it out like powershell".
---
--- CPS is deliberately brisk: this is a flourish, not a cutscene. A sixty-character line lands in
--- about a second, which is long enough to be watched and short enough that nobody waits for it.
--- Clicking the line at any point finishes it instantly - a person who wants to copy it should
--- never have to wait for an animation.
U.CPS = 55

function U.Type(elapsed)
    local f = U.frame
    if not (f and f.hashLine and U.typeTarget) then return end
    if U.typeAt >= #U.typeTarget then
        f.hashLine:SetText(U.typeTarget)
        return
    end
    U.typeAt = math.min(#U.typeTarget, U.typeAt + (tonumber(elapsed) or 0) * U.CPS)
    -- the cursor comes OFF on the tick that finishes it, not the one after: a trailing underscore
    -- left on a command somebody is about to copy is a character they would paste into a shell
    if U.typeAt >= #U.typeTarget then
        f.hashLine:SetText(U.typeTarget)
    else
        f.hashLine:SetText(U.typeTarget:sub(1, math.floor(U.typeAt)) .. "_")
    end
end

--- Start typing a line, or clear it with nil.
function U.TypeOut(text)
    U.typeTarget = (type(text) == "string" and text ~= "") and text or nil
    U.typeAt = 0
    if U.frame and U.frame.hashLine then U.frame.hashLine:SetText("") end
end

--- Skip the animation. Nobody should wait on a flourish to copy a line.
function U.TypeNow()
    if U.typeTarget then
        U.typeAt = #U.typeTarget
        if U.frame and U.frame.hashLine then U.frame.hashLine:SetText(U.typeTarget) end
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
    -- THE WARNING STANDS DOWN ONCE, PER SESSION, and only by a press. Not remembered across a
    -- reload on purpose: the whole point is that running a script is a decision, and a decision
    -- made last Tuesday is not one made now.
    if U.agreed and cmd then
        f.warn:Hide()
        f.cmd:SetText(cmd)
        f.l2:Show()
    elseif U.agreed then
        f.warn:Hide()
        f.cmd:SetText("")
        f.l2:Show()
        U.Say("tell me where your logs are first")
    else
        -- EMPTIED, not just covered. The warning frame sits over the box, but the text was still IN
        -- the box - so the command existed on screen behind an overlay, one dragged window or one
        -- failed draw away from being copied. Caught by its own test, which is the only reason this
        -- line is here.
        f.cmd:SetText("")
        f.warn:Show()
    end

    -- The hash check types itself out INSIDE the warning. It used to be a box on the window behind,
    -- which printed straight through the warning's own words.
    if U.hash then
        local want = ('PS> Get-FileHash -Algorithm SHA256 "%s"'):format(P.ScriptPath() or "...")
        if U.typeTarget ~= want then U.TypeOut(want) end
        f.hashLine:Show()
        -- THREE SENTENCES, because a command with no instruction is a thing people stare at. Arn,
        -- at exactly this line: "what do i do with this".
        f.hashWhat:SetText(
            T().text("accent", "Click the line below to copy it,") .. " paste it into PowerShell,\n"
            .. "and compare the answer with the hash on our CurseForge page. "
            .. T().text("warn", "Not with this addon") .. " -\n"
            .. "a faked copy would show you a faked hash here too.")
    else
        U.TypeOut(nil)
        f.hashLine:Hide()
        f.hashWhat:SetText("")
    end
    -- the old boxes on the window behind are gone; keep them empty so nothing can draw through
    if f.hashLabel then f.hashLabel:SetText("") end
    if f.hashBox then f.hashBox:SetText("") f.hashBox:Hide() end

    local r = P.Report()
    if not r then
        f.report:SetText(T().text("muted",
            "No report yet. Run the command above after a raid, then /reload."))
        f.note:SetText("")
        return
    end
    -- OVER HOW MANY NIGHTS, not just the last one. A percentage with no denominator on screen is a
    -- percentage somebody will argue with, and they would be right to: 100% of one night is not a
    -- record.
    local over = (tonumber(r.nights) or 1)
    local lines = {
        T().text("accent", ("%d raid night(s) on record"):format(over)),
        T().text("muted", "last: " .. (r.zones or "?") .. " (" .. (r.kills or 0) .. " kill(s))"),
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
    f:Show()
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
