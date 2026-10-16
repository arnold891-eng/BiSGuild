--[[
  BiSGuild :: Core/Terminal.lua - the raider terminal.

  Arn, 16 Oct 2026: "I saw a Bloomberg terminal window and I know that's the layout I want" - "type
  in a raider name, show all the gear they have ... what their attendance is, how much they consume,
  what we used to put into the raider sheet and LC sheet", and "we type in a boss name, it's like its
  own company ticker".

  THE SHAPE IS BLOOMBERG'S, THE LOOK IS OURS (Arn: "i like our bis theme, these pictures are just
  ideas"): a command line you type a name into, function keys along the top, panels of numbers, a
  ticker along the bottom - in BiSTheme's palette, at the family's 1.43:1.

    KUMLUST <RAIDER> GO     the raider card: armory, attendance, consumes, gear issues, loot won
    RAGNAROS <BOSS> GO      the boss ticker: kills, wipes, first kill, fastest, who has downed it
    RAIDERS  BOSSES         tabs: the two lists, every row clickable
    LOG                     tab: the script window (Core/Window.lua), for the officer who imports

  The Bloomberg words are optional: a bare name works, and a start of one does when only one thing
  starts that way. Everything shown is built from the guild's record (Core/Store.lua), so a night that
  arrived over the guild channel is on the card exactly like one imported from a log.

  NO FUNCTION KEYS (Arn, 16 Oct: "those tabs - i have stuff keybound to those keys"). Bloomberg's
  F1/F2 are a raider's keybinds, so the tabs are clicked, and they say only what they are.
]]
local ADDON, ns = ...

local K = {}
ns.K = K

K.W, K.H = 860, 601            -- 1.43:1, the family's shape
K.ROW = 16
K.FONT = "Fonts\\ARIALN.TTF"   -- narrow, closest the client ships to a terminal face
K.LIST_ROWS = 27
K.STRIP = 12                   -- nights in an attendance strip

local function T() return ns.T end
local function S() return ns.S end

--------------------------------------------------------------------
-- the words (no frames: the suite drives these directly)
--------------------------------------------------------------------

function K.Clock(ms)
    ms = tonumber(ms) or 0
    if ms <= 0 then return "-" end
    local s = math.floor(ms / 1000 + 0.5)
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

local function lower(s) return tostring(s or ""):lower() end

