--// [REDACTED] | Build
local WindUI
do
    local ok, res = pcall(function()
        return loadstring(game:HttpGet("https://raw.githubusercontent.com/qewwwwwww/666/main/ui.lua", true))()
    end)
    if ok and res then
        WindUI = res
    else
        warn("UI 加载失败")
        return
    end
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local char = nil

local PR = nil
task.spawn(function()
    local ref = ReplicatedStorage:FindFirstChild("REFERENCES", true)
    if ref then
        local pr = ref:FindFirstChild("PacketReference")
        if pr then
            pcall(function() PR = require(pr) end)
        end
    end
end)

local PU = nil
task.spawn(function()
    pcall(function()
        PU = require(ReplicatedStorage.MODULES.ProjectileUtility)
    end)
end)

local Window = WindUI:CreateWindow({
    Title = "莱克星顿和康科德",
    Icon = "sword",
    Size = UDim2.fromOffset(480, 380),
})

WindUI:Notify({ Title = "莱克星顿和康科德", Content = "脚本已加载 | 按G键开关菜单", Icon = "check", Duration = 3 })

local KillTab = Window:Tab({ Title = "杀戮", Icon = "crosshair", Desc = "近战自动攻击" })
local GunTab = Window:Tab({ Title = "枪械", Icon = "zap", Desc = "枪械辅助功能" })
local FunTab = Window:Tab({ Title = "娱乐", Icon = "smile", Desc = "娱乐功能" })
local CharTab = Window:Tab({ Title = "角色", Icon = "user", Desc = "坐标加速 + 飞行" })
local BypassTab = Window:Tab({ Title = "绕过", Icon = "shield", Desc = "反作弊绕过" })
local InfoTab = Window:Tab({ Title = "信息", Icon = "info", Desc = "游戏信息" })

local CFG = { ON = false, TEAM = true, RANGE = 7, COOLDOWN = 0.3, NO_EQUIP = false }
local lastHit = 0
local meleeTool = nil

local function isMeleeName(n)
    n = n:lower()
    return n:find("saber") or n:find("sword") or n:find("knife")
        or n:find("melee") or n:find("bayonet") or n:find("blade")
        or n:find("axe") or n:find("hatchet") or n:find("chopper")
end

local recoilOn = false
local origRecoil = nil

local animatorHooked = {}
local IRCFG = { ON = false, SPEED = 999 }

local function isReloadTrack(t)
    if not t or not t:IsA("AnimationTrack") then return false end
    return t.Name:lower():find("reload") ~= nil
end

local function procTrack(t)
    if not t or not t:IsA("AnimationTrack") or not t.IsPlaying then return end
    if IRCFG.ON and isReloadTrack(t) then
        pcall(function() t:AdjustSpeed(IRCFG.SPEED) end)
    end
end

local function hookAnr(anr)
    if not anr or animatorHooked[anr] then return end
    animatorHooked[anr] = true
    anr.AnimationPlayed:Connect(function(t)
        if not t then return end
        if IRCFG.ON and isReloadTrack(t) then
            pcall(function() t:AdjustSpeed(IRCFG.SPEED) end)
            task.spawn(function()
                while t and t.IsPlaying and IRCFG.ON do
                    if math.abs(t.Speed - IRCFG.SPEED) > 1 then
                        pcall(function() t:AdjustSpeed(IRCFG.SPEED) end)
                    end
                    task.wait(0.03)
                end
            end)
        end
    end)
end

local function scanAnr()
    if not char then return end
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("Animator") then hookAnr(d) end
    end
end

LP.CharacterAdded:Connect(function(c)
    task.wait(0.3)
    char = c
    scanAnr()
    c.DescendantAdded:Connect(function(d)
        if d:IsA("Animator") then hookAnr(d) end
    end)
end)
if LP.Character then
    char = LP.Character
    scanAnr()
    char.DescendantAdded:Connect(function(d)
        if d:IsA("Animator") then hookAnr(d) end
    end)
