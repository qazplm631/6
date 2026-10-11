--[[
================================================================================
  ZakaAriaBypass  v1.0      ·      Roblox 客户端反作弊绕过框架
--------------------------------------------------------------------------------
  定位:针对「Remote 上报型 / 客户端脚本检测型」反作弊(圣奥里 及同结构游戏)
  环境:支持元表钩子的注入器(Synapse / KRNL / Fluxus / Delta / 忍者 / Codex 等)

  正确用法(别一上来就开拦截):
    1) 执行脚本 -> 左上角出面版,右侧出悬浮球
    2) 保持默认【侦察模式】,正常玩 1~2 分钟
    3) 看「出包记录」,找带 ac / detect / report / flag 特征的包名
    4) 关掉侦察模式 -> 开「拦截上报包」或「参数洗白」(二选一,别同时开)
    5) 被踢 / 打不出伤害,把出包记录发回来,按实际包结构精调
================================================================================
]]

--=====================================================================
-- 0. 兼容层(不同注入器的 API 名字不一样,全部兜一层)
--=====================================================================
local unpack = table.unpack or unpack

local typeof = typeof or type

local genv = (getgenv and getgenv()) or _G
if genv.ZAKA_ARIA_DESTROY then pcall(genv.ZAKA_ARIA_DESTROY) end

local function safe(fn, ...)
	if type(fn) ~= "function" then return nil end
	local r = { pcall(fn, ...) }
	if r[1] then
		return r[2], r[3], r[4]
	end
	return nil
end

local function attempt(fn, ...)
	if type(fn) ~= "function" then return false end
	return (pcall(fn, ...))
end

local function lower(s)
	return string.lower(tostring(s or ""))
end

local function tn(v)
	return (typeof and typeof(v)) or type(v)
end

local getrawmetatable_ = getrawmetatable or getmetatable
local setreadonly_     = setreadonly or function() end
local newcclosure_     = newcclosure or function(f) return f end
local getnamecallmethod_ = getnamecallmethod or function() return "" end
local checkcaller_     = checkcaller
local hookmetamethod_  = hookmetamethod

local CAP = {
	MetaHook    = type(getrawmetatable) == "function",
	CheckCaller = type(checkcaller) == "function",
	HookMethod  = type(hookmetamethod) == "function",
	Connections = type(getconnections) == "function",
	FileWrite   = type(writefile) == "function",
	Gui         = type(gethui) == "function",
}

--=====================================================================
-- 1. 配置
--=====================================================================
local CFG = {
	Recon           = true,     -- 侦察模式:只记录,不拦不洗(默认开,先摸清游戏)
	BlockKick       = true,     -- 拦截客户端 Kick
	BlockReport     = false,    -- 拦截上报包(直接不发)
	WashReport      = false,    -- 参数洗白(推荐:照发,但内容洗干净)
	DisableClientAC = false,    -- 禁用客户端反作弊脚本
	KillACConnects  = false,    -- 断开反作弊脚本挂的心跳连接(激进)
	HookReadSpoof   = false,    -- 属性读取伪装(AC 读 WalkSpeed 时看到正常值)
	BlockLocalWrite = false,    -- 拦游戏脚本改你的属性(防被冻/被锁)
	SpeedBypass     = false,    -- 物理加速(不改 WalkSpeed,绕开属性检测)
	SpeedValue      = 45,       -- 物理加速速度
	InfiniteJump    = false,    -- 无限跳
	ClampNumbers    = true,     -- 洗白时把异常数值钳回正常范围
	ClampMax        = 60,       -- 数值钳制上限
	Whitelist       = {},       -- 永不拦截的白名单(包名关键词)
}

local CFG_FILE = "zaka_aria_cfg.json"

