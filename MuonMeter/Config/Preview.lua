local _, ns = ...
local F = ns[2]
local P = {}
F.AdjustPreview = P

local samples = {
	{class = "MAGE", icon = 135932, value = 1234567},
	{class = "WARRIOR", icon = 132355, value = 987654},
	{class = "MONK", icon = 608951, value = 765432},
	{class = "PRIEST", icon = 135940, value = 543210},
	{class = "HUNTER", icon = 132222, value = 432109},
}

local function Text(parent, font)
	local text = parent:CreateFontString(nil, "OVERLAY", font)
	text:SetWordWrap(false)
	return text
end

function P.Create(parent)
	local preview = CreateFrame("Frame", nil, parent)
	preview:Hide()
	preview:SetFrameStrata("DIALOG")
	preview:SetClampedToScreen(true)
	preview:EnableMouse(true)
	preview.Background = preview:CreateTexture(nil, "BACKGROUND")
	preview.Background:SetAllPoints()
	preview.header = CreateFrame("Frame", nil, preview)
	preview.header:SetPoint("TOPLEFT")
	preview.header:SetPoint("TOPRIGHT")
	preview.header.Background = preview.header:CreateTexture(nil, "BACKGROUND")
	preview.header.Background:SetAllPoints()
	preview.title = Text(preview.header, "GameFontNormalMed1")
	preview.title:SetPoint("LEFT", 5, 0)
	preview.title:SetText("00:30  "..DAMAGE_METER_TYPE_DAMAGE_DONE)
	preview.session = CreateFrame("Frame", nil, preview.header)
	preview.gear = CreateFrame("Frame", nil, preview.header)
	preview.gear:SetPoint("RIGHT")
	preview.session:SetPoint("RIGHT", preview.gear, "LEFT")
	preview.header.LeftBackground = preview.header:CreateTexture(nil, "BACKGROUND")
	preview.header.LeftBackground:SetPoint("TOPLEFT", preview.header, "TOPLEFT")
	preview.header.LeftBackground:SetPoint("BOTTOMRIGHT", preview.session, "BOTTOMLEFT")
	preview.title:SetPoint("RIGHT", preview.session, "LEFT", -2, 0)
	preview.session.Text = Text(preview.session, "GameFontNormalMed1")
	preview.session.Text:SetPoint("CENTER")
	preview.session.Text:SetText(DAMAGE_METER_CURRENT_SESSION_SHORT)
	preview.gear.Icon = preview.gear:CreateTexture(nil, "ARTWORK")
	preview.gear.Icon:SetTexture("Interface\\WorldMap\\GEAR_64GREY")
	preview.content = CreateFrame("Frame", nil, preview)
	preview.content:SetClipsChildren(true)
	preview.rows, preview.revision = {}, 0
	return preview
end

function P.Render(preview, values, showIcons, classColors)
	local S = Enum.EditModeDamageMeterSetting
	local skin, numbers = F.GetModule("DamageMeterSkin"), F.GetModule("DamageMeterNumbers")
	local width, height, barHeight = values[S.FrameWidth], values[S.FrameHeight], values[S.BarHeight]
	local spacing, style, alpha = values[S.Padding], values[S.Style], values[S.BackgroundTransparency] / 100
	local scale = values[S.TextSize] / 100
	local pixel = PixelUtil.GetPixelToUIUnitFactor() / preview:GetEffectiveScale()
	if preview.style ~= style or preview.showIcons ~= showIcons then
		preview.revision = preview.revision + 1
	end
	preview:SetSize(width, height)
	preview:SetAlpha(values[S.Transparency] / 100)
	preview.header:SetHeight(barHeight)
	preview.gear:SetSize(barHeight, barHeight)
	preview.session:SetSize(math.max(60, barHeight * 2), barHeight)
	preview.gear.Icon:SetPoint("TOPLEFT", 3 * pixel, -3 * pixel)
	preview.gear.Icon:SetPoint("BOTTOMRIGHT", -3 * pixel, 3 * pixel)
	preview.content:ClearAllPoints()
	preview.content:SetPoint("TOPLEFT", preview.header, "BOTTOMLEFT", 0, -2)
	preview.content:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", 0, 6)
	if skin.enabled then
		if not skin:StylePreviewPanel(preview, preview.Background, pixel, style, alpha)
			or not skin:StylePreviewHeader(preview.header, preview.header.LeftBackground, pixel, style)
			or not skin:StylePreviewHeader(preview.session, preview.session, pixel, style)
			or not skin:StylePreviewHeader(preview.gear, preview.gear, pixel, style) then return false end
		for _, text in ipairs({preview.title, preview.session.Text}) do
			local font, size = text:GetFont()
			text:SetFont(font, size, "OUTLINE")
			text:SetShadowOffset(0, 0)
		end
	else
		preview.Background:SetAtlas("damagemeters-background")
		preview.Background:SetAlpha(alpha)
		preview.header.Background:SetAtlas("ui-damagemeters-header-bar")
	end
	local count = math.max(0, math.floor((height - barHeight - 8 + spacing) / (barHeight + spacing)))
	local total = 0
	for index = 1, count do total = total + samples[(index - 1) % #samples + 1].value end
	for index = 1, count do
		local row = preview.rows[index]
		if not row then
			-- 此模板只有自有子框與 mixin，沒有 OnLoad／事件／真實場次綁定。
			row = CreateFrame("Button", nil, preview.content, "DamageMeterEntryTemplate")
			preview.rows[index] = row
		end
		local sample = samples[(index - 1) % #samples + 1]
		row.index, row.classFilename, row.deathRecapID = index, sample.class, 0
		row.sourceName = F.L.AdjustSample:format(index)
		row.value, row.valuePerSecond, row.sessionTotalValue = sample.value, sample.value / 30, total
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", preview.content, "TOPLEFT", 0, -(index - 1) * (barHeight + spacing))
		row:SetPoint("RIGHT", preview.content, "RIGHT")
		row:SetHeight(barHeight)
		-- Skin 擁有圖示的內縮尺寸；數字或透明度重畫不能先覆寫它的幾何快取。
		if not skin.enabled then row.Icon:SetSize(barHeight, barHeight) end
		row:GetIcon():SetTexture(sample.icon)
		if row:ShouldShowBarIcons() ~= showIcons then row:SetShowBarIcons(showIcons) end
		if row:GetStyle() ~= style then row:SetStyle(style) end
		row:SetBackgroundAlpha(alpha)
		row:SetTextScale(scale)
		row:GetName():SetFormattedText("%d. %s", index, row.sourceName)
		row:SetNumberDisplayType(values[S.Numbers])
		local color = classColors and RAID_CLASS_COLORS[sample.class] or DAMAGE_METER_STATUS_BAR_DEFAULT_COLOR
		row:GetStatusBar():SetStatusBarColor(color:GetRGB())
		row:GetStatusBar():SetMinMaxValues(0, samples[1].value)
		row:GetStatusBar():SetValue(sample.value)
		if skin.enabled and not skin:StylePreviewEntry(row, barHeight, pixel, preview.revision) then return false end
		if numbers.enabled then numbers:FormatPreviewEntry(row) end
		row:Show()
	end
	for index = count + 1, #preview.rows do preview.rows[index]:Hide() end
	preview.style, preview.showIcons = style, showIcons
	return true
end
