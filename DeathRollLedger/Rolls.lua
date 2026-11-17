-- Death Roll Ledger - death roll detection from /roll system messages
--
-- A death roll: someone rolls 1-N, the next player rolls 1-(previous result),
-- and so on until someone rolls a 1 and loses. Results involving you are
-- added to that player's history with a win/loss count. Gold itself is
-- tracked by Money.lua when it actually changes hands.
local ADDON, ns = ...
local R = {}
ns.modules.Rolls = R

local GAME_TIMEOUT = 180 -- seconds between rolls before a game is abandoned

local rollPattern
local function BuildPattern()
    local fmt = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
    fmt = fmt:gsub("%%%d%$", "%%")                         -- "%1$s" -> "%s"
    fmt = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")   -- escape pattern characters
    fmt = fmt:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    rollPattern = "^" .. fmt .. "$"
end

local game -- { start, last, result, rolls, t }

local function FinishGame(winner, loser)
    local me = ns.MyName()
    local start = game.start
    game = nil
    if winner ~= me and loser ~= me then return end
    local opp = winner == me and loser or winner
    local won = winner == me
    ns.RecordRoll(opp, won, ("%s death roll (1-%s)"):format(won and "Won" or "Lost",
        BreakUpLargeNumbers and BreakUpLargeNumbers(start) or start))
    local b = ns.GetBucket(opp)
    ns.Print(("You %s the death roll against |cffffffff%s|r. Record vs them: %d-%d"):format(
        won and "|cff33ff33won|r" or "|cffff4040lost|r", opp, b.wins, b.losses))
end

function R:OnRoll(name, roll, low, high)
    if low ~= 1 then return end
    name = ns.NormalizeName(name)
    if not name then return end
    local now = GetTime()

    if game and high == game.result and name ~= game.last and now - game.t < GAME_TIMEOUT then
        game.rolls = game.rolls + 1
    else
        game = { start = high, rolls = 1 }
    end
    local previous = game.last
    game.last, game.result, game.t = name, roll, now

    if roll == 1 and game.rolls >= 2 then
        FinishGame(previous, name)
    elseif roll == 1 then
        game = nil
    end
end

local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(_, _, msg)
    if not ns.IsEnabled() or type(msg) ~= "string" or ns.IsSecret(msg) then return end
    local name, roll, low, high = msg:match(rollPattern)
    if name then
        R:OnRoll(name, tonumber(roll), tonumber(low), tonumber(high))
    end
end)

function R:Init()
    BuildPattern()
    f:RegisterEvent("CHAT_MSG_SYSTEM")
end
