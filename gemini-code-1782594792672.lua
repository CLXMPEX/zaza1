-- =============================================
--  AUTO FARM GUI v4.1 — SUNSHINE + DARK MATTER
--  Supports both bossRaids and invasions
-- =============================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UIS               = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local HttpService       = game:GetService("HttpService")

local player = Players.LocalPlayer
local pgui   = player:WaitForChild("PlayerGui", 10)

-- HTTP Request for Webhooks (Supports Synapse, Krnl, Fluxus, etc.)
local http_request = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request

-- =============================================
--  REMOTES (exact paths)
-- =============================================

local remoBase
local ok, err = pcall(function()
    remoBase = ReplicatedStorage:WaitForChild("rbxts_include", 5)
        :WaitForChild("node_modules", 5):WaitForChild("@rbxts", 5)
        :WaitForChild("remo", 5):WaitForChild("src", 5):WaitForChild("container", 5)
end)
if not ok or not remoBase then
    warn("[AF] Remote path not found! Game may have updated. Error: " .. tostring(err))
    remoBase = nil
end

local function getRemote(cat, name)
    if not remoBase then return nil end
    local c = remoBase:FindFirstChild(cat)
    return c and c:FindFirstChild(name)
end

local R = {
    createRaid            = getRemote("bossRaids", "create"),
    leaveRaid             = getRemote("bossRaids", "leaveRaid"),
    createInvasion        = getRemote("invasions", "create"),
    replayInvasion        = getRemote("invasions", "replay"),
    voteCard              = getRemote("invasions", "voteCard"),
    lobbyStart            = getRemote("lobbies", "start"),
    weaponActivate        = getRemote("weapons", "activate"),
    sendAndRetreat        = getRemote("enemies", "sendAndRetreat"),
    toolbarEquip          = getRemote("toolbar", "equip"),
    toolbarUnequip        = getRemote("toolbar", "unequip"),
    warriorsEquipBest     = getRemote("warriors", "equipBest"),
    achievementClaim      = getRemote("achievements", "claim"),
    achievementClaimGroup = getRemote("achievements", "claimGroup"),
}

-- =============================================
--  RAID DATA & STATE
-- =============================================

local RaidList = {
    {
        name = "Sunshine Raid", display = "Sunshine Lake", raidType = "bossRaid",
        portalPos = CFrame.new(-653.9, -1471.1, 186.3), bossPos = CFrame.new(4982.6, 6007.8, -50.4),
        startText = "start raid", working = true,
    },
    {
        name = "Dark Matter Invasion", display = "Dark Matter", raidType = "invasion",
        portalPos = CFrame.new(-1743, -1490, -745), bossPos = CFrame.new(5068, 6030, -150),
        startText = "start invasion", working = true,
    },
}

getgenv().AFState = {
    autoEquipWeapon      = false,
    autoUseWeapon        = false,
    autoClaimAchievement = false,
    autoEquipBestPet     = false,
    autoFarm             = false,
    friendOnly           = false,
    autoCreateRaid       = false,
    guiVisible           = true,
    running              = true,
    inRaid               = false,
    selectedRaid         = RaidList[1],

    -- WEBHOOK SETTINGS
    sendWebhook          = true, 
    webhookUrl           = "YOUR_WEBHOOK_URL_HERE", -- Paste your Discord Webhook URL here

    -- MODIFIER PRIORITIES (1 = highest priority. Add exact names here)
    modifierPriorities   = {
        "Boss Killer",
        "Overflowing Wealth",
        "Espionage",
        "Reinforcement",
        "Momentum"
    }
}
local State = getgenv().AFState

local RAID_Y_MIN = 5000

local function getChar()
    local c = player.Character
    if not c then return nil, nil end
    return c, c:FindFirstChild("HumanoidRootPart")
end

local function isInRaidArea()
    local _, hrp = getChar()
    if not hrp then return false end
    return hrp.Position.Y > RAID_Y_MIN
end

-- Fix: If we inject while ALREADY inside the raid, set state immediately
if isInRaidArea() then
    State.inRaid = true
    print("[AF] Script started while inside raid. Bypassing lobby teleport.")
end

-- =============================================
--  WEBHOOK FUNCTION
-- =============================================

local function sendWebhookNotification(raidName, rewardsText)
    if not State.sendWebhook or State.webhookUrl == "" or State.webhookUrl == "YOUR_WEBHOOK_URL_HERE" then return end
    if not http_request then print("[AF] HTTP Requests not supported by executor.") return end

    pcall(function()
        http_request({
            Url = State.webhookUrl,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode({
                content = nil,
                embeds = {{
                    title = "🏆 Raid Completed!",
                    description = "**" .. raidName .. "** was successfully finished.\n\n**Rewards:**\n" .. (rewardsText or "No reward data parsed."),
                    color = 5814783, -- Purple color
                    timestamp = DateTime.now():ToIsoDate()
                }}
            })
        })
    end)
    print("[AF] Webhook sent!")
