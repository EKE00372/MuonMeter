local _, ns = ...
local F = ns[2]
local Core = F.GetModule("DamageMeter")
local M = F.RegisterModule("DamageMeterTooltip", "DamageMeterTooltip")

local tooltip, currentEntry, currentWindow
local currentRevision, currentContentRevision, currentStatsRevision, currentRestrictionRevision
local currentGUID, currentSessionType, currentSessionID
local currentInterrupts, currentDispels, currentAvoidable
local statsRevision = 0
local stats
local memberships = {}
local UpdateVisibility

local function HideTooltip()
	if currentEntry then
		tooltip:Hide()
		currentEntry, currentWindow = nil, nil
		currentGUID, currentSessionType, currentSessionID = nil, nil, nil
		currentInterrupts, currentDispels, currentAvoidable = nil, nil, nil
		Core:SetFrameUpdateActive(UpdateVisibility, false)
	end
end

local function CanDisplay()
	return M.enabled and not InCombatLockdown() and not UnitAffectingCombat("player")
		and not DamageMeter:IsEditing()
end

local function IsEligibleWindow(window)
	if not window:IsVisible() or not window:GetMinimizeContainer():IsVisible()
		or window:IsNonInteractive() then return false end
	local meterType = window:GetDamageMeterType()
	return meterType == Enum.DamageMeterType.DamageDone or meterType == Enum.DamageMeterType.Dps
		or meterType == Enum.DamageMeterType.HealingDone or meterType == Enum.DamageMeterType.Hps
end

local function MayContainCursor(window)
	local over = window:IsMouseOver()
	-- 幾何只用來排除明確在窗外的游標；受限錨點仍走原本的焦點查詢。
	return issecretvalue(over) or over
end

local function StatLine(stat, sessionType, sessionID, guid)
	local source
	if sessionType then
		source = C_DamageMeter.GetCombatSessionSourceFromType(sessionType, stat.type, guid)
	else
		source = C_DamageMeter.GetCombatSessionSourceFromID(sessionID, stat.type, guid)
	end
	if not canaccesstable(source) then return false end
	-- 成功旗標公開，文字保持 opaque；零值連同標籤與換行一起省略。
	return true, C_StringUtil.WrapString(C_StringUtil.TruncateWhenZero(source.totalAmount), stat.prefix)
end

local function ShowForWindow(window, focus)
	if not focus then return false end
	local box = window:GetScrollBox()
	local sourceBox = window:GetSourceWindow():GetScrollBox()
	if box:IsUpdateLocked() or box:IsAcquireLocked()
		or sourceBox:IsUpdateLocked() or sourceBox:IsAcquireLocked() then return false end

	local player = window:GetLocalPlayerEntry()
	local revision = Core.revisions[window]
	local entry, guid, name, classFilename
	if focus == player then
		if not player:IsVisible() then return false end
		-- 固定列沒有 ScrollBox accessor；其原生來源保證為本機玩家。
		entry, guid, name, classFilename = player, UnitGUID("player"), player.sourceName, player.classFilename
	else
		local membership = memberships[window]
		if membership and membership.focus == focus and membership.revision == revision then
			entry = membership.entry
		else
			for _, row in box:EnumerateFrames() do
				if row == focus then entry = row; break end
			end
			-- 只記公開框體的列表歸屬；命中後仍逐次重查資料、身分與權限。
			membership = membership or {}
			membership.focus, membership.revision, membership.entry = focus, revision, entry
			memberships[window] = membership
		end
		if not entry then return false end
		if not entry:IsVisible() then return false end
		local data = entry:GetElementData()
		if not canaccesstable(data) or not data then return false end
		guid, name, classFilename = data.sourceGUID, data.name, data.classFilename
		if data.isLocalPlayer then guid = UnitGUID("player") end
	end
	if not classFilename
		or not C_RestrictedActions.CheckAllowProtectedFunctions(entry, true) then return false end
	-- 原生列可能保留戰鬥中的 Secret GUID；只透過允許受限參數的 API 找回同一單位。
	if issecretvalue(guid) then
		local unit = UnitTokenFromGUID(guid)
		if issecretvalue(unit) or not unit then return false end
		guid = UnitGUID(unit)
	end
	-- token 與重取的 GUID 都可能仍受限，只有公開身分才能查其他統計。
	if issecretvalue(guid) or not guid then return false end
	local sessionType, sessionID = window:GetSessionType(), window:GetSessionID()
	if not sessionType and not sessionID then return false end
	-- 只有成功內容可重用；上面的資料、物件權限及 Secret 身分檢查不跳過。
	local contentRevision = Core.contentRevisions[window]
	local reuseContent = currentWindow == window and currentEntry == entry and currentContentRevision == contentRevision
		and currentStatsRevision == statsRevision and currentRestrictionRevision == Core.restrictionRevision
		and currentGUID == guid and currentSessionType == sessionType and currentSessionID == sessionID
	if reuseContent and currentRevision == revision then return true end

	local interrupts, dispels, avoidable = currentInterrupts, currentDispels, currentAvoidable
	if not reuseContent then
		local ok
		ok, interrupts = StatLine(stats[1], sessionType, sessionID, guid)
		if not ok then return false end
		ok, dispels = StatLine(stats[2], sessionType, sessionID, guid)
		if not ok then return false end
		ok, avoidable = StatLine(stats[3], sessionType, sessionID, guid)
		if not ok then return false end
	end

	if not tooltip then
		tooltip = CreateFrame("GameTooltip", "MuonMeterTooltip", UIParent, "SharedNoHeaderTooltipTemplate")
	end
	local color = RAID_CLASS_COLORS[classFilename]
	local format = color and ("|c"..color.colorStr.."%s|r%s%s%s") or "%s%s%s%s"
	-- 純捲動只重用三段 opaque 明細，仍沿原流程定位並填回文字。
	tooltip:SetOwner(entry, "ANCHOR_RIGHT")
	tooltip.TextLeft1:SetFormattedText(format, name, interrupts, dispels, avoidable)
	-- 只原樣轉送文字，尺寸交原生 tooltip；不讀文字長度或高度自行布局。
	tooltip:SetText(tooltip.TextLeft1:GetText(), 1, 1, 1, 1, false)
	tooltip:Show()
	local startVisibility = not currentEntry
	currentEntry, currentWindow = entry, window
	currentRevision, currentStatsRevision, currentRestrictionRevision = revision, statsRevision, Core.restrictionRevision
	currentContentRevision = contentRevision
	currentGUID, currentSessionType, currentSessionID = guid, sessionType, sessionID
	currentInterrupts, currentDispels, currentAvoidable = interrupts, dispels, avoidable
	if startVisibility then Core:SetFrameUpdateActive(UpdateVisibility, true) end
	return true
