-- Hey Listen! - shaman totem tracker: shows how many group members each totem is affecting
--
-- WoW Forever uses the modern addon API, including Midnight's combat restrictions:
--   * GetTotemInfo() returns "secret" values while you're in combat.
--   * Party aura data (C_UnitAuras) can be unreadable while in combat.
-- Secret values can't be compared or used in math, but they *can* be handed straight to
-- widgets (SetTexture, SetCooldown). So out of combat we read everything and show exact
-- counts and timers; in combat we pass the totem's icon/timer straight to the widgets
-- and keep showing the last count we could read (greyed out, marked with "?").
local ADDON, ns = ...

local M = {}
ns.modules.Totems = M

-- GetTotemInfo slots: 1 Fire, 2 Earth, 3 Water, 4 Air. Displayed in totem-bar order.
local DISPLAY_ORDER = { 2, 1, 3, 4 }
local PLACEHOLDER = {
    [1] = "Interface\\Icons\\Spell_Fire_SearingTotem",
    [2] = "Interface\\Icons\\Spell_Nature_EarthBindTotem",
    [3] = "Interface\\Icons\\INV_Spear_04",
    [4] = "Interface\\Icons\\Spell_Nature_InvisibilityTotem",
}
local GROUP_UNITS = { "player", "party1", "party2", "party3", "party4" }
local ICON_SIZE, SPACING = 36, 6
local NO_AURA_GRACE = 2.5 -- seconds after dropping before we decide a totem gives no buff

-- Totems that do their job without putting a buff on anyone, so there is nothing to count.
local NO_AURA = {
    ["searing"] = true, ["magma"] = true, ["fire nova"] = true, ["stoneclaw"] = true,
    ["earthbind"] = true, ["tremor"] = true, ["poison cleansing"] = true,
    ["disease cleansing"] = true, ["sentry"] = true,
}

local IsSecret = issecretvalue or function() return false end
local GetAuraDataByIndex = C_UnitAuras.GetAuraDataByIndex

local function AnySecret(...)
    for i = 1, select("#", ...) do
        if IsSecret((select(i, ...))) then return true end
    end
    return false
end

-- "Strength of Earth Totem IV" / "Grounding Totem Effect" / "Windfury Totem" -> base name
local function Normalize(name)
    name = name:lower()
    name = name:gsub("%s+[ivxl]+$", "")
    name = name:gsub("%s+effect$", "")
    name = name:gsub("%s+totem$", "")
    return name
end

