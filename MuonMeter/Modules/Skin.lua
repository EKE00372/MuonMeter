local _, ns = ...
local F, G = ns[2], ns[3]

local Core = F.GetModule("DamageMeter")
local M = F.RegisterModule("DamageMeterSkin", "DamageMeterSkin")
local surfaces, windows, rows, panelGlows = {}, {}, {}, {}
local layoutRevisions, rowLayouts = {}, {}
local BORDERED_SHADE = .3
local pendingWindows, processingWindows, settleIdle = {}, {}, false

local function QueueWindow(window)
	if pendingWindows[window] then return end
	pendingWindows[window], settleIdle = true, true
	-- 隱藏窗口只留待辦；原生 OnShow 會喚醒，避免隱藏統計刷新重啟 ticker。
	if window:IsVisible() then Core:Wake() end
end

local function InvalidateAll()
	for _, window in ipairs(Core.windows) do QueueWindow(window) end
end

local watchingRoot
local function WatchWindow(window, created, dataOnly)
	local state = windows[window]
	-- 同筆數資料已交完成通知同步補列；只有標題尺寸／風格改變才另排外框工作。
	if dataOnly and state and state.height == window:GetBarHeight() and state.style == window:GetStyle() then return end
	if created then
		local function Changed() QueueWindow(window) end
		window:HookScript("OnSizeChanged", Changed)
		window:GetSourceWindow():HookScript("OnSizeChanged", Changed)
		-- 只記待辦，不讀縮放參數；父層的有效縮放同樣須使像素布局失效。
		hooksecurefunc(window, "SetScale", Changed)
		hooksecurefunc(window, "SetIgnoreParentScale", Changed)
		if not watchingRoot then
			watchingRoot = true
			for _, owner in ipairs({DamageMeter, UIParent}) do
				hooksecurefunc(owner, "SetScale", InvalidateAll)
				hooksecurefunc(owner, "SetIgnoreParentScale", InvalidateAll)
			end
			F.RegisterEvent("UI_SCALE_CHANGED", InvalidateAll)
			F.RegisterEvent("DISPLAY_SIZE_CHANGED", InvalidateAll)
		end
	end
	QueueWindow(window)
end

