--[[ 无限体力 · 速度锁 终版
     只改下面 CONFIG 里的数字即可调速，重复运行不会叠加 hook
     推荐区间：基础走速 6 的游戏，SPEED 用 24 ~ 32 最自然
--]]

local CONFIG = {
    SPEED = 28,          -- ← 改这里：24 / 28 / 32 / 36
    BLOCK_LOWER = true,  -- 拦截游戏把速度调低
}

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer
local SPEED = CONFIG.SPEED
local out = function(s) print("[SPD] " .. s) end

-- 只装一次 hook，重复运行不会套娃
if CONFIG.BLOCK_LOWER and not _G.__spdHookInstalled then
    local ok, err = pcall(function()
        local oldIndex
        oldIndex = hookmetamethod(game, "__newindex", function(self, key, value)
            if key == "WalkSpeed" and not checkcaller() then
                if type(value) == "number" and value < _G.__spdSpeed then
                    return
                end
            end
            return oldIndex(self, key, value)
        end)
        _G.__spdHookInstalled = true
    end)
    if not ok then out("hook 装不上: " .. tostring(err)) end
end

-- 动态速度：每次运行都更新这个值，hook 读它
_G.__spdSpeed = SPEED

-- 停掉上一轮的循环
if _G.__spdLoop then
    pcall(function() _G.__spdLoop:Disconnect() end)
end

_G.__spdLoop = RunService.Heartbeat:Connect(function()
    local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if hum and hum.WalkSpeed < _G.__spdSpeed then
        pcall(function() hum.WalkSpeed = _G.__spdSpeed end)
    end
end)

out("已启用，速度 " .. SPEED)
