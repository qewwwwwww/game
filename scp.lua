-- ============================================================
--  SCP异常站点 v2.0 - 全武器战斗系统
--  功能：自动射击 + 自动近战 + 显示弹道 + 范围圆圈 + 透视 + 穿门
--  阵营逻辑：D级只攻基金会 | 违规=Hostile可见 | 逃出=Escaped可见
--  UI：手机端自动缩小 | 点击输入距离 | 自动扫描武器 | 透视分色
-- ============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- ==================== 网络事件 ====================
local Libraries = ReplicatedStorage:FindFirstChild("Libraries")
local Network = Libraries and Libraries:FindFirstChild("Network")
local Channel = Network and Network:FindFirstChild("Channel")
local ShootEvent = Channel and Channel:FindFirstChild("tool/shoot")
local AttackEvent = Channel and Channel:FindFirstChild("tool/attack")
local SoundEvent = Channel and Channel:FindFirstChild("tool/sound")

-- ==================== 设备检测 ====================
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- ==================== 配置（运行时可改） ====================
local MAX_RANGE = 180
local MELEE_RANGE = 5
local SHOOT_CD = 0.040
local MELEE_CD = 0.370

-- ==================== 开关状态 ====================
local autoShoot = true
local autoMelee = true
local rayEnabled = true
local drawVis = true
local drawCircle = true
local espEnabled = true
local DoorSysEnabled = true

-- ==================== 阵营常量 ====================
local FOUNDATION = { scientist = true, security = true, mtf = true, director = true }
local CHAOS = { chaos_insurgency = true, rogue_agent = true, traitor = true, renegade = true }
local DCLASS = { d_class = true, escaped_d = true, escaped_d_class = true }

-- ==================== 白名单 ====================
local WL = {}
local function isWL(p) return p and WL[p.Name] or false end
local function addWL(n) if n and n ~= "" then WL[n] = true end end

-- ==================== 角色系统 ====================
local myRole = nil
local function GetRole(p) return p and p:GetAttribute("Role") or nil end

local function UpdateMyRole()
    local r = GetRole(player)
    myRole = r
end
UpdateMyRole()
player:GetAttributeChangedSignal("Role"):Connect(UpdateMyRole)

-- ==================== 敌对判定 ====================
-- D级：只攻基金会，不攻任何D级（无论违规/逃出/正常）
-- 非D级：攻敌对阵营 + 攻违规D级(Hostile可见) + 攻逃出D级(Escaped可见)
local function IsEnemy(p)
    if not p or p == player then return false end
    if isWL(p) then return false end

    local tr = GetRole(p)
    if not tr or tr == "" then return false end

    -- 异常实体互敌
    if tr == "anomaly" or myRole == "anomaly" then return true end
    -- 同阵营不互攻
    if tr == myRole then return false end

    -- 基金会视角
    if FOUNDATION[myRole] then
        if CHAOS[tr] then return true end
        -- D级由下方标签补充判定
        return false
    end

    -- 混沌视角
    if CHAOS[myRole] then
        if FOUNDATION[tr] then return true end
        -- D级由下方标签补充判定
        return false
    end

    -- D级视角：只攻基金会，不攻混沌，不攻任何D级
    if DCLASS[myRole] then
        if FOUNDATION[tr] then return true end
        return false
    end

    return false
end

-- ==================== 违规/逃出判定（基于Tag.Wrapper UI标签Visible） ====================
local function GetTagWrapper(p)
    if not p or not p.Character then return nil end
    local hrp = p.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local tag = hrp:FindFirstChild("Tag")
    if not tag then return nil end
    return tag:FindFirstChild("Wrapper")
end

local function IsHostile(p)
    local wrapper = GetTagWrapper(p)
    if not wrapper then return false end
    local hostile = wrapper:FindFirstChild("Hostile")
    if not hostile then return false end
    if hostile:IsA("GuiObject") then return hostile.Visible end
    local ok, v = pcall(function() return hostile.Visible end)
    return ok and v or false
end

local function IsEscaped(p)
    local wrapper = GetTagWrapper(p)
    if not wrapper then return false end
    local escaped = wrapper:FindFirstChild("Escaped")
    if not escaped then return false end
    if escaped:IsA("GuiObject") then return escaped.Visible end
    local ok, v = pcall(function() return escaped.Visible end)
    return ok and v or false
end

-- ==================== 武器系统 ====================
local MeleeNames = { "knife", "crowbar", "tomahawk", "hammer", "bat", "sword", "axe", "machete" }
local RangedNames = { "glock", "beretta", "mp5", "ak47", "hk416", "spas-12", "awm", "m249", "deagle", "uzi", "rifle", "shotgun", "pistol" }

local function IsMelee(name)
    name = (name or ""):lower()
    for _, kw in ipairs(MeleeNames) do
        if name:find(kw) then return true end
    end
    return false
end

local function IsRanged(name)
    name = (name or ""):lower()
    for _, kw in ipairs(RangedNames) do
        if name:find(kw) then return true end
    end
    return false
end

local WepList = {}
local WepNames = {}
local CurrentWeaponID = nil
local CurrentWeaponName = "无"

local function ExtractID(tool)
    for _, c in ipairs(tool:GetDescendants()) do
        if c:IsA("StringValue") and c.Value and #c.Value == 36 then
            return c.Value
        end
    end
    for k, v in pairs(tool:GetAttributes()) do
        if type(v) == "string" and #v == 36 then return v end
    end
    if #tool.Name == 36 then return tool.Name end
    return nil
end

