local OBS_REPO = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local HUB = {
    [5269058522] = {
        Name = "莱克星顿与康科德",
        Url = "https://raw.githubusercontent.com/qewwwwwww/GR-hub/main/Lc.lua",
    },
    [10050988996] = {
        Name = "scp异常站点",
        Url = "https://raw.githubusercontent.com/qewwwwwww/GR-hub/main/scp.lua",
    },
    [6756445340] = {
        Name = "亡灵前线（测试）",
        Url = "https://raw.githubusercontent.com/qewwwwwww/GR-hub/main/wlqx.lua",
    },
}
local okLib, Library = pcall(function()
    return loadstring(game:HttpGet(OBS_REPO .. "Library.lua"))()
end)
if not okLib or type(Library) ~= "table" then
    return
end
local entry = HUB[game.GameId]
if not entry then
    return
end

-- ===== ① 尺寸：固定 px，不缩放、不赌库私有接口 =====
local UIS    = game:GetService("UserInputService")
local camera = workspace.CurrentCamera
local vp     = camera.ViewportSize

local function isTouch()
    if Library.IsMobile == true then return true end
    return UIS.TouchEnabled == true
end
local landscape = vp.X >= vp.Y

local FORCE_W, FORCE_H = nil, nil

local CFG = {
    LAND_W = { k = 0.46, lo = 700, hi = 900 },
    LAND_H = { k = 0.62, lo = 380, hi = 520 },
    PORT_W = { k = 0.92, lo = 420, hi = 620 },
    PORT_H = { k = 0.55, lo = 520, hi = 760 },
    PC_W   = { k = 0.62, lo = 820, hi = 1080 },
    PC_H   = { k = 0.72, lo = 520, hi = 780 },
}
local function pick(c, base)
    return math.max(c.lo, math.min(c.hi, math.floor(base * c.k + 0.5)))
end
local wCfg, hCfg
if isTouch() then
    wCfg, hCfg = landscape and CFG.LAND_W or CFG.PORT_W,
                 landscape and CFG.LAND_H or CFG.PORT_H
else
    wCfg, hCfg = CFG.PC_W, CFG.PC_H
end
local winW = math.min(pick(wCfg, vp.X), math.floor(vp.X - 16))
local winH = math.min(pick(hCfg, vp.Y), math.floor(vp.Y - 16))
winW = FORCE_W or winW
winH = FORCE_H or winH

-- ===== ② CreateWindow：原始 5 字段 =====
local okUI, Window = pcall(function()
    return Library:CreateWindow({
        Title = "GR hub  ·  v2.0",
        Footer = "GR hub  ·  " .. entry.Name .. "  ·  Obsidian",
        Center = true,
        AutoShow = true,
        Size = UDim2.new(0, winW, 0, winH),
    })
end)
if not okUI or type(Window) ~= "table" then
    return
end

-- ===== 以下原样 =====
local genv = (type(getgenv) == "function") and getgenv() or _G
local G = genv and genv.GRHub
if type(G) ~= "table" then
    G = {}
    if type(genv) == "table" then genv.GRHub = G end
end
G.Library = Library
G.Window = Window
G.GameId = game.GameId
G.GameName = entry.Name
G.Version = "2.0"
if type(G.Modules) ~= "table" then G.Modules = {} end
if type(G.Tabs) ~= "table" then G.Tabs = {} end
G.Notify = function(text, dur)
    pcall(function() Library:Notify(tostring(text), dur or 4) end)
end
G.RegisterModule = function(name, data)
    if type(name) == "string" and type(data) == "table" then G.Modules[name] = data end
end
G.RegisterTab = function(name, tab)
    if type(name) == "string" and tab then G.Tabs[name] = tab end
end
G.GetModule = function(name)
    if type(G.Modules) == "table" then return G.Modules[name] end
end
G.UnloadAll = function()
    if type(G.Modules) == "table" then
        for _, m in pairs(G.Modules) do
            if type(m) == "table" and type(m.Unload) == "function" then pcall(m.Unload) end
        end
    end
    if G.StatusGui then
        pcall(G.StatusGui.Destroy, G.StatusGui)
        G.StatusGui = nil
    end
end
local function getPingMs()
    local ok, v = pcall(function()
        local lp = game:GetService("Players").LocalPlayer
        if lp and type(lp.GetNetworkPing) == "function" then
            local s = lp:GetNetworkPing()
            if type(s) == "number" and s >= 0 then
                return math.floor(s * 1000 + 0.5)
            end
        end
        local stats = game:GetService("Stats")
        local net = stats and stats:FindFirstChild("Network")
        local ssi = net and net:FindFirstChild("ServerStatsItem")
        local item = ssi and ssi:FindFirstChild("Data Ping")
        if item then
            local n = tonumber(string.match(tostring(item.Value), "%d+%.?%d*"))
            if n then return math.floor(n + 0.5) end
        end
        return nil
    end)
    if ok and type(v) == "number" then return v end
    return nil
end