end

task.spawn(function()
    while true do
        task.wait(0.2)
        if not char or not IRCFG.ON then continue end
        local anr = char:FindFirstChildWhichIsA("Animator")
        if not anr then continue end
        for _, t in ipairs(anr:GetTracks()) do procTrack(t) end
    end
end)

local function getTarget()
    if not char then return nil end
    local myHRP = char:FindFirstChild("HumanoidRootPart")
    if not myHRP then return nil end
    local myTeam = LP.Team
    local myColor = LP.TeamColor
    local best, bd = nil, tonumber(CFG.RANGE) or 7
    local isAxe = meleeTool and (meleeTool.Name:lower():find("axe") or meleeTool.Name:lower():find("hatchet") or meleeTool.Name:lower():find("bayonet"))
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end
        if CFG.TEAM then
            if myTeam and p.Team and p.Team == myTeam then continue end
            if myColor and p.TeamColor and p.TeamColor == myColor then continue end
        end
        if not p.Character then continue end
        local hum = p.Character:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        local ehrp = p.Character:FindFirstChild("HumanoidRootPart")
        if not ehrp then continue end
        local d = (ehrp.Position - myHRP.Position).Magnitude
        if d > bd then continue end
        local target
        if isAxe then
            target = p.Character:FindFirstChild("Left Arm") or p.Character:FindFirstChild("Right Arm") or p.Character:FindFirstChild("Head") or ehrp
        else
            target = p.Character:FindFirstChild("Head") or ehrp
        end
        if d < bd then bd = d; best = target end
    end
    return best
end

local function sendHit(tp)
    if not tp or not PR then return end
    local tool = meleeTool
    if not tool and CFG.NO_EQUIP then
        local bp = LP:FindFirstChild("Backpack")
        if bp then
            for _, t in ipairs(bp:GetChildren()) do
                if t:IsA("Tool") and isMeleeName(t.Name) then tool = t; break end
            end
        end
    end
    if not tool then return end
    local ht = "Humanoid"
    local pr = tp.Parent
    if pr and pr:FindFirstChildOfClass("Humanoid") then
        ht = "Humanoid"
    elseif tp:GetAttribute("BreakableBy") or (pr and pr:GetAttribute("ModuleLoaded")) then
        ht = "ToolBreakable"
    else
        ht = "Construct"
    end
    local myHRP = char:FindFirstChild("HumanoidRootPart")
    local kd = Vector3.zero
    local ko = Vector3.zero
    if myHRP then kd = (tp.Position - myHRP.Position).Unit * 60; ko = myHRP.Position end
    pcall(function()
        PR.MeleeHitRegistration.send({ Type = ht, Tool = tool, hitInstance = tp, knockbackOrigin = ko, knockbackDirection = kd })
    end)
end

local function ensureAxe()
    if not meleeTool or not PR then return end
    local n = meleeTool.Name:lower()
    if not (n:find("axe") or n:find("hatchet") or n:find("bayonet")) then return end
    if meleeTool:GetAttribute("isMeleeEquipped") then return end
    meleeTool:SetAttribute("isMeleeEquipped", true)
    pcall(function() PR.GunMeleeStatus.send({ isEquipped = true, Tool = meleeTool }) end)
end

local function onToolAdd(v)
    if not v:IsA("Tool") then return end
    if not isMeleeName(v.Name) then return end
    meleeTool = v
    ensureAxe()
end
local function onToolRem(v) if v == meleeTool then meleeTool = nil end end

local function bindChar(c)
    char = c; meleeTool = nil
    c.ChildAdded:Connect(onToolAdd)
    c.ChildRemoved:Connect(onToolRem)
    local bp = LP:FindFirstChild("Backpack")
    if bp then bp.ChildAdded:Connect(onToolAdd); bp.ChildRemoved:Connect(onToolRem) end
    for _, v in ipairs(c:GetChildren()) do onToolAdd(v) end
    if bp then for _, v in ipairs(bp:GetChildren()) do onToolAdd(v) end end
