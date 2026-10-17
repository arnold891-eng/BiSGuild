--[[
  BiSGuild :: Core/Logins.lua - "X just logged in - invite?"

  Arn, 16 Oct 2026: "if the addons can see if someone logged in and they are on the roster, makes the
  invite button pulse or a window pop up that says invite this <raider name> that just logged in?"

  WHO COUNTS: somebody on the pasted roster (Core/Invite.lua), in the guild, not signed Absence or
  Bench. WHEN: only while it can help - a roster is pasted, and you lead or assist your group (or are
  on your own, about to form one). Otherwise nothing happens: no pop-up on a random Wednesday.

  HOW IT KNOWS: the client's own "X has come online." (ERR_FRIEND_ONLINE_SS, the guild's login line),
  and the guild roster's online flags compared update to update - the backup for a player who turned
  that chat line off. One person is announced once a minute at most, whichever source is first.

  WHAT IT SHOWS: one small window, 1.43:1, stacking whoever logged in - a row each with Invite, then
  Invite all and Not now - and the terminal's INVITE ONLINE buttons pulse while anyone waits. No
  sound. `/bisg logins off` stops all of it.
]]
local ADDON, ns = ...
local K = ns.K

local L = {}
ns.Login = L

L.W, L.H = 280, 196          -- 1.43:1
L.ROWS = 5
L.AGAIN = 60                 -- seconds before the same person is announced again
L.waiting = {}               -- { { name, signed, at } } in the order they came online
L.told = {}                  -- key -> GetTime() last announced

local function Now() return GetTime and GetTime() or 0 end
local function hidden(v)
    if v == nil or not issecretvalue then return false end
    local ok, yes = pcall(issecretvalue, v)
    return (not ok) or yes == true
end

function L.On() return ns.DB().logins ~= false end

--- Is now a time to offer invites? A roster to compare with, the say over the group - and, when the
--- roster is a Raid-Helper event with a start time, raid time: from L.BEFORE before the start to
--- L.AFTER after it (Arn, 16 Oct: "does the json say what time the raid is supposed to start?"), so
--- last week's roster left pasted never pops up on the wrong night.
L.BEFORE, L.AFTER = 2 * 3600, 4 * 3600
function L.Armed()
    if not L.On() or not ns.Inv then return false end
    local text = ns.DB().roster
    if type(text) ~= "string" or text == "" then return false end
    local e = ns.Inv.Event(text)                    -- read once per paste, then only looked up
    local now = GetServerTime and GetServerTime()
    if e and e.start and now and (now < e.start - L.BEFORE or now > e.start + L.AFTER) then return false end
    return ns.Inv.Leads()
end

--- This person's roster row, if they are one we would invite (in the guild, not absent or bench).
function L.OnRoster(name)
    local key = K.NameKey(name)
    for _, r in ipairs(ns.Inv.Read(ns.DB().roster)) do
        if r.key == key and r.member and not (r.standing and ns.Inv.OUT[r.standing]) then return r end
    end
    return nil
end

