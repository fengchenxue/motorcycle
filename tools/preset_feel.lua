--[[
NEON RUN — GR2 手感预设一键切换(ADR-44;命令栏或 MCP execute_luau 跑,Edit/Play 均可)
用法:改下面 PRESET 为 "stock" | "steady" | "hot" 后整段执行;Play 内切换即时生效,停止后不留痕。
  stock  = 还原 Handling.luau 源码默认(GR2 六特性归零 = 旧手感)
  steady = GR2 稳妥档(低近紧相机+侧倾+速度FOV,移动端友好)
  hot    = GR2 激进档(更低更近更快;FOVSprint 97 需真机验证晕动)
只写 Handling Attributes,不碰源码;三档均先回源码值再覆盖 → 切换幂等不累积。
微调:T 调参面板 / 属性面板;满意后对 AI 说"锁定当前参数",AI 写回 Config 源码+更新基准表。
若相机侧倾方向感觉反了:把 Camera_SteerRollGain 改成负值即可(面板支持 -1~1)。
v2(人类首轮反馈 2026-07-15"参考 GR2:左右移动有插值平滑,倾斜十分克制"):
  侧倾大砍(0.35/10°→0.12/4°)+侧倾低通 SteerRollLerpSec 去过冲+横向独立插值 LatLagSec。
v3(人类二轮反馈 2026-07-15"在 hot 基础上改:平地镜头抖动小一些,镜头晃动再平稳一些"):
  hot=工作基线;震动大减(ShakeSprint 0.25→0.14/ShakeSpeedGain 0.12→0.04/频率 14→11)+
  全链路低通软化(FollowLag 0.05→0.07/YawLag 0.08→0.11/LatLag 0.18→0.24/RollLerp 0.12→0.18/FOVLerp 0.12→0.16)。
  steady 保持 v2 原值作 A/B 对照。
]]
local PRESET = "steady"  -- ◀◀ 改这里:"stock" / "steady" / "hot"

local RS = game:GetService("ReplicatedStorage")
local hInst = RS:WaitForChild("NeonRun").Config.Handling

-- 源码默认值(require(Clone) 强制重编译,躲 require 缓存 —— 坑 15)
local defaults = require(hInst:Clone())
local flat = {}
local function flatten(prefix, tbl)
	for k, v in pairs(tbl) do
		local key = prefix == "" and tostring(k) or prefix .. "_" .. tostring(k)
		if type(v) == "table" then flatten(key, v) else flat[key] = v end
	end
end
flatten("", defaults)

-- 预设触及的键(stock=全部回源码值;steady/hot=在源码值基础上覆盖)
local TOUCHED = {
	"Camera_Distance", "Camera_Height", "Camera_LookAhead", "Camera_LookUp",
	"Camera_FollowLagSec", "Camera_YawLagSec",
	"Camera_FOVBase", "Camera_FOVSprint", "Camera_FlowFOV", "Camera_FOVLerpSec",
	"Camera_ShakeSprint", "Camera_ShakeFreqHz",
	"Camera_SteerRollGain", "Camera_SteerRollMaxDeg", "Camera_SteerRollLerpSec", "Camera_LatLagSec",
	"Camera_FOVSpeedGain",
	"Camera_FOVPunchDeg", "Camera_FOVPunchDecaySec", "Camera_LandDipPerVy", "Camera_LandDipMax",
	"Camera_ShakeSpeedGain", "Camera_AirPitchDownDeg", "Camera_AirPitchLerpSec",
	"Steering_InputRampInSec", "Steering_TurnRateHighDeg",
	"Lean_BodyRollMaxDeg", "Lean_LerpSpeed", "Lean_OvershootDeg",
}

local OVERRIDES = {
	stock = {},
	steady = {
		Camera_Distance = 12.5, Camera_Height = 4.2, Camera_LookAhead = 14, Camera_LookUp = 3,
		Camera_FollowLagSec = 0.07, Camera_YawLagSec = 0.12,
		Camera_FOVBase = 76, Camera_FOVSprint = 92, Camera_FlowFOV = 97, Camera_FOVLerpSec = 0.15,
		Camera_ShakeSprint = 0.20, Camera_ShakeFreqHz = 13,
		Camera_SteerRollGain = 0.12, Camera_SteerRollMaxDeg = 4, Camera_SteerRollLerpSec = 0.15,
		Camera_LatLagSec = 0.22, Camera_FOVSpeedGain = 0.08,
		Camera_FOVPunchDeg = 5, Camera_FOVPunchDecaySec = 0.35,
		Camera_LandDipPerVy = 0.006, Camera_LandDipMax = 1.2,
		Camera_ShakeSpeedGain = 0.08, Camera_AirPitchDownDeg = 4, Camera_AirPitchLerpSec = 0.25,
		Steering_InputRampInSec = 0.09, Steering_TurnRateHighDeg = 60,
		Lean_BodyRollMaxDeg = 26, Lean_LerpSpeed = 11, Lean_OvershootDeg = 5,
	},
	hot = {
		-- v3(二轮反馈):震动大减+低通全链路软化;机位/FOV/转向/车倾维持 hot 原值
		Camera_Distance = 11, Camera_Height = 3.5, Camera_LookAhead = 16, Camera_LookUp = 3.2,
		Camera_FollowLagSec = 0.07, Camera_YawLagSec = 0.11,
		Camera_FOVBase = 80, Camera_FOVSprint = 97, Camera_FlowFOV = 103, Camera_FOVLerpSec = 0.16,
		Camera_ShakeSprint = 0.14, Camera_ShakeFreqHz = 11,
		Camera_SteerRollGain = 0.18, Camera_SteerRollMaxDeg = 6, Camera_SteerRollLerpSec = 0.18,
		Camera_LatLagSec = 0.24, Camera_FOVSpeedGain = 0.10,
		Camera_FOVPunchDeg = 6, Camera_FOVPunchDecaySec = 0.30,
		Camera_LandDipPerVy = 0.008, Camera_LandDipMax = 1.4,
		Camera_ShakeSpeedGain = 0.04, Camera_AirPitchDownDeg = 5, Camera_AirPitchLerpSec = 0.25,
		Steering_InputRampInSec = 0.07, Steering_TurnRateHighDeg = 65,
		Lean_BodyRollMaxDeg = 30, Lean_LerpSpeed = 13, Lean_OvershootDeg = 6,
	},
}

local ov = OVERRIDES[PRESET]
if not ov then
	warn(("[preset_feel] 未知预设 %q(可选 stock/steady/hot)"):format(tostring(PRESET)))
	return
end

local changed, skipped, missing = 0, 0, 0
for _, key in ipairs(TOUCHED) do
	local target = ov[key]
	if target == nil then target = flat[key] end
	if target == nil then
		warn(("[preset_feel] 键 %s 在 Handling 源码里不存在(源码未同步?)"):format(key))
		missing += 1
	else
		local old = hInst:GetAttribute(key)
		if old ~= target then
			hInst:SetAttribute(key, target)
			print(("[preset_feel]   %s  %s → %s"):format(key, tostring(old), tostring(target)))
			changed += 1
		else
			skipped += 1
		end
	end
end
print(("[preset_feel] 预设 %q 应用完毕:改 %d 键 / 已是目标值 %d 键%s"):format(
	PRESET, changed, skipped, missing > 0 and (" / 缺失 " .. missing .. " 键") or ""))
print("[preset_feel] 微调=T 面板或属性面板;满意后对 AI 说“锁定当前参数”。侧倾方向反了就把 SteerRollGain 改负值。")
