-- LibBiSLedger-1.0
-- The loot ledger's core, as a library (16 Oct 2026). Append-only events, one chain per author, a
-- checksum on every line. Born as BiS Loot's Core/Ledger.lua (13 Sep, TBC); lifted out when Arn folded
-- the ledger into BiS Guild: "if they are going to install one thing it's BiS Guild ... or maybe we put
-- it into the library thing". EMBEDDED, never installed: the canon lives in _bisdev, every embedder
-- carries a byte-identical copy (sync.ps1), and the newest MINOR present wins.
--
--   line  = v \t author \t seq \t prev \t t \t kind \t raid \t boss \t item \t who \t resp \t by \t ref \t note \t sum
--
--   - `seq`  numbers each author's own events 1, 2, 3...  id = author .. "#" .. seq.
--   - `prev` is the sum of that author's previous line ("0" for seq 1): a hash chain per author.
--   - `sum`  is CRC32 over everything before it. A flipped byte fails the sum and the line is
--            dropped, never repaired.
--   Two copies of a ledger can only ever disagree by a FORK (same author + seq, different sum) or a
--   GAP (a seq we have not seen yet). Both are kept and reported, never resolved by guessing.
--
-- No wire, no UI, no saved variables here: the embedding addon stores `L:Lines()` and feeds them back
-- through `L:Accept(line, "file")`. One ledger per `LibBiSLedger.New()` - BiS Guild keeps one per guild.
--
--   LibBiSLedger.New()             -> a ledger
--   LibBiSLedger.pack(ev) / unpack(line) / crc32(s) / sum(s); .FORMAT, .FIELDS, .KINDS
--   L:Reset()  L:OnEvent(fn(ev, source))  L:Head(author) -> seq, sum
--   L:Accept(line, source)         -> "new"|"dup"|"fork"|"gap"|"bad", event-or-why
--                                     source: "own" | "author" | "relay" | "file"
--   L:Add(author, fields)          -> event | nil, why          (fields.t defaults to GetServerTime())
--   L:Gaps()  L:Verify()  L:Lines()  L:Events(keep)  L:Witness(id, who)
local MAJOR, MINOR = "LibBiSLedger-1.0", 1

local lib = _G.LibBiSLedger
if lib and (lib.MINOR or 0) >= MINOR then return end   -- an equal or newer copy won
lib = lib or {}
_G.LibBiSLedger = lib
lib.MAJOR, lib.MINOR = MAJOR, MINOR

lib.FORMAT = "1"
lib.FIELDS = { "v", "author", "seq", "prev", "t", "kind", "raid", "boss", "item", "who", "resp", "by", "ref", "note" }
lib.KINDS = { award = true, fix = true, roster = true, note = true, session = true, resp = true, vote = true, roll = true }
local NFIELDS = #lib.FIELDS
local SEP = "\t"

local function Now()
  if GetServerTime then return GetServerTime() end
  return time and time() or 0
end

-- CRC32 --------------------------------------------------------------------------------
-- Lua 5.1 on this client has the `bit` library, the harness does not. One implementation
-- for both: xor on nibbles through a 16x16 table, so the sum is the same bytes everywhere.
local XN = {}
for a = 0, 15 do
  XN[a] = {}
  for b = 0, 15 do
    local r, x, y, p = 0, a, b, 1
    for _ = 1, 4 do
      if (x % 2) ~= (y % 2) then r = r + p end
      x, y, p = math.floor(x / 2), math.floor(y / 2), p * 2
    end
    XN[a][b] = r
  end
end
local function bxor(x, y)
  local r, p = 0, 1
  for _ = 1, 8 do
    local xa, ya = x % 16, y % 16
    r = r + XN[xa][ya] * p
    x, y, p = (x - xa) / 16, (y - ya) / 16, p * 16
  end
  return r
end
local CRC = {}
for i = 0, 255 do
  local c = i
  for _ = 1, 8 do
    if c % 2 == 1 then c = bxor((c - 1) / 2, 0xEDB88320) else c = c / 2 end
  end
  CRC[i] = c
end
local byte = string.byte
function lib.crc32(s)
  local c = 0xFFFFFFFF
  for i = 1, #s do
    local b = byte(s, i)
    local idx = bxor(c % 256, b)
    c = bxor((c - c % 256) / 256, CRC[idx])
  end
  return bxor(c, 0xFFFFFFFF)
