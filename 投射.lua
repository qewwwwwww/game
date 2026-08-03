-- 破坏者谜团2 - 精简版 (仅扫描高亮)
-- 已移除：GunDrop监听、原点标记、传送功能及相关UI元素

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer

-- ====== 配置 ======
local TOOL_SCAN = 3
local DEBUG = false
local HIGHLIGHT_FILL = 0.5
local HIGHLIGHT_LINE = 0.2

-- 颜色
local SHERIFF_COLOR  = Color3.fromRGB(50, 120, 255)
local KILLER_COLOR   = Color3.fromRGB(255, 50, 50)
local CIVILIAN_COLOR = Color3.fromRGB(50, 220, 80)

-- 全局
local SHERIFF_EXISTS = false

-- ====== 工具判断 ======
local function scanPlayerTools(p)
    local hasGun, hasKnife = false, false
    local function check(it)
        if not it:IsA("Tool") then return end
        local n = it.Name:lower()
        if n:find("gun") then hasGun = true
        elseif n:find("knife") or n:find("blade") or n:find("dagger") then hasKnife = true
        end
    end
    local bp = p:FindFirstChild("Backpack")
    if bp then for _, it in ipairs(bp:GetChildren()) do check(it) end end
    local char = p.Character
    if char then for _, it in ipairs(char:GetChildren()) do check(it) end end

    if hasGun then return "sheriff" end
    if hasKnife then return "killer" end
    return "civilian"
end

-- ====== 高亮 ======
local function applyHighlight(char, color)
    if not char then return end
    local hl = char:FindFirstChild("HL")
    if not hl then hl = Instance.new("Highlight"); hl.Name = "HL"; hl.Parent = char end
    hl.FillColor = color; hl.OutlineColor = color
    hl.FillTransparency = HIGHLIGHT_FILL; hl.OutlineTransparency = HIGHLIGHT_LINE
end

local function removeHighlight(char)
    if not char then return end
    local hl = char:FindFirstChild("HL")
    if hl then hl:Destroy() end
end

-- 名字标签（缩小 + 半透明）
local function applyNameTag(char, name, color)
    if not char then return end
    local head = char:FindFirstChild("Head")
    if not head then return end
    local old = head:FindFirstChild("NT")
    if old then old:Destroy() end

    local bg = Instance.new("BillboardGui")
    bg.Name = "NT"
    bg.Size = UDim2.new(0, 140, 0, 18)
    bg.StudsOffset = Vector3.new(0, 2.2, 0)
    bg.Adornee = head
    bg.AlwaysOnTop = true
    bg.Parent = head

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = name
    lbl.TextColor3 = color
    lbl.TextTransparency = 0.45
    lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    lbl.TextStrokeTransparency = 0.6
    lbl.TextScaled = true
    lbl.Font = Enum.Font.GothamSemibold
    lbl.Parent = bg
end

local function removeNameTag(char)
    if not char then return end
    local head = char:FindFirstChild("Head")
    if head then local t = head:FindFirstChild("NT"); if t then t:Destroy() end end
end

-- ====== 处理玩家 ======
local function processPlayer(p)
    local char = p.Character
    if not char then return end
    local r = scanPlayerTools(p)
    if r == "sheriff" then
        applyHighlight(char, SHERIFF_COLOR); applyNameTag(char, p.Name, SHERIFF_COLOR)
    elseif r == "killer" then
        applyHighlight(char, KILLER_COLOR); applyNameTag(char, p.Name, KILLER_COLOR)
    else
        applyHighlight(char, CIVILIAN_COLOR); applyNameTag(char, p.Name, CIVILIAN_COLOR)
    end
end

-- ====== 警长检测 ======
local function checkSheriff()
    for _, p in ipairs(Players:GetPlayers()) do
        if scanPlayerTools(p) == "sheriff" then return true end
    end
    return false
end

-- ====== 主循环 ======
task.spawn(function()
    task.wait(2)
    while true do
        task.wait(TOOL_SCAN)
        for _, p in ipairs(Players:GetPlayers()) do
            pcall(function() processPlayer(p) end)
        end
        SHERIFF_EXISTS = checkSheriff()
    end
end)

Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function()
        task.wait(1); pcall(function() processPlayer(p) end)
    end)
end)

-- ==========================================
-- UI（半透明小窗，锁定右上角偏下）
-- ==========================================
local sg = Instance.new("ScreenGui")
sg.Name = "UI"; sg.ResetOnSpawn = false; sg.IgnoreGuiInset = true
sg.Parent = player:WaitForChild("PlayerGui")

