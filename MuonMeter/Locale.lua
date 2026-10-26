local _, ns = ...
local F = ns[2]
local L = {}
F.L = L

local locale = GetLocale()
local colon = (locale == "zhTW" or locale == "zhCN") and "：" or ": "
L.TooltipInterrupts = DAMAGE_METER_TYPE_INTERRUPTS..colon
L.TooltipDispels = DAMAGE_METER_TYPE_DISPELS..colon
L.TooltipAvoidableDamage = DAMAGE_METER_TYPE_AVOIDABLE_DAMAGE_TAKEN..colon

if locale == "zhTW" then
	L.DamageMeterSkin = "視窗美化"
	L.DamageMeterSkin_Desc = "美化統計視窗，|cff00ccff右鍵|r點擊|cff00ccff場次|r按鈕切換統計類型，|cff00ccff中鍵|r點擊|cff00ccff齒輪|r折疊傷害量表。"
	L.DamageMeterHidePlayer = "隱藏固定玩家列"
	L.DamageMeterHidePlayer_Desc = "隱藏固定在頂部或底部的自身統計列；正常排名中的自己仍會顯示。"
	L.DamageMeterMove = "點擊拖動"
	L.DamageMeterMove_Desc = "|cff00ccffAlt + 右鍵|r拖曳左側標題列可以移動傷害量表；位置會自動保存至原生編輯模式。"
	L.DamageMeterNumbers = "簡化格式"
	L.DamageMeterNumbers_Desc = "隱藏伺服器名稱，數值使用縮寫。"
	L.DamageMeterFade = "閒置淡出"
	L.DamageMeterFade_Desc = "脫戰閒置時淡至 30%；滑鼠指向或進入戰鬥時恢復。"
	L.DamageMeterTooltip = "明細提示"
	L.DamageMeterTooltip_Desc = "滑鼠指向傷害或治療計量條時，顯示中斷、驅散及受到的可躲避傷害；只在戰鬥外顯示。"

	L.AdjustTitle = "調整面板"
	L.AdjustDescription = "使你可以直接調整統計視窗的外觀，不必進入編輯模式。"
	L.AdjustSample = "預覽角色 %d"
	L.AdjustSave = "儲存並重載"
	L.AdjustHint = "尚未修改原生量表。調整完成後請點擊「儲存並重載」；取消會放棄本次草稿。"
	L.AdjustNewLayout = "另存布局名稱"
	L.AdjustPresetHint = "目前使用預設布局，調整後需要新建自訂布局。"
	L.AdjustUnavailable = "目前無法調整；請脫戰、退出編輯模式後再試。若仍無法調整，請重載介面。"
	L.AdjustConflict = "目前布局或設定已改變，無法提交這份草稿。請關閉面板後重新開啟。"
	L.AdjustInvalidName = "布局名稱無效或已存在，請更名。"
	L.AdjustLayoutsFull = "帳號與角色布局數量皆已達上限，無法儲存新布局。"
	L.AdjustSaveFailed = "保存結果未能確認，請按重載介面後檢查原生布局。本次不再重複提交。"

	L.Reload = "重載介面"
	L.ReloadRequired = "設定已保存，重載後生效。"
	L.ReloadOption = "此選項在重載介面後生效。"