end
function lib.sum(s)
  return ("%08x"):format(lib.crc32(s))
end

-- pack / unpack ------------------------------------------------------------------------
local function clean(v)
  v = tostring(v == nil and "" or v)
  return (v:gsub("[\t\r\n]", " "))
end

--- Event table -> one line (sum appended). Every field is a string on the line.
function lib.pack(ev)
  local parts = {}
  for i, k in ipairs(lib.FIELDS) do parts[i] = clean(ev[k]) end
  local body = table.concat(parts, SEP)
  return body .. SEP .. lib.sum(body)
end

--- Line -> event table, or nil + why. The sum is checked here and nowhere else needs to.
function lib.unpack(line)
  if type(line) ~= "string" then return nil, "not a string" end
  local parts = {}
  for p in (line .. SEP):gmatch("(.-)\t") do parts[#parts + 1] = p end
  if #parts ~= NFIELDS + 1 then return nil, ("%d fields, want %d"):format(#parts, NFIELDS + 1) end
  local body = line:sub(1, #line - 9)
  if line:sub(-9, -9) ~= SEP or lib.sum(body) ~= parts[NFIELDS + 1] then return nil, "bad sum" end
  local ev = {}
  for i, k in ipairs(lib.FIELDS) do ev[k] = parts[i] end
  if ev.v ~= lib.FORMAT then return nil, "format " .. tostring(ev.v) end
  ev.seq = tonumber(ev.seq)
  if not ev.seq or ev.seq < 1 or ev.seq ~= math.floor(ev.seq) then return nil, "bad seq" end
  if ev.author == "" then return nil, "no author" end
  if not lib.KINDS[ev.kind] then return nil, "kind " .. tostring(ev.kind) end
  ev.t = tonumber(ev.t) or 0
  ev.sum = parts[NFIELDS + 1]
  ev.id = ev.author .. "#" .. ev.seq
  ev.line = line
  return ev
end

-- the store ----------------------------------------------------------------------------
local Proto = {}
lib.Proto = Proto
local meta = { __index = Proto }

function lib.New()
  local L = setmetatable({}, meta)
  L:Reset()
  return L
end

function Proto:Reset()
  self.chains = {}    -- [author] = { head = n, ev = { [seq] = ev } }
  self.byId = {}      -- [id] = ev
  self.forks = {}     -- [author] = { ev, ... }  (same seq, different sum / broken link)
  self.waiting = {}   -- [author] = { [seq] = ev }  (arrived ahead of a gap)
  self.bad = {}       -- { { line = , why = }, ... }
  self.meta = {}      -- [id] = { w = witnesses, direct = from its author }
  self.count = 0
  self.listeners = self.listeners or {}
end

function Proto:OnEvent(fn) self.listeners[#self.listeners + 1] = fn end
local function fire(self, ev, how)
  for _, fn in ipairs(self.listeners) do fn(ev, how) end
end

local function chain(self, author)
  local c = self.chains[author]
  if not c then c = { head = 0, ev = {} }; self.chains[author] = c end
  return c
end

function Proto:Head(author)
  local c = self.chains[author]
  if not c or c.head == 0 then return 0, "0" end
  return c.head, c.ev[c.head].sum
end

local function link(self, c, ev, source)
  c.ev[ev.seq] = ev
  c.head = ev.seq
  self.byId[ev.id] = ev
  self.count = self.count + 1
  local m = self.meta[ev.id] or { w = 0, direct = false }
  if source == "author" or source == "own" then m.direct = true; m.w = math.max(m.w, 1) end
  self.meta[ev.id] = m
end

--- Take a line in. source: "own" | "author" (from its author on the wire) | "relay" | "file".
--- Returns "new" | "dup" | "fork" | "gap" | "bad", and the event (or why for "bad").
function Proto:Accept(line, source)
  local ev, why = lib.unpack(line)
  if not ev then
    self.bad[#self.bad + 1] = { line = line, why = why }
    return "bad", why
  end
  local c = chain(self, ev.author)
  if ev.seq <= c.head then
    local have = c.ev[ev.seq]
    if have.sum == ev.sum then
      local m = self.meta[ev.id]
      if source == "author" then m.direct = true; m.w = math.max(m.w, 1) end
      return "dup", have
    end
    self.forks[ev.author] = self.forks[ev.author] or {}
    table.insert(self.forks[ev.author], ev)
    return "fork", ev
  end
  if ev.seq > c.head + 1 then
    self.waiting[ev.author] = self.waiting[ev.author] or {}
    ev.src = source   -- remembered for the drain: an author's own line stays witnessed
    self.waiting[ev.author][ev.seq] = ev
    return "gap", ev
  end
  -- seq == head + 1: the link must hold
  local _, headSum = self:Head(ev.author)
  if ev.prev ~= headSum then
    self.forks[ev.author] = self.forks[ev.author] or {}
    table.insert(self.forks[ev.author], ev)
    return "fork", ev
  end
  link(self, c, ev, source)
  fire(self, ev, source)
  -- anything that was waiting right behind it lands now
  local w = self.waiting[ev.author]
  while w and w[c.head + 1] do
    local nxt = w[c.head + 1]
    w[c.head + 1] = nil
    local _, hs = self:Head(ev.author)
    local src = nxt.src or "relay"; nxt.src = nil
    if nxt.prev == hs then link(self, c, nxt, src); fire(self, nxt, src)
    else self.forks[ev.author] = self.forks[ev.author] or {}; table.insert(self.forks[ev.author], nxt) end
  end
  return "new", ev
end

--- Write one of our own. Fields: kind + whatever applies. Returns the event.
function Proto:Add(author, fields)
  if not lib.KINDS[fields.kind] then return nil, "kind " .. tostring(fields.kind) end
  local head, headSum = self:Head(author)
  local ev = {}
  for _, k in ipairs(lib.FIELDS) do ev[k] = fields[k] end
  ev.v = lib.FORMAT
  ev.author = author
  ev.seq = head + 1
  ev.prev = headSum
  ev.t = fields.t or Now()
  local line = lib.pack(ev)
  local status, got = self:Accept(line, "own")
  if status ~= "new" then return nil, status end
  return got
end

--- The gaps: for each author, the first seq we are missing before something waiting.
function Proto:Gaps()
  local out = {}
  for author, w in pairs(self.waiting) do
    local lo
    for seq in pairs(w) do if not lo or seq < lo then lo = seq end end
    if lo then
      local head = self:Head(author)
      out[#out + 1] = { author = author, from = head + 1, to = lo - 1 }
    end
  end
  table.sort(out, function(a, b) return a.author < b.author end)
  return out
end

--- Re-check everything from the lines themselves: sums, links, forks, gaps.
function Proto:Verify()
  local r = { events = 0, authors = 0, bad = #self.bad, forks = 0, broken = {}, ok = true }
  local names = {}
  for author in pairs(self.chains) do names[#names + 1] = author end
  table.sort(names)
  for _, author in ipairs(names) do
    local c = self.chains[author]
    if c.head > 0 then r.authors = r.authors + 1 end
    local prev = "0"
    for seq = 1, c.head do
      local ev = c.ev[seq]
      local re = lib.unpack(ev.line)
      if not re or re.sum ~= ev.sum or re.prev ~= prev then
        r.broken[#r.broken + 1] = ev.id
        r.ok = false
      end
      prev = ev.sum
      r.events = r.events + 1
    end
    if self.forks[author] then r.forks = r.forks + #self.forks[author] end
  end
  r.gaps = self:Gaps()
  -- quarantined lines are history, not a hole: a chain can be whole with a bad line beside it
  if r.forks > 0 or #r.gaps > 0 then r.ok = false end
  return r
end

--- Every line, authors sorted, seq ascending - what goes to SavedVariables.
function Proto:Lines()
  local out, names = {}, {}
  for author in pairs(self.chains) do names[#names + 1] = author end
  table.sort(names)
  for _, author in ipairs(names) do
    local c = self.chains[author]
    for seq = 1, c.head do out[#out + 1] = c.ev[seq].line end
  end
  return out
end

--- Events, newest first, optionally filtered (a function ev -> bool).
function Proto:Events(keep)
  local out = {}
  for _, ev in pairs(self.byId) do
    if not keep or keep(ev) then out[#out + 1] = ev end
  end
  table.sort(out, function(a, b)
    if a.t ~= b.t then return a.t > b.t end
    if a.author ~= b.author then return a.author < b.author end
    return a.seq > b.seq
  end)
  return out
end

function Proto:Witness(id, who)
  local m = self.meta[id]
  if not m then return end
  m.from = m.from or {}
  if who and not m.from[who] then m.from[who] = true; m.w = m.w + 1 end
end

return lib
