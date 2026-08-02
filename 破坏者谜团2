-- 破坏者谜团2
-- 工具扫描高亮 + GunDrop 全工作区监听
-- UI 半透明小窗锁定右上角偏下

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
local ORIGIN = nil
local SHERIFF_EXISTS = false

-- ====== 工具函数 ======
local function getRoot()
    local c = player.Character
    return c and c:FindFirstChild("HumanoidRootPart") or nil
end

local function markOrigin()
    local r = getRoot()
    if r then ORIGIN = r.CFrame; return true end
    return false
end

local function goTo(pos)
    local r = getRoot()
    if r then r.CFrame = CFrame.new(pos) end
end

local function goHome()
    local r = getRoot()
    if r and ORIGIN then
        r.CFrame = ORIGIN
        ORIGIN = nil
        if DEBUG then print("[🏠] 已回原点并清除") end
    end
end

-- 万能坐标
local function getObjPos(obj)
    if not obj then return nil end
    local ok, v = pcall(function() return obj.Position end)
    if ok and v then return v end
    ok, v = pcall(function() return obj.CFrame.Position end)
    if ok and v then return v end
    if obj:IsA("Model") then
        for _, c in ipairs(obj:GetChildren()) do
            if c:IsA("BasePart") then return c.Position end
        end
    end
    return nil
end

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

-- ====== GunDrop 触发 ======
local function onGunDrop(obj)
    task.wait(0.1)
    local pos = getObjPos(obj)
    if not pos then return end
    if DEBUG then print("[🔫] GunDrop: "..obj.Name) end
    markOrigin(); goTo(pos); task.wait(0.15); goHome()
end

-- 监听所有层级
Workspace.DescendantAdded:Connect(function(obj)
    if not obj or not obj.Name then return end
    if obj.Name:find("GunDrop") then task.spawn(function() onGunDrop(obj) end) end
end)

-- 监听顶层兜底
Workspace.ChildAdded:Connect(function(obj)
    if not obj or not obj.Name then return end
    if obj.Name:find("GunDrop") then task.spawn(function() onGunDrop(obj) end) end
end)

-- 启动时检查已有
task.spawn(function()
    task.wait(2)
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj.Name:find("GunDrop") then task.spawn(function() onGunDrop(obj) end) end
    end
end)

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

player.CharacterAdded:Connect(function() ORIGIN = nil end)

-- ==========================================
-- UI（半透明小窗，锁定右上角偏下）
-- ==========================================
local sg = Instance.new("ScreenGui")
sg.Name = "UI"; sg.ResetOnSpawn = false; sg.IgnoreGuiInset = true
sg.Parent = player:WaitForChild("PlayerGui")

-- 主面板
local f = Instance.new("Frame")
f.Size = UDim2.new(0, 180, 0, 120)
f.Position = UDim2.new(1, -190, 0, 60)  -- ★ 往下移：Y=60
f.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
f.BackgroundTransparency = 0.65         -- 背景半透明
f.BorderSizePixel = 0
f.Active = false                        -- 锁定不可拖动
f.Parent = sg

-- 标题（不透明）
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -6, 0, 16)
title.Position = UDim2.new(0, 3, 0, 3)
title.BackgroundTransparency = 1
title.Text = "破坏者谜团2"
title.TextColor3 = Color3.fromRGB(255, 210, 80)
title.TextTransparency = 0                 -- ★ 不透明
title.TextScaled = true
title.Font = Enum.Font.GothamBold          -- ★ 不透明字体
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = f

-- 状态
local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, -6, 0, 12)
statusLbl.Position = UDim2.new(0, 3, 0, 22)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = "● 运行中"
statusLbl.TextColor3 = Color3.fromRGB(144, 238, 144)
statusLbl.TextTransparency = 0             -- ★ 不透明
statusLbl.TextScaled = true
statusLbl.Font = Enum.Font.GothamSemibold  -- ★ 不透明字体
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Parent = f

-- 警长
local sheriffLbl = Instance.new("TextLabel")
sheriffLbl.Size = UDim2.new(1, -6, 0, 12)
sheriffLbl.Position = UDim2.new(0, 3, 0, 36)
sheriffLbl.BackgroundTransparency = 1
sheriffLbl.Text = "警长: 检测中..."
sheriffLbl.TextColor3 = Color3.fromRGB(180, 200, 255)
sheriffLbl.TextTransparency = 0            -- ★ 不透明
sheriffLbl.TextScaled = true
sheriffLbl.Font = Enum.Font.GothamSemibold -- ★ 不透明字体
sheriffLbl.TextXAlignment = Enum.TextXAlignment.Left
sheriffLbl.Parent = f

-- 监听状态
local detectLbl = Instance.new("TextLabel")
detectLbl.Size = UDim2.new(1, -6, 0, 12)
detectLbl.Position = UDim2.new(0, 3, 0, 50)
detectLbl.BackgroundTransparency = 1
detectLbl.Text = "监听: ✓"
detectLbl.TextColor3 = Color3.fromRGB(144, 238, 144)
detectLbl.TextTransparency = 0              -- ★ 不透明
detectLbl.TextScaled = true
detectLbl.Font = Enum.Font.GothamSemibold  -- ★ 不透明字体
detectLbl.TextXAlignment = Enum.TextXAlignment.Left
detectLbl.Parent = f