-- 主面板
local f = Instance.new("Frame")
f.Size = UDim2.new(0, 160, 0, 85)
f.Position = UDim2.new(1, -170, 0, 40)
f.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
f.BackgroundTransparency = 0.65
f.BorderSizePixel = 0
f.Active = false
f.Parent = sg

-- 标题
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -6, 0, 14)
title.Position = UDim2.new(0, 3, 0, 3)
title.BackgroundTransparency = 1
title.Text = "破坏者谜团2"
title.TextColor3 = Color3.fromRGB(240, 195, 75)
title.TextTransparency = 0
title.TextScaled = true
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = f

-- 状态
local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, -6, 0, 11)
statusLbl.Position = UDim2.new(0, 4, 0, 19)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = "● 扫描中"
statusLbl.TextColor3 = Color3.fromRGB(130, 225, 135)
statusLbl.TextTransparency = 0
statusLbl.TextScaled = true
statusLbl.Font = Enum.Font.GothamSemibold
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Parent = f

-- 警长
local sheriffLbl = Instance.new("TextLabel")
sheriffLbl.Size = UDim2.new(1, -6, 0, 13)
sheriffLbl.Position = UDim2.new(0, 4, 0, 32)
sheriffLbl.BackgroundTransparency = 1
sheriffLbl.Text = "警长: 检测中..."
sheriffLbl.TextColor3 = Color3.fromRGB(175, 205, 245)
sheriffLbl.TextTransparency = 0
sheriffLbl.TextScaled = true
sheriffLbl.Font = Enum.Font.GothamSemibold
sheriffLbl.TextXAlignment = Enum.TextXAlignment.Left
sheriffLbl.Parent = f

-- 杀手
local killerLbl = Instance.new("TextLabel")
killerLbl.Size = UDim2.new(1, -6, 0, 13)
killerLbl.Position = UDim2.new(0, 90, 0, 46)
killerLbl.BackgroundTransparency = 1
killerLbl.Text = "杀手: ?"
killerLbl.TextColor3 = Color3.fromRGB(235, 165, 155)
killerLbl.TextTransparency = 0
killerLbl.TextScaled = true
killerLbl.Font = Enum.Font.GothamSemibold
killerLbl.TextXAlignment = Enum.TextXAlignment.Left
killerLbl.Parent = f

-- 平民
local civilianLbl = Instance.new("TextLabel")
civilianLbl.Size = UDim2.new(1, -8, 0, 17)
civilianLbl.Position = UDim2.new(0, 110, 0, 44)
civilianLbl.BackgroundTransparency = 1
civilianLbl.Text = "平民: ?"
civilianLbl.TextColor3 = Color3.fromRGB(145, 215, 185)
civilianLbl.TextTransparency = 0
civilianLbl.TextScaled = true
civilianLbl.Font = Enum.Font.GothamSemibold
civilianLbl.TextXAlignment = Enum.TextXAlignment.Left
civilianLbl.Parent = f

-- 玩家数量
local countLbl = Instance.new("TextLabel")
countLbl.Size = UDim2.new(1, -6, 0, 12)
countLbl.Position = UDim2.new(0, 55, 0, 56)
countLbl.BackgroundTransparency = 1
countLbl.Text = "玩家: 0"
countLbl.TextColor3 = Color3.fromRGB(200, 198, 188)
countLbl.TextTransparency = 0
countLbl.TextScaled = true
countLbl.Font = Enum.Font.GothamSemibold
countLbl.TextXAlignment = Enum.TextXAlignment.Left
countLbl.Parent = f

-- UI 更新
task.spawn(function()
    while true do
        task.wait(0.5)

        if SHERIFF_EXISTS then
            sheriffLbl.Text = "警长: ✅"
            sheriffLbl.TextColor3 = Color3.fromRGB(100, 192, 232)
        else
            sheriffLbl.Text = "警长: ❌"
            sheriffLbl.TextColor3 = Color3.fromRGB(242, 184, 102)
        end

        -- 统计各类人数
        local sheriffs, killers, civilians = 0, 0, 0
        for _, p in ipairs(Players:GetPlayers()) do
            local role = scanPlayerTools(p)
            if role == "sheriff" then sheriffs = sheriffs + 1
            elseif role == "killer" then killers = killers + 1
            else civilians = civilians + 1
            end
        end
        
        killerLbl.Text = "杀手: " .. tostring(killers)
        civilianLbl.Text = "平民: " .. tostring(civilians)
        countLbl.Text = "玩家: " .. tostring(#Players:GetPlayers())
    end
end)

print("[✅] 破坏者谜团2 (仅扫描高亮) 加载完成")
