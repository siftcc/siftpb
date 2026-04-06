-- ====================================================================
--   Sift.Win  |  Win Playground Basketball  v4.1
--   FIXED: AnimationService removed (not a valid service)
--   UI: Compact tabbed layout — fits any screen, mobile-optimised
-- ====================================================================

local Players              = game:GetService("Players")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local TweenService         = game:GetService("TweenService")
local UserInputService     = game:GetService("UserInputService")
local RunService           = game:GetService("RunService")
local Lighting             = game:GetService("Lighting")
local HttpService          = game:GetService("HttpService")
-- AnimationService is NOT a valid Roblox service — removed.

local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid  = character:WaitForChild("Humanoid")
local animator  = humanoid:FindFirstChildOfClass("Animator")
            or (function()
                local a = Instance.new("Animator"); a.Parent = humanoid; return a
            end)()
local hrp = character:WaitForChild("HumanoidRootPart")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Action  = Remotes:WaitForChild("Server"):WaitForChild("Action")

-- ====================================================================
-- PLATFORM
-- ====================================================================
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local Platform = isMobile and "Mobile"
    or (UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled and "Controller")
    or "PC"
print("[SiftWin] Platform: "..Platform)

-- ====================================================================
-- PALETTE
-- ====================================================================
local C = {
    BG         = Color3.fromRGB(7,  7,  10),
    PANEL      = Color3.fromRGB(12, 12, 18),
    CARD       = Color3.fromRGB(16, 16, 24),
    CARD_ON    = Color3.fromRGB(10, 18, 34),
    HEADER     = Color3.fromRGB(9,  9,  14),
    TAB        = Color3.fromRGB(14, 14, 20),
    TAB_ON     = Color3.fromRGB(0,  80, 200),
    ACCENT     = Color3.fromRGB(0,  130,255),
    ACCENT_DIM = Color3.fromRGB(0,  60, 160),
    TEXT_HI    = Color3.fromRGB(220,225,235),
    TEXT_MID   = Color3.fromRGB(100,108,125),
    TEXT_DIM   = Color3.fromRGB(46, 48, 58),
    TOGGLE_OFF = Color3.fromRGB(26, 26, 36),
    KNOB       = Color3.fromRGB(195,200,212),
    SHOOT_BTN  = Color3.fromRGB(0,  100,230),
    SHOOT_DOWN = Color3.fromRGB(0,  60, 150),
    DIVIDER    = Color3.fromRGB(20, 20, 30),
}

-- ====================================================================
-- STATE
-- ====================================================================
local state = {
    autoGreen=false, infiniteStamina=false, speedBoost=false, 
    manualSpeed=false, velocityBoost=false, antiLag=false, dribbleSpeedBoost = false,
    autoSprint=false, customFeedback=false, dribbleMacro=false, instantSpin = false,
    antiOOB=false, autoBlock=false, animSpeedBoost=false, hipHeightBoost = false,
    autoGuard=false, antiAnkleBreak=false, antiStun=false, hipHeightAmount = 0.3,
    antiContest=false, blowByBoost=false, autoCrossover = false,
}
local vfxHue        = 210
local manualSpeedVal = 16
local blockRange    = 12
local blockFOV      = 90
local blockDelayMs  = 150

-- ====================================================================
-- ====================================================================
-- SETTINGS SAVE/LOAD (uses writefile/readfile if available)
-- ====================================================================
local SETTINGS_FILE = "SiftWinSettings.json"

local function saveSettings()
if not container then return end
    local settings = {
        position = {X = container and container.Position.X.Offset or 0, Y = container and container.Position.Y.Offset or 0},
        toggles = {},
        sliders = {
            manualSpeedVal = manualSpeedVal,
            blockRange = blockRange,
            blockFOV = blockFOV,
            blockDelayMs = blockDelayMs,
            GUARD_DISTANCE = GUARD_DISTANCE,
            vfxHue = vfxHue,
        }
    }
    for k, v in pairs(state) do
        settings.toggles[k] = v
    end
    local success, encoded = pcall(HttpService.JSONEncode, HttpService, settings)
    if success and encoded then
        pcall(writefile, SETTINGS_FILE, encoded)
    end
end

local function loadSettings()
    local success, data = pcall(readfile, SETTINGS_FILE)
    if not success or not data then return end
    local decoded = HttpService:JSONDecode(data)
    if not decoded then return end
    -- Apply toggles
    if decoded.toggles then
        for k, v in pairs(decoded.toggles) do
            if state[k] ~= nil then state[k] = v end
        end
    end
    -- Apply sliders
    if decoded.sliders then
        manualSpeedVal = decoded.sliders.manualSpeedVal or manualSpeedVal
        blockRange = decoded.sliders.blockRange or blockRange
        blockFOV = decoded.sliders.blockFOV or blockFOV
        blockDelayMs = decoded.sliders.blockDelayMs or blockDelayMs
        GUARD_DISTANCE = decoded.sliders.GUARD_DISTANCE or GUARD_DISTANCE
        vfxHue = decoded.sliders.vfxHue or vfxHue
    end
    -- UI position will be applied after container is created
    return decoded.position
end

-- HSV
-- ====================================================================
local function hsvToRgb(h,s,v)
    h=h/360
    local i=math.floor(h*6); local f=h*6-i
    local p,q,t2=v*(1-s),v*(1-f*s),v*(1-(1-f)*s)
    local r,g,b
    local m=i%6
    if m==0 then r,g,b=v,t2,p elseif m==1 then r,g,b=q,v,p
    elseif m==2 then r,g,b=p,v,t2 elseif m==3 then r,g,b=p,q,v
    elseif m==4 then r,g,b=t2,p,v else r,g,b=v,p,q end
    return Color3.fromRGB(math.floor(r*255),math.floor(g*255),math.floor(b*255))
end
local function getVfxColor(br)
    return hsvToRgb(vfxHue,0.9,math.clamp(0.4+br*0.6,0,1))
end

-- ====================================================================
-- AUTO GREEN
-- ====================================================================
local TIMINGS,scores,shotLog={},{},{}
local AG_MIN,AG_MAX,AG_STEP=0.4111,0.4144,0.001
do local t=AG_MIN
    while t<=AG_MAX+0.00001 do
        table.insert(TIMINGS,math.floor(t*10000+0.5)/10000); t=t+AG_STEP
    end
end
for _,t in ipairs(TIMINGS) do scores[t]=0; shotLog[t]={} end
for _,p in ipairs({0.4233,0.4253}) do if scores[p]~=nil then scores[p]=10 end end

local shotCount,agBusy,exploreCounter=0,false,0
local S_PERFECT,S_100,S_95,S_85,S_70,S_MISS=12,10,7,4,1,-6

local function agStart()  Action:FireServer(unpack({{Shoot=true, Type="Shoot",HoldingQ=false,HoldingL1=false}})) end
local function agRelease() Action:FireServer(unpack({{Shoot=false,Type="Shoot"}})) end

local function readResult()
    local pg=player:FindFirstChild("PlayerGui"); if not pg then return nil,nil end
    local pct,label=nil,nil
    for _,obj in ipairs(pg:GetDescendants()) do
        if obj:IsA("TextLabel") then
            local t=obj.Text or ""
            local p=t:match("Shot Percentage:%s*(%d+%.?%d*)%%"); if p then pct=tonumber(p) end
            local up=t:upper()
            if up=="EARLY" then label="EARLY" elseif up=="LATE" then label="LATE"
            elseif up=="GREEN" then label="GREEN" elseif up=="PERFECT" or up=="CHICKEN!" then label="PERFECT" end
        end
    end
    return pct,label
end

local function recordResult(used,pct,label)
    if not pct then return end
    local s=(label=="PERFECT") and S_PERFECT or (pct>=100) and S_100 or (pct>=95) and S_95
          or (pct>=85) and S_85 or (pct>=70) and S_70 or S_MISS
    local lg=shotLog[used]
    if lg then
        table.insert(lg,s); if #lg>8 then table.remove(lg,1) end
        local tot,wt=0,0
        for i,v in ipairs(lg) do tot=tot+v*i; wt=wt+i end
        scores[used]=wt>0 and tot/wt or 0
    end
    print(string.format("[AG] #%d | %.4fs | %s%% | %s",shotCount,used,tostring(pct),tostring(label)))
end

