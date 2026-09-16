-- Vexon Steal Bar HUD
-- Estilo: pill escuro, foto de perfil, barra roxa, FPS/PING texto normal
-- Funcao de steal: Adapt (oz.v8) integrada

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local UIS          = game:GetService("UserInputService")
local Stats        = game:GetService("Stats")
local TweenService = game:GetService("TweenService")
local CoreGui      = game:GetService("CoreGui")
local LP           = Players.LocalPlayer

local getconnections = getconnections or (getgenv and getgenv().getconnections)

-- ──────────────────────────────
-- STEAL STATE (exposto via getgenv para o VexonMenu sincronizar)
-- ──────────────────────────────
local Steal = {
    AutoStealEnabled = true,
    StealRadius      = 60,
    StealDuration    = 1.3,
    Mode             = 4,
    Data             = {},
}

-- expoe o state para o VexonMenu atualizar em tempo real
pcall(function()
    if getgenv then
        getgenv()._VexonSteal = Steal
    end
end)

local STEAL_MODE_CFG = {
    [1] = { threshold = 0.90, nearDist = 14 },
    [2] = { threshold = 0.85, nearDist = 12 },
    [3] = { threshold = 0.80, nearDist = 11 },
    [4] = { threshold = 0.75, nearDist = 10 },
}

local isStealing = false
local stealConn  = nil

-- refs para a barra (preenchidas depois da UI)
local progressFill

local function setBar(p)
    p = math.clamp(p or 0, 0, 1)
    if progressFill and progressFill.Parent then
        TweenService:Create(progressFill,
            TweenInfo.new(0.1, Enum.EasingStyle.Linear),
            {Size = UDim2.new(p, 0, 1, 0)}
        ):Play()
    end
end

-- ──────────────────────────────
-- STEAL LOGIC (Adapt oz.v8)
-- ──────────────────────────────
local function getStealHRP()
    local c = LP.Character
    return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("UpperTorso"))
end

local function isMyPlotByName(plotName)
    local plots = workspace:FindFirstChild("Plots")
    local plot = plots and plots:FindFirstChild(plotName)
    if not plot then return false end
    local sign = plot:FindFirstChild("PlotSign")
    local yb = sign and sign:FindFirstChild("YourBase")
    return yb and yb:IsA("BillboardGui") and yb.Enabled
end

local function getPromptPosition(prompt)
    if not prompt then return nil end
    local p = prompt.Parent
    while p and p ~= workspace do
        if p:IsA("BasePart") then return p.Position end
        p = p.Parent
    end
    return nil
end

local function findNearestPrompt()
    local hrp = getStealHRP()
    if not hrp then return nil end
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    local nearest, dist = nil, math.huge
    for _, plot in ipairs(plots:GetChildren()) do
        if isMyPlotByName(plot.Name) then continue end
        local pods = plot:FindFirstChild("AnimalPodiums")
        if not pods then continue end
        for _, pod in ipairs(pods:GetChildren()) do
            local base = pod:FindFirstChild("Base")
            if not base then continue end
            local spawn = base:FindFirstChild("Spawn")
            if not spawn then continue end
            local d = (spawn.Position - hrp.Position).Magnitude
            if d <= Steal.StealRadius and d < dist then
                local att = spawn:FindFirstChild("PromptAttachment")
                if att then
                    for _, pr in ipairs(att:GetChildren()) do
                        if pr:IsA("ProximityPrompt") and pr.ActionText and pr.ActionText:find("Steal") then
                            nearest, dist = pr, d
                        end
                    end
                end
            end
        end
    end
    return nearest
end