end

-- =============================================
--  COMBAT & HELPERS
-- =============================================

local function getEnemyFolder()
    local w = Workspace:FindFirstChild("World") return w and w:FindFirstChild("Enemies")
end

local function getWarriorFolder()
    local w = Workspace:FindFirstChild("World") return w and w:FindFirstChild("Warriors")
end

local function getWarriorUUIDs()
    local uuids = {}
    local f = getWarriorFolder()
    if not f then return uuids end
    for _, w in ipairs(f:GetChildren()) do
        if w:IsA("Model") then table.insert(uuids, w.Name) end
    end
    return uuids
end

local function getAliveEnemies()
    local enemies = {}
    local folder = getEnemyFolder()
    if not folder then return enemies end

    for _, e in ipairs(folder:GetChildren()) do
        if not e:IsA("Model") then continue end
        if e:GetAttribute("dead") ~= false then continue end

        local hrp = e:FindFirstChild("HumanoidRootPart") or e:FindFirstChild("Root")
        if not hrp or hrp.Position.Y < RAID_Y_MIN then continue end

        local hum = e:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health <= 0 then continue end

        table.insert(enemies, {
            model = e, uuid = e.Name, hrp = hrp,
            hasHumanoid = hum ~= nil,
            boundsX = (e:GetAttribute("bounds") and e:GetAttribute("bounds").X or 0),
            state = e:GetAttribute("_battleState") or "none",
        })
    end
    return enemies
end

local function teleportTo(targetHRP)
    local _, hrp = getChar()
    if hrp and targetHRP then hrp.CFrame = targetHRP.CFrame * CFrame.new(0, 0, 5) end
end

local function swingWeapon()
    if R.weaponActivate then
        local _, hrp = getChar()
        if hrp then pcall(function() R.weaponActivate:FireServer(tick(), hrp.CFrame) end) end
    end
end

local function hitEnemy(uuid)
    if R.sendAndRetreat then
        local warriors = getWarriorUUIDs()
        if #warriors > 0 then pcall(function() R.sendAndRetreat:FireServer(uuid, warriors) end) end
    end
end

local function equipWeapon()
    if R.toolbarEquip then pcall(function() R.toolbarEquip:FireServer("weapon") end) end
end

local function attackTarget(target)
    teleportTo(target.hrp)
    task.wait(0.05)
    swingWeapon()
    task.wait(0.05)
    hitEnemy(target.uuid)
    task.wait(0.05)
    swingWeapon()
end

-- =============================================
--  RAID MANAGEMENT & AUTO VOTE
-- =============================================

local function clickByText(searchText)
    searchText = string.lower(searchText)
    for _, obj in ipairs(pgui:GetDescendants()) do
        if obj:IsA("TextLabel") and obj.Visible then
            if obj:IsDescendantOf(pgui:FindFirstChild("AutoFarmGUI")) then continue end
            if string.find(string.lower(obj.Text), searchText, 1, true) then
                local current = obj.Parent
                for d = 1, 8 do
                    if not current or current == pgui then break end
                    if current.Name == "inner" then
                        local textButton = current:FindFirstChildOfClass("TextButton")
                        if textButton then
                            pcall(function() for _, conn in pairs(getconnections(textButton.Activated)) do conn:Fire() end end)
                            return true
                        end
                    end
                    current = current.Parent
                end
            end
        end
    end
    return false
end

local function clickExact(exactText)
    for _, obj in ipairs(pgui:GetDescendants()) do
        if obj:IsA("TextLabel") and obj.Visible and obj.Text == exactText then
            if obj:IsDescendantOf(pgui:FindFirstChild("AutoFarmGUI")) then continue end
            local current = obj.Parent
            for d = 1, 8 do
                if not current then break end
                if current.Name == "inner" then
                    local tb = current:FindFirstChildOfClass("TextButton")
                    if tb then
                        pcall(function() for _, conn in pairs(getconnections(tb.Activated)) do conn:Fire() end end)
                        return true
                    end
                    break
                end
                current = current.Parent
            end
        end
    end
    return false
end

local function createRaid()
    local raid = State.selectedRaid
    if raid.raidType == "invasion" then clickByText("lead me to the invasion"); task.wait(1) end
    if clickByText(raid.startText) then
        task.wait(1.5)
        if State.friendOnly then clickByText("friends only"); task.wait(0.5) end
        task.wait(0.5)
        if clickByText("yes") then return true end
    end
    
    if raid.raidType == "invasion" and R.createInvasion then
        pcall(function() R.createInvasion:InvokeServer(raid.name, {friendsOnly = State.friendOnly}) end)
        return true
    elseif raid.raidType == "bossRaid" and R.createRaid then
        pcall(function() R.createRaid:InvokeServer(raid.name, {friendsOnly = State.friendOnly, spawnNormal = false}) end)
        return true
    end
    return false
