-- Death Roll Ledger - money tracking
--
-- PLAYER_MONEY is the single source of truth for how much gold changed, so
-- nothing is counted twice. Trades and mail register an "expectation"
-- (partner + exact amount). When a money change matches one, it is booked to
-- that player. Changes that match nothing within a short grace period are
-- booked to "Other" (loot, vendor, repairs...).
local ADDON, ns = ...
local M = {}
ns.modules.Money = M

local GRACE = 1.5 -- seconds a money change waits for a trade/mail to explain it

local lastMoney
local expectations = {} -- { key, amount, alt, record, src, note, expires }
local pending = {}      -- { amount, t }

local function Now() return GetTime() end

function M:ResetBaseline()
    lastMoney = GetMoney()
    wipe(pending)
    wipe(expectations)
end

local function Book(e, delta)
    ns.Record(e.key, e.record or delta, e.src, e.note)
end

local function TakeExpectation(delta)
    local now = Now()
    for i = #expectations, 1, -1 do
        local e = expectations[i]
        if e.expires < now then
            table.remove(expectations, i)
        elseif e.amount == delta or (e.alt and e.alt == delta) then
            table.remove(expectations, i)
            return e
        end
    end
end

local function OtherSource(delta)
    if MerchantFrame and MerchantFrame:IsShown() then return "Vendor" end
    if delta > 0 then return "Gold gained" end
    return "Gold spent"
end

local function FlushPending()
    local now = Now()
    for i = #pending, 1, -1 do
        local p = pending[i]
        if now - p.t >= GRACE - 0.05 then
            table.remove(pending, i)
            local e = TakeExpectation(p.amount)
            if e then
                Book(e, p.amount)
            elseif ns.IsEnabled() then
                ns.Record(ns.OTHER, p.amount, p.src)
            end
        end
    end
end

-- Called by trade/mail code once it knows who the money is from/to.
function M:Expect(e)
    if not ns.IsEnabled() or not e.key or e.amount == 0 then return end
    -- The money may already have arrived and be waiting in `pending`.
    for i, p in ipairs(pending) do
        if p.amount == e.amount or (e.alt and p.amount == e.alt) then
            table.remove(pending, i)
            Book(e, p.amount)
            return
        end
    end
    e.expires = Now() + (e.ttl or 5)
    table.insert(expectations, e)
end

function M:OnMoney()
    local money = GetMoney()
    if not lastMoney then lastMoney = money return end
    local delta = money - lastMoney
    lastMoney = money
    if delta == 0 or not ns.IsEnabled() then return end

    local e = TakeExpectation(delta)
    if e then Book(e, delta) return end

    table.insert(pending, { amount = delta, t = Now(), src = OtherSource(delta) })
    C_Timer.After(GRACE, FlushPending)
end

---------------------------------------------------------------------------
-- Trades
---------------------------------------------------------------------------
local trade = {}

local function TradePartner()
    local name, realm = UnitName("NPC")
    local n = ns.NormalizeName(name, realm)
    if not n and TradeFrameRecipientNameText then
        n = ns.NormalizeName(TradeFrameRecipientNameText:GetText())
    end
    return n
end

local function SnapshotTrade()
    trade.partner = trade.partner or TradePartner()
    local p, t = GetPlayerTradeMoney(), GetTargetTradeMoney()
    if p and not ns.IsSecret(p) then trade.player = p end
    if t and not ns.IsSecret(t) then trade.target = t end
end

local function FinishTrade()
    if trade.done or not trade.partner then return end
    trade.done = true
    local net = (trade.target or 0) - (trade.player or 0)
    if net ~= 0 then
        M:Expect({ key = trade.partner, amount = net, src = "Trade" })
    end
end

---------------------------------------------------------------------------
-- Mail
---------------------------------------------------------------------------
local inboxCache = {}
local sendMoney = 0

local function CacheInbox()
    wipe(inboxCache)
    for i = 1, (GetInboxNumItems() or 0) do
        local _, _, sender, subject, money = GetInboxHeaderInfo(i)
        inboxCache[i] = { sender = sender, subject = subject, money = money or 0 }
    end