end

LP.CharacterAdded:Connect(function(c) task.wait(0.3); bindChar(c) end)
if LP.Character then bindChar(LP.Character) end

--// G键开关 + 鼠标控制
local menuVisible = true
local savedMouseIconEnabled = nil

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.G then
        menuVisible = not menuVisible
        pcall(function() Window:Toggle() end)
        if menuVisible then
            savedMouseIconEnabled = UserInputService.MouseIconEnabled
            UserInputService.MouseIconEnabled = true
        else
            if savedMouseIconEnabled ~= nil then
                UserInputService.MouseIconEnabled = savedMouseIconEnabled
            else
                UserInputService.MouseIconEnabled = false
            end
        end
    end
end)

--// ═══ 杀戮 Tab ═══
KillTab:Section({ Title = "自动攻击", TextSize = 14 })
local statusP = KillTab:Paragraph({ Title = "状态", Desc = "等待武器...", Image = "circle-help", ImageSize = 16 })

RunService.Heartbeat:Connect(function()
    if not meleeTool then statusP:SetDesc("等待武器...")
    elseif meleeTool.Parent == char then statusP:SetDesc("⚔ " .. meleeTool.Name .. " | 已装备")
    else statusP:SetDesc("🎒 " .. meleeTool.Name .. " | 背包") end
end)

KillTab:Divider()
KillTab:Toggle({ Title = "杀戮光环", Desc = "持续自动攻击最近的敌人", Value = false,
    Callback = function(v) CFG.ON = v; WindUI:Notify({ Title = "杀戮光环", Content = v and "已开启" or "已关闭", Icon = "check", Duration = 2 }) end })
KillTab:Toggle({ Title = "队伍检测", Desc = "不攻击同队的玩家", Value = true, Callback = function(v) CFG.TEAM = v end })
KillTab:Toggle({ Title = "无需装备攻击", Desc = "不装备武器直接攻击", Value = false,
    Callback = function(v) CFG.NO_EQUIP = v; WindUI:Notify({ Title = "无需装备攻击", Content = v and "已开启" or "已关闭", Icon = "check", Duration = 2 }) end })
KillTab:Divider()
KillTab:Slider({ Title = "攻击范围", Desc = "近战攻击距离", Value = { Min = 1, Max = 12, Default = 7 }, Step = 1, Callback = function(v) CFG.RANGE = tonumber(v) or 7 end })
KillTab:Slider({ Title = "攻击间隔", Desc = "每次攻击间隔", Value = { Min = 0.1, Max = 1.0, Default = 0.3 }, Step = 0.05, Callback = function(v) CFG.COOLDOWN = tonumber(v) or 0.3 end })

--// ═══ 枪械 Tab — 换弹加速 ═══
GunTab:Section({ Title = "换弹加速", TextSize = 14 })
local RLC = { ON = false, SPEED = 1.6 }

GunTab:Toggle({ Title = "换弹加速", Value = false,
    Callback = function(v) RLC.ON = v; WindUI:Notify({ Title = "换弹加速", Content = v and "已开启" or "已关闭", Icon = "check", Duration = 2 }) end })
GunTab:Slider({ Title = "换弹倍率", Desc = "1.0 = 正常 | 1.6 = 极限", Value = { Min = 1.0, Max = 1.6, Default = 1.6 }, Step = 0.1, Callback = function(v) RLC.SPEED = tonumber(v) or 1.6 end })
GunTab:Divider()
GunTab:Paragraph({ Title = "说明", Desc = "旗帜手增益无法覆盖", Image = "info", ImageSize = 16 })

task.spawn(function()
    while true do
        task.wait(0.1)
        if not RLC.ON then continue end
        if not char then continue end
        local c = char:GetAttribute("buff_FasterReload")
        if c ~= RLC.SPEED then char:SetAttribute("buff_FasterReload", RLC.SPEED) end
    end
end)

