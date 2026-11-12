-- Hey Listen! - shaman totem tracker: shows how many group members each totem is affecting
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
    ["disease cleansing"] = true, ["sentry"] = true, ["earth elemental"] = true,
    ["fire elemental"] = true,
}

local GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex

-- "Strength of Earth Totem IV" / "Grounding Totem Effect" / "Windfury Totem" -> base name
local function Normalize(name)
    name = name:lower()
    name = name:gsub("%s+[ivxl]+$", "")
    name = name:gsub("%s+effect$", "")
    name = name:gsub("%s+totem$", "")
    return name
end

local function CollectBuffs(unit, into)
    for i = 1, 40 do
        local name
        if GetAuraDataByIndex then
            local data = GetAuraDataByIndex(unit, i, "HELPFUL")
            name = data and data.name
        else
            name = UnitAura(unit, i, "HELPFUL")
        end
        if not name then return end
        into[Normalize(name)] = true
    end
end

local container
local buttons = {}
local slotState = {} -- [slot] = { start = dropTime, sawAura = bool }

local function BuildFrames()
    local n = #DISPLAY_ORDER
    container = CreateFrame("Frame", "HeyListenTotems", UIParent)
    container:SetSize(n * ICON_SIZE + (n - 1) * SPACING, ICON_SIZE + 16)
    ns.MakeMovable(container, "totems", "Totems", { "CENTER", "CENTER", 0, -170 })

    for i, slot in ipairs(DISPLAY_ORDER) do
        local b = CreateFrame("Frame", nil, container)
        b:SetSize(ICON_SIZE, ICON_SIZE)
        b:SetPoint("TOPLEFT", (i - 1) * (ICON_SIZE + SPACING), 0)

        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        b.border = b:CreateTexture(nil, "BACKGROUND")
        b.border:SetPoint("TOPLEFT", -2, 2)
        b.border:SetPoint("BOTTOMRIGHT", 2, -2)
        b.border:SetColorTexture(0, 0, 0, 1)

        b.count = b:CreateFontString(nil, "OVERLAY")
        b.count:SetFont(STANDARD_TEXT_FONT, 15, "THICKOUTLINE")
        b.count:SetPoint("CENTER", 0, 0)

        b.timer = b:CreateFontString(nil, "OVERLAY")
        b.timer:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
        b.timer:SetPoint("TOP", b, "BOTTOM", 0, -2)
        b.timer:SetTextColor(1, 1, 1)

        b.slot = slot
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

function M:Update()
    if not container then return end
    if not HeyListenDB.totems then container:Hide(); return end
    container:Show()

    -- Snapshot who is around and which buffs they carry.
    local buffs, total = {}, 0
    for _, unit in ipairs(GROUP_UNITS) do
        if UnitExists(unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then
            total = total + 1
            local set = {}
            CollectBuffs(unit, set)
            buffs[unit] = set
        end
    end

    local now = GetTime()
    for slot, b in pairs(buttons) do
        local have, name, start, duration, icon = GetTotemInfo(slot)
        if have and name and name ~= "" and duration and duration > 0 then
            local key = Normalize(name)
            local st = slotState[slot]
            if not st or st.start ~= start then
                st = { start = start, sawAura = false }
                slotState[slot] = st
            end

            local affected = 0
            for _, set in pairs(buffs) do
                if set[key] then affected = affected + 1 end
            end
            if affected > 0 then st.sawAura = true end

            b.icon:SetTexture(icon)
            b.icon:SetDesaturated(false)
            b.timer:SetText(FormatTime(math.max(0, start + duration - now)))

            local countable = not NO_AURA[key] and (st.sawAura or now - start < NO_AURA_GRACE)
            if countable then
                b.count:SetText(affected .. "/" .. total)
                if affected >= total then
                    b.count:SetTextColor(0.2, 1, 0.2); SetBorder(b, 0, 0, 0)
                elseif affected > 0 then
                    b.count:SetTextColor(1, 0.85, 0.1); SetBorder(b, 0.9, 0.7, 0)
                else
                    b.count:SetTextColor(1, 0.2, 0.2); SetBorder(b, 0.9, 0, 0)
                end
            else
                b.count:SetText("")
                SetBorder(b, 0, 0, 0)
            end
            b:Show()
        else
            slotState[slot] = nil
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
    end
end

function M:Init()
    local _, class = UnitClass("player")
    if class ~= "SHAMAN" then return end
    BuildFrames()

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_TOTEM_UPDATE")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:SetScript("OnEvent", function() M:Update() end)

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
