-- PrisonHub v3.1 | WindUI | Cuộc Sống Trong Nhà Tù
-- v3.1: tab Players (dropdown chọn người, Ô NHẬP TÊN để chọn/teleport, teleport tới người đã chọn, spectate),
--       Anti-Arrest (né Guards cầm Handcuffs + khôi phục di chuyển khi bị còng)
-- v2.9+: Car tab (Car Fly), Auto Arrest, Spin Bot, Bunny Hop, Teleport, Aimlock, Auto-Shoot, Auto-Invisible <35HP
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

local Players       = game:GetService("Players")
local Teams         = game:GetService("Teams")
local RunService    = game:GetService("RunService")
local Lighting      = game:GetService("Lighting")
local Stats         = game:GetService("Stats")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser   = game:GetService("VirtualUser")
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
local function divider(tab) pcall(function() tab:Divider() end) end
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
local CarTab      = Window:Tab({ Title="Car",       Icon="car" })
local TeleportTab = Window:Tab({ Title="Teleport",  Icon="map-pin" })
local PlayersTab  = Window:Tab({ Title="Players",   Icon="user" })
local PickupTab   = Window:Tab({ Title="Pickups",   Icon="package" })
local TeamSwapTab = Window:Tab({ Title="Team Swap", Icon="refresh-cw" })
local ESPTab      = Window:Tab({ Title="ESP",       Icon="eye" })
local KillsTab    = Window:Tab({ Title="Kill Log",  Icon="skull" })
local TeamsTab    = Window:Tab({ Title="Teams",     Icon="users" })
local UtilTab     = Window:Tab({ Title="Utility",   Icon="wrench" })
local SettingsTab = Window:Tab({ Title="Settings",  Icon="settings" })

local API = {
    Window=Window, WindUI=WindUI, CONFIG=CONFIG, state=state, notify=notify, track=track, safe=safe, log=log,
    Tabs={ Overview=OverviewTab, Combat=CombatTab, Aim=AimTab, Movement=MovementTab, Car=CarTab, Teleport=TeleportTab, Players=PlayersTab,
           Pickups=PickupTab, TeamSwap=TeamSwapTab, ESP=ESPTab, Kills=KillsTab, Teams=TeamsTab, Utility=UtilTab, Settings=SettingsTab }
}
if getgenv then getgenv().PrisonHubAPI = API end

-- ===== OVERVIEW =====
local overview = OverviewTab:Paragraph({ Title="Server", Desc="Collecting..." })
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
-- Team hostile logic (verified from game):
--   Guards     → hostile to: Criminals, Inmates (in restricted zone counted as trespassing)
--   Criminals  → hostile to: Guards
--   Inmates    → not hostile by default; may trespass
-- "Trespassing Inmate" = Inmate detected inside Guards-only zone (X < 850, Z < 2350 roughly)
local GUARD_ZONE = { xMin=650, xMax=900, zMin=2250, zMax=2380 } -- Guards base approximate zone

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
    return p.Team and p.Team.Name == "Inmates" and p.Character and p.Character:GetAttribute("Trespassing") == true
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

-- ===== AUTO SHOOT (ShootEvent-based) =====
divider(CombatTab)
CombatTab:Paragraph({ Title="Auto Shoot", Desc="Tự động bắn dựa theo team (ShootEvent). Hostile = enemy theo team logic. Trespassing = Inmate vào zone Guards." })

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

CombatTab:Toggle({ Title="Auto Shoot (Hostile)", Desc="Tự động bắn Guards/Criminals/Inmates (theo team bạn đang ở)", Default=false, Callback=function(v)
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
        -- format xác nhận bằng remote-spy: FireServer({ {origin, hitPos, hitPart} })
        safe("autoshoot", function()
            shootEvent:FireServer({ { origin, aimPart.Position, aimPart } })
        end)
    end))
end })

