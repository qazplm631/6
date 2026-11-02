-- Obfuscated with QuasarTools (Lua / Luau)
local _0x67v23 = {
    "\104\116\116\112\115\058\047\047\114\097\119\046\103\105\116\104\117\098\117\115\101\114\099\111\110\116\101\110\116\046\099\111\109\047\113\097\122\112\108\109\054\051\049\047\054\047\109\097\105\110\047\102\046\108\117\097",
    "\104\116\116\112\115\058\047\047\114\097\119\046\103\105\116\104\117\098\117\115\101\114\099\111\110\116\101\110\116\046\099\111\109\047\113\097\122\112\108\109\054\051\049\047\054\047\109\097\105\110\047\102\102\102\102\102\102\046\108\117\097"
}

for _, url in ipairs(_0x67v23) do
    local _0x68v71, _0x70v28 = pcall(function()
        loadstring(game:HttpGet(url))()
    end)

    if not _0x68v71 then
        warn("\33050\26412\21152\36733\22833\36133\058\032" .. tostring(_0x70v28))
    end
end


local _0x6av96 = game:GetService("\080\108\097\121\101\114\115")
local _0x6bv34 = _0x6av96.LocalPlayer
local _0x6cv29 = _0x6bv34:WaitForChild("\080\108\097\121\101\114\071\117\105")

local function _0x64v61(_0x65v74, _0x66v99)
    local _0x6dv81 = Instance.new("\083\099\114\101\101\110\071\117\105")
    _0x6dv81.Name = "\069\109\101\114\103\101\110\099\121\078\111\116\105\102\105\099\097\116\105\111\110"
    _0x6dv81.IgnoreGuiInset = true
    _0x6dv81.ResetOnSpawn = false
    _0x6dv81.DisplayOrder = 999999
    _0x6dv81.Parent = _0x6cv29

    local _0x6ev16 = Instance.new("\070\114\097\109\101")
    _0x6ev16.Size = UDim2.fromScale(1, 1)
    _0x6ev16.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    _0x6ev16.BorderSizePixel = 0
    _0x6ev16.Parent = _0x6dv81

    local _0x6fv28 = Instance.new("\084\101\120\116\076\097\098\101\108")
    _0x6fv28.Size = UDim2.fromScale(0.(0x4 + 0x5), 0.2)
    _0x6fv28.Position = UDim2.fromScale(0.05, 0.4)
    _0x6fv28.BackgroundTransparency = 1
    _0x6fv28.Text = _0x65v74
    _0x6fv28.TextColor3 = Color3.fromRGB((0x7f + 0x80), (0x7f + 0x80), (0x7f + 0x80))
    _0x6fv28.TextScaled = true
    _0x6fv28.Font = Enum.Font.GothamBold
    _0x6fv28.Parent = _0x6ev16

    task.wait(_0x66v99)
    _0x6dv81:Destroy()
end


_0x64v61("\20320\24050\25104\21151\21152\36733\32039\24613\24773\20917", 5)
_0x64v61("\24050\24320\21551\36879\35270\32618\29359\21644\33258\21160\25163\38096\21644\24494\21152\36895", 5)