local function pickTiming()
    exploreCounter=exploreCounter+1
    if exploreCounter%12==0 then
        local c={} for _,t in ipairs(TIMINGS) do if #shotLog[t]<3 then table.insert(c,t) end end
        if #c>0 then return c[math.random(1,#c)] end
    end
    local ranked={}
    for _,t in ipairs(TIMINGS) do table.insert(ranked,{t=t,s=scores[t]}) end
    table.sort(ranked,function(a,b) return a.s>b.s end)
    local pool,wts,total={},{5,4,3,2,1},0
    for i=1,math.min(5,#ranked) do table.insert(pool,ranked[i].t); total=total+wts[i] end
    local r,acc=math.random()*total,0
    for i,t in ipairs(pool) do acc=acc+wts[i]; if r<=acc then return t end end
    return pool[1]
end

local DRIB_NAMES={"SpeedBoostLeft","SpeedBoostRight","Crossover","Hesitation","SpinMove","BehindBack",
    "HalfSpin","Snatchback","MovingCrossover","Combo","AnkleBreaker01","AnkleBreaker02",
    "AnkleBreaker03","AnkleBreaker05","AnkleBreaker06","BlowByLeft","BlowByRight"}
local function dribPlaying()
    for _,tr in ipairs(animator:GetPlayingAnimationTracks()) do
        for _,n in ipairs(DRIB_NAMES) do if tr.Name:lower():find(n:lower()) then return true,tr end end
    end return false
end
local function waitDribEnd()
    local w=0 while w<0.35 do
        local ok,tr=dribPlaying(); if not ok then return end
        if tr and tr.Length>0 and (tr.Length-tr.TimePosition)<0.12 then return end
        local dt=RunService.Heartbeat:Wait(); w=w+dt
    end
end

local function executeShot()
    if not state.autoGreen or agBusy then return end
    agBusy=true; shotCount=shotCount+1
    local used=pickTiming()
    if character:GetAttribute("Action")=="Dribbling" then waitDribEnd() end
    agRelease(); task.wait(0.04); agStart()
    local t0=os.clock(); local coarse=used-0.003
    if coarse>0 then task.wait(coarse) end
    while(os.clock()-t0)<used do end
    agRelease(); task.wait(0.40)
    local pct,label=readResult(); recordResult(used,pct,label)
    task.wait(0.22); agBusy=false
end

-- List of random PNG asset IDs (replace with your own)
local RANDOM_PNG_IDS = {
    "rbxassetid://85822546904397",  -- example star
    "rbxassetid://6031094597",  -- example burst
    "rbxassetid://10147220411", -- example glow
    "rbxassetid://9125469473",  -- example impact
}
-- Function to show a random PNG effect on screen
local function showRandomPNGEffect()
    local pngUrl = RANDOM_PNG_IDS[math.random(1, #RANDOM_PNG_IDS)]
    local gui = Instance.new("ScreenGui")
    gui.Name = "CustomGreenVFX"
    gui.ResetOnSpawn = false
    gui.Parent = player:WaitForChild("PlayerGui")
    
    local img = Instance.new("ImageLabel")
    img.Size = UDim2.new(0, 120, 0, 120)
    img.Position = UDim2.new(0.5, -60, 0.5, -60)
    img.AnchorPoint = Vector2.new(0.5, 0.5)
    img.BackgroundTransparency = 1
    img.Image = pngUrl
    img.ImageTransparency = 0
    img.ZIndex = 20
    img.Parent = gui
    
    -- Animate: grow and fade out
    local startSize = UDim2.new(0, 40, 0, 40)
    local endSize = UDim2.new(0, 200, 0, 200)
    img.Size = startSize
    
    local grow = TweenService:Create(img, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = endSize})
    local fade = TweenService:Create(img, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {ImageTransparency = 1})
    
    grow:Play()
    grow.Completed:Connect(function()
        fade:Play()
        fade.Completed:Connect(function()
            gui:Destroy()
        end)
    end)
    
    -- Optional: slight rotation
    local rotate = TweenService:Create(img, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Rotation = 30})
    rotate:Play()
end


ContextActionService:BindActionAtPriority("SiftWinShoot",function(_,st,_)
    if st==Enum.UserInputState.Begin then task.spawn(executeShot) end
    return state.autoGreen and Enum.ContextActionResult.Sink or Enum.ContextActionResult.Pass
end,false,2000,Enum.KeyCode.E,Enum.KeyCode.ButtonB,Enum.KeyCode.ButtonX)

-- ====================================================================
-- ====================================================================
-- VFX + GLOW
-- ====================================================================
local function recolour(inst)
    for _,v in ipairs(inst:GetDescendants()) do
        if v:IsA("ParticleEmitter") then
            local ks={}
            for _,kp in ipairs(v.Color.Keypoints) do
                local br=kp.Value.R*0.299+kp.Value.G*0.587+kp.Value.B*0.114
                table.insert(ks,ColorSequenceKeypoint.new(kp.Time,getVfxColor(br)))
            end
            if #ks>=2 then pcall(function() v.Color=ColorSequence.new(ks) end) end
        elseif v:IsA("PointLight") or v:IsA("SpotLight") then
            pcall(function() v.Color=hsvToRgb(vfxHue,0.8,1) end)
        elseif v:IsA("Trail") then
            local ks={}
            for _,kp in ipairs(v.Color.Keypoints) do
                local br=kp.Value.R*0.299+kp.Value.G*0.587+kp.Value.B*0.114
                table.insert(ks,ColorSequenceKeypoint.new(kp.Time,getVfxColor(br)))
            end
            if #ks>=2 then pcall(function() v.Color=ColorSequence.new(ks) end) end
        end
    end
end

local function syncGlow()
    for _,obj in ipairs(character:GetDescendants()) do
        if obj.Name=="Glow_Outline" and obj:IsA("ParticleEmitter") then
            local col=hsvToRgb(vfxHue,0.85,1)
            pcall(function() obj.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,col),ColorSequenceKeypoint.new(1,col)}) end)
            pcall(function() obj.LightEmission=1 end)
        end
    end
end

local function applyVfx()
    task.spawn(function()
        local a=ReplicatedStorage:FindFirstChild("Assets")
        if a then local v=a:FindFirstChild("VFX"); if v then recolour(v) end end
        recolour(character); syncGlow()
    end)
end

-- ========== NEW: Attach PNG to ball / hoop / player ==========
-- Find the basketball in the workspace
local function findBall()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name:lower():find("ball") then
            -- Ignore balls that are welded to a player (being held)
            if not obj:FindFirstChild("WeldConstraint") then
                return obj
            end
        end
    end
    return nil
end

-- Find the hoop (rim)
local function findHoop()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and (obj.Name:lower():find("rim") or obj.Name:lower():find("hoop")) then
            return obj
        end
    end
    return nil
end

-- Attach a PNG image to a part (BillboardGui)
local function attachPNGToPart(part, pngUrl, duration)
    duration = duration or 0.6
    if not part or not part.Parent then return end
    
    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 100, 0, 100)
    billboard.StudsOffset = Vector3.new(0, 1.5, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = part
    
    local img = Instance.new("ImageLabel")
    img.Size = UDim2.new(1, 0, 1, 0)
    img.BackgroundTransparency = 1
    img.Image = pngUrl
    img.ImageTransparency = 0
    img.Parent = billboard
    
    -- Animate: grow + rotate + fade
    local startSize = UDim2.new(0.3, 0, 0.3, 0)
    local endSize = UDim2.new(1.2, 0, 1.2, 0)
    img.Size = startSize
    
    local grow = TweenService:Create(img, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = endSize})
    local fade = TweenService:Create(img, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {ImageTransparency = 1})
    local rotate = TweenService:Create(img, TweenInfo.new(0.3, Enum.EasingStyle.Linear), {Rotation = 180})
    
    grow:Play()
    rotate:Play()
    grow.Completed:Connect(function()
        fade:Play()
        fade.Completed:Connect(function()
            billboard:Destroy()
        end)
    end)
    
    -- Auto-destroy after duration (safety)
    task.wait(duration)
    if billboard and billboard.Parent then
        billboard:Destroy()
    end
end
-- ==============================================================