LP.CharacterAdded:Connect(function(c)
    task.wait(0.3); char = c
    if RLC.ON then char:SetAttribute("buff_FasterReload", RLC.SPEED) end
end)

--// ═══ 枪械 Tab — 零后坐力 ═══
GunTab:Divider()
GunTab:Section({ Title = "后坐力控制", TextSize = 14 })

GunTab:Toggle({ Title = "零后坐力", Desc = "关不掉", Value = false,
    Callback = function(v)
        if v then
            if not PU then pcall(function() PU = require(ReplicatedStorage.MODULES.ProjectileUtility) end) end
            if PU then
                if not origRecoil then origRecoil = PU.GetRecoilOffset end
                hookfunction(PU.GetRecoilOffset, function() return 0 end)
                recoilOn = true
                WindUI:Notify({ Title = "零后坐力", Content = "已开启", Icon = "check", Duration = 2 })
            else
                WindUI:Notify({ Title = "零后坐力", Content = "模块未就绪", Icon = "x", Duration = 2 })
            end
        else
            if PU and origRecoil then
                hookfunction(PU.GetRecoilOffset, origRecoil)
            end
            recoilOn = false
            WindUI:Notify({ Title = "零后坐力", Content = "已关闭", Icon = "info", Duration = 2 })
        end
    end
})

--// ═══ 娱乐 Tab — 转圈 ═══
FunTab:Section({ Title = "转圈", TextSize = 14 })
local SC = { ON = false, SPEED = 25 }

FunTab:Toggle({ Title = "开启转圈", Desc = "背起了行囊", Value = false,
    Callback = function(v) SC.ON = v; WindUI:Notify({ Title = "极速转圈", Content = v and "已开启 " or "已关闭 ⏹", Icon = "check", Duration = 2 }) end })
FunTab:Slider({ Title = "旋转速度", Value = { Min = 5, Max = 50, Default = 25 }, Step = 5, Callback = function(v) SC.SPEED = tonumber(v) or 25 end })
FunTab:Divider()
FunTab:Paragraph({ Title = "说明", Desc = "开启后角色高速旋转，关闭后自动恢复朝向", Image = "info", ImageSize = 16 })

local sy = 0
RunService.Heartbeat:Connect(function(dt)
    if not SC.ON then
        if char then local h = char:FindFirstChildOfClass("Humanoid"); if h then h.AutoRotate = true end end
        sy = 0; return
    end
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end
    hum.AutoRotate = false
    sy = sy + SC.SPEED * dt
    hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, sy, 0)
end)

--// ═══ 娱乐 Tab — 秒换弹 ═══
FunTab:Divider()
FunTab:Section({ Title = "秒换弹", TextSize = 14 })

FunTab:Toggle({ Title = "秒换弹", Desc = "可能打不死人", Value = false,
    Callback = function(v)
        IRCFG.ON = v
        if v then scanAnr(); WindUI:Notify({ Title = "秒换弹", Content = "已开启 | 速度 x" .. IRCFG.SPEED, Icon = "zap", Duration = 2 })
        else WindUI:Notify({ Title = "秒换弹", Content = "已关闭", Icon = "info", Duration = 2 }) end
    end
})
FunTab:Slider({ Title = "换弹速度倍率", Desc = "默认999 = 瞬间完成", Value = { Min = 10, Max = 9999, Default = 999 }, Step = 10, Callback = function(v) IRCFG.SPEED = tonumber(v) or 999 end })

--// ═══ 角色 Tab — 坐标加速 + 飞行 ═══
CharTab:Section({ Title = "坐标加速", TextSize = 14 })
CharTab:Paragraph({
    Title = "提示",
    Desc = "没有绕过反作弊就把倍速调至 0.6 不会被踢",
    Image = "info", ImageSize = 16
})

local SpeedCFG = { ON = false, MULT = 0.6 }

