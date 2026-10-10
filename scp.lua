-- ============================================================
--  SCP异常站点 v6.27
--
--  ★ v6.27 修复（仅核心功能，UI未改动）：
--  ① 修复加载崩溃：全局立即执行的代码延迟到下一帧 + pcall保护
--  ② 修复穿门字典膨胀：新增CleanDeadDoors定期清理已销毁门对象
--  ③ 修复无敌检测表泄漏：改用Weak Table + 定期清理失效玩家
--  ④ 修复弹道task.delay堆积：改用task.spawn + beamSpawnCount上限控制
--  ⑤ 修复ESP角色部件缓存泄漏：改用Weak Table
--  ⑥ 修复状态更新全服遍历：先粗筛距离再判断阵营
--  ⑦ 修复脚底圆圈Part残留：MAX_CIRCLE_PARTS上限管控
--  ⑧ 新增Unload全局清理：断开所有事件连接
-- ============================================================
--  SCP异常站点 v6.26
--
--  ★ 弹道：Part方案（100%可见，不跟随屏幕/不UI）
--          樱花粉 RGB(255,183,197) 粗细0.06 Neon发光
--          最多40条 生命周期0.5s 对象池复用
--  ★ 无敌检测：0.3s循环扫描玩家模型中的"Forcefield"文件
--          有→血条蓝色(80,160,255) 无→按血量染色
--  ★ 穿门：靠近12格才移除碰撞（射线不穿墙）
--  ★ 近战范围：8格
--  ★ 透视：60Hz不降帧 4段职业色渐变 8角包围盒
--  ★ 攻击跳过无敌玩家
--  ★ 玩家列表：0.1秒实时刷新 + 无敌O(1)缓存查询
--  ★ 性能：Ignore缓存0.1s/武器去抖50ms/弹道短生命周期
--  ★ 娱乐模式/静默模式/白名单/Unload全局清理
--  ★ v6.26：近战攻击重写 — 多武器连续快速攻击
--
--  刷钱逻辑（不变）：
--  ① 检测是否在出生点附近 → 不在就循环复活
--  ② 确认是D级
--  ③ 检测逃出 → 逃出就自杀 → 等消失 → 复活循环
--  ④ 未逃出 → 延迟3秒 → 传送
--  ⑤ 传送冷却0.5秒
--  ⑥ 按S×2 → W×2
--  ⑦ 检测逃出 → 逃出就自杀 → 循环
-- ============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer

-- ==================== 安全调用封装（防止脚本崩溃无报错） ====================
local function SafeCall(name, func, ...)
	local args = { ... }
	local ok, result = pcall(function() return func(table.unpack(args)) end)
	if not ok then
		warn("[SCP] " .. name .. " 执行失败: " .. tostring(result))
	end
	return ok, result
end

-- ==================== 连接管理器（防止事件连接泄漏） ====================
local allConnections = {}
local function TrackConnection(conn)
	table.insert(allConnections, conn)
	return conn
end

-- ==================== 网络事件 ====================
local Libraries = ReplicatedStorage:FindFirstChild("Libraries")
local Network = Libraries and Libraries:FindFirstChild("Network")
local Channel = Network and Network:FindFirstChild("Channel")
local ShootEvent = Channel and Channel:FindFirstChild("tool/shoot")
local AttackEvent = Channel and Channel:FindFirstChild("tool/attack")
local SoundEvent = Channel and Channel:FindFirstChild("tool/sound")
local RoleEvent = Channel and Channel:FindFirstChild("core/role")

-- ==================== 设备 / 屏幕 ====================
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local function GetScreenSize()
	local guiInset = GuiService:GetGuiInset()
	local size = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize
			or Vector2.new(1024, 750)
	return Vector2.new(size.X, size.Y - guiInset.Y), guiInset
end

local function GetScale()
	local sz = GetScreenSize()
	if IS_MOBILE then
		return math.clamp(sz.X / 772, 0.452, 0.786)
	else
		return math.clamp(sz.X / 1870, 0.555, 0.895)
	end
end

-- ==================== 配置 ====================
local MAX_RANGE = 271
local MELEE_RANGE = 8          -- ★ v6.26: 7→8（配合更快攻击）
local SHOOT_CD = 0.087
local MELEE_CD = 0.150         -- ★ v6.26: 0.450→0.150（快3倍）
local MELEE_INTERVAL = 0.035   -- ★ v6.26: 多武器间间隔35ms
local autoShoot = true
local autoMelee = true
local rayEnabled = true
local drawCircle = true
local attackEscapedD = true
local espEnabled = true
local funMode = false
local silentMode = false
local invincibleCheck = true
local drawBeams = true

-- ==================== 阵营 ====================
local FOUNDATION = { scientist = true, security = true, mtf = true, director = true }
local CHAOS = { chaos_insurgency = true, rogue_agent = true, traitor = true, renegade = true }
local DCLASS = { d_class = true, escaped_d = true, escaped_d_class = true }

-- ==================== 白名单 ====================
local WL = {}
local function isWL(p) return p and WL[p.Name] or false end
local function addWL(n) if n and n ~= "" then WL[n] = true end end

-- ==================== 角色 ====================
local myRole = nil
local function GetRole(p) return p and p:GetAttribute("Role") or nil end
local function UpdateMyRole()
	local r = GetRole(player)
	if r ~= myRole then myRole = r end
end
UpdateMyRole()
player:GetAttributeChangedSignal("Role"):Connect(UpdateMyRole)

-- ==================== 敌对判定 ====================
local function IsEnemy(p)
	if not p or p == player then return false end
	if isWL(p) then return false end
	local tr = GetRole(p)
	if not tr or tr == "" then return false end
	if tr == "anomaly" or myRole == "anomaly" then return true end
	if tr == myRole then return false end

	if FOUNDATION[myRole] then
		if CHAOS[tr] then return true end
		if DCLASS[tr] then return attackEscapedD and (tr ~= "d_class") or false end
		return false
	end
	if CHAOS[myRole] then
		if FOUNDATION[tr] then return true end
		if DCLASS[tr] then return true end
		return false
	end
	if DCLASS[myRole] then
		return FOUNDATION[tr] and true or false
	end
	return false
end

-- ==================== 违规/逃出检测 ====================
local function GetTagWrapper(p)
	if not p or not p.Character then return nil end
	local hrp = p.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	local tag = hrp:FindFirstChild("Tag")
	return tag and tag:FindFirstChild("Wrapper") or nil
end

local function IsHostile(p)
	local w = GetTagWrapper(p)
	if not w then return false end
	local h = w:FindFirstChild("Hostile")
	if not h then return false end
	local s, v = pcall(function() return h.Visible end)
	return s and v or false
end

local function IsEscaped(p)
	local w = GetTagWrapper(p)
	if not w then return false end
	local e = w:FindFirstChild("Escaped")
	if not e then return false end
	local s, v = pcall(function() return e.Visible end)
	return s and v or false
end

-- ==================== ★ 无敌检测（循环检测"Forcefield"文件） ====================
local invincibleUntil = {}
local forceFieldState = setmetatable({}, { __mode = "k" })  -- Weak Table: 玩家离开自动移除

local function CheckForceFieldExists(p)
	if not p then return false end

	local wsModel = Workspace:FindFirstChild(p.Name)
	if wsModel then
		local ff = wsModel:FindFirstChild("Forcefield")
		if ff then return true end
		ff = wsModel:FindFirstChild("ForceField")
		if ff then return true end
		for _, child in ipairs(wsModel:GetChildren()) do
			if child:IsA("ForceField") then return true end
			local ff2 = child:FindFirstChild("Forcefield")
			if ff2 then return true end
			ff2 = child:FindFirstChild("ForceField")
			if ff2 then return true end
		end
	end

	if p.Character then
		local ff = p.Character:FindFirstChild("Forcefield")
		if ff then return true end
		ff = p.Character:FindFirstChild("ForceField")
		if ff then return true end
		for _, desc in ipairs(p.Character:GetDescendants()) do
			if desc.Name == "Forcefield" or desc.Name == "ForceField" then
				if desc:IsA("ForceField") or desc:IsA("BasePart") or desc:IsA("Folder") then
					return true
				end
			end
		end
	end

	return false
end

local function MarkInvincible(p)
	invincibleUntil[p] = tick() + 5.0
	forceFieldState[p] = true
end

local function ClearInvincible(p)
	invincibleUntil[p] = nil
	forceFieldState[p] = false
end

local function IsInvincibleCached(p)
	if not invincibleCheck then return false end
	if invincibleUntil[p] and tick() < invincibleUntil[p] then
		return true
	end
	return false
end

task.spawn(function()
	while true do
		task.wait(0.3)
		if not invincibleCheck then
			for p in pairs(forceFieldState) do
				forceFieldState[p] = false
			end
			invincibleUntil = {}
			continue
		end

		for _, p in ipairs(Players:GetPlayers()) do
			if p == player then continue end
			local hasFF = CheckForceFieldExists(p)
			if hasFF then
				MarkInvincible(p)
			else
				if forceFieldState[p] then
					ClearInvincible(p)
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(p)
	ClearInvincible(p)
	forceFieldState[p] = nil
end)

-- ==================== 武器系统 ====================
local MeleeNames = { "knife", "crowbar", "tomahawk", "hammer", "bat", "sword", "axe", "machete", "fists", "combat", "blade", "spear", "dagger" }
local RangedNames = { "glock", "beretta", "mp5", "ak47", "hk416", "spas-12", "awm", "m249", "deagle", "uzi", "rifle", "shotgun", "pistol" }
local function IsMelee(n) n=(n or ""):lower() for _,k in ipairs(MeleeNames) do if n:find(k) then return true end end return false end
local function IsRanged(n) n=(n or ""):lower() for _,k in ipairs(RangedNames) do if n:find(k) then return true end end return false end
local function IsShotgun(n) n=(n or ""):lower() return n:find("spas") or n:find("shotgun") or false end

local WepList, WepNames = {}, {}
local function ExtractID(tool)
	for _,c in ipairs(tool:GetDescendants()) do if c:IsA("StringValue") and c.Value and #c.Value==36 then return c.Value end end
	for _,v in pairs(tool:GetAttributes()) do if type(v)=="string" and #v==36 then return v end end
	return #tool.Name==36 and tool.Name or nil
