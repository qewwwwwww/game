-- 破坏者谜团2 - 完整版
-- 工具扫描高亮 + GunDrop + 自动射击（敌人背后直射）

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer

-- ====== 配置 ======
local TOOL_SCAN = 0.5
local GUNDROP_SCAN = 0.2
local SHOOT_COOLDOWN = 0.1
local BEHIND_DISTANCE = 3

-- 颜色
local SHERIFF_COLOR  = Color3.fromRGB(50, 120, 255)
local KILLER_COLOR   = Color3.fromRGB(255, 50, 50)
local CIVILIAN_COLOR = Color3.fromRGB(50, 220, 80)

-- 全局
local ORIGIN = nil
local SHERIFF_EXISTS = false
local lastShootTime = 0
local AUTO_SHOOT = true
local HIGHLIGHT_ENABLED = true
local GUNDROP_ENABLED = true
local SHERIFF_CHECK_ENABLED = true
local SCRIPT_ENABLED = true
local currentKillerPos = nil

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
    if r and ORIGIN then r.CFrame = ORIGIN; ORIGIN = nil end
end

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
        elseif n:find("knife") or n:find("blade") or n:find("dagger") or n:find("sword") or n:find("melee") then hasKnife = true
        end
    end
    local bp = p:FindFirstChild("Backpack")
    if bp then for _, it in ipairs(bp:GetChildren()) do check(it) end end
    local char = p.Character
    if char then for _, it in ipairs(char:GetChildren()) do check(it) end end
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj:IsA("Model") and (obj.Name:lower():find(p.Name:lower()) or obj.Name:lower():find("player")) then
            for _, item in ipairs(obj:GetChildren()) do if item:IsA("Tool") then check(item) end end
            for _, subItem in ipairs(obj:GetDescendants()) do if subItem:IsA("Tool") then check(subItem) end end
        end
    end
    if hasGun then return "sheriff" end
    if hasKnife then return "killer" end
    return "civilian"
end

-- ====== 高亮 ======
local function removeAllHighlights(char)
    if not char then return end
    local hl = char:FindFirstChild("HL")
    if hl then hl:Destroy() end
    local head = char:FindFirstChild("Head")
    if head then
        local nt = head:FindFirstChild("NT")
        if nt then nt:Destroy() end
    end
end

local function clearAllHighlights()
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then removeAllHighlights(p.Character) end
    end
end

local function applyHighlight(char, color)
    if not HIGHLIGHT_ENABLED then return end
    if not char then return end
    local hl = char:FindFirstChild("HL")
    if not hl then hl = Instance.new("Highlight"); hl.Name = "HL"; hl.Parent = char end
    hl.FillColor = color; hl.OutlineColor = color
    hl.FillTransparency = 0.5; hl.OutlineTransparency = 0.2
end

local function applyNameTag(char, name, color)
    if not HIGHLIGHT_ENABLED then return end
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

local function processPlayer(p)
    local char = p.Character
    if not char then return end
    if not HIGHLIGHT_ENABLED then removeAllHighlights(char); return end
    local r = scanPlayerTools(p)
    if r == "sheriff" then
        applyHighlight(char, SHERIFF_COLOR); applyNameTag(char, p.Name, SHERIFF_COLOR)
    elseif r == "killer" then
        applyHighlight(char, KILLER_COLOR); applyNameTag(char, p.Name, KILLER_COLOR)
    else
        applyHighlight(char, CIVILIAN_COLOR); applyNameTag(char, p.Name, CIVILIAN_COLOR)
    end
end

local function checkSheriff()
    if not SHERIFF_CHECK_ENABLED then return SHERIFF_EXISTS end
    for _, p in ipairs(Players:GetPlayers()) do
        if scanPlayerTools(p) == "sheriff" then return true end
    end
    return false
end

-- ====== 杀手位置 ======
local function getKillerModel()
    for _, p in ipairs(Players:GetPlayers()) do
        if p == player then continue end
        if scanPlayerTools(p) ~= "killer" then continue end
        local char = p.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            return {model = char, player = p}
        end
        for _, obj in ipairs(Workspace:GetChildren()) do
            if obj:IsA("Model") then
                local name = obj.Name:lower()
                if name:find(p.Name:lower()) or name:find("player") or name:find("killer") then
                    return {model = obj, player = p}
                end
            end
        end
    end
    return nil
