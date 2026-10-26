local addonName, ns = ...
local F = {}
ns[2], ns[3] = F, {GlowTex = "Interface\\AddOns\\MuonMeter\\Media\\glow.tga"}

local modules, moduleOrder, callbacks = {}, {}, {}
local applied = {}
local eventFrame = CreateFrame("Frame")

F.options = {
	{key = "DamageMeterSkin", default = true, reload = true},
	{key = "DamageMeterHidePlayer"},
	{key = "DamageMeterMove", default = true},
	{key = "DamageMeterNumbers", default = true, reload = true},
	{key = "DamageMeterFade"},
	{key = "DamageMeterTooltip"},
}
local options = {}
for _, option in ipairs(F.options) do options[option.key] = option end

function F.RegisterModule(name, settingKey)
	local module = {settingKey = settingKey}
	modules[name] = module
	moduleOrder[#moduleOrder + 1] = module
	return module
end

function F.GetModule(name)
	return modules[name]
end

function F.RegisterEvent(event, callback)
	callbacks[event] = callback
	eventFrame:RegisterEvent(event)
end

function F.GetSetting(key)
	return MuonMeterDB[key] == true
end

function F.HasPendingSettings()
	for _, option in ipairs(F.options) do
		if option.reload and F.GetSetting(option.key) ~= applied[option.key] then return true end
	end
	return false
end

function F.SetSetting(key, value)
	local option = options[key]
	value = (value == true)
	if F.GetSetting(key) == value then return end
	MuonMeterDB[key] = value
	if not option.reload then
		local module = modules[key]
		module.enabled = value
		module:OnSettingChanged()
		modules.DamageMeter:RequestUpdate()
	end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if (...) ~= addonName then return end
		if type(MuonMeterDB) ~= "table" then MuonMeterDB = {} end
		for _, option in ipairs(F.options) do
			local value = MuonMeterDB[option.key]
			if value == nil then value = option.default end
			MuonMeterDB[option.key] = (value == true)
			applied[option.key] = F.GetSetting(option.key)
		end
		eventFrame:UnregisterEvent(event)
	elseif event == "PLAYER_LOGIN" then
		eventFrame:UnregisterEvent(event)
		for _, module in ipairs(moduleOrder) do
			local option = options[module.settingKey]
			module.enabled = (not option or applied[module.settingKey] == true)
			-- 即時選項只安裝一次；後續以 runtime gate 啟停及完成清理。
			if not option or not option.reload or module.enabled then module:OnEnable() end
		end
	else
		callbacks[event](event, ...)
	end
end)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