task.spawn(function()
    task.wait(2); applyVfx()
    local a = ReplicatedStorage:FindFirstChild("Assets")
    if a then
        local vf = a:FindFirstChild("VFX")
        if vf then
            vf.DescendantAdded:Connect(function(d)
                task.defer(function() recolour(d); syncGlow() end)
            end)
        end
    end
    
    -- GREEN VFX: attach PNG to ball/hoop/player instead of screen popup
    local ge = Remotes:FindFirstChild("GreenVfx")
    if not ge then
        for _, v in ipairs(Remotes:GetDescendants()) do
            if v.Name:lower():find("green") and v:IsA("RemoteEvent") then
                ge = v
                break
            end
        end
    end
    
    if ge then
        ge.OnClientEvent:Connect(function()
            task.wait(0.05)
            
            -- Pick a random PNG from your existing list
            local pngUrl = RANDOM_PNG_IDS[math.random(1, #RANDOM_PNG_IDS)]
            
            -- Try to attach to the ball first (made basket)
            local ball = findBall()
            if ball then
                attachPNGToPart(ball, pngUrl, 0.6)
            else
                -- No ball found → attach to hoop (swish)
                local hoop = findHoop()
                if hoop then
                    attachPNGToPart(hoop, pngUrl, 0.6)
                else
                    -- Fallback: attach to player's head (personal green)
                    local head = character:FindFirstChild("Head")
                    if head then
                        attachPNGToPart(head, pngUrl, 0.6)
                    else
                        -- Ultimate fallback: screen GUI (your old method)
                        showRandomPNGEffect()
                    end
                end
            end
            
            -- Keep the character glow (optional)
            syncGlow()
        end)
    end
    
    -- Keep the periodic glow refresh
    while true do
        task.wait(3)
        syncGlow()
    end
end)

-- ====================================================================
-- FEATURES
-- ====================================================================
local staminaConn,sprintConn,sbConn1,sbConn2,sbAutoConn=nil,nil,nil,nil,nil
local manualSpeedConn,velConn,feedbackConn,autoBlockConn,animSpeedConn=nil,nil,nil,nil,nil
local guardConn,ankleConn,antiStunConn,blowByConn,antiContestConn=nil,nil,nil,nil,nil
local oobConn1,oobConn2,lastSafePos,oobPartRefs={},{},nil,{}
local macroActive,sbLastTap=false,0 
local blockCooldown = 0
local lagOriginals={}

local function enableInfiniteStamina()
    pcall(function() character:SetAttribute("Stamina",100) end)
    staminaConn=RunService.Heartbeat:Connect(function()
        local c=character:GetAttribute("Stamina"); if c and c<98 then character:SetAttribute("Stamina",100) end
        local h=character:FindFirstChild("Head"); if h then local sw=h:FindFirstChild("Sweat"); if sw then sw.Enabled=false end end
    end)
end
local function disableInfiniteStamina() if staminaConn then staminaConn:Disconnect();staminaConn=nil end end

local function enableAutoSprint()
    Action:FireServer(unpack({{Sprinting=true,Type="Sprint"}}))
    task.spawn(function() while state.autoSprint do Action:FireServer(unpack({{Sprinting=true,Type="Sprint"}}));task.wait(0.28) end end)
end
local function disableAutoSprint() if sprintConn then sprintConn:Disconnect();sprintConn=nil end Action:FireServer(unpack({{Sprinting=false,Type="Sprint"}})) end

local function fireSpeedBoost()
    if character:GetAttribute("FinishDribble") or character:GetAttribute("Action")=="Dribbling" then
        local last=character:GetAttribute("LastDribbleName")
        if last=="SpeedBoostLeft" or last=="SpeedBoostRight" then return end
        if character:GetAttribute("Action")=="Dribbling" then task.wait(0.08) end
        local keys=character:GetAttribute("Hand")=="L" and "SPEEDBOOSTL" or "SPEEDBOOSTR"
        Action:FireServer({Type="Dribble",Keys=keys})
    end
end
local function enableSpeedBoost()
    sbConn1=UserInputService.InputBegan:Connect(function(p,gp) if gp then return end
        if p.KeyCode==Enum.KeyCode.LeftShift or p.KeyCode==Enum.KeyCode.ButtonR2 then sbLastTap=tick() end end)
    sbConn2=UserInputService.InputEnded:Connect(function(p,gp) if gp then return end
        if (p.KeyCode==Enum.KeyCode.LeftShift or p.KeyCode==Enum.KeyCode.ButtonR2) and sbLastTap then
            if tick()-sbLastTap<=0.25 then task.spawn(fireSpeedBoost) end; sbLastTap=tick() end end)
    sbAutoConn=RunService.Heartbeat:Connect(function()
        if not state.speedBoost then return end
        if character:GetAttribute("Action")=="Dribbling" then
            if tick()-sbLastTap>0.55 then sbLastTap=tick(); task.spawn(fireSpeedBoost) end end end)
end
local function disableSpeedBoost()
    if sbConn1 then sbConn1:Disconnect();sbConn1=nil end
    if sbConn2 then sbConn2:Disconnect();sbConn2=nil end
    if sbAutoConn then sbAutoConn:Disconnect();sbAutoConn=nil end
end
local autoCrossoverConn = nil
local lastCrossoverTime = 0
local function enableAutoCrossover()
    if autoCrossoverConn then autoCrossoverConn:Disconnect() end
    autoCrossoverConn = RunService.Heartbeat:Connect(function()
        if not state.autoCrossover then return end
        if character:GetAttribute("Action") ~= "Dribbling" then return end
        if not character:GetAttribute("Sprinting") then return end
        
        -- Cooldown: random between 2 and 4 seconds
        if tick() - lastCrossoverTime < (math.random(20, 40) / 10) then return end
        
        -- Avoid spamming if last dribble was already a crossover
        local lastDrib = character:GetAttribute("LastDribbleName") or ""
        if lastDrib:lower():find("crossover") then return end
        
        -- Find nearest opponent
        local myPos = hrp.Position
        local nearestDist = math.huge
        for _, other in ipairs(Players:GetPlayers()) do
            if other ~= player then
                local char = other.Character
                if char and char.Parent then
                    local root = char:FindFirstChild("HumanoidRootPart")
                    if root then
                        local dist = (root.Position - myPos).Magnitude
                        if dist < nearestDist then nearestDist = dist end
                    end
                end
            end
        end
        
        -- Only crossover if no defender within 12 studs (open space)
        -- Or if moving away from the closest defender (optional)
        if nearestDist > 12 then
            lastCrossoverTime = tick()
            Action:FireServer({Type = "Dribble", Keys = "CX"})
        end
    end)
end
local function disableAutoCrossover()
    if autoCrossoverConn then
        autoCrossoverConn:Disconnect()
        autoCrossoverConn = nil
    end
end


local dribSpeedBoostConn = nil
local DRIBBLE_SPEED_OVERRIDE = 22
local lastSpeedBoostTime = 0

local instantSpinConn = nil
local lastSpinTime = 0
local function enableInstantSpin()
    if instantSpinConn then instantSpinConn:Disconnect() end
    instantSpinConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if not state.instantSpin then return end
        if input.KeyCode == Enum.KeyCode.Q then
            if character:GetAttribute("Action") == "Dribbling" then
                if tick() - lastSpinTime > 0.5 then
                    lastSpinTime = tick()
                    -- Try both spin keys
                    pcall(function() Action:FireServer({Type = "Dribble", Keys = "CXZ"}) end)
                    task.wait(0.05)
                    pcall(function() Action:FireServer({Type = "Dribble", Keys = "ZXC"}) end)
                end
            end
        end
    end)
end
local function enableManualSpeed()
    manualSpeedConn=RunService.Heartbeat:Connect(function()
        if not state.manualSpeed then return end
        local a=character:GetAttribute("Action")
        if (a=="" or a=="Dribbling") and not character:GetAttribute("Stunned") then
            humanoid.WalkSpeed=math.clamp(manualSpeedVal,0,30) end end)
end
local function disableManualSpeed() if manualSpeedConn then manualSpeedConn:Disconnect();manualSpeedConn=nil end; humanoid.WalkSpeed=16 end

local function enableVelocityBoost()
    local bv=hrp:FindFirstChild("BodyVelocity")
    if not bv then bv=Instance.new("BodyVelocity"); bv.MaxForce=Vector3.new(0,0,0); bv.Velocity=Vector3.new(0,0,0); bv.Parent=hrp end
    velConn=character:GetAttributeChangedSignal("Velocity"):Connect(function()
        local action=character:GetAttribute("Action")
        local raw=character:GetAttribute("Velocity") or Vector3.new(0,0,0)
        local str=tostring(raw); local vel=(str:find("nan") or str:find("inf")) and Vector3.new(0,0,0) or raw
        local boosted=vel*1.53
        if vel==Vector3.new(0,0,0) then TweenService:Create(bv,TweenInfo.new(0.38,Enum.EasingStyle.Sine),{Velocity=Vector3.new(0,0,0),MaxForce=Vector3.new(0,0,0)}):Play()
        elseif action=="Dribbling" then bv.MaxForce=Vector3.new(99999,0,99999); bv.Velocity=boosted
        else TweenService:Create(bv,TweenInfo.new(0.515,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),{Velocity=boosted,MaxForce=Vector3.new(89999,0,89999)}):Play() end
    end)
end
local function disableVelocityBoost()
    if velConn then velConn:Disconnect();velConn=nil end
    local bv=hrp:FindFirstChild("BodyVelocity"); if bv then bv.MaxForce=Vector3.new(0,0,0); bv.Velocity=Vector3.new(0,0,0) end
end

local function enableAntiLag()
    lagOriginals.GS=Lighting.GlobalShadows; lagOriginals.SS=Lighting.ShadowSoftness; lagOriginals.FE=Lighting.FogEnd
    Lighting.GlobalShadows=false; Lighting.ShadowSoftness=0; Lighting.FogEnd=9999
    for _,v in ipairs(Lighting:GetChildren()) do if v:IsA("PostEffect") then lagOriginals["PE"..v.Name]=v.Enabled; v.Enabled=false end end
    for _,v in ipairs(workspace:GetDescendants()) do if v:IsA("ParticleEmitter") then local k="PR"..tostring(v); if not lagOriginals[k] then lagOriginals[k]=v.Rate end; v.Rate=math.floor(v.Rate*0.3) end end
    pcall(function() settings().Rendering.QualityLevel=1 end)
end
local function disableAntiLag()
    Lighting.GlobalShadows=lagOriginals.GS~=nil and lagOriginals.GS or true
    Lighting.ShadowSoftness=lagOriginals.SS~=nil and lagOriginals.SS or 0.5
    Lighting.FogEnd=lagOriginals.FE~=nil and lagOriginals.FE or 100000
    for _,v in ipairs(Lighting:GetChildren()) do if v:IsA("PostEffect") then local o=lagOriginals["PE"..v.Name]; if o~=nil then v.Enabled=o end end end
    for _,v in ipairs(workspace:GetDescendants()) do if v:IsA("ParticleEmitter") then local o=lagOriginals["PR"..tostring(v)]; if o then v.Rate=o end end end
    pcall(function() settings().Rendering.QualityLevel=Enum.QualityLevel.Automatic end)
end

local FEEDBACK_COLORS={["VERY EARLY"]={255,60,60},["SLIGHTLY EARLY"]={255,200,50},["EARLY"]={255,140,30},["SLIGHTLY LATE"]={255,200,50},["LATE"]={255,140,30},["VERY LATE"]={255,60,60},["GOOD"]={180,190,210},["PERFECT"]={0,160,255},["CHICKEN!"]={0,200,255}}
local CONTEST_COLORS={["SUFFOCATED"]={255,50,50},["HEAVILY CONTESTED"]={255,50,50},["CONTESTED"]={255,140,30},["LIGHTLY CONTESTED"]={255,220,60},["OPEN"]={180,190,210},["WIDE OPEN"]={0,160,255}}
local function rgb3(t) return Color3.fromRGB(t[1],t[2],t[3]) end
local function enableCustomFeedback()
    feedbackConn=character:GetAttributeChangedSignal("ShotFeedback"):Connect(function()
        if not state.customFeedback then return end
        task.spawn(function()
            local raw=character:GetAttribute("ShotFeedback"); if not raw then return end
            local ok,data=pcall(function() return HttpService:JSONDecode(raw) end); if not ok or not data then return end
            local tl=tostring(data.Timing or ""); local cl=tostring(data.Contest or ""); local sp=data.ShotPercentage or 0
            if tl=="DEFAULT" then return end
            local shooter=workspace:FindFirstChild(tostring(data.Shooter or ""))
            if shooter then local w=0; while not shooter:GetAttribute("Released") and w<2 do local dt=RunService.Heartbeat:Wait(); w=w+dt end end
            local isGreen=shooter and shooter:GetAttribute("Green") or false
            task.wait(0.15)
            local pg=player:FindFirstChild("PlayerGui"); if not pg then return end
            for _,obj in ipairs(pg:GetDescendants()) do
                if obj.Name=="ShotFeedbackFrame" then
                    local display=(isGreen or tl:upper()=="PERFECT") and "CHICKEN!" or tl
                    local tCol=rgb3(FEEDBACK_COLORS[display:upper()] or FEEDBACK_COLORS[tl:upper()] or {180,190,210})
                    pcall(function()
                        local rel=obj:FindFirstChild("Release")
                        if rel then local tl2=rel:FindFirstChild("Timing"); if tl2 then tl2.Text=display:upper(); tl2.TextColor3=tCol end
                            local il=rel:FindFirstChild("ImageLabel"); if il then il.ImageColor3=tCol end end
                        local cf=obj:FindFirstChild("Contest")
                        if cf then local cl2=cf:FindFirstChild("Contest"); local cCol=rgb3(CONTEST_COLORS[cl:upper()] or {180,190,210})
                            if cl2 then cl2.TextColor3=cCol end end
                    end)
                    local spf=obj.Parent and obj.Parent:FindFirstChild("ShotPercentage")
                    if spf then
                        local pct=tonumber(tostring(sp):match("(%d+%.?%d*)")) or 0
                        local pCol=pct<=55 and Color3.fromRGB(255,60,60) or pct<=70 and Color3.fromRGB(255,140,30) or pct<=80 and Color3.fromRGB(255,220,60) or Color3.fromRGB(0,160,255)
                        pcall(function() local h=spf:FindFirstChild("Header"); if h then h.TextColor3=pCol end end)
                    end; break
                end
            end
        end)
    end)
end
local function disableCustomFeedback() if feedbackConn then feedbackConn:Disconnect();feedbackConn=nil end end

local MACRO_SEQ={{keys="ZC",delay=0.55},{keys="CZ",delay=0.50},{keys="SPEEDBOOST",delay=0.45},{keys="ZC",delay=0.55},{keys="XX",delay=0.60},{keys="SPEEDBOOST",delay=0.45},{keys="CZ",delay=0.50},{keys="X",delay=0.55},{keys="VV",delay=0.65},{keys="SPEEDBOOST",delay=0.45}}
local function fireDrib(keys)
    if keys=="SPEEDBOOST" then if character:GetAttribute("Action")=="Dribbling" then local last=character:GetAttribute("LastDribbleName"); if last~="SpeedBoostLeft" and last~="SpeedBoostRight" then local k=character:GetAttribute("Hand")=="L" and "SPEEDBOOSTL" or "SPEEDBOOSTR"; Action:FireServer(unpack({{Type="Dribble",Keys=k}})) end end
    else Action:FireServer(unpack({{Keys=keys,Type="Dribble"}})) end
end
local function enableDribbleMacro() macroActive=true
    task.spawn(function() local idx=1; while macroActive do if character:GetAttribute("Action")=="Dribbling" then local m=MACRO_SEQ[idx]; task.spawn(function() fireDrib(m.keys) end); task.wait(m.delay); idx=(idx%#MACRO_SEQ)+1 else task.wait(0.1) end end end)
end
local function disableDribbleMacro() macroActive=false end

local function enableAntiOOB()
    lastSafePos=hrp.Position
    oobPartRefs={}; for _,v in ipairs(workspace:GetDescendants()) do if v:IsA("BasePart") and (v.Name=="Out of Bounds" or v.Name:lower():find("outofbounds")) then pcall(function() v.CanTouch=false end); table.insert(oobPartRefs,v) end end
    oobConn1=RunService.Heartbeat:Connect(function()
        if not state.antiOOB then return end; local pos=hrp.Position; local onOOB=false
        for _,part in ipairs(oobPartRefs) do if part and part.Parent then local lp=part.CFrame:PointToObjectSpace(pos); local s=part.Size
            if math.abs(lp.X)<s.X/2+1.5 and math.abs(lp.Y)<s.Y/2+3 and math.abs(lp.Z)<s.Z/2+1.5 then onOOB=true;break end end end
        if onOOB then if lastSafePos then hrp.CFrame=CFrame.new(lastSafePos+Vector3.new(0,3,0)) end
        elseif hrp.Velocity.Y>-8 then lastSafePos=pos end end)
    oobConn2=workspace.DescendantAdded:Connect(function(obj) if obj:IsA("BasePart") and obj.Name=="Out of Bounds" then pcall(function() obj.CanTouch=false end); table.insert(oobPartRefs,obj) end end)
end
local function disableAntiOOB()
    for _,p in ipairs(oobPartRefs) do pcall(function() p.CanTouch=true end) end; oobPartRefs={}
    if oobConn1 then oobConn1:Disconnect();oobConn1=nil end; if oobConn2 then oobConn2:Disconnect();oobConn2=nil end
end

local function enableAutoBlock()
    if autoBlockConn then autoBlockConn:Disconnect() end
    autoBlockConn = RunService.Heartbeat:Connect(function()
        if not state.autoBlock then return end
        
        -- Cooldown check (uses blockDelayMs slider)
        if tick() - blockCooldown < (blockDelayMs / 1000) then return end
        
        local myPos = hrp.Position
        local myLook = hrp.CFrame.LookVector
        
        for _, other in ipairs(Players:GetPlayers()) do
            if other ~= player then
                local char = other.Character
                if char and char.Parent then
                    local action = char:GetAttribute("Action")
                    -- Only block shooting or dunking opponents
                    if action == "Shooting" or action == "Dunking" then
                        local root = char:FindFirstChild("HumanoidRootPart")
                        if root then
                            local diff = root.Position - myPos
                            local dist = diff.Magnitude
                            if dist <= blockRange then
                                local dot = myLook:Dot(diff.Unit)
                                local angle = math.deg(math.acos(math.clamp(dot, -1, 1)))
                                if angle <= blockFOV / 2 then
                                    blockCooldown = tick()
                                    
                                    -- Optional: lunge toward shooter (improves block range)
                                    local dir = diff.Unit
                                    local bv = hrp:FindFirstChild("BodyVelocity")
                                    if not bv then
                                        bv = Instance.new("BodyVelocity")
                                        bv.MaxForce = Vector3.new(0,0,0)
                                        bv.Parent = hrp
                                    end
                                    bv.MaxForce = Vector3.new(50000,0,50000)
                                    bv.Velocity = dir * 18
                                    task.delay(0.15, function()
                                        if bv then
                                            TweenService:Create(bv, TweenInfo.new(0.2), {Velocity=Vector3.new(0,0,0), MaxForce=Vector3.new(0,0,0)}):Play()
                                        end
                                    end)
                                    
                                    -- Send block remote (try both formats; uncomment the one that works)
                                    pcall(function() Action:FireServer({Type = "Block"}) end)
                                    -- Alternative: pcall(function() Action:FireServer({Action = "Block"}) end)
                                    
                                    break -- only block one shooter per frame
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end

local function disableAutoBlock()
    if autoBlockConn then
        autoBlockConn:Disconnect()
        autoBlockConn = nil
    end
    -- Reset any lingering BodyVelocity
    local bv = hrp:FindFirstChild("BodyVelocity")
    if bv then
        bv.MaxForce = Vector3.new(0,0,0)
        bv.Velocity = Vector3.new(0,0,0)
    end
end
local ANIM_SPEED_MULT=1.35
local function enableAnimSpeedBoost()
    animSpeedConn=RunService.Heartbeat:Connect(function()
        if not state.animSpeedBoost then return end
        for _,tr in ipairs(animator:GetPlayingAnimationTracks()) do if tr.Speed>0 then pcall(function() tr:AdjustSpeed(ANIM_SPEED_MULT) end) end end end)
end
local function disableAnimSpeedBoost() if animSpeedConn then animSpeedConn:Disconnect();animSpeedConn=nil end
    for _,tr in ipairs(animator:GetPlayingAnimationTracks()) do pcall(function() tr:AdjustSpeed(1) end) end end

-- Configurable guard distance (in studs)
-- Configurable guard distance (studs)
local GUARD_DISTANCE = 25

local function enableAutoGuard()
    if guardConn then guardConn:Disconnect() end
    
    guardConn = RunService.Heartbeat:Connect(function()
        if not state.autoGuard then return end
        
        local myPos = hrp.Position
        local nearestPlayer = nil
        local nearestDist = math.huge
        
        for _, other in ipairs(Players:GetPlayers()) do
            if other ~= player then
                local char = other.Character
                if char and char.Parent then
                    -- Detect ball possession
                    local hasBall = false
                    if char:FindFirstChild("Ball") then
                        hasBall = true
                    elseif char:GetAttribute("HasBall") == true then
                        hasBall = true
                    elseif char:GetAttribute("Action") == "Dribbling" then
                        hasBall = true
                    end
                    
                    if hasBall then
                        local root = char:FindFirstChild("HumanoidRootPart")
                        if root then
                            local dist = (root.Position - myPos).Magnitude
                            if dist < GUARD_DISTANCE and dist < nearestDist then
                                nearestDist = dist
                                nearestPlayer = other.Name
                            end
                        end
                    end
                end
            end
        end
        
        -- Send guard command (try these two formats – uncomment the working one)
        if nearestPlayer then
            -- Format 1 (most common)
            pcall(function() Action:FireServer({Action = "Guard", Guard = true, Guarding = nearestPlayer}) end)
            -- Format 2 (alternative)
            -- pcall(function() Action:FireServer({Type = "Guard", Guarding = nearestPlayer}) end)
        else
            -- Stop guarding
            pcall(function() Action:FireServer({Action = "Guard", Guard = false}) end)
            -- pcall(function() Action:FireServer({Type = "Guard", Guarding = ""}) end)
        end
    end)
end

local function disableAutoGuard()
    if guardConn then
        guardConn:Disconnect()
        guardConn = nil
    end
    pcall(function() Action:FireServer({Action = "Guard", Guard = false}) end)
end

local ANKLE_ANIMS={"AnkleBreaker01","AnkleBreaker02","AnkleBreaker03","AnkleBreaker05","AnkleBreaker06"}
local function enableAntiAnkleBreak()
    ankleConn=animator.AnimationPlayed:Connect(function(tr)
        if not state.antiAnkleBreak then return end
        for _,n in ipairs(ANKLE_ANIMS) do if tr.Name==n or tr.Name:find(n) then pcall(function() tr:Stop(0) end); pcall(function() Action:FireServer(unpack({{Type="AnkleBreakRecover"}})) end); break end end end)
end
local function disableAntiAnkleBreak() if ankleConn then ankleConn:Disconnect();ankleConn=nil end end

local function enableAntiStun()
    if antiStunConn then antiStunConn:Disconnect() end
    antiStunConn = RunService.Heartbeat:Connect(function()
        if not state.antiStun then return end
        pcall(function()
            -- Clear all stun-related attributes
            if character:GetAttribute("Stunned") then
                character:SetAttribute("Stunned", false)
            end
            if character:GetAttribute("PushStun") then
                character:SetAttribute("PushStun", false)
            end
            if character:GetAttribute("BlowByStun") then
                character:SetAttribute("BlowByStun", false)
            end
            if character:GetAttribute("SecondPushStun") then
                character:SetAttribute("SecondPushStun", false)
            end
            if character:GetAttribute("Action") == "ScreenStun" then
                character:SetAttribute("Action", "")
            end
        end)
    end)
end

local function disableAntiStun()
    if antiStunConn then
        antiStunConn:Disconnect()
        antiStunConn = nil
    end
end
local function enableBlowByBoost()
    blowByConn=animator.AnimationPlayed:Connect(function(tr)
        if not state.blowByBoost then return end
        if tr.Name=="BlowByLeft" or tr.Name=="BlowByRight" then
            task.spawn(function()
                local bv=hrp:FindFirstChild("BodyVelocity")
                if not bv then bv=Instance.new("BodyVelocity"); bv.Velocity=Vector3.new(0,0,0); bv.MaxForce=Vector3.new(0,0,0); bv.Parent=hrp end
                local isL=tr.Name=="BlowByLeft"; local dir=hrp.CFrame.LookVector; local side=isL and -hrp.CFrame.RightVector or hrp.CFrame.RightVector
                bv.MaxForce=Vector3.new(99999,0,99999); bv.Velocity=(dir*0.7+side*0.3).Unit*85
                task.wait(tr.Length*0.6)
                TweenService:Create(bv,TweenInfo.new(0.25,Enum.EasingStyle.Quad),{Velocity=Vector3.new(0,0,0),MaxForce=Vector3.new(0,0,0)}):Play()
            end) end end)
end
local function disableBlowByBoost() if blowByConn then blowByConn:Disconnect();blowByConn=nil end end

local originalHitboxSize = nil
local hitboxPart = nil
local wasShooting = false

local function findHitbox()
    for _, obj in ipairs(character:GetDescendants()) do
        if obj:IsA("BasePart") and (obj.Name:lower() == "hitbox" or obj.Name:lower() == "hitboxpart") then
            return obj
        end
    end
    return nil
end
-- Hip Height Booster: temporarily increases hip height during shooting
local originalHipHeight = humanoid.HipHeight
local hipHeightBoostConn = nil
local wasShootingForHip = false

local function enableHipHeightBoost()
    if hipHeightBoostConn then hipHeightBoostConn:Disconnect() end
    hipHeightBoostConn = RunService.Heartbeat:Connect(function()
        if not state.hipHeightBoost then
            -- Restore original hip height when feature is off
            if wasShootingForHip then
                humanoid.HipHeight = originalHipHeight
                wasShootingForHip = false
            end
            return
        end
        
        local action = character:GetAttribute("Action") or ""
        local isShooting = (action == "Shooting")
        
        if isShooting then
            -- Apply boost (only if not already boosted)
            if not wasShootingForHip then
                humanoid.HipHeight = originalHipHeight + state.hipHeightAmount
                wasShootingForHip = true
            end
        elseif wasShootingForHip then
            -- Restore after shooting
            humanoid.HipHeight = originalHipHeight
            wasShootingForHip = false
        end
    end)
end

local function disableHipHeightBoost()
    if hipHeightBoostConn then
        hipHeightBoostConn:Disconnect()
        hipHeightBoostConn = nil
    end
    -- Restore original height
    if wasShootingForHip then
        humanoid.HipHeight = originalHipHeight
        wasShootingForHip = false
    end
end
local function enableAntiContest()
    if antiContestConn then antiContestConn:Disconnect() end
    antiContestConn = RunService.Heartbeat:Connect(function()
        if not state.antiContest then
            -- If feature is turned off, restore hitbox and exit
            if wasShooting and hitboxPart and originalHitboxSize then
                hitboxPart.Size = originalHitboxSize
                wasShooting = false
            end
            return
        end

        local action = character:GetAttribute("Action") or ""
        local isShooting = (action == "Shooting")

        -- Find hitbox once
        if not hitboxPart then
            hitboxPart = findHitbox()
            if hitboxPart then
                originalHitboxSize = hitboxPart.Size
            end
        end

        if isShooting then
            -- Shrink hitbox when shooting (only if not already shrunk)
            if hitboxPart and hitboxPart.Size ~= Vector3.new(0.1, 0.1, 0.1) then
                hitboxPart.Size = Vector3.new(0.1, 0.1, 0.1)
            end
            wasShooting = true

            -- Optional: push away nearby guards (single impulse, not continuous)
            local myPos = hrp.Position
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= player then
                    local c = p.Character
                    if c then
                        local ph = c:FindFirstChild("HumanoidRootPart")
                        if ph then
                            local diff = myPos - ph.Position
                            if diff.Magnitude < 6 then
                                local bv = hrp:FindFirstChild("BodyVelocity")
                                if bv then
                                    local a = diff.Unit * 12
                                    bv.MaxForce = Vector3.new(50000, 0, 50000)
                                    bv.Velocity = Vector3.new(a.X, 0, a.Z)
                                end
                            end
                        end
                    end
                end
            end
        elseif wasShooting then
            -- Just finished shooting: restore hitbox size
            if hitboxPart and originalHitboxSize then
                hitboxPart.Size = originalHitboxSize
            end
            wasShooting = false
        end
    end)
end

local function disableAntiContest()
    if antiContestConn then
        antiContestConn:Disconnect()
        antiContestConn = nil
    end
    -- Restore hitbox size
    if hitboxPart and originalHitboxSize then
        hitboxPart.Size = originalHitboxSize
    end
    wasShooting = false
end
local FEATURE_ACTIONS={
    autoGreen={nil,nil}, -- handled by ContextAction binding
    infiniteStamina={enableInfiniteStamina,disableInfiniteStamina},
    autoSprint={enableAutoSprint,disableAutoSprint},
    speedBoost={enableSpeedBoost,disableSpeedBoost},
    manualSpeed={enableManualSpeed,disableManualSpeed},
    velocityBoost={enableVelocityBoost,disableVelocityBoost},
    antiLag={enableAntiLag,disableAntiLag},
    customFeedback={enableCustomFeedback,disableCustomFeedback},
    dribbleMacro={enableDribbleMacro,disableDribbleMacro},
    antiOOB={enableAntiOOB,disableAntiOOB},
    autoBlock={enableAutoBlock,disableAutoBlock},
    animSpeedBoost={enableAnimSpeedBoost,disableAnimSpeedBoost},
    autoGuard={enableAutoGuard,disableAutoGuard},
    antiAnkleBreak={enableAntiAnkleBreak,disableAntiAnkleBreak},
    antiStun={enableAntiStun,disableAntiStun},
    blowByBoost={enableBlowByBoost,disableBlowByBoost},
    antiContest={enableAntiContest,disableAntiContest},
    autoCrossover = {enableAutoCrossover, nil},
    dribbleSpeedBoost = {enableDribbleSpeedBoost, nil},
    instantSpin = {enableInstantSpin, nil}, 
    autoCrossover = {enableAutoCrossover, disableAutoCrossover},
    hipHeightBoost = {enableHipHeightBoost, disableHipHeightBoost},
}

-- ====================================================================
-- GUI  v4.1  —  COMPACT TABBED  (fits 375×667 mobile screen)
-- Panel: ~280×460px  |  4 tabs  |  each tab fits on screen
-- ====================================================================
local existing=player.PlayerGui:FindFirstChild("SiftWinGUI")
if existing then existing:Destroy() end

local SG=Instance.new("ScreenGui")
SG.Name="SiftWinGUI"; SG.ResetOnSpawn=false
SG.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
SG.IgnoreGuiInset=true; SG.DisplayOrder=10
SG.Parent=player:WaitForChild("PlayerGui")

-- Center the UI initially
local PW = isMobile and 272 or 280
local PH = isMobile and 430 or 440

local container = Instance.new("Frame", SG)
container.Size = UDim2.new(0, PW, 0, PH)
-- Default centered position
container.Position = UDim2.new(0.5, -PW/2, 0.5, -PH/2)
container.BackgroundTransparency = 1

-- Load saved position
local savedPos = loadSettings()
if savedPos then
    container.Position = UDim2.new(0.5, savedPos.X, 0.5, savedPos.Y)
end

local main=Instance.new("Frame",container)
main.Size=UDim2.new(1,0,1,0)
main.BackgroundColor3=C.BG
main.BorderSizePixel=0; main.ClipsDescendants=true
Instance.new("UICorner",main).CornerRadius=UDim.new(0,12)
local mainStroke=Instance.new("UIStroke",main)
mainStroke.Color=C.ACCENT; mainStroke.Thickness=1; mainStroke.Transparency=0.6

-- Animated top accent line
local topBar=Instance.new("Frame",main)
topBar.Size=UDim2.new(1,0,0,2); topBar.BackgroundColor3=C.ACCENT; topBar.BorderSizePixel=0; topBar.ZIndex=8
local topGrad=Instance.new("UIGradient",topBar)
topGrad.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(0,50,180)),ColorSequenceKeypoint.new(0.5,Color3.fromRGB(80,180,255)),ColorSequenceKeypoint.new(1,Color3.fromRGB(0,50,180))})
task.spawn(function() local t=0; while main and main.Parent do RunService.Heartbeat:Wait(); t=t+0.006; topGrad.Offset=Vector2.new(math.sin(t)*0.5,0) end end)

-- ── HEADER (36px) ────────────────────────────────────────────────────
local HDR_H=36
local header=Instance.new("Frame",main)
header.Size=UDim2.new(1,0,0,HDR_H); header.Position=UDim2.new(0,0,0,2)
header.BackgroundColor3=C.HEADER; header.BorderSizePixel=0

local hTitle=Instance.new("TextLabel",header)
hTitle.Size=UDim2.new(0,100,1,0); hTitle.Position=UDim2.new(0,10,0,0)
hTitle.BackgroundTransparency=1; hTitle.Text="SIFT.WIN"
hTitle.TextColor3=C.TEXT_HI; hTitle.Font=Enum.Font.GothamBlack
hTitle.TextSize=14; hTitle.TextXAlignment=Enum.TextXAlignment.Left

local hSub=Instance.new("TextLabel",header)
hSub.Size=UDim2.new(0,140,1,0); hSub.Position=UDim2.new(0,88,0,0)
hSub.BackgroundTransparency=1; hSub.Text="WIN PLAYGROUND"
hSub.TextColor3=C.ACCENT; hSub.Font=Enum.Font.Gotham
hSub.TextSize=7; hSub.TextXAlignment=Enum.TextXAlignment.Left; hSub.TextTransparency=0.25

local hVer=Instance.new("TextLabel",header)
hVer.Size=UDim2.new(0,36,0,14); hVer.Position=UDim2.new(1,-76,0.5,-7)
hVer.BackgroundColor3=C.ACCENT_DIM; hVer.BorderSizePixel=0
hVer.TextColor3=C.TEXT_HI; hVer.Text="v4.1"; hVer.Font=Enum.Font.GothamBold; hVer.TextSize=7
Instance.new("UICorner",hVer).CornerRadius=UDim.new(0,4)

local minimized=false
local minBtn=Instance.new("TextButton",header)
minBtn.Size=UDim2.new(0,22,0,22); minBtn.Position=UDim2.new(1,-28,0.5,-11)
minBtn.BackgroundColor3=C.TOGGLE_OFF; minBtn.BorderSizePixel=0
minBtn.Text="−"; minBtn.TextColor3=C.TEXT_MID; minBtn.Font=Enum.Font.GothamBold; minBtn.TextSize=14; minBtn.ZIndex=10
Instance.new("UICorner",minBtn).CornerRadius=UDim.new(0,5)

-- Drag to move UI (simple & reliable)
local dragging, dragStart, dStartPos = false, nil, nil
header.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = Vector2.new(i.Position.X, i.Position.Y)
        dStartPos = container.Position
    end
end)
header.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = false
        saveSettings()  -- save new position
    end