local function executeSteal(prompt)
    if isStealing or not Steal.AutoStealEnabled then return end
    if not Steal.Data[prompt] then
        Steal.Data[prompt] = { hold = {}, trigger = {}, ready = true }
        if getconnections then
            for _, c in ipairs(getconnections(prompt.PromptButtonHoldBegan) or {}) do
                if c.Function then table.insert(Steal.Data[prompt].hold, c.Function) end
            end
            for _, c in ipairs(getconnections(prompt.Triggered) or {}) do
                if c.Function then table.insert(Steal.Data[prompt].trigger, c.Function) end
            end
        end
    end
    local data = Steal.Data[prompt]
    if not data.ready then return end
    data.ready  = false
    isStealing  = true
    task.spawn(function()
        for _, f in ipairs(data.hold) do pcall(f) end
    end)
    local cfg            = STEAL_MODE_CFG[Steal.Mode] or STEAL_MODE_CFG[4]
    local threshold      = cfg.threshold
    local nearDist       = cfg.nearDist
    local totalTime      = tonumber(Steal.StealDuration) or 1.3
    local timeToThreshold = totalTime * threshold
    local timeAfterThreshold = totalTime - timeToThreshold
    local startTime      = tick()
    -- fase 1: carrega ate o threshold
    while tick() - startTime < timeToThreshold do
        if not Steal.AutoStealEnabled then
            isStealing = false; data.ready = true; setBar(0); return
        end
        setBar(math.clamp((tick() - startTime) / totalTime, 0, threshold))
        task.wait()
    end
    setBar(threshold)
    -- fase 2: espera estar perto (max 4s)
    local stillNear = false
    local hrp = getStealHRP()
    if hrp then
        local tp = getPromptPosition(prompt)
        if tp and (tp - hrp.Position).Magnitude <= nearDist then stillNear = true end
    end
    if not stillNear then
        local holdStart = tick()
        while tick() - holdStart < 4 do
            if not Steal.AutoStealEnabled then
                isStealing = false; data.ready = true; setBar(0); return
            end
            setBar(threshold)
            local hrp2 = getStealHRP()
            if hrp2 then
                local tp = getPromptPosition(prompt)
                if tp and (tp - hrp2.Position).Magnitude <= nearDist then
                    stillNear = true; break
                end
            end
            task.wait()
        end
        if not stillNear then
            isStealing = false; data.ready = true; setBar(0); return
        end
    end
    -- fase 3: finaliza e dispara
    local resumeTime = tick()
    while tick() - resumeTime < timeAfterThreshold do
        if not Steal.AutoStealEnabled then
            isStealing = false; data.ready = true; setBar(0); return
        end
        local fin = (tick() - resumeTime) / math.max(timeAfterThreshold, 0.01)
        setBar(threshold + fin * (1 - threshold))
        task.wait()
    end
    setBar(1)
    for _, f in ipairs(data.trigger) do pcall(f) end
    task.wait(0.05)
    data.ready = true
    isStealing = false
    setBar(0)
end

local function startAutoSteal()
    if stealConn then return end
    stealConn = RunService.Heartbeat:Connect(function()
        if isStealing or not Steal.AutoStealEnabled then return end
        local ok, prompt = pcall(findNearestPrompt)
        if ok and prompt then pcall(executeSteal, prompt) end
    end)
end

-- ──────────────────────────────
-- CLEANUP
-- ──────────────────────────────
pcall(function()
    local old = CoreGui:FindFirstChild("VexonStealHUD")
    if old then old:Destroy() end
end)

-- ──────────────────────────────
-- GUI
-- ──────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name           = "VexonStealHUD"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 60
gui.Parent         = CoreGui

-- ── PILL PRINCIPAL ──
local PILL_W = 340
local PILL_H = 52

local pill = Instance.new("Frame")
pill.Name             = "Pill"
pill.Size             = UDim2.fromOffset(PILL_W, PILL_H)
pill.Position         = UDim2.new(0.5, -PILL_W/2, 1, -(PILL_H + 12))
pill.BackgroundColor3 = Color3.fromRGB(8, 4, 16)
pill.BorderSizePixel  = 0
pill.Active           = true
pill.Parent           = gui

local pillCorner = Instance.new("UICorner")
pillCorner.CornerRadius = UDim.new(1, 0)
pillCorner.Parent = pill

local pillStroke = Instance.new("UIStroke")
pillStroke.Color     = Color3.fromRGB(106, 13, 173)
pillStroke.Thickness = 1.8
pillStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
pillStroke.Parent = pill

task.spawn(function()
    while pillStroke and pillStroke.Parent do
        TweenService:Create(pillStroke,
            TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
            {Color = Color3.fromRGB(191, 95, 255)}):Play()
        task.wait(1.6)
        TweenService:Create(pillStroke,
            TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
            {Color = Color3.fromRGB(106, 13, 173)}):Play()
        task.wait(1.6)
    end
end)

-- ── FOTO DE PERFIL ──
local avatarSz = 36
local avatarFrame = Instance.new("Frame")
avatarFrame.Size             = UDim2.fromOffset(avatarSz, avatarSz)
avatarFrame.Position         = UDim2.fromOffset(8, (PILL_H - avatarSz) / 2)
avatarFrame.BackgroundColor3 = Color3.fromRGB(20, 10, 36)
avatarFrame.BorderSizePixel  = 0
avatarFrame.ZIndex           = 2
avatarFrame.Parent           = pill

local avatarCorner = Instance.new("UICorner")
avatarCorner.CornerRadius = UDim.new(1, 0)
avatarCorner.Parent = avatarFrame

local avatarStroke = Instance.new("UIStroke")
avatarStroke.Color     = Color3.fromRGB(191, 95, 255)
avatarStroke.Thickness = 1.4
avatarStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
avatarStroke.Parent = avatarFrame

local avatarImg = Instance.new("ImageLabel")
avatarImg.Size                  = UDim2.fromScale(1, 1)
avatarImg.BackgroundTransparency = 1
avatarImg.Image                 = ""
avatarImg.ScaleType             = Enum.ScaleType.Crop
avatarImg.ZIndex                = 3
avatarImg.Parent                = avatarFrame

local avatarImgCorner = Instance.new("UICorner")
avatarImgCorner.CornerRadius = UDim.new(1, 0)
avatarImgCorner.Parent = avatarImg