-- ===== ③ 配色：只赋值已有表键 =====
local function applyColors()
    local pal = {
        BackgroundColor = Color3.fromRGB(14, 16, 24),
        MainColor       = Color3.fromRGB(22, 25, 36),
        AccentColor     = Color3.fromRGB(88, 101, 242),
        OutlineColor    = Color3.fromRGB(52, 60, 92),
        FontColor       = Color3.fromRGB(232, 236, 255),
    }
    pcall(function()
        for _, h in ipairs({ Library.Scheme, Library.Theme, Library.Colors, Library.CurrentTheme }) do
            if type(h) == "table" then
                for k, v in pairs(pal) do
                    if h[k] ~= nil then pcall(function() h[k] = v end) end
                end
            end
        end
    end)
    pcall(function() Library:UpdateColorsUsingRegistry() end)
    pcall(function() if Library.KeybindFrame then Library.KeybindFrame.Visible = false end end)
end

local holders = {}
local function addHolder(h)
    if not h then return end
    for _, x in ipairs(holders) do if x == h then return end end
    holders[#holders + 1] = h
end
pcall(function() if typeof(gethui) == "function" then addHolder(gethui()) end end)
pcall(function() addHolder(game:GetService("CoreGui")) end)
pcall(function()
    local pg = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
    addHolder(pg)
end)

local function applySkin()
    pcall(applyColors)
    pcall(function()
        if type(Library.SetCustomTheme) == "function" then
            Library:SetCustomTheme("GRhub", Color3.fromRGB(88, 101, 242))
        end
    end)
    pcall(function()
        if type(Library.SetTheme) == "function" then
            Library:SetTheme("GRhub")
        end
    end)
    pcall(function()
        if Library.KeybindFrame then
            Library.KeybindFrame.Visible = false
        end
    end)
    pcall(function()
        if G.StatusGui then return end
        local holder = holders[1]
        if not holder then return end
        local sg = Instance.new("ScreenGui")
        sg.Name = "GRHub_Status"
        sg.ResetOnSpawn = false
        sg.IgnoreGuiInset = true
        sg.DisplayOrder = 999999
        sg.Parent = holder

        local barW, barH = 300, 30
        local bar = Instance.new("Frame", sg)
        bar.Name = "Bar"
        bar.Size = UDim2.fromOffset(barW, barH)
        bar.AnchorPoint = Vector2.new(1, 0)
        bar.Position = UDim2.new(1, -14, 0, 14)
        bar.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
        bar.BackgroundTransparency = 0.2
        bar.BorderSizePixel = 0
        local corner = Instance.new("UICorner", bar)
        corner.CornerRadius = UDim.new(0, 10)
        local stroke = Instance.new("UIStroke", bar)
        stroke.Color = Color3.fromRGB(88, 101, 242)
        stroke.Thickness = 1.5
        stroke.Transparency = 0.35
        local txt = Instance.new("TextLabel", bar)
        txt.Size = UDim2.new(1, -24, 1, 0)
        txt.Position = UDim2.new(0, 12, 0, 0)
        txt.BackgroundTransparency = 1
        local okFont, fontVal = pcall(function() return Enum.Font.GothamBold end)
        txt.Font = (okFont and fontVal) or Enum.Font.SourceSansBold
        txt.TextSize = 12
        txt.TextColor3 = Color3.fromRGB(220, 224, 255)
        txt.TextXAlignment = Enum.TextXAlignment.Left
        txt.TextTruncate = Enum.TextTruncate.AtEnd
        txt.Text = "GR hub  ·  " .. entry.Name .. "  ·  — ms"
        G.StatusGui = sg
        local RunService = game:GetService("RunService")
        local frames, last = 0, os.clock()
        local conn
        conn = RunService.Heartbeat:Connect(function()
            frames = frames + 1
            local now = os.clock()
            if now - last >= 0.5 then
                local fps = math.floor(frames / (now - last) + 0.5)
                frames = 0
                last = now
                pcall(function()
                    local ping = getPingMs()
                    txt.Text = "GR hub  ·  " .. entry.Name .. "  ·  " .. tostring(fps) .. " FPS  ·  "
                        .. (ping and (tostring(ping) .. " ms") or "— ms")
                end)
            end
            if not sg.Parent then
                pcall(conn.Disconnect, conn)
            end
        end)
    end)
end

print("[GR hub] 尺寸 · " .. winW .. "x" .. winH
    .. " · " .. (isTouch() and "触屏" or "键鼠")
    .. " · " .. (landscape and "横屏" or "竖屏") .. " · 1:1 不缩放")

-- ===== ④ 以下原样：就绪提示 =====
G.Notify("GR hub  ·  UI 已就绪", 3)
Library:Notify("已加载（" .. entry.Name .. "）", 4)

-- 皮肤/状态条先挂上，后台重试期间界面可用
applySkin()

if entry.Url == nil or entry.Url == "" then
    return
end

-- ===== ⑤ 后台无限重试，直到「下载 + 编译」成功 =====
local RETRY = {
    MIN       = 2,     -- 起始退避秒
    MAX       = 8,     -- 退避上限
    BUST      = true,  -- 加 ?t= 防 CDN 脏缓存
    LOG_EVERY = 3,     -- 每 N 次打一次控制台，防刷屏
}

local function fetch(url)
    local ok, src = pcall(function() return game:HttpGet(url) end)
    if ok and type(src) == "string" and #src > 0 then return src end
    local req = (typeof(syn) == "table" and syn.request)
        or (typeof(request) == "function" and request)
        or (typeof(http_request) == "function" and http_request)
    if req then
        local o2, res = pcall(function()
            return req({ Url = url, Method = "GET", Headers = { ["User-Agent"] = "Roblox/WinInet" } })
        end)
        if o2 and type(res) == "table" then
            local body = res.Body or res.body
            if type(body) == "string" and #body > 0 then return body end
        end
    end
    return nil
end

-- 只判「网关页/404 页」特征，不再全文搜 "404"
-- 否则子模块正文里带个 404 数字就会永远重试
local function isBad(src)
    if type(src) ~= "string" or #src == 0 then return true end
    local head = src:sub(1, 96)
    if head:find("404: Not Found", 1, true) then return true end
    if head:find("Not Found", 1, true) and #src < 512 then return true end
    if head:find("Request denied", 1, true) then return true end
    if head:find("<!DOCTYPE", 1, true) or head:find("<html", 1, true) then return true end
    if head:find('"status":403', 1, true) then return true end
    return false
end

-- errContext 原样保留
local srcLines = {}
local function errContext(msg)
    local ln = tonumber(string.match(tostring(msg), ":(%d+):"))
    if not ln then return "（无行号）" end
    local out = "报错行 " .. tostring(ln) .. " / 共 " .. tostring(#srcLines) .. " 行"
    for i = ln - 2, ln + 2 do
        if srcLines[i] then
            local t = string.gsub(srcLines[i], "^%s+", "")
            if #t > 55 then t = string.sub(t, 1, 55) end
            out = out .. "\n" .. tostring(i) .. "| " .. t
        end
    end
    return out
end

-- 防重复：模块已挂载 / 已有循环在跑，就不再叠第二个
if type(G.Modules) == "table" and G.Modules[entry.Name] ~= nil then
    G.Notify(entry.Name .. "  ·  模块已在，跳过重试", 3)
    return
end
if G.LoaderRunning then
    return
end
G.LoaderRunning = true

G.Notify("正在加载 " .. entry.Name .. " · 后台自动重试中", 4)

task.spawn(function()
    local attempt, waitS = 0, RETRY.MIN
    while true do
        attempt = attempt + 1
        local url = entry.Url
        if RETRY.BUST then
            url = url .. (url:find("?", 1, true) and "&" or "?")
                .. "t=" .. tostring(os.time()) .. "_" .. tostring(attempt)
        end

        local src = fetch(url)
        if src and not isBad(src) then
            local fn, compileErr = loadstring(src)
            if type(fn) == "function" then
                srcLines = {}
                for line in string.gmatch(src, "[^\r\n]+") do
                    srcLines[#srcLines + 1] = line
                end

                local okRun, err = pcall(function()
                    local mod = fn()
                    if type(mod) == "function" then
                        local res = mod(Library, Window, G)
                        local info = { Name = entry.Name, Url = entry.Url, Window = Window, Library = Library }
                        if type(res) == "table" then
                            for k, v in pairs(res) do info[k] = v end
                        end
                        G.Modules[entry.Name] = info
                        G.Current = info
                    else
                        G.Modules[entry.Name] = { Name = entry.Name, Url = entry.Url, Window = Window, Library = Library }
                    end
                end)

                G.LoaderRunning = false
                if not okRun then
                    Library:Notify("GR功能运行报错\n" .. tostring(err) .. "\n" .. errContext(err), 12)
                else
                    local tabCount = 0
                    for _ in pairs(G.Tabs) do tabCount = tabCount + 1 end
                    G.Notify(entry.Name .. "  ·  模块已挂载"
                        .. (tabCount > 0 and ("  ·  " .. tostring(tabCount) .. " 个功能页") or ""), 5)
                end
                print("[GR hub] 加载成功 · 第 " .. tostring(attempt) .. " 次尝试")
                return
            else
                if attempt <= RETRY.LOG_EVERY or attempt % RETRY.LOG_EVERY == 0 then
                    warn("[GR hub] 第 " .. tostring(attempt) .. " 次：编译失败 " .. tostring(compileErr))
                end
            end
        else
            if attempt <= RETRY.LOG_EVERY or attempt % RETRY.LOG_EVERY == 0 then
                warn("[GR hub] 第 " .. tostring(attempt) .. " 次：下载失败/空内容，继续后台重试")
            end
        end

        waitS = math.min(RETRY.MAX, waitS + 1)
        task.wait(waitS)
    end
end)