end)
UserInputService.InputChanged:Connect(function(i)
    if not dragging then return end
    if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
        local dx = i.Position.X - dragStart.X
        local dy = i.Position.Y - dragStart.Y
        container.Position = UDim2.new(dStartPos.X.Scale, dStartPos.X.Offset + dx, dStartPos.Y.Scale, dStartPos.Y.Offset + dy)
    end
end)

-- ── TAB BAR (32px, 4 tabs) ───────────────────────────────────────────
local TAB_Y = HDR_H+2
local TAB_H = 28
local tabBar=Instance.new("Frame",main)
tabBar.Size=UDim2.new(1,0,0,TAB_H); tabBar.Position=UDim2.new(0,0,0,TAB_Y)
tabBar.BackgroundColor3=C.PANEL; tabBar.BorderSizePixel=0

local TABS={"SHOOT","MOVE","DRIB","DEFENSE"}
local TAB_ICONS={"🏀","🏃","🤹","🛡"}
local tabBtns={}
local activeTab=nil

local CONTENT_Y = TAB_Y+TAB_H
local CONTENT_H = PH - CONTENT_Y

local contentFrames={}
for _,name in ipairs(TABS) do
    local f=Instance.new("ScrollingFrame",main)
    f.Size=UDim2.new(1,0,0,CONTENT_H); f.Position=UDim2.new(0,0,0,CONTENT_Y)
    f.BackgroundTransparency=1; f.BorderSizePixel=0
    f.ScrollBarThickness=3; f.ScrollBarImageColor3=C.ACCENT
    f.CanvasSize=UDim2.new(0,0,0,0); f.Visible=false
    local layout=Instance.new("UIListLayout",f); layout.Padding=UDim.new(0,4); layout.SortOrder=Enum.SortOrder.LayoutOrder
    local pad=Instance.new("UIPadding",f); pad.PaddingTop=UDim.new(0,5); pad.PaddingLeft=UDim.new(0,6); pad.PaddingRight=UDim.new(0,6)
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        f.CanvasSize=UDim2.new(0,0,0,layout.AbsoluteContentSize.Y+10)
    end)
    contentFrames[name]=f
