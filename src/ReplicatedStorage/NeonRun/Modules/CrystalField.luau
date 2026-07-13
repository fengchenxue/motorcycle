-- NeonRun / CrystalField —— 能量水晶实体(M5 保底收入渠道)
-- 策划案 §4.5:主行车线摆水晶,顺路骑过即得 +CrystalGain(由 EnergyState 受 CrystalCap 约束)。
-- CollectionService Tag="EnergyCrystal";骑过拾取→回调→冷却→重现。纯表现/拾取层。
-- 用法:local field = CrystalField.new(function() energy:addCrystal() end); field:step(bikePos, dt)
local CS = game:GetService("CollectionService")

local TAG = "EnergyCrystal"
local PICKUP_RADIUS = 8
local COOLDOWN_SEC = 6

local CrystalField = {}
CrystalField.__index = CrystalField

function CrystalField.new(onPickup)
	local self = setmetatable({}, CrystalField)
	self.onPickup = onPickup
	self.crystals = {}
	self.pickupRadius = PICKUP_RADIUS
	self.cooldown = COOLDOWN_SEC
	self._conns = {}
	for _, part in ipairs(CS:GetTagged(TAG)) do self:_register(part) end
	table.insert(self._conns, CS:GetInstanceAddedSignal(TAG):Connect(function(p) self:_register(p) end))
	table.insert(self._conns, CS:GetInstanceRemovedSignal(TAG):Connect(function(p) self.crystals[p] = nil end))
	return self
end

function CrystalField:_register(part)
	if not part:IsA("BasePart") then return end
	self.crystals[part] = { cooldown = 0, baseTransparency = part.Transparency }
end

function CrystalField:_setAvailable(part, state, avail)
	if avail then
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
	for part, state in pairs(self.crystals) do
		if part and part.Parent then
			if state.cooldown > 0 then
				state.cooldown = math.max(0, state.cooldown - dt)
				if state.cooldown == 0 then self:_setAvailable(part, state, true) end
			else
				if (part.Position - bikePos).Magnitude <= self.pickupRadius then
					state.cooldown = self.cooldown
					self:_setAvailable(part, state, false)
					if self.onPickup then self.onPickup(part) end
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