end

local function autoVoteCard()
    if not R.voteCard then return false end
    
    local bestCardObj = nil
    local bestPriority = 9999 -- High number = lower priority

    for _, obj in ipairs(pgui:GetDescendants()) do
        if obj:IsA("TextLabel") and obj.Visible then
            if obj:IsDescendantOf(pgui:FindFirstChild("AutoFarmGUI")) then continue end
            local t = string.lower(obj.Text)

            -- Check if this text matches any of our priorities
            for index, modName in ipairs(State.modifierPriorities) do
                if string.find(t, string.lower(modName)) then
                    if index < bestPriority then
                        bestPriority = index
                        bestCardObj = obj
                    end
                end
            end
        end
    end

    if bestCardObj then
        local current = bestCardObj.Parent
        for d = 1, 10 do
            if not current or current == pgui then break end
            if current.Name == "inner" then
                local tb = current:FindFirstChildOfClass("TextButton")
                if tb then
                    pcall(function()
                        for _, conn in pairs(getconnections(tb.Activated)) do
                            conn:Fire()
                        end
                    end)
                    print("[AF] Voted for priority modifier: " .. bestCardObj.Text .. " (Rank " .. bestPriority .. ")")
                    return true
                end
                break
            end
            current = current.Parent
        end
    end
    return false
end

local function startLobby() if R.lobbyStart then pcall(function() R.lobbyStart:FireServer() end) end end
local function leaveRaid() if R.leaveRaid then pcall(function() R.leaveRaid:FireServer() end) end end
local function replayInvasion() if R.replayInvasion then pcall(function() R.replayInvasion:InvokeServer() end) end end
local function equipBestWarriors() if R.warriorsEquipBest then pcall(function() R.warriorsEquipBest:FireServer() end) end end
local function claimAchievements()
    if R.achievementClaim then pcall(function() R.achievementClaim:FireServer() end) end
    if R.achievementClaimGroup then pcall(function() R.achievementClaimGroup:FireServer() end) end
end

-- =============================================
--  LOOPS
-- =============================================

local function farmLoop()
    while State.running do
        task.wait(0.2)
        if not State.autoFarm or not isInRaidArea() then task.wait(0.5); continue end
        if State.autoEquipWeapon then equipWeapon() end

        local enemies = getAliveEnemies()
        if #enemies > 0 then
            local _, myHRP = getChar()
            if myHRP then
                table.sort(enemies, function(a, b) return (myHRP.Position - a.hrp.Position).Magnitude < (myHRP.Position - b.hrp.Position).Magnitude end)
            end
            attackTarget(enemies[1])
        else
            local bossPos = State.selectedRaid.bossPos
            local _, hrp = getChar()
            if hrp and bossPos and (hrp.Position - bossPos.Position).Magnitude > 15 then
                hrp.CFrame = bossPos
                task.wait(0.1)
            end
            swingWeapon(); task.wait(0.1); swingWeapon()
        end
    end
end

local function raidCycleLoop()
    while State.running do
        task.wait(3)
        if not State.autoFarm or not State.autoCreateRaid or not State.selectedRaid.working then continue end

        -- Detect if we somehow entered the raid area manually or via restart
        if isInRaidArea() and not State.inRaid then
            print("[AF] Detected inside raid. Resuming.")
            State.inRaid = true
            task.wait(1)
            clickByText("start")
            startLobby()
            if State.autoEquipWeapon then equipWeapon() end
            continue
        end

        if not isInRaidArea() and not State.inRaid then
            local enemies = getAliveEnemies()
            if #enemies == 0 then
                local raid = State.selectedRaid
                if State.autoEquipBestPet then equipBestWarriors(); task.wait(0.5) end
                
                local _, hrp = getChar()
                if hrp then hrp.CFrame = raid.portalPos; task.wait(2) end

                if raid.raidType == "invasion" then
                    -- Trigger E prompt
                    local _, myHRP = getChar()
                    if myHRP then
                        for _, desc in ipairs(Workspace:GetDescendants()) do
                            if desc:IsA("ProximityPrompt") then
                                local part = desc.Parent
                                if part and part:IsA("BasePart") and (myHRP.Position - part.Position).Magnitude < 10 then
                                    pcall(function() fireproximityprompt(desc) end)
                                    break
                                end
                            end
                        end
                    end
                    task.wait(1)
                    clickByText("lead me to the invasion")
                    task.wait(2)
                    createRaid()
                    task.wait(4)
                else
                    createRaid()
                    task.wait(4)
                end

                local waited = 0
                while not isInRaidArea() and waited < 20 do task.wait(0.5); waited = waited + 0.5 end

                if isInRaidArea() then
                    task.wait(1)
                    for attempt = 1, 6 do if clickByText("start") then break end; task.wait(0.5) end
                    startLobby()
                    State.inRaid = true
                end
            end
        end
    end