-- 原点
local originLbl = Instance.new("TextLabel")
originLbl.Size = UDim2.new(1, -6, 0, 12)
originLbl.Position = UDim2.new(0, 3, 0, 64)
originLbl.BackgroundTransparency = 1
originLbl.Text = "原点: 无"
originLbl.TextColor3 = Color3.fromRGB(180, 180, 180)
originLbl.TextTransparency = 0              -- ★ 不透明
originLbl.TextScaled = true
originLbl.Font = Enum.Font.GothamSemibold  -- ★ 不透明字体
originLbl.TextXAlignment = Enum.TextXAlignment.Left
originLbl.Parent = f

-- 坐标
local coordLbl = Instance.new("TextLabel")
coordLbl.Size = UDim2.new(1, -6, 0, 12)
coordLbl.Position = UDim2.new(0, 3, 0, 78)
coordLbl.BackgroundTransparency = 1
coordLbl.Text = "坐标: --"
coordLbl.TextColor3 = Color3.fromRGB(200, 200, 200)
coordLbl.TextTransparency = 0                -- ★ 不透明
coordLbl.TextScaled = true
coordLbl.Font = Enum.Font.GothamSemibold   -- ★ 不透明字体
coordLbl.TextXAlignment = Enum.TextXAlignment.Left
coordLbl.Parent = f

-- ★ 传回原点按钮（不透明）
local homeBtn = Instance.new("TextButton")
homeBtn.Size = UDim2.new(1, -6, 0, 18)
homeBtn.Position = UDim2.new(0, 3, 0, 95)
homeBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 70)
homeBtn.BackgroundTransparency = 0           -- ★ 不透明
homeBtn.Text = "🏠 传回原点"
homeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
homeBtn.TextTransparency = 0                 -- ★ 不透明
homeBtn.TextScaled = true
homeBtn.Font = Enum.Font.GothamSemibold    -- ★ 不透明字体
homeBtn.BorderSizePixel = 0
homeBtn.Parent = f

homeBtn.MouseButton1Click:Connect(function() goHome() end)

-- ★ 开关按钮（不透明）- 显示/隐藏面板
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0, 24, 0, 16)
toggleBtn.Position = UDim2.new(1, -27, 0, 3)
toggleBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
toggleBtn.BackgroundTransparency = 0          -- ★ 不透明
toggleBtn.Text = "_"
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.TextTransparency = 0                -- ★ 不透明
toggleBtn.TextScaled = true
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.BorderSizePixel = 0
toggleBtn.Parent = f

local UIVISIBLE = true
toggleBtn.MouseButton1Click:Connect(function()
    UIVISIBLE = not UIVISIBLE
    -- 隐藏/显示除标题栏以外的所有内容
    statusLbl.Visible = UIVISIBLE
    sheriffLbl.Visible = UIVISIBLE
    detectLbl.Visible = UIVISIBLE
    originLbl.Visible = UIVISIBLE
    coordLbl.Visible = UIVISIBLE
    homeBtn.Visible = UIVISIBLE
    toggleBtn.Text = UIVISIBLE and "_" or "▲"
    -- 调整面板高度
    if UIVISIBLE then
        f.Size = UDim2.new(0, 180, 0, 120)
    else
        f.Size = UDim2.new(0, 180, 0, 20)
    end
end)

-- UI 更新
task.spawn(function()
    while true do
        task.wait(0.5)

        if SHERIFF_EXISTS then
            sheriffLbl.Text = "警长: ✅"
            sheriffLbl.TextColor3 = Color3.fromRGB(100, 200, 255)
        else
            sheriffLbl.Text = "警长: ❌"
            sheriffLbl.TextColor3 = Color3.fromRGB(255, 200, 100)
        end

        local root = getRoot()
        if ORIGIN then
            originLbl.Text = "原点: ✓"
            originLbl.TextColor3 = Color3.fromRGB(100, 230, 100)
            coordLbl.Text = string.format("坐标: %.0f,%.0f,%.0f",
                ORIGIN.Position.X, ORIGIN.Position.Y, ORIGIN.Position.Z)
            coordLbl.TextColor3 = Color3.fromRGB(100, 230, 100)
        else
            originLbl.Text = "原点: 无"
            originLbl.TextColor3 = Color3.fromRGB(180, 180, 180)
            if root then
                coordLbl.Text = string.format("坐标: %.0f,%.0f,%.0f",
                    root.Position.X, root.Position.Y, root.Position.Z)
                coordLbl.TextColor3 = Color3.fromRGB(200, 200, 200)
            else
                coordLbl.Text = "坐标: --"
            end
        end
    end
end)

print("[✅] 破坏者谜团2 加载完成")
