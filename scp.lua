local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local channel = ReplicatedStorage:WaitForChild("Libraries"):WaitForChild("Network"):WaitForChild("Channel")
local shootEvent = channel:WaitForChild("tool/shoot")
local soundEvent = channel:WaitForChild("tool/sound")

-- ====== 阵营分组 ======
local FOUNDATION = { scientist = true, security = true, mtf = true, director = true }
local INSURGENCY = { d_class = true, escaped_d = true, chaos_insurgency = true }

-- ====== 白名单 ======
local Whitelist = {}

local function addWhitelist(name)
    if not name or name == "" then return end
    Whitelist[name] = true
    warn("[🟢] 白名单+: " .. name)
end

local function removeWhitelist(name)
    Whitelist[name] = nil
    warn("[🔴] 白名单-: " .. name)
end

local function isWhitelisted(p)
    return p and Whitelist[p.Name] or false
end

-- ====== 配置 ======
local weaponId = nil
local maxRange = 5000
local fireInterval = 0.05
local autoShootEnabled = true
local drawTrajectory = true

-- ====== Role 读取 ======
local myRole = nil

local function getPlayerRole(p)
    if not p then return nil end
    return p:GetAttribute("Role")
end

local function updateMyRole()
    local r = getPlayerRole(player)
    if r ~= myRole then
        myRole = r
        warn("[👤] 我的Role: " .. tostring(myRole or "无"))
    end
end

updateMyRole()

-- ====== D级违规检查 ======
local function checkDClassHostile(targetPlayer)
    if not targetPlayer then return false end
    
    local success, result = pcall(function()
        local char = targetPlayer.Character
        if not char then return false end
        
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end
        
        local tag = hrp:FindFirstChild("Tag")
        if not tag then return false end
        
        local wrapper = tag:FindFirstChild("Wrapper")
        if not wrapper then return false end
        
        local hostile = wrapper:FindFirstChild("Hostile")
        if not hostile then return false end
        
        if hostile:IsA("TextLabel") or hostile:IsA("ImageLabel") then
            return hostile.Visible == true
        end
        
        return false
    end)
    
    if success then
        return result
    end
    return false
end

-- ====== 敌人判定 ======
local function isEnemy(target)
    if not target or target == player then return false end
    if isWhitelisted(target) then return false end

    local tr = getPlayerRole(target)
    if not tr or tr == "" then return false end
    
    -- 异常 → 直接击毙
    if tr == "anomaly" then return true end
    if not myRole then return false end
    if myRole == "anomaly" then return true end
    
    -- 同Role → 不打
    if tr == myRole then return false end

    -- 混沌、出逃D级 → 直接击毙
    if INSURGENCY[tr] and tr ~= "d_class" then
        if FOUNDATION[myRole] then return true end
    end

    -- 普通D级 → 检查 Hostile 是否勾选
    if tr == "d_class" and FOUNDATION[myRole] then
        local hostileCheck = checkDClassHostile(target)
        if hostileCheck == true then
            return true  -- 违规D级，击杀
        else
            return false -- 没违规，不打
        end
    end

    -- 基金会 vs 反基金会
    if FOUNDATION[myRole] and INSURGENCY[tr] then return true end
    if INSURGENCY[myRole] and FOUNDATION[tr] then return true end

    return false
end

-- ====== 弹道可视化 ======
local function drawLine(origin, hitPos)
    if not drawTrajectory then return end
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.Material = Enum.Material.Neon
    part.Color = Color3.fromRGB(255, 50, 50)
    part.Transparency = 0.3
    part.Size = Vector3.new(0.15, 0.15, (hitPos - origin).Magnitude)
    part.CFrame = CFrame.new(origin, hitPos) * CFrame.new(0, 0, -part.Size.Z / 2)
    part.Parent = Workspace
    task.spawn(function()
        task.wait(0.3)
        if part then part:Destroy() end
    end)
end

-- ====== 获取枪口位置 ======
local function getMuzzlePosition()
    local bp = player:FindFirstChild("Backpack")
    local weapon = bp and bp:FindFirstChildOfClass("Tool")
    if not weapon then
        weapon = player.Character and player.Character:FindFirstChildOfClass("Tool")
    end
    if weapon then
        local muzzle = weapon:FindFirstChild("Muzzle") or
                       weapon:FindFirstChild("Barrel") or
                       weapon:FindFirstChild("Handle")
        if muzzle then
            return muzzle.Position + muzzle.CFrame.LookVector * 2
        end
    end
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    return root and root.Position
end

