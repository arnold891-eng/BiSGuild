-- BiSGuild :: dev/same_report.lua - do two Data/Report.lua files say the same thing?
--
--     lua dev/same_report.lua <python's Report.lua> <powershell's Report.lua>
--
-- The two readers (dev/logreport.py, Tools/logreport.ps1) are kept in step on purpose: raiders run
-- the PowerShell one, the suite drives the Python one. This compares everything the raider terminal
-- reads - days, cards, bosses, rows - value by value, so the two cannot drift without a red line.
-- Only `written` (the clock) is allowed to differ.

local function load(path)
    local env = {}
    local chunk = assert(loadfile(path))
    setfenv(chunk, env)
    chunk()
    return env.BiSGuildReport
end

local function same(a, b, where, out)
    if type(a) ~= type(b) then
        out[#out + 1] = where .. ": " .. type(a) .. " vs " .. type(b)
        return
    end
    if type(a) ~= "table" then
        if a ~= b then out[#out + 1] = where .. ": " .. tostring(a) .. " vs " .. tostring(b) end
        return
    end
    for k, v in pairs(a) do same(v, b[k], where .. "." .. tostring(k), out) end
    for k, v in pairs(b) do
        if a[k] == nil then out[#out + 1] = where .. "." .. tostring(k) .. ": only in the second" end
    end
end

local a, b = load(arg[1]), load(arg[2])
local out = {}
for _, k in ipairs({ "days", "cards", "bosses", "rows", "kills", "nights", "zones" }) do
    same(a[k], b[k], k, out)
end
if #out == 0 then
    print("SAME")
    os.exit(0)
end
for _, line in ipairs(out) do print("DIFF " .. line) end
os.exit(1)