CharTab:Toggle({
    Title = "启用坐标加速",
    Desc = "绕过反作弊后你就跑去吧老快了",
    Value = false,
    Callback = function(v)
        SpeedCFG.ON = v
        WindUI:Notify({
            Title = "坐标加速",
            Content = v and ("已开启 | 当前 " .. tostring(SpeedCFG.MULT) .. "x") or "已关闭",
            Icon = "check", Duration = 2
        })
    end
})

CharTab:Slider({
    Title = "加速倍率",
    Value = { Min = 0.1, Max = 10, Default = 0.6 },
    Step = 0.1,
    Callback = function(v)
        SpeedCFG.MULT = math.floor((tonumber(v) or 0.6) * 10 + 0.5) / 10
    end
})

local function applySpeedTick()
    if not SpeedCFG.ON then return end
    local c = LP.Character
    if not c then return end
    local hum = c:FindFirstChildOfClass("Humanoid")
    local root = c:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end
    local dir = hum.MoveDirection
    if not dir or dir.Magnitude < 0.01 then return end
    local step = SpeedCFG.MULT * 0.125
    root.CFrame = root.CFrame + (dir.Unit * step)
end

CharTab:Divider()
CharTab:Section({ Title = "飞行", TextSize = 14 })
CharTab:Paragraph({
    Title = "说明",
    Desc = "F键飞行 | 空格上升 | 左Ctrl下降",
    Image = "info", ImageSize = 16
})

--// 飞行核心状态
local flying = false
local heightLocked = true
local lockedY = 0
local flySpeed = 0.52
local shiftLockOn = false

local function GetRoot()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function GetHum()
    local c = LP.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function ApplyShiftLock(state)
    local c = LP.Character
    if c then c:SetAttribute("isShiftLocked", state) end
end

--// UI Toggles
local flyToggle = CharTab:Toggle({
    Title = "飞行开关",
    Desc = "F键 / 手机按钮",
    Value = false,
    Callback = function(v)
        flying = v
        local root = GetRoot()
        if root then
            if flying then
                lockedY = root.CFrame.Position.Y
                heightLocked = true
                WindUI:Notify({ Title = "飞行", Content = "已开启 | 高度锁定", Icon = "check", Duration = 2 })
            else
                heightLocked = false
                WindUI:Notify({ Title = "飞行", Content = "已关闭", Icon = "info", Duration = 2 })
            end
        end
    end
})

local shiftLockToggle = CharTab:Toggle({
    Title = "视角锁定",
    Desc = "左Shift(最高优先级) / 手机按钮",
    Value = false,
    Callback = function(v)
        shiftLockOn = v
        ApplyShiftLock(v)
        WindUI:Notify({ Title = "视角锁定", Content = v and "已开启" or "已关闭", Icon = "info", Duration = 2 })
    end
})

CharTab:Divider()

--// 手机端按钮
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local flyBtnUpHeld = false
local flyBtnDownHeld = false
local mobileBtnFly = nil
local mobileBtnLock = nil

