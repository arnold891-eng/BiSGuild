--[[
  BiSGuild :: Core/Report.lua - the numbers that came out of a combat log.

  Arn, 4 Oct 2026: "am I expected to copy and paste a whole 108mb of text into a text box in wow?"

  No - and the honest answer to that question is that the paste should not exist either. The script
  boils 110 MB down to 410 characters, which IS pasteable, but a paste is still a thing to remember,
  get wrong, and do again every raid night.

  So `logreport.py --write` writes `Data/Report.lua` straight into the addon folder, and the client
  loads it like any other file. Run the script, /reload, the numbers are in game. Nothing is typed
  and nothing is pasted. It is the same trick Gargul uses: Gargul_ItemData is an entire addon whose
  only job is to be a data file.

  THE GENERATED FILE MAY NOT BE THERE. It is not in git - it is somebody's raid data, not source -
  and `deploy.sh` wipes the game folder before copying, so a deploy removes it until the script runs
  again. A missing file named in a TOC is skipped by the client, so this file must work when
  `BiSGuildReport` is nil, and say so in words rather than looking broken.
]]
local ADDON, ns = ...

local P = {}
ns.P = P

--- THE FINGERPRINT OF THE SCRIPT WE SHIPPED (4 Oct 2026).
---
--- Arn: "we need a big warning that you are about to run a powershell make sure no one sent you
--- this copy and that you got it from curseforge and even then we should add some sort of
--- integrity check... something like a blockchain idk I'm not tech literate".
---
--- The word wanted is a HASH, and it is simpler than a blockchain: a fingerprint where changing one
--- character of the file changes the whole fingerprint unpredictably, so a tampered script cannot
--- be made to match. Windows computes it with Get-FileHash and needs nothing installed.
---
--- WHAT THIS ACTUALLY DEFENDS AGAINST, said plainly because security that is oversold is worse than
--- none:
---   * somebody swapping ONLY the .ps1 inside an otherwise real addon - caught, the hash moves.
---   * a download that was corrupted or half-written - caught.
---   * somebody handing you a WHOLE fake BiSGuild - NOT caught by this number, because they would
---     change this line too. Nothing inside a file can prove the file is genuine. The only defence
---     is where you got it, which is why the warning says that first and the hash second.
---
--- The addon cannot check the script itself: no file I/O, the same wall as everything else here. So
--- the player is given the command to check it with, and the answer to compare against. The
--- authority is the copy published on GitHub, not this constant - a constant can be edited by
--- whoever edited the script.
---
--- PUBLISHED AT THE TOP OF EVERY RELEASE (Arn's idea, 4 Oct): the hash goes in the CHANGELOG and on
--- the CurseForge page, so the number to compare against lives somewhere the person handing you a
--- copy does not control. That is the half that makes the hash worth anything.
---
--- REGENERATE with Tools\stamp.ps1 whenever logreport.ps1 changes; `-Check` says whether they still
--- agree. The suite asserts the SHAPE of this constant only - it cannot compute SHA-256 in Lua, so
--- a script edited without restamping is NOT caught automatically yet. That gap is on the desk.
P.SCRIPT_SHA = "64E58A59C45E4AC505AF570AB89C0336F93E535F2A9ECECCFB9755BA2ECBE216"

--- WHERE THE LOGS LIVE, asked once and remembered (4 Oct 2026).
---
--- Arn: "we should ask one time copy the path to your logs folder once and from there we generate
--- a ps script they can powershell to do the whole process".
---
--- The addon cannot write that script - no file I/O, the same wall that stops it reading the log.
--- What it CAN do is print the command, already filled in. One path is all it needs: the WoW folder
--- is the Logs folder with \Logs taken off, and every installed copy of this addon is under that,
--- so one answer reaches all of them.
function P.SetLogs(path)
    path = tostring(path or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub('^"', ""):gsub('"$', "")
    if path == "" then return nil, "nothing" end
    -- a trailing slash would make the derived WoW folder wrong by one level
    path = path:gsub("[\\/]+$", "")
    if not path:lower():find("logs$") then return nil, "not a logs folder" end
    ns.DB().logs = path
    return path
end

function P.Logs()
    local p = ns.DB().logs
    return type(p) == "string" and p ~= "" and p or nil
end

--- Where the shipped script is, worked out from the Logs folder. Nil until that is known.
--- ONE LEVEL UP, NOT TWO (fixed 5 Oct 2026, off Arn's screen).
---
--- He set `x:\logs`, was told "logs folder remembered", and then `/bisg script` said "tell me where
--- your logs are first". The first version went up TWO levels and re-appended the flavour folder,
--- which silently needs the path to be at least `<something>\<flavour>\Logs` - so anything shallower
--- matched nothing and the addon denied knowing a folder it had just confirmed.
---
--- `Logs` and `Interface` are SIBLINGS inside the client folder. Dropping the last part is the whole
--- derivation, it works at any depth, and it was what the two-level version was laboriously
--- reconstructing anyway.
function P.ScriptPath()
    local logs = P.Logs()
    if not logs then return nil end
    local client = logs:match("^(.*)[\\/][^\\/]+$")      -- drop \Logs; Interface sits beside it
    if not client or client == "" then return nil end
    return client .. "\\Interface\\AddOns\\BiSGuild\\Tools\\logreport.ps1"
end

--- The line to paste into PowerShell. Nil until the folder is known.
function P.Command()
    local script = P.ScriptPath()
    local logs = P.Logs()
    if not (script and logs) then return nil end
    return ('powershell -ExecutionPolicy Bypass -File "%s" -Logs "%s"'):format(script, logs)
end

--- What the last written report holds, or nil. Shape, from logreport.py:
---   BiSGuildReport = { written = <epoch>, kills = <n>, zones = "...",
---                      rows = { { name =, attend =, consumes = }, ... } }
function P.Report()
    local r = _G.BiSGuildReport
    if type(r) ~= "table" or type(r.rows) ~= "table" then return nil end
    return r
end

--- One person's imported numbers, or nil for somebody not in the report.
function P.Of(name)
    local r = P.Report()
    if not r then return nil end
    for _, row in ipairs(r.rows) do
        if row.name == name then return row end
    end
    return nil
end

--- Everyone, best attendance first, then best consumes, then by name - so the same report always
--- prints in the same order and two councils reading it see the same list.
function P.Rows()
    local r = P.Report()
    if not r then return {} end
    local out = {}
    for _, row in ipairs(r.rows) do out[#out + 1] = row end
    table.sort(out, function(a, b)
        if (a.attend or 0) ~= (b.attend or 0) then return (a.attend or 0) > (b.attend or 0) end
        if (a.consumes or 0) ~= (b.consumes or 0) then return (a.consumes or 0) > (b.consumes or 0) end
        return tostring(a.name) < tostring(b.name)
    end)
    return out
end
