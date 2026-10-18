-- BiSGuild :: dev/store_matches.lua - does the game build the same cards the readers wrote?
--
--     lua dev/store_matches.lua <Report.lua> <Core/Store.lua>
--
-- The readers write `cards` and `bosses` from their history; the addon rebuilds both from `nightly`
-- and the cards' gear (Core/Store.lua), because a night that came over the guild channel has no
-- reader behind it. Two builders of the same thing drift unless something holds them together: this
-- imports the report into an empty record and compares the two, value by value.

local env = {}
local chunk = assert(loadfile(arg[1]))
setfenv(chunk, env)
chunk()
local report = env.BiSGuildReport

local db = {}
-- the per-guild books (16 Oct): this harness lacked them and died on load, unseen, because the
-- Python test that runs it is not in check.sh (17 Oct)
local ns = { DB = function() return db end, Books = function() return db end }
assert(loadfile(arg[2]))("BiSGuild", ns)
local S = ns.S
S.Import(report)

local out = {}
local function same(a, b, where)
    if type(a) ~= type(b) then
        out[#out + 1] = where .. ": " .. type(a) .. " vs " .. type(b)
        return
    end
    if type(a) ~= "table" then
        if a ~= b then out[#out + 1] = where .. ": " .. tostring(a) .. " vs " .. tostring(b) end
        return
    end
    for k, v in pairs(a) do same(v, b[k], where .. "." .. tostring(k)) end
    for k in pairs(b) do
        if a[k] == nil then out[#out + 1] = where .. "." .. tostring(k) .. ": only in the game's" end
    end
end

same(report.cards or {}, S.Cards(), "cards")
same(report.bosses or {}, S.Bosses(), "bosses")

-- and the WANT list is dev/gearcheck.txt's, in its order
local want = {}
for line in io.lines((arg[2]:gsub("Core[/\\]Store%.lua$", "dev/gearcheck.txt"))) do
    local slot = line:match("^enchant%s+(%S+)")
    if slot then want[#want + 1] = slot end
end
same(want, S.WANT, "gearcheck")

if #out == 0 then
    print("SAME")
    os.exit(0)
end
for _, line in ipairs(out) do print("DIFF " .. line) end
os.exit(1)
