-- ============================================================
--  SCP异常站点 v6.14-fix
--  刷钱逻辑（修复版）：
--  1. 检测自己是否有职业 → 没有就走完整复活流程
--  2. 自杀后等角色彻底消失 → 再请求选D级 → 等角色生成 → 等职业赋值
--  3. 检测自己是否是D级 → 是就继续
--  4. 检测自己是否逃出 → 逃出就自杀 → 等角色消失 → 复活循环
--  5. 没逃出 → 延迟3秒 → 传送到刷钱点
--  6. 模拟按2下S，2下W
--  7. 检测是否逃出 → 逃出就自杀 → 循环
-- ============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer

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
local MELEE_RANGE = 5
local SHOOT_CD = 0.087
local MELEE_CD = 0.450
local autoShoot = true
local autoMelee = true
local rayEnabled = true
local drawVis = true
local drawCircle = true
local attackEscapedD = true
local espEnabled = true
local funMode = false
local silentMode = false

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

-- ==================== 违规/逃出检测（路径法） ====================
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

-- ==================== 武器系统 ====================
local MeleeNames = { "knife", "crowbar", "tomahawk", "hammer", "bat", "sword", "axe", "machete" }
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

-- ==================== 武器实时监听 ====================
local function HookChar(char)
	char.ChildAdded:Connect(function(c)
		if c:IsA("Tool") then task.wait(0.085); ScanWeapons() end
	end)
	char.ChildRemoved:Connect(function(c)
		if c:IsA("Tool") then task.wait(0.082); ScanWeapons() end
	end)
end

local bp = player:FindFirstChild("Backpack")
if bp then
	bp.ChildAdded:Connect(function(c)
		if c:IsA("Tool") then task.wait(0.084); ScanWeapons() end
	end)
end

-- ==================== 视线 ====================
local function BuildIgnore()
	local ig = {}
	local char = player.Character
	if char then
		for _,p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") then table.insert(ig, p) end
		end
		for _,t in ipairs(char:GetChildren()) do
			if t:IsA("Tool") then
				table.insert(ig, t)
				for _,c in ipairs(t:GetDescendants()) do
					if c:IsA("BasePart") then table.insert(ig, c) end
				end
			end
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
	return ig
end

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
				local d=(ph.Position-hrp.Position).Magnitude
				if d<=MAX_RANGE then
					local tr = GetRole(p)
					if myRole and tr then
						if (DCLASS[myRole] and DCLASS[tr]) or
						   (FOUNDATION[myRole] and FOUNDATION[tr]) or
						   (CHAOS[myRole] and CHAOS[tr]) then
							continue
						end
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
				local tr = GetRole(p)
				if myRole and tr then
					if (DCLASS[myRole] and DCLASS[tr]) or
					   (FOUNDATION[myRole] and FOUNDATION[tr]) or
					   (CHAOS[myRole] and CHAOS[tr]) then
						continue
					end
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

-- ==================== 脚底圆圈 ====================
local CircleParts = {}
local function DestroyCircle()
	for _,p in ipairs(CircleParts) do pcall(function() p:Destroy() end) end
	CircleParts={}
end
local function CreateCircle()
	DestroyCircle()
	if not drawCircle then return end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	for i=1,44 do
		local a=(i/44)*math.pi*2
		local pt=Instance.new("Part")
		pt.Anchored=true; pt.CanCollide=false; pt.CastShadow=false
		pt.Material=Enum.Material.Neon; pt.Color=Color3.fromRGB(231,235,241); pt.Transparency=0.547
		pt.Size=Vector3.new(0.077,0.007,0.072)
		pt.CFrame=CFrame.new(hrp.Position+Vector3.new(math.cos(a)*MELEE_RANGE, -0.009, math.sin(a)*MELEE_RANGE))
		pt.Parent=Workspace; table.insert(CircleParts, pt)
	end