--- What a typed line asks for. Returns kind, key - kind is "raider", "boss", "raiders", "bosses",
--- "log" - or nil and a list of near names to offer.
---   "kumlust", "KUMLUST <RAIDER> GO", "kum" (if only one name starts so), "rag <boss>", "bosses"
function K.Parse(line, cards, bosses)
    local s = tostring(line or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local want
    s = s:gsub("%s+[Gg][Oo]$", "")          -- a space first: "Margo" is a raider, not "Mar GO"
    local tag = s:match("<%s*(%a+)%s*>%s*$")
    if tag then
        want = lower(tag)
        s = s:gsub("%s*<%s*%a+%s*>%s*$", "")
    end
    local l = lower(s)
    if l == "" then
        if want == "raider" or want == "raiders" then return "raiders" end
        if want == "boss" or want == "bosses" then return "bosses" end
        return nil, {}
    end
    if l == "raiders" then return "raiders" end
    if l == "bosses" then return "bosses" end
    if l == "log" then return "log" end
    if want == "raider" or want == "player" then bosses = {} end
    if want == "boss" then cards = {} end

    local starts, near = {}, {}
    local function look(kind, set)
        for name in pairs(set or {}) do
            local n = lower(name)
            if n == l then return kind, name end
            if n:sub(1, #l) == l then starts[#starts + 1] = { kind, name }
            elseif n:find(l, 1, true) then near[#near + 1] = { kind, name } end
        end
    end
    local kind, name = look("raider", cards)
    if kind then return kind, name end
    kind, name = look("boss", bosses)
    if kind then return kind, name end
    if #starts == 1 then return starts[1][1], starts[1][2] end
    local offer = {}
    for _, list in ipairs({ starts, near }) do
        table.sort(list, function(a, b) return a[2] < b[2] end)
        for _, e in ipairs(list) do if #offer < 4 then offer[#offer + 1] = e[2] end end
    end
    return nil, offer
end

--- The last `n` raid dates, each with whether this raider earned it - the attendance strip.
function K.Strip(card, n)
    local dates = S().Dates()
    local earned = {}
    for _, d in ipairs(card and card.attended or {}) do earned[d] = true end
    local out = {}
    for i = math.max(1, #dates - n + 1), #dates do out[#out + 1] = { date = dates[i], earned = earned[dates[i]] or false } end
    return out
end

--- BiS Loot's awards to one raider, newest first. Read straight from its saved ledger (one tab-
--- separated line per event, Core/Ledger.lua over there) - so it works whenever BiS Loot has ever
--- run on this client, and says nothing at all when it has not.
K.LEDGER = { author = 2, t = 5, kind = 6, raid = 7, boss = 8, item = 9, who = 10 }
function K.Loot(name)
    local db = _G.BiSLootDB
    local out = {}
    if type(db) ~= "table" or type(db.lines) ~= "table" then return out, false end
    local want = lower(name)
    for _, line in pairs(db.lines) do
        if type(line) == "string" then
            local p = {}
            for f in (line .. "\t"):gmatch("(.-)\t") do p[#p + 1] = f end
            if p[K.LEDGER.kind] == "award" and lower(p[K.LEDGER.who]) == want then
                out[#out + 1] = { item = p[K.LEDGER.item], boss = p[K.LEDGER.boss], t = tonumber(p[K.LEDGER.t]) or 0 }
            end
        end
    end
    table.sort(out, function(a, b) return a.t > b.t end)
    return out, true
end

--- An item's name and quality colour, or "item 12345" until the client has it (it asks the server,
--- and GET_ITEM_INFO_RECEIVED repaints).
function K.Item(id)
    local n = tonumber(id)
    if not n then
        local link = tostring(id or "")
        return (link:match("%[(.-)%]") or link), nil
    end
    if n == 0 then return nil end
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if get then
        local ok, name, _, quality = pcall(get, n)
        if ok and name then return name, quality end
    end
    K.waiting = true
    return "item " .. n, nil
end

--- The raiders list: name, attendance %, last night, flask on the last night, deaths, issues.
function K.Rows(cards)
    local nights = #S().Dates()
    local out = {}
    for name, c in pairs(cards) do
        out[#out + 1] = {
            name = name,
            att = nights > 0 and math.floor(100 * #c.attended / nights + 0.5) or 0,
            last = c.last and c.last.date or "-",
            flask = c.last and ((c.last.flask or 0) + (c.last.elixir or 0) > 0) or false,
            deaths = c.deaths or 0,
            issues = #(c.issues or {}),
        }
    end
    table.sort(out, function(a, b)
        if a.att ~= b.att then return a.att > b.att end
        return a.name < b.name
    end)
    return out
end

function K.BossRows(pages)
    local out = {}
    for name, p in pairs(pages) do
        out[#out + 1] = { name = name, kills = p.kills, wipes = p.wipes, best = p.best, first = p.first or "-" }
    end
    table.sort(out, function(a, b)
        if (a.first == "-") ~= (b.first == "-") then return b.first == "-" end
        if a.first ~= b.first then return a.first < b.first end
        return a.name < b.name
    end)
    return out
end

--- The ticker: the newest night, boss by boss.
function K.TickerText()
    local dates = S().Dates()
    local last = dates[#dates]
    if not last then return "NO RAID NIGHTS ON RECORD" end
    local n = S().Record().nights[last]
    local parts = { ("LAST RAID %s  %d KILLS  %d RAIDERS"):format(last, tonumber(n.kills) or 0, select(1, S().Weight(n))) }
    local names = {}
    for boss in pairs(n.bosses or {}) do names[#names + 1] = boss end
    table.sort(names)
    for _, boss in ipairs(names) do
        local b = n.bosses[boss]
        local up = (tonumber(b.kills) or 0) > 0
        parts[#parts + 1] = ("%s %s %s"):format(boss:upper(), up and "DOWN" or "WIPE",
            up and K.Clock(b.best) or ("x" .. (tonumber(b.pulls) or 0)))
    end
    parts[#parts + 1] = ("%d NIGHTS ON RECORD"):format(#dates)
    return table.concat(parts, "   //   ")
end

--------------------------------------------------------------------
-- frames
--------------------------------------------------------------------

local function rgb(name) return T().rgb(name) end

local function Fill(region, name, a)
    local r, g, b = rgb(name)
    region:SetColorTexture(r, g, b, a or 1)
end

local function Text(parent, size, colour, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if fs.SetFont then pcall(fs.SetFont, fs, K.FONT, size or 12, "") end
    fs:SetTextColor(rgb(colour or "ink"))
    fs:SetJustifyH(justify or "LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    return fs
end

--- A panel: a sunken box with a gold title in its top bar - Bloomberg's amber header, our gold.
local function Panel(parent, title, x, y, w, h)
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT", x, -y)
    p:SetSize(w, h)
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    Fill(bg, "surface", 0.95)
    local bar = p:CreateTexture(nil, "BORDER")
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetHeight(18)
    Fill(bar, "accentSoft")
    p.title = Text(p, 11, "gold")
    p.title:SetPoint("TOPLEFT", 6, -3)
    p.title:SetText(title)
    p.right = Text(p, 11, "muted", "RIGHT")
    p.right:SetPoint("TOPRIGHT", -6, -3)
    return p
end

--- A table of rows: column heads in muted, `n` clickable rows below. cols = { {w, justify}, ... }
--- THE LISTS SCROLL (Arn's first real report, 16 Oct: 34 raiders, 27 rows - everyone after Rollsy
--- was simply not there). The mouse wheel moves a list three rows at a time; the panel's corner
--- says which rows are showing.
local function Scroll(g, total)
    local most = math.max(0, total - #g.rows)
    g.offset = math.max(0, math.min(g.offset or 0, most))
    g.total = total
    return g.offset
end
local function Showing(g)
    if (g.total or 0) <= #g.rows then return "" end
    return ("   rows %d-%d of %d"):format(g.offset + 1, math.min(g.total, g.offset + #g.rows), g.total)
end

local function Grid(parent, heads, cols, n, y0, onClick)
    local g = { rows = {}, offset = 0 }
    parent:EnableMouseWheel(true)
    parent:SetScript("OnMouseWheel", function(_, delta)
        g.offset = (g.offset or 0) - (delta or 0) * 3
        K.Paint()
    end)
    local x = 6
    for i, c in ipairs(cols) do
        local h = Text(parent, 11, "muted", c[2])
        h:SetPoint("TOPLEFT", x, -y0)
        h:SetWidth(c[1])
        h:SetText(heads[i])
        x = x + c[1] + 6
    end
    for r = 1, n do
        local row = CreateFrame("Button", nil, parent)
        row:SetPoint("TOPLEFT", 2, -(y0 + r * K.ROW))
        row:SetSize(x - 2, K.ROW)
        local hi = row:CreateTexture(nil, "HIGHLIGHT")
        hi:SetAllPoints()
        Fill(hi, "accentSoft", 0.8)
        row.cells = {}
        local cx = 4
        for i, c in ipairs(cols) do
            local fs = Text(row, 12, "ink", c[2])
            fs:SetPoint("TOPLEFT", cx, -2)
            fs:SetWidth(c[1])
            row.cells[i] = fs
            cx = cx + c[1] + 6
        end
        if onClick then row:SetScript("OnClick", function(self) if self.key then onClick(self.key) end end) end
        g.rows[r] = row
    end
    return g
end

local function SetRow(row, key, values, colours)
    row.key = key
    for i, fs in ipairs(row.cells) do
        fs:SetText(values[i] ~= nil and tostring(values[i]) or "")
        fs:SetTextColor(rgb(colours and colours[i] or "ink"))
    end
    if key then row:Show() else row:Hide() end
end

function K.Build()
    if K.frame then return K.frame end
    if not CreateFrame then return nil end
    local f = CreateFrame("Frame", "BiSGuildTerminal", UIParent)
    K.frame = f
    f:SetSize(K.W, K.H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    Fill(bg, "bg", 0.97)
    local edge = f:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT", 0, 0)
    edge:SetPoint("TOPRIGHT", 0, 0)
    edge:SetHeight(2)
    Fill(edge, "accent")

    -- the top bar: the console prompt, then the function keys
    f.head = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.head:SetPoint("TOPLEFT", 10, -8)
    f.head:SetText(T().text("accent", "BiS> Terminal"))
    local theme = _G.BiSTheme
    if theme and theme.Console then
        f.con = theme.Console(f.head, { width = 170, size = 9 })
        f.con:Set("name", "Guild Terminal")
    end
    f.keys = {}
    local keyX = 300
    for _, k in ipairs({ { "RAIDERS", "raiders" }, { "BOSSES", "bosses" }, { "LOG", "log" } }) do
        local b = CreateFrame("Button", nil, f)
        b:SetPoint("TOPLEFT", keyX, -6)
        b:SetSize(96, 18)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        Fill(b.bg, "sunken")
        local hi = b:CreateTexture(nil, "HIGHLIGHT")
        hi:SetAllPoints()
        Fill(hi, "accentSoft", 0.8)
        b.fs = Text(b, 11, "ink", "CENTER")
        b.fs:SetPoint("CENTER", 0, 0)
        b.fs:SetText(k[1])
        b:SetScript("OnClick", function() K.Go(k[2]) end)
        f.keys[k[2]] = b
        keyX = keyX + 102
    end
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() K.Hide() end)

    -- the command line
    local cmdbg = f:CreateTexture(nil, "BORDER")
    cmdbg:SetPoint("TOPLEFT", 8, -30)
    cmdbg:SetSize(K.W - 16, 22)
    Fill(cmdbg, "sunken")
    f.prompt = Text(f, 13, "gold")
    f.prompt:SetPoint("TOPLEFT", 14, -34)
    f.prompt:SetText("BiS>")
    local e = CreateFrame("EditBox", nil, f)
    e:SetPoint("TOPLEFT", 52, -30)
    e:SetSize(K.W - 70, 22)
    e:SetAutoFocus(false)
    e:SetMaxLetters(60)
    e:SetFontObject("GameFontHighlight")
    if e.SetFont then pcall(e.SetFont, e, K.FONT, 13, "") end
    e:SetTextColor(rgb("ink"))
    e:SetScript("OnEnterPressed", function(self)
        local line = self:GetText()
        self:SetText("")
        K.Go(line)
    end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.cmd = e
    f.status = Text(f, 11, "muted")
    f.status:SetPoint("TOPLEFT", 12, -56)
    f.status:SetWidth(K.W - 24)

    -- ESC: the command line takes the first press (it gives the keyboard back), the window the next
    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(true)
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            K.Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    -- the pages, one shown at a time, between the status line and the ticker
    local top, bottom = 72, 24
    local bodyH = K.H - top - bottom
    local function Page()
        local p = CreateFrame("Frame", nil, f)
        p:SetPoint("TOPLEFT", 0, -top)
        p:SetSize(K.W, bodyH)
        p:Hide()
        return p
    end
    f.pages = {}

    -- AN EMPTY LIST SAYS WHY (Arn clicked RAIDERS on a fresh install and "nothing" happened: the
    -- tab sent him to the same blank page he was already on). Each list keeps its own page and says
    -- where the nights come from when it has none.
    local EMPTY = "No raid nights on record yet.\n\nAfter a raid, an officer runs the log script (the LOG "
        .. "tab) and types /reload - the night is kept here and shared with the guild.\n\nOr wait: when "
        .. "an officer who has the nights is online, they arrive by themselves."
    local function Hint(panel)
        panel.hint = Text(panel, 13, "ink2")
        panel.hint:SetPoint("TOPLEFT", 16, -44)
        panel.hint:SetWidth(K.W - 64)
        if panel.hint.SetWordWrap then panel.hint:SetWordWrap(true) end
        panel.hint:SetText(EMPTY)
    end

    -- every raider
    local pr = Page()
    local plist = Panel(pr, "RAIDERS", 8, 0, K.W - 16, bodyH - 4)
    Hint(plist)
    pr.grid = Grid(plist, { "NAME", "ATTEND", "LAST RAID", "FLASK/ELIX", "DEATHS", "GEAR ISSUES" },
        { { 200, "LEFT" }, { 80, "RIGHT" }, { 110, "RIGHT" }, { 70, "RIGHT" }, { 70, "RIGHT" }, { 110, "RIGHT" } },
        K.LIST_ROWS, 22, function(name) K.Go(name .. " <raider>") end)
    pr.panel = plist
    f.pages.raiders = pr

    -- every boss
    local pb = Page()
    local blist = Panel(pb, "BOSSES", 8, 0, K.W - 16, bodyH - 4)
    Hint(blist)
    pb.grid = Grid(blist, { "BOSS", "KILLS", "WIPES", "FASTEST", "FIRST KILL" },
        { { 260, "LEFT" }, { 70, "RIGHT" }, { 70, "RIGHT" }, { 90, "RIGHT" }, { 120, "RIGHT" } },
        K.LIST_ROWS, 22, function(name) K.Go(name .. " <boss>") end)
    pb.panel = blist
    f.pages.bosses = pb

    -- the raider card: the armory on the left, the numbers on the right
    local rc = Page()
    local leftW = 470
    rc.armory = Panel(rc, "ARMORY", 8, 0, leftW, bodyH - 4)
    rc.gear = Grid(rc.armory, { "SLOT", "ITEM", "ILVL", "" },
        { { 62, "LEFT" }, { 250, "LEFT" }, { 34, "RIGHT" }, { 84, "RIGHT" } }, #S().SLOTS, 22)
    local rx, rw = leftW + 16, K.W - leftW - 24
    rc.att = Panel(rc, "ATTENDANCE", rx, 0, rw, 74)
    rc.attLine = Text(rc.att, 13, "ink")
    rc.attLine:SetPoint("TOPLEFT", 8, -24)
    rc.strip = {}
    for i = 1, K.STRIP do
        local sq = rc.att:CreateTexture(nil, "ARTWORK")
        sq:SetPoint("TOPLEFT", 8 + (i - 1) * 28, -46)
        sq:SetSize(24, 14)
        rc.strip[i] = sq
    end
    rc.cons = Panel(rc, "CONSUMES", rx, 80, rw, 132)
    rc.consLines = {}
    for i = 1, 6 do
        local l = Text(rc.cons, 12, "ink")
        l:SetPoint("TOPLEFT", 8, -6 - i * 18)
        l:SetWidth(rw - 16)
        rc.consLines[i] = l
    end
    rc.loot = Panel(rc, "LOOT WON", rx, 218, rw, bodyH - 222)
    rc.lootLines = {}
    for i = 1, 14 do
        local l = Text(rc.loot, 12, "ink")
        l:SetPoint("TOPLEFT", 8, -6 - i * 17)
        l:SetWidth(rw - 16)
        rc.lootLines[i] = l
    end
    f.pages.raider = rc

    -- the boss ticker: the numbers on the left, who has downed it on the right
    local bp = Page()
    bp.stats = Panel(bp, "BOSS", 8, 0, 400, 200)
    bp.statLines = {}
    for i = 1, 6 do
        local l = Text(bp.stats, 13, "ink")
        l:SetPoint("TOPLEFT", 8, -6 - i * 22)
        l:SetWidth(384)
        bp.statLines[i] = l
    end
    bp.nights = Panel(bp, "NIGHTS IT DIED", 8, 206, 400, bodyH - 210)
    bp.nightLines = {}
    for i = 1, 16 do
        local l = Text(bp.nights, 12, "ink")
        l:SetPoint("TOPLEFT", 8, -6 - i * 17)
        bp.nightLines[i] = l
    end
    bp.killers = Panel(bp, "WHO HAS DOWNED IT", 416, 0, K.W - 424, bodyH - 4)
    bp.grid = Grid(bp.killers, { "RAIDER", "KILLS" }, { { 300, "LEFT" }, { 80, "RIGHT" } }, K.LIST_ROWS, 22,
        function(name) K.Go(name .. " <raider>") end)
    f.pages.boss = bp

    -- the ticker along the bottom
    local tbg = f:CreateTexture(nil, "BORDER")
    tbg:SetPoint("BOTTOMLEFT", 0, 0)
    tbg:SetPoint("BOTTOMRIGHT", 0, 0)
    tbg:SetHeight(20)
    Fill(tbg, "sunken")
    f.tickClip = CreateFrame("Frame", nil, f)
    f.tickClip:SetPoint("BOTTOMLEFT", 8, 2)
    f.tickClip:SetSize(K.W - 16, 16)
    if f.tickClip.SetClipsChildren then f.tickClip:SetClipsChildren(true) end
    f.tick = Text(f.tickClip, 12, "gold")
    f.tick:SetPoint("LEFT", f.tickClip, "LEFT", 0, 0)
    f.tickX = 0
    -- THE TICKER MOVES ONLY WHILE THE WINDOW IS OPEN, and it costs one SetPoint a frame (the suite
    -- holds it to that): its OnUpdate lives on the window, which runs nothing while hidden.
    f:SetScript("OnUpdate", function(self, elapsed)
        local w = self.tickW or 0
        if w <= 0 then return end
        self.tickX = self.tickX - (elapsed or 0) * 40
        if self.tickX < -w then self.tickX = K.W end
        self.tick:ClearAllPoints()
        self.tick:SetPoint("LEFT", self.tickClip, "LEFT", self.tickX, 0)
        if self.con then self.con:Paint() end
    end)

    f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    f:SetScript("OnEvent", function()
        if K.waiting and f:IsShown() and K.page == "raider" then K.Paint() end
    end)
    return f
end

--------------------------------------------------------------------
-- painting
--------------------------------------------------------------------

local function Say(text, colour)
    local f = K.frame
    if not f then return end
    f.status:SetText(text or "")
    f.status:SetTextColor(rgb(colour or "muted"))
end
K.Say = Say

local function PaintRaiders(p)
    local rows = K.Rows(S().Cards())
    local off = Scroll(p.grid, #rows)
    p.panel.right:SetText(("%d raiders, %d nights"):format(#rows, #S().Dates()) .. Showing(p.grid))
    if #rows == 0 then p.panel.hint:Show() else p.panel.hint:Hide() end
    for i, row in ipairs(p.grid.rows) do
        local r = rows[i + off]
        if r then
            SetRow(row, r.name, { r.name, r.att .. "%", r.last, r.flask and "yes" or "no", r.deaths,
                                  r.issues > 0 and (r.issues .. " no enchant") or "clean" },
                { "ink", r.att >= 75 and "good" or (r.att >= 50 and "gold" or "warn"), "ink2",
                  r.flask and "good" or "warn", r.deaths > 0 and "warn" or "ink2", r.issues > 0 and "warn" or "good" })
        else
            SetRow(row, nil, {})
        end
    end
end

local function PaintBosses(p)
    local rows = K.BossRows(S().Bosses())
    local off = Scroll(p.grid, #rows)
    p.panel.right:SetText(("%d bosses"):format(#rows) .. Showing(p.grid))
    if #rows == 0 then p.panel.hint:Show() else p.panel.hint:Hide() end
    for i, row in ipairs(p.grid.rows) do
        local r = rows[i + off]
        if r then
            SetRow(row, r.name, { r.name, r.kills, r.wipes, K.Clock(r.best), r.first },
                { "ink", r.kills > 0 and "good" or "muted", r.wipes > 0 and "warn" or "ink2", "gold", "ink2" })
        else
            SetRow(row, nil, {})
        end
    end
end

local QUALITY = { [0] = "muted", [1] = "ink", [2] = "good", [3] = "slate", [4] = "accent", [5] = "gold" }

local function PaintRaider(p, name)
    local card = S().Cards()[name]
    if not card then return false end
    K.waiting = false
    local issues = {}
    for _, i in ipairs(card.issues or {}) do issues[i.slot] = i.what end
    p.armory.title:SetText("ARMORY  " .. T().text("ink", name:upper()))
    p.armory.right:SetText(card.gearDate and ("seen " .. card.gearDate) or "no gear seen")
    for i, row in ipairs(p.gear.rows) do
        local slot = S().SLOTS[i]
        local g = card.gear and card.gear[i]
        local id = g and tonumber(g[1]) or 0
        if id ~= 0 then
            local item, q = K.Item(id)
            SetRow(row, slot, { slot, item, g[2], issues[slot] or "" },
                { "muted", QUALITY[q or 1] or "ink", "ink2", "warn" })
        else
            SetRow(row, slot, { slot, card.gear and "-" or "", "", "" }, { "muted", "muted", "muted", "muted" })
        end
    end

    local nights = #S().Dates()
    local pct = nights > 0 and math.floor(100 * #card.attended / nights + 0.5) or 0
    p.attLine:SetText(("%d of %d nights   %d%%"):format(#card.attended, nights, pct))
    p.attLine:SetTextColor(rgb(pct >= 75 and "good" or (pct >= 50 and "gold" or "warn")))
    local strip = K.Strip(card, K.STRIP)
    for i, sq in ipairs(p.strip) do
        local s = strip[i]
        if s then Fill(sq, s.earned and "good" or "line2") sq:Show() else sq:Hide() end
    end
    p.att.right:SetText(strip[1] and (strip[1].date .. " ->") or "")

    local l = card.last
    local lines = {}
    if l then
        local pulls = l.pulls or 0
        local function of(n) return ("%d of %d pulls"):format(n or 0, pulls) end
        lines = {
            { "flask      " .. of(l.flask), (l.flask or 0) > 0 and "good" or "warn" },
            { "elixirs    " .. of(l.elixir), (l.elixir or 0) > 0 and "good" or "ink2" },
            { "food       " .. of(l.food), (l.food or 0) > 0 and "good" or "warn" },
            { "weapon     " .. of(l.weapon), (l.weapon or 0) > 0 and "good" or "warn" },
            { ("potions    %d that night, %d on record"):format(l.pots or 0, card.pots or 0), "ink" },
            { ("deaths     %d that night, %d on record"):format(l.deaths or 0, card.deaths or 0),
              (card.deaths or 0) > 0 and "warn" or "good" },
        }
        p.cons.right:SetText(l.date)
    else
        p.cons.right:SetText("")
        lines = { { "no pulls on record", "muted" } }
    end
    for i, fs in ipairs(p.consLines) do
        local e = lines[i]
        fs:SetText(e and e[1] or "")
        if e then fs:SetTextColor(rgb(e[2])) end
    end

    local loot, have = K.Loot(name)
    p.loot.right:SetText(have and (#loot .. " item(s)") or "")
    for i, fs in ipairs(p.lootLines) do
        local e = loot[i]
        if e then
            local item, q = K.Item(e.item)
            fs:SetText(item .. ((e.boss and e.boss ~= "") and T().text("muted", "  " .. e.boss) or ""))
            fs:SetTextColor(rgb(QUALITY[q or 1] or "ink"))
        elseif i == 1 then
            fs:SetText(have and "nothing awarded in BiS Loot" or "BiS Loot has not run on this client")
            fs:SetTextColor(rgb("muted"))
        else
            fs:SetText("")
        end
    end
    return true
end

local function PaintBoss(p, name)
    local pg = S().Bosses()[name]
    if not pg then return false end
    p.stats.title:SetText("BOSS  " .. T().text("ink", name:upper()))
    local pulls = pg.kills + pg.wipes
    local lines = {
        { ("kills        %d"):format(pg.kills), pg.kills > 0 and "good" or "muted" },
        { ("wipes        %d"):format(pg.wipes), pg.wipes > 0 and "warn" or "ink2" },
        { ("kill rate    %d%%"):format(pulls > 0 and math.floor(100 * pg.kills / pulls + 0.5) or 0), "ink" },
        { ("fastest      %s"):format(K.Clock(pg.best)), "gold" },
        { ("first kill   %s"):format(pg.first or "not yet"), "ink" },
        { ("nights dead  %d"):format(#pg.nights), "ink" },
    }
    for i, fs in ipairs(p.statLines) do
        fs:SetText(lines[i][1])
        fs:SetTextColor(rgb(lines[i][2]))
    end
    for i, fs in ipairs(p.nightLines) do
        local d = pg.nights[#pg.nights - i + 1]
        fs:SetText(d or (i == 1 and "never killed" or ""))
        fs:SetTextColor(rgb(d and "ink" or "muted"))
    end
    local who = {}
    for n, c in pairs(pg.killers) do who[#who + 1] = { n, c } end
    table.sort(who, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    local off = Scroll(p.grid, #who)
    p.killers.right:SetText(("%d raiders"):format(#who) .. Showing(p.grid))
    for i, row in ipairs(p.grid.rows) do
        local w = who[i + off]
        if w then SetRow(row, w[1], { w[1], w[2] }, { "ink", "good" }) else SetRow(row, nil, {}) end
    end
    return true
end

function K.Paint()
    local f = K.frame
    if not f then return end
    for name, p in pairs(f.pages) do if name ~= K.page then p:Hide() end end
    local p = f.pages[K.page]
    if K.page == "raiders" then PaintRaiders(p)
    elseif K.page == "bosses" then PaintBosses(p)
    elseif K.page == "raider" then PaintRaider(p, K.key)
    elseif K.page == "boss" then PaintBoss(p, K.key)
    end
    p:Show()
    -- the tab you are on is lit; a card lights the list it belongs to
    local on = (K.page == "raider" and "raiders") or (K.page == "boss" and "bosses") or K.page
    for name, b in pairs(f.keys) do
        Fill(b.bg, name == on and "accentSoft" or "sunken")
        b.fs:SetTextColor(rgb(name == on and "gold" or "ink"))
    end
    f.tick:SetText(K.TickerText())
    f.tickW = f.tick:GetStringWidth() or 0
end

--------------------------------------------------------------------
-- commands
--------------------------------------------------------------------

function K.Open(page, key)
    -- a different boss starts its killers list at the top; the two big lists keep their place
    local p = K.frame and K.frame.pages[page]
    if p and p.grid and page == "boss" and key ~= K.key then p.grid.offset = 0 end
    K.page, K.key = page, key
    K.Paint()
end

--- Run a typed line (or a key). Returns what it did, for the suite.
function K.Go(line)
    local kind, key = K.Parse(line, S().Cards(), S().Bosses())
    if kind == "log" then
        if ns.U and ns.U.Show then ns.U.Show() end
        return "log"
    end
    if kind == "raiders" or kind == "bosses" then
        K.Open(kind)
        Say(kind == "raiders" and "every raider, best attendance first - click one, or type a name"
            or "every boss - click one, or type a name")
        return kind
    end
    if kind == "raider" then
        K.Open("raider", key)
        Say(("%s <RAIDER>"):format(key:upper()), "accent")
        if ns.X and ns.X.WantGear then ns.X.WantGear(key) end    -- a newer armory from an officer?
        return kind, key
    end
    if kind == "boss" then
        K.Open("boss", key)
        Say(("%s <BOSS>"):format(key:upper()), "accent")
        return kind, key
    end
    local what = tostring(line or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if what ~= "" then
        local offer = key or {}
        Say(#offer > 0 and ("no raider or boss called %s - did you mean %s?"):format(what, table.concat(offer, ", "))
            or ("no raider or boss called %s"):format(what), "warn")
    end
    return nil
end

function K.Show(page, key)
    local f = K.Build()
    if not f then return end
    f:Show()
    -- in front, whole, and back in front when clicked (the log window does the same - Window.lua)
    if f.SetToplevel then f:SetToplevel(true) end
    if f.Raise then f:Raise() end
    if f.con then f.con:Say("guild record", "accent") end
    if page then K.Go(page) elseif not K.page then K.Go("raiders") else K.Paint() end
    f.cmd:SetFocus()
    return f
end

function K.Hide()
    if K.frame then
        K.frame.cmd:ClearFocus()
        K.frame:Hide()
    end
end

function K.Toggle()
    if K.frame and K.frame:IsShown() then K.Hide() else K.Show() end
end