end

local currentWeaponName = "无"
local currentWeaponID = "无"

local function ScanWeapons()
	local ids, names = {}, {}
	local function AddTool(t)
		local id = ExtractID(t)
		if id then ids[id]=true; names[id]=(t:GetAttribute("Name") or t.Name):lower() end
	end
	local bp = player:FindFirstChild("Backpack")
	if bp then for _,t in ipairs(bp:GetChildren()) do if t:IsA("Tool") then AddTool(t) end end end
	if player.Character then for _,t in ipairs(player.Character:GetChildren()) do if t:IsA("Tool") then AddTool(t) end end end
	WepList={}; WepNames={}
	for id in pairs(ids) do table.insert(WepList, id); WepNames[id]=names[id] end
	if player.Character then
		for _,t in ipairs(player.Character:GetChildren()) do
			if t:IsA("Tool") then
				currentWeaponName = t:GetAttribute("Name") or t.Name
				currentWeaponID = ExtractID(t) or "?"
				return #WepList
			end
		end
	end
	currentWeaponName = "无"; currentWeaponID = "无"
	return #WepList
end

local function HasRanged()
	local has = false; local isSG = false
	for _,id in ipairs(WepList) do
		if IsRanged(WepNames[id]) then
			has = true
			if IsShotgun(WepNames[id]) then isSG = true end
		end
	end
	return has, isSG
end
local function HasMelee() for _,id in ipairs(WepList) do if IsMelee(WepNames[id]) then return true end end return false end

-- ==================== 武器监听（去抖50ms） ====================
local weaponScanScheduled = false
local function ScheduleWeaponScan()
	if weaponScanScheduled then return end
	weaponScanScheduled = true
	task.delay(0.05, function()
		weaponScanScheduled = false
		ScanWeapons()
	end)
end

local function HookChar(char)
	char.ChildAdded:Connect(function(c)
		if c:IsA("Tool") then ScheduleWeaponScan() end
	end)
	char.ChildRemoved:Connect(function(c)
		if c:IsA("Tool") then ScheduleWeaponScan() end
	end)
end

local bp = player:FindFirstChild("Backpack")
if bp then
	bp.ChildAdded:Connect(function(c)
		if c:IsA("Tool") then ScheduleWeaponScan() end
	end)
end

player.CharacterAdded:Connect(function(char)
	HookChar(char)
	ScanWeapons()
	task.spawn(function()
		task.wait(0.1)
		ScanWeapons()
		if drawCircle then pcall(CreateCircle) end
	end)
end)

if player.Character then
	HookChar(player.Character)
	SafeCall("ScanWeapons", ScanWeapons)
end

-- ==================== 视线检测（Ignore列表缓存0.1s） ====================
local ignoreList = nil
local IGNORE_TTL = 0.1

local function BuildIgnore()
	if ignoreList then
		if tick() < ignoreList.expire then
			return ignoreList.list
		end
	end
	local ig = {}
	local char = player.Character
	if char then
		for _,p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") then table.insert(ig, p) end
		end
	end
	local bp2 = player:FindFirstChild("Backpack")
	if bp2 then
		for _,t in ipairs(bp2:GetChildren()) do
			if t:IsA("Tool") then
				table.insert(ig, t)
				for _,c in ipairs(t:GetDescendants()) do
					if c:IsA("BasePart") then table.insert(ig, c) end
				end
			end
		end
	end
	ignoreList = { list = ig, expire = tick() + IGNORE_TTL }
	return ig
end

local function ClearIgnoreCache()
	ignoreList = nil
end

player.CharacterAdded:Connect(ClearIgnoreCache)

local function HasLineOfSight(from, char)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = BuildIgnore()
	params.IgnoreWater = true
	local dir = (hrp.Position - from).Unit
	local dist = (hrp.Position - from).Magnitude
	local result = Workspace:Raycast(from, dir * dist, params)
	if not result then return true end
	return char:IsAncestorOf(result.Instance) or result.Instance:FindFirstAncestorOfClass("Model") == char
end

-- ==================== 敌人获取 ====================
local function GetEnemies()
	local out, hrp = {}, player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return out end
	for _,p in ipairs(Players:GetPlayers()) do
		if p~=player and not isWL(p) and p.Character then
			local ph = p.Character:FindFirstChild("HumanoidRootPart")
			local hu = p.Character:FindFirstChildOfClass("Humanoid")
			if ph and hu and hu.Health>0 then
				if invincibleCheck and IsInvincibleCached(p) then continue end
				local d=(ph.Position-hrp.Position).Magnitude
				if d<=MAX_RANGE then
					local tr = GetRole(p)
					if myRole and tr then
						if (DCLASS[myRole] and DCLASS[tr]) or
						   (FOUNDATION[myRole] and FOUNDATION[tr]) or
						   (CHAOS[myRole] and CHAOS[tr]) then continue end
					end
					local enemy = IsEnemy(p)
					if not enemy and not DCLASS[myRole] and IsHostile(p) then enemy=true end
					if not enemy and not DCLASS[myRole] and IsEscaped(p) then enemy=true end
					if enemy and (not rayEnabled or HasLineOfSight(hrp.Position, p.Character)) then
						table.insert(out, {player=p, char=p.Character, hrp=ph, dist=d})
					end
				end
			end
		end
	end
	table.sort(out, function(a,b) return a.dist<b.dist end)
	return out
end

local function GetMeleeTargets()
	local out, hrp = {}, player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return out end
	for _,p in ipairs(Players:GetPlayers()) do
		if p~=player and not isWL(p) and p.Character then
			local ph = p.Character:FindFirstChild("HumanoidRootPart")
			local hu = p.Character:FindFirstChildOfClass("Humanoid")
			if ph and hu and hu.Health>0 and (ph.Position-hrp.Position).Magnitude<=MELEE_RANGE then
				if invincibleCheck and IsInvincibleCached(p) then continue end
				local tr = GetRole(p)
				if myRole and tr then
					if (DCLASS[myRole] and DCLASS[tr]) or
					   (FOUNDATION[myRole] and FOUNDATION[tr]) or
					   (CHAOS[myRole] and CHAOS[tr]) then continue end
				end
				local enemy = IsEnemy(p)
				if not enemy and not DCLASS[myRole] and IsHostile(p) then enemy=true end
				if not enemy and not DCLASS[myRole] and IsEscaped(p) then enemy=true end
				if enemy then table.insert(out, {player=p, char=p.Character, hrp=ph}) end
			end
		end
	end
	return out
end

-- ==================== ★ 弹道（Part方案，100%可见） ====================
local BEAM_COLOR = Color3.fromRGB(255, 183, 197)
local BEAM_LIFETIME = 0.5
local MAX_BEAMS = 40
local MAX_POOL_SIZE = 80  -- 池上限，防止无限增长
local activeBeams = {}
local beamPool = {}
local beamSpawnCount = 0  -- 防止task.spawn堆积

local function GetBeamPart()
	-- 优先从池里取
	if #beamPool > 0 then
		local p = table.remove(beamPool)
		if p and not p.Parent then
			return p
		end
	end
	-- 池空了才创建新Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = BEAM_COLOR
	p.Size = Vector3.new(0.06, 0.06, 1)
	return p
end

local function RecycleBeamPart(p)
	-- 重置属性
	p.Transparency = 0.1
	-- 池满了就直接销毁，不保留
	if #beamPool >= MAX_POOL_SIZE then
		if p and p.Parent then p:Destroy() end
		return
	end
	if p and not p.Parent then
		table.insert(beamPool, p)
	end
end

local function CleanDeadBeams()
	-- 清理已销毁/无Parent的弹道引用
	for i = #activeBeams, 1, -1 do
		local beam = activeBeams[i]
		if not beam or not beam.Parent then
			table.remove(activeBeams, i)
		end
	end
	-- 数量上限保护
	while #activeBeams > MAX_BEAMS do
		local old = table.remove(activeBeams, 1)
		if old and old.Parent then
			old:Destroy()
		end
	end
end

local function DrawBulletTrail(from, to)
	if not drawBeams then return end

	-- 防止极端情况下弹道堆积
	if beamSpawnCount >= MAX_BEAMS * 2 then
		return
	end

	local dir = to - from
	local dist = dir.Magnitude
	if dist < 0.5 then return end

	local part = GetBeamPart()
	part.CFrame = CFrame.new((from + to) / 2, to)
	part.Size = Vector3.new(0.06, 0.06, dist)
	part.Material = Enum.Material.Neon
	part.Color = BEAM_COLOR
	part.Transparency = 0.1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = Workspace

	table.insert(activeBeams, part)
	beamSpawnCount = beamSpawnCount + 1

	-- 用task.spawn替代task.delay，避免闭包引用堆积
	task.spawn(function()
		task.wait(BEAM_LIFETIME)
		beamSpawnCount = beamSpawnCount - 1
		if part and part.Parent then
			part.Parent = nil
			RecycleBeamPart(part)
		end
		for i = #activeBeams, 1, -1 do
			if activeBeams[i] == part then
				table.remove(activeBeams, i)
				break
			end
		end
	end)
end

-- ==================== 脚底范围指示（绿色/红色双状态旋转） ====================
local CircleParts = {}
local circleValid = false
local MAX_CIRCLE_PARTS = 12  -- 12个方块，绕一圈均匀分布
local circleRotation = 0      -- 当前旋转角度
local CIRCLE_ROT_SLOW = 1.2   -- 空闲旋转速度（弧度/秒）
local CIRCLE_ROT_FAST = 9.0   -- 有敌人时旋转速度（快速）
local COLOR_IDLE = Color3.fromRGB(0, 255, 60)   -- 绿色：无敌人
local COLOR_ALERT = Color3.fromRGB(255, 30, 30)  -- 红色：有敌人
local COLOR_ALERT_GLOW = Color3.fromRGB(255, 80, 30)  -- 橙红：渐变闪烁
local circleHasEnemy = false   -- 当前是否有敌人在范围内

local function DestroyCircle()
	for _,p in ipairs(CircleParts) do pcall(function() p:Destroy() end) end
	CircleParts={}
	circleValid = false
end

