--[[
  BiSGuild :: Core/Invite.lua - invites from the terminal, and the ROSTER page.

  Arn, 16 Oct 2026: "It'll plug into or use its own invite to raid module like BiS Tools", and "there
  are raid tools on discord and someone can import a code to build a roster and one click invites
  them to the raid team".

  PLUG IN FIRST, THROUGH ITS API. BiS Tools' party tool already does this well, and Arn shaped it
  (15 Oct): whole Forever names, a confirm list sorted by class with an x per person, the little
  "inviting..." box, refusals in red. When BiS Tools is installed and its party tool on, a list goes
  to BiSToolsAPI.InviteList (Arn: "I like OpenMap, that opens its stuff via API ... if installed it
  can API-call it" - never its insides). Without it - "bisg can do its own thing if no BiS Tools" -
  a second click within I.ARM seconds is the confirm, then one invite every I.GAP seconds.

  A ROSTER IS WHATEVER WAS PASTED. Discord raid tools export in their own shapes - a list, a table,
  "1. Name - Class", a CSV with a header. So the reader does not trust a format: it splits the text
  into pieces (lines, commas, tabs), throws away the words every roster has (classes, roles, "bench",
  headers), and looks for guild members' names in what is left - the first name is enough, Forever's
  whole "Name Surname" wins when both words are there. A piece naming nobody in the guild is shown
  as "not in guild" with its first plausible word, and is NOT invited: a Discord nickname is not a
  character name, and inviting a stranger by a guess is worse than leaving the line for a human.
]]
local ADDON, ns = ...
local K = ns.K

local I = {}
ns.Inv = I

I.GAP = 0.25            -- seconds between two of our own invites (BiS Tools paces its own)
I.ARM = 5               -- seconds the "click again to send" stays armed
I.MAX = 39              -- a raid, less you

local function Key(name) return K.NameKey(name) end

--------------------------------------------------------------------
-- who is with me
--------------------------------------------------------------------

function I.Here()
    local here = {}
    local me = UnitName and UnitName("player")
    if type(me) == "string" then here[Key(me)] = true end
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    local raid = IsInRaid and IsInRaid()
    for i = 1, n do
        local unit = raid and ("raid" .. i) or ("party" .. i)
        local ok, name = pcall(UnitName, unit)
        if ok and type(name) == "string" then here[Key(name)] = true end
    end
    return here
end

function I.Leads()
    if not (IsInGroup and IsInGroup()) then return true end
    if UnitIsGroupLeader and UnitIsGroupLeader("player") then return true end
    if UnitIsGroupAssistant and UnitIsGroupAssistant("player") then return true end
    return false
end

--------------------------------------------------------------------
-- reading a pasted roster
--------------------------------------------------------------------

I.SKIP = {}
for w in ([[name names class classes role roles spec specs tank tanks heal heals healer healers dps damage
    melee ranged caster casters support bench benched late absent tentative signed confirmed accepted
    declined maybe yes no raid team group party sign signup signups list roster player players character
    characters main alt alts discord the and or of in on at
    warrior warriors paladin paladins hunter hunters rogue rogues priest priests shaman shamans mage mages
    warlock warlocks druid druids protection prot holy disc discipline shadow restoration resto balance
    feral guardian arms fury retribution ret enhancement enh elemental ele arcane fire frost affliction
    demonology destruction beast marksmanship survival assassination combat subtlety]]):gmatch("%S+") do
    I.SKIP[w] = true
end

--- The plausible name words of a piece of text: letters (any alphabet's bytes), at least two long,
--- not a word every roster carries.
function I.Words(piece)
    local out = {}
    for w in piece:gmatch("[%a\128-\255']+") do
        if #w >= 2 and not I.SKIP[w:lower()] then out[#out + 1] = w end
    end
    return out
end

--- text -> rows { typed, member (roster entry or nil), key }, one per person, in the order pasted.
function I.Read(text)
    local guild = K.Guild().members
    local whole = {}
    for key, m in pairs(guild) do
        if m.name then whole[m.name:lower()] = key end
    end
    local rows, seen = {}, {}
    for piece in (tostring(text or "") .. "\n"):gmatch("([^\n,;\t|]*)[\n,;\t|]") do
        local words = I.Words(piece)
        local hit, typed
        for i, w in ipairs(words) do
            local two = words[i + 1] and (w .. " " .. words[i + 1]):lower()
            local key = (two and whole[two]) or (guild[w:lower()] and w:lower())
            if key then hit, typed = key, guild[key].name or w break end
        end
        if hit then
            if not seen[hit] then
                seen[hit] = true
                rows[#rows + 1] = { typed = typed, member = guild[hit], key = hit }
            end
        elseif words[1] then
            local key = "?" .. words[1]:lower()
            if not seen[key] then
                seen[key] = true
                rows[#rows + 1] = { typed = words[1], key = key }
            end
        end
    end
    return rows
end

--- Where each row stands now: "here" (with you), "online", "offline", "not in guild".
function I.Status(row, here)
    if not row.member then return "not in guild" end
    if here[row.key] then return "with you" end
    return row.member.online and "online" or "offline"
end

--------------------------------------------------------------------
-- sending
--------------------------------------------------------------------

--- BiS Tools' public API, when it is installed and its party tool is on (Arn, 16 Oct: "if installed it
--- can API-call it" - never its insides, which may change; BiSToolsAPI major 1 promises not to).
local function Tools()
    local A = _G.BiSToolsAPI
    if type(A) ~= "table" or A.major ~= 1 or not A.PartyReady then return nil end
    local ok, ready = pcall(A.PartyReady)
    return ok and ready and A or nil
end
I.Tools = Tools

local function ClassName(file)
    local names = _G.LOCALIZED_CLASS_NAMES_MALE
    return file and names and names[file] or file
end

--- Invite these guild members (roster entries), `label` naming the list. Through BiS Tools' confirm
--- list when it is here; else armed, then sent on the second click. Answers how many, and by what.
function I.Send(members, label)
    local here = I.Here()
    local go, with = {}, {}
    for _, m in ipairs(members) do
        local e = { name = m.name, class = ClassName(m.class), classFile = m.class, rank = m.rank }
        if here[Key(m.name)] then with[#with + 1] = e else go[#go + 1] = e end
    end
    if #go == 0 then K.Say(("everyone %s is already with you"):format(label), "good") return 0, "none" end
    local A = Tools()
    if A then
        local ok, n, why = pcall(A.InviteList, label, go)
        if ok and n then
            K.Say(("%d on BiS Tools' invite list - look it over, then Send"):format(n), "accent")
            return n, "tools"
        end
        if ok and why == "not leader" then K.Say("only the leader (or an assistant) can invite", "warn") return 0, why end
        -- anything else: BiS Tools could not take it - BiS Guild does it itself below
    end
    if not I.Leads() then K.Say("only the leader (or an assistant) can invite", "warn") return 0, "not leader" end
    local now = GetTime and GetTime() or 0
    local a = I.armed
    if not (a and a.label == label and now - a.at <= I.ARM) then
        I.armed = { label = label, at = now }
        K.Say(("invite %d %s? click again within %d s to send"):format(#go, label, I.ARM), "gold")
        return 0, "armed"
    end
    I.armed = nil
    local names = {}
    for _, e in ipairs(go) do names[#names + 1] = e.name end
    I.Queue(names)
    K.Say(("inviting %d: %s"):format(#names, table.concat(names, ", ")), "good")
    return #names, "sent"
end

--- One raider, from their card: no confirm - the click on their own card is the choice.
function I.One(name)
    local m = K.Guild().members[Key(name)]
    local whole = m and m.name or name
    if I.Here()[Key(whole)] then K.Say(whole .. " is already with you", "good") return 0 end
    if not I.Leads() then K.Say("only the leader (or an assistant) can invite", "warn") return 0 end
    local A = Tools()
    local ok, n = false, nil
    if A and A.InviteOne then ok, n = pcall(A.InviteOne, whole) end
    if not (ok and n) then I.Queue({ whole }) end
    K.Say(("invited %s%s"):format(whole, m and "" or " (not in the guild roster - invited as written)"), "good")
    return 1
end

I.queue = {}
function I.Queue(names)
    -- past five, the party must be a raid before the sixth invite can land
    local total = ((GetNumGroupMembers and GetNumGroupMembers()) or 0) + #names
    if total > 4 and IsInGroup and IsInGroup() and not (IsInRaid and IsInRaid()) then
        local convert = (C_PartyInfo and C_PartyInfo.ConvertToRaid) or ConvertToRaid
        if convert then pcall(convert) end
    end
    for _, n in ipairs(names) do I.queue[#I.queue + 1] = n end
    I.Pump()
end

function I.Pump()
    if I._armed or #I.queue == 0 then return end
    local name = table.remove(I.queue, 1)
    local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if invite then pcall(invite, name) end
    I.sent = (I.sent or 0) + 1
    if #I.queue > 0 and C_Timer and C_Timer.After then
        I._armed = true
        C_Timer.After(I.GAP, function() I._armed = false I.Pump() end)
    elseif #I.queue > 0 then
        I.Pump()
    end
end

--- Every guild member on the record who is online and not with you: raid night's one button.
function I.OnlineRaiders()
    local out = {}
    for name in pairs(ns.S.Cards()) do
        local m = K.Guild().members[Key(name)]
        if m and m.online then out[#out + 1] = m end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

--------------------------------------------------------------------
-- the ROSTER page
--------------------------------------------------------------------

I.STATUS_COLOUR = { ["online"] = "good", ["with you"] = "accent", ["offline"] = "muted", ["not in guild"] = "warn" }

function K.BuildRoster(page, bodyH)
    local ui = K.ui
    local leftW = 330
    page.paste = ui.Panel(page, "PASTE A ROSTER", 8, 0, leftW, bodyH - 4)
    local box = CreateFrame("EditBox", nil, page.paste)
    box:SetPoint("TOPLEFT", 8, -26)
    box:SetSize(leftW - 16, bodyH - 70)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetMaxLetters(6000)
    box:SetFontObject("GameFontHighlightSmall")
    if box.SetFont then pcall(box.SetFont, box, K.FONT, 12, "") end
    box:SetTextColor(ui.rgb("ink"))
    local bbg = page.paste:CreateTexture(nil, "BORDER")
    bbg:SetPoint("TOPLEFT", 4, -22)
    bbg:SetSize(leftW - 8, bodyH - 62)
    ui.Fill(bbg, "sunken")
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    page.box = box
    page.paste.right:SetText("names, a list, a table - any shape")

    local function Button(parent, label, x, y, w, fn)
        local b = CreateFrame("Button", nil, parent)
        b:SetPoint("BOTTOMLEFT", x, y)
        b:SetSize(w, 20)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        ui.Fill(bg, "accentSoft")
        local hi = b:CreateTexture(nil, "HIGHLIGHT")
        hi:SetAllPoints()
        ui.Fill(hi, "accent", K.HOVER)
        b.fs = ui.Text(b, 12, "gold", "CENTER")
        b.fs:SetPoint("CENTER", 0, 0)
        b.fs:SetText(label)
        b:SetScript("OnClick", fn)
        return b
    end
    page.read = Button(page.paste, "READ IT", 8, 8, 100, function()
        ns.DB().roster = page.box:GetText()
        page.box:ClearFocus()
        K.Paint()
    end)
    page.clear = Button(page.paste, "CLEAR", 116, 8, 80, function()
        ns.DB().roster = nil
        page.box:SetText("")
        K.Paint()
    end)

    local rx = leftW + 16
    page.list = ui.Panel(page, "THE ROSTER", rx, 0, K.W - rx - 8, bodyH - 4)
    page.grid = ui.Grid(page.list, { "NAME", "CLASS", "RANK", "NOW" },
        { { 170, "LEFT" }, { 90, "LEFT" }, { 100, "LEFT" }, { 80, "RIGHT" } }, K.LIST_ROWS - 2, 22,
        function(key)
            local r = I.byKey and I.byKey[key]
            if r and r.member then K.Go(r.member.name .. " <raider>") end
        end)
    page.send = Button(page.list, "INVITE ONLINE", 8, 8, 160, function()
        local rows, members = I.Read(ns.DB().roster), {}
        local here = I.Here()
        for _, r in ipairs(rows) do
            if r.member and I.Status(r, here) == "online" then members[#members + 1] = r.member end
        end
        I.Send(members, "on the pasted roster")
    end)
    page.hint = ui.Text(page.list, 12, "ink2")
    page.hint:SetPoint("TOPLEFT", 12, -44)
    page.hint:SetWidth(K.W - rx - 40)
    if page.hint.SetWordWrap then page.hint:SetWordWrap(true) end
    page.hint:SetText("Paste the roster from your Discord raid tool (or just names) on the left and press READ IT. "
        .. "Guild members are found by name; anyone else is shown but never invited by a guess.")
    return page
end

function K.PaintRoster(p)
    local ui = K.ui
    local text = ns.DB().roster
    if type(text) == "string" and p.box:GetText() ~= text and not p.box:HasFocus() then p.box:SetText(text) end
    local rows = I.Read(text)
    local here = I.Here()
    local counts = { online = 0 }
    I.byKey = {}
    for _, r in ipairs(rows) do
        local s = I.Status(r, here)
        counts[s] = (counts[s] or 0) + 1
        I.byKey[r.key] = r
    end
    if #rows == 0 then p.hint:Show() else p.hint:Hide() end
    p.list.right:SetText(#rows == 0 and "" or ("%d on it, %d online, %d not in guild"):format(#rows, counts.online,
        counts["not in guild"] or 0) .. ui.Showing(p.grid))
    p.send.fs:SetText(("INVITE %d ONLINE"):format(counts.online))
    local off = ui.Scroll(p.grid, #rows)
    local colours = _G.RAID_CLASS_COLORS
    for i, row in ipairs(p.grid.rows) do
        local r = rows[i + off]
        if r then
            local s = I.Status(r, here)
            local m = r.member
            local cc = m and m.class and colours and colours[m.class]
            ui.SetRow(row, r.key, { m and m.name or r.typed, m and ClassName(m.class) or "", m and m.rank or "", s },
                { cc and { cc.r, cc.g, cc.b } or (m and "ink" or "muted"), "ink2", "muted", I.STATUS_COLOUR[s] or "ink" })
        else
            ui.SetRow(row, nil, {})
        end
    end
end
