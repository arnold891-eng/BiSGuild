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

local W, H = 560, 300

local function T() return ns.T end

--- A box whose whole contents select on one click. The point of the window.
local function copyBox(parent, width)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    e:SetFontObject("GameFontHighlightSmall")
    e:SetTextInsets(6, 6, 0, 0)
    local bg = e:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.10, 0.09, 0.13, 0.95)
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

    f.cmd = copyBox(f, W - 24)
    f.cmd:SetPoint("TOPLEFT", 12, -110)

    -- THE WARNING, over the top of the command and not beside it. It is a child of the window so
    -- it moves with it, and it covers the command box so the words cannot be copied before the
    -- warning has been answered. A caution you can ignore by looking slightly to the left is a
    -- caution that does not work.
    local warn = CreateFrame("Frame", nil, f)
    warn:SetPoint("TOPLEFT", 8, -86)
    warn:SetPoint("BOTTOMRIGHT", -8, 8)
    warn:EnableMouse(true)                      -- swallows clicks aimed at what is underneath
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

    -- the hash line, shown under the command once asked for
    f.hashLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hashLabel:SetPoint("TOPLEFT", 12, -142)
    f.hashBox = copyBox(f, W - 24)
    f.hashBox:SetPoint("TOPLEFT", 12, -158)

    -- the report
    f.report = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.report:SetPoint("TOPLEFT", 12, -190)
    f.report:SetPoint("BOTTOMRIGHT", -12, 10)
    f.report:SetJustifyH("LEFT")
    f.report:SetJustifyV("TOP")

    f:Hide()
    U.frame = f
    return f
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

    if U.hash and cmd then
        f.hashLabel:SetText("Compare this with the hash on the CurseForge page:")
        f.hashBox:SetText(('Get-FileHash -Algorithm SHA256 "%s"'):format(P.ScriptPath() or ""))
        f.hashBox:Show()
    else
        f.hashLabel:SetText("")
        f.hashBox:SetText("")
        f.hashBox:Hide()
    end

    local r = P.Report()
    if not r then
        f.report:SetText(T().text("muted",
            "No report yet. Run the command above after a raid, then /reload."))
        f.note:SetText("")
        return
    end
    local lines = { T().text("accent", (r.zones or "?") .. "  (" .. (r.kills or 0) .. " kill(s))") }
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
