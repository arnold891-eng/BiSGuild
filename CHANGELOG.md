# BiSGuild

## Unreleased

- Shared messaging library updated (LibBiSComm minor 10): after a boss, when the game lifts its chat lockdown, BiS addons say hello again so group lists stay current; it respects a realm that blocks addon messages, picks the raid channel only when the game confirms you are in a raid, and ignores anyone flooding it.

## 0.0.1

- Created from the BiS house skeleton (`_bisdev/new-addon.sh`): shared BiS channel, palette, tests, CI and
  release from GitHub already wired.
- Window: the report's "last" line keeps the kill count; the boss names moved into its tooltip. A full
  Black Temple night ran the line out of the window.