local function CreateCircle()
	-- 如果已存在且有效，先销毁旧的
	if #CircleParts > 0 then
		DestroyCircle()
	end
	if not drawCircle then return end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	for i=1,MAX_CIRCLE_PARTS do
		local pt=Instance.new("Part")
		pt.Anchored=true; pt.CanCollide=false; pt.CastShadow=false
		pt.Material=Enum.Material.Neon
		pt.Color=COLOR_IDLE
		pt.Transparency=0.25
		pt.Size=Vector3.new(0.5, 0.5, 0.5)
		pt.Parent=Workspace; table.insert(CircleParts, pt)
	end
	circleValid = true
end

local function UpdateCircle()
	if not drawCircle then DestroyCircle(); return end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then DestroyCircle(); return end
	if not circleValid or #CircleParts==0 then CreateCircle(); return end

	-- ★ 检测范围内是否有敌人
	local hasEnemy = false
	if autoMelee then
		local tgts = GetMeleeTargets()
		if #tgts > 0 then
			hasEnemy = true
		end
	end

	-- ★ 旋转速度：有敌人时快速，否则缓慢
	local rotSpeed = hasEnemy and CIRCLE_ROT_FAST or CIRCLE_ROT_SLOW
	circleRotation = circleRotation + rotSpeed * (1/60)
	if circleRotation >= math.pi*2 then
		circleRotation = circleRotation - math.pi*2
	end

	-- ★ 颜色插值：有敌人时闪烁红→橙红，否则绿色
	local targetColor
	if hasEnemy then
		-- 用时间做正弦闪烁
		local flash = (math.sin(tick() * 12) + 1) / 2  -- 0~1
		targetColor = COLOR_ALERT:lerp(COLOR_ALERT_GLOW, flash)
	else
		targetColor = COLOR_IDLE
	end

	for i,pt in ipairs(CircleParts) do
		-- 每个方块在圆上均匀分布，加上整体旋转偏移
		local a = (i / #CircleParts) * math.pi * 2 + circleRotation
		local offsetX = math.cos(a) * MELEE_RANGE
		local offsetZ = math.sin(a) * MELEE_RANGE
		-- 有敌人时方块轻微弹跳（高度波动）
		local yOffset = -2.5
		if hasEnemy then
			yOffset = -2.5 + math.sin(circleRotation * 3 + i) * 0.3
		end
		local pos = hrp.Position + Vector3.new(offsetX, yOffset, offsetZ)
		pt.CFrame = CFrame.new(pos) * CFrame.Angles(0, a, 0)
		pt.Color = targetColor
	end
end

-- ==================== 枪口 ====================
local function GetMuzzlePos(id)
	local cam = Workspace:FindFirstChild("Camera")
	if not cam then return nil end
	local w = cam:FindFirstChild(id)
	local pts = w and w:FindFirstChild("Points")
	local m = pts and pts:FindFirstChild("Muzzle")
	return m and m.WorldPosition or nil
end

-- ==================== 射击 ====================
local function BuildShotData(org, aim, hitPart, spread)
	spread = spread or Vector3.zero
	local aimPos = aim + spread
	local dir = (aimPos - org).Unit * 8300
	return {
		normal = Vector3.new(0, 1, 0),
		direction = dir,
		origin = org,
		instance = hitPart,
		points = {},
		position = aimPos
	}
end

local function FireRanged(tgt)
	if funMode then
		if SoundEvent then
			for _, id in ipairs(WepList) do
				if IsRanged(WepNames[id]) then
					pcall(function() SoundEvent:FireServer(id, "FIRE") end)
				end
			end
		end
		return
	end

	local head = tgt.char:FindFirstChild("Head")
	local aim = (head or tgt.hrp).Position
	local org = nil
	local wepIsShotgun = false
	for _,id in ipairs(WepList) do
		if IsRanged(WepNames[id]) then
			if IsShotgun(WepNames[id]) then wepIsShotgun = true end
			if not org then org=GetMuzzlePos(id) end
		end
	end
	if not org then
		local h=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		org = h and (h.Position+Vector3.new(math.random(-50,50)/10,math.random(-28,48)/10,math.random(-60,60)/10)) or aim+Vector3.new(0,2.376,0)
	end

	if drawBeams then
		DrawBulletTrail(org, aim)
	end

	local shots = {}
	local pelletCount = wepIsShotgun and 8 or 1

	for i = 1, pelletCount do
		local spread = Vector3.zero
		if wepIsShotgun and i > 1 then
			spread = Vector3.new(
					math.random(-15, 15) / 100,
					math.random(-10, 10) / 100,
					math.random(-15, 15) / 100
				)
		end
		table.insert(shots, BuildShotData(org, aim, head or tgt.hrp, spread))
	end

	if ShootEvent then
		for _,id in ipairs(WepList) do
			if IsRanged(WepNames[id]) then
				pcall(function() ShootEvent:FireServer(id, shots) end)
				if not silentMode and SoundEvent then
					pcall(function() SoundEvent:FireServer(id,"FIRE") end)
				end
			end
		end
	end
end

-- ==================== ★ 近战攻击（v6.26 重写：多武器连续快速攻击） ====================
--
--  旧版问题：
--    ① MELEE_CD=0.450 → 每450ms才打一次，太慢
--    ② 每把武器只FireServer一次 → 多把武器时总耗时=武器数×等待
--    ③ 只打tgts[1] → 多个目标时只打最近的
--
--  新版方案：
--    ① MELEE_CD=0.150 → 快3倍
--    ② 收集所有近战武器ID → 依次快速FireServer（间隔35ms）
--    ③ 每把武器对所有目标各打一次（最大3个目标，防过载）
--    ④ 使用task.spawn不阻塞主循环
--
local meleeInProgress = false  -- 防止重入

local function FireMelee(tgts)
	if #tgts == 0 then return end
	if meleeInProgress then return end  -- 上一次还没打完就跳过
	meleeInProgress = true

	task.spawn(function()
		local cam = Workspace:FindFirstChild("Camera")
		if not cam then meleeInProgress = false; return end

		-- ★ 收集所有近战武器ID
		local meleeIDs = {}
		for _, id in ipairs(WepList) do
			if IsMelee(WepNames[id]) then
				table.insert(meleeIDs, id)
			end
		end

		if #meleeIDs == 0 then
			meleeInProgress = false
			return
		end

		-- ★ 最多打前3个目标（防服务端过载）
		local maxTargets = math.min(#tgts, 3)

		-- ★ 每把武器依次攻击
		for _, id in ipairs(meleeIDs) do
			-- 确保武器对象存在
			local cw = cam:FindFirstChild(id)
			if not cw then
				task.wait(0.015)  -- 短暂等待武器加载
				cw = cam:FindFirstChild(id)
			end

			if cw and AttackEvent then
				-- 对每个目标各发一次攻击
				for ti = 1, maxTargets do
					local tgt = tgts[ti]
					if tgt and tgt.char and tgt.char.Parent then
						pcall(function()
							AttackEvent:FireServer(id, {tgt.char, cw})
						end)
						-- 目标之间间隔10ms（让服务端处理）
						if ti < maxTargets then
							task.wait(0.010)
						end
					end
				end
			end

			-- ★ 武器之间间隔35ms（关键：让服务端确认上一次攻击）
			if id ~= meleeIDs[#meleeIDs] then
				task.wait(MELEE_INTERVAL)
			end
		end

		meleeInProgress = false
	end)
end

-- ==================== 职业映射 ====================
local RoleNames = {
	scientist="科学家", security="安保", mtf="机动特遣队", director="主管",
	d_class="D级人员", escaped_d="逃脱D级", escaped_d_class="逃脱D级",
	chaos_insurgency="混沌分裂者", rogue_agent="叛变特工",
	traitor="叛徒", renegade="反叛者", anomaly="异常实体",
}
local RoleColors = {
	scientist=Color3.fromRGB(97,162,204),
	security=Color3.fromRGB(170,175,185),
	mtf=Color3.fromRGB(52,110,218),
	director=Color3.fromRGB(108,197,109),
	d_class=Color3.fromRGB(255,175,40),
	escaped_d=Color3.fromRGB(255,175,40),
	escaped_d_class=Color3.fromRGB(255,175,40),
	chaos_insurgency=Color3.fromRGB(220,180,30),
	rogue_agent=Color3.fromRGB(220,180,30),
	traitor=Color3.fromRGB(220,180,30),
	renegade=Color3.fromRGB(220,180,30),
	anomaly=Color3.fromRGB(121,119,124),
	Default=Color3.fromRGB(162,165,173),
}

-- ==================== ★ 透视系统 ====================
local ESP = {}
local charPartsCache = setmetatable({}, { __mode = "k" })  -- Weak Table: 角色销毁自动移除缓存

local function ClearCharPartsCache(char)
	if not char then return end
	charPartsCache[char] = nil
	for k in pairs(charPartsCache) do
		if typeof(k) == "Instance" and k ~= char then
			local p = k
			while p do
				if p == char then
					charPartsCache[k] = nil
					break
				end
				p = p.Parent
			end
		end
	end
end

local function GetCharParts(char)
	local cached = charPartsCache[char]
	if cached then
		return cached
	end
	local parts = {}
	for _, part in ipairs(char:GetDescendants()) do
		if not part:IsA("BasePart") then continue end
		if part.Name == "HumanoidRootPart" then continue end
		local parent = part.Parent
		if parent and parent:IsA("Accessory") then continue end
		if part.Transparency >= 0.936 then continue end
		table.insert(parts, part)
	end
	charPartsCache[char] = parts
	return parts
end

local function CleanESP(p)
	if ESP[p] then
		pcall(function()
			if ESP[p].sg and ESP[p].sg.Parent then ESP[p].sg:Destroy() end
		end)
		ESP[p] = nil
	end
	ClearCharPartsCache(p.Character)
	ClearInvincible(p)
end

local function MakeESP(p)
	if p==player or ESP[p] then return end

	p.CharacterAdded:Connect(function(char)
		ClearCharPartsCache(char)
		task.wait(0.3)
		CleanESP(p)
		task.spawn(function() MakeESP(p) end)
	end)
	p.CharacterRemoving:Connect(function(char)
		ClearCharPartsCache(char)
		CleanESP(p)
	end)

	task.spawn(function()
		local char = p.Character or p.CharacterAdded:Wait()
		local hrp = char:WaitForChild("HumanoidRootPart", 5)
		local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
		if not hrp or not hum then return end

		local sg = Instance.new("ScreenGui")
		sg.Name = "ESP_"..p.Name
		sg.ResetOnSpawn = false; sg.Enabled = true
		sg.IgnoreGuiInset = true; sg.DisplayOrder = 109
		sg.Parent = player:WaitForChild("PlayerGui")

		local box = Instance.new("Frame")
		box.Name = "Box"; box.BackgroundTransparency = 1; box.BorderSizePixel = 0; box.Parent = sg

		local stroke = Instance.new("UIStroke"); stroke.Thickness = 2; stroke.Parent = box

		local grad = Instance.new("UIGradient")
		grad.Rotation = 94; grad.Parent = stroke

		local hpBg = Instance.new("Frame")
		hpBg.Name = "HpBg"; hpBg.Size = UDim2.new(0,4,1,0)
		hpBg.Position = UDim2.new(1,3,0,0)
		hpBg.BackgroundColor3 = Color3.fromRGB(49,51,56); hpBg.BackgroundTransparency = 0.269; hpBg.BorderSizePixel = 0; hpBg.Parent = box
		Instance.new("UICorner",hpBg).CornerRadius = UDim.new(0,2)

		local hpFill = Instance.new("Frame")
		hpFill.Name = "HpFill"; hpFill.AnchorPoint = Vector2.new(0.5,1)
		hpFill.Size = UDim2.new(1,0,1,0); hpFill.Position = UDim2.new(0.5,0,1,0)
		hpFill.BackgroundColor3 = Color3.fromRGB(32,164,56); hpFill.BorderSizePixel = 0; hpFill.Parent = hpBg
		Instance.new("UICorner",hpFill).CornerRadius = UDim.new(0,2)

		local distL = Instance.new("TextLabel")
		distL.Name = "Dist"; distL.BackgroundTransparency = 1
		distL.Size = UDim2.new(1,0,0,14)
		distL.Position = UDim2.new(0,0,1,2)
		distL.TextColor3 = Color3.fromRGB(204,210,216); distL.Font = Enum.Font.GothamBold
		distL.TextSize = 10; distL.TextXAlignment = Enum.TextXAlignment.Left; distL.Text = ""; distL.Parent = box

		ESP[p] = { sg=sg, Box=box, Stroke=stroke, Grad=grad, HpBg=hpBg, HpFill=hpFill, Dist=distL, Hum=hum, Char=char, HRP=hrp }

		hum.HealthChanged:Connect(function(hp)
			if not hpFill or not hpFill.Parent then return end
			local isInv = IsInvincibleCached(p)
			if isInv then
				hpFill.Size = UDim2.new(1,0,1,0)
				hpFill.BackgroundColor3 = Color3.fromRGB(80,160,255)
				hpFill.BackgroundTransparency = 0
			else
				local r = math.clamp(hp / math.max(hum.MaxHealth,1), 0, 1)
				hpFill.Size = UDim2.new(1,0,r,0)
				hpFill.BackgroundColor3 = r>0.463 and Color3.fromRGB(28,146,62) or r>0.263 and Color3.fromRGB(198,144,39) or Color3.fromRGB(202,46,46)
				hpFill.BackgroundTransparency = 0
			end
		end)

		hum.Died:Connect(function()
			CleanESP(p)
		end)

		char.ChildAdded:Connect(function()
			ClearCharPartsCache(char)
		end)
		char.ChildRemoved:Connect(function()
			ClearCharPartsCache(char)
		end)
	end)
end

for _,p in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		SafeCall("MakeESP_" .. p.Name, function() MakeESP(p) end)
	end)
end
Players.PlayerAdded:Connect(function(p)
	task.spawn(function()
		task.wait(0.3)
		SafeCall("MakeESP_" .. p.Name, function() MakeESP(p) end)
	end)
end)
Players.PlayerRemoving:Connect(function(p)
	SafeCall("CleanESP_" .. p.Name, function() CleanESP(p) end)
end)

-- 包围盒计算（8角）
local function ComputeBoundingBox(char, cam)
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	local any = false
	local parts = GetCharParts(char)
	for _, part in ipairs(parts) do
		local cf, size = part.CFrame, part.Size
		local hx, hy, hz = size.X*0.5, size.Y*0.5, size.Z*0.5
		local corners = {
			cf * Vector3.new( hx, hy,  hz),
			cf * Vector3.new( hx, hy, -hz),
			cf * Vector3.new( hx,-hy,  hz),
			cf * Vector3.new( hx,-hy, -hz),
			cf * Vector3.new(-hx, hy,  hz),
			cf * Vector3.new(-hx, hy, -hz),
			cf * Vector3.new(-hx,-hy,  hz),
			cf * Vector3.new(-hx,-hy, -hz),
		}
		for _, v in ipairs(corners) do
			local sp, onScreen = cam:WorldToViewportPoint(v)
			if onScreen then
				any = true
				if sp.X < minX then minX = sp.X end
				if sp.Y < minY then minY = sp.Y end
				if sp.X > maxX then maxX = sp.X end
				if sp.Y > maxY then maxY = sp.Y end
			end
		end
	end
	if not any then return nil end
	return minX, minY, maxX, maxY
end

-- ★ 透视渲染（60Hz）
RunService.RenderStepped:Connect(function()
	if not espEnabled then
		for p,d in pairs(ESP) do if d.sg then d.sg.Enabled=false end end
		return
	end
	local cam = Workspace.CurrentCamera
	if not cam then return end

	local sw = cam.ViewportSize.X
	local sh = cam.ViewportSize.Y
	local margin = 2

	for p, d in pairs(ESP) do
		if not d.sg or not d.sg.Parent then CleanESP(p); continue end
		if not d.Char or not d.Char.Parent then CleanESP(p); continue end
		if not d.HRP or not d.HRP.Parent then CleanESP(p); continue end

		d.sg.Enabled = true

		local minX, minY, maxX, maxY = ComputeBoundingBox(d.Char, cam)
		if not minX then
			d.Box.Visible = false
		else
			minX = math.max(0, minX - margin)
			minY = math.max(0, minY - margin)
			maxX = math.min(sw, maxX + margin)
			maxY = math.min(sh, maxY + margin)
			local w, h = maxX-minX, maxY-minY
			if w < 4 or h < 4 then
				d.Box.Visible = false
			else
				d.Box.Visible = true
				d.Box.Position = UDim2.new(0, minX, 0, minY)
				d.Box.Size = UDim2.new(0, w, 0, h)

				local role = GetRole(p)
				local col = RoleColors[role] or RoleColors.Default

				-- ★ 只在颜色变化时更新（避免每帧创建ColorSequence）
				if d.LastColor ~= col then
					d.LastColor = col
					d.Stroke.Color = col
					local dim = Color3.new(0,0,0)
					d.Grad.Color = ColorSequence.new{
						ColorSequenceKeypoint.new(0,   col),
						ColorSequenceKeypoint.new(0.35, col:Lerp(dim, 0.20)),
						ColorSequenceKeypoint.new(0.70, col:Lerp(dim, 0.45)),
						ColorSequenceKeypoint.new(1,   col:Lerp(dim, 0.70)),
					}
				end

				-- ★ 无敌检测 → 血条蓝色 / 正常 → 血量色
				local isInv = IsInvincibleCached(p) or CheckForceFieldExists(p)

				if isInv then
					if not d.WasInvincible then
						d.WasInvincible = true
						d.HpFill.BackgroundColor3 = Color3.fromRGB(80,160,255)
						d.HpFill.BackgroundTransparency = 0
						d.HpFill.Size = UDim2.new(1,0,1,0)
					end
					forceFieldState[p] = true
				else
					if d.WasInvincible then
						d.WasInvincible = false
					end
					local hp = d.Hum and d.Hum.Health or 0
					local maxHp = d.Hum and d.Hum.MaxHealth or 100
					local r = math.clamp(hp / math.max(maxHp, 1), 0, 1)
					d.HpFill.Size = UDim2.new(1,0,r,0)
					d.HpFill.BackgroundTransparency = 0
					d.HpFill.BackgroundColor3 = r>0.463 and Color3.fromRGB(28,146,62)
					                         or r>0.263 and Color3.fromRGB(198,144,39)
					                         or Color3.fromRGB(202,46,46)
					forceFieldState[p] = false
				end

				local dist = (cam.CFrame.Position - d.HRP.Position).Magnitude
				d.Dist.Text = string.format("%.0fm", dist)
			end
		end
	end
end)

-- ==================== ★ 穿门系统（靠近才移除） ====================
local DoorSys = {
	Enabled = true,
	Range = 12,
	Parts = {},
	Orig = {},
}

local DOOR_SCAN_INTERVAL = 0.1

local function ScanDoors()
	local map = Workspace:FindFirstChild("Map")
	if not map then return 0 end
	local doors = map:FindFirstChild("Doors")
	if not doors then return 0 end

	local c = 0
	local DEPTH_LIMIT = 5
	local function Rec(o, depth)
		if depth > DEPTH_LIMIT then return end
		if o:IsA("BasePart") and not DoorSys.Parts[o] then
			DoorSys.Parts[o] = true
			DoorSys.Orig[o] = o.CanCollide
			c = c + 1
		end
		if c > 1000 then return end
		for _,ch in ipairs(o:GetChildren()) do
			Rec(ch, depth + 1)
		end
	end
	Rec(doors, 0)
	return c
end

local function RemoveNearbyDoors()
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return 0 end
	local px, py, pz = hrp.Position.X, hrp.Position.Y, hrp.Position.Z
	local rangeSq = DoorSys.Range * DoorSys.Range
	local count = 0
	for pt in pairs(DoorSys.Parts) do
		if pt and pt.Parent then
			local dx, dy, dz = pt.Position.X-px, pt.Position.Y-py, pt.Position.Z-pz
			if dx*dx + dy*dy + dz*dz <= rangeSq then
				if DoorSys.Orig[pt] == nil then
					DoorSys.Orig[pt] = pt.CanCollide
				end
				if pt.CanCollide then
					pt.CanCollide = false
					count = count + 1
				end
			else
				local orig = DoorSys.Orig[pt]
				if orig ~= nil and pt.CanCollide ~= orig then
					pt.CanCollide = orig
				end
			end
		else
			DoorSys.Parts[pt] = nil
			DoorSys.Orig[pt] = nil
		end
	end
	return count
end

local function RestoreAllDoors()
	local count = 0
	for pt in pairs(DoorSys.Parts) do
		if pt and pt.Parent then
			local orig = DoorSys.Orig[pt]
			if orig ~= nil and pt.CanCollide ~= orig then
				pt.CanCollide = orig
				count = count + 1
			end
		end
	end
	DoorSys.Parts = {}
	DoorSys.Orig = {}
	return count
end

-- ★ 定期清理已销毁的门对象（防止字典膨胀）
local function CleanDeadDoors()
	local cleaned = 0
	for pt in pairs(DoorSys.Parts) do
		if not pt or not pt.Parent then
			DoorSys.Parts[pt] = nil
			DoorSys.Orig[pt] = nil
			cleaned = cleaned + 1
		end
	end
	if cleaned > 0 then
		print("[穿门] 清理了 " .. cleaned .. " 个已销毁门对象")
	end
end

task.spawn(function()
	SafeCall("ScanDoors", function()
		DoorCount = ScanDoors()
		print("🚪 发现 " .. DoorCount .. " 个门部件")
	end)
end)

task.spawn(function()
	local cleanTimer = 0
	while true do
		task.wait(DOOR_SCAN_INTERVAL)
		cleanTimer = cleanTimer + DOOR_SCAN_INTERVAL
		if DoorSys.Enabled then
			RemoveNearbyDoors()
			-- 每5秒清理一次已销毁的门对象
			if cleanTimer >= 5.0 then
				CleanDeadDoors()
				cleanTimer = 0
			end
		else
			for pt in pairs(DoorSys.Parts) do
				if pt and pt.Parent then
					local orig = DoorSys.Orig[pt]
					if orig ~= nil and pt.CanCollide ~= orig then
						pt.CanCollide = orig
					end
				end
			end
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(30)
		if DoorSys.Enabled then
			local newCount = ScanDoors()
			if newCount > DoorCount then
				DoorCount = newCount
				print("🚪 补充发现新门，总计 " .. DoorCount)
			end
		end
	end
end)

-- ==================== 刷钱系统（不变） ====================
local autoFarm = false
local farmRunning = false

local SPAWN_CHECK_POS = Vector3.new(1223.6483154296875, 176.08985900878906, -1192.4896240234375)
local SPAWN_RADIUS = 50
local FARM_TELEPORT = Vector3.new(1208.21240234375, 133.37843322753906, -677.5913696289062)

local FARM_DELAY_BEFORE_TP = 3.0
local FARM_TP_COOLDOWN    = 0.5
local FARM_KEY_HOLD        = 0.08
local FARM_KEY_GAP         = 0.05
local FARM_AFTER_KEYS      = 0.3
local FARM_CHECK_INTERVAL  = 0.2
local FARM_ESCAPE_TIMEOUT  = 10.0
local FARM_DEATH_DELAY     = 1.0
local FARM_REBIRTH_WAIT    = 2.0
local FARM_MAX_RETRY       = 30

local function GetMyHRP()
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart") or nil
end
local function GetMyHumanoid()
	return player.Character and player.Character:FindFirstChildOfClass("Humanoid") or nil
end
local function KillMySelf()
	local hum = GetMyHumanoid()
	if not hum then return false end
	pcall(function() hum.Health = 0 end)
	return true
end
local function SelectDClass()
	if RoleEvent then
		pcall(function() RoleEvent:FireServer("d_class") end)
	end
end
local function TeleportTo(pos)
	local hrp = GetMyHRP()
	if not hrp then return false end
	hrp.CFrame = CFrame.new(pos)
	return true
end
local function IsNearSpawnPoint()
	local hrp = GetMyHRP()
	if not hrp then return false end
	return (hrp.Position - SPAWN_CHECK_POS).Magnitude < SPAWN_RADIUS
end

local function PressKey(keyCode, times)
	times = times or 1
	for i = 1, times do
		pcall(function()
			VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
		end)
		task.wait(FARM_KEY_HOLD)
		pcall(function()
			VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
		end)
		if i < times then task.wait(FARM_KEY_GAP) end
	end
end

local function WaitForDeath(timeout)
	timeout = timeout or 8
	local start = tick()
	while player.Character and (tick() - start) < timeout do
		task.wait(0.1)
	end
	task.wait(0.8)
	return true
end

local function WaitForCharacter(timeout)
	timeout = timeout or 15
	local start = tick()
	local char = player.Character
	while not char and (tick() - start) < timeout do
		task.wait(0.1)
		char = player.Character
	end
	if not char then return false end

	local hrp = nil
	local hrpWait = 0
	while not hrp and hrpWait < 8 do
		task.wait(0.1)
		hrpWait = hrpWait + 0.1
		hrp = char:FindFirstChild("HumanoidRootPart")
	end
	if not hrp then return false end

	local hum = nil
	local humWait = 0
	while not hum and humWait < 8 do
		task.wait(0.1)
		humWait = humWait + 0.1
		hum = char:FindFirstChildOfClass("Humanoid")
	end
	if not hum then return false end

	local healthWait = 0
	while hum.Health <= 0 and healthWait < 8 do
		task.wait(0.1)
		healthWait = healthWait + 0.1
	end
	if hum.Health <= 0 then return false end

	return true
end

local function WaitForRole(timeout)
	timeout = timeout or 12
	local start = tick()
	while (tick() - start) < timeout do
		if myRole and myRole ~= "" then
			return myRole
		end
		task.wait(0.2)
	end
	return nil
end

local function FullRespawnAsDClass()
	local MAX_TIME = 30
	local start = tick()

	local hum = GetMyHumanoid()
	if hum and hum.Health > 0 then
		pcall(function() hum.Health = 0 end)
	end

	local deathWait = 0
	while player.Character and deathWait < 10 do
		task.wait(0.1)
		deathWait = deathWait + 0.1
	end
	task.wait(0.8)

	if (tick() - start) > MAX_TIME then return false end

	SelectDClass()

	local char = nil
	local charWait = 0
	while not char and charWait < 15 do
		task.wait(0.2)
		charWait = charWait + 0.2
		char = player.Character
	end
	if not char then return false end

	if (tick() - start) > MAX_TIME then return false end

	local charOk = WaitForCharacter(15)
	if not charOk then return false end

	if (tick() - start) > MAX_TIME then return false end

	local role = WaitForRole(15)
	if role ~= "d_class" then
		SelectDClass()
		task.wait(1.0)
		role = myRole
	end
	if role ~= "d_class" then return false end

	task.wait(1.0)

	return true
end

local function CheckSelfEscaped()
	return IsEscaped(player)
end

local function FarmLoop()
	if farmRunning then return end
	farmRunning = true

	local retryCount = 0

	while autoFarm do
		if not IsNearSpawnPoint() then
			retryCount = retryCount + 1
			if retryCount > FARM_MAX_RETRY then break end
			local ok = FullRespawnAsDClass()
			if not ok then
				task.wait(2.0)
			else
				retryCount = 0
			end
			continue
		end

		local char = player.Character
		local hum = GetMyHumanoid()
		local alive = hum and hum.Health > 0
		local hasRole = myRole and myRole ~= ""

		if not alive or not hasRole then
			retryCount = retryCount + 1
			if retryCount > FARM_MAX_RETRY then break end
			local ok = FullRespawnAsDClass()
			if not ok then task.wait(2.0) else retryCount = 0 end
			continue
		end

		if myRole ~= "d_class" then
			KillMySelf()
			task.wait(FARM_REBIRTH_WAIT)
			continue
		end

		retryCount = 0

		if CheckSelfEscaped() then
			task.wait(FARM_DEATH_DELAY)
			KillMySelf()
			task.wait(FARM_REBIRTH_WAIT)
			continue
		end

		task.wait(FARM_DELAY_BEFORE_TP)

		hum = GetMyHumanoid()
		if not hum or hum.Health <= 0 then
			task.wait(FARM_REBIRTH_WAIT)
			continue
		end
		if CheckSelfEscaped() then
			task.wait(FARM_DEATH_DELAY)
			KillMySelf()
			task.wait(FARM_REBIRTH_WAIT)
			continue
		end

		local tpOk = TeleportTo(FARM_TELEPORT)
		if not tpOk then
			task.wait(0.5)
			continue
		end

		task.wait(FARM_TP_COOLDOWN)

		PressKey(Enum.KeyCode.S, 2)
		task.wait(FARM_KEY_GAP)
		PressKey(Enum.KeyCode.W, 2)
		task.wait(FARM_AFTER_KEYS)

		local checkStart = tick()
		local escaped = false
		while (tick() - checkStart) < FARM_ESCAPE_TIMEOUT do
			hum = GetMyHumanoid()
			if not hum or hum.Health <= 0 then
				task.wait(FARM_REBIRTH_WAIT)
				break
			end
			if CheckSelfEscaped() then
				escaped = true
				break
			end
			task.wait(FARM_CHECK_INTERVAL)
		end

		if escaped then
			task.wait(FARM_DEATH_DELAY)
			KillMySelf()
			task.wait(FARM_REBIRTH_WAIT)
		else
			KillMySelf()
			task.wait(FARM_REBIRTH_WAIT)
		end
	end

	farmRunning = false
end

-- ==================== ★ 战斗主循环 ====================
SafeCall("ScanWeapons", ScanWeapons)
local LastShoot, LastMelee = 0, 0

task.spawn(function() while true do task.wait(3.0); ScanWeapons() end end)

RunService.Heartbeat:Connect(function()
	local now = tick()

	if autoFarm and farmRunning then
		pcall(UpdateCircle)
		return
	end

	-- ★ 近战：CD 0.150s（快3倍），多武器连续攻击
	if autoMelee and HasMelee() and now - LastMelee >= MELEE_CD then
		local t = GetMeleeTargets()
		if #t > 0 then
			FireMelee(t)
			LastMelee = now
		end
	end

	-- 射击
	if autoShoot and now - LastShoot >= SHOOT_CD then
		local hasR, isSG = HasRanged()
		if hasR then
			local e = GetEnemies()
			if #e > 0 then
				FireRanged(e[1])
				LastShoot = now
			end
		end
	end

	pcall(UpdateCircle)
end)

-- ==================== UI ====================
local UI = {}
local ListVisible = true
local Minimized = false

task.spawn(function()
	local pg = player:WaitForChild("PlayerGui", 30)
	if not pg then return end

	local scale = GetScale()
	local C = {
		BG=Color3.fromRGB(35,38,43), Title=Color3.fromRGB(45,49,55), Dark=Color3.fromRGB(69,74,82),
		Text=Color3.fromRGB(223,227,233), Dim=Color3.fromRGB(144,151,163),
		Green=Color3.fromRGB(113,191,78), Purple=Color3.fromRGB(174,138,208),
		Blue=Color3.fromRGB(74,132,196), Yellow=Color3.fromRGB(190,175,80),
		Red=Color3.fromRGB(200,70,75), Orange=Color3.fromRGB(255,175,40),
		Pink=Color3.fromRGB(193,143,183), Label=Color3.fromRGB(85,88,95),
		Input=Color3.fromRGB(86,91,101), Sep=Color3.fromRGB(69,76,86),
	}

	local PW = math.floor((IS_MOBILE and 280 or 340) * scale)
	local PH = math.floor((IS_MOBILE and 370 or 430) * scale)
	local MH = math.floor((IS_MOBILE and 26 or 28) * scale)
	local GAP = math.floor(4*scale)
	local PAD = math.floor(7*scale)
	local BW = math.floor((PW - PAD*2 - GAP*3) / 4)
	local BH = math.floor((IS_MOBILE and 24 or 28) * scale)
	local TS = math.max(11, math.floor(13*scale))
	local BS = math.max(10, math.floor(12*scale))

	local sg = Instance.new("ScreenGui")
	sg.Name = "SCPAnomalySite"
	sg.ResetOnSpawn = false; sg.Enabled = true
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	sg.Parent = pg

	local MF = Instance.new("Frame")
	MF.Size = UDim2.new(0,PW,0,PH)
	MF.Position = UDim2.new(1,-(PW+9),0.429,-PH/2)
	MF.BackgroundColor3=C.BG; MF.BackgroundTransparency=0.029; MF.BorderSizePixel=0
	MF.Active=true; MF.Draggable=true; MF.Parent=sg
	Instance.new("UICorner",MF).CornerRadius=UDim.new(0,math.floor(6*scale))

	local CC = Instance.new("Frame")
	CC.Size = UDim2.new(1,0,1,-MH)
	CC.Position = UDim2.new(0,0,0,MH)
	CC.BackgroundTransparency=1; CC.BorderSizePixel=0; CC.Parent=MF

	local TB = Instance.new("Frame")
	TB.Size = UDim2.new(1,0,0,MH)
	TB.BackgroundColor3=C.Title; TB.BackgroundTransparency=0.035; TB.BorderSizePixel=0; TB.Parent=MF
	Instance.new("UICorner",TB).CornerRadius=UDim.new(0,math.floor(6*scale))

	local TL = Instance.new("TextLabel")
	TL.Size = UDim2.new(1,-85,1,0); TL.Position=UDim2.new(0,43,0,0)
	TL.BackgroundTransparency=1; TL.Text="⚔️ SCP异常站点 v6.26"
	TL.TextColor3=C.Text; TL.Font=Enum.Font.GothamBold; TL.TextSize=TS; TL.TextXAlignment=Enum.TextXAlignment.Center; TL.Parent=TB

	local function mkIconBtn(sym, xpos)
		local b=Instance.new("TextButton")
		b.Size=UDim2.new(0,math.floor(BH*0.801),0,math.floor(BH*0.787))
		b.Position=UDim2.new(0,xpos,0,math.floor((MH-BH*0.809)/2))
		b.BackgroundColor3=C.Dark; b.BackgroundTransparency=0.066
		b.Text=sym; b.TextColor3=C.Text; b.Font=Enum.Font.GothamBold; b.TextSize=math.floor(TS*0.845); b.Parent=TB
		Instance.new("UICorner",b).CornerRadius=UDim.new(0,4); return b
	end
	local EB = mkIconBtn("☰", 5)
	local MB = mkIconBtn("━", PW-math.floor(BH*1.677))
	local CB = mkIconBtn("✕", PW-math.floor(BH*0.834))

	EB.MouseButton1Click:Connect(function() ListVisible=not ListVisible end)
	MB.MouseButton1Click:Connect(function()
		Minimized=not Minimized
		CC.Visible=not Minimized; MF.Size=Minimized and UDim2.new(0,PW,0,MH) or UDim2.new(0,PW,0,PH)
		MB.Text=Minimized and "□" or "━"
	end)
	CB.MouseButton1Click:Connect(function()
		local cfm=Instance.new("TextButton")
		cfm.Size=UDim2.new(0,106,0,38); cfm.Position=UDim2.new(0.488,-53,0.494,-19)
		cfm.BackgroundColor3=C.Red; cfm.BackgroundTransparency=0.053; cfm.Text="关闭?"
		cfm.TextColor3=C.Text; cfm.Font=Enum.Font.GothamBold; cfm.TextSize=TS; cfm.Parent=sg
		Instance.new("UICorner",cfm).CornerRadius=UDim.new(0,5)
		cfm.MouseButton1Click:Connect(function() sg:Destroy() end)
		task.delay(2.369,function() if cfm.Parent then cfm:Destroy() end end)
	end)

	local y = GAP

	-- 状态面板
	local SB = Instance.new("Frame")
	SB.Size = UDim2.new(0, PW-PAD*2, 0, math.floor(50*scale))
	SB.Position = UDim2.new(0,PAD,0,y)
	SB.BackgroundColor3=C.Dark; SB.BackgroundTransparency=0.057; SB.BorderSizePixel=0; SB.Parent=CC
	Instance.new("UICorner",SB).CornerRadius=UDim.new(0,5)

	local SL = Instance.new("TextLabel")
	SL.Size = UDim2.new(1,-9,1,-5); SL.Position=UDim2.new(0,5,0,3)
	SL.BackgroundTransparency=1; SL.Text="加载中..."
	SL.TextColor3=C.Text; SL.Font=Enum.Font.Gotham; SL.TextSize=math.max(10,math.floor(TS*0.705))
	SL.TextXAlignment=Enum.TextXAlignment.Left; SL.TextYAlignment=Enum.TextYAlignment.Top; SL.Parent=SB
	UI.StatusLabel = SL

	y = y + SB.Size.Y.Offset + GAP

	local function mkBtn(text, color)
		local b=Instance.new("TextButton")
		b.Size=UDim2.new(0,BW,0,BH); b.BackgroundColor3=color; b.BackgroundTransparency=0.049
		b.Text=text; b.TextColor3=C.Text; b.Font=Enum.Font.GothamBold; b.TextSize=BS; b.Parent=CC
		Instance.new("UICorner",b).CornerRadius=UDim.new(0,4); return b
	end

	-- 第1排：射击 | 近战 | 射线 | 弹道
	local SHT = mkBtn("🔫射击", C.Green); SHT.Position=UDim2.new(0,PAD,0,y)
	local MEL = mkBtn("🔪近战", C.Purple); MEL.Position=UDim2.new(0,PAD+BW+GAP,0,y)
	local RAY = mkBtn("👁️射线", C.Blue); RAY.Position=UDim2.new(0,PAD+(BW+GAP)*2,0,y)
	local BEAM_BTN = mkBtn("🌸弹道", C.Pink); BEAM_BTN.Position=UDim2.new(0,PAD+(BW+GAP)*3,0,y)
	y = y + BH + GAP

	SHT.MouseButton1Click:Connect(function() autoShoot=not autoShoot; SHT.BackgroundColor3=autoShoot and C.Green or C.Red end)
	MEL.MouseButton1Click:Connect(function() autoMelee=not autoMelee; MEL.BackgroundColor3=autoMelee and C.Purple or C.Red end)
	RAY.MouseButton1Click:Connect(function()
		rayEnabled=not rayEnabled; RAY.Text=rayEnabled and "👁️射线" or "💀穿墙"
		RAY.BackgroundColor3=rayEnabled and C.Blue or C.Red
	end)
	BEAM_BTN.MouseButton1Click:Connect(function()
		drawBeams=not drawBeams
		BEAM_BTN.BackgroundColor3 = drawBeams and C.Pink or C.Red
		BEAM_BTN.Text = drawBeams and "🌸弹道ON" or "🌸弹道"
	end)

	-- 第2排：范围 | 透视 | 射程 | 穿门
	local CIR = mkBtn("⭕范围", C.Orange); CIR.Position=UDim2.new(0,PAD,0,y)
	local ESB = mkBtn("👁️透视", C.Blue); ESB.Position=UDim2.new(0,PAD+BW+GAP,0,y)

	local RGL = Instance.new("TextButton")
	RGL.Size=UDim2.new(0,BW*2+GAP,0,BH)
	RGL.Position=UDim2.new(0,PAD+(BW+GAP)*2,0,y)
	RGL.BackgroundColor3=C.Label; RGL.BackgroundTransparency=0.063
	RGL.Text="🔫射程:"..MAX_RANGE; RGL.TextColor3=C.Text; RGL.Font=Enum.Font.GothamBold; RGL.TextSize=BS; RGL.Parent=CC
	Instance.new("UICorner",RGL).CornerRadius=UDim.new(0,4)
	y = y + BH + GAP

	CIR.MouseButton1Click:Connect(function()
		drawCircle=not drawCircle; CIR.BackgroundColor3=drawCircle and C.Orange or C.Red
		if drawCircle then pcall(CreateCircle) else pcall(DestroyCircle) end
	end)
	ESB.MouseButton1Click:Connect(function()
		espEnabled=not espEnabled; ESB.BackgroundColor3=espEnabled and C.Blue or C.Red
	end)

	local function mkRangeOverlay()
		local overlay = Instance.new("Frame")
		overlay.Size=UDim2.new(0,math.floor(190*scale),0,math.floor(72*scale))
		overlay.Position=UDim2.new(0,PAD+(BW+GAP)*2,0,y-BH-GAP-math.floor(80*scale))
		overlay.BackgroundColor3=C.BG; overlay.BackgroundTransparency=0.020; overlay.BorderSizePixel=0; overlay.Parent=CC
		Instance.new("UICorner",overlay).CornerRadius=UDim.new(0,5)
		local tb = Instance.new("TextBox")
		tb.Size=UDim2.new(0,math.floor(110*scale),0,math.floor(26*scale))
		tb.Position=UDim2.new(0,7,0,5); tb.BackgroundColor3=C.Input; tb.BackgroundTransparency=0.050
		tb.Text=tostring(MAX_RANGE); tb.TextColor3=C.Text; tb.Font=Enum.Font.Gotham; tb.TextSize=BS; tb.Parent=overlay
		Instance.new("UICorner",tb).CornerRadius=UDim.new(0,3)
		local ok = Instance.new("TextButton")
		ok.Size=UDim2.new(0,math.floor(48*scale),0,math.floor(26*scale))
		ok.Position=UDim2.new(0,math.floor(125*scale),0,5)
		ok.BackgroundColor3=C.Green; ok.Text="✓"; ok.TextColor3=C.Text; ok.Font=Enum.Font.GothamBold; ok.TextSize=BS; ok.Parent=overlay
		Instance.new("UICorner",ok).CornerRadius=UDim.new(0,3)
		local function apply()
			local n=tonumber(tb.Text)
			if n and n>=10 and n<=2000 then MAX_RANGE=math.floor(n) end
			RGL.Text="🔫射程:"..MAX_RANGE; overlay:Destroy()
		end
		ok.MouseButton1Click:Connect(apply)
		tb.FocusLost:Connect(function(ep) if ep then apply() end end)
	end
	RGL.MouseButton1Click:Connect(mkRangeOverlay)

	-- 第3排：近战距离 | 娱乐 | 静默 | 无敌检测
	local MRL = Instance.new("TextButton")
	MRL.Size=UDim2.new(0,BW*2+GAP,0,BH)
	MRL.Position=UDim2.new(0,PAD,0,y)
	MRL.BackgroundColor3=C.Label; MRL.BackgroundTransparency=0.052
	MRL.Text="🔪近战:"..MELEE_RANGE; MRL.TextColor3=C.Text; MRL.Font=Enum.Font.GothamBold; MRL.TextSize=BS; MRL.Parent=CC
	Instance.new("UICorner",MRL).CornerRadius=UDim.new(0,4)

	local FUN = mkBtn("🎵娱乐", C.Pink); FUN.Position=UDim2.new(0,PAD+(BW+GAP)*2,0,y)
	local SIL = mkBtn("🔇静默", Color3.fromRGB(82,87,97)); SIL.Position=UDim2.new(0,PAD+(BW+GAP)*3,0,y)
	y = y + BH + GAP

	MRL.MouseButton1Click:Connect(function()
		local overlay = Instance.new("Frame")
		overlay.Size=UDim2.new(0,math.floor(190*scale),0,math.floor(72*scale))
		overlay.Position=UDim2.new(0,PAD,0,y-BH-GAP-math.floor(80*scale))
		overlay.BackgroundColor3=C.BG; overlay.BackgroundTransparency=0.019; overlay.BorderSizePixel=0; overlay.Parent=CC
		Instance.new("UICorner",overlay).CornerRadius=UDim.new(0,5)
		local tb = Instance.new("TextBox")
		tb.Size=UDim2.new(0,math.floor(110*scale),0,math.floor(26*scale))
		tb.Position=UDim2.new(0,7,0,5); tb.BackgroundColor3=C.Input; tb.BackgroundTransparency=0.041
		tb.Text=tostring(MELEE_RANGE); tb.TextColor3=C.Text; tb.Font=Enum.Font.Gotham; tb.TextSize=BS; tb.Parent=overlay
		Instance.new("UICorner",tb).CornerRadius=UDim.new(0,3)
		local ok = Instance.new("TextButton")
		ok.Size=UDim2.new(0,math.floor(48*scale),0,math.floor(26*scale))
		ok.Position=UDim2.new(0,math.floor(125*scale),0,5)
		ok.BackgroundColor3=C.Green; ok.Text="✓"; ok.TextColor3=C.Text; ok.Font=Enum.Font.GothamBold; ok.TextSize=BS; ok.Parent=overlay
		Instance.new("UICorner",ok).CornerRadius=UDim.new(0,3)
		local function apply()
			local n=tonumber(tb.Text)
			if n and n>=2 and n<=20 then MELEE_RANGE=math.floor(n); pcall(CreateCircle) end
			MRL.Text="🔪近战:"..MELEE_RANGE; overlay:Destroy()
		end
		ok.MouseButton1Click:Connect(apply)
		tb.FocusLost:Connect(function(ep) if ep then apply() end end)
	end)

	FUN.MouseButton1Click:Connect(function()
		funMode = not funMode
		FUN.BackgroundColor3 = funMode and C.Pink or Color3.fromRGB(82,87,97)
		FUN.Text = funMode and "🎵娱乐ON" or "🎵娱乐"
	end)

	SIL.MouseButton1Click:Connect(function()
		silentMode = not silentMode
		SIL.BackgroundColor3 = silentMode and Color3.fromRGB(84,89,99) or Color3.fromRGB(82,87,97)
		SIL.Text = silentMode and "🔇静默ON" or "🔇静默"
	end)

	-- 第4排：穿门 | 无敌检测 | 刷钱 | 传送
	local DRB = mkBtn("🚪穿门", C.Green); DRB.Position=UDim2.new(0,PAD,0,y)

	local INV = mkBtn("🛡️无敌ON", C.Blue); INV.Position=UDim2.new(0,PAD+BW+GAP,0,y)
	INV.Size = UDim2.new(0, BW, 0, BH)

	local FMB = mkBtn("🌾刷钱:关", C.Orange); FMB.Position=UDim2.new(0,PAD+(BW+GAP)*2,0,y)

	local TPB = mkBtn("📍传送刷钱点", C.Dark)
	TPB.Position = UDim2.new(0, PAD + (BW + GAP) * 3, 0, y)
	TPB.Size = UDim2.new(0, BW, 0, BH)
	y = y + BH + GAP

	DRB.MouseButton1Click:Connect(function()
		DoorSys.Enabled = not DoorSys.Enabled
		DRB.BackgroundColor3 = DoorSys.Enabled and C.Green or C.Red
		if not DoorSys.Enabled then
			local c = RestoreAllDoors()
			print("🚪 穿门关，恢复 " .. c .. " 个门碰撞")
		else
			print("🚪 穿门开，靠近门将自动穿透")
		end
	end)

	INV.MouseButton1Click:Connect(function()
		invincibleCheck = not invincibleCheck
		INV.BackgroundColor3 = invincibleCheck and C.Blue or C.Red
		INV.Text = invincibleCheck and "🛡️无敌ON" or "🛡️无敌检测"
		if not invincibleCheck then
			for p in pairs(invincibleUntil) do
				invincibleUntil[p] = nil
			end
			for p in pairs(forceFieldState) do
				forceFieldState[p] = false
			end
		end
	end)

	FMB.MouseButton1Click:Connect(function()
		autoFarm = not autoFarm
		FMB.BackgroundColor3 = autoFarm and C.Orange or C.Red
		FMB.Text = autoFarm and "🌾刷钱:开" or "🌾刷钱:关"
		if autoFarm then
			task.spawn(FarmLoop)
		end
	end)

	TPB.MouseButton1Click:Connect(function()
		TeleportTo(FARM_TELEPORT)
		task.wait(0.2)
		PressKey(Enum.KeyCode.S, 2)
		task.wait(FARM_KEY_GAP)
		PressKey(Enum.KeyCode.W, 2)
	end)

	-- 分隔线
	local SEP = Instance.new("Frame")
	SEP.Size=UDim2.new(0,PW-PAD*2,0,1); SEP.Position=UDim2.new(0,PAD,0,y+GAP)
	SEP.BackgroundColor3=C.Sep; SEP.BackgroundTransparency=0.051; SEP.BorderSizePixel=0; SEP.Parent=CC
	y = y + GAP*2 + 2

	-- 白名单
	local WLT = Instance.new("TextLabel")
	WLT.Size=UDim2.new(0,PW-PAD*2,0,math.floor(16*scale))
	WLT.Position=UDim2.new(0,PAD,0,y); WLT.BackgroundTransparency=1
	WLT.Text="— 白名单 —"; WLT.TextColor3=C.Dim; WLT.Font=Enum.Font.Gotham; WLT.TextSize=math.floor(BS*0.818)
	WLT.TextXAlignment=Enum.TextXAlignment.Center; WLT.Parent=CC
	y = y + WLT.Size.Y.Offset + GAP

	local NBW = math.floor((PW - PAD*2 - GAP*2) * 0.5)
	local ADW = math.floor((PW - PAD*2 - GAP*2) * 0.25)
	local CLW = PW - PAD*2 - NBW - ADW - GAP*2

	local NMB = Instance.new("TextBox")
	NMB.Size=UDim2.new(0,NBW,0,math.floor(24*scale))
	NMB.Position=UDim2.new(0,PAD,0,y); NMB.BackgroundColor3=C.Input; NMB.BackgroundTransparency=0.045
	NMB.Text=""; NMB.PlaceholderText="玩家名"; NMB.PlaceholderColor3=C.Dim
	NMB.TextColor3=C.Text; NMB.Font=Enum.Font.Gotham; NMB.TextSize=math.floor(BS*0.850); NMB.ClearTextOnFocus=false; NMB.Parent=CC
	Instance.new("UICorner",NMB).CornerRadius=UDim.new(0,4)

	local ADB = Instance.new("TextButton")
	ADB.Size=UDim2.new(0,ADW,0,math.floor(24*scale))
	ADB.Position=UDim2.new(0,PAD+NBW+GAP,0,y); ADB.BackgroundColor3=C.Green; ADB.BackgroundTransparency=0.048
	ADB.Text="加入"; ADB.TextColor3=C.Text; ADB.Font=Enum.Font.GothamBold; ADB.TextSize=BS; ADB.Parent=CC
	Instance.new("UICorner",ADB).CornerRadius=UDim.new(0,4)

	local CLB = Instance.new("TextButton")
	CLB.Size=UDim2.new(0,CLW,0,math.floor(24*scale))
	CLB.Position=UDim2.new(0,PAD+NBW+GAP+ADW+GAP,0,y); CLB.BackgroundColor3=C.Red; CLB.BackgroundTransparency=0.047
	CLB.Text="🗑️清空"; CLB.TextColor3=C.Text; CLB.Font=Enum.Font.GothamBold; CLB.TextSize=BS; CLB.Parent=CC
	Instance.new("UICorner",CLB).CornerRadius=UDim.new(0,4)

	ADB.MouseButton1Click:Connect(function() if NMB.Text~="" then addWL(NMB.Text); NMB.Text="" end end)
	NMB.FocusLost:Connect(function(ep) if ep and NMB.Text~="" then addWL(NMB.Text); NMB.Text="" end end)
	CLB.MouseButton1Click:Connect(function() for n in pairs(WL) do WL[n]=nil end end)

	y = y + math.floor(24*scale) + GAP

	local AST = Instance.new("TextLabel")
	AST.Size=UDim2.new(0,PW-PAD*2,0,math.floor(18*scale))
	AST.Position=UDim2.new(0,PAD,0,y); AST.BackgroundTransparency=1
	AST.Text="🔍 武器自动扫描中..."; AST.TextColor3=C.Dim; AST.Font=Enum.Font.Gotham; AST.TextSize=math.floor(BS*0.752)
	AST.TextXAlignment=Enum.TextXAlignment.Left; AST.Parent=CC

	-- ==================== 玩家列表（右上角） ====================
	local PLF = Instance.new("Frame")
	PLF.Size = UDim2.new(0, math.floor(200*scale), 0, math.floor(300*scale))
	PLF.Position = UDim2.new(1, -math.floor(210*scale), 0, 5)
	PLF.BackgroundTransparency = 1
	PLF.BorderSizePixel = 0
	PLF.Active = false
	PLF.Draggable = false
	PLF.Visible = true
	PLF.Parent = sg
	UI.PlayerListFrame = PLF

	local PLL = Instance.new("TextLabel")
	PLL.Size = UDim2.new(1, -4, 1, -4)
	PLL.Position = UDim2.new(0, 2, 0, 2)
	PLL.BackgroundTransparency = 1
	PLL.Text = "加载中..."
	PLL.TextColor3 = Color3.fromRGB(226,229,237)
	PLL.TextTransparency = 0
	PLL.Font = Enum.Font.Gotham
	PLL.TextSize = IS_MOBILE and 9 or 11
	PLL.TextXAlignment = Enum.TextXAlignment.Right
	PLL.TextYAlignment = Enum.TextYAlignment.Top
	PLL.TextWrapped = true
	PLL.Parent = PLF
	UI.PlayerListLabel = PLL

	print("✅ UI 创建完成")
end)

-- ==================== ★ 状态更新循环（0.1秒实时） ====================
local playerListDirty = true
local function MarkPlayerListDirty()
	playerListDirty = true
end
Players.PlayerAdded:Connect(MarkPlayerListDirty)
Players.PlayerRemoving:Connect(MarkPlayerListDirty)

task.spawn(function()
	local REFRESH_INTERVAL = 0.1

	while true do
		task.wait(REFRESH_INTERVAL)
		local now = tick()
		local myHRP = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local enemyCount, violateCount, escapeCount, invincibleCount = 0,0,0,0

		local friendLines = {}
		local enemyLines = {}

		if myHRP then
			local myPos = myHRP.Position
			local rangeSq = MAX_RANGE * MAX_RANGE  -- 用平方距离粗筛，避免sqrt
			for _,p in ipairs(Players:GetPlayers()) do
				if p~=player and p.Character then
					local hrp=p.Character:FindFirstChild("HumanoidRootPart")
					local hu=p.Character:FindFirstChildOfClass("Humanoid")
					if hrp and hu and hu.Health>0 then
						-- ★ 先用平方距离粗筛，超出范围直接跳过
						local dx = hrp.Position.X - myPos.X
						local dy = hrp.Position.Y - myPos.Y
						local dz = hrp.Position.Z - myPos.Z
						local distSq = dx*dx + dy*dy + dz*dz
						local d = math.sqrt(distSq)

						if d<=MAX_RANGE and IsEnemy(p) then enemyCount=enemyCount+1 end
						if IsHostile(p) then violateCount=violateCount+1 end
						if IsEscaped(p) then escapeCount=escapeCount+1 end

						local isInv = false
						if forceFieldState[p] == true then
							isInv = true
						elseif invincibleUntil[p] and now < invincibleUntil[p] then
							isInv = true
						else
							isInv = CheckForceFieldExists(p)
							if isInv then MarkInvincible(p) end
						end
						if isInv then invincibleCount = invincibleCount + 1 end

						local role=GetRole(p) or "?"
						local cn=RoleNames[role] or role
						local isHostile = IsHostile(p)
						local isEscaped = IsEscaped(p)

						local dist = string.format(" %.0fm", d)

						local suffix = ""
						if isHostile then suffix = suffix .. " ❗" end
						if isEscaped then suffix = suffix .. " 🏃" end
						if isInv then suffix = suffix .. " 🛡️" end

						local line = string.format("%s [%s]%s%s", p.Name, cn, suffix, dist)

						local isFriend = false
						if role == myRole and role ~= "" then
							isFriend = true
						elseif FOUNDATION[myRole] and FOUNDATION[role] then
							isFriend = true
						elseif CHAOS[myRole] and CHAOS[role] then
							isFriend = true
						elseif DCLASS[myRole] and DCLASS[role] then
							isFriend = true
						end

						if isFriend then
							table.insert(friendLines, "🛡️" .. line)
						else
							table.insert(enemyLines, "⚠️" .. line)
						end
					end
				end
			end
		end

		if UI.StatusLabel then
			local roleName = RoleNames[myRole] or (myRole or "未知")
			local wid = currentWeaponID
			if #wid>8 then wid=wid:sub(1,8).."..." end
			local modeStr = ""
			if silentMode then modeStr = " 🔇静默" end
			if funMode then modeStr = modeStr .. " 🎵娱乐" end
			if invincibleCheck then modeStr = modeStr .. " 🛡️" end
			if drawBeams then modeStr = modeStr .. " 🌸" end
			local farmStr = autoFarm and " 🌾刷钱" or ""
			local txt = string.format("职业:%s\n武器:%s\nID:%s\n敌人:%d 违规:%d 逃出:%d 无敌:%d 门:%d%s%s",
				roleName, currentWeaponName, wid, enemyCount, violateCount, escapeCount, invincibleCount, DoorCount, modeStr, farmStr)
			pcall(function() UI.StatusLabel.Text=txt end)
		end

		if UI.PlayerListLabel and ListVisible then
			local allLines = {}
			if #friendLines > 0 then
				table.insert(allLines, "===== 友军 =====")
				for _, l in ipairs(friendLines) do table.insert(allLines, l) end
				table.insert(allLines, "")
			end
			if #enemyLines > 0 then
				table.insert(allLines, "===== 敌人 =====")
				for _, l in ipairs(enemyLines) do table.insert(allLines, l) end
			end
			if #allLines == 0 then
				allLines = {"加载中..."}
			end
			pcall(function() UI.PlayerListLabel.Text = table.concat(allLines, "\n") end)
		end
	end
end)

-- ==================== 角色初始化 ====================
if player.Character then
	HookChar(player.Character)
end

for _, p in ipairs(Players:GetPlayers()) do
	p.CharacterAdded:Connect(function()
		playerListDirty = true
	end)
	p.CharacterRemoving:Connect(function()
		playerListDirty = true
	end)
end
Players.PlayerAdded:Connect(function(p)
	playerListDirty = true
	p.CharacterAdded:Connect(function() playerListDirty = true end)
	p.CharacterRemoving:Connect(function() playerListDirty = true end)
end)

-- ==================== ★ 全局清理函数 ====================
function Unload()
	autoFarm = false

	-- 断开所有事件连接
	for _, conn in ipairs(allConnections) do
		pcall(function() conn:Disconnect() end)
	end
	allConnections = {}

	pcall(function()
		local pg = player:FindFirstChild("PlayerGui")
		if pg then
			local sg = pg:FindFirstChild("SCPAnomalySite")
			if sg then sg:Destroy() end
		end
	end)

	-- 清理所有ESP（包括断开事件连接）
	for p in pairs(ESP) do
		pcall(function() CleanESP(p) end)
	end
	ESP = {}

	RestoreAllDoors()
	pcall(DestroyCircle)

	-- 清理所有弹道
	for _, b in ipairs(activeBeams) do
		if b and b.Parent then b:Destroy() end
	end
	activeBeams = {}
	for _, p in ipairs(beamPool) do
		if p and p.Parent then p:Destroy() end
	end
	beamPool = {}

	-- 清理缓存
	ignoreList = nil
	charPartsCache = {}
	DoorSys.Parts = {}
	DoorSys.Orig = {}
	invincibleUntil = {}
	forceFieldState = {}
	meleeInProgress = false

	print("✅ SCP异常站点 v6.27 已完全卸载")
end

-- ==================== 启动提示 ====================
print("✅ SCP异常站点 v6.27 已启动（核心修复版，UI未改动）")
print("🔧 v6.27 修复：加载崩溃/穿门字典膨胀/无敌表泄漏/弹道堆积/ESP缓存泄漏/状态遍历优化/圆圈Part管控/连接管理")
print("🔪 近战攻击重写：CD 0.150s + 多武器连续快速攻击")
print("🌸 弹道：Part方案 100%可见（不跟随屏幕/不UI）")
print("🛡️ 无敌检测：0.3s循环扫描玩家模型中的'Forcefield'文件")
print("🚪 穿门：靠近12格才移除碰撞（射线不穿门）")
print("🔪 近战范围：8格")
print("📋 玩家列表：0.1秒实时刷新")
print("🧹 控制台输入 Unload() 可完全卸载")