local function ScanWeapons()
    local ids = {}
    local names = {}

    local function AddTool(t)
        local id = ExtractID(t)
        if id then
            ids[id] = true
            names[id] = (t:GetAttribute("Name") or t.Name):lower()
        end
    end

    local bp = player:FindFirstChild("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then AddTool(t) end
        end
    end
    if player.Character then
        for _, t in ipairs(player.Character:GetChildren()) do
            if t:IsA("Tool") then AddTool(t) end
        end
    end

    WepList = {}
    WepNames = {}
    for id in pairs(ids) do
        table.insert(WepList, id)
        WepNames[id] = names[id]
    end

    -- 更新当前武器（取角色手上第一个）
    local found = false
    if player.Character then
        for _, t in ipairs(player.Character:GetChildren()) do
            if t:IsA("Tool") then
                local id = ExtractID(t)
                if id then
                    CurrentWeaponID = id
                    CurrentWeaponName = t:GetAttribute("Name") or t.Name
                    found = true
                    break
                end
            end
        end
    end
    if not found then
        CurrentWeaponID = nil
        CurrentWeaponName = "无"
    end

    return #WepList
end

local function HasRanged()
    for _, id in ipairs(WepList) do
        if IsRanged(WepNames[id]) then return true end
    end
    return false
end

local function HasMelee()
    for _, id in ipairs(WepList) do
        if IsMelee(WepNames[id]) then return true end
    end
    return false
end

-- ==================== 视线检测（射线） ====================
local function BuildIgnoreList()
    local ignore = {}
    local function Add(v) if v then table.insert(ignore, v) end end
    Add(player.Character)
    if player.Character then
        for _, t in ipairs(player.Character:GetChildren()) do
            if t:IsA("Tool") then Add(t) end
        end
    end
    local bp = player:FindFirstChild("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then Add(t) end
        end
    end
    local cam = Workspace:FindFirstChild("Camera")
    if cam then
        for _, v in ipairs(cam:GetChildren()) do Add(v) end
    end
    return ignore
end

local function HasLineOfSight(from, targetChar)
    local hrp = targetChar:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = BuildIgnoreList()
    params.IgnoreWater = true
    local dir = (hrp.Position - from).Unit
    local dist = (hrp.Position - from).Magnitude
    local result = Workspace:Raycast(from, dir * dist, params)
    if result then
        return result.Instance:FindFirstAncestorOfClass("Model") == targetChar
    end
    return true
end

-- ==================== 获取敌人 ====================
local function GetEnemies()
    local enemies = {}
    local myHRP = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not myHRP then return enemies end

    for _, p in ipairs(Players:GetPlayers()) do
        if p == player then continue end
        if isWL(p) then continue end
        if not p.Character then continue end

        local hrp = p.Character:FindFirstChild("HumanoidRootPart")
        local hum = p.Character:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then continue end

        local dist = (hrp.Position - myHRP.Position).Magnitude
        if dist > MAX_RANGE then continue end

        local isEnemy = false
        local reason = ""

        if IsEnemy(p) then
            isEnemy = true
            reason = "敌对"
        end

        -- 非D级阵营才因标签攻击D级
        if not isEnemy and not DCLASS[myRole] then
            if IsHostile(p) then
                isEnemy = true
                reason = "违规D级"
            elseif IsEscaped(p) then
                isEnemy = true
                reason = "逃出D级"
            end
        end

        if isEnemy then
            local canSee = true
            if rayEnabled then
                canSee = HasLineOfSight(myHRP.Position, p.Character)
            end
            if canSee then
                table.insert(enemies, {
                    player = p,
                    char = p.Character,
                    hrp = hrp,
                    dist = dist,
                    reason = reason
                })
            end
        end
    end

    table.sort(enemies, function(a, b) return a.dist < b.dist end)
    return enemies
end

local function GetMeleeTargets()
    local targets = {}
    local myHRP = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not myHRP then return targets end

    for _, p in ipairs(Players:GetPlayers()) do
        if p == player then continue end
        if isWL(p) then continue end
        if not p.Character then continue end

        local hrp = p.Character:FindFirstChild("HumanoidRootPart")
        local hum = p.Character:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then continue end

        local dist = (hrp.Position - myHRP.Position).Magnitude
        if dist > MELEE_RANGE then continue end

        local isEnemy = false
        if IsEnemy(p) then isEnemy = true end

        if not isEnemy and not DCLASS[myRole] then
            if IsHostile(p) then isEnemy = true end
            if IsEscaped(p) then isEnemy = true end
        end

        if isEnemy then
            table.insert(targets, { player = p, char = p.Character, hrp = hrp })
        end
    end

    return targets
end

-- ==================== 脚底范围圆圈 ====================
local CircleParts = {}

local function DestroyCircle()
    for _, part in ipairs(CircleParts) do
        pcall(function() part:Destroy() end)
    end
    CircleParts = {}
end

local function CreateCircle()
    DestroyCircle()
    if not drawCircle then return end
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local segments = 44
    local radius = MELEE_RANGE
    local center = hrp.Position

    for i = 1, segments do
        local angle = (i / segments) * math.pi * 2
        local x = center.X + math.cos(angle) * radius
        local z = center.Z + math.sin(angle) * radius
        local part = Instance.new("Part")
        part.Name = "RangeCircle"
        part.Anchored = true
        part.CanCollide = false
        part.CastShadow = false
        part.Material = Enum.Material.Neon
        part.Color = Color3.fromRGB(255, 250, 240)
        part.Transparency = 0.610
        part.Size = Vector3.new(0.085, 0.010, 0.080)
        part.CFrame = CFrame.new(x, center.Y - 0.020, z)
        part.Parent = Workspace
        table.insert(CircleParts, part)
    end
end

local function UpdateCircle()
    if not drawCircle then DestroyCircle(); return end
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then DestroyCircle(); return end

    local valid = true
    for _, part in ipairs(CircleParts) do
        if not part or not part.Parent then valid = false; break end
    end
    if not valid or #CircleParts == 0 then CreateCircle(); return end

    local center = hrp.Position
    local segments = #CircleParts
    for i, part in ipairs(CircleParts) do
        local angle = (i / segments) * math.pi * 2
        local x = center.X + math.cos(angle) * MELEE_RANGE
        local z = center.Z + math.sin(angle) * MELEE_RANGE
        part.CFrame = CFrame.new(x, center.Y - 0.020, z)
    end
end

-- ==================== 枪口位置 ====================
local function GetMuzzlePos(weaponID)
    local camera = Workspace:FindFirstChild("Camera")
    if not camera then return nil end
    local weaponObj = camera:FindFirstChild(weaponID)
    if not weaponObj then return nil end
    local points = weaponObj:FindFirstChild("Points")
    if not points then return nil end
    local muzzle = points:FindFirstChild("Muzzle")
    if not muzzle then return nil end
    return muzzle.WorldPosition
end

-- ==================== 远程射击 ====================
local function FireRanged(target)
    local head = target.char:FindFirstChild("Head")
    local aimPoint = (head or target.hrp).Position

    local origin = nil
    for _, id in ipairs(WepList) do
        if IsRanged(WepNames[id]) then
            local mp = GetMuzzlePos(id)
            if mp then origin = mp; break end
        end
    end

    if not origin then
        local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            origin = hrp.Position + Vector3.new(
                math.random(-60, 60)/10,
                math.random(-30, 50)/10,
                math.random(-60, 60)/10
            )
        else
            origin = aimPoint + Vector3.new(0, 2.5, 0)
        end
    end

    local dir = (aimPoint - origin).Unit * 8500

    if drawVis then
        local beam = Instance.new("Part")
        beam.Anchored = true
        beam.CanCollide = false
        beam.Material = Enum.Material.Neon
        beam.Color = Color3.fromRGB(230, 235, 245)
        beam.Transparency = 0.350
        beam.Size = Vector3.new(0.050, 0.055, (aimPoint - origin).Magnitude)
        beam.CFrame = CFrame.new(origin, aimPoint) * CFrame.new(0, 0, -beam.Size.Z/2)
        beam.Parent = Workspace

        local hit = Instance.new("Part")
        hit.Anchored = true
        hit.CanCollide = false
        hit.Material = Enum.Material.Neon
        hit.Color = Color3.fromRGB(240, 245, 250)
        hit.Transparency = 0.450
        hit.Shape = Enum.PartType.Ball
        hit.Size = Vector3.new(0.390, 0.380, 0.340)
        hit.CFrame = CFrame.new(aimPoint)
        hit.Parent = Workspace

        task.delay(0.810, function()
            pcall(function() beam:Destroy() end)
            pcall(function() hit:Destroy() end)
        end)
    end

    if ShootEvent then
        for _, id in ipairs(WepList) do
            if IsRanged(WepNames[id]) then
                pcall(function()
                    ShootEvent:FireServer(id, {{
                        normal = Vector3.new(0,1,0),
                        direction = dir,
                        origin = origin,
                        instance = head or target.hrp,
                        points = {},
                        position = aimPoint
                    }})
                end)
                if SoundEvent then
                    pcall(function() SoundEvent:FireServer(id, "FIRE") end)
                end
            end
        end
    end
end

-- ==================== 近战攻击 ====================
local function FireMelee(targets)
    if #targets == 0 then return end
    local targetChar = targets[1].char
    local camera = Workspace:FindFirstChild("Camera")
    if not camera then return end

    if AttackEvent then
        for _, id in ipairs(WepList) do
            if IsMelee(WepNames[id]) then
                local camWep = camera:FindFirstChild(id)
                if not camWep then
                    task.wait(0.035)
                    camWep = camera:FindFirstChild(id)
                end
                if camWep then
                    pcall(function()
                        AttackEvent:FireServer(id, { targetChar, camWep })
                    end)
                end
            end
        end
    end
end

-- ==================== 职业中文映射 ====================
local RoleNames = {
    scientist = "科学家",
    security = "安保",
    mtf = "机动特遣队",
    director = "主管",
    d_class = "D级人员",
    escaped_d = "逃脱D级",
    escaped_d_class = "逃脱D级",
    chaos_insurgency = "混沌分裂者",
    rogue_agent = "叛变特工",
    traitor = "叛徒",
    renegade = "反叛者",
    anomaly = "异常实体",
}
local function RoleCN(role)
    if not role or role == "" then return "未知" end
    return RoleNames[role] or role
end

-- ==================== 透视ESP（英文key直查颜色，无Gradient） ====================
local ESPData = {}

local RoleColors = {
    scientist = Color3.fromRGB(102, 168, 208),
    security = Color3.fromRGB(191, 194, 201),
    mtf = Color3.fromRGB(67, 119, 222),
    director = Color3.fromRGB(118, 210, 120),
    d_class = Color3.fromRGB(247, 108, 48),
    escaped_d = Color3.fromRGB(255, 170, 0),
    escaped_d_class = Color3.fromRGB(255, 170, 0),
    chaos_insurgency = Color3.fromRGB(227, 156, 0),
    rogue_agent = Color3.fromRGB(215, 95, 85),
    traitor = Color3.fromRGB(225, 85, 75),
    renegade = Color3.fromRGB(235, 75, 65),
    anomaly = Color3.fromRGB(141, 139, 143),
    Default = Color3.fromRGB(174, 176, 178),
}

local function CleanESP(p)
    if ESPData[p] then
        if ESPData[p].GUI and ESPData[p].GUI.Parent then
            ESPData[p].GUI:Destroy()
        end
        ESPData[p] = nil
    end
end

local function CreateESP(p)
    if p == player or ESPData[p] then return end

    p.CharacterAdded:Connect(function()
        task.wait(0.300)
        CleanESP(p)
        task.spawn(function() CreateESP(p) end)
    end)
    p.CharacterRemoving:Connect(function() CleanESP(p) end)

    task.spawn(function()
        local char = p.Character or p.CharacterAdded:Wait()
        local hrp = char:WaitForChild("HumanoidRootPart", 5)
        local head = char:WaitForChild("Head", 5)
        local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
        if not hrp or not head or not hum then return end

        local gui = Instance.new("BillboardGui")
        gui.Name = "ESP_" .. p.Name
        gui.Adornee = hrp
        -- 手机端缩小（IS_MOBILE时尺寸减半）
        if IS_MOBILE then
            gui.Size = UDim2.new(0, 140, 0, 255)
        else
            gui.Size = UDim2.new(0, 280, 0, 510)
        end
        gui.StudsOffset = Vector3.new(0, 1.470, 0)
        gui.AlwaysOnTop = true
        gui.MaxDistance = 800000
        gui.Parent = hrp

        local box = Instance.new("Frame")
        box.Size = UDim2.new(0.640, 0, 0.515, 0)
        box.Position = UDim2.new(0.140, 0, 0.320, 0)
        box.BackgroundTransparency = 0.820
        box.BorderSizePixel = 0
        box.Parent = gui

        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 2
        stroke.Color = Color3.fromRGB(180, 178, 181)
        stroke.Parent = box

        local hpBG = Instance.new("Frame")
        hpBG.Size = UDim2.new(0.028, 0, 0.490, 0)
        hpBG.Position = UDim2.new(0.666, 0, 0.310, 0)
        hpBG.BackgroundColor3 = Color3.fromRGB(20, 16, 18)
        hpBG.BackgroundTransparency = 0.285
        hpBG.BorderSizePixel = 0
        hpBG.Parent = gui
        Instance.new("UICorner", hpBG).CornerRadius = UDim.new(0, 1)

        local hpFill = Instance.new("Frame")
        hpFill.Size = UDim2.new(1, 0, 1, 0)
        hpFill.AnchorPoint = Vector2.new(0, 1)
        hpFill.Position = UDim2.new(0, 0, 1, 0)
        hpFill.BackgroundColor3 = Color3.fromRGB(25, 130, 20)
        hpFill.BorderSizePixel = 0
        hpFill.Parent = hpBG
        Instance.new("UICorner", hpFill).CornerRadius = UDim.new(0, 1)

        ESPData[p] = {
            GUI = gui,
            Box = box,
            Stroke = stroke,
            HPFill = hpFill,
            Hum = hum,
            Char = char,
        }

        hum.HealthChanged:Connect(function(health)
            if not hpFill or not hpFill.Parent then return end
            local maxHP = hum.MaxHealth > 0 and hum.MaxHealth or 100
            local ratio = math.clamp(health / maxHP, 0, 1)
            hpFill.Size = UDim2.new(1, 0, ratio, 0)
            if ratio > 0.52 then
                hpFill.BackgroundColor3 = Color3.fromRGB(50, 105, 48)
            elseif ratio > 0.70 then
                hpFill.BackgroundColor3 = Color3.fromRGB(66, 156, 143)
            else
                hpFill.BackgroundColor3 = Color3.fromRGB(75, 153, 140)
            end
        end)
    end)
end

for _, p in ipairs(Players:GetPlayers()) do
    task.spawn(function() CreateESP(p) end)
end
Players.PlayerAdded:Connect(function(p)
    task.wait(0.460)
    CreateESP(p)
end)
Players.PlayerRemoving:Connect(CleanESP)

task.spawn(function()
    while true do task.wait(0.020)
        if not espEnabled then
            for p, data in pairs(ESPData) do
                if data.GUI then data.GUI.Enabled = false end
            end
        else
            local camera = Workspace.CurrentCamera
            for p, data in pairs(ESPData) do
                if not data.GUI then continue end
                data.GUI.Enabled = true

                local role = GetRole(p) or "Default"
                local col = RoleColors[role] or RoleColors.Default

                -- 违规标红，逃出标亮橙
                if IsHostile(p) then
                    col = Color3.fromRGB(255, 75, 75)
                elseif IsEscaped(p) then
                    col = Color3.fromRGB(255, 175, 0)
                end

                data.Stroke.Color = col

                if camera and data.Char and data.Char:FindFirstChild("HumanoidRootPart") then
                    local hrp = data.Char.HumanoidRootPart
                    local dist = (camera.CFrame.Position - hrp.Position).Magnitude
                    local scale = math.pow(6 / math.max(dist, 1), 0.45)
                    local w = math.max(18, 275 * scale)
                    local h = math.max(28, 500 * scale)
                    data.GUI.Size = UDim2.new(0, w, 0, h)
                end

                if not p.Character or (data.Hum and data.Hum.Health <= 0) then
                    CleanESP(p)
                end
            end
        end
    end
end)

-- ==================== 穿门系统（一次性扫描+平方距离，零卡顿） ====================
local DoorSys = {}
DoorSys.Range = 7
DoorSys.RangeSq = 49
DoorSys.Parts = {}
DoorSys.OriginalCollide = {}

local function ScanAllDoors()
    local map = Workspace:FindFirstChild("Map")
    if not map then return 0 end
    local doors = map:FindFirstChild("Doors")
    if not doors then return 0 end

    local count = 0
    local function Rec(obj)
        if obj:IsA("BasePart") then
            if not DoorSys.Parts[obj] then
                DoorSys.Parts[obj] = true
                DoorSys.OriginalCollide[obj] = obj.CanCollide
                count = count + 1
            end
        end
        for _, ch in ipairs(obj:GetChildren()) do Rec(ch) end
    end
    Rec(doors)
    return count
end

local DoorCount = ScanAllDoors()

task.spawn(function()
    while true do task.wait(30)
        if DoorSysEnabled then
            local nc = ScanAllDoors()
            if nc > DoorCount then DoorCount = nc end
        end
    end
end)

task.spawn(function()
    while true do task.wait(0.090)
        if not DoorSysEnabled then
            task.wait(0.500)
            continue
        end
        local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then task.wait(0.480); continue end

        local px, py, pz = hrp.Position.X, hrp.Position.Y, hrp.Position.Z
        for part in pairs(DoorSys.Parts) do
            if not part or not part.Parent then
                DoorSys.Parts[part] = nil
                DoorSys.OriginalCollide[part] = nil
                continue
            end
            local dx = part.Position.X - px
            local dy = part.Position.Y - py
            local dz = part.Position.Z - pz
            local distSq = dx*dx + dy*dy + dz*dz

            if distSq <= DoorSys.RangeSq then
                if part.CanCollide then part.CanCollide = false end
            else
                local orig = DoorSys.OriginalCollide[part]
                if orig ~= nil and part.CanCollide ~= orig then
                    part.CanCollide = orig
                end
            end
        end
    end
end)

-- ==================== 战斗主循环 ====================
ScanWeapons()

local LastShoot = 0
local LastMelee = 0

player.CharacterAdded:Connect(function()
    task.wait(0.340)
    ScanWeapons()
    task.wait(0.330)
    if drawCircle then pcall(CreateCircle) end
end)

-- 持续自动扫描武器（检测换枪 + 角色变化）
task.spawn(function()
    local lastWepName = ""
    while true do
        task.wait(1)
        ScanWeapons()
        -- 检测当前手持武器变化
        if player.Character then
            for _, t in ipairs(player.Character:GetChildren()) do
                if t:IsA("Tool") then
                    if t.Name ~= lastWepName then
                        lastWepName = t.Name
                        local id = ExtractID(t)
                        if id then
                            CurrentWeaponID = id
                            CurrentWeaponName = t:GetAttribute("Name") or t.Name
                        end
                    end
                    break
                end
            end
        end
        -- 更新自己的角色
        UpdateMyRole()
    end
end)

RunService.Heartbeat:Connect(function()
    local now = tick()

    if autoMelee and HasMelee() and now - LastMelee >= MELEE_CD then
        local targets = GetMeleeTargets()
        if #targets > 0 then
            FireMelee(targets)
            LastMelee = now
        end
    end

    if autoShoot and HasRanged() and now - LastShoot >= SHOOT_CD then
        local enemies = GetEnemies()
        if #enemies > 0 then
            FireRanged(enemies[1])
            LastShoot = now
        end
    end

    pcall(UpdateCircle)
end)

-- ==================== UI ====================
local UI = {}
local ListVisible = true
local Minimized = false

-- 颜色表
local C = {
    BG = Color3.fromRGB(46, 50, 56),
    Title = Color3.fromRGB(54, 58, 64),
    Dark = Color3.fromRGB(68, 74, 82),
    Text = Color3.fromRGB(236, 239, 243),
    Dim = Color3.fromRGB(156, 162, 174),
    Green = Color3.fromRGB(28, 145, 10),
    Purple = Color3.fromRGB(163, 135, 207),
    Blue = Color3.fromRGB(50, 105, 213),
    Yellow = Color3.fromRGB(202, 186, 115),
    Red = Color3.fromRGB(230, 73, 77),
    Orange = Color3.fromRGB(204, 159, 94),
    Pink = Color3.fromRGB(193, 144, 186),
    Label = Color3.fromRGB(86, 90, 98),
    Input = Color3.fromRGB(80, 85, 93),
    Sep = Color3.fromRGB(102, 108, 118),
}

task.spawn(function()
    local pg = player:WaitForChild("PlayerGui", 30)
    if not pg then return end

    local sg = Instance.new("ScreenGui")
    sg.Name = "SCPAnomalySite"
    sg.ResetOnSpawn = false
    sg.Enabled = true
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
    sg.Parent = pg

    -- ===== 尺寸定义（手机/电脑分开） =====
    -- 手机整体缩小0.5倍
    local scale = IS_MOBILE and 0.5 or 1.0

    local PW = math.floor(370 * scale)       -- 主面板宽
    local PH = math.floor(280 * scale)       -- 主面板高（展开时）
    local MH = math.floor(30 * scale)        -- 标题栏高
    local LW = math.floor(330 * scale)       -- 玩家列表面板宽
    local LH = math.floor(400 * scale)       -- 玩家列表面板高
    local GAP = math.floor(4 * scale)
    local PAD = math.floor(6 * scale)
    local BW = math.floor((PW - PAD*2 - GAP*3) / 4)  -- 按钮宽
    local BH = math.floor(28 * scale)        -- 按钮高
    local TS = math.max(8, math.floor(12 * scale))    -- 状态栏文字
    local BS = math.max(8, math.floor(12 * scale))    -- 按钮文字

    -- 主面板
    local MF = Instance.new("Frame")
    MF.Size = UDim2.new(0, PW, 0, PH)
    MF.Position = UDim2.new(1, -(PW + 10), 0.44, math.floor(-PH/2))
    MF.BackgroundColor3 = C.BG
    MF.BackgroundTransparency = 0.04
    MF.BorderSizePixel = 0
    MF.Active = true
    MF.Draggable = true
    MF.Parent = sg
    Instance.new("UICorner", MF).CornerRadius = UDim.new(0, 6)

    -- 内容区
    local CC = Instance.new("Frame")
    CC.Size = UDim2.new(1, 0, 1, -MH)
    CC.Position = UDim2.new(0, 0, 0, MH)
    CC.BackgroundTransparency = 1
    CC.BorderSizePixel = 0
    CC.Parent = MF

    -- 标题栏
    local TB = Instance.new("Frame")
    TB.Size = UDim2.new(1, 0, 0, MH)
    TB.Position = UDim2.new(0, 0, 0, 0)
    TB.BackgroundColor3 = C.Title
    TB.BackgroundTransparency = 0.055
    TB.BorderSizePixel = 0
    TB.Parent = MF
    Instance.new("UICorner", TB).CornerRadius = UDim.new(0, 6)

    local TL = Instance.new("TextLabel")
    TL.Size = UDim2.new(1, -math.floor(70*scale), 1, 0)
    TL.Position = UDim2.new(0, math.floor(35*scale), 0, 0)
    TL.BackgroundTransparency = 1
    TL.Text = "SCP异常站点"
    TL.TextColor3 = C.Text
    TL.Font = Enum.Font.GothamBold
    TL.TextSize = math.max(10, math.floor(16 * scale))
    TL.TextXAlignment = Enum.TextXAlignment.Center
    TL.Parent = TB

    -- 最小化按钮
    local MB = Instance.new("TextButton")
    MB.Size = UDim2.new(0, math.floor(24*scale), 0, math.floor(24*scale))
    MB.Position = UDim2.new(1, -math.floor(50*scale), 0, math.floor(3*scale))
    MB.BackgroundColor3 = C.Dark
    MB.BackgroundTransparency = 0.07
    MB.Text = "━"
    MB.TextColor3 = C.Text
    MB.Font = Enum.Font.GothamBold
    MB.TextSize = math.max(10, math.floor(16*scale))
    MB.Parent = TB
    Instance.new("UICorner", MB).CornerRadius = UDim.new(0, 4)

    -- 关闭按钮
    local CB = Instance.new("TextButton")
    CB.Size = UDim2.new(0, math.floor(24*scale), 0, math.floor(24*scale))
    CB.Position = UDim2.new(1, -math.floor(26*scale), 0, math.floor(3*scale))
    CB.BackgroundColor3 = C.Dark
    CB.BackgroundTransparency = 0.07
    CB.Text = "✕"
    CB.TextColor3 = C.Text
    CB.Font = Enum.Font.GothamBold
    CB.TextSize = math.max(10, math.floor(16*scale))
    CB.Parent = TB
    Instance.new("UICorner", CB).CornerRadius = UDim.new(0, 4)

    -- 玩家列表按钮（☰）
    local EB = Instance.new("TextButton")
    EB.Size = UDim2.new(0, math.floor(24*scale), 0, math.floor(24*scale))
    EB.Position = UDim2.new(0, math.floor(4*scale), 0, math.floor(3*scale))
    EB.BackgroundColor3 = C.Dark
    EB.BackgroundTransparency = 0.07
    EB.Text = "☰"
    EB.TextColor3 = C.Text
    EB.Font = Enum.Font.GothamBold
    EB.TextSize = math.max(10, math.floor(16*scale))
    EB.Parent = TB
    Instance.new("UICorner", EB).CornerRadius = UDim.new(0, 4)

    -- 最小化逻辑
    MB.MouseButton1Click:Connect(function()
        Minimized = not Minimized
        if Minimized then
            CC.Visible = false
            MF.Size = UDim2.new(0, PW, 0, MH)
            MB.Text = "□"
        else
            CC.Visible = true
            MF.Size = UDim2.new(0, PW, 0, PH)
            MB.Text = "━"
        end
    end)

    -- 关闭逻辑
    CB.MouseButton1Click:Connect(function()
        local cfm = Instance.new("TextButton")
        cfm.Size = UDim2.new(0, math.floor(110*scale), 0, math.floor(44*scale))
        cfm.Position = UDim2.new(0.5, -math.floor(55*scale), 0.5, -math.floor(22*scale))
        cfm.BackgroundColor3 = C.Red
        cfm.BackgroundTransparency = 0.06
        cfm.Text = "关闭?"
        cfm.TextColor3 = C.Text
        cfm.Font = Enum.Font.GothamBold
        cfm.TextSize = math.max(12, math.floor(18*scale))
        cfm.Parent = sg
        Instance.new("UICorner", cfm).CornerRadius = UDim.new(0, 5)
        cfm.MouseButton1Click:Connect(function() sg:Destroy(); cfm:Destroy() end)
        task.delay(2.5, function() if cfm and cfm.Parent then cfm:Destroy() end end)
    end)

    -- ===== 玩家列表面板（独立，不随主面板最小化） =====
    local PLF = Instance.new("Frame")
    PLF.Size = UDim2.new(0, LW, 0, LH)
    PLF.Position = UDim2.new(1, -(PW + LW + 15), 0.46, math.floor(-LH/2))
    PLF.BackgroundColor3 = C.BG
    PLF.BackgroundTransparency = 0.06
    PLF.BorderSizePixel = 0
    PLF.Active = true
    PLF.Draggable = true
    PLF.Visible = true
    PLF.Parent = sg
    Instance.new("UICorner", PLF).CornerRadius = UDim.new(0, 6)
    UI.PlayerListFrame = PLF

    local PLT = Instance.new("Frame")
    PLT.Size = UDim2.new(1, 0, 0, MH)
    PLT.BackgroundColor3 = C.Title
    PLT.BackgroundTransparency = 0.06
    PLT.BorderSizePixel = 0
    PLT.Parent = PLF
    Instance.new("UICorner", PLT).CornerRadius = UDim.new(0, 6)

    local PTL = Instance.new("TextLabel")
    PTL.Size = UDim2.new(1, -12, 1, 0)
    PTL.Position = UDim2.new(0, 6, 0, 0)
    PTL.BackgroundTransparency = 1
    PTL.Text = "玩家列表"
    PTL.TextColor3 = C.Text
    PTL.Font = Enum.Font.GothamBold
    PTL.TextSize = math.max(10, math.floor(15*scale))
    PTL.TextXAlignment = Enum.TextXAlignment.Center
    PTL.Parent = PLT

    local PLC = Instance.new("ScrollingFrame")
    PLC.Size = UDim2.new(1, -10, 1, -(MH + 4))
    PLC.Position = UDim2.new(0, 5, 0, MH + 2)
    PLC.BackgroundTransparency = 1
    PLC.BorderSizePixel = 0
    PLC.ScrollBarThickness = math.max(3, math.floor(5*scale))
    PLC.ScrollBarImageColor3 = Color3.fromRGB(130, 144, 160)
    PLC.Parent = PLF

    local PLL = Instance.new("TextLabel")
    PLL.Size = UDim2.new(1, -8, 1, -4)
    PLL.Position = UDim2.new(0, 4, 0, 2)
    PLL.BackgroundTransparency = 1
    PLL.Text = "加载中..."
    PLL.TextColor3 = C.Text
    PLL.Font = Enum.Font.Gotham
    PLL.TextSize = math.max(8, math.floor(12*scale))
    PLL.TextXAlignment = Enum.TextXAlignment.Left
    PLL.TextYAlignment = Enum.TextYAlignment.Top
    PLL.TextWrapped = true
    PLL.Parent = PLC
    UI.PlayerListLabel = PLL

    EB.MouseButton1Click:Connect(function()
        ListVisible = not ListVisible
        PLF.Visible = ListVisible
    end)

    -- ===== 内容区布局 =====
    local y = GAP

    -- 状态栏（三行：职业 / 武器 / ID + 计数）
    local SB = Instance.new("Frame")
    SB.Size = UDim2.new(0, PW - PAD*2, 0, math.floor(54*scale))
    SB.Position = UDim2.new(0, PAD, 0, y)
    SB.BackgroundColor3 = C.Dark
    SB.BackgroundTransparency = 0.07
    SB.BorderSizePixel = 0
    SB.Parent = CC
    Instance.new("UICorner", SB).CornerRadius = UDim.new(0, 4)

    local SL = Instance.new("TextLabel")
    SL.Size = UDim2.new(1, -8, 1, -4)
    SL.Position = UDim2.new(0, 4, 0, 2)
    SL.BackgroundTransparency = 1
    SL.Text = "加载中..."
    SL.TextColor3 = C.Text
    SL.Font = Enum.Font.Gotham
    SL.TextSize = TS
    SL.TextXAlignment = Enum.TextXAlignment.Left
    SL.TextYAlignment = Enum.TextYAlignment.Top
    SL.Parent = SB
    UI.StatusLabel = SL

    y = y + math.floor(54*scale) + GAP

    -- 按钮创建函数
    local function mkBtn(text, color, w, h)
        w = w or BW
        h = h or BH
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, w, 0, h)
        b.BackgroundColor3 = color
        b.BackgroundTransparency = 0.06
        b.Text = text
        b.TextColor3 = C.Text
        b.Font = Enum.Font.GothamBold
        b.TextSize = BS
        b.Parent = CC
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
        return b
    end

    -- ===== 第一排：射击 | 近战 | 射线检测 | 显示弹道 =====
    local SHT = mkBtn("射击", C.Green)
    SHT.Position = UDim2.new(0, PAD, 0, y)
    local MEL = mkBtn("近战", C.Purple)
    MEL.Position = UDim2.new(0, PAD + BW + GAP, 0, y)
    local RAY = mkBtn("射线检测", C.Blue)
    RAY.Position = UDim2.new(0, PAD + (BW+GAP)*2, 0, y)
    local VIS = mkBtn("显示弹道", C.Yellow)
    VIS.Position = UDim2.new(0, PAD + (BW+GAP)*3, 0, y)

    y = y + BH + GAP

    SHT.MouseButton1Click:Connect(function()
        autoShoot = not autoShoot
        SHT.BackgroundColor3 = autoShoot and C.Green or C.Red
    end)
    MEL.MouseButton1Click:Connect(function()
        autoMelee = not autoMelee
        MEL.BackgroundColor3 = autoMelee and C.Purple or C.Red
    end)
    RAY.MouseButton1Click:Connect(function()
        rayEnabled = not rayEnabled
        RAY.Text = rayEnabled and "射线检测" or "穿墙"
        RAY.BackgroundColor3 = rayEnabled and C.Blue or C.Red
    end)
    VIS.MouseButton1Click:Connect(function()
        drawVis = not drawVis
        VIS.BackgroundColor3 = drawVis and C.Yellow or C.Red
    end)

    -- ===== 第二排：范围 | 透视 | 穿门 | 射程(点击输入) =====
    local CIR = mkBtn("范围", C.Orange)
    CIR.Position = UDim2.new(0, PAD, 0, y)
    local ESB = mkBtn("透视", C.Blue)
    ESB.Position = UDim2.new(0, PAD + BW + GAP, 0, y)
    local DRB = mkBtn("穿门", C.Green)
    DRB.Position = UDim2.new(0, PAD + (BW+GAP)*2, 0, y)

    -- 射程按钮（点击弹键盘输入）
    local RGL = Instance.new("TextButton")
    RGL.Size = UDim2.new(0, BW, 0, BH)
    RGL.Position = UDim2.new(0, PAD + (BW+GAP)*3, 0, y)
    RGL.BackgroundColor3 = C.Label
    RGL.BackgroundTransparency = 0.05
    RGL.Text = "射程:" .. MAX_RANGE
    RGL.TextColor3 = C.Text
    RGL.Font = Enum.Font.GothamBold
    RGL.TextSize = BS
    RGL.Parent = CC
    Instance.new("UICorner", RGL).CornerRadius = UDim.new(0, 4)

    y = y + BH + GAP

    CIR.MouseButton1Click:Connect(function()
        drawCircle = not drawCircle
        CIR.BackgroundColor3 = drawCircle and C.Orange or C.Red
        if drawCircle then pcall(CreateCircle) else pcall(DestroyCircle) end
    end)
    ESB.MouseButton1Click:Connect(function()
        espEnabled = not espEnabled
        ESB.BackgroundColor3 = espEnabled and C.Blue or C.Red
    end)
    DRB.MouseButton1Click:Connect(function()
        DoorSysEnabled = not DoorSysEnabled
        DRB.BackgroundColor3 = DoorSysEnabled and C.Green or C.Red
        if not DoorSysEnabled then
            for part in pairs(DoorSys.Parts) do
                local orig = DoorSys.OriginalCollide[part]
                if orig ~= nil and part and part.Parent then
                    part.CanCollide = orig
                end
            end
        end
    end)

    -- 射程输入弹窗
    local rangeInputOpen = false
    RGL.MouseButton1Click:Connect(function()
        if rangeInputOpen then return end
        rangeInputOpen = true

        local overlay = Instance.new("Frame")
        overlay.Size = UDim2.new(0, PW - PAD*2, 0, math.floor(50*scale))
        overlay.Position = UDim2.new(0, PAD, 0, y)
        overlay.BackgroundColor3 = C.Dark
        overlay.BackgroundTransparency = 0.02
        overlay.BorderSizePixel = 0
        overlay.Parent = CC
        Instance.new("UICorner", overlay).CornerRadius = UDim.new(0, 4)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0.30, 0, 1, 0)
        lbl.Position = UDim2.new(0, 0, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = "射程:"
        lbl.TextColor3 = C.Dim
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = BS
        lbl.TextXAlignment = Enum.TextXAlignment.Right
        lbl.Parent = overlay

        local tb = Instance.new("TextBox")
        tb.Size = UDim2.new(0.55, 0, 0.7, 0)
        tb.Position = UDim2.new(0.33, 0, 0.15, 0)
        tb.BackgroundColor3 = C.Input
        tb.BackgroundTransparency = 0.04
        tb.Text = tostring(MAX_RANGE)
        tb.PlaceholderText = "输入数字"
        tb.PlaceholderColor3 = C.Dim
        tb.TextColor3 = C.Text
        tb.Font = Enum.Font.GothamBold
        tb.TextSize = BS
        tb.ClearTextOnFocus = false
        tb.Parent = overlay
        Instance.new("UICorner", tb).CornerRadius = UDim.new(0, 3)

        local ok = false
        local function apply()
            if ok then return end
            ok = true
            local val = tonumber(tb.Text)
            if val and val >= 10 and val <= 5000 then
                MAX_RANGE = math.floor(val)
            end
            RGL.Text = "射程:" .. MAX_RANGE
            overlay:Destroy()
            rangeInputOpen = false
        end
        tb.FocusLost:Connect(function(ep) if ep then apply() end end)

        local OKBtn = Instance.new("TextButton")
        OKBtn.Size = UDim2.new(0.15, 0, 0.7, 0)
        OKBtn.Position = UDim2.new(0.84, 0, 0.15, 0)
        OKBtn.BackgroundColor3 = C.Green
        OKBtn.BackgroundTransparency = 0.05
        OKBtn.Text = "✓"
        OKBtn.TextColor3 = C.Text
        OKBtn.Font = Enum.Font.GothamBold
        OKBtn.TextSize = math.max(10, math.floor(14*scale))
        OKBtn.Parent = overlay
        Instance.new("UICorner", OKBtn).CornerRadius = UDim.new(0, 3)
        OKBtn.MouseButton1Click:Connect(apply)

        tb:CaptureFocus()
    end)

    -- ===== 第三排：近战(点击输入) | 自动扫描标签 | 空白 =====
    local MRL = Instance.new("TextButton")
    MRL.Size = UDim2.new(0, BW, 0, BH)
    MRL.Position = UDim2.new(0, PAD, 0, y)
    MRL.BackgroundColor3 = C.Label
    MRL.BackgroundTransparency = 0.05
    MRL.Text = "近战:" .. MELEE_RANGE
    MRL.TextColor3 = C.Text
    MRL.Font = Enum.Font.GothamBold
    MRL.TextSize = BS
    MRL.Parent = CC
    Instance.new("UICorner", MRL).CornerRadius = UDim.new(0, 4)

    -- 自动扫描状态标签
    local SCN_LBL = Instance.new("TextLabel")
    SCN_LBL.Size = UDim2.new(0, BW * 2 + GAP, 0, BH)
    SCN_LBL.Position = UDim2.new(0, PAD + BW + GAP, 0, y)
    SCN_LBL.BackgroundColor3 = C.Dark
    SCN_LBL.BackgroundTransparency = 0.06
    SCN_LBL.Text = "自动扫描✓"
    SCN_LBL.TextColor3 = C.Green
    SCN_LBL.Font = Enum.Font.GothamBold
    SCN_LBL.TextSize = BS
    SCN_LBL.TextXAlignment = Enum.TextXAlignment.Center
    SCN_LBL.Parent = CC
    Instance.new("UICorner", SCN_LBL).CornerRadius = UDim.new(0, 4)

    y = y + BH + GAP

    -- 近战距离输入弹窗
    local meleeInputOpen = false
    MRL.MouseButton1Click:Connect(function()
        if meleeInputOpen then return end
        meleeInputOpen = true

        local overlay = Instance.new("Frame")
        overlay.Size = UDim2.new(0, PW - PAD*2, 0, math.floor(50*scale))
        overlay.Position = UDim2.new(0, PAD, 0, y)
        overlay.BackgroundColor3 = C.Dark
        overlay.BackgroundTransparency = 0.02
        overlay.BorderSizePixel = 0
        overlay.Parent = CC
        Instance.new("UICorner", overlay).CornerRadius = UDim.new(0, 4)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0.30, 0, 1, 0)
        lbl.Position = UDim2.new(0, 0, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = "近战:"
        lbl.TextColor3 = C.Dim
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = BS
        lbl.TextXAlignment = Enum.TextXAlignment.Right
        lbl.Parent = overlay

        local tb = Instance.new("TextBox")
        tb.Size = UDim2.new(0.55, 0, 0.7, 0)
        tb.Position = UDim2.new(0.33, 0, 0.15, 0)
        tb.BackgroundColor3 = C.Input
        tb.BackgroundTransparency = 0.04
        tb.Text = tostring(MELEE_RANGE)
        tb.PlaceholderText = "输入数字"
        tb.PlaceholderColor3 = C.Dim
        tb.TextColor3 = C.Text
        tb.Font = Enum.Font.GothamBold
        tb.TextSize = BS
        tb.ClearTextOnFocus = false
        tb.Parent = overlay
        Instance.new("UICorner", tb).CornerRadius = UDim.new(0, 3)

        local ok = false
        local function apply()
            if ok then return end
            ok = true
            local val = tonumber(tb.Text)
            if val and val >= 2 and val <= 50 then
                MELEE_RANGE = math.floor(val)
            end
            MRL.Text = "近战:" .. MELEE_RANGE
            pcall(CreateCircle)
            overlay:Destroy()
            meleeInputOpen = false
        end
        tb.FocusLost:Connect(function(ep) if ep then apply() end end)

        local OKBtn = Instance.new("TextButton")
        OKBtn.Size = UDim2.new(0.15, 0, 0.7, 0)
        OKBtn.Position = UDim2.new(0.84, 0, 0.15, 0)
        OKBtn.BackgroundColor3 = C.Green
        OKBtn.BackgroundTransparency = 0.05
        OKBtn.Text = "✓"
        OKBtn.TextColor3 = C.Text
        OKBtn.Font = Enum.Font.GothamBold
        OKBtn.TextSize = math.max(10, math.floor(14*scale))
        OKBtn.Parent = overlay
        Instance.new("UICorner", OKBtn).CornerRadius = UDim.new(0, 3)
        OKBtn.MouseButton1Click:Connect(apply)

        tb:CaptureFocus()
    end)

    -- 分隔线
    local SEP = Instance.new("Frame")
    SEP.Size = UDim2.new(0, PW - PAD*2, 0, 1)
    SEP.Position = UDim2.new(0, PAD, 0, y + BH + GAP)
    SEP.BackgroundColor3 = C.Sep
    SEP.BackgroundTransparency = 0.04
    SEP.BorderSizePixel = 0
    SEP.Parent = CC
    y = y + BH + GAP + 1 + GAP

    -- ===== 白名单 =====
    local WLT = Instance.new("TextLabel")
    WLT.Size = UDim2.new(0, PW - PAD*2, 0, math.floor(16*scale))
    WLT.Position = UDim2.new(0, PAD, 0, y)
    WLT.BackgroundTransparency = 1
    WLT.Text = "白名单"
    WLT.TextColor3 = C.Dim
    WLT.Font = Enum.Font.Gotham
    WLT.TextSize = math.max(9, math.floor(11*scale))
    WLT.TextXAlignment = Enum.TextXAlignment.Center
    WLT.Parent = CC
    y = y + math.floor(18*scale) + GAP

    local NBW = math.floor(160 * scale)
    local ADW = math.floor(55 * scale)
    local CLW = PW - PAD*2 - NBW - ADW - GAP*2

    local NMB = Instance.new("TextBox")
    NMB.Size = UDim2.new(0, NBW, 0, math.floor(24*scale))
    NMB.Position = UDim2.new(0, PAD, 0, y)
    NMB.BackgroundColor3 = C.Input
    NMB.BackgroundTransparency = 0.05
    NMB.Text = ""
    NMB.PlaceholderText = "玩家名"
    NMB.PlaceholderColor3 = C.Dim
    NMB.TextColor3 = C.Text
    NMB.Font = Enum.Font.Gotham
    NMB.TextSize = math.max(9, math.floor(12*scale))
    NMB.ClearTextOnFocus = false
    NMB.Parent = CC
    Instance.new("UICorner", NMB).CornerRadius = UDim.new(0, 4)

    local ADB = mkBtn("加入", C.Green, ADW, math.floor(24*scale))
    ADB.Position = UDim2.new(0, PAD + NBW + GAP, 0, y)

    local CLB = mkBtn("清空", C.Red, CLW, math.floor(24*scale))
    CLB.Position = UDim2.new(0, PAD + NBW + GAP + ADW + GAP, 0, y)

    ADB.MouseButton1Click:Connect(function()
        if NMB.Text ~= "" then addWL(NMB.Text); NMB.Text = "" end
    end)
    NMB.FocusLost:Connect(function(ep)
        if ep and NMB.Text ~= "" then addWL(NMB.Text); NMB.Text = "" end
    end)
    CLB.MouseButton1Click:Connect(function()
        for n in pairs(WL) do WL[n] = nil end
    end)

    print("✅ SCP异常站点 UI创建完成")
end)

-- ==================== 状态更新循环 ====================
task.spawn(function()
    while true do task.wait(0.400)
        -- 刷新自己的角色
        UpdateMyRole()

        local roleCN = RoleCN(myRole)
        local wepName = (CurrentWeaponName ~= "无") and CurrentWeaponName or "无武器"
        local wepID = CurrentWeaponID and (string.sub(CurrentWeaponID, 1, 8) .. "...") or "无"

        local enemyCount = 0
        local violateCount = 0
        local escapeCount = 0
        local foundationCount = 0
        local chaosCount = 0
        local dclassCount = 0

        local myHRP = player.Character and player.Character:FindFirstChild("HumanoidRootPart")

        if myHRP then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= player and p.Character then
                    local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                    local hum = p.Character:FindFirstChildOfClass("Humanoid")
                    if hrp and hum and hum.Health > 0 then
                        local d = (hrp.Position - myHRP.Position).Magnitude
                        local role = GetRole(p) or ""

                        if d <= MAX_RANGE and IsEnemy(p) then
                            enemyCount = enemyCount + 1
                        end
                        if IsHostile(p) then violateCount = violateCount + 1 end
                        if IsEscaped(p) then escapeCount = escapeCount + 1 end
                        if FOUNDATION[role] then foundationCount = foundationCount + 1 end
                        if CHAOS[role] then chaosCount = chaosCount + 1 end
                        if DCLASS[role] then dclassCount = dclassCount + 1 end
                    end
                end
            end
        end

        -- 状态栏：职业 / 武器 / ID + 计数
        local status = ""
        status = status .. "职业:" .. roleCN .. "\n"
        status = status .. "武器:" .. wepName .. "\n"
        status = status .. "ID:" .. wepID .. "\n"
        status = status .. "敌人:" .. enemyCount
        status = status .. " 违规:" .. violateCount
        status = status .. " 逃出:" .. escapeCount .. "\n"
        status = status .. "基金会:" .. foundationCount
        status = status .. " 混沌:" .. chaosCount
        status = status .. " D级:" .. dclassCount
        status = status .. " 门:" .. DoorCount

        if UI.StatusLabel then
            pcall(function() UI.StatusLabel.Text = status end)
        end

        -- 玩家列表（详细版，标注关系）
        if UI.PlayerListLabel and ListVisible then
            local listText = ""
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= player then
                    local role = GetRole(p) or ""
                    local cn = RoleCN(role)
                    local isE = IsEnemy(p)
                    local viol = IsHostile(p)
                    local esc = IsEscaped(p)
                    local dist = ""
                    if myHRP and p.Character then
                        local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            dist = string.format("%.0f", (myHRP.Position - hrp.Position).Magnitude)
                        end
                    end

                    -- 关系判定
                    local rel = ""
                    if isE then
                        rel = "⚠️敌人"
                    elseif viol then
                        rel = "❗违规"
                    elseif esc then
                        rel = "🏃逃出"
                    elseif FOUNDATION[role] then
                        rel = "🛡️友军"
                    elseif CHAOS[role] then
                        if DCLASS[myRole] then
                            rel = "🤝盟友"
                        else
                            rel = "⚠️敌人"
                        end
                    elseif DCLASS[role] then
                        if DCLASS[myRole] then
                            rel = "🤝同袍"
                        elseif CHAOS[myRole] then
                            rel = "🤝盟友"
                        else
                            rel = "❓D级"
                        end
                    else
                        rel = "❓未知"
                    end

                    local wlMark = isWL(p) and "⭐" or ""
                    listText = listText .. wlMark .. p.Name .. " [" .. cn .. "] " .. rel .. " " .. dist .. "m\n"
                end
            end
            pcall(function() UI.PlayerListLabel.Text = listText end)
        end
    end
end)

-- ==================== 启动日志 ====================
print("✅ SCP异常站点 v2.0 已启动")
print("📦 功能：射击 | 近战 | 射线检测 | 显示弹道 | 范围 | 透视 | 穿门")
print("🚪 穿门路径：Workspace.Map.Doors")
print("⚔️ D级只攻基金会，不攻任何D级（违规/逃出均不打）")
print("❗ 违规=Hostile可见 → 非D级攻击 | 🏃 逃出=Escaped可见 → 非D级攻击")
print("📱 手机端UI自动缩小0.5倍 | 透视UI自动缩小")
print("⌨️ 点击射程/近战按钮输入距离 | 武器自动扫描")
