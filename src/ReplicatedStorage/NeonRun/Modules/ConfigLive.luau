-- NeonRun / ConfigLive —— 配置表映射为宿主实例 Attributes
-- Play 中在属性面板改 Attribute 即实时生效(调参面板 v0)
-- 用法:
--   local live = ConfigLive.bind(cfgInstance, require(cfgInstance))
--   live.get("Speed", "Base")
--   live.reset()  -- Attributes 重置回模块默认值
local ConfigLive = {}

local function flatten(prefix, tbl, out)
	for k, v in pairs(tbl) do
		local key = prefix == "" and tostring(k) or prefix .. "_" .. tostring(k)
		if type(v) == "table" then
			flatten(key, v, out)
		else
			out[key] = v
		end
	end
end

function ConfigLive.bind(host, defaults)
	local flat = {}
	flatten("", defaults, flat)
	for key, v in pairs(flat) do
		if host:GetAttribute(key) == nil then
			host:SetAttribute(key, v)
		end
	end
	local api = {}
	function api.get(...)
		local key = table.concat({ ... }, "_")
		local v = host:GetAttribute(key)
		if v == nil then
			v = flat[key]
		end
		return v
	end
	function api.reset()
		for key, v in pairs(flat) do
			host:SetAttribute(key, v)
		end
	end
	return api
end

return ConfigLive