task.spawn(function()
    local ok, url = pcall(function()
        return Players:GetUserThumbnailAsync(
            LP.UserId,
            Enum.ThumbnailType.HeadShot,
            Enum.ThumbnailSize.Size150x150
        )
    end)
    if ok and url then
        avatarImg.Image = url
    end
end)

-- ── LABEL "STEAL" ──
local stealLbl = Instance.new("TextLabel")
stealLbl.Position               = UDim2.fromOffset(avatarSz + 14, 10)
stealLbl.Size                   = UDim2.fromOffset(52, 16)
stealLbl.BackgroundTransparency = 1
stealLbl.Text                   = "STEAL"
stealLbl.Font                   = Enum.Font.GothamBlack
stealLbl.TextSize               = 12
stealLbl.TextColor3             = Color3.fromRGB(218, 160, 255)
stealLbl.TextXAlignment         = Enum.TextXAlignment.Left
stealLbl.ZIndex                 = 2
stealLbl.Parent                 = pill

-- ── BARRA DE PROGRESSO ──
local barX = avatarSz + 14
local barW = PILL_W - barX - 140 - 12
local barH = 6
local barY = PILL_H - barH - 10

local barTrack = Instance.new("Frame")
barTrack.Position         = UDim2.fromOffset(barX, barY)
barTrack.Size             = UDim2.fromOffset(barW, barH)
barTrack.BackgroundColor3 = Color3.fromRGB(30, 14, 52)
barTrack.BorderSizePixel  = 0
barTrack.ClipsDescendants = true
barTrack.ZIndex           = 2
barTrack.Parent           = pill

local barTrackCorner = Instance.new("UICorner")
barTrackCorner.CornerRadius = UDim.new(1, 0)
barTrackCorner.Parent = barTrack

local barFill = Instance.new("Frame")
barFill.Size             = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(191, 95, 255)
barFill.BorderSizePixel  = 0
barFill.ZIndex           = 3
barFill.Parent           = barTrack
progressFill = barFill

local barFillCorner = Instance.new("UICorner")
barFillCorner.CornerRadius = UDim.new(1, 0)
barFillCorner.Parent = barFill

local barGrad = Instance.new("UIGradient")
barGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0,   Color3.fromRGB(106, 13, 173)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(191, 95, 255)),
    ColorSequenceKeypoint.new(1,   Color3.fromRGB(218, 160, 255)),
})
barGrad.Parent = barFill

-- ── FPS / PING ──
local fpsLbl = Instance.new("TextLabel")
fpsLbl.Position               = UDim2.new(1, -138, 0, 8)
fpsLbl.Size                   = UDim2.fromOffset(60, 16)
fpsLbl.BackgroundTransparency = 1
fpsLbl.Text                   = "FPS: 0"
fpsLbl.Font                   = Enum.Font.GothamBold
fpsLbl.TextSize               = 11
fpsLbl.TextColor3             = Color3.fromRGB(200, 180, 230)
fpsLbl.TextXAlignment         = Enum.TextXAlignment.Right
fpsLbl.ZIndex                 = 2
fpsLbl.Parent                 = pill

local pingLbl = Instance.new("TextLabel")
pingLbl.Position               = UDim2.new(1, -72, 0, 8)
pingLbl.Size                   = UDim2.fromOffset(60, 16)
pingLbl.BackgroundTransparency = 1
pingLbl.Text                   = "PING: 0ms"
pingLbl.Font                   = Enum.Font.GothamBold
pingLbl.TextSize               = 11
pingLbl.TextColor3             = Color3.fromRGB(200, 180, 230)
pingLbl.TextXAlignment         = Enum.TextXAlignment.Right
pingLbl.ZIndex                 = 2
pingLbl.Parent                 = pill

-- ── DRAG ──
do
    local dragging, dragStart, startPos
    pill.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging  = true
            dragStart = i.Position
            startPos  = pill.Position
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if not dragging then return end
        if i.UserInputType == Enum.UserInputType.MouseMovement
        or i.UserInputType == Enum.UserInputType.Touch then
            local d = i.Position - dragStart
            pill.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

-- ── FPS/PING UPDATER ──
task.spawn(function()
    local fpsCount = 0
    local fpsConn = RunService.RenderStepped:Connect(function() fpsCount += 1 end)
    while pill and pill.Parent do
        task.wait(1)
        local ping = 0
        pcall(function()
            ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
        end)
        if fpsLbl and fpsLbl.Parent then
            fpsLbl.Text  = "FPS: " .. fpsCount
        end
        if pingLbl and pingLbl.Parent then
            pingLbl.Text = "PING: " .. ping .. "ms"
        end
        fpsCount = 0
    end
    pcall(function() fpsConn:Disconnect() end)
end)

-- ── KEYBIND: LCtrl toggle steal ──
UIS.InputBegan:Connect(function(i, gameHandled)
    if gameHandled then return end
    if i.KeyCode == Enum.KeyCode.LeftControl then
        Steal.AutoStealEnabled = not Steal.AutoStealEnabled
        if not Steal.AutoStealEnabled then setBar(0) end
    end
end)

-- ── START ──
startAutoSteal()

print("[Vexon StealBar] carregado")