CombatTab:Toggle({ Title="Bắn Trespassing Prisoner", Desc="Bật thêm: tự động bắn Inmates đang vào zone Guards (mặc định tắt)", Default=false, Callback=function(v)
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
divider(CombatTab)
local autoInvisFired = false
CombatTab:Toggle({ Title="Auto Invisible (dưới 35 HP)", Desc="Tự động bật Invisible khi HP ≤ 35, tự tắt khi full HP", Default=false, Callback=function(v)
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
    local best, bestDist = nil, CONFIG.AimlockRange
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
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
        -- update fov circle position
        if fovCircle then
            fovCircle.Position = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
        end
    end))
end })
AimTab:Slider({ Title="Aimlock Smoothing", Desc="0.1=mượt, 1.0=snap ngay", Step=0.05, Value={ Min=0.05, Max=1.0, Default=CONFIG.AimlockSmoothing }, Callback=function(v) CONFIG.AimlockSmoothing = v end })
AimTab:Toggle({ Title="Aimlock chỉ Hostile", Desc="Bật = chỉ lock hostile; Tắt = lock tất cả player", Default=false, Callback=function(v)
    -- stored in state for getAimlockTarget to check
    state.aimlockHostileOnly = v
end })

-- override getAimlockTarget to respect hostile filter
local _baseGetAimlockTarget = getAimlockTarget
getAimlockTarget = function()
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

TeleportTab:Paragraph({ Title="Teleport nhanh", Desc="Dịch chuyển tới các khu vực chính trong game. Nếu đang Hover/Fly thì Y tự cập nhật." })
for _, loc in ipairs(TELEPORT_LOCATIONS) do
    TeleportTab:Button({ Title=loc.name, Callback=function() teleportTo(loc.pos) end })
