-- ============================================
--  高亮 + 名称显示 控制面板
--  可拖动 · 右上角偏下 · 两个独立开关
-- ============================================

local Players   = game:GetService("Players")
local UserInput = game:GetService("UserInputService")
local player    = Players.LocalPlayer

-- ====== 配置 ======
local SCAN_INTERVAL   = 3      -- 扫描间隔(秒)
local HIGHLIGHT_FILL  = 0.5
local HIGHLIGHT_LINE  = 0.2

local SHERIFF_COLOR   = Color3.fromRGB(50, 120, 255)   -- 蓝
local KILLER_COLOR    = Color3.fromRGB(255, 50, 50)    -- 红
local CIVILIAN_COLOR  = Color3.fromRGB(50, 220, 80)    -- 绿

-- ====== 全局开关 ======
local HIGHLIGHT_ENABLED = true
local NAMETAG_ENABLED   = true

-- ============================================
--              工具函数
-- ============================================
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
    if hasGun      then return "sheriff"  end
    if hasKnife    then return "killer"   end
    return "civilian"
end

-- ====== 高亮 ======
local function applyHighlight(char, color)
    if not char then return end
    local hl = char:FindFirstChild("HL")
    if not hl then
        hl = Instance.new("Highlight")
        hl.Name = "HL"
        hl.Parent = char
    end
    hl.FillColor = color
    hl.OutlineColor = color
    hl.FillTransparency = HIGHLIGHT_FILL
    hl.OutlineTransparency = HIGHLIGHT_LINE
end

local function removeHighlight(char)
    if not char then return end
    local hl = char:FindFirstChild("HL")
    if hl then hl:Destroy() end
end

-- ====== 名称标签 ======
local function applyNameTag(char, name, color)
    if not char then return end
    local head = char:FindFirstChild("Head")
    if not head then return end

    -- 已存在则更新
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
    lbl.TextTransparency = 0.35
    lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    lbl.TextStrokeTransparency = 0.5
    lbl.TextScaled = true
    lbl.Font = Enum.Font.GothamSemibold
    lbl.Parent = bg
end

local function removeNameTag(char)
    if not char then return end
    local head = char:FindFirstChild("Head")
    if head then
        local t = head:FindFirstChild("NT")
        if t then t:Destroy() end
    end
end

-- ====== 清除全部标记 ======
local function clearAllMarks()
    for _, p in ipairs(Players:GetPlayers()) do
        local char = p.Character
        if char then
            removeHighlight(char)
            removeNameTag(char)
        end
    end
end

-- ====== 处理单个玩家 ======
local function processPlayer(p)
    local char = p.Character
    if not char then return end

    -- 两个都关 → 清干净
    if not HIGHLIGHT_ENABLED and not NAMETAG_ENABLED then
        removeHighlight(char)
        removeNameTag(char)
        return
    end

    local role = scanPlayerTools(p)
    local color =
        role == "sheriff"  and SHERIFF_COLOR or
        role == "killer"   and KILLER_COLOR  or
        CIVILIAN_COLOR

    if HIGHLIGHT_ENABLED then
        applyHighlight(char, color)
    else
        removeHighlight(char)
    end

    if NAMETAG_ENABLED then
        applyNameTag(char, p.Name, color)
    else
        removeNameTag(char)
    end
end

-- ====== 主扫描循环 ======
task.spawn(function()
    task.wait(2)
    while true do
        task.wait(SCAN_INTERVAL)
        for _, p in ipairs(Players:GetPlayers()) do
            pcall(function() processPlayer(p) end)
        end
    end
end)

-- 新玩家加入时立即扫描
Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function()
        task.wait(1)
        pcall(function() processPlayer(p) end)
    end)
end)

-- ============================================
--              UI 控制面板
-- ============================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "HighlightControlUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.Parent = player:WaitForChild("PlayerGui")

-- ====== 主面板 ======
local Panel = Instance.new("Frame")
Panel.Name = "Panel"
Panel.Size = UDim2.new(0, 200, 0, 130)
Panel.Position = UDim2.new(1, -210, 0, 50)   -- 右上角偏下
Panel.BackgroundColor3 = Color3.fromRGB(18, 18, 25)
Panel.BackgroundTransparency = 0.35
Panel.BorderSizePixel = 0
Panel.Active = true          -- 允许拖动
Panel.Draggable = true       -- 开启拖动
Panel.Parent = ScreenGui

local PanelCorner = Instance.new("UICorner")
PanelCorner.CornerRadius = UDim.new(0, 8)
PanelCorner.Parent = Panel

-- ====== 标题栏（拖动手柄） ======
local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 24)
TitleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
TitleBar.BackgroundTransparency = 0.2
TitleBar.BorderSizePixel = 0
TitleBar.Parent = Panel

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 8)
TitleCorner.Parent = TitleBar

-- 底部切角（让标题栏下半部分方角）
local TitleFix = Instance.new("Frame")
TitleFix.Size = UDim2.new(1, 0, 0, 8)
TitleFix.Position = UDim2.new(0, 0, 1, -8)
TitleFix.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
TitleFix.BackgroundTransparency = 0.2
TitleFix.BorderSizePixel = 0
TitleFix.Parent = TitleBar

