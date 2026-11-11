-- Time to die: how fast the target's health falls (least squares over the last seconds).
-- Keeps the engine from putting long debuffs on a target that is about to die.
-- When target health is hidden in combat there are no samples and Core/State.lua falls back
-- to "the target lives long" (see State.FALLBACK).
local ADDON, ns = ...

local TTD = {
    window = 12,      -- seconds of history
    minSamples = 3,
    minSpan = 1.5,    -- seconds between the first and the last sample
    size = 0, first = 1,
    ts = {}, hp = {},
    guid = nil,
}
ns.TTD = TTD

local CAPACITY = 64

function TTD:Reset(guid)
    self.guid = guid
    self.size, self.first = 0, 1
end

local function at(self, i)
    local idx = (self.first + i - 2) % CAPACITY + 1
    return self.ts[idx], self.hp[idx]
end

-- Add a health sample (percent) for the target with this GUID.
function TTD:Add(guid, t, pct)
    if guid ~= self.guid then self:Reset(guid) end
    if self.size > 0 then
        local lastT, lastHp = at(self, self.size)
        if t - lastT < 0.1 then return end           -- too close to the previous sample
        if pct > lastHp + 5 then self:Reset(guid) end -- healed or reset: start over
    end
    -- drop samples outside the window
    while self.size > 0 do
        local t0 = at(self, 1)
        if t - t0 <= self.window then break end
        self.first = self.first % CAPACITY + 1
        self.size = self.size - 1
    end
    if self.size == CAPACITY then
        self.first = self.first % CAPACITY + 1
        self.size = self.size - 1
    end
    self.size = self.size + 1
    local idx = (self.first + self.size - 2) % CAPACITY + 1
    self.ts[idx], self.hp[idx] = t, pct
end

-- Seconds until the target reaches 0%, or nil when unknown or not dropping.
function TTD:Get(now)
    local n = self.size
    if n < self.minSamples then return nil end
    local t0 = at(self, 1)
    local tn = at(self, n)
    if tn - t0 < self.minSpan then return nil end
    local sx, sy, sxx, sxy = 0, 0, 0, 0
    for i = 1, n do
        local t, hp = at(self, i)
        local x = t - t0
        sx, sy = sx + x, sy + hp
        sxx, sxy = sxx + x * x, sxy + x * hp
    end
    local denom = n * sxx - sx * sx
    if denom <= 0 then return nil end
    local slope = (n * sxy - sx * sy) / denom   -- % per second
    if slope >= -0.01 then return nil end        -- not dropping
    local intercept = (sy - slope * sx) / n
    local current = intercept + slope * (now - t0)
    if current <= 0 then return 0 end
    return current / -slope
end
