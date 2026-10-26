local _, ns = ...
local F = ns[2]

local Core = F.GetModule("DamageMeter")
local M = F.RegisterModule("DamageMeterMove", "DamageMeterMove")
local window, handle, handleShown, handleReady
local activeDrag, pendingDrag, pendingSave

local function CanUseProtectedObjects(...)
	for index = 1, select("#", ...) do
		if not C_RestrictedActions.CheckAllowProtectedFunctions(select(index, ...), true) then
			return false
		end
	end
	return true
end

local function IsCombatRestricted()
	return C_RestrictedActions.GetAddOnRestrictionState(Enum.AddOnRestrictionType.Combat)
		~= Enum.AddOnRestrictionState.Inactive
end

local function IsEditing()
	return EditModeManagerFrame:IsEditModeActive() or DamageMeter:IsEditing()
end

local function CanInteract()
	return M.enabled and window:IsVisible()
		and not window:IsLocked() and not window:IsNonInteractive()
		and not InCombatLockdown() and not IsEditing()
end

local function SavePosition(target)
	local manager = EditModeManagerFrame
	-- 位置由原生 Lua 讀取並寫回布局；不傳入插件建立的座標或資料表。
	securecallfunction(manager.OnSystemPositionChange, manager, target)
	securecallfunction(manager.SaveLayoutChanges, manager)
end

local function TryPendingSave()
	if not pendingSave then return end
	if not CanInteract() then pendingSave = nil; return end
	if IsCombatRestricted() or not CanUseProtectedObjects(pendingSave) then return end
	local target = pendingSave
	-- 原生 helper 沒有成功回值；消耗一次呼叫要求，不把返回 nil 當作保存成功。
	pendingSave = nil
	SavePosition(target)
end

local function FinishDrag(dragInfo, savePosition)
	local target = dragInfo.target
	target:StopMovingOrSizing()
	-- SetUserPlaced 要求仍為 movable／resizable，先清除此旗標再還原移動能力。
	target:SetUserPlaced(false)
	target:SetMovable(dragInfo.wasMovable)
	if savePosition then pendingSave = target end
end

local function StopDragging(savePosition)
	local dragInfo = activeDrag
	if not dragInfo then return end
	activeDrag = nil
	if not CanUseProtectedObjects(dragInfo.target) then
		pendingDrag = dragInfo
		return
	end
	FinishDrag(dragInfo, savePosition and CanInteract())
	TryPendingSave()
end

local function StartDragging()
	if activeDrag or pendingDrag or pendingSave or not IsAltKeyDown()
		or not CanInteract() or IsCombatRestricted()
		or not CanUseProtectedObjects(DamageMeter) then return end
	activeDrag = {target = DamageMeter, wasMovable = DamageMeter:IsMovable()}
	securecallfunction(EditModeSystemMixin.ClearFrameSnap, DamageMeter)
	DamageMeter:SetMovable(true)
	DamageMeter:StartMoving()
end

local function SetHandleShown(shown)
	if handle and handleShown ~= shown and CanUseProtectedObjects(handle) then
		handle:SetShown(shown)
		handleShown = shown
	end
end

local function UpdateHandleVisibility()
	if not handleReady then return end
	SetHandleShown(CanInteract() and not IsCombatRestricted() and not pendingDrag
		and (IsAltKeyDown() or activeDrag ~= nil))
end

local function OnDragStop()
	StopDragging(true)
	UpdateHandleVisibility()
end

local function CreateHandle()
	local header, session = window:GetHeader(), window:GetSessionDropdown()
	if not CanUseProtectedObjects(window, header, session) then return false end
	if not handle then handle = CreateFrame("Button", nil, window) end
	if not CanUseProtectedObjects(handle) then return false end
	-- 只覆蓋左側標題；右界止於場次按鈕左側，保留場次及齒輪三鍵。
	handle:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
	handle:SetPoint("BOTTOMRIGHT", session, "BOTTOMLEFT", 0, 0)
	handle:RegisterForDrag("RightButton")
	handle:SetPassThroughButtons("LeftButton", "MiddleButton")
	handle:SetScript("OnDragStart", StartDragging)
	handle:SetScript("OnDragStop", OnDragStop)
	handle:SetScript("OnHide", function() StopDragging(false) end)
	handle:Hide()
	handleShown = false
	return true
end

local function UpdateTick(_, canChangeLayout)
	if not M.enabled and not activeDrag and not pendingDrag and not pendingSave and not handleShown then return end
	-- 原生主窗在 LOD 完成時已建立，之後沿用同一物件與手把。
	if not window then window = DamageMeter:GetPrimarySessionWindow() end
	if handleReady and not activeDrag and not pendingDrag and not pendingSave and not IsAltKeyDown() then
		SetHandleShown(false)
		return handleShown
	end
	-- 只在 Alt 互動期間或首次手把配置尚未完成時追蹤狀態；平常交 modifier 喚醒。
	local watchingInput = M.enabled and window:IsVisible() and (IsAltKeyDown() or not handleReady)
	if pendingDrag and not InCombatLockdown() and not IsEditing()
		and CanUseProtectedObjects(pendingDrag.target) then
		local dragInfo = pendingDrag
		pendingDrag = nil
		FinishDrag(dragInfo, false)
	end
	-- 保存會進入原生 callback，完成後才統一確認本輪互動條件。
	if canChangeLayout then TryPendingSave() end
	if not canChangeLayout or not CanInteract() then
		SetHandleShown(false)
		StopDragging(false)
		pendingSave = nil
		return pendingDrag or handleShown or watchingInput
	end
	if IsCombatRestricted() or pendingDrag or not CanUseProtectedObjects(DamageMeter) then
		SetHandleShown(false)
		StopDragging(false)
		return pendingDrag or handleShown or watchingInput
	end
	if not handleReady then handleReady = CreateHandle() end
	if handleReady then SetHandleShown(IsAltKeyDown() or activeDrag ~= nil) end
	return activeDrag or pendingDrag or pendingSave or handleShown or (M.enabled and IsAltKeyDown()) or not handleReady
end

function M:IsInteracting()
	return activeDrag ~= nil or pendingDrag ~= nil or pendingSave ~= nil
end

local function OnWindowChanged(owner)
	-- 主窗或父層隱藏就取消待保存；手把自身因限制隱藏仍可正常延後保存。
	if pendingSave and owner == window and not owner:IsVisible() then pendingSave = nil end
end

function M:OnSettingChanged()
	if not self.enabled then
		-- 關閉代表取消尚未提交的位置保存；停止／還原被拒時由共用 driver 收尾。
		pendingSave = nil
		StopDragging(false)
		SetHandleShown(false)
	end
end

function M:OnEnable()
	Core:RegisterUpdate(UpdateTick, nil, nil, OnWindowChanged)
	F.RegisterEvent("MODIFIER_STATE_CHANGED", function(_, key)
		if key ~= "LALT" and key ~= "RALT" then return end
		UpdateHandleVisibility()
		if M.enabled or activeDrag or pendingDrag or pendingSave or handleShown then Core:Wake() end
	end)
end
