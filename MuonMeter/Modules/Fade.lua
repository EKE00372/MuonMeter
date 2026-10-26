local _, ns = ...
local F = ns[2]
local Core = F.GetModule("DamageMeter")

local M = F.RegisterModule("DamageMeterFade", "DamageMeterFade")

local FADED_ALPHA = .3
local FADE_IN_SPEED, FADE_OUT_SPEED = 6, 1.5
local currentAlpha, targetAlpha = 1, 1
local visibleWindow

local function AdvanceFade(elapsed)
	-- 兩次狀態掃描之間也檢查可見性；只推進私有 alpha，不讀回原生透明度。
	if not visibleWindow:IsVisible() then
		Core:SetFrameUpdateActive(AdvanceFade, false)
		return
	end

	local nextAlpha
	if currentAlpha < targetAlpha then
		nextAlpha = math.min(targetAlpha, currentAlpha + FADE_IN_SPEED * elapsed)
	else
		nextAlpha = math.max(targetAlpha, currentAlpha - FADE_OUT_SPEED * elapsed)
	end
	if nextAlpha ~= currentAlpha then
		DamageMeter:SetAlpha(nextAlpha)
		currentAlpha = nextAlpha
	end
	if currentAlpha == targetAlpha then Core:SetFrameUpdateActive(AdvanceFade, false) end
end

local function UpdateTarget(windows, canChangeLayout)
	if not M.enabled then return end
	local canFade = canChangeLayout and not UnitAffectingCombat("player")
	local hovering = false
	visibleWindow = nil
	for index = 1, #windows do
		local window = windows[index]
		if window:IsVisible() then
			visibleWindow = window
			if canFade and not hovering then
				local sourceWindow = window:GetSourceWindow()
				hovering = window:IsMouseOver()
					or (sourceWindow:IsVisible() and sourceWindow:IsMouseOver())
			end
		end
	end
	targetAlpha = canFade and visibleWindow and not hovering and FADED_ALPHA or 1
	Core:SetFrameUpdateActive(AdvanceFade, visibleWindow ~= nil and currentAlpha ~= targetAlpha)
	-- 戰鬥／編輯模式只完成回到全亮的動畫；恢復由 Core 的狀態事件喚醒。
	return canFade and visibleWindow ~= nil
end

function M:OnSettingChanged()
	currentAlpha, targetAlpha, visibleWindow = 1, 1, nil
	Core:SetFrameUpdateActive(AdvanceFade, false)
	if not self.enabled then DamageMeter:SetAlpha(1) end
end

function M:OnEnable()
	Core:RegisterUpdate(UpdateTarget, AdvanceFade)
end
