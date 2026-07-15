-- NeonRun / CrystalField —— 能量水晶实体(M5 保底收入渠道 + M8.1 磁吸 + ADR-42 满蓝不捕获)
-- 策划案 §4.5:主行车线摆水晶,进磁吸半径 CrystalMagnetRadius(7)即尝试捕获 +CrystalGain(受 CrystalCap),
--   并飞向玩家(纯表现)。CollectionService Tag="EnergyCrystal";捕获→冷却→回家复现。纯表现/拾取层。
-- 磁吸边界=拾取边界:进半径即入账(确定性,验收"磁吸半径边界拾取");飞入动画不影响入账时机。
-- ADR-42:回调返回入账 delta——**≤0(蓝区已满)则不捕获、留在原地**,持槽点火不再销毁沿途供给;
--   回调无返回值(nil)按旧语义捕获(兼容计数型回调)。
-- 用法:local field = CrystalField.new(function() return energy:addCrystal() end); field:step(bikePos, dt)
local CS = game:GetService("CollectionService")
local RS = game:GetService("ReplicatedStorage")

local TAG = "EnergyCrystal"
local COOLDOWN_SEC = 6      -- 捕获后重现冷却(灰盒常量;正式可入 Config)
local FLY_SEC = 0.14        -- 磁吸飞入玩家的视觉时长(纯表现,不影响入账)

local CrystalField = {}
CrystalField.__index = CrystalField

function CrystalField.new(onPickup)
	local self = setmetatable({}, CrystalField)
	-- 磁吸半径走 Config(零魔法数字);与 EnergyState 绑同一 Energy 实例,属性面板实时可调
	local nr = RS:WaitForChild("NeonRun")
	local ConfigLive = require(nr.Modules.ConfigLive)
	self.cfg = ConfigLive.bind(nr.Config.Energy, require(nr.Config.Energy))
	self.onPickup = onPickup
	self.crystals = {}
	self.cooldown = COOLDOWN_SEC
	self._conns = {}
	for _, part in ipairs(CS:GetTagged(TAG)) do self:_register(part) end
	table.insert(self._conns, CS:GetInstanceAddedSignal(TAG):Connect(function(p) self:_register(p) end))
	table.insert(self._conns, CS:GetInstanceRemovedSignal(TAG):Connect(function(p) self.crystals[p] = nil end))
	return self
end

function CrystalField:_register(part)
	if not part:IsA("BasePart") then return end
	-- homePos/homeSize:飞入会改 Position/Size,复现时须还原到摆放原位
	self.crystals[part] = {
		cooldown = 0, flyT = 0,
		homePos = part.Position, homeSize = part.Size,
		baseTransparency = part.Transparency,
	}
end

function CrystalField:_setAvailable(part, state, avail)
	if avail then
		part.Position = state.homePos
		part.Size = state.homeSize
		part.Transparency = state.baseTransparency
		if part:FindFirstChildWhichIsA("PointLight") then part:FindFirstChildWhichIsA("PointLight").Enabled = true end
	else
		part.Transparency = 1
		if part:FindFirstChildWhichIsA("PointLight") then part:FindFirstChildWhichIsA("PointLight").Enabled = false end
	end
end

function CrystalField:step(bikePos, dt)
	if not bikePos then return end
	dt = dt or 0
	local radius = self.cfg.get("CrystalMagnetRadius")
	for part, state in pairs(self.crystals) do
		if part and part.Parent then
			if state.cooldown > 0 then
				-- 冷却中:先播飞入视觉(飞向玩家并缩小),飞完隐藏;冷却到点回家复现
				if state.flyT > 0 then
					state.flyT = math.max(0, state.flyT - dt)
					local p = 1 - state.flyT / FLY_SEC           -- 0→1 进度
					part.Position = state.homePos:Lerp(bikePos, math.clamp(p, 0, 1))
					part.Size = state.homeSize * (1 - 0.85 * p)  -- 逐渐缩小到 15%
					if state.flyT == 0 then self:_setAvailable(part, state, false) end
				end
				state.cooldown = math.max(0, state.cooldown - dt)
				if state.cooldown == 0 then self:_setAvailable(part, state, true) end
			else
				-- 可用:进磁吸半径尝试捕获——立刻入账(边界确定性),随后飞入玩家(纯表现)。
				-- ADR-42:回调返回 ≤0(蓝区已满)则不捕获、留在原地,骑过白吃不再销毁供给。
				if (state.homePos - bikePos).Magnitude <= radius then
					local gained = self.onPickup and self.onPickup(part) or nil
					if gained == nil or (type(gained) == "number" and gained > 0) then
						state.cooldown = self.cooldown
						state.flyT = FLY_SEC
					end
				end
			end
		end
	end
end

function CrystalField:destroy()
	for _, c in ipairs(self._conns) do c:Disconnect() end
	self._conns = {}
	self.crystals = {}
end

return CrystalField