-- 标题文字
local TitleText = Instance.new("TextLabel")
TitleText.Size = UDim2.new(1, -40, 1, 0)
TitleText.Position = UDim2.new(0, 8, 0, 0)
TitleText.BackgroundTransparency = 1
TitleText.Text = "⚙ 高亮控制面板"
TitleText.TextColor3 = Color3.fromRGB(245, 220, 110)
TitleText.TextScaled = true
TitleText.Font = Enum.Font.GothamBold
TitleText.TextXAlignment = Enum.TextXAlignment.Left
TitleText.Parent = TitleBar

-- 关闭按钮 (X)
local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 22, 0, 22)
CloseBtn.Position = UDim2.new(1, -24, 0, 1)
CloseBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
CloseBtn.BackgroundTransparency = 0.3
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.TextScaled = true
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.BorderSizePixel = 0
CloseBtn.Parent = TitleBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 4)
CloseCorner.Parent = CloseBtn

-- ====== 高亮开关按钮 ======
local HighlightBtn = Instance.new("TextButton")
HighlightBtn.Size = UDim2.new(1, -16, 0, 28)
HighlightBtn.Position = UDim2.new(0, 8, 0, 32)
HighlightBtn.BackgroundColor3 = Color3.fromRGB(50, 180, 80)
HighlightBtn.BackgroundTransparency = 0
HighlightBtn.Text = "✅ 高亮已开启"
HighlightBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
HighlightBtn.TextScaled = true
HighlightBtn.Font = Enum.Font.GothamSemibold
HighlightBtn.BorderSizePixel = 0
HighlightBtn.Parent = Panel

local HLBtnCorner = Instance.new("UICorner")
HLBtnCorner.CornerRadius = UDim.new(0, 5)
HLBtnCorner.Parent = HighlightBtn

-- ====== 名称显示开关按钮 ======
local NameTagBtn = Instance.new("TextButton")
NameTagBtn.Size = UDim2.new(1, -16, 0, 28)
NameTagBtn.Position = UDim2.new(0, 8, 0, 68)
NameTagBtn.BackgroundColor3 = Color3.fromRGB(50, 180, 80)
NameTagBtn.BackgroundTransparency = 0
NameTagBtn.Text = "✅ 名称已开启"
NameTagBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
NameTagBtn.TextScaled = true
NameTagBtn.Font = Enum.Font.GothamSemibold
NameTagBtn.BorderSizePixel = 0
NameTagBtn.Parent = Panel

local NTBtnCorner = Instance.new("UICorner")
NTBtnCorner.CornerRadius = UDim.new(0, 5)
NTBtnCorner.Parent = NameTagBtn

-- ====== 底部状态指示 ======
local StatusText = Instance.new("TextLabel")
StatusText.Size = UDim2.new(1, -16, 0, 14)
StatusText.Position = UDim2.new(0, 8, 1, -18)
StatusText.BackgroundTransparency = 1
StatusText.Text = "● 运行中"
StatusText.TextColor3 = Color3.fromRGB(130, 230, 130)
StatusText.TextScaled = true
StatusText.Font = Enum.Font.GothamSemibold
StatusText.TextXAlignment = Enum.TextXAlignment.Left
StatusText.Parent = Panel

-- ============================================
--           按钮交互逻辑
-- ============================================

-- 高亮开关
HighlightBtn.MouseButton1Click:Connect(function()
    HIGHLIGHT_ENABLED = not HIGHLIGHT_ENABLED
    if HIGHLIGHT_ENABLED then
        HighlightBtn.Text = "✅ 高亮已开启"
        HighlightBtn.BackgroundColor3 = Color3.fromRGB(50, 180, 80)
    else
        HighlightBtn.Text = "⭕ 高亮已关闭"
        HighlightBtn.BackgroundColor3 = Color3.fromRGB(160, 60, 60)
        -- 立即清除所有高亮
        for _, p in ipairs(Players:GetPlayers()) do
            removeHighlight(p.Character)
        end
    end
end)

-- 名称开关
NameTagBtn.MouseButton1Click:Connect(function()
    NAMETAG_ENABLED = not NAMETAG_ENABLED
    if NAMETAG_ENABLED then
        NameTagBtn.Text = "✅ 名称已开启"
        NameTagBtn.BackgroundColor3 = Color3.fromRGB(50, 180, 80)
    else
        NameTagBtn.Text = "⭕ 名称已关闭"
        NameTagBtn.BackgroundColor3 = Color3.fromRGB(160, 60, 60)
        -- 立即清除所有名称标签
        for _, p in ipairs(Players:GetPlayers()) do
            removeNameTag(p.Character)
        end
    end
end)

-- 关闭按钮 → 隐藏面板到右下角小图标
local PANEL_CLOSED = false
CloseBtn.MouseButton1Click:Connect(function()
    PANEL_CLOSED = not PANEL_CLOSED
    if PANEL_CLOSED then
        Panel.Size = UDim2.new(0, 200, 0, 24)  -- 只留标题栏
        HighlightBtn.Visible = false
        NameTagBtn.Visible = false
        StatusText.Visible = false
        CloseBtn.Text = "▲"
    else
        Panel.Size = UDim2.new(0, 200, 0, 130)
        HighlightBtn.Visible = true
        NameTagBtn.Visible = true
        StatusText.Visible = true
        CloseBtn.Text = "✕"
    end
end)

print("[✅] 高亮控制面板 加载完成 (可拖动)")