end

local function getKillerAimPos()
    local kd = getKillerModel()
    if not kd then return nil end
    local model = kd.model
    local head = model:FindFirstChild("Head")
    if head then return head.Position end
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if hrp then return hrp.Position + Vector3.new(0, 1.5, 0) end
    for _, part in ipairs(model:GetChildren()) do
        if part:IsA("BasePart") then return part.Position end
    end
    return nil
end

-- ====== 射击系统（敌人背后直射） ======

local function findShootEvent()
    local char = player.Character
    if char then
        for _, v in ipairs(char:GetChildren()) do
            if v:IsA("Tool") then
                local shoot = v:FindFirstChild("Shoot") or v:FindFirstChild("ShootEvent")
                if shoot and (shoot:IsA("RemoteEvent") or shoot:IsA("BindableEvent")) then
                    return shoot, v
                end
            end
        end
    end
    local bp = player:FindFirstChild("Backpack")
    if bp then
        for _, v in ipairs(bp:GetChildren()) do
            if v:IsA("Tool") then
                local shoot = v:FindFirstChild("Shoot") or v:FindFirstChild("ShootEvent")
                if shoot and (shoot:IsA("RemoteEvent") or shoot:IsA("BindableEvent")) then
                    return shoot, v
                end
            end
        end
    end
    return nil, nil
end

local function calculateShootPoints(targetPos)
    local root = getRoot()
    if not root then return nil, nil end
    local myPos = root.Position
    local dirFromMe = (targetPos - myPos).Unit
    local shootPos = targetPos + dirFromMe * BEHIND_DISTANCE
    local aimPos = targetPos
    return shootPos, aimPos
end

local function shootAt(targetPos)
    local shoot, gun = findShootEvent()
    if not shoot then
        local bp = player:FindFirstChild("Backpack")
        if bp then
            for _, v in ipairs(bp:GetChildren()) do
                if v:IsA("Tool") and v.Name:lower():find("gun") then
                    local hum = player.Character and player.Character:FindFirstChild("Humanoid")
                    if hum then
                        pcall(function() hum:EquipTool(v) end)
                        task.wait(0.05)
                        break
                    end
                end
            end
        end
        shoot, gun = findShootEvent()
    end
    if not shoot then return false end
    local shootPos, aimPos = calculateShootPoints(targetPos)
    if not shootPos or not aimPos then return false end
    local ok = pcall(function()
        shoot:FireServer(CFrame.new(shootPos), CFrame.new(aimPos))
    end)
    return ok
end

-- ====== 主循环 ======
task.spawn(function()
    task.wait(2)
    while SCRIPT_ENABLED do
        local now = tick()
        currentKillerPos = getKillerAimPos()
        if currentKillerPos and AUTO_SHOOT then
            if now - lastShootTime >= SHOOT_COOLDOWN then
                lastShootTime = now
                shootAt(currentKillerPos)
            end
        end
        task.wait(0)
    end
end)

-- ====== GunDrop ======
local lastGunDropScan = 0

local function onGunDrop(obj)
    if not SCRIPT_ENABLED or not GUNDROP_ENABLED then return end
    local now = tick()
    if now - lastGunDropScan < GUNDROP_SCAN then return end
    lastGunDropScan = now
    task.wait(0.1)
    local pos = getObjPos(obj)
    if not pos then return end
    markOrigin(); goTo(pos); task.wait(0.06); goHome()
end

Workspace.DescendantAdded:Connect(function(obj)
    if not obj or not obj.Name then return end
    if obj.Name:find("GunDrop") then task.spawn(function() onGunDrop(obj) end) end
end)

Workspace.ChildAdded:Connect(function(obj)
    if not obj or not obj.Name then return end
    if obj.Name:find("GunDrop") then task.spawn(function() onGunDrop(obj) end) end
end)

task.spawn(function()
    task.wait(2)
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj.Name:find("GunDrop") then task.spawn(function() onGunDrop(obj) end) end
    end
end)

