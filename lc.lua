-- 踢出自己（自定义踢出文本）
-- 放到 LocalScript 里（StarterPlayerScripts）

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- 自定义踢出文本
local kickMessage = "我注入器废了，脚本先死一下😭"

-- 执行踢出
LocalPlayer:Kick(kickMessage)

print("✅ 已发送踢出请求")
