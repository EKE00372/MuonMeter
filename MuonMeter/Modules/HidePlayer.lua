local _, ns = ...
local F = ns[2]
local Core = F.GetModule("DamageMeter")

local M = F.RegisterModule("DamageMeterHidePlayer", "DamageMeterHidePlayer")
local states = {}

local function HidePlayerEntry(window)
	local entry = window:GetLocalPlayerEntry()
	local state = states[window]
	state.pendingHide = not C_RestrictedActions.CheckAllowProtectedFunctions(entry, true)
	if not state.pendingHide then
		entry:Hide()
		state.hidden = true
	elseif window:IsVisible() then
		Core:Wake()
	end
end

local function UpdateWindows(windows)
	local pending = false
	for _, window in ipairs(windows) do
		local state = states[window]
		if not state then
			state = {}
			states[window] = state
			-- 原生完成 Show 後才隱藏獨立固定列，不介入 ScrollBox 的正常排名列。
			hooksecurefunc(window, "ShowLocalPlayerEntry", function(owner)
				if M.enabled then
					HidePlayerEntry(owner)
				else
					state.hidden, state.pendingRestore = nil, nil
				end
			end)
			state.pendingHide = M.enabled
		end
		if M.enabled and state.pendingHide then
			HidePlayerEntry(window)
			pending = pending or (state.pendingHide and window:IsVisible())
		-- 戰鬥中保留待還原狀態，由 Core 的脫戰事件喚醒。
		elseif not M.enabled and state.pendingRestore and not InCombatLockdown() then
			local entry = window:GetLocalPlayerEntry()
			local box = window:GetScrollBox()
			local sourceBox = window:GetSourceWindow():GetScrollBox()
			-- 只在可配置時請原生重判捲動條件；不直接 Show 或讀取排名／資料欄位。
			if not DamageMeter:IsEditing()
				and not box:IsUpdateLocked() and not box:IsAcquireLocked()
				and not sourceBox:IsUpdateLocked() and not sourceBox:IsAcquireLocked()
				and C_RestrictedActions.CheckAllowProtectedFunctions(window, true)
				and C_RestrictedActions.CheckAllowProtectedFunctions(box, true)
				and C_RestrictedActions.CheckAllowProtectedFunctions(entry, true) then
				securecallfunction(window.EnsureLocalPlayerPresent, window)
				state.hidden, state.pendingRestore = nil, nil
				Core:RefreshRows(window)
			else
				pending = true
			end
		end
	end
	return pending
end

function M:OnSettingChanged()
	for _, state in pairs(states) do
		state.pendingHide = self.enabled
		state.pendingRestore = not self.enabled and state.hidden or nil
	end
	UpdateWindows(Core.windows)
end

function M:OnEnable()
	Core:RegisterUpdate(UpdateWindows)
end
