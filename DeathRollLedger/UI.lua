-- Death Roll Ledger - on-screen toggle button and ledger window
local ADDON, ns = ...
local UI = {}
ns.modules.UI = UI

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local ROWS = 14
local ROW_HEIGHT = 20

local function SavePos(frame, key)
    local point, _, relPoint, x, y = frame:GetPoint()
    DeathRollLedgerDB[key] = { point, relPoint, x, y }
end

local function RestorePos(frame, key, default)
    frame:ClearAllPoints()
    local p = DeathRollLedgerDB[key] or default
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local BUTTON_DEFAULT = { "TOP", "TOP", 260, -20 }
local WINDOW_DEFAULT = { "CENTER", "CENTER", 0, 60 }

---------------------------------------------------------------------------
-- Toggle button (always on screen)
---------------------------------------------------------------------------
local btn = CreateFrame("Button", "DeathRollLedgerToggle", UIParent, "BackdropTemplate")
btn:SetSize(150, 40)
btn:SetFrameStrata("MEDIUM")
btn:SetBackdrop(BACKDROP)
btn:SetMovable(true)
btn:SetClampedToScreen(true)
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:RegisterForDrag("LeftButton")

btn.title = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
btn.title:SetPoint("TOP", 0, -7)
btn.net = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
btn.net:SetPoint("BOTTOM", 0, 7)

btn:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() then
        self.dragging = true
        self:StartMoving()
    end
end)
btn:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePos(self, "button")
    if self.dragging then
        self.justDragged = true -- swallow the click that ends the drag
        C_Timer.After(0.05, function() self.justDragged = nil end)
    end
    self.dragging = nil
end)
btn:SetScript("OnClick", function(self, mouse)
    if self.justDragged then return end
    if mouse == "RightButton" then
        UI:ToggleWindow()
    else
        ns.SetEnabled(not ns.IsEnabled())
    end
end)
btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Death Roll Ledger")
    GameTooltip:AddLine(ns.IsEnabled() and "|cff00ff00Tracking ON|r: gold gained or lost counts as winnings."
        or "|cffaaaaaaTracking OFF|r", 1, 1, 1, true)
    GameTooltip:AddDoubleLine("Total winnings", ns.ColorMoney(ns.GetTotal()))
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: turn tracking on/off", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: open history", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Shift-drag: move", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function RefreshButton()
    local on = ns.IsEnabled()
    btn.title:SetText("Death Roll: " .. (on and "|cff00ff00ON|r" or "|cffff4040OFF|r"))
    btn.net:SetText("Total: " .. ns.ColorMoney(ns.GetTotal()))
    if on then
        btn:SetBackdropColor(0, 0.25, 0, 0.85)
        btn:SetBackdropBorderColor(0.2, 1, 0.2, 1)
    else
        btn:SetBackdropColor(0, 0, 0, 0.75)
        btn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    end
end

---------------------------------------------------------------------------
-- Ledger window
---------------------------------------------------------------------------
local win = CreateFrame("Frame", "DeathRollLedgerFrame", UIParent, "BackdropTemplate")
win:SetSize(380, 120 + ROWS * ROW_HEIGHT)
win:SetFrameStrata("DIALOG")
win:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
})
win:SetMovable(true)
win:EnableMouse(true)
win:SetClampedToScreen(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePos(self, "window") end)
win:Hide()
tinsert(UISpecialFrames, "DeathRollLedgerFrame") -- Escape closes it

local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -4, -4)

win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
win.title:SetPoint("TOPLEFT", 18, -16)

win.summary = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
win.summary:SetPoint("TOPLEFT", 18, -40)
win.summary:SetJustifyH("LEFT")

win.back = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
win.back:SetSize(70, 22)
win.back:SetPoint("TOPRIGHT", -34, -14)
win.back:SetText("< Back")

-- Column headers, lined up with the row columns below
local header = CreateFrame("Frame", nil, win)
header:SetHeight(14)
header:SetPoint("TOPLEFT", 14, -62)
header:SetPoint("TOPRIGHT", -14, -62)
header.left = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
header.left:SetPoint("LEFT", 4, 0)
header.mid = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
header.right = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
header.right:SetPoint("RIGHT", -4, 0)
local function SetHeader(left, mid, midX, right)
    header.left:SetText(left)
    header.mid:SetText(mid)
    header.mid:SetPoint("LEFT", midX, 0)
    header.right:SetText(right)