elseif locale == "zhCN" then
	L.DamageMeterSkin = "窗口美化"
	L.DamageMeterSkin_Desc = "美化统计窗口，|cff00ccff右键|r点击|cff00ccff场次|r按钮切换统计类型，|cff00ccff中键|r点击|cff00ccff齿轮|r折叠伤害统计。"
	L.DamageMeterHidePlayer = "隐藏固定玩家行"
	L.DamageMeterHidePlayer_Desc = "隐藏固定在顶部或底部的自身统计行；正常排名中的自己仍会显示。"
	L.DamageMeterMove = "点击拖动"
	L.DamageMeterMove_Desc = "|cff00ccffAlt + 右键|r拖动左侧标题栏可以移动伤害统计；位置会自动保存到原生编辑模式。"

	L.DamageMeterNumbers = "简化格式"
	L.DamageMeterNumbers_Desc = "隐藏服务器名称，数值使用缩写。"
	L.DamageMeterFade = "空闲淡出"
	L.DamageMeterFade_Desc = "脱战空闲时淡至 30%；鼠标指向或进入战斗时恢复。"
	L.DamageMeterTooltip = "明细提示"
	L.DamageMeterTooltip_Desc = "鼠标指向伤害或治疗计量条时，显示打断、驱散及受到的可躲避伤害；只在战斗外显示。"

	L.AdjustTitle = "调整面板"
	L.AdjustDescription = "使你可以直接调整统计窗口的外观，不必进入编辑模式。"
	L.AdjustSample = "预览角色 %d"

	L.AdjustSave = "保存并重载"
	L.AdjustHint = "尚未修改原生统计。调整完成后请点击「保存并重载」；取消会放弃本次草稿。"
	L.AdjustNewLayout = "另存布局名称"
	L.AdjustPresetHint = "当前使用预设布局，调整后需要新建自定义布局。"
	L.AdjustUnavailable = "当前无法调整；请在脱战、退出编辑模式并结束拖动后重试。外观或简化格式若有尚未生效的更改，请先重载。"
	L.AdjustConflict = "当前布局或设置已改变，无法提交这份草稿。请关闭面板后重新打开。"
	L.AdjustInvalidName = "布局名称无效或已存在，请使用其他名称。"
	L.AdjustLayoutsFull = "账号与角色布局数量均已达到上限，无法另存预设布局。"
	L.AdjustSaveFailed = "无法确认保存结果，请按重载界面后检查原生布局。本次不会重复提交。"

	L.Reload = "重载界面"
	L.ReloadRequired = "设置已保存，重载后生效。"
	L.ReloadOption = "此选项在重载界面后生效。"
else
	L.DamageMeterSkin = "Window Styling"
	L.DamageMeterSkin_Desc = "Style the statistics windows. |cff00ccffRight-click|r the |cff00ccffsession|r button to switch the statistic type. |cff00ccffMiddle-click|r the |cff00ccffgear|r to collapse the damage meter."
	L.DamageMeterHidePlayer = "Hide Pinned Player Row"
	L.DamageMeterHidePlayer_Desc = "Hide your statistics row pinned at the top or bottom; your row in the regular rankings remains visible."
	L.DamageMeterMove = "Click and Drag"
	L.DamageMeterMove_Desc = "Use |cff00ccffAlt + right mouse button|r to drag the left side of the header and move the damage meter. Its position is automatically saved to the native Edit Mode layout."

	L.DamageMeterNumbers = "Simplified Format"
	L.DamageMeterNumbers_Desc = "Hide realm names and abbreviate numbers."
	L.DamageMeterFade = "Idle Fade"
	L.DamageMeterFade_Desc = "Fade to 30% while idle out of combat. Hover the meter or enter combat to restore full opacity."
	L.DamageMeterTooltip = "Details Tooltip"
	L.DamageMeterTooltip_Desc = "Hover a damage or healing bar to see interrupts, dispels, and avoidable damage taken. Only shown out of combat."

	L.AdjustTitle = "Adjustment Panel"
	L.AdjustDescription = "Adjust the statistics windows' appearance directly without entering Edit Mode."
	L.AdjustSample = "Preview player %d"

	L.AdjustSave = "Save and Reload"
	L.AdjustHint = "The native meter is unchanged. Click \"Save and Reload\" when finished; Cancel discards this draft."
	L.AdjustNewLayout = "New layout name"
	L.AdjustPresetHint = "You are using a preset layout. Saving these changes requires a new custom layout."
	L.AdjustUnavailable = "Leave combat and Edit Mode, and finish dragging before trying again. Reload any pending appearance or number-format changes first."
	L.AdjustConflict = "The layout or settings have changed. Close and reopen this panel before saving."
	L.AdjustInvalidName = "Invalid or duplicate layout name. Choose another name."
	L.AdjustLayoutsFull = "Account and character layouts are both full; the preset cannot be saved as a new layout."
	L.AdjustSaveFailed = "Saving could not be confirmed. Reload the UI and check the native layout. This draft will not be submitted again."

	L.Reload = "Reload UI"
	L.ReloadRequired = "Settings saved. Reload the UI to apply."
	L.ReloadOption = "This option takes effect after reloading the UI."
end
