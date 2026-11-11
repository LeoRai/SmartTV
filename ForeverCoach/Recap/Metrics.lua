-- Combat recap (stage 3): what the numbers mean and how they read. Pure functions over a fight
-- record, shared by the recorder, the window and the tests.
--
-- A fight record (saved, last 10 per character):
--   { at = "05:41", target, dur, presses, matched, reactSum, reactN, idle, pauses,
--     debuffUp, debuffTotal, procs, missed, procTalent = { key, level } | nil,
--     events = "oox-oo" (o: as hinted, x: otherwise, -: idle pause), errors = { ... },
--     blind (no-hints mode), build, mode, level, score }
-- An error: { t = seconds into the fight, kind = "miss" | "idle", pressed, pressedId, hint, hintId,
--             reason = "down" | "low" | "proc" | "mana" | "aoe" | "why", arg, gap }
local ADDON, ns = ...
local L, API, Data = ns.L, ns.API, ns.Data

local Metrics = {
    IDLE_PAUSE = 1.5,             -- a pause longer than this while the player could act is idle time
    PRESS_WINDOW = 1.5,           -- a press matches a hint shown within one global cooldown before it
    REACT_FAST = 0.3,             -- reaction up to this: speed 100%
    REACT_SLOW = 1.5,             -- reaction from this: speed 50%
    REACT_CAP = 3,                -- longer waits count as this (they are idle pauses anyway)
    MAX_ERRORS = 8,               -- errors kept per fight
    FIGHTS_KEPT = 10,
    SESSIONS_KEPT = 20,
    GOOD = 0.85,                  -- accuracy colors: green from 85%,
    OK = 0.80,                    -- plain from 80%, orange below
}
ns.RecapMetrics = Metrics

function Metrics.Accuracy(f)
    if not f or (f.presses or 0) == 0 then return nil end
    return f.matched / f.presses
end

function Metrics.Uptime(f)
    if not f or (f.debuffTotal or 0) <= 0 then return nil end
    return f.debuffUp / f.debuffTotal
end

function Metrics.Reaction(f)
    if not f or (f.reactN or 0) == 0 then return nil end
    return f.reactSum / f.reactN
end

-- Speed from the average reaction: 100% up to 0.3 s, down to 50% at 1.5 s and slower.
function Metrics.Speed(reaction)
    if not reaction then return 1 end
    if reaction <= Metrics.REACT_FAST then return 1 end
    if reaction >= Metrics.REACT_SLOW then return 0.5 end
    return 1 - 0.5 * (reaction - Metrics.REACT_FAST) / (Metrics.REACT_SLOW - Metrics.REACT_FAST)
end

-- Score: accuracy times speed, up to 1000.
function Metrics.Score(f)
    local acc = Metrics.Accuracy(f)
    if not acc then return 0 end
    return math.floor(1000 * acc * Metrics.Speed(Metrics.Reaction(f)) + 0.5)
end

function Metrics.Percent(x)
    if not x then return "—" end
    return string.format("%d%%", math.floor(x * 100 + 0.5))
end

-- 24 -> "0:24", 75 -> "1:15"
function Metrics.Clock(seconds)
    seconds = math.max(0, math.floor((seconds or 0) + 0.5))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- 2.1 -> "2,1" in Russian, "2.1" in English.
function Metrics.Seconds(x)
    local s = string.format("%.1f", x or 0)
    if L.DECIMAL and L.DECIMAL ~= "." then s = s:gsub("%.", L.DECIMAL) end
    return s
end

function Metrics.AccuracyColor(acc, C)
    if not acc then return C.muted end
    if acc >= Metrics.GOOD then return C.good end
    if acc >= Metrics.OK then return C.text end
    return C.aoe
end

local function nameOf(key, id)
    if id then
        local name = API.SpellName(id)
        if name then return name end
    end
    local def = Data.class
    local sp = def and def.spells[key]
    if sp then return API.SpellName(sp.ranks[1][1]) or key end
    return tostring(key)
end
Metrics.NameOf = nameOf

-- Why the hint was what it was, in words.
local function reasonText(e)
    if e.reason == "down" then return L.R_WHY_DOWN end
    if e.reason == "low" then return L.R_WHY_LOW end
    if e.reason == "proc" then return L.R_WHY_PROC end
    if e.reason == "mana" then return L.R_WHY_MANA end
    if e.reason == "aoe" then return ns.Count(e.arg or 3, L.R_WHY_AOE) end
    if e.reason == "why" and e.arg then return ns.Tr(e.arg, nil) end
    return nil
end

-- An error line: "Shadow Bolt instead of Corruption", "— Corruption was not on the target".
-- Returns the main text and the reason (nil when there is nothing to add).
function Metrics.ErrorText(e)
    if e.kind == "idle" then
        local text = string.format(L.R_ERR_IDLE, Metrics.Seconds(e.gap))
        local reason = e.hint and string.format(L.R_IDLE_HINT, nameOf(e.hint, e.hintId)) or nil
        return text, reason
    end
    return string.format(L.R_ERR_MISS, nameOf(e.pressed, e.pressedId), nameOf(e.hint, e.hintId)), reasonText(e)
end

-- Session summary: { fights, accuracy, previous (accuracy of the last earlier session), delta }.
function Metrics.Session(current, sessions)
    local out = { fights = current and current.fights or 0 }
    out.accuracy = current and current.fights > 0 and current.accSum / current.fights or nil
    for i = #(sessions or {}), 1, -1 do
        local past = sessions[i]
        if past ~= current and past.fights > 0 and (not current or (past.start or 0) <= (current.start or 0)) then
            out.previous = past.accSum / past.fights
            break
        end
    end
    if out.accuracy and out.previous then out.delta = out.accuracy - out.previous end
    return out
end