end

local function UpdateTick(windows)
	local polling = false
	if CanDisplay() then
		local focus, queried
		for _, window in ipairs(windows) do
			if IsEligibleWindow(window) then
				polling = true
				if MayContainCursor(window) then
					if not queried then focus, queried = GetMouseFoci()[1], true end
					if ShowForWindow(window, focus) then return true end
				end
			end
		end
	end
	HideTooltip()
	return polling
end

local function UpdateRows(window, _, isSource)
	if isSource then return end
	if not CanDisplay() then HideTooltip(); return end
	-- 同筆數刷新會在原表換人；沿完成通知重讀，不能以 table 身分當資料版本。
	if IsEligibleWindow(window) then
		-- 類型／場次切回可顯示範圍時，原生完成通知恢復游標偵測。
		Core:Wake()
		if MayContainCursor(window) and ShowForWindow(window, GetMouseFoci()[1]) then return end
	end
	if currentWindow == window then HideTooltip() end
end

UpdateVisibility = function()
	if currentEntry and (not CanDisplay() or not currentEntry:IsVisible()
		or not IsEligibleWindow(currentWindow) or not MayContainCursor(currentWindow)
		or GetMouseFoci()[1] ~= currentEntry) then
		HideTooltip()
	end
end

function M:OnSettingChanged()
	memberships = {}
	if not self.enabled then HideTooltip() end
end

function M:OnEnable()
	stats = {
		{type = Enum.DamageMeterType.Interrupts, prefix = "\n"..F.L.TooltipInterrupts},
		{type = Enum.DamageMeterType.Dispels, prefix = "\n"..F.L.TooltipDispels},
		{type = Enum.DamageMeterType.AvoidableDamageTaken, prefix = "\n"..F.L.TooltipAvoidableDamage},
	}
	F.RegisterEvent("PLAYER_REGEN_DISABLED", HideTooltip)
	local function InvalidateContent()
		if currentEntry then statsRevision = statsRevision + 1 end
	end
	F.RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED", function(_, meterType)
		if not currentEntry then return end
		-- 三種明細各自更新，不依賴目前傷害／治療頁是否收到 Refresh。
		for _, stat in ipairs(stats) do
			if stat.type == meterType then InvalidateContent(); return end
		end
	end)
	F.RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED", InvalidateContent)
	F.RegisterEvent("DAMAGE_METER_RESET", InvalidateContent)
	-- 停用時仍登記完成通知，讓登入後首次啟用也能處理原生列的更新。
	Core:RegisterUpdate(UpdateTick, UpdateVisibility, UpdateRows)
end
