-- LibBiSComm-1.0
-- The shared BiS addon channel. EMBEDDED in every BiS addon, not installed as
-- one: a client with a single BiS addon carries the whole layer, which is the
-- entire point. Highest version present wins and upgrades in place.
--
--   Wire format:  PROTO|MOD|CMD|a1|a2|...
--
-- Every field is escaped on the wire (minor 6) so a payload may carry "|" - an
-- item link does: "\1" -> "\1\1", "|" -> "\1\2", undone on receipt. A field
-- with neither byte is sent as-is, so CORE and SUMMON traffic is byte-identical
-- to minor 5 and older copies still read it.
--
-- MOD is what lets unrelated addons share one prefix. An unknown MOD or CMD is
-- ignored in silence, so a client running an older or newer BiS addon is never
-- half-understood -- the same additive rule that let Rez fold into Innervate.
--
-- CORE is deliberately three commands. It carries only what a client knows
-- about ITSELF and nobody else can see:
--
--   HI    |libMinor|addonsBlob|known     who is here, running what
--   ASK   |what                          somebody wants WHERE (summoner)
--   WHERE |in|type|instName|zone|x|y|map am I inside an instance, and where
--   SUM   |state|summoner|area|left      OFFER / OK / NO on a summon offer
--
-- House rules, in the lib so they cannot drift addon to addon:
--   * draws nothing, prints nothing (one /biscomm for status and the off switch;
--     /bis belongs to LoonBestInSlot on the raid's clients - minor 4 gave it back)
--   * no periodic chatter: WHERE pushes on a real change, otherwise it answers
--   * every host callback is pcall'd -- a lib fault cannot kill the addon
--   * off means silent AND deaf

-- minor 9 (7 Oct 2026): the cost pass - one roster walk per roster tick, the prefix asked first
-- minor 10 (12 Oct 2026): Forever's own rules (debt 37) - re-announce when the chat lockdown lifts,
-- the realm's outgoing-message block, RAID only when UnitInRaid says so, a per-sender inbox limit
-- minor 11 (14 Oct 2026): no hook on C_SummonInfo.ConfirmSummon on Forever - a hooked Blizzard
-- method can break the client until relaunch (Overlord 2.0, seen 11-12 Oct); summons are TBC's
-- minor 12 (14 Oct 2026): SPOT - where guildmates are, for BiS Tools' map: every embedder shares
-- your spot on the GUILD channel while you move (cascading 15/30/60 s by guild size), one switch
-- for all of them (/biscomm share on|off), and lib.spots for any addon to draw
local MAJOR, MINOR = "LibBiSComm-1.0", 14

local lib = _G.LibBiSComm
if lib and (lib.MINOR or 0) >= MINOR then return end   -- an equal or newer copy won
lib = lib or {}
_G.LibBiSComm = lib
lib.MAJOR, lib.MINOR = MAJOR, MINOR

-- Upgrading in place: everything the old copy learned survives. Wiping these
-- on a reload-in-place would drop the raid off every grid at once.
lib.peers     = lib.peers     or {}    -- name -> peer table
lib.handlers  = lib.handlers  or {}    -- mod -> cmd -> fn
lib.callbacks = lib.callbacks or {}    -- event -> { fn, ... }
lib.addons    = lib.addons    or {}    -- name -> version, what this client runs
lib.guildMods = lib.guildMods or {}    -- mod -> true: may ride the GUILD channel (minor 6)
if lib.enabled == nil then lib.enabled = true end

lib.PREFIX = "BiS"
lib.PROTO  = 1

local PREFIX, PROTO, SEP = lib.PREFIX, lib.PROTO, "|"

local ANSWER_MIN, ANSWER_JITTER = 1, 2   -- 1-3s: 25 clients must not answer as one
local HI_THROTTLE    = 5
local WHERE_THROTTLE = 3
local ASK_COALESCE   = 3
local OFFER_FALLBACK = 120               -- summon offer lifetime if the API is quiet

--------------------------------------------------------------------
-- small helpers (self-contained: the lib must work in an addon that has none)
--------------------------------------------------------------------

local function Now()
    if GetTime then return GetTime() end
    return 0
end

local function After(delay, fn)
    if C_Timer and C_Timer.After then C_Timer.After(delay, fn); return true end
    return false
end

-- A VALUE THE CLIENT WILL NOT LET US LOOK AT (4 Oct 2026). On WoW Forever a string handed to an
-- addon can be a SECRET VALUE: it is truthy, so `if not v` lets it straight through, and it errors
-- the moment anything reads it - a match, a comparison, or being used as a table key.
--
-- Feature-detected, never version-checked: Forever carries a modern API behind a 1.60 interface
-- number, so "does this client have the call" is the only honest question. A client without it has
-- no secret values and this is always false.
local function Secret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end
lib.Secret = Secret

-- GUARDED HERE, so every caller is guarded at once. Short() takes names from UnitName() as well as
-- from the wire, and on this client both can come back secret inside an instance. A nil is the
-- honest answer: we do not know who that is, and every caller already handles not knowing.
local function Short(name)
    if name == nil or Secret(name) or type(name) ~= "string" then return nil end
    return string.match(name, "^([^%-]+)") or name
end
lib.Short = Short

--- A unit's WHOLE name, as its addon messages arrive (minor 14). Forever measured, 18 Oct 2026 (Arn's
--- /run): UnitName("player") is "Chain" while his messages come from "Chain Healz" - so minor 13 and
--- before took its own GUILD echo for a guildmate (Arn on his own map twice, "you'n Healz") and could
--- never match a party member's "Name Surname" to a unit. GetUnitName(unit, false) carries the
--- surname (solved.md, 13 Oct); UnitName is the fallback where it is missing or hidden.
local function FullName(unit)
    if GetUnitName then
        local ok, n = pcall(GetUnitName, unit, false)
        if ok and n ~= nil and not Secret(n) and type(n) == "string" and n ~= "" then return Short(n) end
    end
    return Short(UnitName and UnitName(unit) or nil)
end
lib.FullName = FullName

local function PlayerName()
    return FullName("player")
