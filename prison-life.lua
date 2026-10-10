-- PrisonHub v2.9 | WindUI | Cuộc Sống Trong Nhà Tù
-- Refactored & Fully Populated Tabs

local CONFIG = {
    Title = "PrisonHub", Author = "vxmpingz_", Folder = "PrisonHub",
    ExpectedPlaceId = 155615604, StatsInterval = 1, KillLogSize = 50, KillLogShown = 12,
    RosterNamesPerTeam = 8, DefaultFOV = 70, KillAuraRange = 20, KillAuraInterval = 0.15,
    PickupSettle = 0.4, InvisDepth = 75, InvisTransparency = 0.5, TaseWindow = 10,
    TeamStepWait = 1.5, TeamAttemptWait = 2.5, TeamAttempts = 5,
    AimlockRange = 300, AimlockSmoothing = 0.18,
    AutoShootInterval = 0.12, AutoShootRange = 80,
    AutoInvisHP = 35,
    WindUIUrl = "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua",
}

if getgenv and getgenv().PrisonHubUnload then pcall(getgenv().PrisonHubUnload) end

local Players        = game:GetService("Players")
local Teams          = game:GetService("Teams")
local RunService     = game:GetService("RunService")
local Lighting       = game:GetService("Lighting")
local Stats          = game:GetService("Stats")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser    = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera
local startTime   = os.clock()

local connections, killLog, espObjects = {}, {}, {}
local running = true
local originals = { lighting=nil, fov=Camera and Camera.FieldOfView or CONFIG.DefaultFOV, zoom=LocalPlayer.CameraMaxZoomDistance }
local state = {
    godMode=false, invisible=false, fly=false, noclip=false, killAura=false, esp=false, espNames=false,
    antiTaser=false, aimlock=false, fovCircle=false, autoShoot=false, autoShootTrespassing=false, autoInvis=false
}
local flyBV, flyBG, flyConn, noclipConn, killAuraConn, godModeConn, invisConn
local autoShootConn, aimlockConn, autoInvisConn
local hoverTargetY
local setInvisible
local flySpeed = 50

local meleeEvent   = ReplicatedStorage:FindFirstChild("meleeEvent")
local Remotes      = ReplicatedStorage:FindFirstChild("Remotes")
local GunRemotes   = ReplicatedStorage:FindFirstChild("GunRemotes")
local pickupRemote = Remotes and Remotes:FindFirstChild("InteractWithItem")
local giverRemote  = Remotes and Remotes:FindFirstChild("GiverPressed")
local teamRemote   = Remotes and Remotes:FindFirstChild("RequestTeamChange")
local taseRemote   = GunRemotes and GunRemotes:FindFirstChild("PlayerTased")
local shootEvent   = GunRemotes and GunRemotes:FindFirstChild("ShootEvent")

