local _, ns = ...
local F = ns[2]
local Core = F.GetModule("DamageMeter")
local M = F.RegisterModule("DamageMeterNumbers", "DamageMeterNumbers")

local abbreviationOptions
local revisions, playerRevisions = {}, {}

local function UpdateEntry(entry)
	local classFilename, deathRecapID = entry.classFilename, entry.deathRecapID
	-- 未初始化列與編輯預覽不具完整來源資料；空 class 字串仍可顯示數值。
	if deathRecapID == nil then return end
	if classFilename ~= "" then
		-- 名字可能受限，只交原生轉換與文字 setter，不解析或寫回原生名稱快取。
		local name = Ambiguate(entry.sourceName, "short")
		if deathRecapID ~= 0 then
			entry:GetName():SetText(name)
		else
			entry:GetName():SetFormattedText("%d. %s", entry.index, name)
		end
	end
	if deathRecapID ~= 0 then return end
	local numberDisplayType = entry:GetNumberDisplayType()
	-- 完整模式的百分比保留原生處理，不從受限總量自行除算。
	if numberDisplayType == Enum.DamageMeterNumbers.Complete then return end

	local value, secondaryValue = entry.value, entry.valuePerSecond
	if entry:ShowsValuePerSecondAsPrimary() then
		value, secondaryValue = secondaryValue, value
	end
	local text = entry:GetValue()
	if numberDisplayType == Enum.DamageMeterNumbers.Compact and not entry.suppressValuePerSecond then
		text:SetFormattedText(DAMAGE_METER_ENTRY_FORMAT_COMPACT,
			AbbreviateNumbers(value, abbreviationOptions), AbbreviateNumbers(secondaryValue, abbreviationOptions))
	else
		text:SetText(AbbreviateNumbers(value, abbreviationOptions))
	end
end

function M:FormatPreviewEntry(entry)
	UpdateEntry(entry)
end

local function UpdateEnemyDamageNames(window, sourceWindow)
	if window:GetDamageMeterType() ~= Enum.DamageMeterType.EnemyDamageTaken then return end
	for _, entry in sourceWindow:GetScrollBox():EnumerateFrames() do
		-- 此模式的玩家樣式列固定顯示單位短名，不讀受限法術資料來重建可選名稱格式。
		local classFilename = entry.unitClassFilename
		if classFilename ~= "" then
			local name = Ambiguate(entry.unitName, "short")
			local classColor = RAID_CLASS_COLORS[classFilename]
			if classColor then name = classColor:WrapTextInColorCode(name) end
			entry:GetName():SetText(name)
		end
	end
end

local function UpdateWindow(window, _, isSource)
	local owner = window
	if isSource then
		if not window:GetMinimizeContainer():IsVisible() then return end
		owner = window:GetSourceWindow()
		if not owner:IsVisible() then return end
	end
	local revision = Core.contentRevisions[owner]
	local rowsChanged = (revisions[owner] ~= revision)
	local playerRevision = not isSource and Core.playerRevisions[window]
	if not rowsChanged and (isSource or playerRevisions[window] == playerRevision) then return end
	if not isSource and not window:GetMinimizeContainer():IsVisible() then return end
	local box, sourceBox = window:GetScrollBox(), window:GetSourceWindow():GetScrollBox()
	if box:IsUpdateLocked() or box:IsAcquireLocked()
		or sourceBox:IsUpdateLocked() or sourceBox:IsAcquireLocked() then return true end
	if isSource then
		UpdateEnemyDamageNames(window, owner)
	else
		-- 純捲動只可能重建固定玩家列；一般列等資料或回收版本變更才重新格式化。
		if rowsChanged then
			for _, entry in box:EnumerateFrames() do UpdateEntry(entry) end
		end
		local player = window:GetLocalPlayerEntry()
		if player:IsShown() then UpdateEntry(player) end
		playerRevisions[window] = playerRevision
	end
	revisions[owner] = revision
end

local function UpdateTick(windows)
	local pending = false
	for _, window in ipairs(windows) do
		local mainPending = UpdateWindow(window, nil, false)
		local sourcePending = UpdateWindow(window, nil, true)
		pending = pending or mainPending or sourcePending
	end
	return pending
end

function M:OnEnable()
	-- 與 Ruri 血量使用相同的 k/m/b 規則；公開設定只建立一次，數值交原生縮寫器。
	abbreviationOptions = {
		config = CreateAbbreviateConfig({
			{ breakpoint = 1e9, abbreviation = "b", significandDivisor = 1e5, fractionDivisor = 1e4, abbreviationIsGlobal = false },
			{ breakpoint = 1e6, abbreviation = "m", significandDivisor = 1e4, fractionDivisor = 1e2, abbreviationIsGlobal = false },
			{ breakpoint = 1e5, abbreviation = "k", significandDivisor = 1e3, fractionDivisor = 1,   abbreviationIsGlobal = false },
			{ breakpoint = 1e3, abbreviation = "k", significandDivisor = 1e2, fractionDivisor = 1e1, abbreviationIsGlobal = false },
		}),
	}
	Core:RegisterUpdate(UpdateTick, nil, UpdateWindow)
end