if isMobile then
    local guiParent
    if WindUI.GetGUI then guiParent = WindUI:GetGUI()
    elseif WindUI.GetScreenGui then guiParent = WindUI:GetScreenGui()
    else guiParent = game:GetService("CoreGui") end

    local btnUp = Instance.new("TextButton")
    btnUp.Size = UDim2.new(0, 55, 0, 45)
    btnUp.Position = UDim2.new(1, -65, 1, -180)
    btnUp.Text = "↑"
    btnUp.TextScaled = true
    btnUp.TextColor3 = Color3.fromRGB(255, 255, 255)
    btnUp.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    btnUp.BorderSizePixel = 0
    btnUp.Parent = guiParent

    local btnDown = Instance.new("TextButton")
    btnDown.Size = UDim2.new(0, 55, 0, 45)
    btnDown.Position = UDim2.new(1, -65, 1, -130)
    btnDown.Text = "↓"
    btnDown.TextScaled = true
    btnDown.TextColor3 = Color3.fromRGB(255, 255, 255)
    btnDown.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    btnDown.BorderSizePixel = 0
    btnDown.Parent = guiParent

    mobileBtnLock = Instance.new("TextButton")
    mobileBtnLock.Size = UDim2.new(0, 55, 0, 35)
    mobileBtnLock.Position = UDim2.new(1, -65, 1, -80)
    mobileBtnLock.Text = "视角"
    mobileBtnLock.TextScaled = true
    mobileBtnLock.TextColor3 = Color3.fromRGB(255, 255, 255)
    mobileBtnLock.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    mobileBtnLock.BorderSizePixel = 0
    mobileBtnLock.Parent = guiParent

    mobileBtnFly = Instance.new("TextButton")
    mobileBtnFly.Size = UDim2.new(0, 55, 0, 35)
    mobileBtnFly.Position = UDim2.new(1, -65, 1, -30)
    mobileBtnFly.Text = "飞行"
    mobileBtnFly.TextScaled = true
    mobileBtnFly.TextColor3 = Color3.fromRGB(255, 255, 255)
    mobileBtnFly.BackgroundColor3 = Color3.fromRGB(80, 40, 40)
    mobileBtnFly.BorderSizePixel = 0
    mobileBtnFly.Parent = guiParent

    btnUp.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then flyBtnUpHeld = true end
    end)
    btnUp.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then flyBtnUpHeld = false end
    end)

    btnDown.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then flyBtnDownHeld = true end
    end)
    btnDown.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then flyBtnDownHeld = false end
    end)

    mobileBtnLock.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            shiftLockOn = not shiftLockOn
            ApplyShiftLock(shiftLockOn)
            shiftLockToggle:SetValue(shiftLockOn)
            mobileBtnLock.BackgroundColor3 = shiftLockOn and Color3.fromRGB(40, 120, 40) or Color3.fromRGB(60, 60, 60)
        end
    end)

    mobileBtnFly.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            flying = not flying
            local root = GetRoot()
            if root then
                if flying then
                    lockedY = root.CFrame.Position.Y
                    heightLocked = true
                    mobileBtnFly.BackgroundColor3 = Color3.fromRGB(40, 120, 40)
                else
                    heightLocked = false
                    mobileBtnFly.BackgroundColor3 = Color3.fromRGB(80, 40, 40)
                end
            end
            flyToggle:SetValue(flying)
        end
    end)
end

--// 视角锁定强制保活（每帧覆写，最高优先级）
RunService.RenderStepped:Connect(function()
    if shiftLockOn then
        local c = LP.Character
        if c then c:SetAttribute("isShiftLocked", true) end
    end
end)

--// 飞行主循环
RunService.RenderStepped:Connect(function()
    applySpeedTick()

    if not flying then return end
    local root = GetRoot()
    local hum = GetHum()
    if not root or not hum then return end

    local pos = root.CFrame.Position
    local rot = root.CFrame.Rotation

    local moveDir = hum.MoveDirection
    local dx = moveDir.X * 0.20
    local dz = moveDir.Z * 0.23

    local space = UserInputService:IsKeyDown(Enum.KeyCode.Space)
    local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
    local upHeld = space
    local downHeld = ctrl

    if isMobile then
        upHeld = upHeld or flyBtnUpHeld
        downHeld = downHeld or flyBtnDownHeld
    end

    if heightLocked then
        if upHeld then lockedY = lockedY + flySpeed end
        if downHeld then lockedY = lockedY - flySpeed end
        root.CFrame = CFrame.new(pos.X + dx, lockedY, pos.Z + dz) * rot
    else
        local dy = 0
        if upHeld then dy = flySpeed end
        if downHeld then dy = -flySpeed end
        root.CFrame = CFrame.new(pos.X + dx, pos.Y + dy, pos.Z + dz) * rot
    end

    root.Velocity = Vector3.zero
    root.AssemblyLinearVelocity = Vector3.zero
    root.RotVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end)