end

local function victoryLoop()
    while State.running do
        task.wait(1)
        if not State.autoFarm then continue end

        if State.inRaid and State.selectedRaid.raidType == "invasion" then autoVoteCard() end

        local foundVictory = false
        for _, obj in ipairs(pgui:GetDescendants()) do
            if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and obj.Visible and not obj:IsDescendantOf(pgui:FindFirstChild("AutoFarmGUI")) then
                if string.find(string.lower(obj.Text), "victory") then
                    foundVictory = true; break
                end
            end
        end

        if foundVictory then
            print("[AF] Victory detected!")
            task.wait(2)
            
            -- Try to scrape rewards from UI (Looking for "+100 Gold" etc)
            local rewardsScraped = {}
            for _, obj in ipairs(pgui:GetDescendants()) do
                if obj:IsA("TextLabel") and obj.Visible and not obj:IsDescendantOf(pgui:FindFirstChild("AutoFarmGUI")) then
                    if obj.Text:match("^%+%d+") then table.insert(rewardsScraped, obj.Text) end
                end
            end
            local rewardString = #rewardsScraped > 0 and table.concat(rewardsScraped, ", ") or "Could not parse rewards."
            
            -- Trigger Webhook
            sendWebhookNotification(State.selectedRaid.display, rewardString)
            task.wait(1)

            if State.selectedRaid.raidType == "invasion" then
                local replayed = false
                for attempt = 1, 5 do
                    if clickExact("Replay") then replayed = true; break end
                    task.wait(1)
                end
                if not replayed then replayInvasion() end
                task.wait(3)
                -- We stay in raid area for invasions, do NOT change State.inRaid
            else
                leaveRaid()
                task.wait(3)
                if isInRaidArea() then
                    for attempt = 1, 5 do
                        clickExact("Continue")
                        task.wait(1)
                        leaveRaid()
                        if not isInRaidArea() then break end
                    end
                end
                task.wait(2)
                State.inRaid = false
            end
        end

        if State.inRaid and not isInRaidArea() then State.inRaid = false end
    end
end

local function utilityLoop()
    while State.running do
        task.wait(3)
        if State.autoClaimAchievement then pcall(claimAchievements) end
        if State.autoEquipWeapon then equipWeapon() end
    end
end

task.spawn(farmLoop)
task.spawn(raidCycleLoop)
task.spawn(victoryLoop)
task.spawn(utilityLoop)

-- =============================================
--  GUI
-- =============================================

local oldGui = pgui:FindFirstChild("AutoFarmGUI")
if oldGui then oldGui:Destroy() end

local sg = Instance.new("ScreenGui", pgui)
sg.Name = "AutoFarmGUI"
sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local C = {
    bg = Color3.fromRGB(16, 16, 22), bgCard = Color3.fromRGB(24, 24, 34),
    accent1 = Color3.fromRGB(120, 90, 255),
}

local floatBtn = Instance.new("TextButton", sg)
floatBtn.Size = UDim2.new(0, 44, 0, 44)
floatBtn.Position = UDim2.new(0, 8, 0.35, 0)
floatBtn.BackgroundColor3 = C.accent1; floatBtn.Text = ""
Instance.new("UICorner", floatBtn).CornerRadius = UDim.new(0, 14)

local floatIcon = Instance.new("TextLabel", floatBtn)
floatIcon.Size = UDim2.new(1,0,1,0); floatIcon.BackgroundTransparency = 1
floatIcon.Text = "AF"; floatIcon.TextColor3 = Color3.new(1,1,1)
floatIcon.TextSize = 13; floatIcon.Font = Enum.Font.GothamBold; floatIcon.ZIndex = 101

local fDrag = {on=false, s=nil, p=nil}
floatBtn.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
        fDrag.on = true
        fDrag.s = i.Position
        fDrag.p = floatBtn.Position
        
        -- Fixed up your dragging function logic!
        local endConn
        endConn = i.Changed:Connect(function()
            if i.UserInputState == Enum.UserInputState.End then
                fDrag.on = false
                endConn:Disconnect()
            end
        end)
    end
end)

floatBtn.InputChanged:Connect(function(i)
    if fDrag.on and (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseMovement) then
        local delta = i.Position - fDrag.s
        floatBtn.Position = UDim2.new(
            fDrag.p.X.Scale, fDrag.p.X.Offset + delta.X,
            fDrag.p.Y.Scale, fDrag.p.Y.Offset + delta.Y
        )
    end
end)