end

-- Rows
local rows = {}
for i = 1, ROWS do
    local r = CreateFrame("Button", nil, win)
    r:SetHeight(ROW_HEIGHT)
    r:SetPoint("TOPLEFT", 14, -78 - (i - 1) * ROW_HEIGHT)
    r:SetPoint("TOPRIGHT", -14, -78 - (i - 1) * ROW_HEIGHT)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.12)
    r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.left:SetPoint("LEFT", 4, 0)
    r.left:SetJustifyH("LEFT")
    r.mid = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.mid:SetPoint("LEFT", 150, 0)
    r.mid:SetJustifyH("LEFT")
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT", -4, 0)
    r.right:SetJustifyH("RIGHT")
    rows[i] = r
end

win.page = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
win.page:SetPoint("BOTTOM", 0, 44)

win.track = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
win.track:SetSize(130, 22)
win.track:SetPoint("BOTTOMLEFT", 16, 16)
win.track:SetScript("OnClick", function() ns.SetEnabled(not ns.IsEnabled()) end)

win.reset = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
win.reset:SetSize(90, 22)
win.reset:SetPoint("BOTTOMRIGHT", -16, 16)
win.reset:SetText("Reset All")
win.reset:SetScript("OnClick", function() StaticPopup_Show("DEATHROLLLEDGER_RESET") end)

win.hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
win.hint:SetPoint("BOTTOM", 0, 60)

local view = { mode = "list", key = nil, offset = 0 }
local items = {}

local function KeyLabel(key)
    return key == ns.OTHER and "|cffaaaaaaOther (no player)|r" or key
end

