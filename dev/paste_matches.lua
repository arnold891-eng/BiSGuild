-- BiSGuild :: dev/paste_matches.lua - does the game take in what the notebook prints?
--
--     lua dev/paste_matches.lua <paste.txt> <Report.lua> <Core/Store.lua> <Core/Share.lua>
--
-- dev/logreport.py --paste writes the text a person carries from the Colab notebook into BiS Guild's
-- import box (17 Oct 2026). Two writers of one layout drift unless something holds them together:
-- this imports the paste through the game's OWN Store.lua and Share.lua into an empty record and
-- checks every raid against the reader's nightly in Report.lua, value by value - then pastes again
-- (nothing new) and pastes a damaged copy (refused whole).

local function slurp(p) local fh = assert(io.open(p, "rb")) local s = fh:read("*a") fh:close() return s end
local env = {}
local chunk = assert(loadfile(arg[2]))
setfenv(chunk, env)
chunk()
local report = env.BiSGuildReport

-- the least of a client Share.lua and Store.lua touch at load and on an import
_G.CreateFrame = function()
    return { RegisterEvent = function() end, SetScript = function() end, UnregisterEvent = function() end }
end
_G.UnitName = function() return "Notebookuser" end
_G.GetNumGuildMembers = function() return 0 end
_G.GetGuildRosterInfo = function() return nil end
_G.C_Timer = { After = function() end }
_G.GetTime = function() return 0 end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
local db = {}
local ns = { DB = function() return db end, Books = function() return db end, parts = {} }
assert(loadfile(arg[3]))("BiSGuild", ns)
assert(loadfile(arg[4]))("BiSGuild", ns)
local S, X = ns.S, ns.X

local text = slurp(arg[1])
local raids, gear, bad = X.ImportPaste(text)
local out = {}
if not raids then out[#out + 1] = "refused: " .. tostring(gear) end

local function same(a, b, where)
    if type(a) ~= type(b) then out[#out + 1] = where .. ": " .. type(a) .. " vs " .. type(b) return end
    if type(a) ~= "table" then
        if a ~= b then out[#out + 1] = where .. ": " .. tostring(a) .. " vs " .. tostring(b) end
        return
    end
    for k, v in pairs(a) do same(v, b[k], where .. "." .. tostring(k)) end
    for k in pairs(b) do if a[k] == nil then out[#out + 1] = where .. "." .. tostring(k) .. ": missing" end end
end

if raids then
    local want = 0
    for key, night in pairs(report.nightly or {}) do
        if night.v == 2 then
            want = want + 1
            local got = S.Record().nights[key]
            if not got then
                out[#out + 1] = "raid " .. key .. " not taken in"
            else
                same(got.kills, night.kills, key .. ".kills")
                same(got.raiders, night.raiders, key .. ".raiders")
                same(got.bosses, night.bosses, key .. ".bosses")
                same(#got.pulls, #night.pulls, key .. ".pulls")
                same(got.zone, night.zone, key .. ".zone")
            end
        end
    end
    if raids ~= want then out[#out + 1] = ("raids taken in %d, the report has %d"):format(raids, want) end
    if bad ~= 0 then out[#out + 1] = bad .. " line(s) did not decode" end
    for name, c in pairs(report.cards or {}) do
        if c.gear then
            local g = S.Record().gear[name]
            -- an EMPTY slot travels as "0" (X.EncodeGear, the guild channel's rule since 16 Oct): its item
            -- level means nothing, so an empty slot compares by being empty
            local want = {}
            for i, s in ipairs(c.gear) do want[i] = (tonumber(s[1]) or 0) == 0 and { 0, 0, 0, 0, {} } or s end
            if not g then out[#out + 1] = "gear of " .. name .. " not taken in" else same(g.gear, want, "gear." .. name) end
        end
    end
    local r2, g2 = X.ImportPaste(text)
    if r2 ~= 0 or g2 ~= 0 then out[#out + 1] = "the same paste twice changed something" end
    local cut = text:gsub("END~", "XXX~")
    if X.ImportPaste(cut) ~= nil then out[#out + 1] = "a paste with no END line was taken" end
    local damaged = text:gsub("R~", "R~", 1):gsub(";", "", 1)
    if X.ImportPaste(damaged) ~= nil then out[#out + 1] = "a paste missing a letter was taken" end
end

if #out == 0 then print("SAME") os.exit(0) end
for _, l in ipairs(out) do print("DIFF " .. l) end
os.exit(1)
