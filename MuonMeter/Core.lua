local _, ns = ...
local F = ns[2]

local M = F.RegisterModule("DamageMeter")
local tickUpdates, frameUpdates, rowUpdates, windowUpdates = {}, {}, {}, {}
local refreshRows = {}
M.restrictionRevision = 0
M.revisions, M.geometryRevisions, M.playerRevisions, M.layoutRevisions = {}, {}, {}, {}
M.contentRevisions = {}
M.windows = {}
M.windowSet = {}

function M:RefreshRows(window)
	-- 熱還原固定列也會重設原生列樣式，須同輪重新套用仍啟用的格式與外觀。
	refreshRows[window]()
end

function M:RegisterUpdate(onTick, onFrame, onRows, onWindow)
	tickUpdates[#tickUpdates + 1] = onTick
	if onFrame then frameUpdates[#frameUpdates + 1] = onFrame end
	if onRows then rowUpdates[#rowUpdates + 1] = onRows end
	if onWindow then windowUpdates[#windowUpdates + 1] = onWindow end
end

local function NotifyWindow(window, created, dataOnly)
	for _, update in ipairs(windowUpdates) do update(window, created, dataOnly) end
end

function M:OnEnable()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_DamageMeter", function()
		-- 列內顯示在原生刷新完成後補套；共用 driver 負責外框、互動、動畫與重試。
		local driver = CreateFrame("Frame")
		local windows = M.windows
		local discover, tickRequested, wakeRequested = true, false, false
		local ticker, OnUpdate, RunTick
		local activeFrameUpdates, frameCount, frameRunning = {}, 0, false
		local function RefreshFrameScript()
			local needed = tickRequested or frameCount > 0
			if needed == frameRunning then return end
			frameRunning = needed
			driver:SetScript("OnUpdate", needed and OnUpdate or nil)
		end
		function M:SetFrameUpdateActive(callback, active)
			if (activeFrameUpdates[callback] ~= nil) == active then return end
			activeFrameUpdates[callback] = active and true or nil
			frameCount = frameCount + (active and 1 or -1)
			RefreshFrameScript()
		end
		local function Wake()
			-- 後執行的模組可能替已跑過的模組新增待辦，須保留至下一輪。
			wakeRequested = true
			if ticker or tickRequested then return end
			ticker = C_Timer.NewTicker(.1, RunTick)
		end
		M.Wake = Wake
		F.RegisterEvent("PLAYER_REGEN_ENABLED", Wake)
		F.RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", function()
			M.restrictionRevision = M.restrictionRevision + 1
			for _, window in ipairs(windows) do NotifyWindow(window) end
			Wake()
		end)
		EventRegistry:RegisterCallback("EditMode.Enter", Wake, M)
		EventRegistry:RegisterCallback("EditMode.Exit", Wake, M)
		local function WatchWindow(window)
			hooksecurefunc(window, "SetNonInteractive", Wake)
			window:HookScript("OnHide", function()
				NotifyWindow(window)
				Wake()
			end)
			local box = window:GetScrollBox()
			local source = window:GetSourceWindow()
			local sourceBox = source:GetScrollBox()
			M.layoutRevisions[window], M.layoutRevisions[source] = 0, 0
			local updating

			local function WatchRows(owner, scrollBox, isSource)
				local rebuilding, flushedRevision
				M.revisions[owner], M.geometryRevisions[owner] = 0, 0
				M.contentRevisions[owner] = 0
				if not isSource then M.playerRevisions[owner] = 0 end
				local function DataChanged()
					M.revisions[owner] = M.revisions[owner] + 1
					NotifyWindow(window, false, true)
				end
				local function RowsChanged()
					M.geometryRevisions[owner] = M.geometryRevisions[owner] + 1
					M.contentRevisions[owner] = M.contentRevisions[owner] + 1
					if not isSource then M.playerRevisions[owner] = M.playerRevisions[owner] + 1 end
					DataChanged()
				end
				local function FlushRows()
					local revision = M.revisions[owner]
					if rebuilding or flushedRevision == revision
						or not window:GetMinimizeContainer():IsVisible()
						or (isSource and not source:IsVisible()) then return end
					-- Update 早退仍會進 posthook；兩邊的更新／取框鎖解除後才寫 UI。
					if updating or box:IsUpdateLocked() or box:IsAcquireLocked()
						or sourceBox:IsUpdateLocked() or sourceBox:IsAcquireLocked() then
						NotifyWindow(window)
						Wake()
						return
					end
					updating = true
					local canChangeLayout = not DamageMeter:IsEditing()
					for _, update in ipairs(rowUpdates) do update(window, canChangeLayout, isSource) end
					updating = false
					flushedRevision = revision
				end
				-- 原生 Refresh 更換 provider 時先發此通知，合併其內部多次 Update。
				scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnDataProviderReassigned, function()
					rebuilding = true
				end, M)
				-- 一般列僅在原生重新初始化範圍後失效；純捲動只移動 ScrollTarget。
				scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnDataRangeChanged, function()
					M.geometryRevisions[owner] = M.geometryRevisions[owner] + 1
					M.contentRevisions[owner] = M.contentRevisions[owner] + 1
				end, M)
				scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnUpdate, function()
					-- OnScroll 仍可能重設固定玩家列，完成後須獨立重套。
					if not isSource then M.playerRevisions[owner] = M.playerRevisions[owner] + 1 end
					DataChanged()
				end, M)
				hooksecurefunc(scrollBox, "Update", FlushRows)
				hooksecurefunc(owner, "Refresh", function()
					rebuilding = false
					-- 內容版本不隨純捲動增加；Refresh（含鎖住的明細）仍須保留格式補試。
					M.contentRevisions[owner] = M.contentRevisions[owner] + 1
					-- 同筆數只刷新資料與固定玩家列；重建 provider 的幾何由 ScrollBox 通知。
					if not isSource then
						M.playerRevisions[owner] = M.playerRevisions[owner] + 1
					end
					DataChanged()
					FlushRows()
				end)
				return RowsChanged, FlushRows, DataChanged
			end
			local mainChanged, flushMain, mainDataChanged = WatchRows(window, box, false)
			local sourceChanged, flushSource = WatchRows(source, sourceBox, true)
			local function LayoutChanged()
				M.layoutRevisions[window] = M.layoutRevisions[window] + 1
				NotifyWindow(window)
			end
			local function SourceLayoutChanged()
				M.layoutRevisions[source] = M.layoutRevisions[source] + 1
				NotifyWindow(window)
			end
			local function Shown()
				LayoutChanged()
				SourceLayoutChanged()
				Wake()
				flushMain()
				flushSource()
			end
			window:HookScript("OnShow", Shown)
			refreshRows[window] = function()
				M.playerRevisions[window] = M.playerRevisions[window] + 1
				mainDataChanged()
				flushMain()
			end
			hooksecurefunc(window, "OnNumberDisplayTypeChanged", function()
				-- 原生只重寫數字；同步補回格式，不讓已完成的列布局失效。
				M.revisions[window] = M.revisions[window] + 1
				M.contentRevisions[window] = M.contentRevisions[window] + 1
				flushMain()
			end)
			local function StyleChanged()
				mainChanged()
				sourceChanged()
				flushMain()
				flushSource()
			end
			hooksecurefunc(window, "OnStyleChanged", StyleChanged)
			hooksecurefunc(window, "OnShowBarIconsChanged", StyleChanged)
			-- 折疊期間捲軸改 shown 不會發顯隱 script，展開時也須重套補寬。
			window:GetMinimizeContainer():HookScript("OnShow", Shown)
			source:HookScript("OnShow", function()
				SourceLayoutChanged()
				flushSource()
			end)
			-- 補寬與列更新分開，避免自己的錨點改動再次觸發列表更新後持續重排。
			window:GetScrollBar():HookScript("OnShow", LayoutChanged)
			window:GetScrollBar():HookScript("OnHide", LayoutChanged)
			source:GetScrollBar():HookScript("OnShow", SourceLayoutChanged)
			source:GetScrollBar():HookScript("OnHide", SourceLayoutChanged)
			NotifyWindow(window, true)
		end
		RunTick = function()
			tickRequested, wakeRequested = false, false
			if discover then
				discover = false
				for window in pairs(M.windowSet) do M.windowSet[window] = nil end
				local count = 0
				for index = 1, DamageMeter:GetMaxSessionWindowCount() do
					local window = _G["DamageMeterSessionWindow"..index]
					if window then
						if M.revisions[window] == nil then WatchWindow(window) end
						count = count + 1
						windows[count] = window
						M.windowSet[window] = true
					end
				end
				for index = count + 1, #windows do windows[index] = nil end
			end
			local keepRunning = false
			local canChangeLayout = not DamageMeter:IsEditing()
			for _, update in ipairs(tickUpdates) do
				-- 全關仍須完成選單初始化與拒寫後清理，再停止輪詢。
				if update(windows, canChangeLayout) then keepRunning = true end
			end
			if keepRunning or wakeRequested then Wake()
			elseif ticker then ticker:Cancel(); ticker = nil end
			RefreshFrameScript()
		end
		OnUpdate = function(_, elapsed)
			if tickRequested then
				-- 設定變更在下一幀處理；重排舊 ticker，避免同幀再到期重跑。
				if ticker then ticker:Cancel(); ticker = nil end
				RunTick()
			end
			for _, update in ipairs(frameUpdates) do
				if activeFrameUpdates[update] then update(elapsed) end
			end
		end
		hooksecurefunc(DamageMeter, "SetupSessionWindow", function()
			discover = true
			Wake()
		end)
		function M:RequestUpdate()
			tickRequested = true
			RefreshFrameScript()
		end
		Wake()
	end)
end