end

--- A name's first word: what UnitName gives on Forever ("Chain" of "Chain Healz").
local function First(name)
    return name and (string.match(name, "^(%S+)") or name) or nil
end

local function InGroup()
    if IsInRaid and IsInRaid() then return true end
    if IsInGroup and IsInGroup() then return true end
    return false
end

-- A dungeon-finder group silently DROPS "RAID"/"PARTY" addon messages. Summon
-- work happens at instance doorsteps, which is exactly where this bites.
local function GroupChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    -- RAID ONLY WHEN THE CLIENT SAYS YOU ARE IN ONE (minor 10). Overlord found IsInRaid() can stay
    -- true right after leaving an instance while RAID refuses every message (Sync.lua); UnitInRaid
    -- on yourself is the stricter answer. Asked secret-guarded; a hidden answer is "not sure", and
    -- PARTY still reaches the people beside you.
    if IsInRaid and IsInRaid() then
        local sure = true
        if UnitInRaid then
            local ok, r = pcall(UnitInRaid, "player")
            sure = ok and not Secret(r) and r ~= nil and r ~= false
        end
        if sure then return "RAID" end
    end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end
lib.GroupChannel = GroupChannel

local function ForEachMember(cb)
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if IsInRaid and IsInRaid() then
        for i = 1, n do
            local unit = "raid" .. i
            if UnitExists and UnitExists(unit) then cb(unit, FullName(unit)) end
        end
    else
        cb("player", PlayerName())
        for i = 1, math.max(0, n - 1) do
            local unit = "party" .. i
            if UnitExists and UnitExists(unit) then cb(unit, FullName(unit)) end
        end
    end
end

--- The unit of a name: the whole name exactly, or - for a first name alone (a caller holding UnitName's
--- answer) - the one member whose first name it is. Two members sharing it: nobody, never a guess.
local function UnitOf(name)
    name = Short(name)
    if not name then return nil end
    if name == PlayerName() then return "player" end
    local found, byFirst, firsts = nil, nil, 0
    local bare = not string.find(name, " ", 1, true)
    ForEachMember(function(unit, n)
        if found or not n then return end
        if n == name then found = unit
        elseif bare and First(n) == name then byFirst, firsts = unit, firsts + 1 end
    end)
    if found then return found end
    if firsts == 1 then return byFirst end
    return nil
end
lib.UnitOf = UnitOf