local function log(level, msg) print(string.format("[PrisonHub][%s] %s", level, tostring(msg))) end
local function safe(label, fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then log("ERROR", label .. ": " .. tostring(result)) return nil end
    return result
end
local function track(conn) connections[#connections+1] = conn return conn end

local WindUI = safe("load WindUI", function() return loadstring(game:HttpGet(CONFIG.WindUIUrl))() end)
if not WindUI then warn("[PrisonHub] WindUI failed to load.") return end
local function notify(title, content)
    safe("notify", function() WindUI:Notify({ Title=title, Content=content, Duration=4 }) end)
end

local Window      = WindUI:CreateWindow({ Title=CONFIG.Title, Author=CONFIG.Author, Folder=CONFIG.Folder, Size=UDim2.fromOffset(620,500), Theme="Dark", Transparent=true })
local OverviewTab = Window:Tab({ Title="Overview",  Icon="activity" })
local CombatTab   = Window:Tab({ Title="Combat",    Icon="sword" })
local AimTab      = Window:Tab({ Title="Aimlock",   Icon="crosshair" })
local MovementTab = Window:Tab({ Title="Movement",  Icon="zap" })
local TeleportTab = Window:Tab({ Title="Teleport",  Icon="map-pin" })
local PickupTab   = Window:Tab({ Title="Pickups",   Icon="package" })
local TeamSwapTab = Window:Tab({ Title="Team Swap", Icon="refresh-cw" })
local ESPTab      = Window:Tab({ Title="ESP",       Icon="eye" })
local KillsTab    = Window:Tab({ Title="Kill Log",  Icon="skull" })
local TeamsTab    = Window:Tab({ Title="Teams",     Icon="users" })
local UtilTab     = Window:Tab({ Title="Utility",   Icon="wrench" })
local SettingsTab = Window:Tab({ Title="Settings",  Icon="settings" })

local API = {
    Window=Window, WindUI=WindUI, CONFIG=CONFIG, state=state, notify=notify, track=track, safe=safe, log=log,
    Tabs={ Overview=OverviewTab, Combat=CombatTab, Aim=AimTab, Movement=MovementTab, Teleport=TeleportTab,
           Pickups=PickupTab, TeamSwap=TeamSwapTab, ESP=ESPTab, Kills=KillsTab, Teams=TeamsTab, Utility=UtilTab, Settings=SettingsTab }
}
if getgenv then getgenv().PrisonHubAPI = API end

-- ===== OVERVIEW =====
local overview = OverviewTab:Paragraph({ Title="Server Info", Desc="Collecting statistics..." })
local frames, acc, fps = 0, 0, 0
track(RunService.RenderStepped:Connect(function(dt)
    frames += 1; acc += dt
    if acc >= 1 then fps = math.floor(frames/acc+0.5); frames, acc = 0, 0 end
end))

local function getPing()
    local net = Stats:FindFirstChild("Network")
    local item = net and net:FindFirstChild("ServerStatsItem")
    local dp = item and item:FindFirstChild("Data Ping")
    return dp and math.floor(dp:GetValue()) or -1
end

local function fmtTime(s) return string.format("%02d:%02d:%02d", s//3600, (s%3600)//60, s%60) end

OverviewTab:Button({ Title="Copy Job ID", Callback=function()
    if setclipboard then safe("copy", setclipboard, game.JobId); notify("Copied", game.JobId) else notify("Unsupported","setclipboard unavailable") end
end })

OverviewTab:Button({ Title="Reset Character", Desc="Kills your character and respawns", Callback=function()
    safe("reset", function()
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.Health = 0 end
    end)
end })

-- ===== HOSTILE DETECTION =====
local GUARD_ZONE = { xMin=650, xMax=900, zMin=2250, zMax=2380 }

local function isInGuardZone(char)
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local p = hrp.Position
    return p.X > GUARD_ZONE.xMin and p.X < GUARD_ZONE.xMax and p.Z > GUARD_ZONE.zMin and p.Z < GUARD_ZONE.zMax
end

local function isHostileToMe(p)
    local myTeam = LocalPlayer.Team and LocalPlayer.Team.Name
    local theirTeam = p.Team and p.Team.Name
    if not myTeam or not theirTeam then return false end
    if myTeam == "Guards" then
        return theirTeam == "Criminals" or theirTeam == "Inmates"
    elseif myTeam == "Criminals" then
        return theirTeam == "Guards"
    elseif myTeam == "Inmates" then
        return theirTeam == "Guards" or theirTeam == "Criminals"
    end
    return false
end

local function isTrespassingInmate(p)
    return p.Team and p.Team.Name == "Inmates" and p.Character and isInGuardZone(p.Character)
end

local function shouldAutoShoot(p)
    if p == LocalPlayer then return false end
    if not p.Character then return false end
    local hum = p.Character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    if isHostileToMe(p) then return true end
    if state.autoShootTrespassing and isTrespassingInmate(p) then return true end
    return false
end

-- ===== COMBAT =====
CombatTab:Toggle({ Title="God Mode", Desc="Keeps health at max every frame", Default=false, Callback=function(v)
    state.godMode = v
    if godModeConn then godModeConn:Disconnect(); godModeConn = nil end
    if v then
        godModeConn = track(RunService.Heartbeat:Connect(function()
            local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 and hum.Health < hum.MaxHealth then hum.Health = hum.MaxHealth end
        end))
    end
end })

CombatTab:Toggle({ Title="Kill Aura", Desc="Auto melee on players in range (meleeEvent)", Default=false, Callback=function(v)
    state.killAura = v
    if killAuraConn then killAuraConn:Disconnect(); killAuraConn = nil end
    if not v then return end
    if not meleeEvent then notify("Kill Aura","meleeEvent not found") return end
    local last = 0
    killAuraConn = track(RunService.Heartbeat:Connect(function()
        if os.clock() - last < CONFIG.KillAuraInterval then return end
        last = os.clock()
        local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not myHRP then return end
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                local hum = p.Character:FindFirstChildOfClass("Humanoid")
                if hrp and hum and hum.Health > 0 and (hrp.Position - myHRP.Position).Magnitude <= CONFIG.KillAuraRange then
                    safe("killaura", function() meleeEvent:FireServer(p, "Hammer") end)
                end
            end
        end
    end))
end })

CombatTab:Slider({ Title="Kill Aura Range", Step=1, Value={ Min=5, Max=60, Default=CONFIG.KillAuraRange }, Callback=function(v) CONFIG.KillAuraRange = v end })

-- ===== AUTO SHOOT =====
CombatTab:Paragraph({ Title="Auto Shoot", Desc="Tự động bắn dựa theo team (ShootEvent). Hostile = enemy theo team logic." })

local function getClosestHostile()
    local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myHRP then return nil, nil end
    local closest, closestDist, closestHRP = nil, CONFIG.AutoShootRange, nil
    for _, p in ipairs(Players:GetPlayers()) do
        if shouldAutoShoot(p) then
            local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local dist = (hrp.Position - myHRP.Position).Magnitude
                if dist < closestDist then
                    closest = p; closestDist = dist; closestHRP = hrp
                end
            end
        end
    end
    return closest, closestHRP
end

CombatTab:Toggle({ Title="Auto Shoot (Hostile)", Desc="Tự động bắn Guards/Criminals/Inmates", Default=false, Callback=function(v)
    state.autoShoot = v
    if autoShootConn then autoShootConn:Disconnect(); autoShootConn = nil end
    if not v then return end
    if not shootEvent then notify("Auto Shoot","ShootEvent không tìm thấy") return end
    local last = 0
    autoShootConn = track(RunService.Heartbeat:Connect(function()
        if os.clock() - last < CONFIG.AutoShootInterval then return end
        last = os.clock()
        local char = LocalPlayer.Character
        if not char or not char:FindFirstChildOfClass("Tool") then return end
        local target, hrp = getClosestHostile()
        if not target or not hrp then return end
        local aimPart = target.Character:FindFirstChild("Head") or hrp
        local origin = (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")).Position
        safe("autoshoot", function()
            shootEvent:FireServer({ { origin, aimPart.Position, aimPart } })
        end)
    end))
end })

CombatTab:Toggle({ Title="Bắn Trespassing Prisoner", Desc="Tự động bắn Inmates vào zone Guards", Default=false, Callback=function(v)
    state.autoShootTrespassing = v
end })

CombatTab:Slider({ Title="Auto Shoot Range", Step=5, Value={ Min=20, Max=200, Default=CONFIG.AutoShootRange }, Callback=function(v) CONFIG.AutoShootRange = v end })

-- ===== ANTI TASER =====
local walkBaseline, taseUntil = 16, 0
local function mentionsMe(...)
    local sawInstance = false
    for _, a in ipairs({...}) do
        if typeof(a) == "Instance" then
            sawInstance = true
            local c = LocalPlayer.Character
            if a == LocalPlayer or a == c or (c and a:IsDescendantOf(c)) then return true end
        end
    end
    return not sawInstance
end

track(RunService.Heartbeat:Connect(function()
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum and hum.WalkSpeed > 0.5 and os.clock() > taseUntil then walkBaseline = hum.WalkSpeed end
end))

if taseRemote then
    track(taseRemote.OnClientEvent:Connect(function(...)
        if state.antiTaser and mentionsMe(...) then
            taseUntil = os.clock() + CONFIG.TaseWindow
            notify("Anti Taser", "Phát hiện bị Taser, đang giữ WalkSpeed")
        end
    end))
end

track(RunService.Stepped:Connect(function()
    if not state.antiTaser or os.clock() > taseUntil then return end
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end
    if hum.WalkSpeed < walkBaseline then hum.WalkSpeed = walkBaseline end
    if hum.PlatformStand and not state.fly then hum.PlatformStand = false end
end))

CombatTab:Toggle({ Title="Anti Taser", Desc="Bị Taser bắn thì giữ lại WalkSpeed", Default=false, Callback=function(v)
    state.antiTaser = v
    if not v then taseUntil = 0 end
end })

-- ===== AUTO INVISIBLE < 35 HP =====
local autoInvisFired = false
CombatTab:Toggle({ Title="Auto Invisible (dưới 35 HP)", Desc="Tự động bật Invisible khi HP ≤ 35", Default=false, Callback=function(v)
    state.autoInvis = v
    if autoInvisConn then autoInvisConn:Disconnect(); autoInvisConn = nil end
    if not v then autoInvisFired = false return end
    autoInvisConn = track(RunService.Heartbeat:Connect(function()
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        if hum.Health > 0 and hum.Health <= CONFIG.AutoInvisHP then
            if not autoInvisFired then
                autoInvisFired = true
                safe("auto-invis-on", setInvisible, true)
                notify("⚠ Auto Invisible", "HP thấp ("..math.floor(hum.Health)..") - đã bật Invisible")
            end
        elseif hum.Health >= hum.MaxHealth * 0.9 then
            if autoInvisFired then
                autoInvisFired = false
                safe("auto-invis-off", setInvisible, false)
            end
        end
    end))
end })

-- ===== AIMLOCK =====
local fovCircle
local aimlockTarget = nil
local AIMLOCK_FOV = 80

local function destroyFOVCircle()
    if fovCircle then fovCircle:Remove(); fovCircle = nil end
end

local function createFOVCircle()
    destroyFOVCircle()
    if not Drawing then return end
    fovCircle = Drawing.new("Circle")
    fovCircle.Visible    = true
    fovCircle.Radius     = AIMLOCK_FOV
    fovCircle.Color      = Color3.fromRGB(255, 255, 255)
    fovCircle.Thickness  = 1.5
    fovCircle.Filled     = false
    fovCircle.Transparency = 0.8
    fovCircle.Position   = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
end

AimTab:Toggle({ Title="FOV Circle", Desc="Hiển thị vòng tròn FOV aimlock trên màn hình", Default=false, Callback=function(v)
    state.fovCircle = v
    if v then createFOVCircle() else destroyFOVCircle() end
end })

AimTab:Slider({ Title="FOV Radius", Step=5, Value={ Min=20, Max=250, Default=AIMLOCK_FOV }, Callback=function(v)
    AIMLOCK_FOV = v
    if fovCircle then fovCircle.Radius = v end
end })

local function getAimlockTarget()
    local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myHRP then return nil end
    local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    local best, bestDist = nil, AIMLOCK_FOV
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            if state.aimlockHostileOnly and not isHostileToMe(p) then continue end
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            local head = p.Character:FindFirstChild("Head")
            if hum and hum.Health > 0 and head then
                local screenPos, onScreen = Camera:WorldToViewportPoint(head.Position)
                if onScreen then
                    local dist2D = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
                    if dist2D < AIMLOCK_FOV and dist2D < bestDist then
                        best = p; bestDist = dist2D
                    end
                end
            end
        end
    end
    return best
end

AimTab:Toggle({ Title="Aimlock", Desc="Khóa aim vào đầu target gần nhất trong FOV circle", Default=false, Callback=function(v)
    state.aimlock = v
    if aimlockConn then aimlockConn:Disconnect(); aimlockConn = nil end
    if not v then aimlockTarget = nil return end
    aimlockConn = track(RunService.RenderStepped:Connect(function()
        aimlockTarget = getAimlockTarget()
        if not aimlockTarget or not aimlockTarget.Character then return end
        local head = aimlockTarget.Character:FindFirstChild("Head")
        if not head then return end
        local cf = Camera.CFrame
        local targetCF = CFrame.new(cf.Position, head.Position)
        Camera.CFrame = cf:Lerp(targetCF, CONFIG.AimlockSmoothing)
        if fovCircle then
            fovCircle.Position = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
        end
    end))
end })

AimTab:Slider({ Title="Aimlock Smoothing", Desc="0.1=mượt, 1.0=snap ngay", Step=0.05, Value={ Min=0.05, Max=1.0, Default=CONFIG.AimlockSmoothing }, Callback=function(v) CONFIG.AimlockSmoothing = v end })
AimTab:Toggle({ Title="Aimlock chỉ Hostile", Desc="Bật = chỉ lock hostile; Tắt = lock tất cả player", Default=false, Callback=function(v)
    state.aimlockHostileOnly = v
end })

-- ===== TELEPORT =====
local TELEPORT_LOCATIONS = {
    { name="Guards Base",       pos=Vector3.new(801,  99,  2299) },
    { name="Criminals Base",    pos=Vector3.new(-975, 107, 2058) },
    { name="Courtyard",         pos=Vector3.new(842,  97,  2478) },
    { name="Cells",             pos=Vector3.new(917,  99,  2435) },
    { name="Cafeteria",         pos=Vector3.new(949,  99,  2325) },
    { name="Roof (Cellblock)",  pos=Vector3.new(917,  148, 2458) },
    { name="Prison Gate",       pos=Vector3.new(505,  104, 2241) },
    { name="Outside Prison",    pos=Vector3.new(220,  63,  2347) },
    { name="Neutral Spawn",     pos=Vector3.new(842,  97,  2478) },
}

local function teleportTo(pos)
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then notify("Teleport","Chưa có nhân vật") return end
    hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
    if hoverTargetY then hoverTargetY = pos.Y + 3 end
    notify("📍 Teleport", "Đã tới " .. tostring(pos))
end

TeleportTab:Paragraph({ Title="Teleport nhanh", Desc="Dịch chuyển tới các khu vực chính trong game." })
for _, loc in ipairs(TELEPORT_LOCATIONS) do
    TeleportTab:Button({ Title=loc.name, Callback=function() teleportTo(loc.pos) end })
end

TeleportTab:Button({ Title="Teleport tới Target Aimlock", Desc="Tp ngay tới player đang bị aimlock lock", Callback=function()
    if aimlockTarget and aimlockTarget.Character then
        local hrp2 = aimlockTarget.Character:FindFirstChild("HumanoidRootPart")
        if hrp2 then teleportTo(hrp2.Position) end
    else
        notify("Teleport","Chưa có aimlock target")
    end
end })

TeleportTab:Button({ Title="Teleport tới Player gần nhất", Callback=function()
    local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myHRP then return end
    local closest, closestDist = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local hrp2 = p.Character:FindFirstChild("HumanoidRootPart")
            if hrp2 then
                local d = (hrp2.Position - myHRP.Position).Magnitude
                if d < closestDist then closest=p; closestDist=d end
            end
        end
    end
    if closest then
        local hrp2 = closest.Character:FindFirstChild("HumanoidRootPart")
        if hrp2 then teleportTo(hrp2.Position); notify("Teleport","→ "..closest.Name) end
    end
end })

-- ===== MOVEMENT: INVISIBLE =====
local invisParts, invisBusy = {}, false
local function collectInvisParts()
    invisParts = {}
    local char = LocalPlayer.Character
    if not char then return end
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency == 0 then
            invisParts[#invisParts+1] = d
        end
    end
end

local function applyInvisTransparency(v)
    for _, part in ipairs(invisParts) do
        if part.Parent then part.Transparency = v and CONFIG.InvisTransparency or 0 end
    end
end

setInvisible = function(v)
    state.invisible = v
    if invisConn then invisConn:Disconnect(); invisConn = nil end
    if v then
        collectInvisParts()
        applyInvisTransparency(true)
        invisConn = track(RunService.Heartbeat:Connect(function()
            if invisBusy then return end
            local char = LocalPlayer.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            local hum  = char and char:FindFirstChildOfClass("Humanoid")
            if not hrp or not hum or hum.Health <= 0 then return end
            invisBusy = true
            pcall(function()
                local oldCF, oldOff = hrp.CFrame, hum.CameraOffset
                local target = oldCF * CFrame.new(0, -CONFIG.InvisDepth, 0)
                local offset = target:ToObjectSpace(CFrame.new(oldCF.Position)).Position
                hrp.CFrame = target
                hum.CameraOffset = offset
                RunService.RenderStepped:Wait()
                hrp.CFrame = oldCF
                hum.CameraOffset = oldOff
            end)
            invisBusy = false
        end))
    else
        applyInvisTransparency(false)
    end
end

MovementTab:Toggle({ Title="Invisible", Desc="Server thấy bạn dưới lòng đất", Default=false, Callback=function(v)
    safe("invisible", setInvisible, v)
end })

-- ===== MOVEMENT: FLY =====
local function stopFly()
    if flyConn then flyConn:Disconnect(); flyConn = nil end
    if flyBV then flyBV:Destroy(); flyBV = nil end
    if flyBG then flyBG:Destroy(); flyBG = nil end
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum.PlatformStand = false end
end

local function startFly()
    stopFly()
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end
    hum.PlatformStand = true
    flyBV = Instance.new("BodyVelocity"); flyBV.MaxForce=Vector3.new(1e5,1e5,1e5); flyBV.Velocity=Vector3.zero; flyBV.Parent=hrp
    flyBG = Instance.new("BodyGyro");    flyBG.MaxTorque=Vector3.new(1e5,1e5,1e5); flyBG.P=1e4; flyBG.D=100; flyBG.CFrame=hrp.CFrame; flyBG.Parent=hrp
    flyConn = track(RunService.RenderStepped:Connect(function()
        local c    = LocalPlayer.Character
        local root = c and c:FindFirstChild("HumanoidRootPart")
        local h    = c and c:FindFirstChildOfClass("Humanoid")
        if not root or not h or not flyBV or not flyBV.Parent then return end
        h.PlatformStand = true
        local cam = workspace.CurrentCamera
        local rel = cam.CFrame:VectorToObjectSpace(h.MoveDirection)
        local dir = cam.CFrame.LookVector * (-rel.Z) + cam.CFrame.RightVector * rel.X
        local K   = Enum.KeyCode
        if UserInputService:IsKeyDown(K.Space) or h.Jump then dir += Vector3.yAxis end
        if UserInputService:IsKeyDown(K.LeftControl) then dir -= Vector3.yAxis end
        if dir.Magnitude > 1 then dir = dir.Unit end
        flyBV.Velocity = dir * flySpeed
        local flat = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
        if flat.Magnitude > 0.01 then flyBG.CFrame = CFrame.new(root.Position, root.Position + flat) end
    end))
end

MovementTab:Toggle({ Title="Fly", Desc="WASD/joystick = bay theo camera. Space = lên, Ctrl = xuống", Default=false, Callback=function(v)
    state.fly = v
    if v then startFly() else stopFly() end
end })
MovementTab:Slider({ Title="Fly Speed", Step=5, Value={ Min=10, Max=200, Default=flySpeed }, Callback=function(v) flySpeed = v end })

-- ===== MOVEMENT: NOCLIP =====
local noclipSaved = {}
local noclipMode, noclipSuppress = nil, false
local hoverBV, hoverConn
local hoverSpeed = 30
local voidToggle, hoverToggle

local function noclipOff()
    for part, saved in pairs(noclipSaved) do
        if part.Parent then
            part.CollisionGroup = saved.group
            part.CanCollide     = saved.canCollide
        end
    end
    noclipSaved = {}
end

local function stopHover()
    if hoverConn then hoverConn:Disconnect(); hoverConn = nil end
    if hoverBV   then hoverBV:Destroy();      hoverBV = nil end
    hoverTargetY = nil
end

local function startHover()
    stopHover()
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    hoverTargetY = hrp.Position.Y
    hoverBV = Instance.new("BodyVelocity")
    hoverBV.MaxForce = Vector3.new(1e6,1e6,1e6)
    hoverBV.Velocity = Vector3.zero
    hoverBV.Parent   = hrp
    hoverConn = track(RunService.RenderStepped:Connect(function(dt)
        local c    = LocalPlayer.Character
        local root = c and c:FindFirstChild("HumanoidRootPart")
        local h    = c and c:FindFirstChildOfClass("Humanoid")
        if not root or not h or not hoverBV or not hoverBV.Parent or not hoverTargetY then return end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) or h.Jump then hoverTargetY += hoverSpeed * dt end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then hoverTargetY -= hoverSpeed * dt end
        local md = h.MoveDirection
        local vy = math.clamp((hoverTargetY - root.Position.Y) * 8, -100, 100)
        hoverBV.Velocity = Vector3.new(md.X * h.WalkSpeed, vy, md.Z * h.WalkSpeed)
    end))
end

local function startNoclipLoop()
    noclipConn = track(RunService.Stepped:Connect(function()
        local char = LocalPlayer.Character
        if not char then return end
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") then
                if not noclipSaved[d] then noclipSaved[d] = { group=d.CollisionGroup, canCollide=d.CanCollide } end
                d.CollisionGroup = "Nothing"
                d.CanCollide     = false
            end
        end
    end))
end

local function setNoclipMode(mode)
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    stopHover(); noclipOff()
    noclipMode  = mode
    state.noclip = mode ~= nil
    if mode then
        startNoclipLoop()
        if mode == "hover" then startHover() end
    end
end

local function forceOff(toggle)
    noclipSuppress = true
    pcall(function()
        if toggle and toggle.Set then toggle:Set(false)
        elseif toggle and toggle.SetValue then toggle:SetValue(false) end
    end)
    task.delay(0.3, function() noclipSuppress = false end)
end

voidToggle = MovementTab:Toggle({ Title="Noclip (fall to Void)", Desc="Xuyên mọi thứ kể cả sàn", Default=false, Callback=function(v)
    if noclipSuppress then return end
    if v then forceOff(hoverToggle); setNoclipMode("void")
    elseif noclipMode == "void" then setNoclipMode(nil) end
end })

hoverToggle = MovementTab:Toggle({ Title="Noclip (no fall)", Desc="Xuyên tường, không rơi.", Default=false, Callback=function(v)
    if noclipSuppress then return end
    if v then forceOff(voidToggle); setNoclipMode("hover")
    elseif noclipMode == "hover" then setNoclipMode(nil) end
end })

MovementTab:Slider({ Title="Hover Speed", Step=5, Value={ Min=10, Max=100, Default=hoverSpeed }, Callback=function(v) hoverSpeed = v end })
MovementTab:Button({ Title="Hover Up +5",   Callback=function() if hoverTargetY then hoverTargetY += 5 end end })
MovementTab:Button({ Title="Hover Down -5", Callback=function() if hoverTargetY then hoverTargetY -= 5 end end })

track(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.6)
    autoInvisFired = false
    if state.invisible then safe("invisible respawn", function() collectInvisParts(); applyInvisTransparency(true) end) end
    if state.fly        then safe("fly respawn",       startFly)   end
    if noclipMode == "hover" then safe("hover respawn", startHover) end
end))

-- ===== PICKUPS =====
local FOODS  = { "Breakfast", "Lunch", "Dinner" }
local MELEES = { "Crude Knife", "Hammer" }
local isFood, isMelee = {}, {}
for _, n in ipairs(FOODS)  do isFood[n]  = true end
for _, n in ipairs(MELEES) do isMelee[n] = true end

local function getGiver()
    local items = workspace:FindFirstChild("Prison_ITEMS")
    return items and items:FindFirstChild("giver")
end

local function hasTool(name)
    local c = LocalPlayer.Character
    return LocalPlayer.Backpack:FindFirstChild(name) or (c and c:FindFirstChild(name))
end

local function anchorPart(model)
    return model:FindFirstChild("ITEMPICKUP",true) or model:FindFirstChild("Mesh") or model:FindFirstChildWhichIsA("BasePart",true)
end

local function findCandidates(name)
    local list = {}
    local giver = getGiver()
    if giver then for _, m in ipairs(giver:GetChildren()) do if m.Name == name then list[#list+1] = m end end end
    for _, m in ipairs(workspace:GetChildren()) do
        if m.Name == name and m:IsA("Model") then list[#list+1] = m end
    end
    local teamName = LocalPlayer.Team and LocalPlayer.Team.Name
    local wantGuardSide = teamName == "Guards"
    local function score(model)
        local p = anchorPart(model)
        if not p then return 2 end
        return ((p.Position.X > 0) == wantGuardSide) and 0 or 1
    end
    table.sort(list, function(a,b) return score(a) < score(b) end)
    return list
end

local function pickupByName(name)
    if not pickupRemote and not giverRemote then return false, "Không thấy remote nhặt đồ" end
    if hasTool(name) then return true, "Đã có " .. name end
    local candidates = findCandidates(name)
    if #candidates == 0 then return false, name .. " không có trên map lúc này" end
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false, "Chưa có nhân vật" end
    local home = hrp.CFrame
    local lastMsg = "Server từ chối"
    local function finish(ok, msg)
        hrp.CFrame = home
        if hoverTargetY then hoverTargetY = hrp.Position.Y end
        return ok, msg
    end
    for _, model in ipairs(candidates) do
        local part = anchorPart(model)
        if part and part.Parent then
            hrp.CFrame = part.CFrame + Vector3.new(0,3,0)
            if hoverTargetY then hoverTargetY = hrp.Position.Y end
            task.wait(CONFIG.PickupSettle)
            if giverRemote then
                pcall(function() giverRemote:FireServer(model) end)
                task.wait(CONFIG.PickupSettle * 2)
                if hasTool(name) then return finish(true, "Nhặt qua GiverPressed") end
            end
            if pickupRemote then
                local ok, res = pcall(function() return pickupRemote:InvokeServer(part) end)
                task.wait(CONFIG.PickupSettle)
                if ok and res ~= nil then lastMsg = tostring(res) end
                if hasTool(name) then return finish(true, lastMsg) end
            end
        end
    end
    return finish(false, lastMsg)
end

local function doPickup(name) task.spawn(function() local ok,msg=pickupByName(name); notify(ok and("✓ "..name) or("✗ "..name), msg) end) end
local function pickupMany(names) task.spawn(function() for _,n in ipairs(names) do local ok,msg=pickupByName(n); notify(ok and("✓ "..n) or("✗ "..n), msg) end end) end

PickupTab:Paragraph({ Title="Cách hoạt động", Desc="Tp tới item, gửi GiverPressed, rồi tp về." })
for _, n in ipairs(FOODS)  do PickupTab:Button({ Title="Lấy "..n, Callback=function() doPickup(n) end }) end
PickupTab:Button({ Title="Lấy tất cả đồ ăn", Callback=function() pickupMany(FOODS) end })
for _, n in ipairs(MELEES) do PickupTab:Button({ Title="Lấy "..n, Callback=function() doPickup(n) end }) end
PickupTab:Button({ Title="Lấy Crude Knife + Hammer", Callback=function() pickupMany(MELEES) end })

local function renderGunButtons()
    local gunNames, seen = {}, {}
    local giver = getGiver()
    if giver then
        for _, m in ipairs(giver:GetChildren()) do
            if not isFood[m.Name] and not isMelee[m.Name] and not seen[m.Name] then 
                seen[m.Name] = true
                gunNames[#gunNames+1] = m.Name 
            end
        end
        table.sort(gunNames)
    end
    for _, n in ipairs(gunNames) do PickupTab:Button({ Title="Lấy "..n, Callback=function() doPickup(n) end }) end
    if #gunNames > 0 then
        PickupTab:Button({ Title="Lấy tất cả súng / đồ", Callback=function() pickupMany(gunNames) end })
    end
end
renderGunButtons()
PickupTab:Button({ Title="🔄 Dynamic Refresh Guns", Desc="Cập nhật lại danh sách súng trên map", Callback=function() renderGunButtons(); notify("Pickups", "Đã cập nhật danh sách súng") end })

-- ===== TEAM SWAP =====
local TEAM_EDGES = {
    Neutral  = { "Inmates", "Guards" },
    Guards   = { "Neutral" },
    Criminals= { "Neutral" },
    Inmates  = { "Criminals" },
}

local function curTeam() return LocalPlayer.Team and LocalPlayer.Team.Name end

local function findRoute(from, to)
    if from == to then return {} end
    local queue, visited = { { from, {} } }, { [from]=true }
    while #queue > 0 do
        local node, path = unpack(table.remove(queue,1))
        for _, nxt in ipairs(TEAM_EDGES[node] or {}) do
            if not visited[nxt] then
                local newPath = { table.unpack(path) }; newPath[#newPath+1] = nxt
                if nxt == to then return newPath end
                visited[nxt] = true; queue[#queue+1] = { nxt, newPath }
            end
        end
    end
    return nil
end

local function waitForTeam(name, timeout)
    local t0 = os.clock()
    while os.clock()-t0 < timeout do
        if curTeam() == name then return true end
        task.wait(0.15)
    end
    return curTeam() == name
end

local function waitForCharacter(timeout)
    local t0 = os.clock()
    while os.clock()-t0 < timeout do
        local c = LocalPlayer.Character
        if c and c:FindFirstChild("HumanoidRootPart") and c:FindFirstChildOfClass("Humanoid") then return true end
        task.wait(0.15)
    end
    return false
end

local function stepTeam(from, to)
    if from == "Inmates" and to == "Criminals" then
        local holder = workspace:FindFirstChild("Criminals Spawn",true)
        local sp     = holder and holder:FindFirstChildWhichIsA("SpawnLocation",true)
        local char   = LocalPlayer.Character
        local hrp    = char and char:FindFirstChild("HumanoidRootPart")
        if not sp or not hrp then return false, "Không tìm thấy Criminals Spawn hoặc nhân vật" end
        local home = hrp.CFrame
        hrp.CFrame = sp.CFrame + Vector3.new(0,4,0)
        local ok = waitForTeam("Criminals", 5)
        if ok and LocalPlayer.Character == char and hrp.Parent then hrp.CFrame = home end
        return ok, ok and "Đã thành Criminals" or "Đứng ở Criminals Spawn nhưng team không đổi"
    end
    if not teamRemote then return false, "Không thấy RequestTeamChange" end
    local teamObj = Teams:FindFirstChild(to)
    if not teamObj then return false, "Không có team "..to end
    for attempt = 1, CONFIG.TeamAttempts do
        local ok, res = pcall(function() return teamRemote:InvokeServer(teamObj, 1) end)
        if not ok then return false, "Lỗi gọi server: "..tostring(res) end
        if waitForTeam(to, CONFIG.TeamAttemptWait) then
            waitForCharacter(6); task.wait(CONFIG.TeamStepWait)
            return true, "Đã vào "..to
        end
    end
    local hint = (from=="Guards") and " (vừa vào Guards cần chờ ~8 giây)" or ((to=="Guards") and " (Guards có thể đã đầy)" or "")
    return false, "Server từ chối "..from.."→"..to..hint
end

local switching = false
local function switchTeam(target)
    if switching then return false, "Đang đổi team, chờ chút" end
    local from = curTeam()
    if not from then return false, "Chưa có team hiện tại" end
    if from == target then return true, "Bạn đã ở "..target end
    local route = findRoute(from, target)
    if not route then return false, "Không có đường đi "..from.."→"..target end
    switching = true
    local prev, lastMsg = from, ""
    for _, nextTeam in ipairs(route) do
        local ok, msg = stepTeam(prev, nextTeam)
        lastMsg = msg
        if not ok then switching=false; return false, msg end
        prev = nextTeam
    end
    switching = false
    return true, (#route>1 and ("Đi qua "..#route.." bước: "..from.."→"..table.concat(route,"→")) or lastMsg)
end
API.switchTeam = switchTeam

local teamStatus = TeamSwapTab:Paragraph({ Title="Team hiện tại", Desc="..." })
TeamSwapTab:Paragraph({ Title="Luật đổi team", Desc="Neutral→Inmates/Guards, Guards→Neutral, Criminals→Neutral. Inmates→Criminals bằng Spawn." })
for _, t in ipairs({ "Neutral","Inmates","Guards","Criminals" }) do
    TeamSwapTab:Button({ Title="Đổi sang "..t, Callback=function()
        task.spawn(function()
            local ok, msg = switchTeam(t)
            notify(ok and("✓ "..t) or("✗ "..t), msg)
        end)
    end })
end

-- ===== ESP =====
local TEAM_COLORS = {
    Guards=Color3.fromRGB(0,120,255), Inmates=Color3.fromRGB(255,140,0),
    Criminals=Color3.fromRGB(255,30,30), Neutral=Color3.fromRGB(180,180,180),
}
local function getTeamColor(p) return (p.Team and TEAM_COLORS[p.Team.Name]) or Color3.fromRGB(200,200,200) end
local function removeESP(p)
    local objs = espObjects[p]
    if objs then for _,o in ipairs(objs) do pcall(function() o:Destroy() end) end end
    espObjects[p] = nil
end

local function buildESP(p)
    if p == LocalPlayer then return end
    removeESP(p)
    local char = p.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not char or not hrp then return end
    local color = getTeamColor(p)
    local objs = {}
    local hl = Instance.new("Highlight")
    hl.Adornee=char; hl.FillColor=color; hl.OutlineColor=color
    hl.FillTransparency=0.5; hl.OutlineTransparency=0
    hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; hl.Parent=char
    objs[#objs+1] = hl
    if state.espNames then
        local bb = Instance.new("BillboardGui")
        bb.Adornee=hrp; bb.AlwaysOnTop=true; bb.Size=UDim2.fromOffset(120,20); bb.StudsOffset=Vector3.new(0,3.5,0)
        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency=1; lbl.Size=UDim2.fromScale(1,1); lbl.Font=Enum.Font.GothamBold
        lbl.TextSize=13; lbl.TextColor3=color; lbl.TextStrokeTransparency=0.4; lbl.Text=p.DisplayName
        lbl.Parent=bb; bb.Parent=hrp
        objs[#objs+1] = bb
    end
    espObjects[p] = objs
end

local function refreshAllESP()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then if state.esp then buildESP(p) else removeESP(p) end end
    end
end

ESPTab:Toggle({ Title="ESP (Body)", Desc="Inmates=Cam, Criminals=Đỏ, Guards=Xanh", Default=false, Callback=function(v) state.esp=v; refreshAllESP() end })
ESPTab:Toggle({ Title="Show Names", Desc="Hiện tên trên đầu nhân vật", Default=false, Callback=function(v) state.espNames=v; if state.esp then refreshAllESP() end end })

local function hookPlayer(p)
    if p == LocalPlayer then return end
    track(p.CharacterAdded:Connect(function() task.wait(0.5); if state.esp then buildESP(p) end end))
    track(p:GetPropertyChangedSignal("Team"):Connect(function() if state.esp then buildESP(p) end end))
end
for _, p in ipairs(Players:GetPlayers()) do hookPlayer(p) end
track(Players.PlayerAdded:Connect(hookPlayer))
track(Players.PlayerRemoving:Connect(removeESP))

-- ===== KILL LOG =====
local killParagraph = KillsTab:Paragraph({ Title="Recent Kills", Desc="Waiting for kills..." })
local function renderKills()
    local lines = {}
    for i = #killLog, math.max(1,#killLog-CONFIG.KillLogShown+1), -1 do lines[#lines+1] = killLog[i] end
    safe("render kills", function() killParagraph:SetDesc(#lines>0 and table.concat(lines,"\n") or "Waiting for kills...") end)
end

local killfeed = ReplicatedStorage:FindFirstChild("Killfeed")
if killfeed then
    for _, e in ipairs(killfeed:GetChildren()) do killLog[#killLog+1] = e.Name end
    track(killfeed.ChildAdded:Connect(function(c)
        killLog[#killLog+1] = c.Name
        if #killLog > CONFIG.KillLogSize then table.remove(killLog,1) end
        renderKills()
    end))
    renderKills()
else killParagraph:SetDesc("Killfeed not found in ReplicatedStorage.") end
KillsTab:Button({ Title="Clear Log", Callback=function() killLog={}; renderKills() end })

-- ===== TEAMS =====
local rosterParagraphs = {}
local function initRosterTab()
    for _, t in ipairs(Teams:GetChildren()) do
        if t:IsA("Team") and not rosterParagraphs[t] then
            rosterParagraphs[t] = TeamsTab:Paragraph({ Title=t.Name, Desc="Loading players..." })
        end
    end
end
initRosterTab()

local function updateRoster()
    initRosterTab()
    for t, para in pairs(rosterParagraphs) do
        local members, names = t:GetPlayers(), {}
        for i, plr in ipairs(members) do
            if i > CONFIG.RosterNamesPerTeam then names[#names+1]=string.format("+%d more",#members-CONFIG.RosterNamesPerTeam) break end
            names[#names+1] = plr.DisplayName
        end
        safe("roster", function() para:SetDesc(string.format("%d player(s)\n%s", #members, #names>0 and table.concat(names,", ") or "empty")) end)
    end
end

-- ===== UTILITY =====
local afkConn
UtilTab:Toggle({ Title="Anti-AFK", Desc="Chống kick idle", Default=false, Callback=function(v)
    if v then
        afkConn = track(LocalPlayer.Idled:Connect(function()
            safe("anti-afk", function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new()) end)
        end))
    elseif afkConn then afkConn:Disconnect(); afkConn=nil end
end })

UtilTab:Toggle({ Title="Fullbright", Desc="Xóa bóng tối và sương mù", Default=false, Callback=function(v)
    safe("fullbright", function()
        if v then
            originals.lighting = { Brightness=Lighting.Brightness, ClockTime=Lighting.ClockTime, FogEnd=Lighting.FogEnd, GlobalShadows=Lighting.GlobalShadows, Ambient=Lighting.Ambient }
            Lighting.Brightness=2; Lighting.ClockTime=14; Lighting.FogEnd=1e6; Lighting.GlobalShadows=false; Lighting.Ambient=Color3.fromRGB(178,178,178)
        elseif originals.lighting then
            for k,val in pairs(originals.lighting) do Lighting[k]=val end
            originals.lighting=nil
        end
    end)
end })

UtilTab:Slider({ Title="Field of View", Step=1, Value={ Min=40, Max=120, Default=originals.fov }, Callback=function(v) safe("fov", function() Camera.FieldOfView=v end) end })
UtilTab:Toggle({ Title="Unlock Max Zoom", Default=false, Callback=function(v) safe("zoom", function() LocalPlayer.CameraMaxZoomDistance=v and 1000 or originals.zoom end) end })

-- ===== SETTINGS =====
SettingsTab:Paragraph({ Title="PrisonHub Config", Desc="Tùy chỉnh giao diện và quản lý phiên làm việc." })

SettingsTab:Keybind({ Title="Toggle UI Keybind", Desc="Phím đóng/mở giao diện Hub", Default=Enum.KeyCode.RightShift, Callback=function()
    if Window then Window:Toggle() end
end })

SettingsTab:Dropdown({ Title="UI Theme", Desc="Đổi chủ đề giao diện WindUI", Options={"Dark", "Light", "Rose", "Aqua"}, Default="Dark", Callback=function(theme)
    if Window and Window.SetTheme then Window:SetTheme(theme) end
end })

SettingsTab:Button({ Title="Copy Script Raw Link", Callback=function()
    if setclipboard then 
        setclipboard("loadstring(game:HttpGet('https://raw.githubusercontent.com/Thaihdu21/prison-life-script/refs/heads/main/prison-life.lua'))()")
        notify("Copied", "Đã sao chép đường dẫn Script!")
    else 
        notify("Error", "setclipboard không hỗ trợ") 
    end
end })

local function unload()
    running = false
    state.esp = false; refreshAllESP()
    destroyFOVCircle()
    safe("unload invisible",  setInvisible,   false)
    stopFly()
    safe("unload noclip", setNoclipMode, nil)
    if autoShootConn then autoShootConn:Disconnect(); autoShootConn=nil end
    if aimlockConn   then aimlockConn:Disconnect();   aimlockConn=nil end
    if autoInvisConn then autoInvisConn:Disconnect(); autoInvisConn=nil end
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    connections = {}
    pcall(function()
        if originals.lighting then for k,val in pairs(originals.lighting) do Lighting[k]=val end end
        Camera.FieldOfView = originals.fov
        LocalPlayer.CameraMaxZoomDistance = originals.zoom
    end)
    pcall(function() Window:Destroy() end)
    if getgenv then getgenv().PrisonHubUnload=nil; getgenv().PrisonHubAPI=nil end
    log("INFO","Unloaded")
end
if getgenv then getgenv().PrisonHubUnload = unload end

SettingsTab:Button({ Title="Unload PrisonHub", Desc="Dọn sạch mọi thứ và đóng cửa sổ", Callback=unload })

-- ===== MAIN LOOP =====
task.spawn(function()
    while running do
        local t = LocalPlayer.Team
        local desc = string.format(
            "Your team: %s\nFPS: %d\nPing: %d ms\nMemory: %.1f MB\nPlayers: %d / %d\nSession: %s",
            t and t.Name or "none", fps, getPing(), Stats:GetTotalMemoryUsageMb(),
            #Players:GetPlayers(), Players.MaxPlayers, fmtTime(math.floor(os.clock()-startTime))
        )
        safe("overview",     function() overview:SetDesc(desc) end)
        safe("team status",  function() teamStatus:SetDesc(t and t.Name or "none") end)
        updateRoster()
        task.wait(CONFIG.StatsInterval)
    end
end)

notify("PrisonHub","v2.9 Loaded ✓")
log("INFO","PrisonHub v2.9 ready")