-- ====== 扫描主循环 ======
task.spawn(function()
    task.wait(2)
    while SCRIPT_ENABLED do
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

player.CharacterAdded:Connect(function() ORIGIN = nil; lastShootTime = 0 end)

-- ==========================================
-- UI（右上角 + 展开在左边）
-- ==========================================
local sg = Instance.new("ScreenGui")
sg.Name = "UI"; sg.ResetOnSpawn = false; sg.IgnoreGuiInset = true
sg.Parent = player:WaitForChild("PlayerGui")

-- 拖动逻辑
local function makeDraggable(frame)
    local dragging = false
    local dragStart = nil
    local startPos = nil
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    frame.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

-- 获取屏幕尺寸
local viewportSize = Workspace.CurrentCamera.ViewportSize
local screenW = viewportSize.X
local screenH = viewportSize.Y

-- ====== 收起按钮（右上角偏下） ======
local collapsedBtn = Instance.new("TextButton")
collapsedBtn.Size = UDim2.new(0, 120, 0, 28)
collapsedBtn.Position = UDim2.new(0, screenW - 130, 0, 40)  -- 右上角，距右10，距顶40
collapsedBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
collapsedBtn.BackgroundTransparency = 0.3  -- 半透明
collapsedBtn.Text = "☰ 展开"
collapsedBtn.TextColor3 = Color3.fromRGB(255, 255, 255)  -- 字体不透明
collapsedBtn.TextTransparency = 0
collapsedBtn.TextScaled = true
collapsedBtn.Font = Enum.Font.GothamBold
collapsedBtn.BorderSizePixel = 0
collapsedBtn.Active = true
collapsedBtn.Parent = sg
makeDraggable(collapsedBtn)

local uic_cb = Instance.new("UICorner")
uic_cb.CornerRadius = UDim.new(0, 6)
uic_cb.Parent = collapsedBtn

-- ====== 展开面板（在收起按钮左边） ======
local panelW = 240
local panelH = 280
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, panelW, 0, panelH)
-- 位置：收起按钮左边
panel.Position = UDim2.new(0, screenW - 130 - panelW - 10, 0, 40)
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
panel.BackgroundTransparency = 0.35  -- 半透明
panel.BorderSizePixel = 0
panel.Active = true
panel.Visible = false
panel.Parent = sg
makeDraggable(panel)

local uic_panel = Instance.new("UICorner")
uic_panel.CornerRadius = UDim.new(0, 10)
uic_panel.Parent = panel

-- 拖动手柄
local dragHandle = Instance.new("Frame")
dragHandle.Size = UDim2.new(1, 0, 0, 24)
dragHandle.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
dragHandle.BackgroundTransparency = 0.3
dragHandle.BorderSizePixel = 0
dragHandle.Parent = panel
makeDraggable(dragHandle)

local uic_dh = Instance.new("UICorner")
uic_dh.CornerRadius = UDim.new(0, 8)
uic_dh.Parent = dragHandle

local handleText = Instance.new("TextLabel")
handleText.Size = UDim2.new(1, -50, 1, 0)
handleText.Position = UDim2.new(0, 6, 0, 0)
handleText.BackgroundTransparency = 1
handleText.Text = "≡ 破坏者谜团2"
handleText.TextColor3 = Color3.fromRGB(255, 210, 80)
handleText.TextTransparency = 0  -- 不透明
handleText.TextScaled = true
handleText.Font = Enum.Font.GothamBold
handleText.TextXAlignment = Enum.TextXAlignment.Left
handleText.Parent = dragHandle

-- 收起按钮（面板上的）
local collapseBtn = Instance.new("TextButton")
collapseBtn.Size = UDim2.new(0, 26, 0, 20)
collapseBtn.Position = UDim2.new(1, -30, 0, 2)
collapseBtn.BackgroundColor3 = Color3.fromRGB(100, 60, 60)
collapseBtn.BackgroundTransparency = 0
collapseBtn.Text = "✕"
collapseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
collapseBtn.TextTransparency = 0
collapseBtn.TextScaled = true
collapseBtn.Font = Enum.Font.GothamBold
collapseBtn.BorderSizePixel = 0
collapseBtn.Parent = dragHandle

local uic_col = Instance.new("UICorner")
uic_col.CornerRadius = UDim.new(0, 4)
uic_col.Parent = collapseBtn

-- 状态信息区
local infoY = 28
local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, -10, 0, 14)
statusLbl.Position = UDim2.new(0, 5, 0, infoY)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = "● 运行中"
statusLbl.TextColor3 = Color3.fromRGB(144, 238, 144)
statusLbl.TextTransparency = 0
statusLbl.TextScaled = true
statusLbl.Font = Enum.Font.GothamSemibold
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Parent = panel