-- ====== 射线检测（不穿墙）======
local function canSeeTarget(from, to)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {player.Character}
    params.IgnoreWater = true

    local direction = (to - from).Unit * maxRange
    local result = Workspace:Raycast(from, direction, params)

    if result then
        local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
        if hitModel and hitModel:FindFirstChild("Humanoid") then
            return true, result.Position, hitModel
        end
    end
    return false, nil, nil
end

-- ====== 获取可见敌人 ======
local function getVisibleEnemies()
    local enemies = {}
    local origin = getMuzzlePosition()
    if not origin then return enemies end

    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player and otherPlayer.Character then
            local head = otherPlayer.Character:FindFirstChild("Head")
            local humanoid = otherPlayer.Character:FindFirstChildOfClass("Humanoid")
            if head and humanoid and humanoid.Health > 0 then
                if isEnemy(otherPlayer) then
                    local visible, hitPos, hitModel = canSeeTarget(origin, head.Position)
                    if visible and hitModel == otherPlayer.Character then
                        table.insert(enemies, {
                            player = otherPlayer,
                            model = otherPlayer.Character,
                            head = head,
                            hitPos = hitPos,
                            distance = (head.Position - origin).Magnitude
                        })
                    end
                end
            end
        end
    end

    table.sort(enemies, function(a, b) return a.distance < b.distance end)
    return enemies
end

-- ====== 发送射击 ======
local function fireAt(target)
    local origin = getMuzzlePosition()
    if not origin or not weaponId then return end

    local direction = (target.hitPos - origin).Unit * 700

    pcall(function()
        shootEvent:FireServer(weaponId, {{
            normal = Vector3.new(0, 1, 0),
            direction = direction,
            origin = origin,
            instance = target.head,
            points = {},
            position = target.hitPos
        }})
    end)

    pcall(function()
        soundEvent:FireServer(weaponId, "FIRE")
    end)

    drawLine(origin, target.hitPos)
end

-- ====== Hook捕获武器ID ======
local mt = getrawmetatable(shootEvent) or getmetatable(shootEvent)
if mt and mt.__namecall then
    local oldNamecall = mt.__namecall
    setreadonly(mt, false)
    mt.__namecall = function(self, ...)
        local method = getnamecallmethod()
        if method == "FireServer" and self == shootEvent then
            local args = {...}
            if args[1] and type(args[1]) == "string" and #args[1] == 36 then
                if weaponId ~= args[1] then
                    weaponId = args[1]
                    warn("[✅] 武器ID: " .. weaponId)
                end
            end
        end
        return oldNamecall(self, ...)
    end
    setreadonly(mt, true)
end

-- ============================================================
--  UI 控制面板
-- ============================================================
local pg = player:WaitForChild("PlayerGui", 10)

local sg = Instance.new("ScreenGui")
sg.Name = "AutoShootUI"
sg.ResetOnSpawn = false
sg.Enabled = true
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent = pg

local mf = Instance.new("Frame")
mf.Size = UDim2.new(0, 380, 0, 490)
mf.Position = UDim2.new(0, 20, 0, 80)
mf.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
mf.BorderSizePixel = 0
mf.Active = true
mf.Draggable = true
mf.Visible = true
mf.Parent = sg

local mc = Instance.new("UICorner")
mc.CornerRadius = UDim.new(0, 8)
mc.Parent = mf

-- 标题栏
local tb = Instance.new("Frame")
tb.Size = UDim2.new(1, 0, 0, 34)
tb.BackgroundColor3 = Color3.fromRGB(45, 45, 66)
tb.BorderSizePixel = 0
tb.Parent = mf
local tbc = Instance.new("UICorner")
tbc.CornerRadius = UDim.new(0, 8)
tbc.Parent = tb

local tl = Instance.new("TextLabel")
tl.Size = UDim2.new(1, -40, 1, 0)
tl.Position = UDim2.new(0, 10, 0, 0)
tl.BackgroundTransparency = 1
tl.Text = "🎯 自动射击 v3 (D级违规检测)"
tl.TextColor3 = Color3.new(1,1,1)
tl.Font = Enum.Font.GothamBold
tl.TextSize = 14
tl.TextXAlignment = Enum.TextXAlignment.Left
tl.Parent = tb

-- 状态标签
local sl = Instance.new("TextLabel")
sl.Size = UDim2.new(1, -16, 0, 90)
sl.Position = UDim2.new(0, 8, 0, 42)
sl.BackgroundColor3 = Color3.fromRGB(35, 35, 52)
sl.Text = "加载中..."
sl.TextColor3 = Color3.fromRGB(214,213,219)
sl.Font = Enum.Font.Gotham
sl.TextSize = 12
sl.TextXAlignment = Enum.TextXAlignment.Left
sl.TextYAlignment = Enum.TextYAlignment.Top
sl.Parent = mf
local slc = Instance.new("UICorner")
slc.CornerRadius = UDim.new(0, 6)
slc.Parent = sl

