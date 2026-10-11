--[[
================================================================================
  ZakaAria Bypass  v2.1      ·      「命令总线」版
--------------------------------------------------------------------------------
  定位:针对「单通道 + 命令字符串分发」架构的 Remote 反作弊绕过
  适用:圣奥里 及同结构游戏(Event / PlayerEvent / PlayerFunc / UnreliableEvent
        这类通用名通道,第一个参数是命令串)

  v2.1 相对 v1.0 改了什么(基于实测出包记录):
    1) 修日志截断 bug  —— 原来字符串砍到 14 字符,命令串全看不全,现在记 48 字符
    2) 新增「命令表」   —— 识别出命令总线架构后,按 (通道, 命令串) 归集,
                           每条可 重放 / 克隆到目标 / 设为攻击命令
    3) AC 判定换脑子   —— 从"只看通道名"升级为"通道名 + 命令串 + 参数内容"
                           三维打分;analytics / tracking 类降级为 [?] 待观察,
                           不再像 v1 那样把 ReportGoogleAnalyticsEvent 误标 [AC]
    4) 新增「注入页」   —— 直接手搓一条包(选通道 + 填命令串 + 填参数 JSON)发出去
    5) 光环接回命令表   —— 命令表里把某条命令标成"攻击命令",光环循环就按它出包
    6) 补三个真会翻车的坑:
         · RemoteFunction 绝不拦截(拦了调用方永久 yield,游戏直接卡死)
         · UnreliableEvent "charRot" 旋转静默(朝向异常是最常见的上报项之一)
         · 触摸事件污染学习池(手机上拖屏幕会灌垃圾,不再泛打点)

  正确用法:
    1) 执行 -> 左上角面板,右侧悬浮球
    2) 保持【侦察模式】,正常玩 1~2 分钟(记得挥几刀,把攻击命令喂进来)
    3) 翻「命令表」页,看带 [AC] / [?] 的命令串,以及哪条是攻击命令
    4) 确认了再关侦察 -> 开「拦截上报包」或「参数洗白」(二选一,面板里互斥锁死)
    5) 把命令表复制发回来,我按实际命令串再精调
================================================================================
]]

--=====================================================================
-- 0. 兼容层
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

local function trim(s)
	s = tostring(s or "")
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local getrawmetatable_   = getrawmetatable or getmetatable
local setreadonly_       = setreadonly or function() end
local newcclosure_       = newcclosure or function(f) return f end
local getnamecallmethod_ = getnamecallmethod or function() return "" end
local checkcaller_       = checkcaller
local hookmetamethod_    = hookmetamethod

local CAP = {
	MetaHook    = type(getrawmetatable) == "function",
	CheckCaller = type(checkcaller) == "function",
	HookMethod  = type(hookmetamethod) == "function",
	Connections = type(getconnections) == "function",
	FileWrite   = type(writefile) == "function",
	Gui         = type(gethui) == "function",
	Clipboard   = type(setclipboard) == "function",
	IsA         = type(isa) == "function",
}

local VER = "v2.1"