local targetLbl = Instance.new("TextLabel")
targetLbl.Size = UDim2.new(1, -10, 0, 14)
targetLbl.Position = UDim2.new(0, 5, 0, infoY + 14)
targetLbl.BackgroundTransparency = 1
targetLbl.Text = "目标: 无"
targetLbl.TextColor3 = Color3.fromRGB(180, 180, 180)
targetLbl.TextTransparency = 0
targetLbl.TextScaled = true
targetLbl.Font = Enum.Font.GothamSemibold
targetLbl.TextXAlignment = Enum.TextXAlignment.Left
targetLbl.Parent = panel

local sheriffLbl = Instance.new("TextLabel")
sheriffLbl.Size = UDim2.new(1, -10, 0, 14)
sheriffLbl.Position = UDim2.new(0, 5, 0, infoY + 28)
sheriffLbl.BackgroundTransparency = 1
sheriffLbl.Text = "警长: 检测中..."
sheriffLbl.TextColor3 = Color3.fromRGB(180, 200, 255)
sheriffLbl.TextTransparency = 0
sheriffLbl.TextScaled = true
sheriffLbl.Font = Enum.Font.GothamSemibold
sheriffLbl.TextXAlignment = Enum.TextXAlignment.Left
sheriffLbl.Parent = panel

local originLbl = Instance.new("TextLabel")
originLbl.Size = UDim2.new(1, -10, 0, 14)
originLbl.Position = UDim2.new(0, 5, 0, infoY + 42)
originLbl.BackgroundTransparency = 1
originLbl.Text = "原点: 无"
originLbl.TextColor3 = Color3.fromRGB(180, 180, 180)
originLbl.TextTransparency = 0
originLbl.TextScaled = true
originLbl.Font = Enum.Font.GothamSemibold
originLbl.TextXAlignment = Enum.TextXAlignment.Left
originLbl.Parent = panel

-- 分隔线
local sep = Instance.new("Frame")
sep.Size = UDim2.new(1, -10, 0, 1)
sep.Position = UDim2.new(0, 5, 0, infoY + 58)
sep.BackgroundColor3 = Color3.fromRGB(80, 85, 95)
sep.BackgroundTransparency = 0.5
sep.BorderSizePixel = 0
sep.Parent = panel

-- ====== 开关列表 ======
local switchStartY = infoY + 62

local function createSwitch(parent, yPos, label, state, callback)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -10, 0, 26)
    row.Position = UDim2.new(0, 5, 0, yPos)
    row.BackgroundTransparency = 1
    row.Parent = parent
    
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.58, -4, 1, 0)
    lbl.Position = UDim2.new(0, 0, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = Color3.fromRGB(240, 240, 245)  -- 接近白色，不透明
    lbl.TextTransparency = 0
    lbl.TextScaled = true
    lbl.Font = Enum.Font.GothamSemibold
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row
    
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.35, 0, 0, 20)
    btn.Position = UDim2.new(0.65, 0, 0, 3)
    btn.BackgroundColor3 = state and Color3.fromRGB(46, 153, 89) or Color3.fromRGB(100, 100, 110)
    btn.BackgroundTransparency = 0  -- 按钮不透明
    btn.Text = state and "ON" or "OFF"
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextTransparency = 0
    btn.TextScaled = true
    btn.Font = Enum.Font.GothamBold
    btn.BorderSizePixel = 0
    btn.Parent = row
    
    local uicb = Instance.new("UICorner")
    uicb.CornerRadius = UDim.new(0, 4)
    uicb.Parent = btn
    
    btn.MouseButton1Click:Connect(function()
        state = not state
        btn.BackgroundColor3 = state and Color3.fromRGB(46, 153, 89) or Color3.fromRGB(100, 100, 110)
        btn.Text = state and "ON" or "OFF"
        if callback then callback(state) end
    end)
    
    return {getState = function() return state end}
end

createSwitch(panel, switchStartY, "自动射击", AUTO_SHOOT, function(s)
    AUTO_SHOOT = s
end)

createSwitch(panel, switchStartY + 28, "高亮显示", HIGHLIGHT_ENABLED, function(s)
    HIGHLIGHT_ENABLED = s
    if not s then clearAllHighlights() end
end)

