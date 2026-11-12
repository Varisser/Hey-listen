-- Hey Listen! - small counter of quests that are ready to turn in
local ADDON, ns = ...

local M = {}
ns.modules.Quests = M

local frame

-- WoW Forever uses the modern quest log API (GetQuestLogTitle no longer exists).
local IsReady = C_QuestLog.ReadyForTurnIn or C_QuestLog.IsComplete

local function CountReadyQuests()
    local ready = 0
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and not info.isHidden and not info.isTask
            and not info.isBounty and info.questID and IsReady(info.questID) then
            ready = ready + 1
        end
    end
    return ready
end

function M:Update()
    if not frame then return end
    local n = HeyListenDB.quests and CountReadyQuests() or 0
    if ns.unlocked then
        frame.text:SetText("? quests ready to turn in")
        frame:Show()
    elseif n > 0 then
        frame.text:SetText(n .. (n == 1 and " quest" or " quests") .. " ready to turn in")
        frame:Show()
    else
        frame:Hide()
    end
end

function M:Init()
    frame = CreateFrame("Frame", "HeyListenQuests", UIParent)
    frame:SetSize(180, 16)
    frame:SetFrameStrata("LOW")
    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    frame.text:SetPoint("CENTER")
    frame.text:SetTextColor(1, 0.82, 0)
    ns.MakeMovable(frame, "quests", "Quest turn-ins", { "TOPRIGHT", "TOPRIGHT", -30, -200 })

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("QUEST_LOG_UPDATE")
    ev:RegisterEvent("QUEST_TURNED_IN")
    ev:SetScript("OnEvent", function() M:Update() end)
end
