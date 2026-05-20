--俄亥俄州
local ohio = function(...)
    secureCheck(...)
    game.TextChatService.ChatWindowConfiguration.Enabled = true
    local banned = game:GetService("ReplicatedStorage"):FindFirstChild("devv"):FindFirstChild("remoteStorage"):FindFirstChild("makeExplosion")
    if banned then
        game:GetService("ReplicatedStorage"):FindFirstChild("devv"):FindFirstChild("remoteStorage"):FindFirstChild("makeExplosion"):Destroy()
    end

    local Players = game:GetService("Players")
    local localPlayer = Players.LocalPlayer
    local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
    local rootPart = character:WaitForChild("HumanoidRootPart")
    
    localPlayer.CharacterAdded:Connect(function(newCharacter)
        character = newCharacter
        rootPart = newCharacter:WaitForChild("HumanoidRootPart")
    end)

    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local reqload = require(ReplicatedStorage.devv).load
    local makeToast = reqload("makeToast")
    makeToast("Snow on top", "rainbow", 5)
    
    local rs = game:GetService("RunService")
    local lp = game:GetService("Players").LocalPlayer
    local Players = game:GetService("Players")
    local localPlayer = Players.LocalPlayer
    local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
    local rootPart = character:WaitForChild("HumanoidRootPart")
    
    localPlayer.CharacterAdded:Connect(function(newCharacter)
        character = newCharacter
        rootPart = newCharacter:WaitForChild("HumanoidRootPart")
    end)

    local atms = workspace.ATMs
    local off = Vector3.new(0, -3, 0)
    local rot = CFrame.Angles(1.57079632679, 0, 0)
    local target, timer, state = nil, 0, 0
    local FireServer = require(game:GetService("ReplicatedStorage").devv.client.Helpers.remotes.Signal).FireServer
    local InvokeServer = require(game:GetService("ReplicatedStorage").devv.client.Helpers.remotes.Signal).InvokeServer
    local items = require(game:GetService('ReplicatedStorage').devv).load('v3item').inventory.items

    local lastThrowTime = 0
    local tntid

    local function GetGuid(name)
        for _,v in pairs(items) do
            if v.name==name then
                return v.guid
            end
        end
    end

    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Signal = require(ReplicatedStorage.devv.client.Helpers.remotes.Signal)
    local FireServer, InvokeServer = Signal.FireServer, Signal.InvokeServer
    local Inventory = require(ReplicatedStorage.devv).load("v3item").inventory
    local NextThrow = 0

    local FromATM, FromBank, autobx, autozbd, sell, remls, autouse = false, false, false, false, false, false, false
    local autovest, autohealth, autokz, callphone = false, false, false, false
    getgenv().purchaseTeleport = true
    getgenv().returnTeleport = true
    local shoppingOrigin = nil
    local purchaseQueue = {}
    local isPurchasing = false
    local returnTimer = nil
    local returnDelay = 0.5
    
    local PurchaseCoords = {
        ["Light Vest"] = CFrame.new(1590.4, 6.4, -628.1),
        ["Lockpick"] = CFrame.new(1622.4, 6.5, -631.4),
        ["TNT"] = CFrame.new(1522.6, 6.4, -911.0),
        ["Black Bandana"] = CFrame.new(605.8, 6.3, -1018.4),
        ["Bandage"] = CFrame.new(1166.5, 26.6, -972.7),
        ["Raygun"] = CFrame.new(148.7, -95.6, -529.3)
    }

    function SmartTeleportPurchase(itemName)
        if not getgenv().purchaseTeleport then
            return InvokeServer('attemptPurchase', itemName)
        end
        
        local targetCF = PurchaseCoords[itemName]
        if not targetCF then
            return InvokeServer('attemptPurchase', itemName)
        end
        
        local Players = game:GetService("Players")
        local localPlayer = Players.LocalPlayer
        local character = localPlayer.Character
        if not character or not character:FindFirstChild("HumanoidRootPart") then
            return false
        end
        
        local hrp = character.HumanoidRootPart
        
        if not shoppingOrigin then
            shoppingOrigin = hrp.CFrame
        end
        
        hrp.CFrame = targetCF
        task.wait(0.3)
        
        local success, result = pcall(function()
            return InvokeServer('attemptPurchase', itemName)
        end)
        
        if getgenv().returnTeleport and shoppingOrigin then
            task.wait(0.1)
            
            if #purchaseQueue > 0 then
                task.spawn(function()
                    ProcessPurchaseQueue()
                end)
            else
                hrp.CFrame = shoppingOrigin
                shoppingOrigin = nil
            end
        end
        
        return success
    end

    function BuyItemQueue(itemName)
        table.insert(purchaseQueue, itemName)
        if not isPurchasing then
            ProcessPurchaseQueue()
        end
    end

    function ProcessPurchaseQueue()
        if #purchaseQueue == 0 then
            isPurchasing = false
            return
        end
        
        isPurchasing = true
        local itemName = table.remove(purchaseQueue, 1)
        
        SmartTeleportPurchase(itemName)
        
        task.wait(0.5)
        ProcessPurchaseQueue()
    end

    rs.Heartbeat:Connect(function()
        if not FromBank then return end

        local Robbery = workspace:FindFirstChild("BankRobbery")
        if not Robbery then return end

        local Vault = Robbery:FindFirstChild("VaultDoor")
        local VPos = Vault and (Vault:IsA("Model") and Vault:GetPivot().Position or Vault.Position)

        if VPos and (VPos - Vector3.new(1123.70703125, 13.76093578338623, -353.52301025390625)).Magnitude < 0.5 then
            if tick() < NextThrow then return end
            NextThrow = tick() + 5

            local TNT
            for _, v in pairs(Inventory.items) do
                if v.name == "TNT" then TNT = v.guid break end
            end

            if not TNT then
                BuyItemQueue("TNT")
                return
            end

            rootPart.CFrame = CFrame.new(1123.54749, 8.31286526, -364.052216)

            local vaultPos = Vector3.new(1123.70703125, 13.76093578338623, -353.52301025390625)
            local direction = (vaultPos - rootPart.Position).Unit
            
            FireServer("equip", TNT)
            FireServer("throwItem", TNT, direction, Vector3.new(1124.0853271484, 5.3128666877747, -357.68710327148))
            FireServer("removeItem", TNT)
        else
            local Cash = Robbery:FindFirstChild("BankCash")
            local Main = Cash and Cash:FindFirstChild("Main")
            local Att = Main and Main:FindFirstChild("Attachment")
            local Prompt = Att and Att:FindFirstChild("ProximityPrompt")

            if Prompt and Prompt.Enabled then
                rootPart.CFrame = CFrame.new(1110.40369, 2, -325.485962)
                FireServer("stea\211\143BankCash")
            end
        end
    end)

    local childrenCache = {}
    local itemMap= {}
    local function updateCache()
        childrenCache = game.Workspace.Game.Entities.ItemPickup:GetChildren()
        itemMap = {}
        for _, model in pairs(childrenCache) do
            for _, v in pairs(model:GetChildren()) do
                if (v:IsA("MeshPart") or v:IsA("Part")) then
                    local e = v:FindFirstChildOfClass("ProximityPrompt")
                    if e and e.ObjectText then
                        itemMap[e.ObjectText] = {
                            part = v,
                            prompt = e
                        }
                    end
                end
            end
        end
    end
    updateCache()
    local itemPickupFolder= game.Workspace.Game.Entities:FindFirstChild("ItemPickup")
    if itemPickupFolder then
        itemPickupFolder.ChildAdded:Connect(function()
            updateCache()
        end)
        itemPickupFolder.ChildRemoved:Connect(function()
            updateCache()
        end)
    end
    local function Autoitem(itemName)
        local itemData = itemMap[itemName]
        if itemData then
            rootPart.CFrame = itemData.part.CFrame
            itemData.prompt.RequiresLineOfSight = false
            itemData.prompt.HoldDuration = 0
            fireproximityprompt(itemData.prompt)
            return true
        end
        return false
    end

    local busy = false
    rs.Heartbeat:Connect(function()
        if FromATM and not busy then
            local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            local dist, target = math.huge, nil
            for _, v in pairs(atms:GetChildren()) do
                if v:IsA("Model") and (v:GetAttribute("health") or 0) > 0 then
                    local d = (hrp.Position - v:GetPivot().Position).Magnitude
                    if d < dist then dist, target = d, v end
                end
            end
            if target then
                busy = true
                hrp.CFrame = (target:GetPivot() + off) * rot
                task.spawn(function()
                    task.wait(0.2)
                    target:SetAttribute("health", 0)
                    target:SetAttribute("isDestroyed", true)
                    task.wait(1)
                    busy = false
                end)
            end
        end
    end)

    rs.Heartbeat:Connect(function()
        if FromBalloon then
            for _,v in pairs(game:GetService("ReplicatedStorage").devv.shared.Indicies.v3items.bin.Holdable:GetChildren()) do
                if v:IsA("ModuleScript") then
                    local itemData = require(v)
                    if itemData.holdableType == "Balloon" and itemData.name ~= 'Balloon' then
                        Autoitem(v.Name)
                    end
                end
            end
        end
    end)

    rs.Heartbeat:Connect(function()
        local cashBundles = Workspace.Game.Entities.CashBundle
        local MAX_DISTANCE = 20
        for _, descendant in pairs(cashBundles:GetDescendants()) do
                if descendant:IsA("ClickDetector") then
                    local detectorPos = descendant.Parent:GetPivot().Position
                    local distance = (rootPart.Position - detectorPos).Magnitude
                    if distance <= MAX_DISTANCE then
                        fireclickdetector(descendant)
                    end
                end
            end
    end)

    rs.Heartbeat:Connect(function()
        local bars = game:GetService("Players").LocalPlayer.PlayerGui.Hotbar.Holder.Bars
        bars.Strength.Visible = true
        if AntiDoll then
            local isRagdolled = game:GetService("Players").LocalPlayer:GetAttribute("isRagdoll")
            local load = require(game:GetService("ReplicatedStorage").devv).load
            local client = load("ClientReplicator")
            if isRagdolled then
                FireServer("setRagdoll", false)
                client.Set(lp, "ragdolled", false)
                lp:SetAttribute("isRagdoll", false)
            end
        end
        if AntiAdmin then
            for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
                if player:GetAttribute("clanId") == "6557c057b60ffcc7226f532c" then
                    game:GetService("Players").LocalPlayer:Kick('[Anti Admin] Admin UserName = '.. player.Name)
                    break
                end
            end
        end
    end)

    local sig = require(game:GetService("ReplicatedStorage").devv).load("Signal")
    local ps, lp, lastTick = game:GetService("Players"), game:GetService("Players").LocalPlayer, 0

    rs.Heartbeat:Connect(function()
        if callphone then
            if tick() - lastTick < 0.5 then return end
            lastTick = tick()
            for _, p in ps:GetPlayers() do
                if p ~= lp then
                    task.spawn(function()
                        local ok, id = sig.InvokeServer("attemptCall", p.UserId)
                        if ok then sig.FireServer("sendPhoneAction", id, "hangup") end
                    end)
                end
            end
        end
    end)

    rs.Heartbeat:Connect(function()
        if openfake then
            local v_u_1 = require(game:GetService("ReplicatedStorage").devv).load
            local v_u_2 = v_u_1("moneyDisplay")
            v_u_1("v3sound")
            v_u_2.current = getgenv().fakemoney
            v_u_2.tweenTo = getgenv().fakemoney
            local v6 = v_u_1("v3item").inventory.getEquipped()
            if v6 and v6.name == "Wallet" then
                v6.controller:updateMoney(getgenv().fakemoney)
            end
        end
    end)

    local silentaim = false
    local function findTarget()
        if not silentaim then return nil end
        local Players = game:GetService("Players")
        local LocalPlayer = Players.LocalPlayer
        local Camera = workspace.CurrentCamera
        
        local closestTarget = nil
        local closestDistance = math.huge
        
        for _, player in pairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local head = player.Character:FindFirstChild("Head")
                if head then
                    local distance = (head.Position - Camera.CFrame.Position).Magnitude
                    if distance < closestDistance then
                        closestDistance = distance
                        closestTarget = head
                    end
                end
            end
        end
        return closestTarget
    end

    local function setupHooks()
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local success, loadModule = pcall(function() 
            return require(ReplicatedStorage:WaitForChild("devv")).load 
        end)
        
        if not success then return end
        local v3item = loadModule("v3item")
        if v3item and v3item.projectiles then
            local oldFn = v3item.projectiles.newProjectileOfType
            v3item.projectiles.newProjectileOfType = function(ptype, pdata)
                local target = findTarget()
                if target and pdata.cframe then
                    pdata.cframe = CFrame.lookAt(pdata.cframe.Position, target.Position)
                end
                return oldFn(ptype, pdata)
            end
        end
    end
    setupHooks()

    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer
    local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
    local TweenService = game:GetService("TweenService")

    function buyItem(itemName)
        InvokeServer("attemptPurchase", itemName)
    end

    function Teleport(cframe)
        local tweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Linear)
        local tween = TweenService:Create(HumanoidRootPart, tweenInfo, {CFrame = cframe})
        tween:Play()
        tween.Completed:Wait()
    end

    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local TS = game:GetService("TweenService")
    local DB = game:GetService("Debris")

    local LP = Players.LocalPlayer
    local Devv = require(ReplicatedStorage.devv)
    local Remote = require(ReplicatedStorage.devv.client.Helpers.remotes.Signal)
    local Inventory = Devv.load("v3item").inventory
    local guid = Devv.load("GUID")

    local lastMaskCheck = 0
    local maskProcessing = false
    local lastCombatTime = 0
    
    rs.Heartbeat:Connect(function()
        local now = tick()
        if now - lastCombatTime < 0.05 then return end
        lastCombatTime = now
        
        if autohealth then
            local character = game:GetService("Players").LocalPlayer.Character
            bdid = GetGuid('Bandage')
            if not bdid then
                BuyItemQueue('Bandage')
                return
            end
            for i, v in next, items do
                if v.name == 'Bandage' then
                    bande = v.guid
                    local humanoid = character:FindFirstChild("Humanoid")
                    if humanoid.Health ~= 0 and humanoid.Health < humanoid.MaxHealth then
                        FireServer("equip", bande)
                        FireServer("useConsumable", bande)
                        FireServer("removeItem", bande)
                    end
                    break
                end
            end
        end

        if autovest then
            veid = GetGuid('Light Vest')
            if not veid then
                BuyItemQueue('Light Vest')
                return
            end
            for i, v in next, items do
                if v.subtype == "vest" then
                    light = v.guid
                    local armor = localPlayer:GetAttribute('armor')
                    if armor == nil or armor <= 0 then
                        FireServer("equip", light)
                        FireServer("useConsumable", light)
                        FireServer("removeItem", light)
                    end
                    break
                end
            end
        end

        if autokz then
            if now - lastMaskCheck < 5 then
                return
            end
            lastMaskCheck = now
            
            if maskProcessing then
                return
            end
            
            maskProcessing = true
            
            local Mask = character:FindFirstChild("Black Bandana")
            if not Mask then
                kzid = GetGuid('Black Bandana')
                if not kzid then
                    BuyItemQueue('Black Bandana')
                else
                    for i, v in next, items do
                        if v.name == "Black Bandana" then
                            sugid = v.guid
                            FireServer("equip", sugid)
                            FireServer("wearMask", sugid)
                            break
                        end
                    end
                end
            end
            
            maskProcessing = false
        end
    end)

    local lastFindTime = 0
    rs.Heartbeat:Connect(function()
        local now = tick()
        if now - lastFindTime < 0.1 then return end
        lastFindTime = now
        
        if FromBalloon then
            for _,v in pairs(game:GetService("ReplicatedStorage").devv.shared.Indicies.v3items.bin.Holdable:GetChildren()) do
                if v:IsA("ModuleScript") then
                    local itemData = require(v)
                    if itemData.holdableType == "Balloon" and itemData.name ~= 'Balloon' then
                        Autoitem(v.Name)
                    end
                end
            end
        end
        
        if autoblock then
            Autoitem("Green Lucky Block")
            Autoitem("Orange Lucky Block")
            Autoitem("Purple Lucky Block")
        end

        if automoss then
            Autoitem("Medium Present")
            Autoitem("Large Present")
        end

        if autoxybs then
            Autoitem("Diamond")
            Autoitem("Void Gem")
            Autoitem("Dark Matter Gem")
            Autoitem("Rollie")
            Autoitem("Gold Crown")
            Autoitem("Gold Cup")
            Autoitem("Pearl Necklace")
        end

        if autoxywp then
            Autoitem("Blue Candy Cane")
            Autoitem("Suitcase Nuke")
            Autoitem("Nuke Launcher")
            Autoitem("Easter Basket")
            Autoitem("Gold Cup")
            Autoitem("Gold Crown")
            Autoitem("Treasure Map")
            Autoitem("Spectral Scythe")
        end

        if autoptbs then
            Autoitem("Amethyst")
            Autoitem("Sapphire")
            Autoitem("Emerald")
            Autoitem("Topaz")
            Autoitem("Ruby")
        end

        if automoney then
            Autoitem("Money Printer")
        end

        if card then
            local red = false
            for i, v in next, items do
                if v.name == "Military Armory Keycard" then
                    red = true
                    break
                end
            end
            if not red then
                Autoitem("Military Armory Keycard")
            end
        end
    end)

    local chestIndex = 1
    local chestList = {}
    local lastChestTime = 0
    local chestInterval = 0.5
    local lastTeleportTime = 0
    local teleportCooldown = 0.2
    
    rs.Heartbeat:Connect(function()
        if not autobx then
            chestIndex = 1
            chestList = {}
            return
        end
        
        local now = tick()
        if now - lastChestTime < chestInterval then return end
        lastChestTime = now
        
        if now - lastTeleportTime < teleportCooldown then
            return
        end
        
        veid = GetGuid('Lockpick')
        if not veid then
            BuyItemQueue('Lockpick')
            return
        end
        
        local hasLockpick = false
        for i, v in next, items do
            if v.name == "Lockpick" then
                hasLockpick = true
                break
            end
        end
        
        if not hasLockpick then
            return
        end
        
        if #chestList == 0 then
            chestList = {}
            chestIndex = 1
            
            local chestTypes = {"SmallChest", "LargeChest", "SmallSafe", "MediumSafe", "LargeSafe", "JewelSafe", "GoldJewelSafe"}
            for _, chestType in pairs(chestTypes) do
                local chestFolder = workspace.Game.Entities:FindFirstChild(chestType)
                if chestFolder then
                    for _, chest in pairs(chestFolder:GetChildren()) do
                        if not state then break end
                        if chest.PrimaryPart then
                            local prompt = chest:FindFirstChild("ProximityPrompt", true)
                            if prompt and prompt.Enabled then
                                table.insert(chestList, {
                                    chest = chest,
                                    prompt = prompt
                                })
                            end
                        end
                    end
                end
            end
        end
        
        if chestList[chestIndex] then
            local chestData = chestList[chestIndex]
            
            lastTeleportTime = tick()
            Teleport(chestData.chest.PrimaryPart.CFrame * CFrame.new(0, 3, 0))
            task.wait(teleportCooldown)
            
            if chestData.prompt and chestData.prompt.Enabled then
                fireproximityprompt(chestData.prompt)
                task.wait(0.2)
                chestIndex = chestIndex + 1
            else
                table.remove(chestList, chestIndex)
            end
        else
            chestIndex = 1
            chestList = {}
        end
    end)

    local zbtick = 0
    local lastAutoTime2 = 0
    rs.Heartbeat:Connect(function()
        local now = tick()
        if now - lastAutoTime2 < 0.2 then return end
        lastAutoTime2 = now
        
        if autouse then
            for i, v in pairs(items) do
            if v.type == "Consumable" and v.subtype ~= "vest" and v.subtype ~= "food" and v.name ~= "Lockpick" then
            FireServer("equip", v.guid)
            FireServer("useConsumable", v.guid)
            FireServer("removeItem", v.guid)
            end
            end
        end

        if autozbd then
            if tick() - zbtick < 0.3 then
                return
            end
            zbtick = tick()
            local cases = Workspace:FindFirstChild("GemRobbery"):FindFirstChild("JewelryCases")
            if cases then
                for _, descendant in pairs(cases:GetDescendants()) do
                    if not state then break end
                    if descendant:IsA("ProximityPrompt") and descendant.ActionText == "Steal" and descendant.Enabled == true then
                        descendant.HoldDuration = 0
                        Teleport(CFrame.new(descendant.Parent.Position + Vector3.new(0, 0, 0)))
                        fireproximityprompt(descendant)
                    end
                end
            end
        end

        if sell then
            for i, v in pairs(items) do
                if (v.type == "Holdable" and v.subtype == "gem" and v.sellPrice < 5000) or (v.subtype == "valuable") or (v.type == "Gun" and v.cost < 3999 and v.name ~= "Raygun")then
                    FireServer("equip", v.guid)
                    FireServer("sellItem", v.guid)
                end
            end
        end

        if remls then
            for i, v in pairs(items) do
                if (v.type == "Consumable" and v.subtype == "food" and v.name ~= "Bandage" ) or (v.type == "Throwable" and v.cost < 500 and v.name ~= "Ninja Star" and v.name ~= "Tomahawk") or (v.type == "Melee" and v.cost > 100 ) then
                    FireServer("removeItem", v.guid)
                end
            end
        end
    end)

    local Ohio = Window:Section({Title = "Ohio", Opened = true})
    
    local Kill = Ohio:Tab({ Title = "战斗" })

    Kill:Toggle({
        Title = "自动护甲",
        Default = false,
        Callback = function(state)
            autovest = state
        end
    })

    Kill:Toggle({
        Title = "自动回血",
        Default = false,
        Callback = function(state)
            autohealth = state
        end
    })

    Kill:Toggle({
        Title = "自动口罩",
        Default = false,
        Callback = function(state)
            autokz = state
        end
    })

    Kill:Toggle({
        Title = "电话骚扰",
        Default = false,
        Callback = function(state)
            callphone = state
        end
    })

    local Auto = Ohio:Tab({ Title = "自动" })

    Auto:Toggle({
        Title = "自动摧毁ATM",
        Default = false,
        Callback = function(state)
           FromATM = state
        end
    })

    Auto:Toggle({
        Title = "自动偷盗银行",
        Default = false,
        Callback = function(state)
           FromBank = state
        end
    })

    Auto:Toggle({
        Title = "自动打开保险",
        Default = false,
        Callback = function(state)
            autobx = state
        end
    })

    Auto:Toggle({
        Title = "自动珠宝店",
        Default = false,
        Callback = function(state)
            autozbd = state
        end
    })

    Auto:Toggle({
        Title = "自动售卖",
        Value = false,
        Callback = function(state) 
            sell = state
        end
    })

    Auto:Toggle({
        Title = "自动移除垃圾",
        Value = false,
        Callback = function(state) 
            remls = state
        end
    })

    Auto:Toggle({
        Title = "自动使用消耗品",
        Value = false,
        Callback = function(state) 
            autouse = state
        end
    })

    local From = Ohio:Tab({ Title = "寻找" })

    From:Toggle({
        Title = "自动寻找稀有物品",
        Default = false,
        Callback = function(state)
            autoxywp = state
        end
    })

    From:Toggle({
        Title = "自动寻找气球",
        Default = false,
        Callback = function(state)
            FromBalloon = state
        end
    })

    From:Toggle({
        Title = "自动寻找印钞机",
        Default = false,
        Callback = function(state)
            automoney = state
        end
    })

    From:Toggle({
        Title = "自动寻找普通宝石",
        Default = false,
        Callback = function(state)
            autoptbs = state
        end
    })

    From:Toggle({
        Title = "自动寻找稀有宝石",
        Default = false,
        Callback = function(state)
            autoxybs = state
        end
    })

    From:Toggle({
        Title = "自动寻找礼物",
        Default = false,
        Callback = function(state)
            automoss = state
        end
    })

    From:Toggle({
        Title = "自动寻找幸运方块",
        Default = false,
        Callback = function(state)
            autoblock = state
        end
    })

    From:Toggle({
        Title = "自动寻找红卡",
        Default = false,
        Callback = function(state)
            card = state
        end
    })

    local Countermeasures = Ohio:Tab({ Title = "反制" })
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local reqload = require(ReplicatedStorage.devv).load
    local makeToast = reqload("makeToast")

    Countermeasures:Button({
        Title = "重进当前服务器[慎！]",
        Locked = false,
        Callback = function()
            game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end
    })

    Countermeasures:Input({
        Title = "弹窗提醒内容",
        Value = "",
        Type = "Input",
        Callback = function(input)
            getgenv().make = input
        end
    })

    Countermeasures:Input({
        Title = "弹窗提醒时长(秒)",
        Value = "",
        Type = "Input",
        Callback = function(input)
            getgenv().makes = input
        end
    })

    Countermeasures:Button({
        Title = "开启弹窗",
        Locked = false,
        Callback = function()
            makeToast(getgenv().make, "rainbow", getgenv().makes)
        end
    })

    Countermeasures:Button({
        Title = "通话禁音",
        Locked = false,
        Callback = function()
            require(game:GetService("ReplicatedStorage").devv).load("Signal").FireServer("setAirplaneMode", true)
            local lp = game:GetService('Players').LocalPlayer
            lp:SetAttribute('isAirplaneMode', true)
        end
    })

    Countermeasures:Button({
        Title = "不允许战斗中",
        Locked = false,
        Callback = function()
            local combatModule = require(game:GetService("ReplicatedStorage").devv.client.Helpers.ui.combatIndicator)
            if hookfunction then
                hookfunction(combatModule.isInCombat, function() return false end)
                hookfunction(combatModule.enterCombat, function() end)
            end
        end
    })

    Countermeasures:Button({
        Title = "不允许被抓取",
        Locked = false,
        Callback = function()
            local GrabHandler = require(game:GetService("ReplicatedStorage").devv.client.Handlers.GrabHandler)
            local originalCheckValid = GrabHandler.CheckValid
            GrabHandler.CheckValid = function(p28, p29, p30)
                if p29 == game:GetService("Players").LocalPlayer then
                    return false
                end
                return originalCheckValid(p28, p29, p30)
            end
            local originalGrab = GrabHandler.Grab
            GrabHandler.Grab = function(p54, p55)
                if p55 == game:GetService("Players").LocalPlayer then
                    return
                end
                return originalGrab(p54, p55)
            end
        end
    })

    Countermeasures:Button({
        Title = "清除树叶",
        Locked = false,
        Callback = function()
            for _, part in pairs(workspace:GetDescendants()) do
                if part.Name == "Leaves" and part:IsA("MeshPart") then
                    part:Destroy()
                end
            end
        end
    })

    Countermeasures:Button({
        Title = "反坐下",
        Locked = false,
        Callback = function()
            local plr = game:GetService("Players").LocalPlayer
            local function antiSit(char)
                local hum = char:WaitForChild("Humanoid")
                hum:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
                hum:GetPropertyChangedSignal("Sit"):Connect(function()
                    if hum.Sit then
                        hum.Sit = false
                    end
                end)
                hum.Sit = false
            end
            if plr.Character then antiSit(plr.Character) end
            plr.CharacterAdded:Connect(antiSit)
        end
    })

    Countermeasures:Toggle({
        Title = "反布娃娃",
        Default = false,
        Callback = function(state)
            AntiDoll = state
        end
    })

    Countermeasures:Toggle({
        Title = "反管理",
        Default = false,
        Callback = function(state)
            AntiAdmin = state
        end
    })

    local Bypass = Ohio:Tab({ Title = "绕过" })

    Bypass:Input({
        Title = "伪装金钱数量",
        Value = "",
        Type = "Input",
        Callback = function(input)
            getgenv().fakemoney = input
        end
    })

    Bypass:Toggle({
        Title = "开启伪装",
        Default = false,
        Callback = function(state)
            openfake = state
        end
    })

    Bypass:Slider({
        Title = "物品栏数量",
        Value = {
            Min = 6,
            Max = 12,
            Default = 9,
        },
        Callback = function(value)
            local sum = require(ReplicatedStorage.devv.client.Objects.v3item.modules.inventory)
            sum.numSlots = value
        end
    })

    Bypass:Button({
        Title = "解锁移动经销商(无法使用)",
        Locked = false,
        Callback = function()
            local Signal = require(game:GetService("ReplicatedStorage").devv.client.Helpers.remotes.Signal)
            local Purchase = Signal.InvokeServer
            Signal.InvokeServer = function(self, ...)
                if self == "attemptPurchase" then
                    local itemName, isDealer = ...
                    return Purchase(self, itemName, false, select(3, ...))
                elseif self == "attemptPurchaseAmmo" then
                    local itemName, isDealer = ...
                    return Purchase(self, itemName, false, select(3, ...))
                end
                return Purchase(self, ...)
            end
            game:GetService("Players").LocalPlayer:SetAttribute("mobileDealer",true)
            local mobileDealer=require(ReplicatedStorage.devv.shared.Indicies.mobileDealer)
            for category,items in pairs(mobileDealer)do for _,item in ipairs(items)do item.stock=12e12 end end
            table.insert(mobileDealer.Gun,{itemName="Acid Gun",stock=12e12})
        end
    })

    Bypass:Button({
        Title = "解锁全皮肤",
        Locked = false,
        Callback = function()
            local ReplicatedStorage = game:GetService('ReplicatedStorage')
            local skinsModule = require(ReplicatedStorage.devv.client.Helpers.ui.screens.CaseMenu.Skins)
            local load = require(ReplicatedStorage.devv).load
            local state = load("state")
            hookfunction(skinsModule.AttemptEquip, function(self, itemName, skinName)
                local skinToEquip = skinName
                if self:IsSkinEquipped(itemName, skinName) then
                    skinToEquip = nil
                end
                state.data.equippedSkins[itemName] = skinToEquip
                load("v3item").inventory.unequipAll()
                load("v3item").inventory.skinUpdate(itemName, skinToEquip)
                self:_setEquipped(itemName, skinToEquip)
                return true
            end)
            local skins = load("skins")
            for skinName in pairs(skins.skinData) do
                for _, itemName in pairs(skins.compatabilities.Generic) do
                    state.data.ownedSkins[itemName] = state.data.ownedSkins[itemName] or {}
                    state.data.ownedSkins[itemName][skinName] = 1
                end
            end
        end
    })

    Bypass:Button({
        Title = "解锁高级表情",
        Locked = false,
        Callback = function()
            for _, v in pairs(game:GetService("Players").LocalPlayer.PlayerGui.Emotes.Frame.ScrollingFrame:GetDescendants()) do
                if v.Name == "Locked" then
                    v.Visible = false
                end
            end
        end
    })

    Bypass:Button({
        Title = "绕过火&酸伤害",
        Locked = false,
        Callback = function()
            local fire = game:GetService("ReplicatedStorage").devv.remoteStorage.fireHit
            local acid = game:GetService("ReplicatedStorage").devv.remoteStorage.acidHit
            if fire and acid then
                fire:Destroy()
                acid:Destroy()
            end
        end
    })

    local weapon = Ohio:Tab({ Title = "武器" })

    weapon:Toggle({
        Title = "静默自瞄(子弹不拐弯)",
        Default = false,
        Callback = function(state)
            silentaim = state
        end
    })

    weapon:Button({
        Title = "全枪无后座",
        Locked = false,
        Callback = function()
            for _,particle in pairs(game:GetDescendants()) do
                if particle:IsA("ParticleEmitter") then
                    particle:Destroy()
                end
            end
            game.DescendantAdded:Connect(function(descendant)
                if descendant:IsA("ParticleEmitter") then
                    descendant:Destroy()
                end
            end)
            local inv = require(game:GetService("ReplicatedStorage").devv).load("v3item").inventory.items
            for k,v in pairs(inv) do 
                if v.type == "Gun" then
                    v.recoilAdd = 0
                    v.maxRecoil = 0
                    v.recoilDiminishFactor = 0
                    v.recoilFastDiminishFactor = 0
                end 
            end
            local gunTemplates = game:GetService("ReplicatedStorage").devv.shared.Indicies.v3items.bin.Gun
            for _,gunTemplate in pairs(gunTemplates:GetChildren()) do
                if gunTemplate:IsA("ModuleScript") then
                    local template = require(gunTemplate)
                    template.recoilAdd = 0
                    template.maxRecoil = 0
                    template.recoilDiminishFactor = 0
                    template.recoilFastDiminishFactor = 0
                end
            end
        end
    })

    weapon:Button({
        Title = "全枪据点",
        Locked = false,
        Callback = function()
            local inv = require(game:GetService("ReplicatedStorage").devv).load("v3item").inventory.items
            for k,v in pairs(inv) do 
                if v.type == "Gun" then
                    v.baseSpread = 0
                    v.baseAimSpread = 0
                    v.spread = 0
                    v.aimSpread = 0
                end 
            end
            local gunTemplates = game:GetService("ReplicatedStorage").devv.shared.Indicies.v3items.bin.Gun
            for _,gunTemplate in pairs(gunTemplates:GetChildren()) do
                if gunTemplate:IsA("ModuleScript") then
                    local template = require(gunTemplate)
                    template.baseSpread = 0
                    template.baseAimSpread = 0
                end
            end
        end
    })

    weapon:Button({
        Title = "全枪射速",
        Locked = false,
        Callback = function()
            local inv = require(game:GetService("ReplicatedStorage").devv).load("v3item").inventory.items
            for k,v in pairs(inv) do 
                if v.type == "Gun" then
                    v.fireDebounce = 0
                end 
            end
            local gunTemplates = game:GetService("ReplicatedStorage").devv.shared.Indicies.v3items.bin.Gun
            for _,gunTemplate in pairs(gunTemplates:GetChildren()) do
                if gunTemplate:IsA("ModuleScript") then
                    local template = require(gunTemplate)
                    template.fireDebounce = 0
                end
            end
        end
    })

    weapon:Button({
        Title = "全枪瞬击",
        Callback = function()
            local inv = require(game.ReplicatedStorage.devv).load("v3item").inventory.items
            for k,v in pairs(inv) do 
                if v.type == "Gun" then
                    v.speedMax = 9999
                    v.speedDropoff = 0
                    v.projectileLifetime = 9999
                end 
            end
            local gunTemplates = game.ReplicatedStorage.devv.shared.Indicies.v3items.bin.Gun
            for _,v in pairs(gunTemplates:GetChildren()) do
                if v:IsA("ModuleScript") then
                    local t = require(v)
                    t.speedMax = 9999
                    t.speedDropoff = 0
                    t.projectileLifetime = 9999
                end
            end
        end
    })

    weapon:Button({
        Title = "快速换弹",
        Callback = function()
            local inv = require(game.ReplicatedStorage.devv).load("v3item").inventory.items
            for k,v in pairs(inv) do
                if v.type == "Gun" then
                    v.reloadTime = 0
                end
            end
            local gunTemplates = game.ReplicatedStorage.devv.shared.Indicies.v3items.bin.Gun
            for _,v in pairs(gunTemplates:GetChildren()) do
                if v:IsA("ModuleScript") then
                    local t = require(v)
                    t.reloadTime = 0
                end
            end
        end
    })
end