createSwitch(panel, switchStartY + 56, "GunDrop拾取", GUNDROP_ENABLED, function(s)
    GUNDROP_ENABLED = s
end)

createSwitch(panel, switchStartY + 84, "警长检测", SHERIFF_CHECK_ENABLED, function(s)
    SHERIFF_CHECK_ENABLED = s
end)

-- 分隔线2
local sep2 = Instance.new("Frame")
sep2.Size = UDim2.new(1, -10, 0, 1)
sep2.Position = UDim2.new(0, 5, 0, switchStartY + 116)
sep2.BackgroundColor3 = Color3.fromRGB(80, 85, 95)
sep2.BackgroundTransparency = 0.5
sep2.BorderSizePixel = 0
sep2.Parent = panel

-- 标记原点 + 传送
local markBtn = Instance.new("TextButton")
markBtn.Size = UDim2.new(0.46, -4, 0, 20)
markBtn.Position = UDim2.new(0, 5, 0, switchStartY + 120)
markBtn.BackgroundColor3 = Color3.fromRGB(50, 110, 75)
markBtn.BackgroundTransparency = 0
markBtn.Text = "📍 标记原点"
markBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
markBtn.TextTransparency = 0
markBtn.TextScaled = true
markBtn.Font = Enum.Font.GothamSemibold
markBtn.BorderSizePixel = 0
markBtn.Parent = panel

local uic_mark = Instance.new("UICorner")
uic_mark.CornerRadius = UDim.new(0, 4)
uic_mark.Parent = markBtn

markBtn.MouseButton1Click:Connect(function()
    if markOrigin() then
        originLbl.Text = "原点: ✓"
        originLbl.TextColor3 = Color3.fromRGB(100, 225, 98)
    end
end)

local tpBtn = Instance.new("TextButton")
tpBtn.Size = UDim2.new(0.46, -4, 0, 20)
tpBtn.Position = UDim2.new(0.54, 0, 0, switchStartY + 120)
tpBtn.BackgroundColor3 = Color3.fromRGB(55, 90, 120)
tpBtn.BackgroundTransparency = 0
tpBtn.Text = "🏠 传送原点"
tpBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
tpBtn.TextTransparency = 0
tpBtn.TextScaled = true
tpBtn.Font = Enum.Font.GothamSemibold
tpBtn.BorderSizePixel = 0
tpBtn.Parent = panel

local uic_tp = Instance.new("UICorner")
uic_tp.CornerRadius = UDim.new(0, 4)
uic_tp.Parent = tpBtn

tpBtn.MouseButton1Click:Connect(function() goHome() end)

-- 分隔线3
local sep3 = Instance.new("Frame")
sep3.Size = UDim2.new(1, -10, 0, 1)
sep3.Position = UDim2.new(0, 5, 0, switchStartY + 145)
sep3.BackgroundColor3 = Color3.fromRGB(80, 85, 95)
sep3.BackgroundTransparency = 0.5
sep3.BorderSizePixel = 0
sep3.Parent = panel

-- 关闭脚本按钮
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(1, -10, 0, 24)
closeBtn.Position = UDim2.new(0, 5, 0, switchStartY + 148)
closeBtn.BackgroundColor3 = Color3.fromRGB(170, 50, 50)
closeBtn.BackgroundTransparency = 0
closeBtn.Text = "⚠ 关闭脚本"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.TextTransparency = 0
closeBtn.TextScaled = true
closeBtn.Font = Enum.Font.GothamBold
closeBtn.BorderSizePixel = 0
closeBtn.Parent = panel

local uic_close = Instance.new("UICorner")
uic_close.CornerRadius = UDim.new(0, 5)
uic_close.Parent = closeBtn

-- 确认框
local confirmFrame = Instance.new("Frame")
confirmFrame.Size = UDim2.new(0, 210, 0, 90)
confirmFrame.Position = UDim2.new(0.5, -105, 0.5, -45)
confirmFrame.BackgroundColor3 = Color3.fromRGB(140, 40, 40)
confirmFrame.BackgroundTransparency = 0.15
confirmFrame.BorderSizePixel = 0
confirmFrame.Visible = false
confirmFrame.Parent = panel

local uic_conf = Instance.new("UICorner")
uic_conf.CornerRadius = UDim.new(0, 8)
uic_conf.Parent = confirmFrame