local function LastTime(b)
    local e = b.history[#b.history]
    return e and e.t or 0
end

local function BuildList()
    wipe(items)
    for name, b in pairs(DeathRollLedgerDB.players) do
        items[#items + 1] = { key = name, b = b }
    end
    table.sort(items, function(a, c) return LastTime(a.b) > LastTime(c.b) end)
    local other = DeathRollLedgerDB.other
    if other and #other.history > 0 then
        items[#items + 1] = { key = ns.OTHER, b = other }
    end
end

local function BuildHistory(key)
    wipe(items)
    local b = ns.GetBucket(key)
    if not b then return end
    local running = 0
    for i, e in ipairs(b.history) do
        running = running + e.amt
        table.insert(items, 1, { index = i, e = e, balance = running }) -- newest first
    end
end

function UI:Refresh()
    RefreshButton()
    if not win:IsShown() then return end
    local db = DeathRollLedgerDB
    win.track:SetText(ns.IsEnabled() and "Tracking: |cff00ff00ON|r" or "Tracking: |cffff4040OFF|r")

    if view.mode == "detail" and not ns.GetBucket(view.key) then view.mode = "list" end

    if view.mode == "list" then
        BuildList()
        win.title:SetText("Death Roll Ledger")
        local otherNote = ""
        if db.other and db.other.net ~= 0 then
            otherNote = db.countOther and "  |cffaaaaaa(incl. Other)|r" or "  |cffaaaaaa(Other excluded)|r"
        end
        win.summary:SetText("Total winnings: " .. ns.ColorMoney(ns.GetTotal()) .. otherNote)
        SetHeader("Player", "Games W-L", 170, "Net")
        win.back:Hide()
        win.hint:SetText(#items == 0 and "No history yet. Turn tracking on and start rolling!"
            or "Click a player to see your history with them.")
    else
        local b = ns.GetBucket(view.key)
        BuildHistory(view.key)
        win.title:SetText(KeyLabel(view.key))
        local wl = view.key ~= ns.OTHER and ("    Games: |cff33ff33%dW|r - |cffff4040%dL|r"):format(b.wins, b.losses) or ""
        win.summary:SetText("Net: " .. ns.ColorMoney(b.net) .. wl)
        SetHeader("Date", "Type", 80, "Amount  /  Running")
        win.back:Show()
        win.hint:SetText("Left-click: move entry to another player   Right-click: delete")
    end

    local maxOffset = math.max(0, #items - ROWS)
    view.offset = math.min(view.offset, maxOffset)
    for i = 1, ROWS do
        local r = rows[i]
        local item = items[view.offset + i]
        r.item = item
        if not item then
            r:Hide()
        elseif view.mode == "list" then
            r.left:SetText(KeyLabel(item.key))
            r.mid:SetText(item.key ~= ns.OTHER and ("%d-%d"):format(item.b.wins, item.b.losses) or "")
            r.right:SetText(ns.ColorMoney(item.b.net))
            r:Show()
        else
            local e = item.e
            r.left:SetText(date("%m/%d %H:%M", e.t))
            local label = e.src
            if e.src == "Roll" then
                label = (e.won and "|cff33ff33" or "|cffff4040") .. (e.note or "Death roll") .. "|r"
            elseif e.note and e.note ~= "" then
                label = label .. " |cff888888(" .. e.note .. ")|r"
            end
            r.mid:SetText(label)
            r.mid:SetPoint("LEFT", 80, 0)
            if e.src == "Roll" then
                r.right:SetText("")
            else
                r.right:SetText(ns.ColorMoney(e.amt) .. "  /  " .. ns.ColorMoney(item.balance))
            end
            r:Show()
        end
        if view.mode == "list" then r.mid:SetPoint("LEFT", 170, 0) end
    end
    if #items > ROWS then
        win.page:SetText(("%d-%d of %d  (mouse wheel to scroll)"):format(
            view.offset + 1, math.min(view.offset + ROWS, #items), #items))
    else
        win.page:SetText("")
    end
end

win:EnableMouseWheel(true)
win:SetScript("OnMouseWheel", function(_, delta)
    view.offset = math.max(0, view.offset - delta * 3)
    UI:Refresh()
end)
win:SetScript("OnShow", function() UI:Refresh() end)

win.back:SetScript("OnClick", function()
    view.mode, view.key, view.offset = "list", nil, 0
    UI:Refresh()
end)

for _, r in ipairs(rows) do
    r:SetScript("OnClick", function(self, mouse)
        local item = self.item
        if not item then return end
        if view.mode == "list" then
            view.mode, view.key, view.offset = "detail", item.key, 0
            UI:Refresh()
        elseif mouse == "RightButton" then
            local d = StaticPopup_Show("DEATHROLLLEDGER_DELETE")
            if d then d.data = { key = view.key, index = item.index } end
        elseif item.e.src ~= "Roll" then
            local d = StaticPopup_Show("DEATHROLLLEDGER_MOVE")
            if d then d.data = { key = view.key, index = item.index } end
        end
    end)
end

function UI:ToggleWindow()
    win:SetShown(not win:IsShown())
end

function UI:ResetPositions()
    DeathRollLedgerDB.button, DeathRollLedgerDB.window = nil, nil
    RestorePos(btn, "button", BUTTON_DEFAULT)
    RestorePos(win, "window", WINDOW_DEFAULT)
end

function UI:Init()
    RestorePos(btn, "button", BUTTON_DEFAULT)
    RestorePos(win, "window", WINDOW_DEFAULT)
    btn:Show()
end

---------------------------------------------------------------------------
-- Popups
---------------------------------------------------------------------------
local function PopupEditBox(self) return self.editBox or self.EditBox end

StaticPopupDialogs.DEATHROLLLEDGER_MOVE = {
    text = "Move this entry to which player?\n(type |cffffff00other|r for no player)",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    OnAccept = function(self, data)
        local name = strtrim(PopupEditBox(self):GetText() or "")
        if name:lower() == "other" then name = ns.OTHER end
        if name ~= "" and data then ns.MoveEntry(data.key, data.index, name) end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs.DEATHROLLLEDGER_MOVE.OnAccept(parent, parent.data)
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs.DEATHROLLLEDGER_DELETE = {
    text = "Delete this history entry?",
    button1 = DELETE or "Delete",
    button2 = CANCEL or "Cancel",
    OnAccept = function(_, data)
        if data then ns.DeleteEntry(data.key, data.index) end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs.DEATHROLLLEDGER_RESET = {
    text = "Wipe ALL death roll history and totals for this character?",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function()
        wipe(DeathRollLedgerDB.players)
        DeathRollLedgerDB.other = nil
        view.mode, view.key, view.offset = "list", nil, 0
        ns.Print("History wiped.")
        ns.Changed()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