-- 射击开关
local tBtn = Instance.new("TextButton")
tBtn.Size = UDim2.new(0.452, 0, 0, 30)
tBtn.Position = UDim2.new(0.023, 0, 0, 142)
tBtn.BackgroundColor3 = Color3.fromRGB(57, 171, 62)
tBtn.Text = "⚙️ 射击: 开启"
tBtn.TextColor3 = Color3.new(1,1,1)
tBtn.Font = Enum.Font.GothamBold
tBtn.TextSize = 12
tBtn.Parent = mf
local tBtnc = Instance.new("UICorner")
tBtnc.CornerRadius = UDim.new(0, 6)
tBtnc.Parent = tBtn
tBtn.MouseButton1Click:Connect(function()
    autoShootEnabled = not autoShootEnabled
    tBtn.Text = autoShootEnabled and "⚙️ 射击: 开启" or "⚙️ 射击: 关闭"
    tBtn.BackgroundColor3 = autoShootEnabled and Color3.fromRGB(57,171,62) or Color3.fromRGB(174,53,53)
end)

-- 弹道开关
local bBtn = Instance.new("TextButton")
bBtn.Size = UDim2.new(0.458, 0, 0, 30)
bBtn.Position = UDim2.new(0.504, 0, 0, 141)
bBtn.BackgroundColor3 = Color3.fromRGB(61, 146, 196)
bBtn.Text = "👁️ 弹道: 开启"
bBtn.TextColor3 = Color3.new(1,1,1)
bBtn.Font = Enum.Font.GothamBold
bBtn.TextSize = 12
bBtn.Parent = mf
local bBtnc = Instance.new("UICorner")
bBtnc.CornerRadius = UDim.new(0, 6)
bBtnc.Parent = bBtn
bBtn.MouseButton1Click:Connect(function()
    drawTrajectory = not drawTrajectory
    bBtn.Text = drawTrajectory and "👁️ 弹道: 开启" or "👁️ 弹道: 关闭"
    bBtn.BackgroundColor3 = drawTrajectory and Color3.fromRGB(61,146,196) or Color3.fromRGB(156,63,67)
end)

-- 输入框
local nb = Instance.new("TextBox")
nb.Size = UDim2.new(0.615, 0, 0, 28)
nb.Position = UDim2.new(0.021, 0, 0, 188)
nb.BackgroundColor3 = Color3.fromRGB(51, 51, 73)
nb.Text = ""
nb.PlaceholderText = "输入玩家名称..."
nb.PlaceholderColor3 = Color3.fromRGB(138,137,141)
nb.TextColor3 = Color3.new(1,1,1)
nb.Font = Enum.Font.Gotham
nb.TextSize = 12
nb.Parent = mf
local nbc = Instance.new("UICorner")
nbc.CornerRadius = UDim.new(0, 4)
nbc.Parent = nb

-- 加入按钮
local ab = Instance.new("TextButton")
ab.Size = UDim2.new(0.305, 0, 0, 28)
ab.Position = UDim2.new(0.664, 0, 0, 187)
ab.BackgroundColor3 = Color3.fromRGB(58, 136, 213)
ab.Text = "➕ 加入"
ab.TextColor3 = Color3.new(1,1,1)
ab.Font = Enum.Font.GothamBold
ab.TextSize = 12
ab.Parent = mf
local abc = Instance.new("UICorner")
abc.CornerRadius = UDim.new(0, 4)
abc.Parent = ab

ab.MouseButton1Click:Connect(function()
    local nm = nb.Text
    if nm and nm ~= "" then
        addWhitelist(nm)
        nb.Text = ""
    end
end)

nb.FocusLost:Connect(function(ep)
    if ep then
        local nm = nb.Text
        if nm and nm ~= "" then
            addWhitelist(nm)
            nb.Text = ""
        end
    end
end)

-- 白名单友方
local fb = Instance.new("TextButton")
fb.Size = UDim2.new(0.392, 0, 0, 24)
fb.Position = UDim2.new(0.034, 0, 0, 228)
fb.BackgroundColor3 = Color3.fromRGB(54, 126, 191)
fb.Text = "🛡️ 白名单友方"
fb.TextColor3 = Color3.new(1,1,1)
fb.Font = Enum.Font.GothamBold
fb.TextSize = 11
fb.Parent = mf
local fbc = Instance.new("UICorner")
fbc.CornerRadius = UDim.new(0, 4)
fbc.Parent = fb
fb.MouseButton1Click:Connect(function()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then
            local r = getPlayerRole(p)
            if r and myRole then
                if r == myRole or (FOUNDATION[myRole] and FOUNDATION[r]) or (INSURGENCY[myRole] and INSURGENCY[r]) then
                    addWhitelist(p.Name)
                end
            end
        end
    end
    warn("[✅] 友方已加入白名单")
end)

