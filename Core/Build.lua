-- BiSGuild :: Core/Build.lua - written by Tools\stamp.ps1. Never edit it by hand.
--
-- What this copy says it is. Every file of ours ends by writing its version into ns.parts, and
-- Core/Copies.lua checks them against this list at login: a file missing, failing to load, or
-- left over from another version, and BiS Guild says so and stops. The fingerprint is the
-- SHA-256 of Tools/manifest.txt. This file is not inside it (it holds it); logreport.ps1 checks
-- instead that it is exactly this text and nothing else.
local _, ns = ...
ns.BUILD = {
    version = "0.1.0",
    fingerprint = "D0375501644F887783CC69320842BDA7696F962DE882782BFE520070D68B3F33",
    parts = {
        "Core/Init.lua",
        "Core/Report.lua",
        "Core/Store.lua",
        "Core/Share.lua",
        "Core/Copies.lua",
        "Core/Window.lua",
        "Core/Terminal.lua",
        "Core/Where.lua",
        "Core/Pins.lua",
        "Core/Invite.lua",
        "Core/Logins.lua",
        "Core/Loot.lua",
        "API.lua",
        "Core/Say.lua",
    },
}
