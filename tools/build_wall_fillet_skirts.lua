--[[
NEON RUN — 墙根圆角裙板生成器(ADR-45 白盒:地面→侧墙过渡)
给指定 WallRideSurface 直墙的墙根加四分之一圆弧裙板(截面小面片,法线 0°→90° 渐变):
  · 面片打 **Rideable**(地面白名单):进场沿裙板自然骑上去,不打 WallRideSurface——
    过渡物理由控制器解析圆角(WallRide_FilletRadius)走,裙板只管"看得见+骑得上"。
  · 半径读活配置 `WallRide_FilletRadius`(几何与物理同源;0/缺失=拒建)。
  · 幂等:每面墙的裙板 Model(<墙名>_FilletSkirt,挂墙同级)按名删重建。
  · 前提约定:墙底=路面/地面高度(现场 WallRig/Z5 均如此);墙底悬空则裙板跟着悬空,先对齐再跑。
用法:MCP execute_luau(datamodel=Edit)或命令栏;改 TARGETS 重跑即可。
]]
local CS = game:GetService("CollectionService")

-- ==== 调参区 ====
local TARGETS = { "WallRide_L", "WallRide_R" } -- Workspace 递归按名找(默认=试炼道 Z5 两面墙)
local FACETS = 6        -- 每 90° 面片数(15°/片)
local THICK = 0.6       -- 面片厚
local BOTH_SIDES = true -- ±X 两侧贴面都建裙板
-- ================

local hInst = game:GetService("ReplicatedStorage").NeonRun.Config.Handling
local R = hInst:GetAttribute("WallRide_FilletRadius") or 0
assert(R > 1.7, "WallRide_FilletRadius=" .. tostring(R) .. " ≤ 悬浮高:先 SetAttribute 再建裙板")

local report = {}
local function buildSkirt(wall)
	local old = wall.Parent:FindFirstChild(wall.Name .. "_FilletSkirt")
	if old then old:Destroy() end
	local model = Instance.new("Model")
	model.Name = wall.Name .. "_FilletSkirt"
	local cf = wall.CFrame
	local halfT, halfH, len = wall.Size.X / 2, wall.Size.Y / 2, wall.Size.Z
	for _, side in ipairs(BOTH_SIDES and { 1, -1 } or { 1 }) do
		local n = cf.RightVector * side
		local base = cf.Position + n * halfT - Vector3.new(0, halfH, 0) -- 该侧墙底贴面线中点
		for i = 1, FACETS do
			local a0 = (i - 1) * (math.pi / 2) / FACETS
			local a1 = i * (math.pi / 2) / FACETS
			-- 截面弧(x=离面距,y=离底高):x(θ)=R(1−sinθ),y(θ)=R(1−cosθ)
			local x0, y0 = R * (1 - math.sin(a0)), R * (1 - math.cos(a0))
			local x1, y1 = R * (1 - math.sin(a1)), R * (1 - math.cos(a1))
			local am = (a0 + a1) / 2
			local nu = n * math.sin(am) + Vector3.new(0, math.cos(am), 0) -- 面片外法线(弦⊥中点半径)
			local chordLen = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
			local chordDir = (n * (x1 - x0) + Vector3.new(0, y1 - y0, 0)) / chordLen
			local part = Instance.new("Part")
			part.Name = string.format("Fillet_%s_%02d", side > 0 and "P" or "N", i)
			part.Anchored = true
			part.Size = Vector3.new(THICK, chordLen + 0.12, len) -- 弦向微搭接防缝
			part.CFrame = CFrame.fromMatrix(
				base + n * ((x0 + x1) / 2) + Vector3.new(0, (y0 + y1) / 2, 0) - nu * (THICK / 2),
				nu, chordDir)
			part.Material = Enum.Material.SmoothPlastic
			part.Color = i % 2 == 0 and Color3.fromRGB(70, 150, 160) or Color3.fromRGB(90, 175, 185)
			CS:AddTag(part, "Rideable")
			part.Parent = model
		end
	end
	model.Parent = wall.Parent
	-- 底部对齐核对:墙底贴面线正下方地面高度(仅报告,不自动挪墙)
	local probe = workspace:Raycast(
		cf.Position + cf.RightVector * (halfT + R + 2) - Vector3.new(0, halfH - 2, 0),
		Vector3.new(0, -30, 0))
	local groundGap = probe and ((cf.Position.Y - halfH) - probe.Position.Y) or nil
	report[#report + 1] = string.format("%s:裙板 %d 片,墙底-地面差=%s",
		wall.Name, FACETS * (BOTH_SIDES and 2 or 1),
		groundGap and string.format("%.2f", groundGap) or "无地面(悬空?)")
end

for _, name in ipairs(TARGETS) do
	local wall = workspace:FindFirstChild(name, true)
	if wall and wall:IsA("BasePart") and CS:HasTag(wall, "WallRideSurface") then
		buildSkirt(wall)
	else
		report[#report + 1] = name .. ":未找到/非授权墙,跳过"
	end
end

local msg = "裙板生成(R=" .. R .. "):\n" .. table.concat(report, "\n")
print(msg)
return msg
