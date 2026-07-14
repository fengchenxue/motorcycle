-- NeonRun / tools/jumptable.lua —— 跳距速查表(Edit 模式,execute_luau,纯打印零副作用)
-- 用途:铺赛道前的"尺子"。复刻 BikeController 的飞行积分(dt=1/60 定步):
--   起飞 vy0 = v·tanθ(中心探针弹道脱离,ADR-5);空中 vy -= g·dt(半隐式欧拉);
--   水平速度全额保留并按 Handling.Speed 渐变——按住冲刺=维持档位,松开=衰回 Base(ADR-30)。
-- 近似说明:心流松开首帧衰减速率取冲刺档(误差 <1 stud);落地按"同高平面/指定落差"简化。
-- 权威数字以 Rig 实测为准;本表喂 design §7 跳跃段语法与 TrackBuilder 跳跃可达性 lint(M8.5 P2)。
local RS = game:GetService("ReplicatedStorage")
local H = require(RS.NeonRun.Config.Handling:Clone()) -- 坑15:Clone 强制重编译,防 require 旧缓存

local g = H.Physics.Gravity
local base = H.Speed.Base
local sprint = base * H.Speed.SprintMultiplier
local flow = sprint * H.Speed.FlowExtraMultiplier
local rampDownRate = sprint / H.Speed.RampDownSec -- BikeController: rate = maxSpeed / RampDownSec
local DT = 1 / 60

-- 模拟一跳:v0=起跳速,thetaDeg=起跳坡角,hold=空中是否按住冲刺,dropH=对岸低多少(默认 0=同高)
-- 返回水平跳距(studs)
local function simJump(v0, thetaDeg, hold, dropH)
	local vy = v0 * math.tan(math.rad(thetaDeg))
	local x, y, v = 0, 0, v0
	local floorY = -(dropH or 0)
	for _ = 1, 600 do -- 10s 上限
		vy -= g * DT
		y += vy * DT
		if not hold then
			v += math.clamp(base - v, -rampDownRate * DT, rampDownRate * DT)
		end
		x += v * DT
		if vy < 0 and y <= floorY then
			return x
		end
	end
	return x
end

local out = {}
local function w(s) table.insert(out, s) end
w(("NeonRun 跳距速查表  g=%d  巡航=%d  冲刺=%.0f  心流=%.1f  (dt=1/60)"):format(g, base, sprint, flow))
w("── A. 起跳坡角 × 档位 → 同高落点跳距(studs);括号=空中松开冲刺(ADR-30 抉择差)──")
w("坡角    巡航     冲刺(松开)       心流(松开)")
for _, th in ipairs({ 5, 10, 15, 20, 25, 30, 40, 50 }) do
	w(("%3d°   %5.0f    %5.0f (%5.0f)    %5.0f (%5.0f)"):format(
		th,
		simJump(base, th, true),
		simJump(sprint, th, true), simJump(sprint, th, false),
		simJump(flow, th, true), simJump(flow, th, false)))
end
w("── B. 平断口下坠(θ=0,对岸低 h studs)→ 跳距;同高对岸永远跳不过(vy0=0)──")
w("落差    巡航     冲刺     心流")
for _, h in ipairs({ 10, 20, 40, 80 }) do
	w(("%3d    %5.0f    %5.0f    %5.0f"):format(
		h, simJump(base, 0, true, h), simJump(sprint, 0, true, h), simJump(flow, 0, true, h)))
end
w("缺口设计法(§7):巡航过不去 / 冲刺刚好 / 心流余量;捷径口可用\"心流才过\"档。")
w("坡角+落差组合、改 Config 后的新表:改参重跑本脚本即可(读 Config 实时算)。")
print(table.concat(out, "\n"))
