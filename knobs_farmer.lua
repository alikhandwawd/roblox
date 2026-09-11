-- KnobsFarmer — standalone script (no mspaint required)
-- Uses logic from FarmAddon + tplays addon (DoorReachAlt, PositionOffsetAlt)

local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService    = game:GetService("TweenService")
local LP              = Players.LocalPlayer
local Camera          = workspace.CurrentCamera
local Character       = LP.Character or LP.CharacterAdded:Wait()
LP.CharacterAdded:Connect(function(c) Character = c end)

-- ── Remotes ────────────────────────────────────────────────
local RemotesFolder     = ReplicatedStorage:WaitForChild("RemotesFolder")
local GameData          = ReplicatedStorage:WaitForChild("GameData")
local CurrentRooms      = workspace:WaitForChild("CurrentRooms")
local Drops             = workspace:WaitForChild("Drops")
local LatestRoom        = GameData:WaitForChild("LatestRoom")
local Cutscene          = RemotesFolder:WaitForChild("Cutscene")
local ServerTeleported  = RemotesFolder:WaitForChild("ServerTeleported")
local Crouch            = RemotesFolder:WaitForChild("Crouch")
local PlayAgain         = RemotesFolder:WaitForChild("PlayAgain")
local ContinueOrSave    = RemotesFolder:WaitForChild("ContinueOrSave")
local RequestLocalAsset = RemotesFolder:WaitForChild("RequestLocalAsset")
local Statistics        = RemotesFolder:WaitForChild("Statistics")

-- ── State ──────────────────────────────────────────────────
local State = {
    running      = false,
    goal         = 0,         -- 0 = infinite
    startKnobs   = 0,
    currentKnobs = 0,
    connections  = {},
    cogAltConn   = nil,
    doorReachRunning = false,
}

local SAVE_FILE  = "KnobsFarmer_settings.json"
local KILL_ROOM  = 40

local AutoFloorDist = {
    RushMoving   = 120,
    AmbushMoving = 180,
    BackdoorRush = 108,
    ["A60"]      = 180,
}

-- ── Helpers ────────────────────────────────────────────────
local function SaveSettings()
    pcall(function()
        writefile(SAVE_FILE, game:GetService("HttpService"):JSONEncode({ goal = State.goal }))
    end)
end

local function LoadSettings()
    local ok, data = pcall(function()
        return game:GetService("HttpService"):JSONDecode(readfile(SAVE_FILE))
    end)
    return ok and type(data) == "table" and data or {}
end

local function GetKnobsVal()
    local ok, val = pcall(function()
        return LP.PlayerGui.TopbarUI.Topbar.StatsTopbarHandler.StatModules.Knobs.KnobsVal
    end)
    return ok and val or nil
end

local function GetEquippedTool()
    return Character and Character:FindFirstChildOfClass("Tool")
end

local function GetDropThatCanUnlock()
    for _, v in Drops:GetDescendants() do
        if v:GetAttribute("PlayerName") == LP.Name then
            if v.Name == "Lockpick" or v.Name == "SkeletonKey" or v.Name == "Multitool" then
                return v
            end
        end
    end
end

local function ItemThatCanUnlock()
    local Backpack = LP.Backpack
    local Tool = GetEquippedTool()
    return (Tool and (Tool.Name == "Lockpick" or Tool.Name == "SkeletonKey" or Tool.Name == "Multitool") and Tool)
        or GetDropThatCanUnlock()
        or Backpack:FindFirstChild("Lockpick")
        or Backpack:FindFirstChild("SkeletonKey")
        or Backpack:FindFirstChild("Multitool")
end

local function FindKeyObtain(Room)
    local key = Room:FindFirstChild("KeyObtain", true)
    if key then
        return key, key.Parent.Name == "DrawerContainer" and key.Parent
    end
    return nil, false
end

local function ActiveRusher()
    local Room     = CurrentRooms:FindFirstChild(LatestRoom.Value)
    local Door     = Room and Room:FindFirstChild("Door")
    local PrevRoom = CurrentRooms:FindFirstChild(LatestRoom.Value - 1)
    local PrevDoor = PrevRoom and PrevRoom:FindFirstChild("Door")
    for _, rusher in workspace:GetDescendants() do
        local dist = AutoFloorDist[rusher.Name]
        if dist then
            local rp = rusher:GetPivot().Position
            if (Character:GetPivot().Position - rp).Magnitude < dist
                or (Door     and (Door:GetPivot().Position     - rp).Magnitude < dist)
                or (PrevDoor and (PrevDoor:GetPivot().Position - rp).Magnitude < dist)
            then return true end
        end
    end
    return false