end
local function UpdateCircle()
	if not drawCircle then DestroyCircle(); return end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then DestroyCircle(); return end
	if #CircleParts==0 then CreateCircle(); return end
	for i,pt in ipairs(CircleParts) do
		local a=(i/#CircleParts)*math.pi*2
		pt.CFrame=CFrame.new(hrp.Position+Vector3.new(math.cos(a)*MELEE_RANGE, -0.010, math.sin(a)*MELEE_RANGE))
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

	if drawVis then
		local beam=Instance.new("Part")
		beam.Anchored=true; beam.CanCollide=false; beam.Material=Enum.Material.Neon
		beam.Color=Color3.fromRGB(227,233,239); beam.Transparency=0.329
		beam.Size=Vector3.new(0.035,0.043,(aim-org).Magnitude)
		beam.CFrame=CFrame.new(org,aim)*CFrame.new(0,0,-beam.Size.Z/2)
		beam.Parent=Workspace
		local hit=Instance.new("Part")
		hit.Anchored=true; hit.CanCollide=false; hit.Material=Enum.Material.Neon
		hit.Color=Color3.fromRGB(237,242,249); hit.Transparency=0.418; hit.Shape=Enum.PartType.Ball
		hit.Size=Vector3.new(0.355,0.347,0.307); hit.CFrame=CFrame.new(aim); hit.Parent=Workspace
		task.delay(0.745,function() pcall(function() beam:Destroy() end) pcall(function() hit:Destroy() end) end)
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

local function FireMelee(tgts)
	if #tgts==0 then return end
	local cam = Workspace:FindFirstChild("Camera")
	if not cam then return end
	for _,id in ipairs(WepList) do
		if IsMelee(WepNames[id]) then
			local cw=cam:FindFirstChild(id) or (task.wait(0.028) and cam:FindFirstChild(id))
			if cw and AttackEvent then pcall(function() AttackEvent:FireServer(id,{tgts[1].char,cw}) end) end
		end
	end
end

-- ==================== 职业映射 ====================
local RoleNames = {
	scientist="科学家", security="安保", mtf="机动特遣队", director="主管",
	d_class="D级人员", escaped_d="逃脱D级", escaped_d_class="逃脱D级",
	chaos_insurgency="混沌分裂者", rogue_agent="叛变特工",
	traitor="叛徒", renegade="反叛者", anomaly="异常实体",
}
local RoleColors = {
	scientist=Color3.fromRGB(99,163,204),
	security=Color3.fromRGB(171,176,185),
	mtf=Color3.fromRGB(53,111,219),
	director=Color3.fromRGB(109,198,110),
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

-- ==================== 透视系统 ====================
local ESP = {}
local function CleanESP(p)
	if ESP[p] then
		pcall(function()
			if ESP[p].Sg and ESP[p].Sg.Parent then ESP[p].Sg:Destroy() end
		end)
		ESP[p] = nil
	end
end

local function MakeESP(p)
	if p==player or ESP[p] then return end
	p.CharacterAdded:Connect(function()
		task.wait(0.258); CleanESP(p); task.spawn(function() MakeESP(p) end)
	end)
	p.CharacterRemoving:Connect(function() CleanESP(p) end)

	task.spawn(function()
		local char = p.Character or p.CharacterAdded:Wait()
		local hrp = char:WaitForChild("HumanoidRootPart",5)
		local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid",5)
		if not hrp or not hum then return end

		local sg = Instance.new("ScreenGui")
		sg.Name = "ESP_"..p.Name
		sg.ResetOnSpawn = false; sg.Enabled = true
		sg.IgnoreGuiInset = true; sg.DisplayOrder = 109
		sg.Parent = player:WaitForChild("PlayerGui")

		local box = Instance.new("Frame")
		box.Name = "Box"; box.BackgroundTransparency = 1; box.BorderSizePixel = 0; box.Parent = sg

		local stroke = Instance.new("UIStroke"); stroke.Thickness = 2; stroke.Parent = box
		local grad = Instance.new("UIGradient"); grad.Rotation = 94; grad.Parent = stroke

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

		ESP[p] = { Sg=sg, Box=box, Stroke=stroke, Grad=grad, HpBg=hpBg, HpFill=hpFill, Dist=distL, Hum=hum, Char=char, HRP=hrp }

		hum.HealthChanged:Connect(function(hp)
			if not hpFill or not hpFill.Parent then return end
			local r = math.clamp(hp / math.max(hum.MaxHealth,1), 0, 1)
			hpFill.Size = UDim2.new(1,0,r,0)
			hpFill.BackgroundColor3 = r>0.463 and Color3.fromRGB(28,146,62) or r>0.263 and Color3.fromRGB(198,144,39) or Color3.fromRGB(202,46,46)
		end)
	end)
end

for _,p in ipairs(Players:GetPlayers()) do task.spawn(function() MakeESP(p) end) end
Players.PlayerAdded:Connect(function(p) task.wait(0.329); MakeESP(p) end)
Players.PlayerRemoving:Connect(CleanESP)

local function ComputeBoundingBox(char, cam)
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	local any = false
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 0.936 then
			local cf, size = part.CFrame, part.Size
			local corners = {
				cf * Vector3.new( size.X/2, size.Y/2, size.Z/2),
				cf * Vector3.new( size.X/2, size.Y/2,-size.Z/2),
				cf * Vector3.new( size.X/2,-size.Y/2, size.Z/2),
				cf * Vector3.new( size.X/2,-size.Y/2,-size.Z/2),
				cf * Vector3.new(-size.X/2, size.Y/2, size.Z/2),
				cf * Vector3.new(-size.X/2, size.Y/2,-size.Z/2),
				cf * Vector3.new(-size.X/2,-size.Y/2, size.Z/2),
				cf * Vector3.new(-size.X/2,-size.Y/2,-size.Z/2),
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
	end
	if not any then return nil end
	return minX, minY, maxX, maxY
end

RunService.RenderStepped:Connect(function()
	if not espEnabled then
		for p,d in pairs(ESP) do if d.Sg then d.Sg.Enabled=false end end
	else
		local cam = Workspace.CurrentCamera
		if cam then
			local sw = cam.ViewportSize.X
			local sh = cam.ViewportSize.Y
			local margin = 2
			for p, d in pairs(ESP) do
				if not d.Sg or not d.Char or not d.HRP then CleanESP(p); continue end
				d.Sg.Enabled = true

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
						d.Stroke.Color = col
						d.Grad.Color = ColorSequence.new(col, col:Lerp(Color3.new(0,0,0), 0.344))

						local dist = (cam.CFrame.Position - d.HRP.Position).Magnitude
						d.Dist.Text = string.format("%.0fm", dist)
					end
				end

				if d.Hum and d.Hum.Health <= 0 then CleanESP(p) end
			end
		end
	end
end)

-- ==================== 穿门 ====================
local DoorSys = { Enabled=true, Range=7, RangeSq=49, Parts={}, Orig={} }
local function ScanDoors()
	local map = Workspace:FindFirstChild("Map")
	if not map then return 0 end
	local doors = map:FindFirstChild("Doors")
	if not doors then return 0 end
	local c = 0
	local function Rec(o)
		if o:IsA("BasePart") and not DoorSys.Parts[o] then
			DoorSys.Parts[o]=true; DoorSys.Orig[o]=o.CanCollide; c=c+1
		end
		for _,ch in ipairs(o:GetChildren()) do Rec(ch) end
	end
	Rec(doors); return c
end
local DoorCount = ScanDoors()
task.spawn(function() while true do task.wait(25) if DoorSys.Enabled then DoorCount=DoorCount+ScanDoors() end end end)
task.spawn(function()
	while true do task.wait(0.081)
		if not DoorSys.Enabled then task.wait(0.464); continue end
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not hrp then task.wait(0.461); continue end
		local px,py,pz=hrp.Position.X,hrp.Position.Y,hrp.Position.Z
		for pt in pairs(DoorSys.Parts) do
			if not pt or not pt.Parent then DoorSys.Parts[pt]=nil; DoorSys.Orig[pt]=nil; continue end
			local dx,dy,dz=pt.Position.X-px,pt.Position.Y-py,pt.Position.Z-pz
			if dx*dx+dy*dy+dz*dz <= DoorSys.RangeSq then
				if pt.CanCollide then pt.CanCollide=false end
			else
				local o=DoorSys.Orig[pt]; if o~=nil and pt.CanCollide~=o then pt.CanCollide=o end
			end
		end
	end
end)

-- ============================================================
--  ==================== 刷钱系统（修复版） ====================
--  核心修复：自杀后等角色彻底消失，再请求选D级
--  不在角色刚生成时抢跑
-- ============================================================

local autoFarm = false
local farmRunning = false

-- 刷钱坐标
local FARM_TELEPORT = Vector3.new(1208.21240234375, 133.37843322753906, -677.5913696289062)

-- 时间常量
local FARM_DELAY_BEFORE_TP = 3.0    -- 延迟3秒再传送
local FARM_KEY_HOLD        = 0.08   -- 按键按住时间
local FARM_KEY_GAP         = 0.05   -- 按键间隔
local FARM_AFTER_KEYS      = 0.3    -- 按键后等0.3秒让服务器处理
local FARM_CHECK_INTERVAL  = 0.2    -- 检测逃出间隔
local FARM_ESCAPE_TIMEOUT  = 10.0   -- 按键后最长等10秒
local FARM_DEATH_DELAY     = 1.0    -- 确认逃出后等1秒再自杀
local FARM_REBIRTH_WAIT    = 2.0    -- 自杀后等角色消失
local FARM_MAX_RETRY       = 30     -- 最大重试次数

-- ========== 基础操作 ==========
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

-- 模拟按键
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

-- ========== 等待角色彻底消失（确认死亡） ==========
local function WaitForDeath(timeout)
	timeout = timeout or 8
	local start = tick()
	while player.Character and (tick() - start) < timeout do
		task.wait(0.1)
	end
	-- 额外缓冲，让服务端完全处理死亡
	task.wait(0.8)
	return true
end

-- ========== 等待角色完全加载 ==========
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

-- ========== 等待职业赋值 ==========
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

-- ========== 完整复活流程（核心修复） ==========
-- 步骤：
--  1. 杀掉当前角色
--  2. ★ 等角色彻底消失（不抢跑）
--  3. FireServer("d_class") 请求选D级
--  4. 等角色出现
--  5. 等角色完全加载（HRP + Health>0）
--  6. 等职业赋值为 d_class
--  7. 稳1秒后返回
local function FullRespawnAsDClass()
	local MAX_TIME = 30
	local start = tick()

	print("🌾 [复活] 开始完整复活流程")

	-- 步骤1：杀掉当前角色
	local hum = GetMyHumanoid()
	if hum and hum.Health > 0 then
		print("🌾 [复活] 步骤1：杀死当前角色")
		pcall(function() hum.Health = 0 end)
	end

	-- 步骤2：★ 等角色彻底消失（关键修复！）
	print("🌾 [复活] 步骤2：等待角色彻底消失...")
	local deathWait = 0
	while player.Character and deathWait < 10 do
		task.wait(0.1)
		deathWait = deathWait + 0.1
	end
	-- 额外缓冲，确保服务端处理完死亡
	task.wait(0.8)
	print("🌾 [复活] 角色已消失 ✅")

	if (tick() - start) > MAX_TIME then
		print("❌ [复活] 超时（等待死亡）")
		return false
	end

	-- 步骤3：请求选D级
	print("🌾 [复活] 步骤3：FireServer('d_class')")
	SelectDClass()

	-- 步骤4：等角色出现
	print("🌾 [复活] 步骤4：等待角色生成...")
	local char = nil
	local charWait = 0
	while not char and charWait < 15 do
		task.wait(0.2)
		charWait = charWait + 0.2
		char = player.Character
	end
	if not char then
		print("❌ [复活] 角色未生成")
		return false
	end
	print("🌾 [复活] 角色已生成 ✅")

	if (tick() - start) > MAX_TIME then
		print("❌ [复活] 超时（等待角色）")
		return false
	end

	-- 步骤5：等角色完全加载
	print("🌾 [复活] 步骤5：等待角色完全加载...")
	local charOk = WaitForCharacter(15)
	if not charOk then
		print("❌ [复活] 角色加载失败")
		return false
	end
	print("🌾 [复活] 角色完全加载 ✅")

	if (tick() - start) > MAX_TIME then
		print("❌ [复活] 超时（加载）")
		return false
	end

	-- 步骤6：等职业赋值
	print("🌾 [复活] 步骤6：等待职业赋值...")
	local role = WaitForRole(15)

	-- 如果分配的不是D级，再请求一次
	if role ~= "d_class" then
		print("⚠️ [复活] 职业是 " .. tostring(role) .. "，重新请求D级")
		SelectDClass()
		task.wait(1.0)
		role = myRole
	end

	if role ~= "d_class" then
		print("❌ [复活] 无法获得D级职业，当前: " .. tostring(role))
		return false
	end
	print("🌾 [复活] 职业确认为D级 ✅")

	-- 步骤7：稳1秒
	print("🌾 [复活] 步骤7：稳定等待1秒")
	task.wait(1.0)

	print("✅ [复活] 完整复活为D级成功！")
	return true
end

-- ========== 检测自己是否逃出 ==========
local function CheckSelfEscaped()
	return IsEscaped(player)
end

-- ========== 刷钱主循环（修复版） ==========
local function FarmLoop()
	if farmRunning then return end
	farmRunning = true

	print("🌾 刷钱循环启动 v6.14-fix")

	local retryCount = 0

	while autoFarm do
		-- ========== ① 检测自己是否有职业 ==========
		local char = player.Character
		local hum = GetMyHumanoid()
		local alive = hum and hum.Health > 0
		local hasRole = myRole and myRole ~= ""

		if not char or not alive or not hasRole then
			-- 没有职业或没活着 → 走完整复活流程
			retryCount = retryCount + 1
			if retryCount > FARM_MAX_RETRY then
				print("❌ 刷钱重试超过" .. FARM_MAX_RETRY .. "次，停止")
				break
			end

			print("🌾 无职业/未存活 → 完整复活 (尝试 #" .. retryCount .. ")")
			print("   状态: char=" .. tostring(char ~= nil) ..
				  " alive=" .. tostring(alive) ..
				  " role=" .. tostring(myRole))

			local ok = FullRespawnAsDClass()
			if not ok then
				print("⚠️ 复活失败，等2秒后重试")
				task.wait(2.0)
				continue
			end

			-- 复活成功，确认是D级
			retryCount = 0
			print("✅ 已复活为D级: " .. tostring(myRole))

			-- 回到循环开头，下一轮检测逃出
			task.wait(0.5)
			continue
		end

		-- 有职业且活着 → 重置计数
		retryCount = 0

		-- ========== ② 确认自己是D级 ==========
		if myRole ~= "d_class" then
			print("⚠️ 职业不是D级 (当前:" .. tostring(myRole) .. ")，重新复活")
			KillMySelf()
			-- 等角色消失后再回到循环开头
			task.wait(1.5)
			continue
		end

		-- ========== ③ 检测自己是否逃出 ==========
		if CheckSelfEscaped() then
			print("🌾 检测到已逃出 → 等" .. FARM_DEATH_DELAY .. "秒后自杀")
			task.wait(FARM_DEATH_DELAY)
			KillMySelf()
			print("💀 已自杀，等待角色消失后重生...")
			-- ★ 等角色消失后再回到循环开头走复活
			task.wait(FARM_REBIRTH_WAIT)
			continue
		end

		-- ========== ④ 没逃出 → 延迟3秒再传送 ==========
		print("🌾 未逃出 → 延迟" .. FARM_DELAY_BEFORE_TP .. "秒后传送")
		task.wait(FARM_DELAY_BEFORE_TP)

		-- 延迟期间可能死了（被攻击等），检查
		hum = GetMyHumanoid()
		if not hum or hum.Health <= 0 then
			print("⚠️ 延迟期间死亡，重新循环")
			task.wait(FARM_REBIRTH_WAIT)
			continue
		end

		-- 延迟期间可能逃出了，再检查一次
		if CheckSelfEscaped() then
			print("🌾 延迟期间逃出 → 自杀")
			task.wait(FARM_DEATH_DELAY)
			KillMySelf()
			task.wait(FARM_REBIRTH_WAIT)
			continue
		end

		-- ========== ⑤ 传送 ==========
		local tpOk = TeleportTo(FARM_TELEPORT)
		if not tpOk then
			print("⚠️ 传送失败（无HRP），等0.5秒重试")
			task.wait(0.5)
			continue
		end
		print("🌾 已传送到刷钱点")

		-- 传送后微等让服务器确认位置
		task.wait(0.2)

		-- ========== ⑥ 模拟按2下S，2下W ==========
		PressKey(Enum.KeyCode.S, 2)
		task.wait(FARM_KEY_GAP)
		PressKey(Enum.KeyCode.W, 2)
		print("🌾 已按键 S×2 W×2")

		-- 按键后等服务器处理
		task.wait(FARM_AFTER_KEYS)

		-- ========== ⑦ 检测是否逃出（循环检测） ==========
		local checkStart = tick()
		local escaped = false

		while (tick() - checkStart) < FARM_ESCAPE_TIMEOUT do
			-- 先检查是否还活着
			hum = GetMyHumanoid()
			if not hum or hum.Health <= 0 then
				print("⚠️ 检测期间死亡，重新循环")
				task.wait(FARM_REBIRTH_WAIT)
				break  -- 回到外循环
			end

			-- 检测逃出
			if CheckSelfEscaped() then
				escaped = true
				break
			end

			task.wait(FARM_CHECK_INTERVAL)
		end

		if escaped then
			-- ========== 逃出成功 → 自杀 → 等角色消失 → 复活 ==========
			print("🌾 逃出成功！等" .. FARM_DEATH_DELAY .. "秒后自杀")
			task.wait(FARM_DEATH_DELAY)
			KillMySelf()
			print("💀 已自杀，等待角色消失...")
			-- ★ 等角色消失后再回到循环开头走复活
			task.wait(FARM_REBIRTH_WAIT)
			-- 回到外循环开头 → 走完整复活流程 → 继续刷钱
		else
			-- 超时未逃出 → 自杀 → 等角色消失 → 复活
			print("⚠️ " .. FARM_ESCAPE_TIMEOUT .. "秒未逃出 → 自杀重试")
			KillMySelf()
			task.wait(FARM_REBIRTH_WAIT)
			-- 回到外循环开头
		end
	end

	farmRunning = false
	print("🌾 刷钱循环停止")
end

-- ==================== 战斗主循环 ====================
ScanWeapons()
local LastShoot, LastMelee = 0, 0
player.CharacterAdded:Connect(function(char)
	HookChar(char)
	task.wait(0.308); ScanWeapons(); task.wait(0.294)
	if drawCircle then pcall(CreateCircle) end
end)
task.spawn(function() while true do task.wait(1.501); ScanWeapons() end end)

RunService.Heartbeat:Connect(function()
	local now = tick()

	-- 刷钱期间暂停射击/近战
	if autoFarm and farmRunning then
		pcall(UpdateCircle)
		return
	end

	if autoMelee and HasMelee() and now-LastMelee>=MELEE_CD then
		local t=GetMeleeTargets(); if #t>0 then FireMelee(t); LastMelee=now end
	end
	if autoShoot and now-LastShoot>=SHOOT_CD then
		local hasR, isSG = HasRanged()
		if hasR then
			local e=GetEnemies(); if #e>0 then FireRanged(e[1]); LastShoot=now end
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
	local PW = math.floor((IS_MOBILE and 280 or 330) * scale)
	local PH = math.floor((IS_MOBILE and 340 or 400) * scale)
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
	TL.BackgroundTransparency=1; TL.Text="⚔️ SCP异常站点"
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

	-- 第1排
	local SHT = mkBtn("🔫射击", C.Green); SHT.Position=UDim2.new(0,PAD,0,y)
	local MEL = mkBtn("🔪近战", C.Purple); MEL.Position=UDim2.new(0,PAD+BW+GAP,0,y)
	local RAY = mkBtn("👁️射线", C.Blue); RAY.Position=UDim2.new(0,PAD+(BW+GAP)*2,0,y)
	local VIS = mkBtn("📡弹道", C.Yellow); VIS.Position=UDim2.new(0,PAD+(BW+GAP)*3,0,y)
	y = y + BH + GAP

	SHT.MouseButton1Click:Connect(function() autoShoot=not autoShoot; SHT.BackgroundColor3=autoShoot and C.Green or C.Red end)
	MEL.MouseButton1Click:Connect(function() autoMelee=not autoMelee; MEL.BackgroundColor3=autoMelee and C.Purple or C.Red end)
	RAY.MouseButton1Click:Connect(function()
		rayEnabled=not rayEnabled; RAY.Text=rayEnabled and "👁️射线" or "💀穿墙"
		RAY.BackgroundColor3=rayEnabled and C.Blue or C.Red
	end)
	VIS.MouseButton1Click:Connect(function() drawVis=not drawVis; VIS.BackgroundColor3=drawVis and C.Yellow or C.Red end)

	-- 第2排
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

	RGL.MouseButton1Click:Connect(function()
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
		ok.MouseButton1Click:Connect(function()
			local n=tonumber(tb.Text)
			if n and n>=10 and n<=2000 then MAX_RANGE=math.floor(n) end
			RGL.Text="🔫射程:"..MAX_RANGE; overlay:Destroy()
		end)
		tb.FocusLost:Connect(function(ep)
			if ep then
				local n=tonumber(tb.Text)
				if n and n>=10 and n<=2000 then MAX_RANGE=math.floor(n) end
				RGL.Text="🔫射程:"..MAX_RANGE; overlay:Destroy()
			end
		end)
	end)

	-- 第3排
	local DRB = mkBtn("🚪穿门", C.Green); DRB.Position=UDim2.new(0,PAD,0,y)

	local MRL = Instance.new("TextButton")
	MRL.Size=UDim2.new(0,BW*2+GAP,0,BH)
	MRL.Position=UDim2.new(0,PAD+BW+GAP,0,y)
	MRL.BackgroundColor3=C.Label; MRL.BackgroundTransparency=0.052
	MRL.Text="🔪近战:"..MELEE_RANGE; MRL.TextColor3=C.Text; MRL.Font=Enum.Font.GothamBold; MRL.TextSize=BS; MRL.Parent=CC
	Instance.new("UICorner",MRL).CornerRadius=UDim.new(0,4)
	y = y + BH + GAP

	DRB.MouseButton1Click:Connect(function()
		DoorSys.Enabled=not DoorSys.Enabled; DRB.BackgroundColor3=DoorSys.Enabled and C.Green or C.Red
		if not DoorSys.Enabled then
			for pt in pairs(DoorSys.Parts) do local o=DoorSys.Orig[pt]; if o~=nil and pt and pt.Parent then pt.CanCollide=o end end
		end
	end)

	MRL.MouseButton1Click:Connect(function()
		local overlay = Instance.new("Frame")
		overlay.Size=UDim2.new(0,math.floor(190*scale),0,math.floor(72*scale))
		overlay.Position=UDim2.new(0,PAD+BW+GAP,0,y-BH-GAP-math.floor(80*scale))
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
		ok.MouseButton1Click:Connect(function()
			local n=tonumber(tb.Text)
			if n and n>=2 and n<=20 then MELEE_RANGE=math.floor(n); pcall(CreateCircle) end
			MRL.Text="🔪近战:"..MELEE_RANGE; overlay:Destroy()
		end)
		tb.FocusLost:Connect(function(ep)
			if ep then
				local n=tonumber(tb.Text)
				if n and n>=2 and n<=20 then MELEE_RANGE=math.floor(n); pcall(CreateCircle) end
				MRL.Text="🔪近战:"..MELEE_RANGE; overlay:Destroy()
			end
		end)
	end)

	-- 第4排
	local SIL = mkBtn("🔇静默", Color3.fromRGB(85,88,95))
	SIL.Position = UDim2.new(0, PAD, 0, y)
	SIL.Size = UDim2.new(0, BW, 0, BH)

	local FMB = mkBtn("🌾刷钱:关", C.Orange)
	FMB.Position = UDim2.new(0, PAD + BW + GAP, 0, y)

	local TPB = mkBtn("📍传送刷钱点", C.Dark)
	TPB.Position = UDim2.new(0, PAD + (BW + GAP) * 2, 0, y)
	TPB.Size = UDim2.new(0, BW * 2 + GAP, 0, BH)
	y = y + BH + GAP

	SIL.MouseButton1Click:Connect(function()
		silentMode = not silentMode
		SIL.BackgroundColor3 = silentMode and Color3.fromRGB(84,89,99) or Color3.fromRGB(82,87,97)
		SIL.Text = silentMode and "🔇静默ON" or "🔇静默"
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

	-- ==================== 手机端提示 ====================
	if IS_MOBILE then
		local MP = Instance.new("Frame")
		MP.Size = UDim2.new(0, math.floor(260*scale), 0, math.floor(80*scale))
		MP.Position = UDim2.new(0.5, -math.floor(130*scale), 0.3, 0)
		MP.BackgroundColor3 = Color3.fromRGB(40,42,48)
		MP.BackgroundTransparency = 0.05
		MP.BorderSizePixel = 0
		MP.Parent = sg
		Instance.new("UICorner",MP).CornerRadius = UDim.new(0,8)

		local MPT = Instance.new("TextLabel")
		MPT.Size = UDim2.new(1, -16, 1, -10)
		MPT.Position = UDim2.new(0, 8, 0, 5)
		MPT.BackgroundTransparency = 1
		MPT.Text = "📱 手机端已启动\n⚠️ 刷钱期间将无法奔跑\n请保持站立等待"
		MPT.TextColor3 = Color3.fromRGB(255,175,40)
		MPT.Font = Enum.Font.GothamBold
		MPT.TextSize = math.floor(12*scale)
		MPT.TextWrapped = true
		MPT.Parent = MP

		task.delay(5, function() pcall(function() MP:Destroy() end) end)
	end

	print("✅ UI 创建完成")
end)

-- ==================== 状态更新循环 ====================
task.spawn(function()
	while true do task.wait(0.360)
		local myHRP = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local enemyCount, violateCount, escapeCount = 0,0,0

		if myHRP then
			for _,p in ipairs(Players:GetPlayers()) do
				if p~=player and p.Character then
					local hrp=p.Character:FindFirstChild("HumanoidRootPart")
					local hu=p.Character:FindFirstChildOfClass("Humanoid")
					if hrp and hu and hu.Health>0 then
						local d=(hrp.Position-myHRP.Position).Magnitude
						if d<=MAX_RANGE and IsEnemy(p) then enemyCount=enemyCount+1 end
						if IsHostile(p) then violateCount=violateCount+1 end
						if IsEscaped(p) then escapeCount=escapeCount+1 end
					end
				end
			end
		end

		if UI.StatusLabel then
			local roleName = RoleNames[myRole] or (myRole or "未知")
			local wid = currentWeaponID
			if #wid>8 then wid=wid:sub(1,8).."..." end
			local modeStr = ""
			if silentMode then modeStr = " 🔇静默"
			elseif funMode then modeStr = " 🎵娱乐"
			end
			local farmStr = autoFarm and " 🌾刷钱" or ""
			local txt = string.format("职业:%s\n武器:%s\nID:%s\n敌人:%d 违规:%d 逃出:%d 门:%d%s%s",
				roleName, currentWeaponName, wid, enemyCount, violateCount, escapeCount, DoorCount, modeStr, farmStr)
			pcall(function() UI.StatusLabel.Text=txt end)
		end

		-- 玩家列表（二段式：友军 / 敌人）
		if UI.PlayerListLabel and ListVisible then
			local friendLines = {}
			local enemyLines = {}

			for _,p in ipairs(Players:GetPlayers()) do
				if p~=player then
					local role=GetRole(p) or "?"
					local cn=RoleNames[role] or role
					local isHostile = IsHostile(p)
					local isEscaped = IsEscaped(p)

					local dist=""
					if myHRP and p.Character then
						local hrp=p.Character:FindFirstChild("HumanoidRootPart")
						if hrp then dist=string.format(" %.0fm",(myHRP.Position-hrp.Position).Magnitude) end
					end

					local suffix = ""
					if isHostile then suffix = suffix .. " ❗" end
					if isEscaped then suffix = suffix .. " 🏃" end

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

			local allLines = {}

			if #friendLines > 0 then
				table.insert(allLines, "===== 友军 =====")
				for _, l in ipairs(friendLines) do
					table.insert(allLines, l)
				end
				table.insert(allLines, "")
			end

			if #enemyLines > 0 then
				table.insert(allLines, "===== 敌人 =====")
				for _, l in ipairs(enemyLines) do
					table.insert(allLines, l)
				end
			end

			pcall(function() UI.PlayerListLabel.Text = table.concat(allLines, "\n") end)
		end
	end
end)

-- ==================== 角色初始化 ====================
if player.Character then
	HookChar(player.Character)
end

print("✅ SCP异常站点 v6.14-fix 已启动")
print("📦 功能：射击|近战|射线检测|显示弹道|范围|透视|穿门|娱乐|静默|刷钱")
print("🎯 透视：包围盒+渐变方框+竖血条")
print("💥 霰弹枪：与普通枪同一系统，8发打头")
print("🌾 刷钱逻辑（修复版）：")
print("  ① 检测职业 → 无则杀自己 → ★等角色消失→选D级→等生成→等职业")
print("  ② 确认是D级")
print("  ③ 检测逃出 → 逃出则自杀 → ★等角色消失→复活循环")
print("  ④ 未逃出 → 延迟3秒 → 传送")
print("  ⑤ 按S×2 W×2")
print("  ⑥ 检测逃出 → 逃出则自杀 → 循环")
print("🎨 D级金黄橙(255,175,40) 混沌柠檬黄(220,180,30)")
