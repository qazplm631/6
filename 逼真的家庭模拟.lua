
local scripts = {
    {
        name = "后座6",
        url = "https://raw.githubusercontent.com/qazplm631/6/main/%E5%90%8E%E5%BA%A76.lua"
    },
    {
        name = "透视13",
        url = "https://raw.githubusercontent.com/qazplm631/6/main/%E9%80%8F%E8%A7%8613.lua"
    },
    {
        name = "范围",
        url = "https://raw.githubusercontent.com/qazplm631/6/main/%E8%8C%83%E5%9B%B4.lua"
    },
    {
        name = "无限子弹V3",
        url = "https://raw.githubusercontent.com/qazplm631/6/main/%E6%97%A0%E9%99%90%E5%AD%90%E5%BC%B9V3.lua"
    },
    {
        name = "人物加速",
        url = "https://raw.githubusercontent.com/qazplm631/6/main/%E4%BA%BA%E7%89%A9%E5%8A%A0%E9%80%9F.lua"
    }
}

for _, script in ipairs(scripts) do
    local ok, err = pcall(function()
        local source = game:HttpGet(script.url)
        local func, compileError = loadstring(source)

        assert(func, compileError)
        func()
    end)

    if not ok then
        warn("[" .. script.name .. "] 加载失败：" .. tostring(err))
    else
        print("[" .. script.name .. "] 已执行")
    end
end
