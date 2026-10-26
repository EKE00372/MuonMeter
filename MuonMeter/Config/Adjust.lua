local _, ns = ...
local F = ns[2]
local A = {}
F.Adjust = A

local panel, draft, baseline, descriptions, keys
local committing, reloadRequired

local function IsAvailable()
	return not F.HasPendingSettings() and not InCombatLockdown() and not DamageMeter:IsEditing()
		and not EditModeManagerFrame:IsEditModeActive() and not EditModeManagerFrame.overrideLayoutInfo
		and not F.GetModule("DamageMeterMove"):IsInteracting()
		and C_RestrictedActions.GetAddOnRestrictionState(Enum.AddOnRestrictionType.Combat)
			== Enum.AddOnRestrictionState.Inactive
end

local function FindSystem(layout)
	for _, system in ipairs(layout.systems) do
		if system.system == Enum.EditModeSystem.DamageMeter and system.systemIndex == DamageMeter.systemIndex then return system end
	end
end

local function GetValues(system)
	local values = {}
	for _, setting in ipairs(system.settings) do values[setting.setting] = setting.value end
	return values
end

local function ReadLayouts()
	-- GetLayouts 只回傳自訂布局，activeLayout 卻包含前方預設布局的索引。
	-- 跟原生 UpdateLayoutInfo 一樣補上預設複本；不借用 manager 的可變資料表。
	local info = C_EditMode.GetLayouts()
	local layouts = EditModePresetLayoutManager:GetCopyOfPresetLayouts()
	for _, layout in ipairs(info.layouts) do layouts[#layouts + 1] = layout end
	info.layouts = layouts
	local active = layouts[info.activeLayout]
	local system = active and FindSystem(active)
	if not system then return end
	return info, active, system
end

local function Status(text)
	panel.status:SetText(text)
	panel:SetHeight(panel.statusTop + math.max(28, math.ceil(panel.status:GetStringHeight())) + 48)
end

local function Close()
	if committing then return end
	if reloadRequired then Status(F.L.AdjustSaveFailed); return end
	panel:Hide()
end

local function Render()
	local S = Enum.EditModeDamageMeterSetting
	local targetScale = DamageMeter:GetPrimarySessionWindow():GetEffectiveScale()
	if issecretvalue(targetScale) then return false end
	panel.preview:SetScale(targetScale / UIParent:GetEffectiveScale())
	local display = {}
	for _, key in ipairs(keys) do
		local info = descriptions[key]
		display[key] = info.options and draft[key] or info:ConvertValueForDisplay(draft[key])
	end
	local icons = baseline.values[S.ShowSpecIcon] == 1
	local colors = baseline.values[S.ShowClassColor] == 1
	return F.AdjustPreview.Render(panel.preview, display, icons, colors)
end

local function SetChoiceState(button, value)
	local selected = button.choiceValue == value
	button:SetButtonState(selected and "PUSHED" or "NORMAL", selected)
end

local function Changed(key, value)
	if not draft or committing or reloadRequired then return end
	draft[key] = value
	if panel.choices[key] then
		for _, button in ipairs(panel.choices[key]) do SetChoiceState(button, value) end
	end
	Status(F.L.AdjustHint)
	if not Render() then
		panel.preview:Hide()
		Status(F.L.AdjustUnavailable)
	else
		panel.preview:Show()
	end
end

local function SameLayout(info, active, values)
	if info.activeLayout ~= baseline.index or active.layoutName ~= baseline.name or active.layoutType ~= baseline.kind then return false end
	for _, key in ipairs(keys) do
		if values[key] ~= baseline.values[key] then return false end
	end
	return true
end

local function Save()
	if not IsAvailable() then Status(F.L.AdjustUnavailable); return end
	local info, active, system = ReadLayouts()
	if not info or not SameLayout(info, active, GetValues(system)) then Status(F.L.AdjustConflict); return end
	local addedIndex
	if active.layoutType == Enum.EditModeLayoutType.Preset then
		local name = panel.layoutName:GetText()
		if not C_EditMode.IsValidLayoutName(name) then Status(F.L.AdjustInvalidName); return end
		local accountCount, characterCount = 0, 0
		for _, layout in ipairs(info.layouts) do
			if layout.layoutName == name then Status(F.L.AdjustInvalidName); return end
			if layout.layoutType == Enum.EditModeLayoutType.Account then accountCount = accountCount + 1 end
			if layout.layoutType == Enum.EditModeLayoutType.Character then characterCount = characterCount + 1 end
		end
		local maxLayouts = Constants.EditModeConsts.EditModeMaxLayoutsPerType
		local kind = accountCount < maxLayouts and Enum.EditModeLayoutType.Account or Enum.EditModeLayoutType.Character
		if kind == Enum.EditModeLayoutType.Character and characterCount >= maxLayouts then Status(F.L.AdjustLayoutsFull); return end
		active = CopyTable(active)
		active.layoutName, active.layoutType, active.layoutIndex = name, kind, nil
		-- 原生排序是預設、帳號、角色；新增後交 OnLayoutAdded 處理選取。
		addedIndex = kind == Enum.EditModeLayoutType.Account
			and Enum.EditModePresetLayoutsMeta.NumValues + accountCount + 1 or #info.layouts + 1
		table.insert(info.layouts, addedIndex, active)
		system = FindSystem(active)
	end
	for _, setting in ipairs(system.settings) do
		if draft[setting.setting] ~= nil then setting.value = draft[setting.setting] end
	end
	-- 提交期間面板也可能消失；核對本次已提交的值，不依賴可被丟棄的面板草稿。
	local expectedIndex, submittedValues = addedIndex or info.activeLayout, draft
	-- 最後一刻才提交私有布局複本；不呼原生 MouseUp／逐項 setter／RefreshLayout。
	-- pcall 僅保留失敗後的重載出口，不提供去 taint 或成功保存保證。
	committing, reloadRequired = true, true
	local ok = pcall(C_EditMode.SaveLayouts, info)
	if ok and addedIndex then ok = pcall(C_EditMode.OnLayoutAdded, addedIndex, true, false) end
	committing = false
	local readOK, saved, savedLayout, savedSystem = pcall(ReadLayouts)
	local verified = ok and readOK and saved and saved.activeLayout == expectedIndex
		and savedLayout.layoutName == active.layoutName and savedLayout.layoutType == active.layoutType
	if verified then
		local values = GetValues(savedSystem)
		for _, key in ipairs(keys) do
			if values[key] ~= submittedValues[key] then verified = false; break end
		end
	end
	if verified and IsAvailable() then
		ReloadUI()
	else
		-- 可能已部分保存，禁止再次提交或假裝取消可還原；保留手動重載出口。
		panel.save:SetText(F.L.Reload)
		panel.cancel:Disable()
		for _, control in ipairs(panel.controls) do control:Disable() end
		panel.layoutName:Disable()
		panel.preview:Hide()
		Status(F.L.AdjustSaveFailed)
	end
end

local function SaveOrReload()
	if committing then return end
	if reloadRequired then
		if not InCombatLockdown() then ReloadUI() end
		return
	end
	Save()
end

local function Button(parent, text, width, onClick)
	local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
	button:SetSize(width, 24)
	button:SetBackdrop({edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
	button:SetBackdropBorderColor(.35, .35, .4, 1)
	local function Texture(r, g, b, alpha)
		local texture = button:CreateTexture(nil, "BACKGROUND")
		texture:SetPoint("TOPLEFT", 1, -1)
		texture:SetPoint("BOTTOMRIGHT", -1, 1)
		texture:SetColorTexture(r, g, b, alpha)
		return texture
	end
	button:SetNormalTexture(Texture(.12, .12, .14, 1))
	button:SetPushedTexture(Texture(.3, .3, .35, 1))
	button:SetHighlightTexture(Texture(1, 1, 1, .12), "ADD")
	button:SetDisabledTexture(Texture(.07, .07, .08, 1))
	local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("CENTER")
	button:SetFontString(label)
	button:SetNormalFontObject(GameFontNormal)
	button:SetHighlightFontObject(GameFontHighlight)
	button:SetDisabledFontObject(GameFontDisable)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

local function CreatePanel()
	panel = CreateFrame("Frame", "MuonMeterAdjustPanel", UIParent, "BackdropTemplate")
	panel:Hide()
	panel:SetFrameStrata("DIALOG")
	panel:SetClampedToScreen(true)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
	panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	panel:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
	panel:SetBackdropColor(.06, .06, .07, .96)
	panel:SetBackdropBorderColor(.35, .35, .4, 1)
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 18, -16)
	title:SetText("Muon Meter — "..F.L.AdjustTitle)
	local close = Button(panel, "×", 24, Close)
	close:SetPoint("TOPRIGHT", -8, -10)
	-- 原生詞條隨客戶端語系改變；用實際字寬決定最小寬度，不縮字或裁切選項。
	local measure = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	local function TextWidth(text)
		measure:SetText(text)
		return math.ceil(measure:GetStringWidth())
	end
	local choiceLabelWidth, choiceWidth, compactWidth, labelWidth = 76, 64, 154, 0
	for index, key in ipairs(keys) do
		local info = descriptions[key]
		local nameWidth = TextWidth(info.name)
		if info.options then
			choiceLabelWidth = math.max(choiceLabelWidth, nameWidth)
			for _, option in ipairs(info.options) do choiceWidth = math.max(choiceWidth, TextWidth(option.text) + 20) end
		elseif index >= 6 then
			local minText = info.formatter and info.formatter(info.minValue) or tostring(info.minValue)
			local maxText = info.formatter and info.formatter(info.maxValue) or tostring(info.maxValue)
			compactWidth = math.max(compactWidth, nameWidth + 12 + math.max(TextWidth(minText), TextWidth(maxText)))
		else
			labelWidth = math.max(labelWidth, nameWidth)
		end
	end
	local cancelWidth = math.max(100, TextWidth(CANCEL) + 20)
	local saveWidth = math.max(180, TextWidth(F.L.AdjustSave) + 20, TextWidth(F.L.Reload) + 20)
	local choiceLeft = 16 + choiceLabelWidth + 12
	local width = math.max(360, choiceLeft + choiceWidth * 3 + 12 + 16, compactWidth * 2 + 20 + 32,
		labelWidth + 32, title:GetStringWidth() + 64, TextWidth(F.L.AdjustNewLayout) + 12 + 160 + 32,
		saveWidth + cancelWidth + 16 + 32)
	measure:Hide()
	panel:SetWidth(width)
	local cellWidth = (width - 32 - 20) / 2
	choiceWidth = (width - choiceLeft - 16 - 12) / 3
	panel.controls, panel.choices = {}, {}
	for index, key in ipairs(keys) do
		local info = descriptions[key]
		local compact = index >= 6
		local row = compact and 6 + math.floor((index - 6) / 2) or index
		local left = 16 + (compact and (index - 6) % 2 or 0) * (cellWidth + 20)
		local top = info.options and -44 - (index - 1) * 32 or -110 - (row - 3) * 42
		local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("TOPLEFT", left, top)
		label:SetText(info.name)
		if info.options then
			local choices = {}
			panel.choices[key] = choices
			for optionIndex, option in ipairs(info.options) do
				local value = option.value
				local button = Button(panel, option.text, choiceWidth, function() Changed(key, value) end)
				button:SetPoint("TOPLEFT", choiceLeft + (optionIndex - 1) * (choiceWidth + 6), top + 5)
				button.key, button.choiceValue = key, value
				choices[#choices + 1] = button
				panel.controls[#panel.controls + 1] = button
			end
		else
			local slider = CreateFrame("Slider", nil, panel)
			slider:SetOrientation("HORIZONTAL")
			slider:SetSize(compact and cellWidth - 48 or width - 150, 16)
			slider:SetPoint("TOPLEFT", left + 24, top - 17)
			slider:SetMinMaxValues(info.minValue, info.maxValue)
			slider:SetValueStep(info.stepSize)
			slider:SetObeyStepOnDrag(true)
			local track = slider:CreateTexture(nil, "BACKGROUND")
			track:SetColorTexture(.25, .25, .28, 1)
			track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(4)
			local thumb = slider:CreateTexture(nil, "ARTWORK")
			thumb:SetColorTexture(.8, .8, .85, 1)
			thumb:SetSize(10, 16)
			slider:SetThumbTexture(thumb)
			slider.valueText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			if compact then
				slider.valueText:SetPoint("TOPRIGHT", panel, "TOPLEFT", left + cellWidth, top)
			else
				slider.valueText:SetPoint("LEFT", slider, "RIGHT", 32, 0)
			end
			slider:SetScript("OnValueChanged", function(self, value)
				value = info.minValue + math.floor((value - info.minValue) / info.stepSize + .5) * info.stepSize
				self.valueText:SetText(info.formatter and info.formatter(value) or tostring(value))
				if not panel.initializing then Changed(key, info:ConvertValue(value, false)) end
			end)
			local minus = Button(panel, "−", 20, function() slider:SetValue(slider:GetValue() - info.stepSize) end)
			minus:SetPoint("RIGHT", slider, "LEFT", -4, 0)
			local plus = Button(panel, "+", 20, function() slider:SetValue(slider:GetValue() + info.stepSize) end)
			plus:SetPoint("LEFT", slider, "RIGHT", 4, 0)
			slider.key = key
			panel.controls[#panel.controls + 1] = slider
			panel.controls[#panel.controls + 1] = minus
			panel.controls[#panel.controls + 1] = plus
		end
	end
	panel.layoutHint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.layoutHint:SetPoint("TOPLEFT", 16, -328)
	panel.layoutHint:SetWidth(width - 32)
	panel.layoutHint:SetJustifyH("LEFT")
	panel.layoutHint:SetWordWrap(true)
	panel.layoutHint:SetText(F.L.AdjustPresetHint)
	local layoutNameTop = 328 + math.ceil(panel.layoutHint:GetStringHeight()) + 8
	panel.presetStatusTop = layoutNameTop + 36
	panel.layoutLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.layoutLabel:SetPoint("TOPLEFT", 16, -layoutNameTop - 6)
	panel.layoutLabel:SetText(F.L.AdjustNewLayout)
	panel.layoutName = CreateFrame("EditBox", nil, panel, "BackdropTemplate")
	panel.layoutName:SetAutoFocus(false)
	panel.layoutName:EnableMouse(true)
	panel.layoutName:SetFontObject(GameFontHighlight)
	panel.layoutName:SetTextInsets(6, 6, 0, 0)
	panel.layoutName:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
	panel.layoutName:SetBackdropColor(.12, .12, .14, 1)
	panel.layoutName:SetBackdropBorderColor(.35, .35, .4, 1)
	panel.layoutName:SetSize(160, 24)
	panel.layoutName:SetPoint("TOPRIGHT", -16, -layoutNameTop)
	panel.layoutName:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.status:SetWidth(width - 32)
	panel.status:SetJustifyH("LEFT")
	panel.status:SetJustifyV("TOP")
	panel.save = Button(panel, F.L.AdjustSave, width - 48 - cancelWidth, SaveOrReload)
	panel.save:SetPoint("BOTTOMLEFT", 16, 16)
	panel.cancel = Button(panel, CANCEL, cancelWidth, Close)
	panel.cancel:SetPoint("BOTTOMRIGHT", -16, 16)
	panel.preview = F.AdjustPreview.Create(UIParent)
	panel:SetScript("OnShow", function(self)
		for _, event in ipairs({"PLAYER_REGEN_DISABLED", "EDIT_MODE_LAYOUTS_UPDATED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "ADDON_RESTRICTION_STATE_CHANGED"}) do
			self:RegisterEvent(event)
		end
	end)
	panel:SetScript("OnHide", function(self)
		-- 父層隱藏也算關閉，不能在父層恢復時帶著已丟棄的草稿重新出現。
		self:Hide()
		self:StopMovingOrSizing()
		self.preview:Hide()
		self:UnregisterAllEvents()
		draft, baseline = nil, nil
	end)
	panel:SetScript("OnEvent", function(self, event)
		-- 強制關閉不走取消流程；已提交的狀態由 OnHide 保留，避免重複保存。
		if event == "PLAYER_REGEN_DISABLED" then self:Hide(); return end
		if committing then return end
		if reloadRequired then
			panel.preview:Hide()
		elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" or event == "ADDON_RESTRICTION_STATE_CHANGED" then
			if not IsAvailable() then Close()
			elseif Render() then
				panel.preview:Show()
				if panel.status:GetText() == F.L.AdjustUnavailable then Status(F.L.AdjustHint) end
			else panel.preview:Hide(); Status(F.L.AdjustUnavailable) end
		else
			Close()
		end
	end)
	EventRegistry:RegisterCallback("EditMode.Enter", function() if panel:IsShown() then panel:Hide() end end, A)
end

function A.Open()
	if not IsAvailable() then UIErrorsFrame:AddMessage(F.L.AdjustUnavailable, 1, .3, .3); return end
	if panel and panel:IsShown() then return end
	if reloadRequired then panel:Show(); return end
	local info, active, system = ReadLayouts()
	if not info then UIErrorsFrame:AddMessage(F.L.AdjustConflict, 1, .3, .3); return end
	if not keys then
		local S = Enum.EditModeDamageMeterSetting
		keys = {S.Style, S.Numbers, S.FrameWidth, S.FrameHeight, S.BarHeight, S.Padding, S.Transparency, S.BackgroundTransparency, S.TextSize}
		descriptions = EditModeSettingDisplayInfoManager:GetSystemSettingDisplayInfoMap(Enum.EditModeSystem.DamageMeter)
	end
	local values = GetValues(system)
	for _, key in ipairs(keys) do
		local value, desc = values[key], descriptions[key]
		if issecretvalue(value) or type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
			UIErrorsFrame:AddMessage(F.L.AdjustConflict, 1, .3, .3); return
		end
		if desc.options then
			local valid
			for _, option in ipairs(desc.options) do if value == option.value then valid = true end end
			if not valid then UIErrorsFrame:AddMessage(F.L.AdjustConflict, 1, .3, .3); return end
		end
	end
	if not panel then CreatePanel() end
	baseline = {index = info.activeLayout, name = active.layoutName, kind = active.layoutType, values = values}
	draft = {}
	for _, key in ipairs(keys) do draft[key] = values[key] end
	reloadRequired = false
	panel.initializing = true
	for _, control in ipairs(panel.controls) do
		control:Enable()
		local key = control.key
		if key then
			local desc = descriptions[key]
			if desc.options then
				SetChoiceState(control, draft[key])
			else
				local value = desc:ConvertValueForDisplay(draft[key])
				control:SetValue(value)
				control.valueText:SetText(desc.formatter and desc.formatter(value) or tostring(value))
			end
		end
	end
	local preset = active.layoutType == Enum.EditModeLayoutType.Preset
	panel.statusTop = preset and panel.presetStatusTop or 328
	panel.status:ClearAllPoints()
	panel.status:SetPoint("TOPLEFT", 16, -panel.statusTop)
	panel.layoutHint:SetShown(preset)
	panel.layoutLabel:SetShown(preset)
	panel.layoutName:SetShown(preset)
	panel.layoutName:Enable()
	local suffix, name = 1, "MuonMeter"
	local used = {}; for _, layout in ipairs(info.layouts) do used[layout.layoutName] = true end
	while used[name] do suffix = suffix + 1; name = "MuonMeter "..suffix end
	panel.layoutName:SetText(name)
	panel.initializing = false
	panel.save:SetText(F.L.AdjustSave)
	panel.cancel:Enable()
	Status(F.L.AdjustHint)
	panel.preview:ClearAllPoints()
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", UIParent, "CENTER", -500, 280)
	-- 預覽跟著私有面板移動，不疊在真實統計上，避免透明背景透出兩套量條。
	panel.preview:SetPoint("TOPLEFT", panel, "TOPRIGHT", 24, 0)
	panel:Show()
	if Render() then panel.preview:Show() else Status(F.L.AdjustUnavailable) end
end