end

local function switchTab(name)
    activeTab=name
    for n,f in pairs(contentFrames) do f.Visible=(n==name) end
    for _,b in ipairs(tabBtns) do
        local on=(b.Name==name)
        TweenService:Create(b,TweenInfo.new(0.12,Enum.EasingStyle.Quad),{BackgroundColor3=on and C.TAB_ON or C.TAB}):Play()
        b.TextColor3=on and C.TEXT_HI or C.TEXT_MID
    end
end

local TW=PW/#TABS
for i,name in ipairs(TABS) do
    local btn=Instance.new("TextButton",tabBar)
    btn.Name=name
    btn.Size=UDim2.new(0,TW-1,1,-2); btn.Position=UDim2.new(0,(i-1)*TW,0,1)
    btn.BackgroundColor3=C.TAB; btn.BorderSizePixel=0
    btn.Text=TAB_ICONS[i].." "..name; btn.TextColor3=C.TEXT_MID
    btn.Font=Enum.Font.GothamBold; btn.TextSize=9
    Instance.new("UICorner",btn).CornerRadius=UDim.new(0,5)
    btn.MouseButton1Click:Connect(function() switchTab(name) end)
    table.insert(tabBtns,btn)
end

-- ── WIDGET BUILDERS ──────────────────────────────────────────────────
local toggleRefs={}

