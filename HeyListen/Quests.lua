-- Hey Listen! - small counter of quests that are ready to turn in
local ADDON, ns = ...

local M = {}
ns.modules.Quests = M

local frame

local function CountReadyQuests()
    local ready = 0
    if GetQuestLogTitle then
        -- Classic-style quest log API
        for i = 1, GetNumQuestLogEntries() do
            local title, _, _, isHeader, _, isComplete = GetQuestLogTitle(i)
            if title and not isHeader then
                -- isComplete: 1 = done, -1 = failed. Quests with no objectives
                -- ("speak to X", deliveries) can be handed in straight away.
                if isComplete == 1 or (isComplete == nil and GetNumQuestLeaderBoards(i) == 0) then
                    ready = ready + 1
                end
            end
        end
    elseif C_QuestLog and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID and C_QuestLog.IsComplete(info.questID) then
                ready = ready + 1
            end
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
    ev:SetScript("OnEvent", function() M:Update() end)
end
