-- BiSGuild palette law (made by _bisdev/new-addon.sh). Run from the addon root: lua5.1 dev/theme.lua
-- The addon loads BEFORE BiSTheme (alphabetical) and must still read the shared addon's colours
-- once it is there. A palette captured at load could never.
local HERE = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local H = dofile(HERE .. "/kit.lua")
local ROOT = os.getenv("BISGUILD") or (HERE .. "/..")
local FILES = H.TOC(ROOT, "BiSGuild.toc")
_G.GetAddOnMetadata = function() return "test" end

H.section("before BiSTheme.lua runs (only the embedded Console fallback)")
local NS = {}
for _, rel in ipairs(FILES) do
    local chunk = assert(loadfile(ROOT .. "/" .. rel))
    chunk("BiSGuild", NS)
end
H.ok(math.abs(NS.T.rgb("accent") - 0xb9 / 255) < 0.01, "accent falls back to b980ff")
H.ok(select(1, NS.T.rgb("nosuchcolour")) ~= nil, "an unknown colour still returns numbers")

H.section("with BiSTheme installed and loading AFTER us")
local THEME = os.getenv("BISTHEME") or (ROOT .. "/../BiSTheme/BiSTheme.lua")
H.ok(io.open(THEME, "rb") ~= nil, "BiSTheme.lua is beside this checkout", THEME)
dofile(THEME)
_G.BiSTheme.hex.accent = "112233"
H.ok(math.abs(NS.T.rgb("accent") - 0x11 / 255) < 0.01, "it really reads BiSTheme per call, not a copy")
H.ok(NS.T.text("accent", "x"):find("112233", 1, true) ~= nil, "text() too")
_G.BiSTheme.hex.accent = "b980ff"
H.report()