-- Toggle card (compact 36px)
local function mkToggle(tabName, key, label, desc)
    local parent=contentFrames[tabName]
    local card=Instance.new("Frame",parent)
    card.Size=UDim2.new(1,0,0,36); card.BackgroundColor3=C.CARD; card.BorderSizePixel=0
    Instance.new("UICorner",card).CornerRadius=UDim.new(0,7)

    local stripe=Instance.new("Frame",card)
    stripe.Size=UDim2.new(0,2,0.6,0); stripe.Position=UDim2.new(0,0,0.2,0)
    stripe.BackgroundColor3=C.ACCENT; stripe.BorderSizePixel=0; stripe.BackgroundTransparency=1
    Instance.new("UICorner",stripe).CornerRadius=UDim.new(0,2)

    local nameLbl=Instance.new("TextLabel",card)
    nameLbl.Size=UDim2.new(1,-80,0,16); nameLbl.Position=UDim2.new(0,10,0,4)
    nameLbl.BackgroundTransparency=1; nameLbl.Text=label
    nameLbl.TextColor3=C.TEXT_HI; nameLbl.Font=Enum.Font.GothamBold
    nameLbl.TextSize=11; nameLbl.TextXAlignment=Enum.TextXAlignment.Left

    local descLbl=Instance.new("TextLabel",card)
    descLbl.Size=UDim2.new(1,-80,0,10); descLbl.Position=UDim2.new(0,10,0,21)
    descLbl.BackgroundTransparency=1; descLbl.Text=desc
    descLbl.TextColor3=C.TEXT_DIM; descLbl.Font=Enum.Font.Gotham; descLbl.TextSize=8
    descLbl.TextXAlignment=Enum.TextXAlignment.Left

    local statLbl=Instance.new("TextLabel",card)
    statLbl.Size=UDim2.new(0,22,0,10); statLbl.Position=UDim2.new(1,-68,0.5,-5)
    statLbl.BackgroundTransparency=1; statLbl.Text="OFF"; statLbl.TextColor3=C.TEXT_DIM
    statLbl.Font=Enum.Font.GothamBold; statLbl.TextSize=8

    local track=Instance.new("Frame",card)
    track.Size=UDim2.new(0,36,0,18); track.Position=UDim2.new(1,-44,0.5,-9)
    track.BackgroundColor3=C.TOGGLE_OFF; track.BorderSizePixel=0
    Instance.new("UICorner",track).CornerRadius=UDim.new(1,0)

    local knob=Instance.new("Frame",track)
    knob.Size=UDim2.new(0,14,0,14); knob.Position=UDim2.new(0,2,0.5,-7)
    knob.BackgroundColor3=C.KNOB; knob.BorderSizePixel=0
    Instance.new("UICorner",knob).CornerRadius=UDim.new(1,0)

    local ref={track=track,knob=knob,statusLbl=statLbl,card=card,stripe=stripe}
    toggleRefs[key]=ref

    local btn=Instance.new("TextButton",card)
    btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1; btn.Text=""; btn.ZIndex=4
    btn.MouseButton1Click:Connect(function()
        state[key]=not state[key]
        local on=state[key]
        TweenService:Create(track,TweenInfo.new(0.14),{BackgroundColor3=on and C.ACCENT or C.TOGGLE_OFF}):Play()
        TweenService:Create(knob,TweenInfo.new(0.14),{Position=on and UDim2.new(1,-16,0.5,-7) or UDim2.new(0,2,0.5,-7)}):Play()
        TweenService:Create(card,TweenInfo.new(0.14),{BackgroundColor3=on and C.CARD_ON or C.CARD}):Play()
        TweenService:Create(stripe,TweenInfo.new(0.14),{BackgroundTransparency=on and 0 or 1}):Play()
        statLbl.Text=on and "ON" or "OFF"; statLbl.TextColor3=on and C.ACCENT or C.TEXT_DIM
        local fa=FEATURE_ACTIONS[key]; if fa then if on then if fa[1] then fa[1]() end else if fa[2] then fa[2]() end end end
        saveSettings()  
    end)
    return ref