--=====================================================================
-- 1. 配置
--=====================================================================
local CFG = {
	Recon            = true,     -- 侦察模式:只记录,不拦不洗(默认开)
	BlockKick        = true,     -- 拦截客户端 Kick
	BlockReport      = false,    -- 拦截上报包(直接不发)
	WashReport       = false,    -- 参数洗白(推荐:照发,内容洗干净)
	ScrubCmds        = false,    -- 按命令串洗白(命令总线架构下这条才是主力)
	SilenceCharRot   = false,    -- 旋转静默:charRot 上报一律喂正常值
	ProtectRemoteFn  = true,     -- RemoteFunction 永不拦截(防游戏卡死,强烈建议常开)
	FlagAnalytics    = false,    -- 把 analytics/tracking 通道也当 AC 处理
	DisableClientAC  = false,    -- 禁用客户端反作弊脚本
	KillACConnects   = false,    -- 断开反作弊脚本挂的心跳连接(激进)
	HookReadSpoof    = false,    -- 属性读取伪装(AC 读 WalkSpeed 时看到正常值)
	BlockLocalWrite  = false,    -- 拦游戏脚本改你的属性(防被冻/被锁)
	SpeedBypass      = false,    -- 物理加速(不改 WalkSpeed,绕开属性检测)
	SpeedValue       = 45,       -- 物理加速速度
	InfiniteJump     = false,    -- 无限跳
	ClampNumbers     = true,     -- 洗白时把异常数值钳回正常范围
	ClampMax         = 60,       -- 数值钳制上限
	AuraOn           = false,    -- 光环总开关
	AuraRange        = 40,       -- 光环半径
	AuraInterval     = 0.14,     -- 出包间隔(被踢就调到 0.18~0.22)
	AuraTargetsAll   = false,    -- 光环目标是全部还是最近一个
	Whitelist        = {},       -- 通道名白名单(v1 兼容)
	ScrubList        = { "detect", "flag", "report", "cheat", "suspic", "kick", "ban" },
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
	CFG.AuraOn = false
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
-- 2. 反作弊特征库(v2:三维打分)
--=====================================================================
-- 通道名 · 强特征:命中即 [AC]
local CHAN_HARD = {
	"anticheat", "anti_cheat", "anti-cheat", "cheatdetect", "exploitdetect",
	"speedhack", "noclip", "flydetect", "banlog", "kicklog", "flagplayer",
	"reportplayer", "suspicious", "sanitycheck", "honeypot", "tripwire",
	"watchdog", "warden", "sentinel", "guardian", "firewall", "overseer",
}

-- 通道名 · 弱特征:命中只是 [?] 待观察(analytics / 日志类大多落这里)
local CHAN_SOFT = {
	"report", "logging", "audit", "monitor", "analytic", "telemetry",
	"track", "verify", "validate", "security", "trust",
}

-- 命令串 · 强特征:命中即 [AC]
local CMD_HARD = {
	"detect", "flag", "suspic", "report", "cheat", "exploit", "hack",
	"violat", "integrity", "kick", "unban", "ban_player", "punish",
	"noclip", "flyhack", "speedhack", "godmode", "physics_check",
	"position_check", "poscheck", "teleport_check",
}

-- 命令串 · 弱特征:命中是 [?]
local CMD_SOFT = {
	"check", "verify", "validate", "audit", "monitor", "sanit",
	"scan", "clamp", "correct",
}

-- 命令串 · 观察名单:名字本身不敏感,但在这类游戏里值得盯一眼
local CMD_WATCH = {
	charrot = "朝向上报(常见的旋转校验/同步项)",
	rot = "朝向上报",
	pos = "位置上报",
	position = "位置上报",
	speed = "速度上报",
	velocity = "速度上报",
	teleport = "传送上报",
	stamina = "体力(客户端上报 = 服务端信你)",
}

local AC_TOKENS = {}
for _, w in ipairs({
	"ac", "anticheat", "detect", "detection", "detector", "detected",
	"report", "reported", "reporter", "flag", "flagged", "flagging",
	"suspicious", "suspicion", "suspect", "exploit", "exploiter",
	"cheat", "cheater", "cheating", "hack", "hacker", "hacking",
	"ban", "banned", "kick", "kicked", "punish", "punishment",
	"violation", "integrity", "verify", "verification", "validate",
	"monitor", "monitoring", "audit", "security", "guard", "guardian",
	"watchdog", "warden", "sentinel", "sentry", "patrol", "inspect",
	"scanner", "honeypot", "tripwire", "canary", "telemetry",
	"analytic", "analytics", "protect", "shield", "firewall",
	"overseer", "supervisor", "trust", "log", "logging",
}) do
	AC_TOKENS[w] = true
end

local function tokenize(s)
	s = tostring(s or "")
	s = string.gsub(s, "(%l)(%u)", "%1 %2")
	s = string.gsub(s, "(%a)(%d)", "%1 %2")
	local out = {}
	for w in string.gmatch(s, "%w+") do out[#out + 1] = string.lower(w) end
	return out
end

local function hitAny(hay, list)
	hay = lower(hay)
	for _, w in ipairs(list) do
		if string.find(hay, lower(w), 1, true) then return w end
	end
	return nil
end

-- 三维判定:level 2 = [AC],level 1 = [?],level 0 = 正常
-- 返回 level, 命中词, 说明
local function judge(chanName, chanPath, cmd)
	local hay = tostring(chanName or "") .. " " .. tostring(chanPath or "")

	-- 白名单优先(按通道名)
	for _, w in ipairs(CFG.Whitelist) do
		if string.find(lower(hay), lower(w), 1, true) then
			return 0, nil, "白名单"
		end
	end

	local h = hitAny(hay, CHAN_HARD)
	if h then return 2, h, "通道名强特征" end

	local c = nil
	local note = nil
	if cmd and cmd ~= "" then
		c = hitAny(cmd, CMD_HARD)
		if c then return 2, c, "命令串强特征" end
	end

	local sh = hitAny(hay, CHAN_SOFT)
	if sh then
		local lvl = CFG.FlagAnalytics and 2 or 1
		return lvl, sh, "通道名弱特征(analytics/日志类)"
	end

	if cmd and cmd ~= "" then
		local sc = hitAny(cmd, CMD_SOFT)
		if sc then return 1, sc, "命令串弱特征" end
		local wk = CMD_WATCH[lower(cmd)]
		if wk then return 1, cmd, wk end
	end

	return 0, nil, nil
end

-- v1 兼容:脚本扫描用的纯名字判定
local function isACName(name, path)
	local hay = tostring(name or "") .. " " .. tostring(path or "")
	for _, w in ipairs(CFG.Whitelist) do
		if string.find(lower(hay), lower(w), 1, true) then return false, "白名单" end
	end
	local toks = tokenize(hay)
	for _, t in ipairs(toks) do
		if AC_TOKENS[t] then return true, t end
		local h = hitAny(t, CHAN_HARD)
		if h then return true, h end
	end
	return false
end

--=====================================================================
-- 3. 运行状态
--=====================================================================
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedFirst   = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer     = game:GetService("StarterPlayer")

local LP = Players.LocalPlayer

local ST = {
	OurDepth   = 0,
	Blocked    = 0,
	Washed     = 0,
	Saved      = 0,
	Recent     = {},
	RecentKeys = {},
	Cmds       = {},
	CmdOrder   = {},
	Kicked     = 0,
	SpawnCF    = nil,
	Conns      = {},
	AuraRun    = false,
	AttackCmd  = nil,   -- { chan=, cmd=, remote=, method=, args= }
	LastRot    = Vector2.new(0, 0),
	SendDepth  = 0,
}

local function log(msg, tag)
	print(string.format("[ZakaAria %s] %s", VER, msg))
	if ST.OnLog then pcall(ST.OnLog, msg, tag) end
end

-- 通道全名(短)
local function chanLabel(remote)
	local ok, cls = pcall(function() return remote.ClassName end)
	local ok2, nm = pcall(function() return remote.Name end)
	return string.format("%s(%s)", tostring(nm or "?"), tostring(cls or "?"))
end

--=====================================================================
-- 4. 出包记录
--=====================================================================
local STR_MAX = 48   -- v1 是 14,命令串全被砍断,这里放宽

local function fmtVal(v)
	local t = tn(v)
	if t == "Vector3" then
		return string.format("V3(%.0f,%.0f,%.0f)", v.X, v.Y, v.Z)
	elseif t == "Vector2" then
		return string.format("V2(%.0f,%.0f)", v.X, v.Y)
	elseif t == "CFrame" then
		local p = v.Position
		return string.format("CF(%.0f,%.0f,%.0f)", p.X, p.Y, p.Z)
	elseif t == "number" then
		return string.format("%.2f", v)
	elseif t == "string" then
		local s = v
		if #s > STR_MAX then
			return '"' .. string.sub(s, 1, STR_MAX) .. '"(+' .. tostring(#s - STR_MAX) .. ')'
		end
		return '"' .. s .. '"'
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "table" then
		return "table[" .. tostring(#v) .. "]"
	elseif t == "nil" then
		return "nil"
	end
	return t
end

local function argSummary(args, maxn)
	local total = args.n or #args        -- table.pack 的 n 才算数(中间可能是 nil)
	local out = {}
	local n = math.min(total, maxn or 6)
	for i = 1, n do
		out[#out + 1] = fmtVal(args[i])
	end
	if total > n then out[#out + 1] = "..." end
	return table.concat(out, ", ")
end

local function remember(chan, path, cmd, args, level, word, note)
	local line = argSummary(args)

	local rkey = tostring(chan) .. "|" .. tostring(cmd or "(无命令串)")
	local rec = ST.Cmds[rkey]
	if not rec then
		rec = {
			chan = chan, cmd = cmd, path = path,
			level = level, word = word, note = note,
			body = line, count = 0, last = nil,
		}
		ST.Cmds[rkey] = rec
		ST.CmdOrder[#ST.CmdOrder + 1] = rkey
		log(string.format("新命令: %s  →  %s%s",
			chan,
			cmd and ('"' .. cmd .. '"') or "(无命令串)",
			level == 2 and "   [AC]" or (level == 1 and "   [?]" or "")))
	else
		-- 后续出现更高级别判定时升级
		if level > rec.level then
			rec.level = level
			rec.word = word
			rec.note = note
		end
	end
	rec.count = rec.count + 1
	rec.body = line

	if not ST.RecentKeys[rkey] then
		ST.RecentKeys[rkey] = true
		ST.Recent[#ST.Recent + 1] = rec
		if #ST.Recent > 300 then table.remove(ST.Recent, 1) end
	end

	if ST.OnRecord then pcall(ST.OnRecord, rec) end
end

--=====================================================================
-- 5. 参数洗白
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

	elseif t == "Vector2" then
		return Vector2.new(0, 0)

	elseif t == "CFrame" then
		return cleanAnchor()

	elseif t == "boolean" then
		-- "是否作弊/是否异常"这类标记,统一洗成 false
		return false

	elseif t == "number" then
		if CFG.ClampNumbers then
			if v ~= v then return 0 end
			if v == math.huge or v == -math.huge then return 0 end
			if math.abs(v) > CFG.ClampMax then
				return CFG.ClampMax * (v > 0 and 1 or -1)
			end
		end
		return v

	elseif t == "table" then
		local out = {}
		for k, vv in pairs(v) do out[k] = washValue(vv, depth + 1) end
		return out
	end

	return v
end

local function washArgs(args)
	local total = args.n or #args
	local out = {}
	for i = 1, total do out[i] = washValue(args[i], 1) end
	out.n = total
	return out
end

-- 命令串是否在洗白名单里(命令总线架构下,这才是真正生效的开关)
local function cmdNeedsScrub(cmd)
	if not cmd or cmd == "" then return false end
	return hitAny(cmd, CFG.ScrubList) ~= nil
end

--=====================================================================
-- 6. 光环:参数重定向(把包里的"自己"换成目标)
--=====================================================================
local function pickTarget()
	local myChar = LP.Character
	if not myChar then return nil end
	local myRoot = myChar:FindFirstChild("HumanoidRootPart")
	if not myRoot then return nil end

	local best, bestD = nil, math.huge
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LP then
			local c = p.Character
			local h = c and c:FindFirstChildOfClass("Humanoid")
			local r = c and c:FindFirstChild("HumanoidRootPart")
			if h and r and h.Health > 0 then
				local d = (r.Position - myRoot.Position).Magnitude
				if d <= CFG.AuraRange and d < bestD then
					bestD = d
					best = { plr = p, char = c, hum = h, root = r }
				end
			end
		end
	end
	return best
end

local function retarget(v, t, depth)
	depth = depth or 1
	if depth > 5 or not t then return v end
	local k = tn(v)

	if k == "Instance" then
		local myChar = LP.Character
		if myChar and v == myChar then return t.char end
		if v == LP then return t.plr end
		if myChar and v:IsDescendantOf(myChar) then
			local alt = t.char:FindFirstChild(v.Name, true)
			if alt then return alt end
		end
		return v

	elseif k == "Vector3" then
		local myChar = LP.Character
		local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
		if myRoot and t.root then
			return v + (t.root.Position - myRoot.Position)
		end
		return v

	elseif k == "CFrame" then
		local myChar = LP.Character
		local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
		if myRoot and t.root then
			return t.root.CFrame * (myRoot.CFrame:Inverse() * v)
		end
		return v

	elseif k == "table" then
		local out = {}
		for kk, vv in pairs(v) do out[kk] = retarget(vv, t, depth + 1) end
		return out
	end

	return v
end

-- 低层发包(统一入口,带防回环 + 防 checkcaller 误判)
local function fire(remote, method, args)
	if not remote then return false end
	local n = args.n or #args
	ST.OurDepth = ST.OurDepth + 1
	ST.SendDepth = ST.SendDepth + 1
	local ok = attempt(function()
		if method == "InvokeServer" then
			if n > 0 then return remote:InvokeServer(unpack(args, 1, n)) end
			return remote:InvokeServer()
		else
			if n > 0 then return remote:FireServer(unpack(args, 1, n)) end
			return remote:FireServer()
		end
	end)
	ST.SendDepth = ST.SendDepth - 1
	ST.OurDepth = ST.OurDepth - 1
	return ok
end

-- 按模式发出一份记录
-- mode: "raw"(原样) / "retarget"(换目标) / "empty"(空参) / "cmdonly"(只发命令串)
local function dispatch(rec, mode, target)
	if not rec or not rec.remote then return false end
	local tgt = target
	if mode == "retarget" and not tgt then tgt = pickTarget() end
	if mode == "retarget" and not tgt then return false end

	local base = rec.last
	if not base or not base.args then return false end

	local total = base.args.n or #base.args
	local out = { n = total }
	if mode == "empty" then
		out = { n = 0 }
	elseif mode == "cmdonly" then
		if rec.cmd then out = { rec.cmd, n = 1 } end
	elseif mode == "retarget" then
		for i = 1, total do
			out[i] = retarget(base.args[i], tgt, 1)
		end
	else
		for i = 1, total do out[i] = base.args[i] end
	end

	return fire(rec.remote, base.method, out)
end

--=====================================================================
-- 7. 元表钩子(核心)
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

	-- ---------- __namecall ----------
	if type(oldNamecall) == "function" then
		mt.__namecall = newcclosure_(function(self, ...)
			local method = getnamecallmethod_()

			local isKick   = (method == "Kick")
			local isRemote = (method == "FireServer" or method == "InvokeServer"
				or method == "Fire" or method == "Invoke")

			if not (isKick or isRemote) then
				return oldNamecall(self, ...)
			end

			-- 自己发的包:直接放行,不记录不拦(防回环 + 防 checkcaller 误判)
			if ST.SendDepth > 0 or callerIsOurs() then
				return oldNamecall(self, ...)
			end

			-- Kick 拦截
			if isKick then
				if CFG.BlockKick and self == LP then
					ST.Kicked = ST.Kicked + 1
					log(string.format("已拦截 Kick(第 %d 次):%s",
						ST.Kicked, tostring((...))), "KICK")
					return nil
				end
				return oldNamecall(self, ...)
			end

			-- Remote 出包
			local chan = safe(function() return self.Name end) or "?"
			local path = safe(function() return self:GetFullName() end) or "?"
			local isFn = false
			safe(function() isFn = self:IsA("RemoteFunction") end)

			local args = table.pack(...)
			local cmd = (type(args[1]) == "string") and args[1] or nil
			local level, word, note = judge(chan, path, cmd)

			remember(chan, path, cmd, args, level, word, note)

			-- 把这条记录的"模板"补全(供重放/光环用)
			local key = tostring(chan) .. "|" .. tostring(cmd or "(无命令串)")
			local live = ST.Cmds[key]
			if live then
				live.remote = self
				live.last = { args = args, method = method, remote = self }
			end

			-- RemoteFunction 保护:拦了会让调用方永久 yield,游戏直接卡死
			if isFn and CFG.ProtectRemoteFn then
				return oldNamecall(self, ...)
			end

			-- 旋转静默:charRot 这类朝向上报一律喂正常值
			if CFG.SilenceCharRot and cmd and lower(cmd) == "charrot" then
				local char = LP.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				local yaw = 0
				if root then
					local _, y = root.CFrame:ToEulerAnglesYXZ()
					yaw = y
				end
				ST.Saved = ST.Saved + 1
				local total = args.n or #args
				local rest = { n = total - 1 }
				for i = 2, total do rest[i - 1] = washValue(args[i], 1) end
				ST.OurDepth = ST.OurDepth + 1
				ST.SendDepth = ST.SendDepth + 1
				local r1, r2
				attempt(function()
					if total > 1 then
						r1, r2 = oldNamecall(self, cmd, Vector2.new(yaw, 0),
							unpack(rest, 1, total - 1))
					else
						r1, r2 = oldNamecall(self, cmd, Vector2.new(yaw, 0))
					end
				end)
				ST.SendDepth = ST.SendDepth - 1
				ST.OurDepth = ST.OurDepth - 1
				return r1, r2
			end

			if CFG.Recon then
				return oldNamecall(self, ...)
			end

			-- 拦截(RemoteFunction 已在上面放行,这里只会是 RemoteEvent)
			if CFG.BlockReport and level >= 1 then
				ST.Blocked = ST.Blocked + 1
				log(string.format("已拦截: %s → %s  [%s]",
					chan, cmd and ('"' .. cmd .. '"') or "-", tostring(word or "?")), "AC")
				return nil
			end

			-- 洗白:通道名命中 或 命令串命中
			local needWash = (level >= 1 and CFG.WashReport)
				or (CFG.ScrubCmds and cmdNeedsScrub(cmd))
			if needWash then
				ST.Washed = ST.Washed + 1
				local washed = washArgs(args)
				ST.OurDepth = ST.OurDepth + 1
				ST.SendDepth = ST.SendDepth + 1
				local r1, r2
				attempt(function()
					local n = washed.n or #washed
					if n > 0 then
						r1, r2 = oldNamecall(self, unpack(washed, 1, n))
					else
						r1, r2 = oldNamecall(self)
					end
				end)
				ST.SendDepth = ST.SendDepth - 1
				ST.OurDepth = ST.OurDepth - 1
				log(string.format("已洗白: %s → %s", chan,
					cmd and ('"' .. cmd .. '"') or "-"))
				return r1, r2
			end

			return oldNamecall(self, ...)
		end)
		HOOKED.Namecall = true
	end

	-- ---------- __index:属性读取伪装 ----------
	if type(oldIndex) == "function" then
		mt.__index = newcclosure_(function(self, key)
			if CFG.HookReadSpoof and not callerIsOurs()
				and (key == "WalkSpeed" or key == "JumpPower"
					or key == "JumpHeight" or key == "HipHeight") then
				local ok, isHum = pcall(function() return self:IsA("Humanoid") end)
				if ok and isHum then return SPI[key] end
			end
			return oldIndex(self, key)
		end)
		HOOKED.Index = true
	end

	-- ---------- __newindex:拦游戏脚本改你的属性 ----------
	if type(oldNewIndex) == "function" then
		mt.__newindex = newcclosure_(function(self, key, value)
			if CFG.BlockLocalWrite and not callerIsOurs()
				and (key == "WalkSpeed" or key == "JumpPower" or key == "HipHeight") then
				local ok, isHum = pcall(function() return self:IsA("Humanoid") end)
				if ok and isHum and self.Parent == LP.Character then
					log(string.format("已拦下脚本改属性:%s = %s",
						tostring(key), tostring(value)), "AC")
					return nil
				end
			end
			return oldNewIndex(self, key, value)
		end)
		HOOKED.NewIndex = true
	end

	safe(setreadonly_, mt, true)

	log(string.format("钩子就位 · namecall=%s index=%s newindex=%s caller=%s",
		tostring(HOOKED.Namecall), tostring(HOOKED.Index),
		tostring(HOOKED.NewIndex),
		CAP.CheckCaller and "OK" or "缺 checkcaller"))
end

--=====================================================================
-- 8. 客户端反作弊脚本扫描 / 禁用 / 断连接
--=====================================================================
local function collectScripts()
	local roots = {}
	local function add(r) if r then roots[#roots + 1] = r end end
	add(LP:FindFirstChild("PlayerScripts"))
	add(LP:FindFirstChild("PlayerGui"))
	add(LP:FindFirstChild("Backpack"))
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
				if ac and c.Disconnect and attempt(c.Disconnect, c) then
					n = n + 1
				end
			end
		end
	end
	log(string.format("已断开 %d 条可疑心跳连接", n))
	return n
end

--=====================================================================
-- 9. 位移绕过
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

--=====================================================================
-- 10. 光环循环
--=====================================================================
local function startAura()
	if ST.AuraRun then return end
	ST.AuraRun = true
	task.spawn(function()
		while ST.AuraRun do
			if CFG.AuraOn and ST.AttackCmd and not CFG.Recon then
				local rec = ST.AttackCmd
				if CFG.AuraTargetsAll then
					for _, p in ipairs(Players:GetPlayers()) do
						if p ~= LP then
							local c = p.Character
							local h = c and c:FindFirstChildOfClass("Humanoid")
							local r = c and c:FindFirstChild("HumanoidRootPart")
							local myRoot = LP.Character
								and LP.Character:FindFirstChild("HumanoidRootPart")
							if h and r and h.Health > 0 and myRoot
								and (r.Position - myRoot.Position).Magnitude <= CFG.AuraRange then
								dispatch(rec, "retarget",
									{ plr = p, char = c, hum = h, root = r })
							end
						end
					end
					task.wait(CFG.AuraInterval)
				else
					local t = pickTarget()
					if t then
						dispatch(rec, "retarget", t)
						task.wait(CFG.AuraInterval)
					else
						task.wait(0.2)
					end
				end
			else
				task.wait(0.2)
			end
		end
	end)
end

local function stopAura()
	ST.AuraRun = false
	CFG.AuraOn = false
end

--=====================================================================
-- 11. 位移循环
--=====================================================================
local function bindLoop()
	local conn = RunService.RenderStepped:Connect(function()
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

	local c2 = UserInputService.JumpRequest:Connect(function()
		if not CFG.InfiniteJump then return end
		local char = LP.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			safe(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
		end
	end)
	ST.Conns[#ST.Conns + 1] = c2

	local c3 = LP.CharacterAdded:Connect(function()
		task.wait(1)
		stopSpeed()
		if CFG.SpeedBypass then startSpeed() end
	end)
	ST.Conns[#ST.Conns + 1] = c3
end

--=====================================================================
-- 12. UI
--=====================================================================
local UI = {}
local COL = {
	bg     = Color3.fromRGB(18, 20, 27),
	card   = Color3.fromRGB(30, 33, 43),
	card2  = Color3.fromRGB(24, 27, 35),
	line   = Color3.fromRGB(46, 50, 62),
	text   = Color3.fromRGB(232, 236, 245),
	dim    = Color3.fromRGB(150, 158, 175),
	on     = Color3.fromRGB(64, 196, 128),
	off    = Color3.fromRGB(70, 74, 88),
	accent = Color3.fromRGB(120, 140, 255),
	warn   = Color3.fromRGB(255, 186, 74),
	danger = Color3.fromRGB(255, 106, 118),
}

local function corner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = p
	return c
end

local function mkLabel(parent, order, text, color, size, h)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -8, 0, h or 20)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = size or 12
	l.TextColor3 = color or COL.accent
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.LayoutOrder = order
	l.Parent = parent
	return l
end

local function mkNote(parent, order, text, h)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -8, 0, h or 30)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Gotham
	l.TextSize = 11
	l.TextColor3 = COL.dim
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.Text = text
	l.LayoutOrder = order
	l.Parent = parent
	return l
end

local function mkToggle(parent, order, key, text, onChanged)
	local row = Instance.new("TextButton")
	row.Size = UDim2.new(1, -8, 0, 42)
	row.BackgroundColor3 = COL.card
	row.BorderSizePixel = 0
	row.AutoButtonColor = false
	row.Text = ""
	row.LayoutOrder = order
	row.Parent = parent
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
	knob.BackgroundColor3 = Color3.fromRGB(245, 247, 252)
	knob.Parent = box
	corner(knob, 10)

	local function render()
		box.BackgroundColor3 = CFG[key] and COL.on or COL.off
		knob.Position = CFG[key] and UDim2.fromOffset(25, 3) or UDim2.fromOffset(3, 3)
	end
	render()
	UI.rows = UI.rows or {}
	UI.rows[key] = { render = render }

	row.MouseButton1Click:Connect(function()
		CFG[key] = not CFG[key]
		render()
		saveCfg()
		if onChanged then pcall(onChanged, CFG[key]) end
	end)
	return row
end

local function mkButton(parent, order, text, color, cb)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -8, 0, 42)
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.TextColor3 = Color3.fromRGB(245, 247, 252)
	b.TextWrapped = true
	b.Text = text
	b.LayoutOrder = order
	b.Parent = parent
	corner(b, 9)
	b.MouseButton1Click:Connect(function() pcall(cb, b) end)
	return b
end

local function mkSmallButton(parent, order, text, color, cb, w)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, w or 84, 0, 34)
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 11
	b.TextColor3 = Color3.fromRGB(245, 247, 252)
	b.Text = text
	b.LayoutOrder = order
	b.Parent = parent
	corner(b, 8)
	b.MouseButton1Click:Connect(function() pcall(cb, b) end)
	return b
end

local function mkBox(parent, order, placeholder, text, h)
	local t = Instance.new("TextBox")
	t.Size = UDim2.new(1, -8, 0, h or 40)
	t.BackgroundColor3 = COL.card2
	t.BorderSizePixel = 0
	t.Font = Enum.Font.Code
	t.TextSize = 13
	t.TextColor3 = COL.text
	t.PlaceholderText = placeholder
	t.PlaceholderColor3 = COL.dim
	t.Text = text or ""
	t.ClearTextOnFocus = false
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.LayoutOrder = order
	t.Parent = parent
	corner(t, 8)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = t
	return t
end

local function newPage(title)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = UI.body

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, 0, 1, 0)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = COL.line
	scroll.CanvasSize = UDim2.new(0, 0, 0, 600)
	safe(function() scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y end)
	scroll.Parent = frame

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.Parent = scroll

	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0, 7)
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = scroll

	return { frame = frame, scroll = scroll, order = 0 }
end

local function clearList(scroll)
	for _, c in ipairs(scroll:GetChildren()) do
		if c:IsA("GuiObject") then safe(function() c:Destroy() end) end
	end
end

local function copyToClipboard(txt, okMsg)
	if not CAP.Clipboard then
		log("本执行器没有剪贴板接口,直接从面板状态栏读")
		return false
	end
	safe(setclipboard, txt)
	log(okMsg or "已复制到剪贴板,直接发我")
	return true
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

	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
		or Vector2.new(1280, 720)
	local W = math.min(360, vp.X - 16)
	local H = math.min(520, vp.Y - 30)

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.Size = UDim2.fromOffset(W, H)
	main.Position = UDim2.fromOffset(8, 50)
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
	title.Size = UDim2.new(1, -92, 0, 28)
	title.Position = UDim2.fromOffset(12, 6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 15
	title.TextColor3 = COL.text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "ZakaAria 绕过 " .. VER
	title.Parent = main

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, -24, 0, 14)
	hint.Position = UDim2.fromOffset(12, 30)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 11
	hint.TextColor3 = COL.dim
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Text = (CAP.MetaHook and "钩子可用" or "钩子不可用 · 走扫描兜底")
		.. (CAP.CheckCaller and " · caller OK" or " · 缺 checkcaller")
	hint.Parent = main

	local min = Instance.new("TextButton")
	min.Size = UDim2.fromOffset(40, 34)
	min.Position = UDim2.new(1, -48, 0, 4)
	min.BackgroundColor3 = COL.card
	min.Text = "—"
	min.TextColor3 = COL.text
	min.Font = Enum.Font.GothamBold
	min.TextSize = 18
	min.Parent = main
	corner(min, 9)

	-- ---- 页签条 ----
	local tabs = {
		{ id = "ctl",   name = "控制" },
		{ id = "cmds",  name = "命令表" },
		{ id = "aura",  name = "光环" },
		{ id = "inject",name = "注入" },
		{ id = "help",  name = "说明" },
	}
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, -20, 0, 34)
	bar.Position = UDim2.fromOffset(10, 48)
	bar.BackgroundTransparency = 1
	bar.Parent = main

	local barLay = Instance.new("UIListLayout")
	barLay.FillDirection = Enum.FillDirection.Horizontal
	barLay.Padding = UDim.new(0, 3)
	barLay.SortOrder = Enum.SortOrder.LayoutOrder
	barLay.Parent = bar

	local body = Instance.new("Frame")
	body.Size = UDim2.new(1, -20, 1, -160)
	body.Position = UDim2.fromOffset(10, 86)
	body.BackgroundTransparency = 1
	body.Parent = main
	UI.body = body

	local tabBtns = {}
	local pages = {}
	for i, t in ipairs(tabs) do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0.2, -3, 1, 0)
		b.BackgroundColor3 = i == 1 and COL.accent or COL.card
		b.BorderSizePixel = 0
		b.Font = Enum.Font.GothamBold
		b.TextSize = 12
		b.TextColor3 = i == 1 and Color3.fromRGB(255, 255, 255) or COL.dim
		b.Text = t.name
		b.LayoutOrder = i
		b.Parent = bar
		corner(b, 8)
		tabBtns[t.id] = b
	end

	for _, t in ipairs(tabs) do
		pages[t.id] = newPage(t.name)
	end
	pages.ctl.frame.Visible = true
	UI.tabBtns = tabBtns
	UI.pages = pages
	UI.active = "ctl"

	local function selectTab(id)
		UI.active = id
		for tid, p in pairs(pages) do
			p.frame.Visible = (tid == id)
			local b = tabBtns[tid]
			if b then
				b.BackgroundColor3 = (tid == id) and COL.accent or COL.card
				b.TextColor3 = (tid == id)
					and Color3.fromRGB(255, 255, 255) or COL.dim
			end
		end
	end
	for _, t in ipairs(tabs) do
		tabBtns[t.id].MouseButton1Click:Connect(function() selectTab(t.id) end)
	end
	UI.selectTab = selectTab

	--=================================================================
	-- 页:控制
	--=================================================================
	local P = pages.ctl
	local o = 0
	local function o1() o = o + 1; return o end

	mkLabel(P.scroll, o1(), "① 侦察阶段(先开这个)", COL.accent, 12)
	mkToggle(P.scroll, o1(), "Recon", "侦察模式(只记录,不拦不洗)")
	mkNote(P.scroll, o1(),
		"默认就是侦察。什么都别改,正常玩 1~2 分钟,记得挥几刀把攻击命令喂进来,再去「命令表」页看结果。", 34)

	mkLabel(P.scroll, o1(), "② 拦截 / 洗白(二选一)", COL.accent, 12)
	mkToggle(P.scroll, o1(), "BlockReport", "拦截上报包(直接不发)", function(v)
		if v then CFG.WashReport = false; CFG.ScrubCmds = false end
		if UI.rows.WashReport then UI.rows.WashReport.render() end
		if UI.rows.ScrubCmds then UI.rows.ScrubCmds.render() end
	end)
	mkToggle(P.scroll, o1(), "WashReport", "参数洗白 · 按通道(照发,内容洗干净)", function(v)
		if v then CFG.BlockReport = false end
		if UI.rows.BlockReport then UI.rows.BlockReport.render() end
	end)
	mkToggle(P.scroll, o1(), "ScrubCmds", "参数洗白 · 按命令串(这游戏的主力)", function(v)
		if v then CFG.BlockReport = false end
		if UI.rows.BlockReport then UI.rows.BlockReport.render() end
	end)
	mkToggle(P.scroll, o1(), "SilenceCharRot", "旋转静默(charRot 喂正常朝向)")
	mkToggle(P.scroll, o1(), "FlagAnalytics", "把 analytics 通道也当 AC 处理")
	mkToggle(P.scroll, o1(), "BlockKick", "拦截客户端 Kick")
	mkToggle(P.scroll, o1(), "ProtectRemoteFn", "RemoteFunction 永不拦截(防卡死)")
	mkNote(P.scroll, o1(),
		"你记录里的 PlayerFunc(readTextFilter) 是 RemoteFunction。拦它会让调用方永久卡住,游戏直接死给你看 —— 所以这条默认常开。", 46)

	mkLabel(P.scroll, o1(), "③ 客户端反作弊", COL.accent, 12)
	mkToggle(P.scroll, o1(), "DisableClientAC", "禁用反作弊 LocalScript", function(v)
		if v then disableClientAC() end
	end)
	mkToggle(P.scroll, o1(), "KillACConnects", "断开反作弊心跳连接(激进)", function(v)
		if v then killACConnections() end
	end)
	mkToggle(P.scroll, o1(), "HookReadSpoof", "属性读取伪装(WalkSpeed 报正常值)")
	mkToggle(P.scroll, o1(), "BlockLocalWrite", "拦游戏脚本改我的属性")

	mkLabel(P.scroll, o1(), "④ 位移(不碰 WalkSpeed)", COL.accent, 12)
	mkToggle(P.scroll, o1(), "SpeedBypass", "物理加速", function(v)
		if v then startSpeed() else stopSpeed() end
	end)
	mkToggle(P.scroll, o1(), "InfiniteJump", "无限跳(状态切换)")

	mkLabel(P.scroll, o1(), "⑤ 操作", COL.accent, 12)
	mkButton(P.scroll, o1(), "🔍 扫描反作弊脚本(只列出)", COL.card, function()
		local hits = collectScripts()
		log(string.format("扫描完成,命中 %d 个可疑脚本", #hits))
		for i = 1, math.min(#hits, 12) do
			log(string.format("  · %s  [%s]", hits[i].obj.Name, tostring(hits[i].word)))
		end
	end)
	mkButton(P.scroll, o1(), "📋 复制命令表(发我)", COL.accent, function()
		local lines = {}
		for _, key in ipairs(ST.CmdOrder) do
			local r = ST.Cmds[key]
			if r then
				local tag = r.level == 2 and "[AC] " or (r.level == 1 and "[?] " or "")
				lines[#lines + 1] = string.format("%s%s  →  %s   (%d 次)",
					tag, tostring(r.chan),
					r.cmd and ('"' .. r.cmd .. '"') or "(无命令串)", r.count)
			end
		end
		copyToClipboard(table.concat(lines, "\n"), "命令表已复制,直接发我")
	end)
	mkButton(P.scroll, o1(), "🧪 自检(钩子 / 通道 / 判定)", COL.card, function()
		log(string.format("自检: MetaHook=%s CheckCaller=%s Connections=%s Clipboard=%s",
			tostring(CAP.MetaHook), tostring(CAP.CheckCaller),
			tostring(CAP.Connections), tostring(CAP.Clipboard)))
		log(string.format("已记录 %d 条命令 · 拦截 %d · 洗白 %d · Kick %d",
			#ST.CmdOrder, ST.Blocked, ST.Washed, ST.Kicked))
	end)

	--=================================================================
	-- 页:命令表
	--=================================================================
	local Q = pages.cmds
	local qo = 0
	local function q1() qo = qo + 1; return qo end

	Q.filter = "all"
	mkLabel(Q.scroll, q1(), "命令表(按 通道 + 命令串 归集)", COL.accent, 12)
	mkNote(Q.scroll, q1(),
		"你这游戏的包都叫 Event / PlayerEvent / UnreliableEvent,靠第 1 个字符串参数区分功能 —— 所以 AC 一定藏在命令串里,不在包名里。", 44)

	local filterRow = Instance.new("Frame")
	filterRow.Size = UDim2.new(1, -8, 0, 34)
	filterRow.BackgroundTransparency = 1
	filterRow.LayoutOrder = q1()
	filterRow.Parent = Q.scroll
	local frLay = Instance.new("UIListLayout")
	frLay.FillDirection = Enum.FillDirection.Horizontal
	frLay.Padding = UDim.new(0, 6)
	frLay.SortOrder = Enum.SortOrder.LayoutOrder
	frLay.Parent = filterRow

	mkSmallButton(filterRow, 1, "全部", COL.card, function(b)
		Q.filter = "all"; UI.refreshCmds()
	end, 76)
	mkSmallButton(filterRow, 2, "只看 [AC]/[?]", COL.card, function(b)
		Q.filter = "ac"; UI.refreshCmds()
	end, 110)
	mkSmallButton(filterRow, 3, "刷新", COL.accent, function(b)
		UI.refreshCmds()
	end, 76)

	Q.list = Instance.new("Frame")
	Q.list.Size = UDim2.new(1, -8, 0, 120)
	Q.list.AutomaticSize = Enum.AutomaticSize.Y
	Q.list.BackgroundTransparency = 1
	Q.list.LayoutOrder = q1()
	Q.list.Parent = Q.scroll
	local qLay = Instance.new("UIListLayout")
	qLay.Padding = UDim.new(0, 7)
	qLay.SortOrder = Enum.SortOrder.LayoutOrder
	qLay.Parent = Q.list

	function UI.refreshCmds()
		clearList(Q.list)
		local arr = {}
		for _, key in ipairs(ST.CmdOrder) do
			local r = ST.Cmds[key]
			if r then
				local pass = true
				if Q.filter == "ac" and r.level == 0 then pass = false end
				if pass then arr[#arr + 1] = r end
			end
		end
		table.sort(arr, function(a, b)
			if a.level ~= b.level then return a.level > b.level end
			return a.count > b.count
		end)

		if #arr == 0 then
			local l = Instance.new("TextLabel")
			l.Size = UDim2.new(1, 0, 0, 40)
			l.BackgroundTransparency = 1
			l.Font = Enum.Font.Gotham
			l.TextSize = 12
			l.TextColor3 = COL.dim
			l.Text = "还没有记录。先正常玩一下,记得挥几刀。"
			l.Parent = Q.list
			return
		end

		local idx = 0
		for _, r in ipairs(arr) do
			idx = idx + 1
			local tag = r.level == 2 and "[AC] " or (r.level == 1 and "[?] " or "")
			local col = r.level == 2 and COL.danger
				or (r.level == 1 and COL.warn or COL.card)

			local card = Instance.new("Frame")
			card.Size = UDim2.new(1, 0, 0, 92)
			card.BackgroundColor3 = COL.card
			card.BorderSizePixel = 0
			card.LayoutOrder = idx
			card.Parent = Q.list
			corner(card, 9)

			local head = Instance.new("TextLabel")
			head.Size = UDim2.new(1, -12, 0, 22)
			head.Position = UDim2.fromOffset(8, 4)
			head.BackgroundTransparency = 1
			head.Font = Enum.Font.GothamBold
			head.TextSize = 12
			head.TextColor3 = col == COL.card and COL.text or col
			head.TextXAlignment = Enum.TextXAlignment.Left
			head.Text = string.format("%s%s → %s  (%d)",
				tag, tostring(r.chan),
				r.cmd and ('"' .. r.cmd .. '"') or "(无命令串)", r.count)
			head.Parent = card

			local body = Instance.new("TextLabel")
			body.Size = UDim2.new(1, -16, 0, 24)
			body.Position = UDim2.fromOffset(8, 26)
			body.BackgroundTransparency = 1
			body.Font = Enum.Font.Code
			body.TextSize = 11
			body.TextColor3 = COL.dim
			body.TextXAlignment = Enum.TextXAlignment.Left
			body.TextWrapped = true
			body.Text = r.body or ""
			body.Parent = card

			local btns = Instance.new("Frame")
			btns.Size = UDim2.new(1, -16, 0, 32)
			btns.Position = UDim2.fromOffset(8, 54)
			btns.BackgroundTransparency = 1
			btns.Parent = card
			local bl = Instance.new("UIListLayout")
			bl.FillDirection = Enum.FillDirection.Horizontal
			bl.Padding = UDim.new(0, 5)
			bl.Parent = btns

			mkSmallButton(btns, 1, "重放", COL.card, function() 
				if dispatch(r, "raw") then log("已重放:" .. tostring(r.cmd)) end
			end, 56)
			mkSmallButton(btns, 2, "换目标", COL.card, function()
				if dispatch(r, "retarget") then log("已按目标重发:" .. tostring(r.cmd)) end
			end, 68)
			mkSmallButton(btns, 3, "设为攻击", COL.accent, function()
				if not r.remote or not r.last then
					log("这条还没有完整模板,先让它再出现一次")
					return
				end
				ST.AttackCmd = r
				log("攻击命令已设为:" .. tostring(r.cmd))
			end, 78)
		end
	end
	UI.refreshCmds()

	--=================================================================
	-- 页:光环
	--=================================================================
	local A = pages.aura
	local ao = 0
	local function a1() ao = ao + 1; return ao end

	mkLabel(A.scroll, a1(), "光环(接命令表里的攻击命令)", COL.accent, 12)
	A.status = mkNote(A.scroll, a1(), "攻击命令:未设置", 30)
	mkToggle(A.scroll, a1(), "AuraOn", "光环开关", function(v)
		if v and not ST.AttackCmd then
			log("还没设攻击命令 —— 先去「命令表」页点某条的「设为攻击」")
		end
	end)
	mkToggle(A.scroll, a1(), "AuraTargetsAll", "打全部(关=只打最近一个)")
	mkButton(A.scroll, a1(), "刷新状态", COL.card, function()
		A.status.Text = string.format("攻击命令:%s\n半径 %d · 间隔 %.2f · %s",
			ST.AttackCmd and (tostring(ST.AttackCmd.chan) .. " → " .. tostring(ST.AttackCmd.cmd))
				or "未设置",
			CFG.AuraRange, CFG.AuraInterval,
			CFG.AuraOn and "运行中" or "停止")
	end)
	mkNote(A.scroll, a1(),
		"出包间隔被踢就往上调(0.18~0.22)。间隔越小越容易被服务端频率检测抓到。", 34)

	--=================================================================
	-- 页:注入(手搓一条包)
	--=================================================================
	local I = pages.inject
	local io_ = 0
	local function i1() io_ = io_ + 1; return io_ end

	mkLabel(I.scroll, i1(), "手搓一条包(注入)", COL.accent, 12)
	mkNote(I.scroll, i1(),
		"通道填记录里的名字(Event / PlayerEvent / UnreliableEvent),命令串按命令表填,参数写 JSON 数组。例如体力拉满:[ \"setStaminaOrForm\", \"stamina\", 999 ]", 58)

	I.chan = mkBox(I.scroll, i1(), "通道名,如 PlayerEvent", "PlayerEvent")
	I.cmd  = mkBox(I.scroll, i1(), "命令串,如 setStaminaOrForm", "")
	I.args = mkBox(I.scroll, i1(), "参数 JSON 数组", '[]', 64)

	mkButton(I.scroll, i1(), "🚀 发送", COL.accent, function()
		local chanName = trim(I.chan.Text)
		local remote = nil
		local roots = { ReplicatedStorage, LP:FindFirstChild("PlayerScripts"),
			LP:FindFirstChild("PlayerGui"), workspace }
		for _, root in ipairs(roots) do
			if root then
				local ok, f = pcall(function() return root:FindFirstChild(chanName, true) end)
				if ok and f then remote = f; break end
			end
		end
		if not remote then
			log("找不到通道:" .. chanName .. "(试试用记录里出现的名字)")
			return
		end

		local args = {}
		local txt = trim(I.args.Text)
		if txt ~= "" and txt ~= "[]" then
			local ok, dec = pcall(function()
				return game:GetService("HttpService"):JSONDecode(txt)
			end)
			if not ok or type(dec) ~= "table" then
				log("参数 JSON 解析失败,检查一下格式")
				return
			end
			args = dec
		end

		local cmd = trim(I.cmd.Text)
		local full = {}
		if cmd ~= "" then full[1] = cmd end
		for i = 1, #args do full[#full + 1] = args[i] end

		if fire(remote, "FireServer", full) then
			log(string.format("已发送: %s → %s", chanName,
				cmd ~= "" and ('"' .. cmd .. '"') or "(无命令串)"))
		else
			log("发送失败,看看通道类型对不对")
		end
	end)
	mkButton(I.scroll, i1(), "体力拉满预设", COL.card, function()
		I.chan.Text = "PlayerEvent"
		I.cmd.Text = "setStaminaOrForm"
		I.args.Text = '[ "stamina", 999 ]'
	end)
	mkButton(I.scroll, i1(), "charRot 归零预设", COL.card, function()
		I.chan.Text = "UnreliableEvent"
		I.cmd.Text = "charRot"
		I.args.Text = '[ 0, 0 ]'
	end)

	--=================================================================
	-- 页:说明
	--=================================================================
	local H2 = pages.help
	local ho = 0
	local function h1() ho = ho + 1; return ho end
	mkLabel(H2.scroll, h1(), "这个东西怎么用", COL.accent, 12)
	mkNote(H2.scroll, h1(),
		"1. 保持侦察模式,正常玩 1~2 分钟,中途挥几刀\n"
		.. "2. 翻「命令表」,看 [AC] / [?] 标记和攻击命令\n"
		.. "3. 确认了再开拦截或洗白(二选一)\n"
		.. "4. 命令表里把攻击命令「设为攻击」,回「光环」页开开关\n"
		.. "5. 把命令表复制发我,我按实际命令串精调", 120)
	mkLabel(H2.scroll, h1(), "别做这几件事", COL.warn, 12)
	mkNote(H2.scroll, h1(),
		"· 别一上来就开拦截 —— 你还不知道哪个包是上报包,拦错直接把游戏功能搞崩\n"
		.. "· 别拦 RemoteFunction(PlayerFunc 那种),调用方会永久挂住\n"
		.. "· 别瞎猜命令串往服务器灌 —— 命令总线是最容易看出异常的地方\n"
		.. "· 加速别改 WalkSpeed,那是送上门的证据", 110)

	--=================================================================
	-- 状态条 + 悬浮球
	--=================================================================
	local status = Instance.new("TextLabel")
	status.Size = UDim2.new(1, -20, 0, 60)
	status.Position = UDim2.new(0, 10, 1, -70)
	status.BackgroundColor3 = COL.card2
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
		LINES[#LINES + 1] = string.format("[%s] %s", os.date("%H:%M:%S"), tostring(msg))
		while #LINES > 4 do table.remove(LINES, 1) end
		status.TextColor3 = (tag == "KICK" or tag == "AC") and COL.warn or COL.dim
		status.Text = table.concat(LINES, "\n")
	end
	ST.OnRecord = function()
		if UI.active == "cmds" then UI.refreshCmds() end
	end

	min.MouseButton1Click:Connect(function()
		main.Visible = false
		if UI.ball then UI.ball.Visible = true end
	end)

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
				main.Visible = not main.Visible
				ball.Visible = not main.Visible
			else
				CFG.Recon = not CFG.Recon
				if UI.rows.Recon then UI.rows.Recon.render() end
				saveCfg()
				log(CFG.Recon and "已切到侦察模式" or "已切到拦截模式")
			end
		end
	end)

	log("面板就绪 · 先跑侦察,挥几刀再翻命令表")
end

--=====================================================================
-- 13. 启动
--=====================================================================
hookAll()
bindLoop()
buildUI()
startAura()

genv.ZAKA_ARIA_DESTROY = function()
	ST.AuraRun = false
	for _, c in ipairs(ST.Conns) do safe(function() c:Disconnect() end) end
	stopSpeed()
	if UI.gui then safe(function() UI.gui:Destroy() end) end
	log("已卸载")
end

log("ZakaAriaBypass " .. VER .. " 已加载")