-- 清空
local cb = Instance.new("TextButton")
cb.Size = UDim2.new(0.558, 0, 0, 24)
cb.Position = UDim2.new(0.433, 0, 0, 227)
cb.BackgroundColor3 = Color3.fromRGB(161, 52, 48)
cb.Text = "🗑️ 清空白名单"
cb.TextColor3 = Color3.new(1,1,1)
cb.Font = Enum.Font.GothamBold
cb.TextSize = 11
cb.Parent = mf
local cbc = Instance.new("UICorner")
cbc.CornerRadius = UDim.new(0, 4)
cbc.Parent = cb
cb.MouseButton1Click:Connect(function()
    for n, _ in pairs(Whitelist) do Whitelist[n] = nil end
    warn("[🗑️] 白名单已清空")
end)

-- 玩家列表
local pl = Instance.new("TextLabel")
pl.Size = UDim2.new(1, -18, 0, 205)
pl.Position = UDim2.new(0, 9, 0, 264)
pl.BackgroundColor3 = Color3.fromRGB(29, 29, 44)
pl.Text = "等待扫描..."
pl.TextColor3 = Color3.fromRGB(186,185,189)
pl.Font = Enum.Font.Gotham
pl.TextSize = 11
pl.TextXAlignment = Enum.TextXAlignment.Left
pl.TextYAlignment = Enum.TextYAlignment.Top
pl.TextWrapped = true
pl.Parent = mf
local plc = Instance.new("UICorner")
plc.CornerRadius = UDim.new(0, 6)
plc.Parent = pl

-- ============================================================
--  循环1: 每秒扫描 + 刷新UI
-- ============================================================
task.spawn(function()
    while true do
        task.wait(1)
        pcall(function()
            updateMyRole()
            local ec, fc, wc = 0, 0, 0
            local txt = ""
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= player then
                    local r = getPlayerRole(p) or "未进入"
                    local pre = "⚪"
                    
                    if isWhitelisted(p) then
                        wc = wc+1
                        pre = "🔵"
                    elseif isEnemy(p) then
                        ec = ec+1
                        -- 如果是D级违规，加标记
                        if r == "d_class" then
                            pre = "⚠️"
                        else
                            pre = "🔴"
                        end
                    else
                        fc = fc+1
                        pre = "🟢"
                    end
                    txt = txt .. string.format("%s %s [%s]\n", pre, p.Name, r)
                end
            end
            sl.Text = string.format("我的Role: %s\n友方: %d | 敌人: %d | 白名单: %d\n武器ID: %s",
                tostring(myRole or "无"), fc, ec, wc, weaponId or "等待捕获")
            pl.Text = txt
        end)
    end
end)

-- ============================================================
--  循环2: 玩家进出
-- ============================================================
Players.PlayerAdded:Connect(function(p)
    task.wait(0.5)
    warn("[➕] 加入: " .. p.Name)
end)
Players.PlayerRemoving:Connect(function(p)
    removeWhitelist(p.Name)
end)

-- ============================================================
--  循环3: 射击
-- ============================================================
local lastFire = 0
RunService.Heartbeat:Connect(function()
    if not autoShootEnabled then return end
    if not weaponId then
        local bp = player:FindFirstChild("Backpack")
        local w = bp and bp:FindFirstChildOfClass("Tool") or (player.Character and player.Character:FindFirstChildOfClass("Tool"))
        if w then
            for _, c in ipairs(w:GetDescendants()) do
                if c:IsA("StringValue") and c.Value and #c.Value == 36 then
                    weaponId = c.Value
                    warn("[✅] 武器ID: " .. weaponId)
                    break
                end
            end
        end
        return
    end
    if tick() - lastFire < fireInterval then return end
    local ch = player.Character
    if not ch then return end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end
    local enemies = getVisibleEnemies()
    if #enemies == 0 then return end
    fireAt(enemies[1])
    lastFire = tick()
end)

-- ============================================================
--  初始化
-- ============================================================
player.CharacterAdded:Connect(function()
    task.wait(0.5)
    updateMyRole()
end)

warn([[
[🚀] === 自动射击 v3 已启动 ===
[🎯] D级违规检测: Hostile.Visible == true 时击杀
[🎯] 混沌/出逃D级: 直接击毙
[🎯] 异常: 直接击毙
]])