end

-- Slider (24px)
local function mkSlider(tabName, label, minV, maxV, initV, onChange)
    local parent=contentFrames[tabName]
    local card=Instance.new("Frame",parent)
    card.Size=UDim2.new(1,0,0,26); card.BackgroundColor3=C.CARD; card.BorderSizePixel=0
    Instance.new("UICorner",card).CornerRadius=UDim.new(0,7)

    local lbl=Instance.new("TextLabel",card)
    lbl.Size=UDim2.new(0,90,1,0); lbl.Position=UDim2.new(0,8,0,0)
    lbl.BackgroundTransparency=1; lbl.Text=label; lbl.TextColor3=C.TEXT_MID
    lbl.Font=Enum.Font.GothamBold; lbl.TextSize=8; lbl.TextXAlignment=Enum.TextXAlignment.Left

    local valLbl=Instance.new("TextLabel",card)
    valLbl.Size=UDim2.new(0,28,1,0); valLbl.Position=UDim2.new(1,-32,0,0)
    valLbl.BackgroundTransparency=1; valLbl.Text=tostring(initV)
    valLbl.TextColor3=C.ACCENT; valLbl.Font=Enum.Font.GothamBold; valLbl.TextSize=8

    local track=Instance.new("Frame",card)
    track.Size=UDim2.new(1,-130,0,4); track.Position=UDim2.new(0,96,0.5,-2)
    track.BackgroundColor3=C.TOGGLE_OFF; track.BorderSizePixel=0
    Instance.new("UICorner",track).CornerRadius=UDim.new(0,2)
    local tg=Instance.new("UIGradient",track)
    tg.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(0,60,180)),ColorSequenceKeypoint.new(1,Color3.fromRGB(80,180,255))})

    local kn=Instance.new("Frame",track)
    local ip=math.clamp((initV-minV)/(maxV-minV),0,1)
    kn.Size=UDim2.new(0,12,0,12); kn.Position=UDim2.new(ip,-6,0.5,-6)
    kn.BackgroundColor3=C.KNOB; kn.BorderSizePixel=0
    Instance.new("UICorner",kn).CornerRadius=UDim.new(1,0)
    local ks=Instance.new("UIStroke",kn); ks.Color=C.BG; ks.Thickness=1.5

    local sliding=false
    local function doSlide(pos)
        local ap=track.AbsolutePosition; local as=track.AbsoluteSize
        local rel=math.clamp((pos.X-ap.X)/as.X,0,1)
        local val=math.floor(minV+(maxV-minV)*rel+0.5)
        kn.Position=UDim2.new(rel,-6,0.5,-6); valLbl.Text=tostring(val); onChange(val)
    end
    track.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then sliding=true; doSlide(i.Position) end end)
    track.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then sliding=false end end)
    UserInputService.InputChanged:Connect(function(i) if sliding and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then doSlide(i.Position) end end)