--- Somebody came online. True when they were announced.
function L.CameOnline(name)
    if type(name) ~= "string" or hidden(name) or not L.Armed() then return false end
    local r = L.OnRoster(name)
    if not r then return false end
    if ns.Inv.Here()[r.key] then return false end
    local last = L.told[r.key]
    if last and Now() - last < L.AGAIN then return false end
    L.told[r.key] = Now()
    for _, w in ipairs(L.waiting) do if w.key == r.key then return false end end
    L.waiting[#L.waiting + 1] = { name = r.member.name, key = r.key, signed = r.signed, class = r.member.class }
    L.Show()
    return true
end

--- Who is still waiting: not yet with you. Joined people drop off by themselves.
function L.Prune()
    local here, keep = ns.Inv.Here(), {}
    for _, w in ipairs(L.waiting) do if not here[w.key] then keep[#keep + 1] = w end end
    L.waiting = keep
    return #keep
end

function L.Pulsing() return #L.waiting > 0 end

--------------------------------------------------------------------
-- the two ways to hear it
--------------------------------------------------------------------

local function Pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.-)")
    return "^" .. p .. "$"
end

--- The client's "|Hplayer:Name|h[Name]|h has come online." - the name, or nil.
function L.FromChat(msg)
    if type(msg) ~= "string" or hidden(msg) then return nil end
    local pat = Pattern(_G.ERR_FRIEND_ONLINE_SS) or "^|Hplayer:(.-)|h%[.-%]|h has come online%.$"
    local who = msg:match(pat)
    if not who then return nil end
    return (who:gsub("%-.*$", ""))
end

--- The roster's online flags, compared with last time: who turned online since.
L.lastOnline = nil
function L.FromRoster()
    K._guildDirty = true
    local now, came = {}, {}
    for key, m in pairs(K.Guild().members) do
        if m.online then
            now[key] = true
            if L.lastOnline and not L.lastOnline[key] then came[#came + 1] = m.name end
        end
    end
    L.lastOnline = now
    return came
end

--------------------------------------------------------------------
-- the window
--------------------------------------------------------------------

function L.Build()
    if L.frame then return L.frame end
    local ui = K.ui
    if not (ui and CreateFrame) then return nil end
    local f = CreateFrame("Frame", "BiSGuildLogins", UIParent)
    L.frame = f
    f:SetSize(L.W, L.H)
    local pos = ns.DB().loginsPos
    if type(pos) == "table" and pos[1] then f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos[1], pos[2])
    else f:SetPoint("TOP", UIParent, "TOP", 0, -140) end
    f:SetFrameStrata("HIGH")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local l, t = self:GetLeft(), self:GetTop()
        local h = UIParent and UIParent.GetHeight and UIParent:GetHeight()
        if l and t and h then ns.DB().loginsPos = { math.floor(l + 0.5), math.floor(t - h + 0.5) } end
    end)
    f:Hide()
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    ui.Fill(bg, "bg", 0.96)
    local edge = f:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT", 0, 0)
    edge:SetPoint("TOPRIGHT", 0, 0)
    edge:SetHeight(2)
    ui.Fill(edge, "accent")
    f.title = ui.Text(f, 12, "accent")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.title:SetText("BiS> just logged in")
    f.sub = ui.Text(f, 10, "muted")
    f.sub:SetPoint("TOPLEFT", 10, -24)
    f.sub:SetWidth(L.W - 20)

    local function Btn(parent, label, w, fn)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(w, 18)
        local bbg = b:CreateTexture(nil, "BACKGROUND")
        bbg:SetAllPoints()
        ui.Fill(bbg, "accentSoft")
        local hi = b:CreateTexture(nil, "ARTWORK")
        hi:SetAllPoints()
        ui.Fill(hi, "accent", 0.28)
        hi:Hide()
        b:SetScript("OnEnter", function() hi:Show() end)
        b:SetScript("OnLeave", function() hi:Hide() end)
        b.fs = ui.Text(b, 11, "gold", "CENTER")
        b.fs:SetPoint("CENTER", 0, 0)
        b.fs:SetText(label)
        b:SetScript("OnClick", fn)
        return b
    end
    f.rows = {}
    for i = 1, L.ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetPoint("TOPLEFT", 8, -40 - (i - 1) * 21)
        row:SetSize(L.W - 16, 20)
        row.name = ui.Text(row, 12, "ink")
        row.name:SetPoint("LEFT", 2, 0)
        row.name:SetWidth(L.W - 100)
        row.invite = Btn(row, "Invite", 64, function()
            local w = row.who
            if w then ns.Inv.One(w.name) L.Done(w.key) end
        end)
        row.invite:SetPoint("RIGHT", 0, 0)
        f.rows[i] = row
    end
    f.all = Btn(f, "Invite all", 120, function()
        for _, w in ipairs(L.waiting) do ns.Inv.One(w.name) end
        L.waiting = {}
        L.Paint()
    end)
    f.all:SetPoint("BOTTOMLEFT", 8, 8)
    f.later = Btn(f, "Not now", 90, function() L.waiting = {} L.Paint() end)
    f.later:SetPoint("BOTTOMRIGHT", -8, 8)
    return f
end

function L.Done(key)
    local keep = {}
    for _, w in ipairs(L.waiting) do if w.key ~= key then keep[#keep + 1] = w end end
    L.waiting = keep
    L.Paint()
end

function L.Paint()
    local f = L.frame
    if not f then return end
    L.Prune()
    if #L.waiting == 0 then f:Hide() return end
    local colours = _G.RAID_CLASS_COLORS
    for i, row in ipairs(f.rows) do
        local w = L.waiting[i]
        row.who = w
        if w then
            local cc = w.class and colours and colours[w.class]
            row.name:SetText(w.signed and (w.name .. "  " .. ns.T.text("muted", w.signed)) or w.name)
            if cc then row.name:SetTextColor(cc.r, cc.g, cc.b) else row.name:SetTextColor(K.ui.rgb("ink")) end
            row:Show()
        else
            row:Hide()
        end
    end
    local more = #L.waiting - L.ROWS
    f.sub:SetText(("on the roster%s - %s"):format(more > 0 and (" (+%d more)"):format(more) or "",
        ns.Inv.Tools() and "invites go through BiS Tools" or "click to invite"))
    f.all.fs:SetText(("Invite all (%d)"):format(#L.waiting))
    f:Show()
end

function L.Show()
    L.Build()
    L.Paint()
end

--------------------------------------------------------------------
-- wiring
--------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_SYSTEM")
ev:RegisterEvent("GUILD_ROSTER_UPDATE")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:SetScript("OnEvent", function(_, event, msg)
    if event == "GROUP_ROSTER_UPDATE" then
        if L.frame and L.frame:IsShown() then L.Paint() end      -- whoever joined drops off
        return
    end
    -- the roster compared only while armed (LEAN: a big guild's roster walk on every roster event,
    -- all week, for a pop-up that only matters on raid night, would be waste). The first armed walk
    -- only takes the baseline - nobody is "just logged in" because the window opened.
    if event == "GUILD_ROSTER_UPDATE" then
        if not L.Armed() then L.lastOnline = nil return end
        for _, name in ipairs(L.FromRoster()) do L.CameOnline(name) end
        return
    end
    if not L.Armed() then return end                              -- cheap first: most system lines
    local who = L.FromChat(msg)
    if who then L.CameOnline(who) end
end)