end

local function TakeMailMoney(index)
    local _, _, sender, subject, money = GetInboxHeaderInfo(index)
    local cached = inboxCache[index]
    if (not money or money == 0) and cached then
        sender, subject, money = cached.sender, cached.subject, cached.money
    end
    if not money or money <= 0 then return end
    if cached then cached.money = 0 end

    -- Auction house sales, refunds etc. aren't from a player.
    local invoice = GetInboxInvoiceInfo and GetInboxInvoiceInfo(index)
    local key = (not invoice) and ns.NormalizeName(sender) or ns.OTHER
    M:Expect({ key = key, amount = money, src = invoice and "Auction" or "Mail", note = subject, ttl = 10 })
end

local function OnSendMail(recipient, subject)
    local money = GetSendMailMoney and GetSendMailMoney() or 0
    if not money or money == 0 then money = sendMoney end
    local key = ns.NormalizeName(recipient)
    if not key or not money or money <= 0 then return end
    local postage = GetSendMailPrice and GetSendMailPrice() or 0
    -- Gold leaves as money + postage; only the gold sent counts against the player.
    M:Expect({ key = key, amount = -(money + postage), alt = -money, record = -money,
        src = "Mail", note = subject, ttl = 10 })
    sendMoney = 0
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_MONEY" then
        M:OnMoney()
    elseif event == "PLAYER_ENTERING_WORLD" then
        lastMoney = GetMoney()
    elseif event == "TRADE_SHOW" then
        trade = { player = 0, target = 0 }
        SnapshotTrade()
    elseif event == "TRADE_MONEY_CHANGED" or event == "TRADE_ACCEPT_UPDATE"
        or event == "TRADE_PLAYER_ITEM_CHANGED" or event == "TRADE_TARGET_ITEM_CHANGED" then
        SnapshotTrade()
    elseif event == "UI_INFO_MESSAGE" or event == "UI_ERROR_MESSAGE" then
        -- Modern clients send (messageType, message); older ones just (message).
        for i = 1, select("#", ...) do
            local m = select(i, ...)
            if type(m) == "string" and not ns.IsSecret(m) then
                if m == ERR_TRADE_COMPLETE then
                    FinishTrade()
                elseif m == ERR_TRADE_CANCELLED or m == ERR_TRADE_BAG_FULL
                    or m == ERR_TRADE_TARGET_BAG_FULL or m == ERR_TRADE_MAX_COUNT_EXCEEDED then
                    trade.done = true
                end
            end
        end
    elseif event == "TRADE_REQUEST_CANCEL" then
        trade.done = true
    elseif event == "TRADE_CLOSED" then
        -- Fallback in case the "Trade complete" message never arrives.
        -- A cancel message, if any, lands before this timer runs.
        C_Timer.After(0.3, FinishTrade)
    elseif event == "MAIL_INBOX_UPDATE" or event == "MAIL_SHOW" then
        CacheInbox()
    end
end)

function M:Init()
    for _, e in ipairs({ "PLAYER_MONEY", "PLAYER_ENTERING_WORLD", "TRADE_SHOW", "TRADE_CLOSED",
        "TRADE_MONEY_CHANGED", "TRADE_ACCEPT_UPDATE", "TRADE_PLAYER_ITEM_CHANGED",
        "TRADE_TARGET_ITEM_CHANGED", "TRADE_REQUEST_CANCEL", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE",
        "MAIL_SHOW", "MAIL_INBOX_UPDATE" }) do
        pcall(f.RegisterEvent, f, e) -- ignore any event this client doesn't have
    end
    if TakeInboxMoney then hooksecurefunc("TakeInboxMoney", TakeMailMoney) end
    if AutoLootMailItem then hooksecurefunc("AutoLootMailItem", TakeMailMoney) end
    if SetSendMailMoney then hooksecurefunc("SetSendMailMoney", function(m) sendMoney = tonumber(m) or 0 end) end
    if SendMail then hooksecurefunc("SendMail", OnSendMail) end
    lastMoney = GetMoney()
end