-- WindfuryComm++ shipped `tonumber(string.gsub(v, ".", "0"))`: "." matches every
-- character, so "2.1.3" became 0 for everybody and its update notice has never
-- once fired. Parse the numbers out; never pattern-mangle a version.
function lib.VersionCmp(a, b)
    local function parts(v)
        local t = {}
        for n in string.gmatch(tostring(v or ""), "(%d+)") do t[#t + 1] = tonumber(n) end
        return t
    end
    local pa, pb = parts(a), parts(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

function lib.VersionGT(a, b) return lib.VersionCmp(a, b) > 0 end

-- MINOR 6: "|" inside a field. SEP is "|", and an item link is full of them, so a
-- field is escaped before it is joined and unescaped after the split. Two bytes
-- for "|", not one: with "|" -> "\1" alone, a field "||" and a field "\1" would
-- both go out as "\1\1" and could never be told apart again.
local ESC, PIPE = "\1", "\2"

local function escape(s)
    if not string.find(s, "[\1|]") then return s end
    return (string.gsub(s, "[\1|]", function(ch)
        if ch == ESC then return ESC .. ESC end
        return ESC .. PIPE
    end))
end

local function unescape(s)
    if not string.find(s, ESC, 1, true) then return s end
    return (string.gsub(s, "\1(.)", function(ch)
        if ch == ESC then return ESC end
        if ch == PIPE then return SEP end
        return ch
    end))
end
lib._escape, lib._unescape = escape, unescape

local function split(msg)
    local out, i = {}, 1
    for piece in string.gmatch(msg .. SEP, "([^" .. SEP .. "]*)%" .. SEP) do
        out[i] = unescape(piece); i = i + 1
    end
    return out
end
lib._split = split

-- MINOR 6: guild membership for guard 3 on the GUILD channel. Rebuilt lazily after
-- GUILD_ROSTER_UPDATE; a name the roster does not list is refused, never guessed.
function lib:InGuild(name)
    name = Short(name)
    if not name then return false end
    if not (IsInGuild and IsInGuild()) then return false end
    if self._guildDirty ~= false or not self._guild then
        local roster = {}
        local n = (GetNumGuildMembers and GetNumGuildMembers()) or 0
        for i = 1, n do
            local member = GetGuildRosterInfo and GetGuildRosterInfo(i)
            if member then roster[Short(member)] = true end
        end
        self._guild, self._guildDirty = roster, false
    end
    return self._guild[name] == true
end

local function fire(event, ...)
    for _, fn in ipairs(lib.callbacks[event] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then lib._lastError = err end   -- a host bug must not stop the next host
    end
end

--------------------------------------------------------------------
-- peers
--------------------------------------------------------------------

local function peer(name)
    local p = lib.peers[name]
    if not p then
        p = { name = name, addons = {}, where = nil, summon = nil }
        lib.peers[name] = p
    end
    return p
end

--- The peers key for a name (minor 14): the whole name as it arrived, or a first name alone when one
--- peer has it (a caller holding UnitName's "Bree" for the peer "Bree Stone").
function lib:PeerKey(name)
    name = Short(name or "")
    if not name or name == "" then return nil end
    if self.peers[name] then return name end
    if string.find(name, " ", 1, true) then return nil end
    local hit
    for k in pairs(self.peers) do
        if First(k) == name then
            if hit then return nil end                       -- two of them: never a guess
            hit = k
        end
    end
    return hit
end
function lib:Peer(name) local k = self:PeerKey(name) return k and self.peers[k] or nil end
function lib:Peers() return self.peers end

function lib:Count()
    local n = 0
    for _ in pairs(self.peers) do n = n + 1 end
    return n
end

-- Does this group member run any BiS addon? Everything downstream hangs off
-- this: a name that answers is fact, a name that does not is a guess, and the
-- two must never look alike in a UI.
function lib:HasLib(name)
    name = Short(name or "")
    local me = PlayerName()
    if name == me or (name == First(me) and not string.find(name or "", " ", 1, true)) then return true end
    return self:PeerKey(name) ~= nil
end

-- ONE WALK OF THE ROSTER, NOT ONE PER PEER (7 Oct 2026). This asked UnitOf about every peer,
-- and UnitOf walks the whole raid: ~1,000 roster questions a tick in a 25-man, ~4,700 in a 40,
-- on an event that comes in bursts. Walk once into a set, then look each peer up in it.
function lib:PurgeAbsent()
    local here = {}
    ForEachMember(function(_, n) if n and not Secret(n) then here[n] = true end end)
    local me = PlayerName()
    for name in pairs(self.peers) do
        if name ~= me and not here[name] then self.peers[name] = nil end
    end
end

--------------------------------------------------------------------
-- registration by host addons
--------------------------------------------------------------------

function lib:RegisterAddon(name, version)
    if not name then return end
    self.addons[name] = tostring(version or "?")
end

function lib:RegisterHandler(mod, cmd, fn)
    self.handlers[mod] = self.handlers[mod] or {}
    self.handlers[mod][cmd] = fn
end

-- MINOR 6: a MOD that may ride the GUILD channel (BiSLoot's LOOT). CORE never can:
-- HI / WHERE / SUM are about the group, and a guild line must not plant a peer.
function lib:RegisterGuildMod(mod)
    if not mod or mod == "CORE" then return false end
    self.guildMods[mod] = true
    return true
end

-- events: "PEER" (name, peer) | "WHERE" (name, where) | "SUM" (name, summon)
function lib:RegisterCallback(event, fn)
    self.callbacks[event] = self.callbacks[event] or {}
    table.insert(self.callbacks[event], fn)
end

function lib:Enabled() return self.enabled and true or false end

-- Off is silent AND deaf. A client that still listened while claiming to be off
-- would be the same lie as Innervate's closed window that kept a live drag strip.
function lib:SetEnabled(on)
    self.enabled = on and true or false
    if not self.enabled then
        self.peers = {}
        lib.peers = self.peers
    end
    return self.enabled
end

--------------------------------------------------------------------
-- send / receive
--------------------------------------------------------------------

local GROUP_CHANNELS = { RAID = true, PARTY = true, INSTANCE_CHAT = true }

-- The group: RAID / PARTY / INSTANCE_CHAT, whichever this client is in.
function lib:Send(mod, cmd, ...)
    return self:SendTo(nil, mod, cmd, ...)
end

-- MINOR 6: an explicit channel. nil = the group (as Send). "GUILD" only for a MOD
-- registered with RegisterGuildMod - the guild reaches four raids at once, which is
-- what BiSLoot's ledger sync needs and exactly what CORE must never do.
function lib:SendTo(channel, mod, cmd, ...)
    if not self.enabled then return false end
    if not mod or not cmd then return false end
    local chan
    if channel == nil then
        chan = GroupChannel()
        if not chan then return false end
    elseif channel == "GUILD" then
        if not self.guildMods[mod] then
            self._lastError = "not guild-scoped: " .. tostring(mod)
            return false
        end
        if not (IsInGuild and IsInGuild()) then return false end
        chan = "GUILD"
    elseif GROUP_CHANNELS[channel] then
        chan = channel
    else
        self._lastError = "channel not allowed: " .. tostring(channel)
        return false
    end
    local parts = { PROTO, escape(tostring(mod)), escape(tostring(cmd)) }
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v == nil then v = "" elseif type(v) == "boolean" then v = v and "1" or "0" end
        parts[#parts + 1] = escape(tostring(v))
    end
    local msg = table.concat(parts, SEP)
    -- The client drops anything past 255 bytes and never tells the sender. Say
    -- so instead of losing it silently. Counted AFTER escaping: that is what goes out.
    if #msg > 250 then
        self._lastError = "message too long: " .. mod .. "/" .. cmd .. " " .. #msg
        return false
    end
    return self:_Queue(msg, chan)
end

--------------------------------------------------------------------
-- THE OUTBOX (minor 8, 6 Oct 2026)
--
-- Until minor 7 every Send went straight to the client and its answer was never read. Overlord
-- measured the client on Forever (27 Sep): about ONE addon message a second PER PREFIX, shared by
-- group, raid and channel together; past that the send answers a throttle code and the message
-- simply does not leave. Eight BiS addons share this lib's one prefix, so they share that one
-- message a second - and a fight's worth of HI, WHERE and answers was being lost with no error
-- anywhere. Chat lockdown (InChatMessagingLockdown) refuses everything for a while besides.
--
-- So: one queue for the whole client (the lib is loaded ONCE however many addons embed it), one
-- message per SEND_GAP, the client's answer read every time. A throttle puts the message back at
-- the head and waits; lockdown holds the queue until it lifts; any other refusal is dropped and
-- said in _lastError. An old message is thrown away rather than sent late - a WHERE from half a
-- minute ago is a lie about where somebody is. The same line already waiting is not queued twice.
--
-- Send still answers true for "accepted", which now means "queued": the first one in a quiet
-- second still leaves at once.
--------------------------------------------------------------------

local SEND_GAP   = 1.0    -- seconds between two of OUR messages; the client allows about one.
                          -- lib.sendGap overrides it: a host SUITE about something else may set 0
local SEND_TTL   = 30     -- a message older than this is stale and dropped, not sent
local OUTBOX_MAX = 40     -- past this a new message is refused, not queued

lib.outbox = lib.outbox or {}
lib.nextSendAt = lib.nextSendAt or 0
lib.sentCount, lib.refusedCount = lib.sentCount or 0, lib.refusedCount or 0

-- The client's answer, by NAME where it has the enum (our census does not record Enum tables, so
-- Forever's numbers are unverified). Retail's numbers, which FojjiCore retries on, are the fallback.
local function ResultKind(r)
    if r == nil or r == true or r == 0 then return "sent" end     -- 2.5.x answers nothing
    if Secret(r) then return "sent" end
    if r == false then return "again" end
    local E = Enum and Enum.SendAddonMessageResult
    local throttle, channel, general = 3, 8, 9
    if type(E) == "table" then
        throttle = E.AddonMessageThrottle or throttle
        channel  = E.ChannelThrottle or channel
        general  = E.GeneralError or general
    end
    if r == throttle or r == channel or r == general then return "again" end
    return "refused"
end

local function clear(t) for i = #t, 1, -1 do t[i] = nil end end

local function ChatLocked()
    local f = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    if not f then return false end
    local ok, v = pcall(f)
    if not ok then return false end
    -- a HIDDEN answer about the lockdown is itself a sign of one (minor 10; ForeverAuras treats any
    -- unreadable restriction check as "restricted"): hold, and let the TTL drop what goes stale
    if Secret(v) then return true end
    return v and true or false
end
lib.ChatLocked = ChatLocked

--- THE REALM'S OWN "BLOCK" (minor 10) - AN ANSWER, NOT A GATE SINCE MINOR 13. Measured on Forever,
--- 18 Oct 2026 (Arn's /run): C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() says plain TRUE while
--- C_ChatInfo.SendAddonMessage("BiS", "test", "GUILD") answers 0 and the message arrives. Minor 10-12
--- held the outbox on it - and so sent NOTHING on Forever (Arn's lib: "sent 0 ... err dropped a stale
--- message"): no spots, no GLOG, no BiS> now, no peers. The send's own result is the client's real
--- word (ResultKind: throttle / general error are retried, anything else is named); this question is
--- only reported, in /biscomm.
local function OutgoingBlocked()
    local f = C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
    if not f then return false end
    local ok, v = pcall(f)
    if not ok then return false end
    if Secret(v) then return true end
    return v and true or false
end
lib.OutgoingBlocked = OutgoingBlocked

local function RawSend(msg, chan)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        return true, C_ChatInfo.SendAddonMessage(PREFIX, msg, chan)
    elseif SendAddonMessage then
        return true, SendAddonMessage(PREFIX, msg, chan)
    end
    return false
end

function lib:_Queue(msg, chan)
    local q = self.outbox
    for _, m in ipairs(q) do
        if m.msg == msg and m.chan == chan then return true end    -- already waiting
    end
    if #q >= OUTBOX_MAX then
        self._lastError = "outbox full: " .. #q .. " waiting"
        return false
    end
    q[#q + 1] = { msg = msg, chan = chan, at = Now() }
    self:_Pump()
    return true
end

function lib:_Arm(delay)
    if self._pumpArmed then return end
    if After(math.max(delay, 0.05), function() lib._pumpArmed = false; lib:_Pump() end) then
        self._pumpArmed = true
    end
end

function lib:_Pump()
    local q = self.outbox
    local gap = tonumber(self.sendGap) or SEND_GAP
    while #q > 0 do
        if not self.enabled then clear(q); return end
        local now = Now()
        -- the clock went BACKWARDS under us (a harness rewinding GetTime; the client never does):
        -- a wait longer than any backoff we set is not a wait, it is a broken clock - send now
        if self.nextSendAt - now > 2 * gap then self.nextSendAt = now end
        if q[1].at > now then q[1].at = now end
        if now - q[1].at > SEND_TTL then
            table.remove(q, 1)
            self._lastError = "dropped a stale message"
        elseif ChatLocked() then
            self:_Arm(SEND_GAP)
            return
        elseif now < self.nextSendAt then
            self:_Arm(self.nextSendAt - now)
            return
        else
            local m = q[1]
            local can, r = RawSend(m.msg, m.chan)
            if not can then clear(q); return end
            local kind = ResultKind(r)
            if kind == "again" then
                -- it did NOT leave: keep it at the head and back off a little further
                self.refusedCount = self.refusedCount + 1
                self.nextSendAt = now + 2 * gap
                self:_Arm(2 * gap)
                return
            end
            table.remove(q, 1)
            self.nextSendAt = now + gap
            if kind == "sent" then
                self.sentCount = self.sentCount + 1
            else
                self.refusedCount = self.refusedCount + 1
                self._lastError = "the client refused a message (" .. tostring(r) .. ")"
            end
        end
    end
end

lib.INBOX_BURST, lib.INBOX_RATE = 20, 2
lib.inbox = lib.inbox or {}
lib.droppedIn = lib.droppedIn or 0

--- May this sender's message in? A token bucket per sender, refilled by the clock.
function lib:_Admit(sender)
    local now = Now()
    local b = self.inbox[sender]
    if not b then b = { tokens = self.INBOX_BURST, at = now } self.inbox[sender] = b end
    if now > b.at then
        b.tokens = math.min(self.INBOX_BURST, b.tokens + (now - b.at) * self.INBOX_RATE)
    end
    b.at = now
    if b.tokens < 1 then
        self.droppedIn = self.droppedIn + 1
        return false
    end
    b.tokens = b.tokens - 1
    return true
end

--- THE LOCKDOWN LIFTED (minor 10). Messages that waited out a boss died at SEND_TTL, and every
--- peer's did too - so after every encounter the roster was as stale as the fight was long. On
--- the lift: send what is still waiting, and say HI - twice, a moment apart, because the others
--- come out of the lockdown a moment later than we do (LibSpecialization's way, EllesmereUI;
--- Overlord's catch-up burst). The short-answer rule keeps it from becoming 25 x 25.
function lib:OnRestrictionChanged()
    if ChatLocked() then return false end          -- (never the realm "block": see OutgoingBlocked)
    self:_Pump()
    if not InGroup() then return false end
    local first = 1 + math.random() * 2
    local function hi() if InGroup() then lib:Hi() end end
    if not After(first, hi) then hi() end
    After(first + 3, hi)
    return true
end

function lib:OnMessage(prefix, msg, channel, sender)
    if not self.enabled then return end
    -- EVERY ARGUMENT, BEFORE ANYTHING READS ONE (4 Oct 2026). CHAT_MSG_ADDON hands over four
    -- values and on this client any of them can be a secret: seen in a dungeon, where the client
    -- hides chat. A secret is truthy, so `not msg` never caught it - the error arrived further
    -- down, out of `split(msg)` or out of using the sender as a table key, and OnEvent does not
    -- pcall, so it landed on the player's screen as a red wall in the middle of a pull.
    --
    -- BiSMemories shipped 0.5.1 to fix exactly this shape one layer up, in CHAT_MSG_LOOT. It was
    -- still here underneath, in the lib seven addons embed. Found 4 Oct in FojjiCore's dungeon
    -- journal, which guards its text AND its sender - the sender being the half nobody here had
    -- thought of.
    --
    -- Nothing hidden is worth answering: a message we may not read is not a message, and a peer we
    -- may not name cannot be put in the table. Dropping it is the whole fix.
    -- the PREFIX first (7 Oct 2026, the cost pass): every addon's messages come through here, and
    -- a raid's worth of them is hundreds a second - one question decides "not ours", not four
    if Secret(prefix) or prefix ~= PREFIX then return end
    if Secret(msg) or Secret(channel) or Secret(sender) then return end
    if type(msg) ~= "string" then return end
    sender = Short(sender)
    if not sender then return end
    -- ONE PEER CANNOT FLOOD US (minor 10). A per-sender bucket: INBOX_BURST at once, then
    -- INBOX_RATE a second (Olympus admits 60 then 2/s; we are far quieter - nothing of ours sends
    -- more than a message a second). Past it the line is dropped before any parsing, and counted.
    if not self:_Admit(sender) then return end

    local p = split(msg)
    local proto, mod, cmd = tonumber(p[1] or ""), p[2], p[3]
    if not mod or not cmd then return end

    -- Guard 1: our framing only. A newer client's message parsed as ours would
    -- corrupt state rather than be rejected.
    if proto ~= PROTO then
        if proto and proto > PROTO then self._sawNewer = true end
        return
    end
    -- Guard 2: group channels only - or GUILD for a guild-scoped MOD (minor 6). A
    -- whisper from a stranger must not be able to plant a position or a summon state,
    -- and neither may a guild line: CORE is never guild-scoped.
    local guild = (channel == "GUILD")
    if channel and not GROUP_CHANNELS[channel] and not guild then return end
    if guild and not self.guildMods[mod] then return end
    -- Guard 3: a sender we can actually see - in the group, or for GUILD in the
    -- guild roster (minor 6).
    if sender ~= PlayerName() then
        if guild then
            if not self:InGuild(sender) then return end
        elseif not UnitOf(sender) then
            return
        end
    end
    -- Guard 4: my own echo. The client hands every group addon message back to
    -- its sender too; taking it would make me my own peer (MINOR 2 did: a
    -- summoner at the stone counted himself twice - Arn, 8 Sep). What I know
    -- about myself lives in self.where / self.summon, never in peers.
    if sender == PlayerName() then return end

    -- A guild sender is not a group peer: grids and summon lists are about the
    -- group, and forty officers across four raids must not appear on them.
    if not guild then
        local isNew = (self.peers[sender] == nil)
        local pr = peer(sender)
        pr.seen = Now()
        if isNew then fire("PEER", sender, pr) end
    end

    local args = {}
    for i = 4, #p do args[i - 3] = p[i] end

    local core = self._core[cmd]
    if mod == "CORE" and core then
        local ok, err = pcall(core, sender, unpack(args))
        if not ok then self._lastError = err end
        return
    end
    -- Guard 4: unknown MOD or CMD is ignored, not guessed at.
    local h = self.handlers[mod] and self.handlers[mod][cmd]
    if h then
        local ok, err = pcall(h, sender, unpack(args))
        if not ok then self._lastError = err end
    end
end

--------------------------------------------------------------------
-- CORE: identity
--------------------------------------------------------------------

function lib:AddonsBlob()
    local out = {}
    for name, ver in pairs(self.addons) do out[#out + 1] = name .. "=" .. ver end
    table.sort(out)
    return table.concat(out, ",")
end

function lib:Hi()
    if not InGroup() then return false end
    return self:Send("CORE", "HI", self.MINOR, self:AddonsBlob(), self:Count())
end

lib._core = {}

lib._core.HI = function(sender, minor, blob, known)
    local pr = peer(sender)
    pr.libMinor = tonumber(minor or "") or 0
    pr.addons = {}
    for entry in string.gmatch(blob or "", "([^,]+)") do
        local n, v = string.match(entry, "^(.-)=(.*)$")
        if n then pr.addons[n] = v end
    end
    fire("PEER", sender, pr)

    -- Answer a HI only when the sender is SHORT: it knows fewer of us than
    -- there are (a reload, a fresh join, a lost HI). A client that knows
    -- everybody already needs no answer - answering every HI "once per 5 s"
    -- (minor 2) turned 8 people zoning into Karazhan into 30 HIs on a 25-man
    -- (raid25.lua). HI_THROTTLE still spaces my own answers.
    local theyKnow = tonumber(known or "") or 0
    local short = theyKnow < (lib:Count() - 1)
    if not lib._hiPending and short then
        lib._hiPending = true
        local send = function()
            lib._hiPending = false
            lib._lastHi = Now()
            lib:Hi()
        end
        -- jittered like every answer; if my last HI is inside the throttle the
        -- answer waits it out instead of being dropped (a reload right after a
        -- join lost 7 of 21 peers that way - raid25.lua)
        local delay = ANSWER_MIN + math.random() * ANSWER_JITTER
        local wait = HI_THROTTLE - (Now() - (lib._lastHi or 0))
        if wait > delay then delay = wait end
        if not After(delay, send) then send() end
    end
end

--------------------------------------------------------------------
-- CORE: where am I
--------------------------------------------------------------------

-- Everything here is about the SELF. UnitPosition on somebody else goes nil the
-- moment they are in another instance -- which is precisely the case a summoner
-- cares about -- while a client's own position is never unknown.
function lib:MyWhere()
    local inInst, instType = false, "none"
    if IsInInstance then
        local a, b = IsInInstance()
        inInst, instType = a and true or false, b or "none"
    end
    -- mapId ALWAYS: outdoors it is the continent's instance id, the same number
    -- UnitPosition hands out, and the summoner compares against it to turn two
    -- positions into yards. MINOR 1 only sent it inside an instance, so a peer
    -- standing next to the summoner in Stormwind read as "far".
    local instName, mapId = "", ""
    if GetInstanceInfo then
        local n, _, _, _, _, _, _, id = GetInstanceInfo()
        mapId = id or ""
        if inInst then instName = n or "" end
    end
    local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
    local x, y = "", ""
    if UnitPosition then
        local py, px = UnitPosition("player")
        if px and py then
            x = string.format("%.1f", px)
            y = string.format("%.1f", py)
        end
    end
    return {
        inInstance = inInst, instType = instType, instName = instName,
        zone = zone, x = tonumber(x), y = tonumber(y), mapId = mapId,
        at = Now(),
    }
end

local function whereKey(w)
    return tostring(w.inInstance) .. w.instType .. w.instName .. w.zone
end

function lib:SendWhere(force)
    if not InGroup() then return false end
    local w = self:MyWhere()
    local key = whereKey(w)
    -- Push only on a real change. Walking around is not news; zoning is.
    if not force and key == self._lastWhereKey and (Now() - (self._lastWhereAt or 0)) < WHERE_THROTTLE then
        return false
    end
    self._lastWhereKey, self._lastWhereAt = key, Now()
    self.where = w
    return self:Send("CORE", "WHERE", w.inInstance, w.instType, w.instName, w.zone,
                     w.x or "", w.y or "", w.mapId)
end

-- A summoner asking. Everyone answers once, spread over 1-3s; repeat asks
-- inside the window fold into the one answer already scheduled.
function lib:Ask()
    return self:Send("CORE", "ASK", "WHERE")
end

lib._core.ASK = function(sender, what)
    if what ~= "WHERE" then return end
    if lib._askPending then return end
    if (Now() - (lib._lastAnswer or 0)) < ASK_COALESCE and lib._lastAnswer then return end
    lib._askPending = true
    local send = function()
        lib._askPending = false
        lib._lastAnswer = Now()
        lib:SendWhere(true)
    end
    if not After(ANSWER_MIN + math.random() * ANSWER_JITTER, send) then send() end
end

lib._core.WHERE = function(sender, inInst, instType, instName, zone, x, y, mapId)
    local pr = peer(sender)
    pr.where = {
        inInstance = (inInst == "1"),
        instType   = instType or "none",
        instName   = instName or "",
        zone       = zone or "",
        x = tonumber(x or ""), y = tonumber(y or ""),
        mapId = mapId or "",
        at = Now(),
    }
    fire("WHERE", sender, pr.where)
end

--------------------------------------------------------------------
-- CORE: summon offers
--------------------------------------------------------------------
-- CONFIRM_SUMMON fires on the person being summoned, never on the summoner, and
-- clicking a meeting stone is a game-object interaction the client does not
-- expose at all. This is the only honest way a summoner learns what happened.

function lib:SendSummon(state, summoner, area, left)
    self.summon = (state ~= "NO") and
        { state = state, summoner = summoner, area = area, left = left, at = Now() } or nil
    return self:Send("CORE", "SUM", state, summoner or "", area or "", left or "")
end

-- MINOR 6: 2.5.6.69795 has these only at C_SummonInfo.* (BiSProbe, 16 Sep) - the
-- globals minor 5 read are gone. C_SummonInfo first, the old globals as the fallback,
-- looked up at call time in pair form (the API fence in _bisdev/audit reads that shape).
local function SummonAPI()
    local who  = (C_SummonInfo and C_SummonInfo.GetSummonConfirmSummoner) or GetSummonConfirmSummoner
    local area = (C_SummonInfo and C_SummonInfo.GetSummonConfirmAreaName) or GetSummonConfirmAreaName
    local left = (C_SummonInfo and C_SummonInfo.GetSummonConfirmTimeLeft) or GetSummonConfirmTimeLeft
    return who, area, left
end

function lib:OnConfirmSummon()
    local getWho, getArea, getLeft = SummonAPI()
    local summoner = getWho and getWho() or ""
    local area     = getArea and getArea() or ""
    local left     = getLeft and getLeft() or OFFER_FALLBACK
    -- MINOR 5: the 2.5.x client fires CONFIRM_SUMMON on bystanders too (Arn, 10 Sep:
    -- "randomly if any other person gets a summon it says SUMMON by someone") - with
    -- no summoner, no area, no clock. That is not an offer to ME; announcing it as
    -- one would put a phantom OFFER on every summoner's list. Ask the client.
    if not self:HasPendingSummon(summoner, area, left) then return end
    left = tonumber(left) or OFFER_FALLBACK
    if left <= 0 then left = OFFER_FALLBACK end
    self._offerId = (self._offerId or 0) + 1
    local id = self._offerId
    self:SendSummon("OFFER", Short(summoner), area, math.floor(left))
    -- An offer that lapses unanswered is the exact case that used to leave the
    -- summoner staring at the same name: say so when the clock runs out.
    After(left, function()
        if lib._offerId == id and lib.summon and lib.summon.state == "OFFER" then
            lib:SendSummon("NO", nil, nil, nil)
        end
    end)
end

-- Is there really a summon waiting on THIS client? Only the client's summon API can
-- say. MINOR 6: when neither C_SummonInfo nor the old globals exist the answer is NO -
-- minor 5 said yes there, and on 2.5.6.69795 (globals gone) that turned every
-- bystander's CONFIRM_SUMMON back into a phantom OFFER.
function lib:HasPendingSummon(summoner, area, left)
    local getWho, getArea, getLeft = SummonAPI()
    if not getWho then return false end
    summoner = summoner or (getWho() or "")
    area = area or (getArea and getArea() or "")
    left = tonumber(left or (getLeft and getLeft())) or 0
    return (summoner ~= "" or area ~= "" or left > 0) and true or false
end

function lib:OnConfirmed()      -- they clicked Accept
    if self.summon and self.summon.state == "OFFER" then
        self._offerId = (self._offerId or 0) + 1
        self:SendSummon("OK", self.summon.summoner, self.summon.area, nil)
    end
end

function lib:OnCancelSummon()   -- declined, or it timed out client-side
    if self.summon then
        self._offerId = (self._offerId or 0) + 1
        self:SendSummon("NO", nil, nil, nil)
    end
end

lib._core.SUM = function(sender, state, summoner, area, left)
    local pr = peer(sender)
    if state == "NO" then
        pr.summon = nil
    else
        pr.summon = {
            state = state, summoner = summoner, area = area,
            left = tonumber(left or ""), at = Now(),
        }
    end
    fire("SUM", sender, pr.summon)
end

--------------------------------------------------------------------
-- events
--------------------------------------------------------------------

function lib:Boot()
    if self._booted then return end
    self._booted = true

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    elseif RegisterAddonMessagePrefix then
        pcall(RegisterAddonMessagePrefix, PREFIX)
    end

    local f = self._frame or (CreateFrame and CreateFrame("Frame"))
    if not f then return end
    self._frame = f

    local function reg(ev)
        -- An event this client does not have must not stop the rest registering.
        pcall(f.RegisterEvent, f, ev)
    end
    reg("CHAT_MSG_ADDON")
    reg("PLAYER_ENTERING_WORLD")
    reg("ZONE_CHANGED_NEW_AREA")
    reg("GROUP_ROSTER_UPDATE")
    reg("CONFIRM_SUMMON")
    reg("CANCEL_SUMMON")
    reg("GUILD_ROSTER_UPDATE")
    reg("ADDON_RESTRICTION_STATE_CHANGED")     -- Forever: the lockdown starting or lifting (minor 10)
    if self.StartSpots then self:StartSpots() end -- minor 12: guild spots

    f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
        if event == "CHAT_MSG_ADDON" then
            lib:OnMessage(a1, a2, a3, a4)
        elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
            lib:OnRestrictionChanged()
        elseif event == "GUILD_ROSTER_UPDATE" then
            lib._guildDirty = true
        elseif event == "CONFIRM_SUMMON" then
            lib:OnConfirmSummon()
        elseif event == "CANCEL_SUMMON" then
            lib:OnCancelSummon()
        elseif event == "GROUP_ROSTER_UPDATE" then
            lib:OnRoster()
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- login / reload: my table may be empty, say HI and let the short
            -- rule fill it
            lib:SendWhere(true)
            if not After(1 + math.random() * 2, function() lib:Hi() end) then lib:Hi() end
        else
            -- ZONE_CHANGED_NEW_AREA: a zone line is news about WHERE, not who
            -- I am; peers survive zoning (the blip rule), so no HI here
            lib:SendWhere(true)
        end
    end)

    -- Accept has no event of its own; the popup calls ConfirmSummon(). MINOR 6: on
    -- 2.5.6.69795 that is C_SummonInfo.ConfirmSummon - minor 5 looked only for the
    -- global, found nothing, and never saw an accept.
    -- MINOR 11: not on Forever. There a hooksecurefunc on a Blizzard object's method can
    -- start failing in Blizzard's own caller ("attempt to call a nil value") until the game
    -- is relaunched (Overlord 2.0 pulled all of its own, 11-12 Oct) - and the summon popup's
    -- Accept is the caller here. Forever is asked by interface number, as BiSTools' summon
    -- tool asks it (16000-19999; WOW_PROJECT_ID reads 1 on the beta). Its summon tool does
    -- not run there, so no accept is missed that anybody reads.
    local iface = GetBuildInfo and select(4, GetBuildInfo())
    lib.forever = type(iface) == "number" and iface >= 16000 and iface < 20000
    if lib.forever then
        -- no hook
    elseif hooksecurefunc and C_SummonInfo and C_SummonInfo.ConfirmSummon then
        hooksecurefunc(C_SummonInfo, "ConfirmSummon", function() lib:OnConfirmed() end)
    elseif hooksecurefunc and type(_G.ConfirmSummon) == "function" then
        hooksecurefunc("ConfirmSummon", function() lib:OnConfirmed() end)
    end
end

-- A zone-in reads the roster as EMPTY for a moment. Wiping the peer table on
-- that blip took Innervate's whole grid out for a night; wait 10s before
-- believing an empty group.
function lib:OnRoster()
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if n > 0 then
        -- HI only when *I* just arrived (0 -> n). Somebody else joining is his
        -- HI to say, and everyone short-answers it; a leave is a purge, not a
        -- conversation. Minor 2 said HI on every roster tick - 22 messages per
        -- join / leave / promote on a 25-man (raid25.lua).
        local arrived = (self._lastN or 0) == 0
        self._lastN, self._emptySince = n, nil
        self:PurgeAbsent()
        if arrived then
            if not After(1 + math.random() * 2, function() lib:Hi() end) then self:Hi() end
        end
        return
    end
    if (self._lastN or 0) == 0 then return end
    self._emptySince = self._emptySince or Now()
    if (Now() - self._emptySince) < 10 then return end
    self._lastN, self._emptySince = 0, nil
    self.peers = {}
    lib.peers = self.peers
end

--------------------------------------------------------------------
-- SPOT: where your guildmates are, for a map (minor 12)
--------------------------------------------------------------------
-- Arn, 14 Oct 2026: "what are the chances we can show all guild locations?" - the game hands an
-- addon the GROUP's positions only, so BiS clients share their own: "on by default but toggleable,
-- lets cascading small guild 15 sec as it get bigger maybe once a min" - and in the LIBRARY, so
-- every BiS addon shares and one switch rules them all ("or does it go in a library?").
--
--   SPOT|AT|uiMapID|x|y     x, y 0-1 on that zone map, three decimals; GUILD channel only
--
-- Sent only while you MOVE (past SPOT_STEP of the map since the last one), never inside an
-- instance or with a hidden position, at most every 15 s with up to 20 guildmates online, 30 s up
-- to 50, 60 s beyond. Received into lib.spots[name] = { map, x, y, at } and fired as "SPOT"; a spot
-- older than SPOT_STALE is a lie about where somebody is, and dropped. The lib has no SavedVariables:
-- each embedder remembers the switch (db.commShare) beside the comm switch, as it does /biscomm off.
lib.spots = lib.spots or {}
if lib.share == nil then lib.share = true end
lib.guildMods.SPOT = true
local SPOT_CHECK, SPOT_STEP, SPOT_STALE = 5, 0.012, 180
-- STANDING STILL STILL SHOWS (minor 13; Arn, 18 Oct: a guildmate standing in Undercity was gone from
-- the map - he had sent his spot once, then stood, and three minutes on every map dropped it as
-- stale). Still, the spot goes again every SPOT_RESEND - inside SPOT_STALE, so it never lapses.
local SPOT_RESEND = 120
lib.SPOT_CHECK, lib.SPOT_STEP, lib.SPOT_STALE, lib.SPOT_RESEND = SPOT_CHECK, SPOT_STEP, SPOT_STALE, SPOT_RESEND

local function plainNum(v)
    if v == nil or Secret(v) or type(v) ~= "number" then return nil end
    return v
end

function lib:Sharing() return self.share and true or false end
function lib:SetSharing(on)
    self.share = on and true or false
    if not self.share then self._spotSent = nil end
end

--- How often to send, by how many guildmates are online.
function lib:ShareEvery()
    local ok, _, online = pcall(GetNumGuildMembers)
    online = ok and plainNum(online) or 0
    if online <= 20 then return 15 elseif online <= 50 then return 30 end
    return 60
end

--- My spot on my zone map, or nil (an instance, a hidden position, no map).
function lib:MySpot()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    if IsInInstance then
        local ok, inside = pcall(IsInInstance)
        if not ok or Secret(inside) or inside then return nil end
    end
    local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
    map = ok and plainNum(map) or nil
    if not map then return nil end
    local ok2, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not ok2 or pos == nil or Secret(pos) then return nil end
    local ok3, x, y = pcall(function() return pos:GetXY() end)
    if not ok3 then return nil end
    x = plainNum(x)
    y = plainNum(y)
    if not (x and y) or (x == 0 and y == 0) then return nil end
    return map, x, y
end

--- One look (every SPOT_CHECK s): send my spot if I may and should. Answers what it did.
function lib:ShareTick()
    if not (self.enabled and self.share) then return "off" end
    if not (IsInGuild and IsInGuild()) then return "no guild" end
    local map, x, y = self:MySpot()
    if not map then return "hidden" end
    local s, now = self._spotSent, Now()
    if s and s.map == map and math.abs(s.x - x) < SPOT_STEP and math.abs(s.y - y) < SPOT_STEP
        and now - s.at < SPOT_RESEND then
        return "still"
    end
    if s and now - s.at < self:ShareEvery() then return "wait" end
    if not self:SendTo("GUILD", "SPOT", "AT", tostring(map), ("%.3f"):format(x), ("%.3f"):format(y)) then
        return "not sent"
    end
    self._spotSent = { map = map, x = x, y = y, at = now }
    return "sent"
end

--- Guildmates' spots, the stale ones dropped. name -> { map, x, y, at }
function lib:Spots()
    local now = Now()
    for name, s in pairs(self.spots) do
        if now - s.at > SPOT_STALE then self.spots[name] = nil end
    end
    return self.spots
end

-- a guildmate's spot (OnMessage already let in only a guild-roster sender, never my own echo)
lib.handlers.SPOT = lib.handlers.SPOT or {}
lib.handlers.SPOT.AT = function(sender, map, x, y)
    map, x, y = tonumber(map), tonumber(x), tonumber(y)
    if not (map and x and y) or x < 0 or x > 1 or y < 0 or y > 1 then return end
    local s = { map = map, x = x, y = y, at = Now() }
    lib.spots[sender] = s
    fire("SPOT", sender, s)
end

function lib:StartSpots()
    if self._spotTicker or not (C_Timer and C_Timer.NewTicker) then return end
    self._spotTicker = C_Timer.NewTicker(SPOT_CHECK, function() lib:ShareTick() end)
end
-- a copy loading after the lib already booted (an upgrade in place) starts it here
if lib._booted then lib:StartSpots() end

--------------------------------------------------------------------
-- the one slash: status and the honest off switch
--------------------------------------------------------------------

-- Always (re)set, even over an older copy's handler: minor 3 took "/bis", which
-- LoonBestInSlot also owns, so the newest copy must move the slash to /biscomm.
if SlashCmdList then
    _G.SLASH_BISCOMM1 = "/biscomm"
    SlashCmdList["BISCOMM"] = function(msg)
        msg = tostring(msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        local say = function(s)
            if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffb980ffBiS|r " .. s) end
        end
        if msg == "comm off" or msg == "off" then
            lib:SetEnabled(false); say("comm off - silent and deaf until /biscomm on")
        elseif msg == "comm on" or msg == "on" then
            lib:SetEnabled(true); lib:Hi(); say("comm on")
        elseif msg == "share off" then
            lib:SetSharing(false); say("share off - your guild no longer sees where you are on their map")
        elseif msg == "share on" then
            lib:SetSharing(true); say("share on - your guild sees where you are on their map (while you move, outside instances)")
        else
            say(("comm %s, share %s, lib %d, %d peer(s), running %s")
                :format(lib:Enabled() and "on" or "off", lib:Sharing() and "on" or "off", lib.MINOR, lib:Count(),
                        lib:AddonsBlob() ~= "" and lib:AddonsBlob() or "nothing"))
            -- what left and what did not (minor 13: the night "sent 0" took four /run lines to see)
            say(("sent %d, refused %d, waiting %d%s%s"):format(lib.sentCount or 0, lib.refusedCount or 0,
                #(lib.outbox or {}), lib._lastError and (", last trouble: " .. lib._lastError) or "",
                OutgoingBlocked() and " (the realm says restricted - Forever always does; ignored)" or ""))
            say("/biscomm on | off  -  /biscomm share on | off")
        end
    end
end

return lib