end

-- Hue slider (24px)
local function mkHueSlider(tabName)
    local parent=contentFrames[tabName]
    local card=Instance.new("Frame",parent)
    card.Size=UDim2.new(1,0,0,26); card.BackgroundColor3=C.CARD; card.BorderSizePixel=0
    Instance.new("UICorner",card).CornerRadius=UDim.new(0,7)

    local lbl=Instance.new("TextLabel",card)
    lbl.Size=UDim2.new(0,60,1,0); lbl.Position=UDim2.new(0,8,0,0)
    lbl.BackgroundTransparency=1; lbl.Text="VFX HUE"; lbl.TextColor3=C.TEXT_MID
    lbl.Font=Enum.Font.GothamBold; lbl.TextSize=8; lbl.TextXAlignment=Enum.TextXAlignment.Left

    local swatch=Instance.new("Frame",card)
    swatch.Size=UDim2.new(0,12,0,12); swatch.Position=UDim2.new(1,-32,0.5,-6)
    swatch.BackgroundColor3=hsvToRgb(vfxHue,0.9,1); swatch.BorderSizePixel=0
    Instance.new("UICorner",swatch).CornerRadius=UDim.new(0,3)

    local valLbl=Instance.new("TextLabel",card)
    valLbl.Size=UDim2.new(0,0,1,0); valLbl.Position=UDim2.new(1,-50,0,0)
    valLbl.BackgroundTransparency=1; valLbl.Text=tostring(vfxHue).."°"
    valLbl.TextColor3=C.ACCENT; valLbl.Font=Enum.Font.GothamBold; valLbl.TextSize=8

    local track=Instance.new("Frame",card)
    track.Size=UDim2.new(1,-120,0,4); track.Position=UDim2.new(0,68,0.5,-2)
    track.BackgroundColor3=C.TOGGLE_OFF; track.BorderSizePixel=0
    Instance.new("UICorner",track).CornerRadius=UDim.new(0,2)
    local rg=Instance.new("UIGradient",track)
    rg.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,0,0)),ColorSequenceKeypoint.new(0.17,Color3.fromRGB(255,165,0)),ColorSequenceKeypoint.new(0.33,Color3.fromRGB(255,255,0)),ColorSequenceKeypoint.new(0.5,Color3.fromRGB(0,255,0)),ColorSequenceKeypoint.new(0.67,Color3.fromRGB(0,130,255)),ColorSequenceKeypoint.new(0.83,Color3.fromRGB(130,0,255)),ColorSequenceKeypoint.new(1,Color3.fromRGB(255,0,0))})

    local kn=Instance.new("Frame",track)
    local ip=vfxHue/360
    kn.Size=UDim2.new(0,12,0,12); kn.Position=UDim2.new(ip,-6,0.5,-6)
    kn.BackgroundColor3=Color3.fromRGB(240,242,248); kn.BorderSizePixel=0
    Instance.new("UICorner",kn).CornerRadius=UDim.new(1,0)
    local ks=Instance.new("UIStroke",kn); ks.Color=C.BG; ks.Thickness=1.5

    local sliding=false
    local function doSlide(pos)
        local ap=track.AbsolutePosition; local as=track.AbsoluteSize
        local rel=math.clamp((pos.X-ap.X)/as.X,0,1)
        vfxHue=math.floor(rel*360+0.5); kn.Position=UDim2.new(rel,-6,0.5,-6)
        valLbl.Text=tostring(vfxHue).."°"; swatch.BackgroundColor3=hsvToRgb(vfxHue,0.9,1); applyVfx()
    end
    track.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then sliding=true; doSlide(i.Position) end end)
    track.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then sliding=false end end)
    UserInputService.InputChanged:Connect(function(i) if sliding and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then doSlide(i.Position) end end)
end

-- Shoot button (inside SHOOT tab)
local function mkShootBtn(tabName)
    local parent=contentFrames[tabName]
    local btn=Instance.new("TextButton",parent)
    btn.Size=UDim2.new(1,0,0,38); btn.BackgroundColor3=C.SHOOT_BTN; btn.BorderSizePixel=0
    btn.Text="▶  SHOOT  [E]"; btn.TextColor3=C.TEXT_HI
    btn.Font=Enum.Font.GothamBlack; btn.TextSize=13
    Instance.new("UICorner",btn).CornerRadius=UDim.new(0,8)
    local sg=Instance.new("UIGradient",btn)
    sg.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(0,70,200)),ColorSequenceKeypoint.new(0.5,Color3.fromRGB(60,160,255)),ColorSequenceKeypoint.new(1,Color3.fromRGB(0,70,200))})
    task.spawn(function() local t=0; while btn and btn.Parent do RunService.Heartbeat:Wait(); t=t+0.01; sg.Offset=Vector2.new(math.sin(t)*0.5,0) end end)
    btn.MouseButton1Click:Connect(function() task.spawn(executeShot) end)
    btn.MouseButton1Down:Connect(function() TweenService:Create(btn,TweenInfo.new(0.07),{BackgroundColor3=C.SHOOT_DOWN}):Play() end)
    btn.MouseButton1Up:Connect(function() TweenService:Create(btn,TweenInfo.new(0.1),{BackgroundColor3=C.SHOOT_BTN}):Play() end)
end

-- ── POPULATE TABS ────────────────────────────────────────────────────

-- SHOOT
mkShootBtn("SHOOT")
mkToggle("SHOOT","autoGreen",    "Auto Green",    "Greens every shot via E/btn")
mkToggle("SHOOT","customFeedback","Custom Feed",  "CHICKEN! + colored feedback")
mkToggle("SHOOT","antiContest",  "Anti Contest",  "Step away when contested")

-- MOVE
mkToggle("MOVE","infiniteStamina","Inf. Stamina", "Full stamina always")
mkToggle("MOVE","autoSprint",    "Auto Sprint",   "Always sprinting")
mkToggle("MOVE","speedBoost",    "Speed Burst",   "Auto burst while dribbling")
mkToggle("MOVE","manualSpeed",   "Speed Override","Slider-set walkspeed")
mkSlider("MOVE","Speed (WS)",0,30,manualSpeedVal,function(v) manualSpeedVal=v end)
mkToggle("MOVE","velocityBoost", "Vel. Boost",    "1.53× movement force")
mkToggle("MOVE","blowByBoost",   "BlowBy Boost",  "Faster blow-by distance")
mkToggle("MOVE","antiLag",       "Anti Lag",      "Lower gfx, boost FPS")
mkHueSlider("MOVE")

-- DRIB
mkToggle("DRIB","dribbleMacro",  "Dribble Macro", "Auto crossover/hesit/combo")
mkToggle("DRIB","antiAnkleBreak","Anti Ankle Brk","Cancel ankle break anims")
mkToggle("DRIB","animSpeedBoost","Anim Speed+",   "1.35× animation speed")
mkToggle("DRIB", "autoCrossover", "Auto Crossover", "Crossover on sprint")
mkToggle("DRIB", "dribbleSpeedBoost", "Dribble Speed+", "Override dribble speed")
mkToggle("DRIB", "instantSpin", "Instant Spin", "Spin on Q key")
mkToggle("DRIB", "hipHeightBoost", "Hip Height Boost", "Subtle rise while shooting to avoid blocks")
mkSlider("DRIB", "Boost Amount", 1.0, 3.0, state.hipHeightAmount, function(v)
    state.hipHeightAmount = v
end)

-- DEFENSE
mkToggle("DEFENSE","autoGuard",  "Auto Guard",    "Face nearest ball carrier")
mkToggle("DEFENSE","autoBlock",  "Auto Block",    "Block nearby shooters")
mkSlider("DEFENSE","Block Range",4,25,blockRange,  function(v) blockRange=v end)
mkSlider("DEFENSE","Block FOV",  20,180,blockFOV,  function(v) blockFOV=v  end)
mkSlider("DEFENSE","Block Delay",0,500,blockDelayMs,function(v) blockDelayMs=v end)
mkSlider("DEFENSE", "Guard Range", 10, 50, GUARD_DISTANCE, function(v) GUARD_DISTANCE= v end)
mkToggle("DEFENSE","antiStun",   "Anti Stun",     "Clear stun/push attrs")
mkToggle("DEFENSE","antiOOB",    "Anti OOB",      "Never go out of bounds")

-- ── DEFAULT TAB + MINIMIZE ───────────────────────────────────────────
switchTab("SHOOT")

minBtn.MouseButton1Click:Connect(function()
    minimized=not minimized
    TweenService:Create(main,TweenInfo.new(0.18,Enum.EasingStyle.Quad),{
        Size=minimized and UDim2.new(1,0,0,HDR_H+2) or UDim2.new(1,0,1,0)}):Play()
    minBtn.Text=minimized and "+" or "−"
end)

print(string.format("[SiftWin] v4.1 | %s | %d AG timings",Platform,#TIMINGS))