--// 电脑按键（左Shift 无视 gameProcessed，强制最高优先级）
UserInputService.InputBegan:Connect(function(input, gp)
    local k = input.KeyCode

    -- 左Shift 视角锁定（放在 gp 检查之前，强制拦截）
    if k == Enum.KeyCode.LeftShift then
        shiftLockOn = not shiftLockOn
        ApplyShiftLock(shiftLockOn)
        shiftLockToggle:SetValue(shiftLockOn)
        if mobileBtnLock then
            mobileBtnLock.BackgroundColor3 = shiftLockOn and Color3.fromRGB(40, 120, 40) or Color3.fromRGB(60, 60, 60)
        end
        WindUI:Notify({ Title = "视角锁定", Content = shiftLockOn and "已开启" or "已关闭", Icon = "info", Duration = 2 })
        return
    end

    if gp then return end

    -- F 键飞行（不再碰视角锁定）
    if k == Enum.KeyCode.F then
        flying = not flying
        local root = GetRoot()
        if root then
            if flying then
                lockedY = root.CFrame.Position.Y
                heightLocked = true
                WindUI:Notify({ Title = "飞行", Content = "已开启 | 高度锁定", Icon = "check", Duration = 2 })
            else
                heightLocked = false
                WindUI:Notify({ Title = "飞行", Content = "已关闭", Icon = "info", Duration = 2 })
            end
        end
        flyToggle:SetValue(flying)
        if mobileBtnFly then
            mobileBtnFly.BackgroundColor3 = flying and Color3.fromRGB(40, 120, 40) or Color3.fromRGB(80, 40, 40)
        end
        return
    end

    -- Z 键高度锁定
    if k == Enum.KeyCode.Z and flying then
        heightLocked = not heightLocked
        local root = GetRoot()
        if heightLocked and root then
            lockedY = root.CFrame.Position.Y
        end
        WindUI:Notify({ Title = "高度锁定", Content = heightLocked and "已开启" or "已关闭（自由模式）", Icon = "info", Duration = 2 })
        return
    end
end)

--// ═══ 绕过 Tab ═══
BypassTab:Section({ Title = "反作弊绕过", TextSize = 14 })
BypassTab:Paragraph({
    Title = "说明",
    Desc = "开启后使用炮兵寻找大炮坐上大炮，一个大炮只能绕过一次",
    Image = "info", ImageSize = 16
})

local BypassCFG = { ON = false, Interval = 0.5 }
local cannonNames = {
    ["Howitzer"] = true,
    ["AmericanCannon"] = true,
    ["NavalCannon"] = true,
    ["Mortar"] = true,
}

local function getClosestCannon(charRoot)
    local mapInteractables = workspace:FindFirstChild("MapContainer")
        and workspace.MapContainer:FindFirstChild("Interactables")
    if not mapInteractables then return nil end

    local closestCannon = nil
    local closestDist = math.huge

    for _, obj in pairs(mapInteractables:GetChildren()) do
        if cannonNames[obj.Name] then
            local seatPart = obj:FindFirstChild("Important")
                and obj.Important:FindFirstChild("SeatPart")
            if seatPart then
                local dist = (seatPart.Position - charRoot.Position).Magnitude
                if dist < closestDist then
                    closestDist = dist
                    closestCannon = { cannon = obj, seat = seatPart, dist = dist }
                end
            end
        end
    end

    return closestCannon
end

local function doBypassTick()
    local c = LP.Character
    if not c then return end
    local root = c:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local artillery = c:FindFirstChild("Artillery")
    if not artillery then return end

    local closest = getClosestCannon(root)
    local bypassMsg = "绕过失败"
    if closest then
        pcall(function() closest.seat:Destroy() end)
        bypassMsg = "绕过成功"
    end

    pcall(function() artillery:Destroy() end)

    WindUI:Notify({
        Title = "反作弊绕过",
        Content = bypassMsg,
        Icon = "check", Duration = 2
    })
