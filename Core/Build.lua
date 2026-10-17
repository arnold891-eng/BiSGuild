-- BiSGuild :: Core/Build.lua - written by Tools\stamp.ps1. Never edit it by hand.
--
-- What this copy says it is. Every file of ours ends by writing its version into ns.parts, and
-- Core/Copies.lua checks them against this list at login: a file missing, failing to load, or
-- left over from another version, and BiS Guild says so and stops. The fingerprint is the
-- SHA-256 of Tools/manifest.txt. This file is not inside it (it holds it); logreport.ps1 checks
-- instead that it is exactly this text and nothing else.
local _, ns = ...
ns.BUILD = {
    version = "0.0.1",
    fingerprint = "E22C6B157846971787956C3B647D7A6F9522BA658D7102423CF5FF3B81E72C7C",
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