local function loadCfg()
	if not CAP.FileWrite then return end
	local raw = safe(readfile, CFG_FILE)
	if not raw then return end
	local ok, dec = pcall(function() return game:GetService("HttpService"):JSONDecode(raw) end)
	if not ok or type(dec) ~= "table" then return end
	for k, v in pairs(dec) do
		if CFG[k] ~= nil then CFG[k] = v end
	end
end

local function saveCfg()
	if not CAP.FileWrite then return end
	local ok, enc = pcall(function()
		return game:GetService("HttpService"):JSONEncode(CFG)
	end)
	if ok then safe(writefile, CFG_FILE, enc) end
end

loadCfg()

--=====================================================================
-- 2. 反作弊特征库
--=====================================================================
local AC_TOKENS = {}
for _, w in ipairs({
	"ac", "anticheat", "anticheats", "detect", "detection", "detector", "detected",
	"report", "reported", "reporter", "reporting", "flag", "flagged", "flagging",
	"suspicious", "suspicion", "suspect", "exploit", "exploiter", "exploiting",
	"cheat", "cheater", "cheating", "hack", "hacker", "hacking", "ban", "banned",
	"kick", "kicked", "punish", "punishment", "violation", "violations",
	"integrity", "verify", "verification", "validate", "validation",
	"monitor", "monitoring", "audit", "security", "secure", "guard", "guardian",
	"watchdog", "warden", "sentinel", "sentry", "patrol", "inspect", "inspector",
	"scanner", "screener", "honeypot", "tripwire", "canary", "snitch", "tattle",
	"telemetry", "analytic", "analytics", "protect", "protection", "shield",
	"firewall", "overseer", "supervisor", "trust", "log", "logging",
}) do
	AC_TOKENS[w] = true
end

-- 强特征(允许子串命中,比如 anticheat2024 / anti_cheat_v3)
local AC_STRONG = {
	"anticheat", "detect", "report", "suspic", "exploit", "cheat", "hack",
	"punish", "violat", "integrity", "monitor", "audit", "watchdog", "warden",
	"sentinel", "honeypot", "tripwire", "canary", "snitch", "telemetry",
}

