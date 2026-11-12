-- Hey Listen! - fishing pole reminder and "you're attacking with a fishing pole" warning
local ADDON, ns = ...

local M = {}
ns.modules.Fishing = M

local MAINHAND = INVSLOT_MAINHAND or 16
local OFFHAND = INVSLOT_OFFHAND or 17
local WEAPON_CLASS = 2      -- Enum.ItemClass.Weapon
local FISHING_POLE = 20     -- Enum.ItemWeaponSubclass.Fishingpole
local SOUND_REPEAT = 4      -- seconds between repeated warning sounds while auto-attacking

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local EquipItemByName = (C_Item and C_Item.EquipItemByName) or EquipItemByName

local attacking, inCombat = false, false
local warningActive, lastSound, testUntil = false, 0, 0

local function IsFishingPole(itemID)
    if not itemID then return false end
    local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemID)
    return classID == WEAPON_CLASS and subclassID == FISHING_POLE
end

local function FishingPoleEquipped()
    return IsFishingPole(GetInventoryItemID("player", MAINHAND))
end

-- Remember whatever weapons you had on before swapping to the pole.
local function RememberWeapons()
    local mh = GetInventoryItemID("player", MAINHAND)
    if mh and not IsFishingPole(mh) then
        HeyListenDB.lastWeapons = {
            main = GetInventoryItemLink("player", MAINHAND),
            off = GetInventoryItemLink("player", OFFHAND) or false,
        }
    end
end

function M:EquipWeapons()
    local w = HeyListenDB.lastWeapons
    if not w or not w.main then
        ns.Print("I don't know which weapons you used before - equip them manually once.")
        return
    end
    EquipItemByName(w.main, MAINHAND)
    if w.off then EquipItemByName(w.off, OFFHAND) end
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local status, warning

local function BuildFrames()
    -- Small, out-of-the-way reminder.
    status = CreateFrame("Frame", "HeyListenFishingStatus", UIParent)
    status:SetSize(190, 20)
    status:SetFrameStrata("LOW")
    status.text = status:CreateFontString(nil, "OVERLAY")
    status.text:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
    status.text:SetPoint("CENTER")
    status.text:SetTextColor(1, 0.75, 0.2)
    status.text:SetText("|TInterface\\Icons\\Trade_Fishing:14:14|t Fishing Pole equipped")
    ns.MakeMovable(status, "fishingStatus", "Fishing reminder", { "TOP", "TOP", 0, -40 })

    -- In-your-face warning.
    warning = CreateFrame("Frame", "HeyListenFishingWarning", UIParent)
    warning:SetAllPoints(UIParent)
    warning:SetFrameStrata("FULLSCREEN_DIALOG")
    warning:EnableMouse(false)
    warning:Hide()

    local vignette = warning:CreateTexture(nil, "BACKGROUND")
    vignette:SetAllPoints()
    vignette:SetTexture("Interface\\FullScreenTextures\\LowHealth")
    vignette:SetBlendMode("ADD")
    vignette:SetVertexColor(1, 0, 0, 1)

    local icon = warning:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\Trade_Fishing")
    icon:SetSize(72, 72)
    icon:SetPoint("BOTTOM", UIParent, "CENTER", 0, 150)

    local big = warning:CreateFontString(nil, "OVERLAY")
    big:SetFont(STANDARD_TEXT_FONT, 38, "THICKOUTLINE")
    big:SetPoint("TOP", icon, "BOTTOM", 0, -10)
    big:SetTextColor(1, 0.1, 0.1)
    big:SetText("YOU'RE ATTACKING WITH A FISHING POLE!")

    warning.sub = warning:CreateFontString(nil, "OVERLAY")
    warning.sub:SetFont(STANDARD_TEXT_FONT, 18, "OUTLINE")
    warning.sub:SetPoint("TOP", big, "BOTTOM", 0, -8)
    warning.sub:SetTextColor(1, 1, 1)

    local pulse = warning:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.35)
    a:SetDuration(0.45)
    warning.pulse = pulse
end

local function WeaponHint()
    local w = HeyListenDB.lastWeapons
    if w and w.main then
        local s = "Equip " .. w.main
        if w.off then s = s .. " + " .. w.off end
        return s .. "  (|cffffff00/hl swap|r)"
    end
    return "Equip your weapons!"
end

function M:Update()
    if not status then return end
    local enabled = HeyListenDB.fishing
    local pole = enabled and FishingPoleEquipped()
    local testing = GetTime() < testUntil
    local danger = testing or (pole and (attacking or inCombat))

    status:SetShown(ns.unlocked or (pole and not danger))

    if danger and not warningActive then
        warningActive = true
        warning.sub:SetText(WeaponHint())
        warning:Show()
        warning.pulse:Play()
        ns.PlayAlert()
        lastSound = GetTime()
    elseif not danger and warningActive then
        warningActive = false
        warning.pulse:Stop()
        warning:Hide()
    end
end

function M:Test()
    testUntil = GetTime() + 4
    self:Update()
end

function M:Init()
    BuildFrames()
    inCombat = UnitAffectingCombat("player") and true or false
    RememberWeapons()

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTER_COMBAT")   -- auto-attack switched on
    ev:RegisterEvent("PLAYER_LEAVE_COMBAT")   -- auto-attack switched off
    ev:RegisterEvent("PLAYER_REGEN_DISABLED") -- entered combat
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")  -- left combat
    ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTER_COMBAT" then
            attacking = true
        elseif event == "PLAYER_LEAVE_COMBAT" then
            attacking = false
        elseif event == "PLAYER_REGEN_DISABLED" then
            inCombat = true
        elseif event == "PLAYER_REGEN_ENABLED" then
            inCombat = false
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            RememberWeapons()
        end
        M:Update()
    end)

    -- Keeps the test preview timing out and repeats the alarm while you keep swinging.
    local elapsed = 0
    ev:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.25 then return end
        elapsed = 0
        if testUntil > 0 and GetTime() >= testUntil then
            testUntil = 0
            M:Update()
        end
        if warningActive and attacking and GetTime() - lastSound >= SOUND_REPEAT then
            ns.PlayAlert()
            lastSound = GetTime()
        end
    end)
end