end

local function startBypassLoop()
    task.spawn(function()
        while BypassCFG.ON do
            pcall(doBypassTick)
            task.wait(BypassCFG.Interval)
        end
    end)
end

BypassTab:Toggle({
    Title = "启用反作弊绕过",
    Desc = "请上大炮",
    Value = false,
    Callback = function(v)
        BypassCFG.ON = v
        if v then
            WindUI:Notify({ Title = "反作弊绕过", Content = "已开启", Icon = "check", Duration = 2 })
            startBypassLoop()
        else
            WindUI:Notify({ Title = "反作弊绕过", Content = "已关闭", Icon = "check", Duration = 2 })
        end
    end
})


--// ═══ 信息 Tab ═══
InfoTab:Section({ Title = "游戏信息", TextSize = 14 })
InfoTab:Paragraph({ Title = "游戏名称", Desc = "莱克星顿和康科德", Image = "gamepad-2", ImageSize = 16 })
InfoTab:Paragraph({ Title = "游戏ID", Desc = tostring(game.GameId), Image = "hash", ImageSize = 16 })
InfoTab:Paragraph({ Title = "地图ID", Desc = tostring(game.PlaceId), Image = "map-pin", ImageSize = 16 })
InfoTab:Divider()
local fpsP = InfoTab:Paragraph({ Title = "帧率", Desc = "--", Image = "activity", ImageSize = 16 })
local wp = InfoTab:Paragraph({ Title = "当前武器", Desc = "无", Image = "sword", ImageSize = 16 })
local sp = InfoTab:Paragraph({ Title = "转圈状态", Desc = " 停止", Image = "refresh-cw", ImageSize = 16 })
local accelP = InfoTab:Paragraph({ Title = "坐标加速", Desc = " 关闭 | 0.6x", Image = "zap", ImageSize = 16 })
local bypassP = InfoTab:Paragraph({ Title = "反作弊绕过", Desc = " 关闭", Image = "shield", ImageSize = 16 })
local flyP = InfoTab:Paragraph({ Title = "飞行", Desc = " 关闭", Image = "bird", ImageSize = 16 })

local ft = tick()
local fpsTimer = 0
RunService.Heartbeat:Connect(function()
    local n = tick()
    local dt = n - ft
    ft = n

    fpsTimer = fpsTimer + dt
    if fpsTimer >= 0.1 and dt > 0 then
        fpsP:SetDesc(tostring(math.floor(1 / dt)) .. " FPS")
        fpsTimer = 0
    end

    if meleeTool then
        local l = meleeTool.Parent == char and "已装备" or "背包"
        wp:SetDesc(meleeTool.Name .. " | " .. l)
    else
        wp:SetDesc("无")
    end

    sp:SetDesc(SC.ON and " 旋转中 | 速度 " .. SC.SPEED or "⏹停止")
    accelP:SetDesc(SpeedCFG.ON and (" 开启 | " .. tostring(SpeedCFG.MULT) .. "x") or (" 关闭 | " .. tostring(SpeedCFG.MULT) .. "x"))
    bypassP:SetDesc(BypassCFG.ON and " 开启 | 检测中" or " 关闭")
    flyP:SetDesc(flying and " 飞行中" or " 关闭")
end)

--// ═══ 主攻击循环 ═══
RunService.Heartbeat:Connect(function()
    if not CFG.ON then return end
    if tick() - lastHit < CFG.COOLDOWN then return end
    if not CFG.NO_EQUIP then
        if not meleeTool or not char then return end
        if meleeTool.Parent ~= char then return end
    end
    local t = getTarget()
    if not t then return end
    sendHit(t)
    lastHit = tick()
    statusP:SetDesc(" 命中: " .. t.Parent.Name)
end)