local confText = Instance.new("TextLabel")
confText.Size = UDim2.new(1, -10, 0, 24)
confText.Position = UDim2.new(0, 5, 0, 8)
confText.BackgroundTransparency = 1
confText.Text = "确认关闭所有功能？"
confText.TextColor3 = Color3.fromRGB(255, 255, 255)
confText.TextTransparency = 0
confText.TextScaled = true
confText.Font = Enum.Font.GothamBold
confText.Parent = confirmFrame

local yesBtn = Instance.new("TextButton")
yesBtn.Size = UDim2.new(0.4, -4, 0, 28)
yesBtn.Position = UDim2.new(0.05, 0, 0, 40)
yesBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
yesBtn.BackgroundTransparency = 0
yesBtn.Text = "确认"
yesBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
yesBtn.TextTransparency = 0
yesBtn.TextScaled = true
yesBtn.Font = Enum.Font.GothamBold
yesBtn.BorderSizePixel = 0
yesBtn.Parent = confirmFrame

local uic_yes = Instance.new("UICorner")
uic_yes.CornerRadius = UDim.new(0, 5)
uic_yes.Parent = yesBtn

local noBtn = Instance.new("TextButton")
noBtn.Size = UDim2.new(0.4, -4, 0, 28)
noBtn.Position = UDim2.new(0.55, 0, 0, 40)
noBtn.BackgroundColor3 = Color3.fromRGB(70, 100, 130)
noBtn.BackgroundTransparency = 0
noBtn.Text = "取消"
noBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
noBtn.TextTransparency = 0
noBtn.TextScaled = true
noBtn.Font = Enum.Font.GothamBold
noBtn.BorderSizePixel = 0
noBtn.Parent = confirmFrame

local uic_no = Instance.new("UICorner")
uic_no.CornerRadius = UDim.new(0, 5)
uic_no.Parent = noBtn

-- ====== 展开/收起逻辑 ======
collapsedBtn.MouseButton1Click:Connect(function()
    panel.Visible = true
    collapsedBtn.Visible = false
end)

collapseBtn.MouseButton1Click:Connect(function()
    panel.Visible = false
    collapsedBtn.Visible = true
end)

closeBtn.MouseButton1Click:Connect(function()
    confirmFrame.Visible = true
end)

yesBtn.MouseButton1Click:Connect(function()
    SCRIPT_ENABLED = false
    clearAllHighlights()
    if sg then sg:Destroy() end
    print("[❌] 破坏者谜团2 已关闭并清理")
end)

noBtn.MouseButton1Click:Connect(function()
    confirmFrame.Visible = false
end)

-- ====== UI 信息更新 ======
task.spawn(function()
    while SCRIPT_ENABLED and sg and sg.Parent do
        task.wait(0.1)
        
        if AUTO_SHOOT then
            statusLbl.Text = "● 运行中"
            statusLbl.TextColor3 = Color3.fromRGB(144, 238, 144)
        else
            statusLbl.Text = "● 暂停"
            statusLbl.TextColor3 = Color3.fromRGB(255, 200, 100)
        end
        
        if SHERIFF_EXISTS then
            sheriffLbl.Text = "警长: ✅"
            sheriffLbl.TextColor3 = Color3.fromRGB(100, 200, 255)
        else
            sheriffLbl.Text = "警长: ❌"
            sheriffLbl.TextColor3 = Color3.fromRGB(255, 200, 100)
        end
        
        if currentKillerPos then
            local kd = getKillerModel()
            if kd then
                targetLbl.Text = "目标: " .. kd.player.Name
                targetLbl.TextColor3 = Color3.fromRGB(255, 100, 100)
            end
        else
            targetLbl.Text = "目标: 无"
            targetLbl.TextColor3 = Color3.fromRGB(180, 180, 180)
        end
        
        local root = getRoot()
        if ORIGIN then
            originLbl.Text = "原点: ✓"
            originLbl.TextColor3 = Color3.fromRGB(100, 225, 98)
        else
            originLbl.Text = "原点: 无"
            originLbl.TextColor3 = Color3.fromRGB(180, 180, 180)
        end
    end
end)

print("[✅] 破坏者谜团2 加载完成")
print("[🔫] 射击模式: 敌人背后直射")
print("[📋] UI: 右上角按钮 → 左边展开面板")
