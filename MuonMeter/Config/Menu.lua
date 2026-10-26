local _, ns = ...
local F = ns[2]
local Core = F.GetModule("DamageMeter")
local M = F.RegisterModule("Menu")
local buttons = {}

local function OpenMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("Muon Meter")
		for _, option in ipairs(F.options) do
			local key = option.key
			local description = root:CreateCheckbox(F.L[key], function()
				return F.GetSetting(key)
			end, function()
				F.SetSetting(key, not F.GetSetting(key))
			end)
			local tooltip = F.L[key.."_Desc"]
			if option.reload then tooltip = tooltip.."\n\n"..F.L.ReloadOption end
			description:SetTitleAndTextTooltip(F.L[key], tooltip)
		end
		root:CreateDivider()
		local adjust = root:CreateButton(F.L.AdjustTitle, function() F.Adjust.Open() end)
		adjust:SetTitleAndTextTooltip(F.L.AdjustTitle, F.L.AdjustDescription)
		local reload = root:CreateButton(F.L.Reload, function() ReloadUI() end)
		-- Refresh 只重跑既有項目的 initializer；提示與常駐按鈕一同更新。
		reload:AddInitializer(function(frame, description)
			local text = F.L.Reload
			if F.HasPendingSettings() then text = text.." — "..F.L.ReloadRequired end
			frame.fontString:SetTextToFit(text)
			MenuUtil.SetElementText(description, text)
		end)
	end)
end

local function UpdateWindows(windows, canChangeLayout)
	local pending = false
	for _, window in ipairs(windows) do
		local state = buttons[window]
		if not state or not state.ready then
			-- 戰鬥／編輯期間不空轉，由 Core 的脫戰／退出編輯事件喚醒。
			if not canChangeLayout or InCombatLockdown() then return end
			local settings = window:GetSettingsDropdown()
			if C_RestrictedActions.CheckAllowProtectedFunctions(settings, true) then
				if not state then
					state = {button = CreateFrame("Button", nil, settings)}
					buttons[window] = state
				end
				local button = state.button
				if C_RestrictedActions.CheckAllowProtectedFunctions(button, true) then
					-- 子層只接齒輪右鍵；原生左鍵、中鍵與滑鼠高亮保持自己的輸入路徑。
					button:SetAllPoints(settings)
					button:EnableMouse(true)
					button:EnableMouseMotion(false)
					button:EnableMouseWheel(false)
					button:RegisterForClicks("RightButtonUp")
					button:SetPassThroughButtons("LeftButton", "MiddleButton")
					button:SetScript("OnClick", function(self, mouseButton)
						if mouseButton == "RightButton" then OpenMenu(self) end
					end)
					state.ready = true
					-- Skin 的首次輸入配置須等右鍵子層完成，再由共用 driver 補套。
					if F.GetModule("DamageMeterSkin").enabled then Core:RequestUpdate() end
				end
			end
			if not state or not state.ready then pending = true end
		end
	end
	return pending
end

function M:IsReady(window)
	local state = buttons[window]
	return state and state.ready
end

function M:OnEnable()
	Core:RegisterUpdate(UpdateWindows)
end