end

-- ── GUI ───────────────────────────────────────────────────
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder   = 999
pcall(function()
    if gethui then
        ScreenGui.Parent = gethui()
    else
        ScreenGui.Parent = game:GetService("CoreGui")
    end
end)
if not ScreenGui.Parent then ScreenGui.Parent = LP.PlayerGui end

-- main frame — right bottom corner
local Frame = Instance.new("Frame")
Frame.Parent            = ScreenGui
Frame.Size              = UDim2.new(0, 220, 0, 160)
Frame.Position          = UDim2.new(1, -228, 1, -168)
Frame.BackgroundColor3  = Color3.fromRGB(18, 18, 24)
Frame.BorderSizePixel   = 0
Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 10)

-- title bar
local TitleBar = Instance.new("Frame")
TitleBar.Parent            = Frame
TitleBar.Size              = UDim2.new(1, 0, 0, 28)
TitleBar.BackgroundColor3  = Color3.fromRGB(30, 30, 42)
TitleBar.BorderSizePixel   = 0
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 10)

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Parent               = TitleBar
TitleLabel.Size                 = UDim2.new(1, -10, 1, 0)
TitleLabel.Position             = UDim2.new(0, 10, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text                 = "🎰 Knobs Farmer"
TitleLabel.TextColor3           = Color3.fromRGB(220, 220, 255)
TitleLabel.Font                 = Enum.Font.GothamBold
TitleLabel.TextSize             = 13
TitleLabel.TextXAlignment       = Enum.TextXAlignment.Left

-- drag
do
    local dragging, dragStart, startPos
    TitleBar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging  = true
            dragStart = i.Position
            startPos  = Frame.Position
        end
    end)
    game:GetService("UserInputService").InputChanged:Connect(function(i)
        if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = i.Position - dragStart
            Frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    game:GetService("UserInputService").InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
end

-- content
local Content = Instance.new("Frame")
Content.Parent              = Frame
Content.Size                = UDim2.new(1, -16, 1, -36)
Content.Position            = UDim2.new(0, 8, 0, 32)
Content.BackgroundTransparency = 1

local Layout = Instance.new("UIListLayout")
Layout.Parent      = Content
Layout.SortOrder   = Enum.SortOrder.LayoutOrder
Layout.Padding     = UDim.new(0, 6)

local function MakeLabel(text, order)
    local lbl = Instance.new("TextLabel")
    lbl.Parent               = Content
    lbl.LayoutOrder          = order
    lbl.Size                 = UDim2.new(1, 0, 0, 16)
    lbl.BackgroundTransparency = 1
    lbl.Text                 = text
    lbl.TextColor3           = Color3.fromRGB(180, 180, 200)
    lbl.Font                 = Enum.Font.Gotham
    lbl.TextSize             = 12
    lbl.TextXAlignment       = Enum.TextXAlignment.Left
    return lbl
end

local LblCurrent = MakeLabel("Current value: —", 1)
local LblGoal    = MakeLabel("Goal: —", 2)

-- input row
local InputRow = Instance.new("Frame")
InputRow.Parent              = Content
InputRow.LayoutOrder         = 3
InputRow.Size                = UDim2.new(1, 0, 0, 26)
InputRow.BackgroundTransparency = 1

local TextBox = Instance.new("TextBox")
TextBox.Parent              = InputRow
TextBox.Size                = UDim2.new(1, -70, 1, 0)
TextBox.BackgroundColor3    = Color3.fromRGB(30, 30, 42)
TextBox.BorderSizePixel     = 0
TextBox.Text                = ""
TextBox.PlaceholderText     = "Goal knobs..."
TextBox.TextColor3          = Color3.fromRGB(220, 220, 255)
TextBox.PlaceholderColor3   = Color3.fromRGB(100, 100, 130)
TextBox.Font                = Enum.Font.Gotham
TextBox.TextSize            = 12
TextBox.ClearTextOnFocus    = false
Instance.new("UICorner", TextBox).CornerRadius = UDim.new(0, 6)

local SetBtn = Instance.new("TextButton")
SetBtn.Parent            = InputRow
SetBtn.Size              = UDim2.new(0, 60, 1, 0)
SetBtn.Position          = UDim2.new(1, -60, 0, 0)
SetBtn.BackgroundColor3  = Color3.fromRGB(60, 60, 90)
SetBtn.BorderSizePixel   = 0
SetBtn.Text              = "Set"
SetBtn.TextColor3        = Color3.fromRGB(200, 200, 255)
SetBtn.Font              = Enum.Font.GothamBold
SetBtn.TextSize          = 12
Instance.new("UICorner", SetBtn).CornerRadius = UDim.new(0, 6)

-- start/stop button
local StartBtn = Instance.new("TextButton")
StartBtn.Parent          = Content
StartBtn.LayoutOrder     = 4
StartBtn.Size            = UDim2.new(1, 0, 0, 28)
StartBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
StartBtn.BorderSizePixel = 0
StartBtn.Text            = "▶  Start Farm"
StartBtn.TextColor3      = Color3.fromRGB(255, 255, 255)
StartBtn.Font            = Enum.Font.GothamBold
StartBtn.TextSize        = 13
Instance.new("UICorner", StartBtn).CornerRadius = UDim.new(0, 6)

-- ── Label update ──────────────────────────────────────────
local function UpdateLabels()
    local kv = GetKnobsVal()
    local cur = kv and kv.Value or State.currentKnobs
    LblCurrent.Text = "Current value: " .. cur
    LblGoal.Text    = "Goal: " .. (State.goal > 0 and tostring(State.goal) or "∞")
end

-- init knobs display
task.spawn(function()
    local kv
    repeat task.wait(0.2) kv = GetKnobsVal() until kv
    State.startKnobs   = kv.Value
    State.currentKnobs = kv.Value
    UpdateLabels()
end)

-- set goal
SetBtn.MouseButton1Click:Connect(function()
    local n = tonumber(TextBox.Text)
    State.goal = (n and n > 0) and math.floor(n) or 0
    UpdateLabels()
    SaveSettings()
end)

-- ── Position Offset Alt ───────────────────────────────────
local function StartPositionOffsetAlt()
    if State.cogAltConn then return end
    pcall(function() Crouch:FireServer(true) end)
    State.cogAltConn = RunService.Heartbeat:Connect(function()
        pcall(function() Crouch:FireServer(true) end)
        local HRP = Character and Character:FindFirstChild("HumanoidRootPart")
        local CP  = Character and Character:FindFirstChild("CollisionPart")
        if not HRP or not CP then return end
        HRP.CFrame *= CFrame.new(0, -2.146, 0)
        if CP:FindFirstChild("Weld") then
            CP.Weld.C1 = CFrame.new(0, 2.146, 0)
        end
        RunService.RenderStepped:Wait()
        HRP.CFrame *= CFrame.new(0, 2.146, 0)
        if CP:FindFirstChild("Weld") then
            CP.Weld.C1 = CFrame.new(0, 0, 0)
        end
        Camera.CFrame += Vector3.new(0, 2.146, 0)
    end)
end

local function StopPositionOffsetAlt()
    if State.cogAltConn then
        State.cogAltConn:Disconnect()
        State.cogAltConn = nil
    end
    pcall(function()
        local HRP = Character and Character:FindFirstChild("HumanoidRootPart")
        if HRP then HRP.CFrame *= CFrame.new(0, 2.146, 0) end
        local CP = Character and Character:FindFirstChild("CollisionPart")
        if CP and CP:FindFirstChild("Weld") then CP.Weld.C1 = CFrame.new(0, 0, 0) end
    end)
end

-- Door Reach Alt теперь встроен в главный цикл AutoFloor
local function StopDoorReachAlt() State.doorReachRunning = false end
local function StartDoorReachAlt() State.doorReachRunning = true end

-- ── Elevator skip ─────────────────────────────────────────
local function TrySkipElevator()
    task.spawn(function()
        -- wait until room 0 and StarterElevator appear
        local attempts = 0
        while attempts < 100 do
            local room0 = CurrentRooms:FindFirstChild("0")
            if room0 then
                local prompt = room0:FindFirstChild("SkipPrompt", true)
                if prompt and prompt:IsA("ProximityPrompt") then
                    pcall(fireproximityprompt, prompt)
                    return
                end
            end
            task.wait(0.2)
            attempts += 1
        end
    end)
end

-- ── Auto Play Again + Shop Confirm ────────────────────────
local function SetupAutoPlayAgain()
    local ok, mainUI = pcall(function()
        return LP.PlayerGui:WaitForChild("MainUI", 10)
    end)
    if not ok or not mainUI then return end

    local deathPanel = mainUI:FindFirstChild("DeathPanel")
    local playBtn    = deathPanel and deathPanel:FindFirstChild("PlayAgain")
    local itemShop   = mainUI:FindFirstChild("ItemShop")
    local confirmBtn = itemShop and itemShop:FindFirstChild("Confirm")

    if playBtn then
        State.connections.playAgain = playBtn:GetPropertyChangedSignal("Visible"):Connect(function()
            if playBtn.Visible then
                task.wait(1)
                pcall(function() PlayAgain:FireServer() end)
            end
        end)
        if playBtn.Visible then
            pcall(function() PlayAgain:FireServer() end)
        end
    end

    if confirmBtn then
        State.connections.confirm = confirmBtn:GetPropertyChangedSignal("Visible"):Connect(function()
            if confirmBtn.Visible then
                pcall(function() firesignal(confirmBtn.MouseButton1Click) end)
            end
        end)
        if confirmBtn.Visible then
            pcall(function() firesignal(confirmBtn.MouseButton1Click) end)
        end
    end

    -- Statistics remote fires when round ends — fire PlayAgain immediately
    State.connections.statistics = Statistics.OnClientEvent:Connect(function()
        task.delay(0.05, function()
            pcall(function() PlayAgain:FireServer() end)
        end)
    end)
end

-- ── Seek room — kill self ─────────────────────────────────
local function KillSelf()
    pcall(function()
        if replicatesignal then
            replicatesignal(LP.Kill)
        else
            local hum = Character and Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.Health = 0 end
        end
    end)
end

-- ── Anti-TP hook ──────────────────────────────────────────
local tpFunction = nil
local function HookAntiTp()
    if not (hookfunction and getconnections) then return end
    local ok, conns = pcall(getconnections, ServerTeleported.OnClientEvent)
    local conn = ok and conns and conns[1]
    tpFunction = conn and conn.Function
    if tpFunction then
        local tp; tp = hookfunction(tpFunction, function(...)
            if checkcaller() then tp(...) end
        end)
    end
    local hook; hook = hookfunction(ServerTeleported.OnClientEvent.Connect, function(self, func)
        if not checkcaller() then
            hookfunction(func, function() end)
            tpFunction = func
        end
        return hook(self, func)
    end)
end

local function UnhookAntiTp()
    if not (isfunctionhooked and restorefunction) then return end
    pcall(function()
        if tpFunction and isfunctionhooked(tpFunction) then
            restorefunction(tpFunction)
        end
        if isfunctionhooked(ServerTeleported.OnClientEvent.Connect) then
            restorefunction(ServerTeleported.OnClientEvent.Connect)
        end
    end)
end

-- ── Main AutoFloor ────────────────────────────────────────
local function StartAutoFloor()
    local unavailableUntil = -math.huge
    local processedRoom    = -1  -- комната которую уже обработали

    State.connections.cutscene = Cutscene.OnClientEvent:Connect(function() end)

    -- Единый цикл: каждые 0.05с смотрим на состояние и действуем
    State.connections.mainLoop = RunService.Heartbeat:Connect(function()
        if os.clock() < unavailableUntil then return end
        if not Character or not Character.PrimaryPart then return end
        if Character.PrimaryPart.Anchored then return end
        if ActiveRusher() then return end

        local roomVal = LatestRoom.Value
        local Room    = CurrentRooms:FindFirstChild(roomVal)
        if not Room then return end

        -- Seek → умираем
        local rawName = Room:GetAttribute("RawName") or ""
        if rawName:lower():find("seek") then
            unavailableUntil = os.clock() + 8
            KillSelf()
            return
        end

        -- Kill room
        if roomVal >= KILL_ROOM then
            unavailableUntil = os.clock() + 3
            task.delay(0.3, KillSelf)
            return
        end

        local Door = Room:FindFirstChild("Door")
        if not Door or not Door.PrimaryPart then return end

        -- Открываем дверь сразу (Door Reach Alt встроен — без проверки дистанции)
        if not Door:FindFirstChild("Lock") then
            pcall(function() Door.ClientOpen:FireServer() end)
        end

        -- Если эту комнату уже телепортировали — не повторяем телепорт
        -- но продолжаем файрить ClientOpen пока дверь существует
        if processedRoom == roomVal then return end

        -- Комната с ключом
        if Room:GetAttribute("RequiresKey") then
            local item = ItemThatCanUnlock()
            if item then
                -- есть чем открыть
                processedRoom = roomVal
                if item:IsA("Tool") and item.Parent ~= Character then
                    item.Parent = Character
                elseif item:IsA("Model") then
                    item:PivotTo(Character:GetPivot())
                    pcall(fireproximityprompt, item.ModulePrompt)
                end
                Character:PivotTo(Door:GetPivot() * CFrame.new(0, 0, 3))
                local prompt = Door.Lock:FindFirstChild("UnlockPrompt") or Door.Lock:FindFirstChild("FakePrompt")
                if prompt then
                    task.delay(0.1, function() pcall(fireproximityprompt, prompt) end)
                end
            else
                local tool = GetEquippedTool()
                if LP.Backpack:FindFirstChild("Key") or (tool and tool.Name == "Key") then
                    processedRoom = roomVal
                    Character:PivotTo(Door:GetPivot() * CFrame.new(0, 0, 3))
                    local prompt = Door.Lock:FindFirstChild("UnlockPrompt") or Door.Lock:FindFirstChild("FakePrompt")
                    if prompt then
                        task.delay(0.1, function() pcall(fireproximityprompt, prompt) end)
                    end
                else
                    -- ищем ключ в комнате
                    local key, drawer = FindKeyObtain(Room)
                    if key then
                        processedRoom = roomVal
                        Character:PivotTo(drawer and drawer:GetPivot() or key:GetPivot())
                        if drawer then
                            task.delay(0.05, function()
                                pcall(fireproximityprompt, drawer.Knobs.ActivateEventPrompt)
                            end)
                        end
                        task.delay(0.1, function() pcall(fireproximityprompt, key.ModulePrompt) end)
                    end
                    -- ключ не найден — попробуем снова на следующем тике
                end
            end
        else
            -- обычная дверь — телепортируемся и открываем
            processedRoom = roomVal
            pcall(function() Crouch:FireServer(true, true) end)
            Character:PivotTo(Door:GetPivot() * CFrame.new(0, 0, 3))
        end
    end)
end

local function StopAutoFloor()
    for k, c in pairs(State.connections) do
        pcall(function() c:Disconnect() end)
        State.connections[k] = nil
    end
end

-- ── Knobs tracking ────────────────────────────────────────
local knobsConn = nil

local function StartKnobsTracking()
    task.spawn(function()
        local kv
        repeat task.wait(0.2) kv = GetKnobsVal() until kv
        State.startKnobs   = kv.Value
        State.currentKnobs = kv.Value
        UpdateLabels()

        knobsConn = kv.Changed:Connect(function(newVal)
            State.currentKnobs = newVal
            UpdateLabels()

            -- goal reached
            if State.goal > 0 and newVal >= State.goal then
                -- stop everything
                StartBtn:GetPropertyChangedSignal("BackgroundColor3") -- dummy to trigger stop below
                task.spawn(function()
                    if State.running then
                        State.running = false
                        StopAutoFloor()
                        StopDoorReachAlt()
                        StopPositionOffsetAlt()
                        UnhookAntiTp()
                        StartBtn.Text            = "▶  Start Farm"
                        StartBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
                        print("[KnobsFarmer] Goal reached! Stopped.")
                    end
                end)
            end
        end)
    end)
end

local function StopKnobsTracking()
    if knobsConn then
        knobsConn:Disconnect()
        knobsConn = nil
    end
end

-- ── Start / Stop ──────────────────────────────────────────
local function StartFarm()
    if State.running then return end
    State.running = true

    StartBtn.Text             = "⏹  Stop Farm"
    StartBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)

    HookAntiTp()
    StartKnobsTracking()
    StartPositionOffsetAlt()
    StartDoorReachAlt()
    SetupAutoPlayAgain()
    TrySkipElevator()
    StartAutoFloor()

    -- re-run after respawn
    LP.CharacterAdded:Connect(function(c)
        Character = c
        if not State.running then return end
        task.wait(0.5)
        StartPositionOffsetAlt()
        TrySkipElevator()
    end)

    print("[KnobsFarmer] Started. Goal:", State.goal > 0 and State.goal or "∞")
end

local function StopFarm()
    if not State.running then return end
    State.running = false

    StopAutoFloor()
    StopDoorReachAlt()
    StopPositionOffsetAlt()
    StopKnobsTracking()
    UnhookAntiTp()

    StartBtn.Text             = "▶  Start Farm"
    StartBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
    print("[KnobsFarmer] Stopped.")
end

StartBtn.MouseButton1Click:Connect(function()
    if State.running then StopFarm() else StartFarm() end
end)

-- ── Load saved settings ───────────────────────────────────
local saved = LoadSettings()
if saved.goal and saved.goal > 0 then
    State.goal = saved.goal
    TextBox.Text = tostring(saved.goal)
    UpdateLabels()
end

print("[KnobsFarmer] Loaded. Set goal and press Start Farm.")