local function tokenize(s)
	s = tostring(s or "")
	s = string.gsub(s, "(%l)(%u)", "%1 %2")
	s = string.gsub(s, "(%a)(%d)", "%1 %2")
	local out = {}
	for w in string.gmatch(s, "%w+") do out[#out + 1] = string.lower(w) end
	return out
end

local function isACName(name, path)
	local hay = tostring(name or "") .. " " .. tostring(path or "")
	for _, w in ipairs(CFG.Whitelist) do
		if string.find(lower(hay), lower(w), 1, true) then return false, "白名单" end
	end
	local toks = tokenize(hay)
	for _, t in ipairs(toks) do
		if AC_TOKENS[t] then return true, t end
		for _, s in ipairs(AC_STRONG) do
			if string.find(t, s, 1, true) then return true, s end
		end
	end
	return false
end

--=====================================================================
-- 3. 运行状态
--=====================================================================
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local ReplicatedFirst    = game:GetService("ReplicatedFirst")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local StarterPlayer      = game:GetService("StarterPlayer")

local LP = Players.LocalPlayer

local ST = {
	OurDepth   = 0,
	Blocked    = 0,
	Washed     = 0,
	Recent     = {},
	RecentKeys = {},
	Kicked     = 0,
	SpawnCF    = nil,
	Conns      = {},
}

local function log(msg, tag)
	print(string.format("[ZakaAria] %s", msg))
	if ST.OnLog then pcall(ST.OnLog, msg, tag) end
end

--=====================================================================
-- 4. 出包记录(侦察核心)
--=====================================================================
local function argSummary(args, maxn)
	local out = {}
	local n = math.min(#args, maxn or 5)
	for i = 1, n do
		local v = args[i]
		local t = tn(v)
		if t == "Vector3" then
			out[#out + 1] = string.format("V3(%.0f,%.0f,%.0f)", v.X, v.Y, v.Z)
		elseif t == "CFrame" then
			local p = v.Position
			out[#out + 1] = string.format("CF(%.0f,%.0f,%.0f)", p.X, p.Y, p.Z)
		elseif t == "number" then
			out[#out + 1] = string.format("%.2f", v)
		elseif t == "string" then
			out[#out + 1] = '"' .. string.sub(v, 1, 14) .. '"'
		elseif t == "boolean" then
			out[#out + 1] = tostring(v)
		elseif t == "table" then
			out[#out + 1] = "table[" .. tostring(#v) .. "]"
		else
			out[#out + 1] = t
		end
	end
	if #args > n then out[#out + 1] = "..." end
	return table.concat(out, ", ")
end

local function remember(name, path, args, isAC, word)
	local key = tostring(name)
	if not ST.RecentKeys[key] then
		ST.RecentKeys[key] = true
		ST.Recent[#ST.Recent + 1] = {
			name = name, path = path, isAC = isAC, word = word,
			body = argSummary(args), count = 1,
		}
		if #ST.Recent > 120 then table.remove(ST.Recent, 1) end
	end
	if ST.OnRecord then pcall(ST.OnRecord) end
end

--=====================================================================
-- 5. 参数洗白(照发,但把内容洗干净)
--=====================================================================
local function cleanAnchor()
	local char = LP.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		ST.SpawnCF = root.CFrame
	end
	return ST.SpawnCF or CFrame.new(0, 0, 0)
end

local function washValue(v, depth)
	if depth > 4 then return v end
	local t = tn(v)

	if t == "Vector3" then
		-- 上报坐标一律换成"出生点附近",服务端看到你老老实实待着
		local p = cleanAnchor().Position
		return Vector3.new(p.X, p.Y, p.Z)

	elseif t == "CFrame" then
		return cleanAnchor()

	elseif t == "boolean" then
		-- 上报里的"是否作弊/是否异常"这类标记,统一洗成 false
		return false

	elseif t == "number" then
		if CFG.ClampNumbers then
			if v ~= v then return 0 end                       -- NaN
			if v == math.huge or v == -math.huge then return 0 end
			if math.abs(v) > CFG.ClampMax then
				return CFG.ClampMax * (v > 0 and 1 or -1)
			end
		end
		return v

	elseif t == "table" then
		local out = {}
		for k, vv in pairs(v) do
			out[k] = washValue(vv, depth + 1)
		end
		return out
	end

	return v
end

local function washArgs(args)
	local out = {}
	for i = 1, #args do
		out[i] = washValue(args[i], 1)
	end
	return out
end

--=====================================================================
-- 6. 核心:元表钩子
--=====================================================================
local function callerIsOurs()
	if ST.OurDepth > 0 then return true end
	if type(checkcaller_) == "function" then
		local ok, r = pcall(checkcaller_)
		if ok and type(r) == "boolean" then return r end
	end
	return false
end

local HOOKED = { Namecall = false, Index = false, NewIndex = false }
local SPI = { WalkSpeed = 16, JumpPower = 50, JumpHeight = 7.2, HipHeight = 2 }

local function hookAll()
	local mt = safe(getrawmetatable_, game)
	if not mt then
		log("本执行器拿不到 game 元表,拦截功能不可用(走扫描/禁用脚本兜底)")
		return
	end

	local oldNamecall = mt.__namecall
	local oldIndex    = mt.__index
	local oldNewIndex = mt.__newindex

	safe(setreadonly_, mt, false)

	-- ---------- __namecall:出包拦截 / 洗白 / Kick 拦截 ----------
	if type(oldNamecall) == "function" then
		mt.__namecall = newcclosure_(function(self, ...)
			local method = getnamecallmethod_()

			local isKick   = (method == "Kick")
			local isRemote = (method == "FireServer" or method == "InvokeServer"
				or method == "Fire" or method == "Invoke")

			-- 不相关的调用直接放行(不做 checkcaller,省性能)
			if not (isKick or isRemote) then
				return oldNamecall(self, ...)
			end

			if callerIsOurs() then
				return oldNamecall(self, ...)
			end

			-- Kick 拦截
			if isKick then
				if CFG.BlockKick and self == LP then
					ST.Kicked = ST.Kicked + 1
					log(string.format("已拦截 Kick(第 %d 次):%s",
						ST.Kicked, tostring((...))))
					return nil
				end
				return oldNamecall(self, ...)
			end

			-- Remote 出包
			local name = safe(function() return self.Name end) or "?"
			local path = safe(function() return self:GetFullName() end) or "?"
			local args = { ... }
			local ac, word = isACName(name, path)

			if ac then
				remember(name, path, args, true, word)

				if CFG.Recon then
					-- 侦察模式:只看不拦
					return oldNamecall(self, ...)
				end

				if CFG.BlockReport then
					ST.Blocked = ST.Blocked + 1
					log(string.format("已拦截上报包:%s  [%s]", name, tostring(word)))
					return nil
				end

				if CFG.WashReport then
					ST.Washed = ST.Washed + 1
					local washed = washArgs(args)
					ST.OurDepth = ST.OurDepth + 1
					local r1, r2 = oldNamecall(self, unpack(washed))
					ST.OurDepth = ST.OurDepth - 1
					return r1, r2
				end
			else
				remember(name, path, args, false, nil)
			end

			return oldNamecall(self, ...)
		end)
		HOOKED.Namecall = true
	end

	-- ---------- __index:属性读取伪装 ----------
	if type(oldIndex) == "function" then
		mt.__index = newcclosure_(function(self, key)
			local k = key
			if CFG.HookReadSpoof
				and (k == "WalkSpeed" or k == "JumpPower" or k == "JumpHeight" or k == "HipHeight") then
				if not callerIsOurs() then
					local ok, isHum = pcall(function() return self:IsA("Humanoid") end)
					if ok and isHum then
						return SPI[k]
					end
				end
			end
			return oldIndex(self, key)
		end)
		HOOKED.Index = true
	end

	-- ---------- __newindex:拦游戏脚本写你的属性 ----------
	if type(oldNewIndex) == "function" then
		mt.__newindex = newcclosure_(function(self, key, value)
			local k = key
			if CFG.BlockLocalWrite
				and (k == "WalkSpeed" or k == "JumpPower" or k == "HipHeight") then
				if not callerIsOurs() then
					local ok, isHum = pcall(function() return self:IsA("Humanoid") end)
					if ok and isHum and self.Parent == LP.Character then
						log(string.format("已拦下脚本改属性:%s = %s", tostring(k), tostring(value)))
						return nil
					end
				end
			end
			return oldNewIndex(self, key, value)
		end)
		HOOKED.NewIndex = true
	end

	safe(setreadonly_, mt, true)

	log(string.format("钩子就位 · namecall=%s index=%s newindex=%s checkcaller=%s",
		tostring(HOOKED.Namecall), tostring(HOOKED.Index),
		tostring(HOOKED.NewIndex), tostring(CAP.CheckCaller)))
end

--=====================================================================
-- 7. 客户端反作弊脚本扫描 / 禁用 / 断连接
--=====================================================================
local function collectScripts()
	local roots = {}
	local function add(r) if r then roots[#roots + 1] = r end end
	add(LP:FindFirstChild("PlayerScripts"))
	add(LP:FindFirstChild("PlayerGui"))
	add(LP:FindFirstChild("Backpack"))
	add(LP:FindFirstChild("PlayerScripts") and LP.PlayerScripts:FindFirstChild("PlayerModule"))
	add(ReplicatedFirst)
	add(ReplicatedStorage)
	add(StarterPlayer and StarterPlayer:FindFirstChild("StarterPlayerScripts"))
	add(StarterPlayer and StarterPlayer:FindFirstChild("StarterCharacterScripts"))

	local hits = {}
	for _, r in ipairs(roots) do
		local ok, desc = pcall(function() return r:GetDescendants() end)
		if ok and desc then
			for _, d in ipairs(desc) do
				local ok2, isS = pcall(function()
					return d:IsA("LocalScript") or d:IsA("Script") or d:IsA("ModuleScript")
				end)
				if ok2 and isS then
					local ac, w = isACName(d.Name, safe(function() return d:GetFullName() end))
					if ac then hits[#hits + 1] = { obj = d, word = w } end
				end
			end
		end
	end
	return hits
end

local function disableClientAC()
	local hits = collectScripts()
	local n = 0
	for _, h in ipairs(hits) do
		if attempt(function() h.obj.Disabled = true end) then
			n = n + 1
			log(string.format("已禁用客户端脚本:%s  [%s]",
				tostring(h.obj.Name), tostring(h.word)))
		end
	end
	log(string.format("扫描完成,命中 %d 个可疑脚本,已禁用 %d 个", #hits, n))
	return n, hits
end

local function killACConnections()
	if not CAP.Connections then
		log("本执行器不支持 getconnections,跳过连接清理")
		return 0
	end
	local sigs = {
		RunService.Heartbeat, RunService.Stepped, RunService.RenderStepped,
		LP.CharacterAdded, LP.CharacterRemoving,
	}
	local n = 0
	for _, sig in ipairs(sigs) do
		local conns = safe(getconnections, sig)
		if conns then
			for _, c in ipairs(conns) do
				local f = c.Function or (c.getfunction and safe(c.getfunction, c))
				local src = "?"
				if f and debug and debug.getinfo then
					local info = safe(debug.getinfo, f, "s")
					src = (info and info.source) or "?"
				end
				local ac = isACName(src, src)
				if ac and c.Disconnect then
					if attempt(c.Disconnect, c) then n = n + 1 end
				end
			end
		end
	end
	log(string.format("已断开 %d 条可疑心跳连接", n))
	return n
end

--=====================================================================
-- 8. 位移绕过(物理加速 / 无限跳,不碰 WalkSpeed)
--=====================================================================
local MOV = { att = nil, lv = nil }

local function stopSpeed()
	if MOV.lv then safe(function() MOV.lv:Destroy() end) end
	if MOV.att then safe(function() MOV.att:Destroy() end) end
	MOV.lv, MOV.att = nil, nil
end

local function startSpeed()
	stopSpeed()
	local char = LP.Character
	if not char then return false end
	local root = char:WaitForChild("HumanoidRootPart", 5)
	if not root then return false end

	local att = Instance.new("Attachment")
	att.Name = "ZakaVelAtt"
	att.Parent = root

	local lv = Instance.new("LinearVelocity")
	lv.Name = "ZakaVel"
	lv.Attachment0 = att
	lv.MaxForce = math.huge
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VectorVelocity = Vector3.zero
	lv.Parent = char

	MOV.att, MOV.lv = att, lv
	log("物理加速已挂载(Humanoid.WalkSpeed 保持默认,属性检测看不见)")
	return true
end

local function bindLoop()
	local conn = RunService.RenderStepped:Connect(function()
		-- 物理加速
		if CFG.SpeedBypass then
			if not MOV.lv then startSpeed() end
			local char = LP.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and MOV.lv then
				local md = hum.MoveDirection
				if md.Magnitude > 0.05 then
					MOV.lv.VectorVelocity = md * CFG.SpeedValue
				else
					MOV.lv.VectorVelocity = Vector3.zero
				end
			end
		end
	end)
	ST.Conns[#ST.Conns + 1] = conn

	-- 无限跳:走状态切换,不改 JumpPower
	local c2 = UserInputService.JumpRequest:Connect(function()
		if not CFG.InfiniteJump then return end
		local char = LP.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			safe(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
		end
	end)
	ST.Conns[#ST.Conns + 1] = c2

	-- 角色重生后重挂
	local c3 = LP.CharacterAdded:Connect(function()
		task.wait(1)
		stopSpeed()
		if CFG.SpeedBypass then startSpeed() end
	end)
	if ST.Conns and c3 then ST.Conns[#ST.Conns + 1] = c3 end
end

--=====================================================================
-- 9. UI(移动端友好:大字大按钮 + 滚动容器 + 悬浮球)
--=====================================================================
local UI = {}

local COL = {
	bg      = Color3.fromRGB(18, 20, 27),
	card    = Color3.fromRGB(28, 31, 40),
	line    = Color3.fromRGB(46, 50, 62),
	text    = Color3.fromRGB(232, 236, 245),
	dim     = Color3.fromRGB(150, 158, 175),
	on      = Color3.fromRGB(64, 196, 128),
	off     = Color3.fromRGB(70, 74, 88),
	accent  = Color3.fromRGB(120, 140, 255),
	warn    = Color3.fromRGB(255, 186, 74),
	danger  = Color3.fromRGB(255, 106, 118),
}

local function corner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = p
	return c
end

local function buildUI()
	local parent = nil
	if CAP.Gui then parent = safe(gethui) end
	if not parent then parent = safe(function() return game:GetService("CoreGui") end) end
	if not parent then parent = LP:WaitForChild("PlayerGui") end

	local gui = Instance.new("ScreenGui")
	gui.Name = "ZakaAriaBypass"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = parent
	UI.gui = gui

	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local W = math.min(340, vp.X - 20)
	local H = math.min(472, vp.Y - 40)

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.Size = UDim2.fromOffset(W, H)
	main.Position = UDim2.fromOffset(14, 60)
	main.BackgroundColor3 = COL.bg
	main.BorderSizePixel = 0
	main.Active = true
	main.Draggable = true
	main.Parent = gui
	corner(main, 12)
	UI.main = main

	local stroke = Instance.new("UIStroke")
	stroke.Color = COL.line
	stroke.Parent = main

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -86, 0, 44)
	title.Position = UDim2.fromOffset(12, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 15
	title.TextColor3 = COL.text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "ZakaAria 反作弊绕过 v1.0"
	title.Parent = main

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, -24, 0, 16)
	hint.Position = UDim2.fromOffset(12, 34)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 11
	hint.TextColor3 = COL.dim
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Text = CAP.MetaHook and "钩子可用" or "钩子不可用 · 走扫描兜底"
	hint.Text = hint.Text .. (CAP.CheckCaller and " · caller 判定 OK" or " · 缺 checkcaller")
	hint.Parent = main

	local min = Instance.new("TextButton")
	min.Size = UDim2.fromOffset(40, 40)
	min.Position = UDim2.new(1, -50, 0, 2)
	min.BackgroundColor3 = COL.card
	min.Text = "—"
	min.TextColor3 = COL.text
	min.Font = Enum.Font.GothamBold
	min.TextSize = 18
	min.Parent = main
	corner(min, 10)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -20, 1, -152)
	scroll.Position = UDim2.fromOffset(10, 58)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = COL.line
	scroll.CanvasSize = UDim2.new(0, 0, 0, 560)
	safe(function()
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	end)
	scroll.Parent = main

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = scroll

	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0, 7)
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = scroll

	local rowOrder = 0
	local function section(text)
		rowOrder = rowOrder + 1
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1, -8, 0, 20)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextSize = 12
		l.TextColor3 = COL.accent
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Text = text
		l.LayoutOrder = rowOrder
		l.Parent = scroll
		return l
	end

	local rows = {}
	local function toggle(key, text, onChanged)
		rowOrder = rowOrder + 1
		local row = Instance.new("TextButton")
		row.Size = UDim2.new(1, -8, 0, 42)
		row.BackgroundColor3 = COL.card
		row.BorderSizePixel = 0
		row.AutoButtonColor = false
		row.Text = ""
		row.LayoutOrder = rowOrder
		row.Parent = scroll
		corner(row, 9)

		local lab = Instance.new("TextLabel")
		lab.Size = UDim2.new(1, -76, 1, 0)
		lab.Position = UDim2.fromOffset(12, 0)
		lab.BackgroundTransparency = 1
		lab.Font = Enum.Font.GothamMedium
		lab.TextSize = 13
		lab.TextColor3 = COL.text
		lab.TextXAlignment = Enum.TextXAlignment.Left
		lab.Text = text
		lab.Parent = row

		local box = Instance.new("Frame")
		box.Size = UDim2.fromOffset(48, 26)
		box.Position = UDim2.new(1, -60, 0.5, -13)
		box.BackgroundColor3 = CFG[key] and COL.on or COL.off
		box.Parent = row
		corner(box, 13)

		local knob = Instance.new("Frame")
		knob.Size = UDim2.fromOffset(20, 20)
		knob.Position = CFG[key] and UDim2.fromOffset(25, 3) or UDim2.fromOffset(3, 3)
		knob.BackgroundColor3 = Color3.fromRGB(245, 247, 252)
		knob.Parent = box
		corner(knob, 10)

		local function render()
			box.BackgroundColor3 = CFG[key] and COL.on or COL.off
			knob.Position = CFG[key] and UDim2.fromOffset(25, 3) or UDim2.fromOffset(3, 3)
		end

		row.MouseButton1Click:Connect(function()
			CFG[key] = not CFG[key]
			render()
			saveCfg()
			if onChanged then pcall(onChanged, CFG[key]) end
		end)

		rows[key] = { render = render }
		return row
	end

	local function button(text, color, cb)
		rowOrder = rowOrder + 1
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, -8, 0, 42)
		b.BackgroundColor3 = color
		b.BorderSizePixel = 0
		b.Font = Enum.Font.GothamBold
		b.TextSize = 13
		b.TextColor3 = Color3.fromRGB(245, 247, 252)
		b.Text = text
		b.LayoutOrder = rowOrder
		b.Parent = scroll
		corner(b, 9)
		b.MouseButton1Click:Connect(function() pcall(cb) end)
		return b
	end

	section("① 侦察阶段(先开这个)")
	toggle("Recon", "侦察模式(只记录,不拦不洗)")

	section("② 拦截 / 洗白(二选一)")
	toggle("BlockReport", "拦截上报包(直接不发)", function(v)
		if v then CFG.WashReport = false; if rows.WashReport then rows.WashReport.render() end end
	end)
	toggle("WashReport", "参数洗白(照发,内容洗干净)", function(v)
		if v then CFG.BlockReport = false; if rows.BlockReport then rows.BlockReport.render() end end
	end)
	toggle("BlockKick", "拦截客户端 Kick")

	section("③ 客户端反作弊(直捣脚本)")
	toggle("DisableClientAC", "禁用反作弊 LocalScript", function(v)
		if v then disableClientAC() end
	end)
	toggle("KillACConnects", "断开反作弊心跳连接(激进)", function(v)
		if v then killACConnections() end
	end)
	toggle("HookReadSpoof", "属性读取伪装(WalkSpeed 报正常值)")
	toggle("BlockLocalWrite", "拦游戏脚本改我的属性")

	section("④ 位移(不碰 WalkSpeed)")
	toggle("SpeedBypass", "物理加速", function(v)
		if v then startSpeed() else stopSpeed() end
	end)
	toggle("InfiniteJump", "无限跳(状态切换)")

	section("⑤ 操作")
	button("🔍 扫描反作弊脚本(只列出)", COL.accent, function()
		local hits = collectScripts()
		log(string.format("扫描完成,命中 %d 个可疑脚本", #hits))
		for i = 1, math.min(#hits, 12) do
			log(string.format("  · %s  [%s]", hits[i].obj.Name, tostring(hits[i].word)))
		end
	end)
	button("📋 复制出包记录", COL.card, function()
		local lines = {}
		for _, r in ipairs(ST.Recent) do
			lines[#lines + 1] = string.format("%s%s  →  %s",
				r.isAC and "[AC] " or "", r.name, r.body)
		end
		local txt = table.concat(lines, "\n")
		if setclipboard then
			safe(setclipboard, txt)
			log("出包记录已复制到剪贴板,直接发我")
		else
			log("本执行器没有剪贴板接口,看面板下方记录")
		end
	end)

	-- 状态条
	local status = Instance.new("TextLabel")
	status.Size = UDim2.new(1, -20, 0, 52)
	status.Position = UDim2.new(0, 10, 1, -62)
	status.BackgroundColor3 = COL.card
	status.BorderSizePixel = 0
	status.Font = Enum.Font.Code
	status.TextSize = 11
	status.TextColor3 = COL.dim
	status.TextWrapped = true
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextYAlignment = Enum.TextYAlignment.Top
	status.Text = "就绪"
	status.Parent = main
	corner(status, 9)

	local spad = Instance.new("UIPadding")
	spad.PaddingTop = UDim.new(0, 5)
	spad.PaddingLeft = UDim.new(0, 7)
	spad.PaddingRight = UDim.new(0, 7)
	spad.Parent = status

	local LINES = {}
	ST.OnLog = function(msg, tag)
		LINES[#LINES + 1] = string.format("[%s] %s",
			os.date("%H:%M:%S"), tostring(msg))
		while #LINES > 6 do table.remove(LINES, 1) end
		status.TextColor3 = (tag == "KICK" or tag == "AC") and COL.warn or COL.dim
		status.Text = table.concat(LINES, "\n")
	end
	ST.OnRecord = function()
		status.Text = table.concat(LINES, "\n")
	end

	min.MouseButton1Click:Connect(function()
		main.Visible = false
		if UI.ball then UI.ball.Visible = true end
	end)

	-- 悬浮球(手机上没有 RightShift,靠它开关)
	local ball = Instance.new("TextButton")
	ball.Name = "Ball"
	ball.Size = UDim2.fromOffset(52, 52)
	ball.Position = UDim2.new(1, -70, 0, 110)
	ball.BackgroundColor3 = COL.accent
	ball.Text = "Z"
	ball.Font = Enum.Font.GothamBold
	ball.TextSize = 20
	ball.TextColor3 = Color3.fromRGB(255, 255, 255)
	ball.Visible = false
	ball.Parent = gui
	corner(ball, 26)
	UI.ball = ball

	local dragging, dragStart, startPos, pressAt
	ball.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			pressAt = tick()
			dragStart = input.Position
			startPos = ball.Position
		end
	end)
	ball.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			ball.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
	ball.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			local held = tick() - (pressAt or tick())
			dragging = false
			if held > 0.45 then
				-- 长按:收起/展开面板
				main.Visible = not main.Visible
				ball.Visible = not main.Visible
			else
				-- 短按:一键在"拦截"和"侦察"之间切
				CFG.Recon = not CFG.Recon
				if rows.Recon then rows.Recon.render() end
				saveCfg()
				log(CFG.Recon and "已切到侦察模式" or "已切到拦截模式")
			end
		end
	end)

	log("面板就绪 · 先跑侦察模式看包名")
end

--=====================================================================
-- 10. 启动
--=====================================================================
hookAll()
bindLoop()
buildUI()

genv.ZAKA_ARIA_DESTROY = function()
	for _, c in ipairs(ST.Conns) do safe(function() c:Disconnect() end) end
	stopSpeed()
	if UI.gui then safe(function() UI.gui:Destroy() end) end
	log("已卸载")
end

log("ZakaAriaBypass v1.0 已加载")