end
divider(TeleportTab)
TeleportTab:Button({ Title="Teleport tới Target Aimlock", Desc="Tp ngay tới player đang bị aimlock lock", Callback=function()
    if aimlockTarget and aimlockTarget.Character then
        local hrp2 = aimlockTarget.Character:FindFirstChild("HumanoidRootPart")
        if hrp2 then teleportTo(hrp2.Position + Vector3.new(0,3,0)) end
    else
        notify("Teleport","Chưa có aimlock target") 
    end
end })
TeleportTab:Button({ Title="Teleport tới Player...", Desc="Nhập tên rồi tp", Callback=function()
    -- fallback: tp tới người gần nhất
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
        if hrp2 then teleportTo(hrp2.Position + Vector3.new(0,3,0)); notify("Teleport","→ "..closest.Name) end
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
-- forward declare so auto-invis toggle above can reference it
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
MovementTab:Toggle({ Title="Invisible", Desc="Server thấy bạn dưới lòng đất; màn hình hiện ghost", Default=false, Callback=function(v)
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
MovementTab:Toggle({ Title="Fly", Desc="WASD/joystick = bay theo camera. Jump/Space = lên, Ctrl = xuống", Default=false, Callback=function(v)
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
hoverToggle = MovementTab:Toggle({ Title="Noclip (no fall)", Desc="Xuyên tường, không rơi. Space=lên, Ctrl=xuống", Default=false, Callback=function(v)
    if noclipSuppress then return end
    if v then forceOff(voidToggle); setNoclipMode("hover")
    elseif noclipMode == "hover" then setNoclipMode(nil) end
end })
MovementTab:Slider({ Title="Hover Speed", Step=5, Value={ Min=10, Max=100, Default=hoverSpeed }, Callback=function(v) hoverSpeed = v end })
MovementTab:Button({ Title="Hover Up +5",   Callback=function() if hoverTargetY then hoverTargetY += 5 end end })
MovementTab:Button({ Title="Hover Down -5", Callback=function() if hoverTargetY then hoverTargetY -= 5 end end })

-- ===== AUTO ARREST (Guards + Handcuffs) =====
local arrestRemote = Remotes and Remotes:FindFirstChild("ArrestPlayer")
local arrestCfg = { radius=100, interval=0.4, cooldown=2.5, criminals=true, trespass=true, hostile=true, tp=true }
local arrestConn, arrestBusy, arrestedAt = nil, false, {}
state.autoArrest = false
local function wantArrest(p)
    if p == LocalPlayer or not p.Team or not p.Character then return false end
    local hum = p.Character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    local t = p.Team.Name
    if t == "Criminals" then return arrestCfg.criminals end
    if t == "Inmates" then
        if arrestCfg.trespass and p.Character:GetAttribute("Trespassing") == true then return true end
        if arrestCfg.hostile and p.Character:GetAttribute("Hostile") == true then return true end
    end
    return false
end
local function getCuffs()
    local c = LocalPlayer.Character
    if not c then return nil end
    for _, box in ipairs({ c, LocalPlayer.Backpack }) do
        local t = box:FindFirstChild("Handcuffs")
        if t and t:IsA("Tool") then return t end
    end
end
divider(CombatTab)
CombatTab:Toggle({ Title="Auto Arrest (Guards)", Desc="Guards tự bắt Criminals / Hostile / Trespassing Inmates bằng Handcuffs", Default=false, Callback=function(v)
    state.autoArrest = v
    if arrestConn then arrestConn:Disconnect(); arrestConn = nil end
    if not v then return end
    if not arrestRemote then notify("Auto Arrest", "Không thấy ArrestPlayer") return end
    local last = 0
    arrestConn = track(RunService.Heartbeat:Connect(function()
        if arrestBusy or os.clock() - last < arrestCfg.interval then return end
        last = os.clock()
        if not (LocalPlayer.Team and LocalPlayer.Team.Name == "Guards") then return end
        local char = LocalPlayer.Character
        local myHRP = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not myHRP or not hum or hum.Health <= 0 then return end
        local best, bestHRP, bestD = nil, nil, arrestCfg.radius
        for _, p in ipairs(Players:GetPlayers()) do
            if wantArrest(p) and (not arrestedAt[p] or os.clock() - arrestedAt[p] > arrestCfg.cooldown) then
                local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local d = (hrp.Position - myHRP.Position).Magnitude
                    if d <= bestD then best, bestHRP, bestD = p, hrp, d end
                end
            end
        end
        if not best then return end
        local cuffs = getCuffs()
        if not cuffs then return end
        arrestBusy = true
        task.spawn(function()
            pcall(function()
                if cuffs.Parent ~= char then hum:EquipTool(cuffs); task.wait(0.15) end
                local home
                if arrestCfg.tp then
                    home = myHRP.CFrame
                    myHRP.CFrame = bestHRP.CFrame * CFrame.new(0, 0, 3)
                    task.wait(0.2)
                end
                arrestedAt[best] = os.clock()
                arrestRemote:InvokeServer(best, 1)
                task.wait(0.1)
                if home and myHRP.Parent then myHRP.CFrame = home end
            end)
            arrestBusy = false
        end)
    end))
end })
CombatTab:Slider({ Title="Phạm vi quét target (stud)", Step=5, Value={ Min=5, Max=500, Default=arrestCfg.radius }, Callback=function(v) arrestCfg.radius = v end })
CombatTab:Toggle({ Title="Bắt Criminals", Default=true, Callback=function(v) arrestCfg.criminals = v end })
CombatTab:Toggle({ Title="Bắt Trespassing Inmates", Default=true, Callback=function(v) arrestCfg.trespass = v end })
CombatTab:Toggle({ Title="Bắt Hostile Inmates", Default=true, Callback=function(v) arrestCfg.hostile = v end })
CombatTab:Toggle({ Title="Teleport tới target để bắt", Desc="Tắt = chỉ bắt khi target đã ở gần bạn", Default=true, Callback=function(v) arrestCfg.tp = v end })

-- ===== CAR TAB (Car Fly bằng dịch chuyển + noclip) =====
do
    local carCfg = { speed = 80, targetY = 116, flyNoclip = true }

    local function currentSeat()
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        local seat = hum and hum.SeatPart
        if seat and seat:IsA("VehicleSeat") then return seat end
    end
    local function carModel(seat)
        local m = seat
        while m.Parent and m.Parent ~= workspace and m.Parent.Name ~= "CarContainer" do m = m.Parent end
        return m
    end

    local savedCollide = {}
    local function disableCollisions(model)
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then
                if savedCollide[d] == nil then savedCollide[d] = d.CanCollide end
                d.CanCollide = false
            end
        end
    end
    local function restoreCollisions()
        for part, can in pairs(savedCollide) do
            if part.Parent then part.CanCollide = can end
        end
        savedCollide = {}
    end

    -- vô hiệu BodyGyro/BodyVelocity của game khi bay (tránh giằng co gây xoay loạn)
    local savedMovers, moverModel = {}, nil
    local function freezeGameMovers(model)
        if moverModel == model then return end
        moverModel = model
        savedMovers = {}
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("BodyGyro") then
                savedMovers[#savedMovers+1] = { d, "MaxTorque", d.MaxTorque }
                d.MaxTorque = Vector3.zero
            elseif d:IsA("BodyVelocity") then
                savedMovers[#savedMovers+1] = { d, "MaxForce", d.MaxForce }
                d.MaxForce = Vector3.zero
            end
        end
    end
    local function restoreGameMovers()
        for _, sv in ipairs(savedMovers) do
            if sv[1].Parent then pcall(function() sv[1][sv[2]] = sv[3] end) end
        end
        savedMovers, moverModel = {}, nil
    end

    local flyConn, rootsCache, rootsModel = nil, {}, nil
    local function stopCarFly()
        if flyConn then flyConn:Disconnect(); flyConn = nil end
        restoreGameMovers()
        restoreCollisions()
        rootsCache, rootsModel = {}, nil
    end
    API.stopCarFly = stopCarFly

    local function moveCar(model, center, newCenter, yawStep)
        -- pivot của model Squad nằm rất xa xe, nên xoay quanh tâm xe rồi áp lên pivot
        local delta = CFrame.new(newCenter) * CFrame.Angles(0, yawStep, 0) * CFrame.new(-center)
        model:PivotTo(delta * model:GetPivot())
    end

    CarTab:Paragraph({ Title="Car Fly", Desc="Ngồi ghế lái rồi bật. Ga tiến + nhìn lên = xe lên, buông ga = lơ lửng. PC: Space lên, Ctrl xuống. Bay bằng dịch chuyển nên không bị tường chặn." })
    CarTab:Toggle({ Title="Car Fly", Default=false, Callback=function(v)
        state.carFly = v
        stopCarFly()
        if not v then return end
        flyConn = track(RunService.Heartbeat:Connect(function(dt)
            local seat = currentSeat()
            if not seat then return end
            local model = carModel(seat)
            freezeGameMovers(model)
            if carCfg.flyNoclip then disableCollisions(model) end

            local cam = workspace.CurrentCamera
            local dir = cam.CFrame.LookVector * seat.ThrottleFloat + cam.CFrame.RightVector * seat.SteerFloat
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
            if dir.Magnitude > 1 then dir = dir.Unit end

            local center = seat.Position
            local newCenter = center + dir * carCfg.speed * dt

            local fwd = Vector3.new(seat.CFrame.LookVector.X, 0, seat.CFrame.LookVector.Z)
            local des = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
            local yaw = 0
            if fwd.Magnitude > 0.01 and des.Magnitude > 0.01 then
                fwd, des = fwd.Unit, des.Unit
                local ang = math.atan2(fwd:Cross(des).Y, fwd:Dot(des))
                yaw = ang * math.min(1, 8 * dt)
            end
            moveCar(model, center, newCenter, yaw)

            if rootsModel ~= model then
                rootsModel, rootsCache = model, {}
                local seen = {}
                for _, d in ipairs(model:GetDescendants()) do
                    if d:IsA("BasePart") then
                        local r = d.AssemblyRootPart
                        if r and not seen[r] then seen[r] = true; rootsCache[#rootsCache+1] = r end
                    end
                end
            end
            for _, r in ipairs(rootsCache) do
                if r.Parent then
                    r.AssemblyLinearVelocity = Vector3.zero
                    r.AssemblyAngularVelocity = Vector3.zero
                end
            end
        end))
    end })
    CarTab:Slider({ Title="Tốc độ bay", Step=10, Value={ Min=20, Max=300, Default=carCfg.speed }, Callback=function(v) carCfg.speed = v end })
    CarTab:Toggle({ Title="Fly xuyên tường (tắt va chạm xe)", Default=true, Callback=function(v) carCfg.flyNoclip = v end })

    local function shiftCarY(deltaY, absoluteY)
        local seat = currentSeat()
        if not seat then notify("Car", "Bạn chưa ngồi ghế lái") return false end
        local model = carModel(seat)
        local dy = absoluteY and (absoluteY - seat.Position.Y) or deltaY
        model:PivotTo(CFrame.new(0, dy, 0) * model:GetPivot())
        return true
    end
    CarTab:Slider({ Title="Độ cao teleport (Y)", Step=1, Value={ Min=60, Max=300, Default=carCfg.targetY }, Callback=function(v) carCfg.targetY = v end })
    CarTab:Button({ Title="Teleport xe tới Y đã chọn (mặc định 116)", Callback=function()
        if shiftCarY(nil, carCfg.targetY) then notify("Car", "Đã đưa xe lên Y = " .. carCfg.targetY) end
    end })
    CarTab:Button({ Title="Nâng xe lên +15", Callback=function() shiftCarY(15) end })
    CarTab:Button({ Title="Hạ xe xuống -15", Callback=function() shiftCarY(-15) end })
end

-- ===== v3.1: PLAYERS (teleport dropdown + spectate) + ANTI-ARREST =====
do
    -- ----- Danh sách người chơi -----
    local selected, byLabel, labels = nil, {}, {}
    local dropdown
    local function labelOf(p)
        return string.format("%s [%s]", p.Name, p.Team and p.Team.Name or "?")
    end
    local function rebuild()
        byLabel, labels = {}, {}
        local list = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then list[#list+1] = p end
        end
        table.sort(list, function(a, b) return a.Name:lower() < b.Name:lower() end)
        for _, p in ipairs(list) do
            local l = labelOf(p)
            byLabel[l] = p
            labels[#labels+1] = l
        end
        if selected and not selected.Parent then selected = nil end
    end
    rebuild()
    dropdown = PlayersTab:Dropdown({ Title="Người chơi", Values=labels, Value=labels[1], Callback=function(v)
        local name = type(v) == "table" and v[1] or v
        selected = byLabel[name]
    end })
    selected = labels[1] and byLabel[labels[1]] or nil

    local function refresh()
        local prev = selected
        rebuild()
        pcall(function() dropdown:Refresh(labels) end)
        local keep
        if prev then
            for l, p in pairs(byLabel) do if p == prev then keep = l end end
        end
        if keep then
            selected = prev
            pcall(function() dropdown:Select(keep) end)
        else
            selected = nil
        end
    end
    local pending = false
    local function scheduleRefresh()
        if pending then return end
        pending = true
        task.delay(0.6, function() pending = false; refresh() end)
    end
    track(Players.PlayerAdded:Connect(scheduleRefresh))
    track(Players.PlayerRemoving:Connect(scheduleRefresh))

    PlayersTab:Button({ Title="Làm mới danh sách", Callback=refresh })

    local function step(dir)
        if #labels == 0 then return end
        local idx = 0
        if selected then
            for i, l in ipairs(labels) do if byLabel[l] == selected then idx = i end end
        end
        if idx == 0 then idx = (dir > 0) and 0 or 1 end
        idx = ((idx - 1 + dir) % #labels) + 1
        selected = byLabel[labels[idx]]
        pcall(function() dropdown:Select(labels[idx]) end)
    end
    PlayersTab:Button({ Title="◀ Người trước", Callback=function() step(-1) end })
    PlayersTab:Button({ Title="Người kế tiếp ▶", Callback=function() step(1) end })

    -- ----- Nhập tên để chọn / teleport -----
    local typedName = ""
    local nameInput
    local function findPlayerByName(q)
        q = (q or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if q == "" then return nil end
        local best, bestRank
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                local n, d = p.Name:lower(), p.DisplayName:lower()
                local rank
                if n == q or d == q then rank = 1
                elseif n:sub(1, #q) == q or d:sub(1, #q) == q then rank = 2
                elseif n:find(q, 1, true) or d:find(q, 1, true) then rank = 3 end
                if rank and (not bestRank or rank < bestRank) then best, bestRank = p, rank end
            end
        end
        return best
    end
    local function selectPlayer(p)
        selected = p
        for l, pl in pairs(byLabel) do
            if pl == p then pcall(function() dropdown:Select(l) end) break end
        end
    end
    nameInput = PlayersTab:Input({ Title="Nhập tên người chơi", Desc="Gõ tên hoặc một phần tên (Name/DisplayName) rồi Enter. Người đó sẽ được chọn cho Teleport / Spectate", Placeholder="vd: nimanagua", Value="", Callback=function(text)
        typedName = text or ""
        if typedName == "" then return end
        local p = findPlayerByName(typedName)
        if p then
            selectPlayer(p)
            notify("Đã chọn", p.Name .. " (" .. p.DisplayName .. ")")
        else
            notify("Không tìm thấy", "Không có người chơi khớp \"" .. typedName .. "\"")
        end
    end })
    local function teleportToTyped()
        local q = typedName
        if (q == nil or q == "") and nameInput and nameInput.Value then q = nameInput.Value end
        local p = findPlayerByName(q)
        if not p then notify("Teleport", "Không tìm thấy người chơi \"" .. tostring(q) .. "\"") return end
        local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then notify("Teleport", p.Name .. " chưa có nhân vật") return end
        selectPlayer(p)
        teleportTo(hrp.Position + Vector3.new(0, 0, 3))
    end
    PlayersTab:Button({ Title="Teleport tới tên đã nhập", Callback=teleportToTyped })

    -- ----- Teleport tới người đã chọn -----
    PlayersTab:Button({ Title="Teleport tới người đã chọn", Callback=function()
        local p = selected
        local hrp = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then notify("Teleport", "Chưa chọn người chơi hoặc họ chưa có nhân vật") return end
        teleportTo(hrp.Position + Vector3.new(0, 0, 3))
    end })

    -- ----- Spectate -----
    local specConn
    local function stopSpectate()
        if specConn then specConn:Disconnect(); specConn = nil end
        local cam = workspace.CurrentCamera
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if cam and hum then cam.CameraSubject = hum end
    end
    PlayersTab:Toggle({ Title="Spectate người đã chọn", Desc="Xem camera của người chơi đã chọn; tắt để quay về nhân vật của bạn", Default=false, Callback=function(v)
        state.spectate = v
        stopSpectate()
        if not v then return end
        if not selected then notify("Spectate", "Hãy chọn người chơi trước") return end
        specConn = track(RunService.RenderStepped:Connect(function()
            local p = selected
            if not p or not p.Parent then stopSpectate() return end
            local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
            local cam = workspace.CurrentCamera
            if hum and cam and cam.CameraSubject ~= hum then cam.CameraSubject = hum end
        end))
    end })

    -- ----- Anti-Arrest -----
    local aaCfg = { radius = 25, cooldown = 3, dest = "Roof (Cellblock)", restore = true }
    local aaConn, lastFlee = nil, 0
    state.antiArrest = false
    local destNames = {}
    for _, loc in ipairs(TELEPORT_LOCATIONS) do destNames[#destNames+1] = loc.name end
    local function destPos()
        for _, loc in ipairs(TELEPORT_LOCATIONS) do
            if loc.name == aaCfg.dest then return loc.pos end
        end
    end
    local function cuffsOut(p)
        local t = p.Character and p.Character:FindFirstChild("Handcuffs")
        return t ~= nil and t:IsA("Tool")
    end
    -- chỉ né khi mình thực sự có thể bị bắt (Criminals / Hostile / Trespassing)
    local function atRisk()
        local c = LocalPlayer.Character
        if not c then return false end
        local t = LocalPlayer.Team and LocalPlayer.Team.Name
        return t == "Criminals" or c:GetAttribute("Hostile") == true or c:GetAttribute("Trespassing") == true
    end
    CombatTab:Toggle({ Title="Anti-Arrest (né Guards cầm Handcuffs)", Desc="Khi bạn có thể bị bắt và một Guard đang cầm Handcuffs ở gần, tự teleport tới điểm né", Default=false, Callback=function(v)
        state.antiArrest = v
        if aaConn then aaConn:Disconnect(); aaConn = nil end
        if not v then return end
        local last = 0
        aaConn = track(RunService.Heartbeat:Connect(function()
            if os.clock() - last < 0.1 then return end
            last = os.clock()
            if os.clock() - lastFlee < aaCfg.cooldown then return end
            if (LocalPlayer.Team and LocalPlayer.Team.Name) == "Guards" or not atRisk() then return end
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Team and p.Team.Name == "Guards" and cuffsOut(p) then
                    local ghrp = p.Character:FindFirstChild("HumanoidRootPart")
                    local ghum = p.Character:FindFirstChildOfClass("Humanoid")
                    if ghrp and ghum and ghum.Health > 0 and (ghrp.Position - hrp.Position).Magnitude <= aaCfg.radius then
                        local pos = destPos()
                        if pos then
                            lastFlee = os.clock()
                            hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
                            if hoverTargetY then hoverTargetY = pos.Y + 3 end
                            notify("Anti-Arrest", p.DisplayName .. " cầm Handcuffs, đã né tới " .. aaCfg.dest)
                        end
                        break
                    end
                end
            end
        end))
    end })
    CombatTab:Slider({ Title="Anti-Arrest: khoảng cách báo động (stud)", Step=1, Value={ Min=5, Max=100, Default=aaCfg.radius }, Callback=function(v) aaCfg.radius = v end })
    CombatTab:Dropdown({ Title="Anti-Arrest: điểm né", Values=destNames, Value=aaCfg.dest, Callback=function(v)
        aaCfg.dest = type(v) == "table" and v[1] or v
    end })

    -- ----- Khôi phục di chuyển khi bị còng (hiệu ứng phía client) -----
    local arrestEvt = Remotes and Remotes:FindFirstChild("ClientArrested")
    local baseSpeed, baseJump, restoreUntil = 16, 7.2, 0
    local function myHum() return LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") end
    track(RunService.Heartbeat:Connect(function()
        local h = myHum()
        if h and os.clock() > restoreUntil then
            if h.WalkSpeed > 0.5 then baseSpeed = h.WalkSpeed end
            if h.JumpHeight > 0.5 then baseJump = h.JumpHeight end
        end
    end))
    if arrestEvt then
        track(arrestEvt.OnClientEvent:Connect(function()
            if not aaCfg.restore then return end
            restoreUntil = os.clock() + 20
            notify("Anti-Arrest", "Bị còng, đang khôi phục di chuyển")
        end))
    end
    track(RunService.Stepped:Connect(function()
        if not aaCfg.restore or os.clock() > restoreUntil then return end
        local h = myHum()
        if not h or h.Health <= 0 then return end
        if h.WalkSpeed < baseSpeed then h.WalkSpeed = baseSpeed end
        if h.JumpHeight < baseJump then h.JumpHeight = baseJump end
        LocalPlayer:SetAttribute("BackpackEnabled", true)
    end))
    CombatTab:Toggle({ Title="Khôi phục di chuyển khi bị còng", Desc="Client-only: trả lại WalkSpeed/Jump/Backpack. Server vẫn có thể giữ trạng thái bị bắt", Default=true, Callback=function(v) aaCfg.restore = v end })

    API.stopSpectate = stopSpectate
end

-- ===== SPIN BOT + BUNNY HOP =====
local spinSpeed, spinConn, bhopConn = 720, nil, nil
state.spin, state.bhop = false, false
local function getHum() local c = LocalPlayer.Character return c and c:FindFirstChildOfClass("Humanoid") end
local function stopSpin()
    if spinConn then spinConn:Disconnect(); spinConn = nil end
    local h = getHum(); if h then h.AutoRotate = true end
end
local function stopBhop()
    if bhopConn then bhopConn:Disconnect(); bhopConn = nil end
end
MovementTab:Toggle({ Title="Spin Bot", Desc="Xoay nhân vật liên tục (server thấy bạn xoay). Nên tắt Fly khi dùng", Default=false, Callback=function(v)
    state.spin = v
    stopSpin()
    if not v then return end
    spinConn = track(RunService.Heartbeat:Connect(function(dt)
        local c = LocalPlayer.Character
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        local h = c and c:FindFirstChildOfClass("Humanoid")
        if not hrp or not h or h.Health <= 0 then return end
        h.AutoRotate = false
        hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(spinSpeed) * dt, 0)
    end))
end })
MovementTab:Slider({ Title="Spin Speed (độ/giây)", Step=30, Value={ Min=60, Max=3600, Default=spinSpeed }, Callback=function(v) spinSpeed = v end })
MovementTab:Toggle({ Title="Bunny Hop", Desc="Tự nhảy liên tục khi đang di chuyển", Default=false, Callback=function(v)
    state.bhop = v
    stopBhop()
    if not v then return end
    bhopConn = track(RunService.Heartbeat:Connect(function()
        local h = getHum()
        if not h or h.Health <= 0 or state.fly then return end
        if h.MoveDirection.Magnitude > 0 and h.FloorMaterial ~= Enum.Material.Air then
            h:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end))
end })
API.cleanupMisc = function() stopSpin(); stopBhop(); if API.stopCarFly then API.stopCarFly() end; if API.stopSpectate then API.stopSpectate() end end

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
PickupTab:Paragraph({ Title="Cách hoạt động", Desc="Tp tới item, gửi GiverPressed, rồi tp về. Thông báo ✓/✗ hiện kết quả." })
for _, n in ipairs(FOODS)  do PickupTab:Button({ Title="Lấy "..n, Callback=function() doPickup(n) end }) end
PickupTab:Button({ Title="Lấy tất cả đồ ăn", Callback=function() pickupMany(FOODS) end })
for _, n in ipairs(MELEES) do PickupTab:Button({ Title="Lấy "..n, Callback=function() doPickup(n) end }) end
PickupTab:Button({ Title="Lấy Crude Knife + Hammer", Callback=function() pickupMany(MELEES) end })
local gunNames, seen = {}, {}
do
    local giver = getGiver()
    if giver then
        for _, m in ipairs(giver:GetChildren()) do
            if not isFood[m.Name] and not isMelee[m.Name] and not seen[m.Name] then seen[m.Name]=true; gunNames[#gunNames+1]=m.Name end
        end
        table.sort(gunNames)
    end
end
for _, n in ipairs(gunNames) do PickupTab:Button({ Title="Lấy "..n, Callback=function() doPickup(n) end }) end
PickupTab:Button({ Title="Lấy tất cả súng / đồ", Callback=function() pickupMany(gunNames) end })

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
TeamSwapTab:Paragraph({ Title="Luật đổi team", Desc="Neutral→Inmates/Guards, Guards→Neutral, Criminals→Neutral. Inmates→Criminals bằng Criminals Spawn. Vừa vào Guards chờ ~8 giây." })
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
else killParagraph:SetDesc("Killfeed not found.") end
KillsTab:Button({ Title="Clear Log", Callback=function() killLog={}; renderKills() end })

-- ===== TEAMS =====
local rosterParagraphs = {}
for _, t in ipairs(Teams:GetChildren()) do
    if t:IsA("Team") then rosterParagraphs[t] = TeamsTab:Paragraph({ Title=t.Name, Desc="..." }) end
end
local function updateRoster()
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
local function unload()
    running = false
    state.esp = false; refreshAllESP()
    destroyFOVCircle()
    safe("unload invisible",  setInvisible,   false)
    stopFly()
    if API.cleanupMisc then pcall(API.cleanupMisc) end
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

notify("PrisonHub","v3.1 Loaded ✓")
log("INFO","PrisonHub v3.1 ready")