-- Returns a set of normalized buff names, or nil if this unit's auras are unreadable right now.
local function ReadBuffs(unit)
    local set = {}
    for i = 1, 40 do
        local ok, data = pcall(GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok then return nil end
        if not data then return set end
        local name = data.name
        if name == nil or IsSecret(name) then return nil end
        set[Normalize(name)] = true
    end
    return set
end

local function IsCountable(unit)
    return UnitExists(unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit)
end

local container
local buttons = {}
local slotState = {} -- [slot] = { start, duration, key, sawAura, lastCount, lastTotal }

local function BuildFrames()
    local n = #DISPLAY_ORDER
    container = CreateFrame("Frame", "HeyListenTotems", UIParent)
    container:SetSize(n * ICON_SIZE + (n - 1) * SPACING, ICON_SIZE + 16)
    ns.MakeMovable(container, "totems", "Totems", { "CENTER", "CENTER", 0, -170 })

    for i, slot in ipairs(DISPLAY_ORDER) do
        local b = CreateFrame("Frame", nil, container)
        b:SetSize(ICON_SIZE, ICON_SIZE)
        b:SetPoint("TOPLEFT", (i - 1) * (ICON_SIZE + SPACING), 0)

        b.border = b:CreateTexture(nil, "BACKGROUND")
        b.border:SetPoint("TOPLEFT", -2, 2)
        b.border:SetPoint("BOTTOMRIGHT", 2, -2)
        b.border:SetColorTexture(0, 0, 0, 1)

        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        -- Cooldown sweep keeps ticking on its own even when the timer values are secret.
        b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        b.cd:SetAllPoints()
        b.cd:SetDrawEdge(false)
        b.cd:SetReverse(true)
        b.cd:SetHideCountdownNumbers(true)
        b.cd:SetScript("OnCooldownDone", function()
            -- Totem ran out (possibly mid-combat, where we can't ask the game).
            slotState[slot] = nil
            if not ns.unlocked then b:Hide() end
        end)

        local textLayer = CreateFrame("Frame", nil, b)
        textLayer:SetAllPoints()
        textLayer:SetFrameLevel(b.cd:GetFrameLevel() + 1)

        b.count = textLayer:CreateFontString(nil, "OVERLAY")
        b.count:SetFont(STANDARD_TEXT_FONT, 15, "THICKOUTLINE")
        b.count:SetPoint("CENTER", 0, 0)

        b.timer = textLayer:CreateFontString(nil, "OVERLAY")
        b.timer:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
        b.timer:SetPoint("TOP", b, "BOTTOM", 0, -2)
        b.timer:SetTextColor(1, 1, 1)

        buttons[slot] = b
    end
end

local function FormatTime(sec)
    sec = math.floor(sec)
    if sec >= 60 then return string.format("%d:%02d", math.floor(sec / 60), sec % 60) end
    return string.format("%ds", sec)
end

local function SetBorder(b, r, g, bl)
    b.border:SetColorTexture(r, g, bl, 1)
end

local function ShowCount(b, affected, total, stale)
    b.count:SetText(affected .. "/" .. total .. (stale and "?" or ""))
    if stale then
        b.count:SetTextColor(0.7, 0.7, 0.7); SetBorder(b, 0.3, 0.3, 0.3)
    elseif affected >= total then
        b.count:SetTextColor(0.2, 1, 0.2); SetBorder(b, 0, 0, 0)
    elseif affected > 0 then
        b.count:SetTextColor(1, 0.85, 0.1); SetBorder(b, 0.9, 0.7, 0)
    else
        b.count:SetTextColor(1, 0.2, 0.2); SetBorder(b, 0.9, 0, 0)
    end
end

local function ShowPlaceholderOrHide(slot, b)
    slotState[slot] = nil
    b.cd:Clear()
    if ns.unlocked then
        b.icon:SetTexture(PLACEHOLDER[slot])
        b.icon:SetDesaturated(true)
        b.count:SetText("")
        b.timer:SetText("")
        SetBorder(b, 0, 0, 0)
        b:Show()
    else
        b:Hide()
    end
end

-- Totem slots the game told us changed while their values were secret (mid-combat drops).
local pendingSecret = {}

-- Combat path for a totem dropped mid-combat: its values are secret, so hand them
-- straight to the widgets. The count stays "?" until combat ends.
local function ShowSecretTotem(slot, b, start, duration, icon)
    slotState[slot] = { secret = true }
    pcall(b.icon.SetTexture, b.icon, icon)
    pcall(b.cd.SetCooldown, b.cd, start, duration)
    b.icon:SetDesaturated(false)
    b.timer:SetText("")
    b.count:SetText("?")
    b.count:SetTextColor(0.7, 0.7, 0.7)
    SetBorder(b, 0.3, 0.3, 0.3)
    b:Show()
end

function M:Update()
    if not container then return end
    if not HeyListenDB.totems then container:Hide(); return end
    container:Show()

    -- Snapshot who is around and which buffs they carry (nil = unreadable right now).
    local buffs, total, unreadable = {}, 0, false
    for _, unit in ipairs(GROUP_UNITS) do
        if IsCountable(unit) then
            total = total + 1
            local set = ReadBuffs(unit)
            if set then buffs[unit] = set else unreadable = true end
        end
    end

    local now = GetTime()
    for slot, b in pairs(buttons) do
        local have, name, start, duration, icon = GetTotemInfo(slot)

        local st = slotState[slot]
        local secret = AnySecret(have, name, start, duration, icon)
        if not secret then pendingSecret[slot] = nil end
        if secret then
            if pendingSecret[slot] then
                pendingSecret[slot] = nil
                ShowSecretTotem(slot, b, start, duration, icon)
            elseif st and not st.secret then
                -- Totem we read before combat: keep its timer, show the last count we saw.
                local remaining = st.start + st.duration - now
                if remaining <= 0 then
                    ShowPlaceholderOrHide(slot, b)
                else
                    b.timer:SetText(FormatTime(remaining))
                    if st.lastCount then ShowCount(b, st.lastCount, st.lastTotal, true) end
                end
            end
            -- Otherwise nothing changed in this slot; leave it as it is.
        elseif have and name and name ~= "" and duration and duration > 0 then
            if not st or st.secret or st.start ~= start then
                st = { start = start, duration = duration, key = Normalize(name), sawAura = false }
                slotState[slot] = st
                b.cd:SetCooldown(start, duration)
            end

            b.icon:SetTexture(icon)
            b.icon:SetDesaturated(false)
            b.timer:SetText(FormatTime(math.max(0, start + duration - now)))

            local affected = 0
            for _, set in pairs(buffs) do
                if set[st.key] then affected = affected + 1 end
            end
            if affected > 0 then st.sawAura = true end

            local countable = not NO_AURA[st.key] and (st.sawAura or unreadable or now - start < NO_AURA_GRACE)
            if not countable then
                b.count:SetText("")
                SetBorder(b, 0, 0, 0)
            elseif unreadable then
                if st.lastCount then ShowCount(b, st.lastCount, st.lastTotal, true)
                else b.count:SetText("?"); b.count:SetTextColor(0.7, 0.7, 0.7) end
            else
                st.lastCount, st.lastTotal = affected, total
                ShowCount(b, affected, total, false)
            end
            b:Show()
        else
            ShowPlaceholderOrHide(slot, b)
        end
    end
end

function M:Init()
    local _, class = UnitClass("player")
    if class ~= "SHAMAN" then return end
    BuildFrames()

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_TOTEM_UPDATE")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED") -- values readable again: refresh immediately
    ev:SetScript("OnEvent", function(_, event, slot)
        if event == "PLAYER_TOTEM_UPDATE" and slot and buttons[slot] then
            pendingSecret[slot] = true -- only used if the slot's values turn out to be secret
        elseif event == "PLAYER_REGEN_ENABLED" then
            wipe(pendingSecret)
        end
        M:Update()
    end)

    -- Timers and group buff coverage refresh twice a second.
    local elapsed = 0
    ev:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.5 then
            elapsed = 0
            M:Update()
        end
    end)
end