-- glow.tga 是八段邊框材質；上下邊的 UV 轉向沿用原生 Backdrop 切片方式。
local glowPieces = {
	{ "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT", uv = {.0078125, .1171875, .0625, .9375} },
	{ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", uv = {.1328125, .2421875, .0625, .9375} },
	{ "BOTTOMLEFT", "TOPLEFT", "BOTTOMRIGHT", "TOPRIGHT", uv = {.2578125, .9375, .3671875, .9375, .2578125, .0625, .3671875, .0625} },
	{ "TOPLEFT", "BOTTOMLEFT", "TOPRIGHT", "BOTTOMRIGHT", uv = {.3828125, .9375, .4921875, .9375, .3828125, .0625, .4921875, .0625} },
	{ "BOTTOMRIGHT", "TOPLEFT", uv = {.5078125, .6171875, .0625, .9375} },
	{ "BOTTOMLEFT", "TOPRIGHT", uv = {.6328125, .7421875, .0625, .9375} },
	{ "TOPRIGHT", "BOTTOMLEFT", uv = {.7578125, .8671875, .0625, .9375} },
	{ "TOPLEFT", "BOTTOMRIGHT", uv = {.8828125, .9921875, .0625, .9375} },
}

local function CanChange(...)
	for index = 1, select("#", ...) do
		if not C_RestrictedActions.CheckAllowProtectedFunctions(select(index, ...), true) then return false end
	end
	return true
end

local function OutlineText(text)
	local font, height, flags = text:GetFont()
	if flags ~= "OUTLINE" then text:SetFont(font, height, "OUTLINE") end
	text:SetShadowOffset(0, 0)
end

local function SetSurface(owner, target, pixel, alpha, shade, shown, key)
	shade = shade or 0
	key = key or owner
	local surface = surfaces[key]
	if surface and surface.pixel == pixel and surface.shade == shade and surface.shown == shown then return surface end
	if not CanChange(owner, target) then return false end
	if not surface then
		surface = {}
		for index = 1, 5 do surface[index] = owner:CreateTexture(nil, index == 1 and "BACKGROUND" or "BORDER") end
		surfaces[key] = surface
	end
	if not CanChange(unpack(surface)) then return false end

	surface[1]:SetColorTexture(0, 0, 0, alpha)
	surface[1]:SetAllPoints(target)
	for index = 2, 5 do
		surface[index]:SetColorTexture(shade, shade, shade, shown == false and 0 or 1)
		surface[index]:ClearAllPoints()
	end
	surface[2]:SetPoint("TOPLEFT", surface[1], "TOPLEFT")
	surface[2]:SetPoint("TOPRIGHT", surface[1], "TOPRIGHT")
	surface[2]:SetHeight(pixel)
	surface[3]:SetPoint("BOTTOMLEFT", surface[1], "BOTTOMLEFT")
	surface[3]:SetPoint("BOTTOMRIGHT", surface[1], "BOTTOMRIGHT")
	surface[3]:SetHeight(pixel)
	surface[4]:SetPoint("TOPLEFT", surface[1], "TOPLEFT")
	surface[4]:SetPoint("BOTTOMLEFT", surface[1], "BOTTOMLEFT")
	surface[4]:SetWidth(pixel)
	surface[5]:SetPoint("TOPRIGHT", surface[1], "TOPRIGHT")
	surface[5]:SetPoint("BOTTOMRIGHT", surface[1], "BOTTOMRIGHT")
	surface[5]:SetWidth(pixel)
	surface.pixel, surface.shade, surface.shown = pixel, shade, shown
	return surface
end

local function ConfigurePanel(owner, background, pixel, border, shade)
	local surface = surfaces[owner]
	local layoutChanged = not surface or surface.panelPixel ~= pixel
	if not layoutChanged and surface.pixel == border and surface.shade == shade then return true end
	if not CanChange(owner, background) then return false end
	local glow = panelGlows[owner]
	if not glow then
		glow = {}
		for index = 1, #glowPieces do glow[index] = owner:CreateTexture(nil, "BACKGROUND", nil, -1) end
		panelGlows[owner] = glow
	end
	-- 光暈拒寫時先保留原背景，避免提早建立不透明底色。
	if layoutChanged and not CanChange(unpack(glow)) then return false end
	surface = SetSurface(owner, background, border, 1, shade)
	if not surface or not CanChange(surface[1]) then return false end

	local padding = 5 * pixel
	surface[1]:ClearAllPoints()
	surface[1]:SetPoint("TOPLEFT", background, "TOPLEFT", -padding, padding)
	surface[1]:SetPoint("BOTTOMRIGHT", background, "BOTTOMRIGHT", padding, -padding)
	if layoutChanged then
		for index, piece in ipairs(glowPieces) do
			local texture = glow[index]
			if not surface.panelPixel then
				texture:SetTexture(G.GlowTex)
				texture:SetTexCoord(unpack(piece.uv))
				texture:SetVertexColor(0, 0, 0, 1)
			end
			texture:ClearAllPoints()
			texture:SetPoint(piece[1], surface[1], piece[2])
			if piece[3] then texture:SetPoint(piece[3], surface[1], piece[4]) end
			if index <= 2 then
				texture:SetWidth(padding)
			elseif index <= 4 then
				texture:SetHeight(padding)
			else
				texture:SetSize(padding, padding)
			end
		end
		-- 原背景仍是原生內容的定位依據；只替換圖像，不改它的錨點或 alpha。
		background:SetTexture(nil)
	end
	surface.panelPixel = pixel
	return true
end

local function UpdateBackgroundAlpha(window)
	local owner = window:GetMinimizeContainer()
	local surface, glow = surfaces[owner], panelGlows[owner]
	if not CanChange(unpack(surface)) or not CanChange(unpack(glow)) then
		surface.alphaDirty = true
		QueueWindow(window)
		return
	end
	local alpha = window:GetBackgroundAlpha()
	if surface.alpha ~= alpha then
		-- 背景、外框與柔光共同跟隨原生設定，保留內容與父層淡出的獨立透明度。
		for _, texture in ipairs(surface) do texture:SetAlpha(alpha) end
		for _, texture in ipairs(glow) do texture:SetAlpha(alpha) end
		surface.alpha = alpha
	end
	surface.alphaDirty = nil
end

local function ConfigureScrollBar(bar)
	local track = bar.Track
	if not CanChange(bar, track, track.Thumb, bar.Back, bar.Forward) then return false end
	-- 保留原生 shown 管理與滾輪；hover 動畫只改父 alpha，無法顯出透明子層。
	track:SetAlpha(0)
	bar.Back:SetAlpha(0)
	bar.Forward:SetAlpha(0)
	bar:SetMouseClickEnabled(false)
	track:SetMouseClickEnabled(false)
	track.Thumb:SetMouseClickEnabled(false)
	bar.Back:SetMouseClickEnabled(false)
	bar.Forward:SetMouseClickEnabled(false)
	return true
end

local function ConfigureWindow(window, height, pixel)
	local state = windows[window]
	local style = window:GetStyle()
	local layoutChanged = (not state or state.height ~= height or state.pixel ~= pixel)
	if not layoutChanged and state.style == style then return true end
	if InCombatLockdown() then return end
	if (not state or not state.initialized) and not F.GetModule("Menu"):IsReady(window) then return end
	local header = window:GetHeader()
	local settings, session = window:GetSettingsDropdown(), window:GetSessionDropdown()
	local minimize, dropdown = window:GetMinimizeButton(), window:GetDamageMeterTypeDropdown()
	local timer, name = window:GetSessionTimerFontString(), window:GetDamageMeterTypeName()
	local sessionName, notActive = session.SessionName, window:GetNotActiveFontString()
	local source = window:GetSourceWindow()
	if not CanChange(window, header, settings, settings.Icon, session,
		session.Background, session.Arrow, session.Text, sessionName, notActive, minimize, dropdown, dropdown.Arrow,
		timer, name) then
		return
	end
	local bordered = (style == Enum.DamageMeterStyle.Bordered)
	local border, shade = bordered and 2 * pixel or pixel, bordered and BORDERED_SHADE or 0
	local container = window:GetMinimizeContainer()
	if not ConfigurePanel(container, window:GetBackground(), pixel, border, shade) then return end
	local panel = surfaces[container]
	if not panel.alphaHooked then
		hooksecurefunc(window, "OnBackgroundAlphaChanged", UpdateBackgroundAlpha)
		panel.alphaHooked = true
	end
	UpdateBackgroundAlpha(window)
	if not ConfigurePanel(source, source:GetBackground(), pixel, border, shade) then return end
	local surface = SetSurface(window, header, border, .55, shade)
	if not surface or not CanChange(surface[1]) then return end
	-- 按鈕與左側標題共用框線風格；只切風格時不重排按鈕。
	if not SetSurface(settings, settings, border, .55, shade) or not SetSurface(session, session, border, .55, shade) then return end
	if not state then
		state = {
			gear = settings:CreateTexture(nil, "ARTWORK", nil, 1), highlights = {},
		}
		windows[window] = state
	end
	local initializeInputs = not state.initialized
	if layoutChanged then
		if not CanChange(state.gear) then return end
		if not ConfigureScrollBar(window:GetScrollBar()) or not ConfigureScrollBar(source:GetScrollBar()) then return end
		if not state.initialized then
			for _, button in ipairs({settings, session}) do
				local highlight = state.highlights[button]
				if not highlight then
					highlight = button:CreateTexture(nil, "HIGHLIGHT")
					state.highlights[button] = highlight
				end
				if not CanChange(highlight) then return end
				highlight:SetColorTexture(1, 1, 1, .3)
				highlight:SetAllPoints(button)
			end
			OutlineText(timer)
			OutlineText(name)
			OutlineText(sessionName)
			OutlineText(notActive)
			-- 保留原生按鈕接收硬體點擊；場次右鍵選類型，齒輪中鍵折疊。
			minimize:Hide()
			settings:RegisterForMouse("LeftButtonDown", "LeftButtonUp")
			settings:SetPassThroughButtons("MiddleButton", "RightButton")
			session:RegisterForMouse("LeftButtonDown", "LeftButtonUp")
			session:SetPassThroughButtons("MiddleButton", "RightButton")
			dropdown:RegisterForMouse("RightButtonDown", "RightButtonUp")
			dropdown:SetPassThroughButtons("LeftButton", "MiddleButton")
			minimize:RegisterForClicks("MiddleButtonUp")
			minimize:SetPassThroughButtons("LeftButton", "RightButton")
			minimize:EnableMouseMotion(false)
			state.initialized = true
		end
		state.gear:SetTexture("Interface\\WorldMap\\GEAR_64GREY")
		state.gear:ClearAllPoints()
		state.gear:SetPoint("TOPLEFT", settings, "TOPLEFT", 3 * pixel, -3 * pixel)
		state.gear:SetPoint("BOTTOMRIGHT", settings, "BOTTOMRIGHT", -3 * pixel, 3 * pixel)

		header:SetTexture(nil)
		header:SetHeight(height)
		settings.Icon:SetAlpha(0)
		session.Background:SetAlpha(0)
		session.Arrow:SetAlpha(0)
		session.Text:SetAlpha(0)
		settings:ClearAllPoints()
		settings:SetSize(height, height)
		settings:SetPoint("RIGHT", header, "RIGHT", 0, 0)
		session:ClearAllPoints()
		session:SetSize(math.max(60, height * 2), height)
		session:SetPoint("RIGHT", settings, "LEFT", 0, 0)
		minimize:ClearAllPoints()
		minimize:SetAllPoints(settings)
		minimize:SetAlpha(0)
		timer:ClearAllPoints()
		timer:SetPoint("LEFT", header, "LEFT", 5 * pixel, 0)
		dropdown:ClearAllPoints()
		dropdown:SetAllPoints(session)
		dropdown.Arrow:Hide()
		name:ClearAllPoints()
		name:SetPoint("LEFT", timer, "RIGHT", 0, 0)
		name:SetPoint("RIGHT", session, "LEFT", -2 * pixel, 0)
	end
	-- 三種風格的標題皆保持全高，與右側按鈕、列表起點及拖曳範圍一致。
	surface[1]:ClearAllPoints()
	surface[1]:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
	surface[1]:SetPoint("BOTTOMRIGHT", session, "BOTTOMLEFT", 0, 0)
	surface[1]:SetHeight(height)
	-- 輸入及布局完成後才啟用中鍵覆蓋，讓原生齒輪高亮從首次顯示生效。
	if initializeInputs then minimize:Show() end
	state.height, state.pixel, state.style = height, pixel, style
	return true
end

local function ConfigureEntry(entry, height, pixel, revision)
	local state = rows[entry]
	if state and state.revision == revision and state.height == height and state.pixel == pixel then return state end
	local bar, icon = entry:GetStatusBar(), entry.Icon
	if not CanChange(entry, bar, icon) then return end
	if not state or not state.initialized then
		local fill, edge = entry:GetStatusBarTexture(), entry:GetBackgroundEdge()
		local name, value = entry:GetName(), entry:GetValue()
		if not CanChange(fill, edge, name, value) then return end
		if not state then
			state = {highlights = {}}
			for index = 1, 4 do state.highlights[index] = entry:CreateTexture(nil, "HIGHLIGHT") end
			rows[entry] = state
		end
		if not CanChange(unpack(state.highlights)) then return end
		OutlineText(name)
		OutlineText(value)
		-- 保留同一填充物件的原生 value／vertex color；不呼叫資料或色彩更新函式。
		fill:ClearTextureSlice()
		fill:SetTexture("Interface\\Buttons\\WHITE8X8")
		bar:DisableDrawLayer("BACKGROUND")
		edge:SetTexture(nil)
		state.initialized = true
	end
	local showIcon = entry:ShouldShowBarIcons()
	local style = entry:GetStyle()
	local bordered = (style == Enum.DamageMeterStyle.Bordered)
	local border = bordered and 2 * pixel or pixel
	local inset = 2 * pixel
	local top = style == Enum.DamageMeterStyle.Thin and height / 2 or 0
	local left = showIcon and height or inset
	if state.height ~= height or state.pixel ~= pixel or state.showIcon ~= showIcon or state.style ~= style then
		local surface = SetSurface(entry, entry, border, .55, bordered and BORDERED_SHADE or 0)
		-- 圖示底框也由列擁有，讓同列 HIGHLIGHT 能蓋過底框，不被 child 圖層遮住。
		local iconSurface = SetSurface(entry, icon, border, 0, bordered and BORDERED_SHADE or 0, showIcon, icon)
		if not surface or not iconSurface or not CanChange(surface[1], iconSurface[1])
			or not CanChange(unpack(state.highlights)) then return end
		-- 底框包含在整列占位內；Thin 只有右側底框半高，圖示仍占整列高度。
		surface[1]:ClearAllPoints()
		surface[1]:SetPoint("TOPLEFT", entry, "TOPLEFT", showIcon and height - border or 0, -top)
		surface[1]:SetPoint("BOTTOMRIGHT", entry, "BOTTOMRIGHT", 0, 0)
		icon:ClearAllPoints()
		icon:SetPoint("LEFT", entry, "LEFT", inset, 0)
		icon:SetSize(height - 2 * inset, height - 2 * inset)
		iconSurface[1]:ClearAllPoints()
		iconSurface[1]:SetPoint("TOPLEFT", icon, "TOPLEFT", -inset, inset)
		iconSurface[1]:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", inset, -inset)
		local highlights = state.highlights
		local shade = bordered and 1 or BORDERED_SHADE
		for _, texture in ipairs(highlights) do
			texture:SetColorTexture(shade, shade, shade, 1)
			texture:ClearAllPoints()
		end
		highlights[1]:SetPoint("TOPLEFT", entry, "TOPLEFT", 0, 0)
		highlights[1]:SetPoint("TOPRIGHT", entry, "TOPRIGHT", 0, 0)
		highlights[1]:SetHeight(inset)
		highlights[2]:SetPoint("BOTTOMLEFT", entry, "BOTTOMLEFT", 0, 0)
		highlights[2]:SetPoint("BOTTOMRIGHT", entry, "BOTTOMRIGHT", 0, 0)
		highlights[2]:SetHeight(inset)
		highlights[3]:SetPoint("TOPLEFT", entry, "TOPLEFT", 0, -inset)
		highlights[3]:SetPoint("BOTTOMLEFT", entry, "BOTTOMLEFT", 0, inset)
		highlights[3]:SetWidth(inset)
		highlights[4]:SetPoint("TOPRIGHT", entry, "TOPRIGHT", 0, -inset)
		highlights[4]:SetPoint("BOTTOMRIGHT", entry, "BOTTOMRIGHT", 0, inset)
		highlights[4]:SetWidth(inset)
	end

	-- 原生重取或 style 更新由 Core 標記；全部配置成功後才完成這一版。
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", entry, "TOPLEFT", left, -top - inset)
	bar:SetPoint("BOTTOMRIGHT", entry, "BOTTOMRIGHT", -inset, inset)
	if style == Enum.DamageMeterStyle.Thin then
		local name, value = entry:GetName(), entry:GetValue()
		if not CanChange(name, value) then return end
		name:ClearAllPoints()
		value:ClearAllPoints()
		-- 不依文字尺寸決定條高，兩個字串固定在整列的垂直中心。
		name:SetPoint("LEFT", entry, "LEFT", left + 2, 0)
		name:SetPoint("RIGHT", value, "LEFT", -25, 0)
		value:SetPoint("RIGHT", entry, "RIGHT", -border - 3, 0)
	end
	state.height, state.pixel, state.showIcon, state.style, state.revision = height, pixel, showIcon, style, revision
	return state
end

-- 調整面板只把自有預覽物件交給既有繪製器，不登記原生窗口或刷新統計。
function M:StylePreviewEntry(entry, height, pixel, revision)
	return ConfigureEntry(entry, height, pixel, revision) ~= nil
end

function M:StylePreviewPanel(owner, background, pixel, style, alpha)
	local bordered = style == Enum.DamageMeterStyle.Bordered
	if not ConfigurePanel(owner, background, pixel, bordered and 2 * pixel or pixel,
		bordered and BORDERED_SHADE or 0) then return false end
	if not CanChange(unpack(surfaces[owner])) or not CanChange(unpack(panelGlows[owner])) then return false end
	for _, texture in ipairs(surfaces[owner]) do texture:SetAlpha(alpha) end
	for _, texture in ipairs(panelGlows[owner]) do texture:SetAlpha(alpha) end
	return true
end

function M:StylePreviewHeader(owner, target, pixel, style)
	local bordered = style == Enum.DamageMeterStyle.Bordered
	return SetSurface(owner, target, bordered and 2 * pixel or pixel, .55,
		bordered and BORDERED_SHADE or 0) ~= false
end

local function UpdateRows(window, height, pixel, isSource)
	local owner = isSource and window:GetSourceWindow() or window
	if isSource then
		if not owner:IsVisible() then return true end
		height = owner:GetBarHeight()
	end
	local revision = Core.geometryRevisions[owner]
	local state = rowLayouts[owner]
	local complete = true
	if not state or state.revision ~= revision or state.height ~= height or state.pixel ~= pixel then
		for _, entry in owner:GetScrollBox():EnumerateFrames() do
			if not ConfigureEntry(entry, height, pixel, revision) then complete = false end
		end
		-- 一般列獨立完成；固定列拒寫時不必再次走訪已完成的列表。
		if complete then
			if not state then state = {}; rowLayouts[owner] = state end
			state.revision, state.height, state.pixel = revision, height, pixel
		end
	end
	if not isSource then
		local player = window:GetLocalPlayerEntry()
		-- Refresh 末段及固定列熱還原會重做 SetupEntry；純數字設定不使此版本失效。
		if player:IsShown() and not ConfigureEntry(player, height, pixel, Core.playerRevisions[owner]) then complete = false end
	end
	return complete
end

local function OnRowsChanged(window, canChangeLayout, isSource)
	if not canChangeLayout then QueueWindow(window); return end
	if not window:GetMinimizeContainer():IsVisible() then return end
	-- 同輪只補列內顯示，外框與 ScrollBox 尺寸仍由 driver 處理。
	local pixel = PixelUtil.GetPixelToUIUnitFactor() / window:GetEffectiveScale()
	if not UpdateRows(window, window:GetBarHeight(), pixel, isSource) then QueueWindow(window) end
end

local function ApplyWindow(window, pixelFactor)
	local source = window:GetSourceWindow()
	local box, sourceBox = window:GetScrollBox(), source:GetScrollBox()
	if box:IsUpdateLocked() or box:IsAcquireLocked()
		or sourceBox:IsUpdateLocked() or sourceBox:IsAcquireLocked() then return end
	local height = window:GetBarHeight()
	local pixel = pixelFactor / window:GetEffectiveScale()
	local complete = ConfigureWindow(window, height, pixel)
	local container = window:GetMinimizeContainer()
	local panel = surfaces[container]
	if panel and panel.alphaDirty then UpdateBackgroundAlpha(window) end
	if panel and panel.alphaDirty then complete = false end
	if container:IsVisible() then
		local layoutRevision = Core.layoutRevisions[window]
		-- 補寬只追原生捲軸顯隱；自己的布局回呼仍交下一批待辦合併。
		if layoutRevisions[window] ~= layoutRevision then
			local header = window:GetHeader()
			if CanChange(box, header, container) then
				box:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
				box:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 6)
				layoutRevisions[window] = layoutRevision
			else
				complete = false
			end
		end
		if source:IsVisible() then
			local sourceRevision = Core.layoutRevisions[source]
			if layoutRevisions[source] ~= sourceRevision then
				if CanChange(sourceBox, source) then
					-- 明細保留原內縮，只收回已隱藏捲軸的 20 UI 單位。
					sourceBox:SetPoint("BOTTOMRIGHT", source, "BOTTOMRIGHT", -22, 17)
					layoutRevisions[source] = sourceRevision
				else
					complete = false
				end
			end
		end
		local mainReady = UpdateRows(window, height, pixel, false)
		local sourceReady = UpdateRows(window, height, pixel, true)
		complete = complete and mainReady and sourceReady
	end
	return complete
end

local function UpdateTick(_, canChangeLayout)
	-- 編輯期間保留待辦，由 Core 的 EditMode.Exit 通知喚醒，不持續空轉。
	if not canChangeLayout then return false end
	if not next(pendingWindows) then
		-- 留一輪空閒過渡，連續原生更新沿用同一 ticker，安靜後才休眠。
		local settling = settleIdle
		settleIdle = false
		return settling
	end
	local pixelFactor, visibleWork
	-- 雙緩衝保留配置途中產生的通知，不能把新版本當成這一批已完成。
	pendingWindows, processingWindows = processingWindows, pendingWindows
	for window in pairs(processingWindows) do
		processingWindows[window] = nil
		if Core.windowSet[window] and window:IsVisible() then
			visibleWork = true
			pixelFactor = pixelFactor or PixelUtil.GetPixelToUIUnitFactor()
			if not ApplyWindow(window, pixelFactor) then pendingWindows[window] = true end
		end
	end
	if not visibleWork then settleIdle = false end
	return next(pendingWindows) ~= nil or settleIdle
end

function M:OnEnable()
	Core:RegisterUpdate(UpdateTick, nil, OnRowsChanged, WatchWindow)
end
