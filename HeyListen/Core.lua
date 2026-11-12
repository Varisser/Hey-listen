-- Hey Listen! - core: saved variables, movable frames, slash commands
local ADDON, ns = ...

ns.movables = {}
ns.modules = {}
ns.unlocked = false

local defaults = {
    fishing = true,
    totems = true,
    quests = true,
    sound = true,
    positions = {},
}

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffHey Listen!|r " .. tostring(msg))
end

function ns.PlayAlert()
    if HeyListenDB and HeyListenDB.sound then
        local kit = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959
        PlaySound(kit, "Master")
    end
end

-- Calls Update() on every module (used after settings change / unlock).
function ns.RefreshAll()
    for _, m in pairs(ns.modules) do
        if m.Update then m:Update() end
    end
end

---------------------------------------------------------------------------
-- Movable frames
---------------------------------------------------------------------------
local function SavePosition(frame)
    local point, _, relPoint, x, y = frame:GetPoint()
    HeyListenDB.positions[frame.hlKey] = { point, relPoint, x, y }
end

function ns.RestorePosition(frame)
    frame:ClearAllPoints()
    local pos = HeyListenDB.positions[frame.hlKey]
    if pos then
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        local d = frame.hlDefault
        frame:SetPoint(d[1], UIParent, d[2], d[3], d[4])
    end
end

-- Registers a frame so it can be dragged around with /hl unlock.
function ns.MakeMovable(frame, key, label, defaultPoint)
    frame.hlKey = key
    frame.hlDefault = defaultPoint
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f) if ns.unlocked then f:StartMoving() end end)
    frame:SetScript("OnDragStop", function(f) f:StopMovingOrSizing(); SavePosition(f) end)
    frame:EnableMouse(false) -- click-through unless unlocked

    local overlay = frame:CreateTexture(nil, "BACKGROUND")
    overlay:SetAllPoints()
    overlay:SetColorTexture(0.2, 0.6, 1, 0.35)
    overlay:Hide()
    frame.hlOverlay = overlay

    local tag = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tag:SetPoint("BOTTOM", frame, "TOP", 0, 2)
    tag:SetText(label)
    tag:Hide()
    frame.hlTag = tag

    table.insert(ns.movables, frame)
end

local function SetUnlocked(state)
    ns.unlocked = state
    for _, f in ipairs(ns.movables) do
        f:EnableMouse(state)
        f.hlOverlay:SetShown(state)
        f.hlTag:SetShown(state)
    end
    ns.RefreshAll()
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
local core = CreateFrame("Frame")
core:RegisterEvent("ADDON_LOADED")
core:RegisterEvent("PLAYER_LOGIN")
core:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        HeyListenDB = HeyListenDB or {}
        for k, v in pairs(defaults) do
            if HeyListenDB[k] == nil then
                HeyListenDB[k] = type(v) == "table" and {} or v
            end
        end
    elseif event == "PLAYER_LOGIN" then
        for _, m in pairs(ns.modules) do
            if m.Init then m:Init() end
        end
        for _, f in ipairs(ns.movables) do ns.RestorePosition(f) end
        ns.RefreshAll()
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function Toggle(key, name)
    HeyListenDB[key] = not HeyListenDB[key]
    ns.Print(name .. " " .. (HeyListenDB[key] and "|cff00ff00enabled|r" or "|cffff0000disabled|r"))
    ns.RefreshAll()
end

SLASH_HEYLISTEN1 = "/heylisten"
SLASH_HEYLISTEN2 = "/hl"
SlashCmdList.HEYLISTEN = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "unlock" or cmd == "move" then
        SetUnlocked(true)
        ns.Print("Frames unlocked - drag them around, then type |cffffff00/hl lock|r.")
    elseif cmd == "lock" then
        SetUnlocked(false)
        ns.Print("Frames locked.")
    elseif cmd == "reset" then
        wipe(HeyListenDB.positions)
        for _, f in ipairs(ns.movables) do ns.RestorePosition(f) end
        ns.Print("Frame positions reset.")
    elseif cmd == "fishing" then
        Toggle("fishing", "Fishing rod warnings")
    elseif cmd == "totems" then
        Toggle("totems", "Totem tracker")
    elseif cmd == "quests" then
        Toggle("quests", "Quest turn-in counter")
    elseif cmd == "sound" then
        Toggle("sound", "Warning sound")
    elseif cmd == "test" then
        if ns.modules.Fishing then ns.modules.Fishing:Test() end
    elseif cmd == "swap" then
        if ns.modules.Fishing then ns.modules.Fishing:EquipWeapons() end
    else
        ns.Print("commands:")
        ns.Print("  /hl unlock | lock  - move the on-screen elements")
        ns.Print("  /hl reset          - reset positions")
        ns.Print("  /hl fishing | totems | quests | sound - toggle features")
        ns.Print("  /hl swap           - re-equip the weapons you had before the fishing pole")
        ns.Print("  /hl test           - preview the fishing pole warning")
    end
end
