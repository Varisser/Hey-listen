-- Death Roll Ledger - core: saved data, ledger bookkeeping, formatting, slash commands
local ADDON, ns = ...

ns.OTHER = "__other" -- bucket for gold changes that can't be tied to a player
ns.modules = {}

local defaults = {
    enabled = false,     -- the on-screen toggle
    countOther = true,   -- count gold changes with no player (loot, vendor...) toward the total
    players = {},        -- [name] = { net, wins, losses, history = { {t, amt, src, note}, ... } }
    other = nil,         -- same shape as a player bucket
    button = nil,        -- saved position of the toggle button
    window = nil,        -- saved position of the ledger window
}

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff7f3fDeath Roll|r " .. tostring(msg))
end

-- Midnight-style "secret values": the game can hand addons opaque values
-- (for example chat text inside instances). Comparing them throws, so check first.
function ns.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

---------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------
local myRealm
-- "Name", "Name-Realm" or (name, realm) -> "Name" on your realm, "Name-Realm" otherwise.
function ns.NormalizeName(name, realm)
    if not name or ns.IsSecret(name) or name == "" then return nil end
    if not realm or realm == "" then
        name, realm = strsplit("-", name, 2)
    end
    myRealm = myRealm or (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
    if realm and realm ~= "" then
        local r = realm:gsub("[%s%-]", "")
        if r ~= myRealm then return name .. "-" .. realm end
    end
    return name
end

function ns.MyName()
    return ns.NormalizeName(UnitName("player"))
end

---------------------------------------------------------------------------
-- Money formatting / parsing
---------------------------------------------------------------------------
function ns.FormatMoney(copper, signed)
    copper = copper or 0
    local neg = copper < 0
    local c = math.abs(copper)
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = (BreakUpLargeNumbers and BreakUpLargeNumbers(g) or g) .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if cp > 0 or #parts == 0 then parts[#parts + 1] = cp .. "c" end
    local str = table.concat(parts, " ")
    if neg then return "-" .. str end
    if signed and copper > 0 then return "+" .. str end
    return str
end

-- Signed and coloured: green for winnings, red for losses, grey for even.
function ns.ColorMoney(copper)
    local str = ns.FormatMoney(copper, true)
    if copper > 0 then return "|cff33ff33" .. str .. "|r" end
    if copper < 0 then return "|cffff4040" .. str .. "|r" end
    return "|cffaaaaaa" .. str .. "|r"
end

-- "5" (gold), "5g", "5g20s", "-3g 50s", "75c" -> copper, or nil
function ns.ParseMoney(str)
    if not str then return nil end
    str = str:lower():gsub("%s", "")
    local sign = 1
    if str:sub(1, 1) == "-" then sign, str = -1, str:sub(2)
    elseif str:sub(1, 1) == "+" then str = str:sub(2) end
    if str == "" then return nil end
    if str:match("^%d+$") then return sign * tonumber(str) * 10000 end
    if str:gsub("%d+[gsc]", "") ~= "" then return nil end
    local mult = { g = 10000, s = 100, c = 1 }
    local total = 0
    for num, unit in str:gmatch("(%d+)([gsc])") do
        total = total + tonumber(num) * mult[unit]
    end
    return sign * total
end

---------------------------------------------------------------------------
-- Ledger
---------------------------------------------------------------------------
local function NewBucket()
    return { net = 0, wins = 0, losses = 0, history = {} }
end

function ns.GetBucket(key, create)
    local db = DeathRollLedgerDB
    if key == ns.OTHER then
        if not db.other and create then db.other = NewBucket() end
        return db.other
    end
    local b = db.players[key]
    if not b and create then
        b = NewBucket()
        db.players[key] = b
    end
    return b
end

-- Fired after any change so the UI can redraw.
function ns.Changed()
    for _, m in pairs(ns.modules) do
        if m.Refresh then m:Refresh() end
    end
end

-- Adds a money entry. key = player name or ns.OTHER.
function ns.Record(key, amount, src, note)
    if not key or amount == 0 then return end
    local b = ns.GetBucket(key, true)
    table.insert(b.history, { t = time(), amt = amount, src = src, note = note })
    b.net = b.net + amount
    if key ~= ns.OTHER then
        ns.Print(("%s %s with |cffffffff%s|r (%s). Net with them: %s"):format(
            amount > 0 and "Won" or "Lost", ns.FormatMoney(math.abs(amount)), key, src, ns.ColorMoney(b.net)))
    end
    ns.Changed()
end

-- Adds a zero-value death roll result entry and updates the win/loss count.
function ns.RecordRoll(key, won, note)
    local b = ns.GetBucket(key, true)
    table.insert(b.history, { t = time(), amt = 0, src = "Roll", note = note, won = won })
    if won then b.wins = b.wins + 1 else b.losses = b.losses + 1 end
    ns.Changed()
end

function ns.DeleteEntry(key, index)
    local b = ns.GetBucket(key)
    local e = b and b.history[index]
    if not e then return end
    table.remove(b.history, index)
    b.net = b.net - e.amt
    if e.src == "Roll" then
        if e.won == true then b.wins = math.max(0, b.wins - 1)
        elseif e.won == false then b.losses = math.max(0, b.losses - 1) end
    end
    if key ~= ns.OTHER and #b.history == 0 then DeathRollLedgerDB.players[key] = nil end
    ns.Changed()
end

-- Moves a money entry to another player (fixes a wrong or missing attribution).
function ns.MoveEntry(fromKey, index, toName)
    local toKey = toName == ns.OTHER and ns.OTHER or ns.NormalizeName(toName)
    local b = ns.GetBucket(fromKey)
    local e = b and b.history[index]
    if not e or not toKey or toKey == fromKey then return end
    ns.DeleteEntry(fromKey, index)
    local dest = ns.GetBucket(toKey, true)
    table.insert(dest.history, e)
    table.sort(dest.history, function(a, c) return a.t < c.t end)
    dest.net = dest.net + e.amt
    ns.Changed()
end

-- Total winnings: every player's net, plus unattributed gold if enabled.
function ns.GetTotal()
    local db = DeathRollLedgerDB
    local total = 0
    for _, b in pairs(db.players) do total = total + b.net end
    if db.countOther and db.other then total = total + db.other.net end
    return total
end

function ns.SetEnabled(state)
    DeathRollLedgerDB.enabled = state and true or false
    if ns.modules.Money then ns.modules.Money:ResetBaseline() end
    ns.Print("Tracking " .. (state and "|cff00ff00ON|r - gold gained or lost now counts as winnings."
        or "|cffff0000OFF|r"))
    ns.Changed()
end

function ns.IsEnabled()
    return DeathRollLedgerDB and DeathRollLedgerDB.enabled
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
local core = CreateFrame("Frame")
core:RegisterEvent("ADDON_LOADED")
core:RegisterEvent("PLAYER_LOGIN")
core:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        DeathRollLedgerDB = DeathRollLedgerDB or {}
        for k, v in pairs(defaults) do
            if DeathRollLedgerDB[k] == nil and v ~= nil then
                DeathRollLedgerDB[k] = type(v) == "table" and {} or v
            end
        end
    elseif event == "PLAYER_LOGIN" then
        for _, m in pairs(ns.modules) do
            if m.Init then m:Init() end
        end
        if DeathRollLedgerDB.enabled then
            ns.Print("Tracking is still |cff00ff00ON|r from last session.")
        end
        ns.Changed()
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_DEATHROLLLEDGER1 = "/deathroll"
SLASH_DEATHROLLLEDGER2 = "/drl"
SLASH_DEATHROLLLEDGER3 = "/dr"
SlashCmdList.DEATHROLLLEDGER = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    local ui = ns.modules.UI
    if cmd == "" or cmd == "show" then
        ui:ToggleWindow()
    elseif cmd == "toggle" then
        ns.SetEnabled(not ns.IsEnabled())
    elseif cmd == "on" then
        ns.SetEnabled(true)
    elseif cmd == "off" then
        ns.SetEnabled(false)
    elseif cmd == "add" then
        local name, amt = rest:match("^(%S+)%s+(%S+)$")
        local copper = ns.ParseMoney(amt)
        name = ns.NormalizeName(name)
        if not name or not copper or copper == 0 then
            ns.Print("usage: /dr add <player> <amount>  e.g. /dr add Bob 5g  or  /dr add Bob -2g50s")
            return
        end
        ns.Record(name, copper, "Manual")
    elseif cmd == "other" then
        DeathRollLedgerDB.countOther = not DeathRollLedgerDB.countOther
        ns.Print("Gold with no player (loot, vendors, repairs) " ..
            (DeathRollLedgerDB.countOther and "|cff00ff00counts|r" or "|cffff0000does not count|r") ..
            " toward the total.")
        ns.Changed()
    elseif cmd == "reset" then
        StaticPopup_Show("DEATHROLLLEDGER_RESET")
    elseif cmd == "resetpos" then
        ui:ResetPositions()
    else
        ns.Print("commands:")
        ns.Print("  /dr               - open the ledger")
        ns.Print("  /dr on | off | toggle - start or stop tracking (same as the button)")
        ns.Print("  /dr add <player> <amount> - add a manual entry, e.g. /dr add Bob -2g50s")
        ns.Print("  /dr other         - count/ignore gold with no player in the total")
        ns.Print("  /dr resetpos      - move the button and window back to default")
        ns.Print("  /dr reset         - wipe all history")
        ns.Print("  Shift-drag the button to move it.")
    end
end
