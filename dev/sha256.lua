--[[
  BiSGuild :: dev/sha256.lua - SHA-256 in plain Lua 5.1, for the suite only.

  WHY THIS EXISTS. The addon shows a hash of the PowerShell script it ships, and the CurseForge page
  publishes the same number so a player can compare. Keeping those two in step was a thing somebody
  had to remember - `Tools\stamp.ps1` by hand - and on 5 Oct nobody did: Arn ran the check, got
  BBFE79CF..., and the window said 64E58A59.... The one number on that page whose whole job is to
  match did not match, which is worse than having no check at all.

  "Lua 5.1 cannot compute SHA-256" was the reason it was never enforced. It can; it just has no
  bitwise operators, so the 32-bit work is done with arithmetic. Seventy lines, run once per suite.

  VERIFIED AGAINST THE CLIENT'S OWN ANSWER, not against my memory of the algorithm: the suite checks
  the three published NIST vectors AND the real .ps1 against what Get-FileHash said. An
  implementation of a hash written from memory and never checked is exactly the kind of thing that
  looks right and is not.

  Not shipped - dev/ is stripped by deploy.sh. The game never computes a hash.
]]

local K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local band, bxor, bnot, rrot, shr

-- 32-bit arithmetic without bitwise operators. Slow and correct; the suite hashes one file.
local function bits(a, b, f)
  local r, bit = 0, 1
  for _ = 1, 32 do
    local x, y = a % 2, b % 2
    r = r + f(x, y) * bit
    a, b, bit = (a - x) / 2, (b - y) / 2, bit * 2
  end
  return r
end

band = function(a, b) return bits(a, b, function(x, y) return (x == 1 and y == 1) and 1 or 0 end) end
bxor = function(a, b) return bits(a, b, function(x, y) return (x ~= y) and 1 or 0 end) end
bnot = function(a) return 4294967295 - a end
shr  = function(a, n) return math.floor(a / 2 ^ n) end
-- ONLY THE LOW n BITS GET SHIFTED UP. `a * 2^(32-n)` overflows a double's exact range (a is up to
-- 2^32, so the product reaches 2^63 and the low bits are silently lost) - which produced a hash
-- that looked like a hash and matched nothing. Caught by the NIST vectors on the first run.
rrot = function(a, n)
  local low = a % 2 ^ n
  return shr(a, n) + low * 2 ^ (32 - n)
end

local function sha256(msg)
  local h = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
              0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }

  local len = #msg
  msg = msg .. "\128" .. string.rep("\0", (55 - len) % 64)
  -- the length is 64 bits; a WoW addon's script is never 512 MB, so the high word is zero
  local bitlen = len * 8
  local tail = ""
  for i = 7, 0, -1 do tail = tail .. string.char(math.floor(bitlen / 2 ^ (8 * i)) % 256) end
  msg = msg .. tail

  for chunk = 1, #msg, 64 do
    local w = {}
    for i = 0, 15 do
      local a, b, c, d = msg:byte(chunk + i * 4, chunk + i * 4 + 3)
      w[i + 1] = ((a * 256 + b) * 256 + c) * 256 + d
    end
    for i = 17, 64 do
      local v = w[i - 15]
      local s0 = bxor(bxor(rrot(v, 7), rrot(v, 18)), shr(v, 3))
      v = w[i - 2]
      local s1 = bxor(bxor(rrot(v, 17), rrot(v, 19)), shr(v, 10))
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) % 4294967296
    end

    local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
    for i = 1, 64 do
      local S1 = bxor(bxor(rrot(e, 6), rrot(e, 11)), rrot(e, 25))
      local ch = bxor(band(e, f), band(bnot(e), g))
      local t1 = (hh + S1 + ch + K[i] + w[i]) % 4294967296
      local S0 = bxor(bxor(rrot(a, 2), rrot(a, 13)), rrot(a, 22))
      local mj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
      local t2 = (S0 + mj) % 4294967296
      hh, g, f, e = g, f, e, (d + t1) % 4294967296
      d, c, b, a = c, b, a, (t1 + t2) % 4294967296
    end
    h[1] = (h[1] + a) % 4294967296  h[2] = (h[2] + b) % 4294967296
    h[3] = (h[3] + c) % 4294967296  h[4] = (h[4] + d) % 4294967296
    h[5] = (h[5] + e) % 4294967296  h[6] = (h[6] + f) % 4294967296
    h[7] = (h[7] + g) % 4294967296  h[8] = (h[8] + hh) % 4294967296
  end

  local out = {}
  for i = 1, 8 do out[i] = string.format("%08X", h[i]) end
  return table.concat(out)
end

return sha256
