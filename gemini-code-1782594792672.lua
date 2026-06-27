-- =============================================
--  AUTO FARM GUI v4 — SUNSHINE + DARK MATTER
--  Supports both bossRaids and invasions
-- =============================================

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UIS               = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local player = Players.LocalPlayer
local pgui   = player:WaitForChild("PlayerGui", 10)

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
    -- Boss Raids (Sunshine Lake)
    createRaid      = getRemote("bossRaids", "create"),
    leaveRaid       = getRemote("bossRaids", "leaveRaid"),
    -- Invasions (Dark Matter)
    createInvasion  = getRemote("invasions", "create"),
    replayInvasion  = getRemote("invasions", "replay"),
    voteCard        = getRemote("invasions", "voteCard"),
    -- Shared
    lobbyStart      = getRemote("lobbies", "start"),
    weaponActivate  = getRemote("weapons", "activate"),
    sendAndRetreat  = getRemote("enemies", "sendAndRetreat"),
    toolbarEquip    = getRemote("toolbar", "equip"),
    toolbarUnequip  = getRemote("toolbar", "unequip"),
    warriorsEquipBest = getRemote("warriors", "equipBest"),
    achievementClaim      = getRemote("achievements", "claim"),
    achievementClaimGroup = getRemote("achievements", "claimGroup"),
}

local rc = 0
for _, v in pairs(R) do if v then rc = rc + 1 end end
print("[AF] Loaded " .. rc .. " remotes")

-- =============================================
--  RAID DATA
-- =============================================

local RaidList = {
    {
        name = "Sunshine Raid",
        display = "Sunshine Lake",
        raidType = "bossRaid",      -- uses bossRaids.create
        portalPos = CFrame.new(-653.9, -1471.1, 186.3),
        bossPos = CFrame.new(4982.6, 6007.8, -50.4),
        startText = "start raid",   -- UI button text to look for
        working = true,
    },
    {
        name = "Dark Matter Invasion",
        display = "Dark Matter",
        raidType = "invasion",       -- uses invasions.create
        portalPos = CFrame.new(-1743, -1490, -745),  -- Saitama NPC
        bossPos = CFrame.new(5068, 6030, -150),      -- boss area
        startText = "start invasion", -- UI button text
        working = true,
    },
}

-- =============================================
--  STATE
-- =============================================

getgenv().AFState = {
    webhookUrl           = "",       -- ADD YOUR WEBHOOK URL HERE
    sendWebhook          = true,     -- SET TO TRUE TO ENABLE WEBHOOK NOTIFICATIONS
    modifierPriority     = {         -- 1 IS HIGHEST PRIORITY. ADD EXACT CARD NAMES HERE:
        "Boss Killer",
        "Overflowing Wealth",
        "Espionage",
        "Reinforcement",
        "Momentum"
    },
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
}
local State = getgenv().AFState

-- =============================================
--  HELPERS
-- =============================================

local function sendWebhookLog(raidName)
    if State.webhookUrl == "" or not State.sendWebhook then return end
    local http_request = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    if not http_request then return end

    local data = {
        content = "",
        embeds = {
            {
                title = "🎉 Raid Completed!",
                description = "Successfully finished: **" .. tostring(raidName) .. "**\n*(Rewards claimed automatically)*",
                color = 5814783
            }
        }
    }
    pcall(function()
        http_request({
            Url = State.webhookUrl,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = game:GetService("HttpService"):JSONEncode(data)
        })
    end)
end

local RAID_Y_MIN = 5000

local function getChar()
    local c = player.Character
    if not c then return nil, nil end
    return c, c:FindFirstChild("HumanoidRootPart")
end

local function getEnemyFolder()
    local w = Workspace:FindFirstChild("World")
    return w and w:FindFirstChild("Enemies")
end

local function getWarriorFolder()
    local w = Workspace:FindFirstChild("World")
    return w and w:FindFirstChild("Warriors")
end

local function getWarriorUUIDs()
    local uuids = {}
    local f = getWarriorFolder()
    if not f then return uuids end
    for _, w in ipairs(f:GetChildren()) do
        if w:IsA("Model") then
            table.insert(uuids, w.Name)
        end
    end
    return uuids
end

local function isInRaidArea()
    local _, hrp = getChar()
    if not hrp then return false end
    return hrp.Position.Y > RAID_Y_MIN
end

-- =============================================
--  UNIVERSAL ENEMY DETECTION
--  Works for both Sunshine (minions have Humanoid)
--  and Dark Matter (minions have NO Humanoid, boss HAS Humanoid)
-- =============================================

local function getAliveEnemies()
    local enemies = {}
    local folder = getEnemyFolder()
    if not folder then return enemies end

    for _, e in ipairs(folder:GetChildren()) do
        if not e:IsA("Model") then continue end

        -- Must be alive
        local dead = e:GetAttribute("dead")
        if dead ~= false then continue end

        -- Find root part (HumanoidRootPart or Root)
        local hrp = e:FindFirstChild("HumanoidRootPart") or e:FindFirstChild("Root")
        if not hrp then continue end

        -- Must be in raid area
        if hrp.Position.Y < RAID_Y_MIN then continue end

        -- Check humanoid health if it has one
        local hum = e:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health <= 0 then continue end

        -- Get bounds to determine size (bigger = likely boss)
        local bounds = e:GetAttribute("bounds")
        local boundsX = bounds and bounds.X or 0

        table.insert(enemies, {
            model = e,
            uuid = e.Name,
            hrp = hrp,
            hasHumanoid = hum ~= nil,
            boundsX = boundsX,
            state = e:GetAttribute("_battleState") or "none",
        })
    end
    return enemies
end

-- =============================================
--  COMBAT
-- =============================================

local function teleportTo(targetHRP)
    local _, hrp = getChar()
    if not hrp or not targetHRP then return end
    hrp.CFrame = targetHRP.CFrame * CFrame.new(0, 0, 5)
end

local function swingWeapon()
    if not R.weaponActivate then return end
    local _, hrp = getChar()
    if not hrp then return end
    pcall(function()
        R.weaponActivate:FireServer(tick(), hrp.CFrame)
    end)
end

local function hitEnemy(uuid)
    if not R.sendAndRetreat then return end
    local warriors = getWarriorUUIDs()
    if #warriors == 0 then return end
    pcall(function()
        R.sendAndRetreat:FireServer(uuid, warriors)
    end)
end

local function equipWeapon()
    if R.toolbarEquip then
        pcall(function() R.toolbarEquip:FireServer("weapon") end)
    end
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
--  RAID MANAGEMENT
-- =============================================

local function clickByText(searchText)
    searchText = string.lower(searchText)

    for _, obj in ipairs(pgui:GetDescendants()) do
        if obj:IsA("TextLabel") and obj.Visible then
            if obj:IsDescendantOf(pgui:FindFirstChild("AutoFarmGUI")) then continue end
            if string.find(string.lower(obj.Text), searchText, 1, true) then

                local current = obj.Parent
                local innerFrame = nil
                for depth = 1, 8 do
                    if not current or current == pgui then break end
                    if current.Name == "inner" then
                        innerFrame = current
                        break
                    end
                    current = current.Parent
                end

                if innerFrame then
                    local textButton = innerFrame:FindFirstChildOfClass("TextButton")
                    if textButton then
                        pcall(function()
                            for _, conn in pairs(getconnections(textButton.Activated)) do
                                conn:Fire()
                            end
                        end)
                        print("[AF] Clicked '" .. searchText .. "' via inner.TextButton.Activated")
                        return true
                    end
                end

                local parent = obj.Parent
                if parent then
                    for _, desc in ipairs(parent:GetDescendants()) do
                        if desc:IsA("TextButton") then
                            pcall(function()
                                for _, conn in pairs(getconnections(desc.Activated)) do
                                    conn:Fire()
                                end
                            end)
                            print("[AF] Clicked '" .. searchText .. "' via parent descendant TextButton")
                            return true
                        end
                    end
                end

                parent = obj.Parent
                for depth = 1, 6 do
                    if not parent or parent == pgui then break end
                    for _, child in ipairs(parent:GetChildren()) do
                        if child:IsA("TextButton") then
                            pcall(function()
                                for _, conn in pairs(getconnections(child.Activated)) do
                                    conn:Fire()
                                end
                            end)
                            print("[AF] Clicked '" .. searchText .. "' via sibling TextButton")
                            return true
                        end
                    end
                    parent = parent.Parent
                end
            end
        end
    end
    print("[AF] Could not find '" .. searchText .. "'")
    return false
end

-- Click exact text match (for Continue/Replay)
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
                        pcall(function()
                            for _, conn in pairs(getconnections(tb.Activated)) do
                                conn:Fire()
                            end
                        end)
                        print("[AF] Clicked exact '" .. exactText .. "'")
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
    if not raid.working then
        print("[AF] " .. raid.display .. " not configured yet")
        return false
    end

    -- Try clicking the start button in game UI
    print("[AF] Looking for " .. raid.startText .. " button...")

    -- For Dark Matter: first click "lead me to the invasion" if talking to NPC
    if raid.raidType == "invasion" then
        clickByText("lead me to the invasion")
        task.wait(1)
    end

    if clickByText(raid.startText) then
        task.wait(1.5)

        if State.friendOnly then
            clickByText("friends only")
            task.wait(0.5)
        end

        task.wait(0.5)
        if clickByText("yes") then
            print("[AF] Clicked Yes!")
            return true
        end
    end

    -- Fallback to direct InvokeServer
    print("[AF] Button click failed, trying InvokeServer...")
    if raid.raidType == "invasion" and R.createInvasion then
        local ok, err = pcall(function()
            R.createInvasion:InvokeServer(raid.name, {
                friendsOnly = State.friendOnly,
            })
        end)
        if ok then print("[AF] Invasion InvokeServer succeeded!"); return true
        else print("[AF] Invasion InvokeServer failed: " .. tostring(err)) end
    elseif raid.raidType == "bossRaid" and R.createRaid then
        local ok, err = pcall(function()
            R.createRaid:InvokeServer(raid.name, {
                friendsOnly = State.friendOnly,
                spawnNormal = false,
            })
        end)
        if ok then print("[AF] Raid InvokeServer succeeded!"); return true
        else print("[AF] Raid InvokeServer failed: " .. tostring(err)) end
    end

    return false
end

local function startLobby()
    if R.lobbyStart then
        pcall(function() R.lobbyStart:FireServer() end)
        print("[AF] Lobby force started")
    end
end

local function leaveRaid()
    if R.leaveRaid then
        pcall(function() R.leaveRaid:FireServer() end)
        print("[AF] Left raid")
    end
end

local function replayInvasion()
    if R.replayInvasion then
        pcall(function() R.replayInvasion:InvokeServer() end)
        print("[AF] Replay invasion!")
    end
end

local function equipBestWarriors()
    if R.warriorsEquipBest then
        pcall(function() R.warriorsEquipBest:FireServer() end)
    end
end

-- Fire the ProximityPrompt "E" button via its inner TextButton
local function pressE()
    local prompts = pgui:FindFirstChild("ProximityPrompts")
    if not prompts then return false end
    for _, desc in ipairs(prompts:GetDescendants()) do
        if desc:IsA("TextButton") and desc.Parent and desc.Parent.Name == "inner" then
            pcall(function()
                for _, conn in pairs(getconnections(desc.Activated)) do
                    conn:Fire()
                end
            end)
            print("[AF] Pressed E via ProximityPrompts.inner.TextButton")
            return true
        end
    end
    return false
end

-- Click a dialog option by matching text in dialogue BillboardGui
local function clickDialog(searchText)
    searchText = string.lower(searchText)
    local dialogue = pgui:FindFirstChild("dialogue")
    if not dialogue then return false end
    for _, obj in ipairs(dialogue:GetDescendants()) do
        if obj:IsA("TextLabel") and obj.Visible then
            if string.find(string.lower(obj.Text), searchText, 1, true) then
                -- Find sibling TextButton in same parent Frame
                local parent = obj.Parent
                if parent then
                    for _, sibling in ipairs(parent:GetChildren()) do
                        if sibling:IsA("TextButton") then
                            pcall(function()
                                for _, conn in pairs(getconnections(sibling.Activated)) do
                                    conn:Fire()
                                end
                            end)
                            print("[AF] Clicked dialog: '" .. searchText .. "'")
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

local function claimAchievements()
    if R.achievementClaim then pcall(function() R.achievementClaim:FireServer() end) end
    if R.achievementClaimGroup then pcall(function() R.achievementClaimGroup:FireServer() end) end
end

-- =============================================
--  AUTO CARD VOTING (Invasions only)
-- =============================================

local function autoVoteCard()
    if not R.voteCard then return end
    
    local bestCardObj = nil
    local bestPriority = 9999

    for _, obj in ipairs(pgui:GetDescendants()) do
        if obj:IsA("TextLabel") and obj.Visible then
            if obj:IsDescendantOf(pgui:FindFirstChild("AutoFarmGUI")) then continue end
            local t = obj.Text

            for i, modName in ipairs(State.modifierPriority) do
                if string.find(string.lower(t), string.lower(modName), 1, true) then
                    if i < bestPriority then
                        bestPriority = i
                        bestCardObj = obj
                    end
                end
            end
        end
    end

    if bestCardObj then
        -- Click the highest priority card
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
                    print("[AF] Voted for priority " .. bestPriority .. " card: " .. bestCardObj.Text)
                    return true
                end
                break
            end
            current = current.Parent
        end
    end
    return false
end

-- =============================================
--  MAIN FARM LOOP
-- =============================================

local function farmLoop()
    while State.running do
        task.wait(0.2)
        if not State.autoFarm then task.wait(0.5); continue end
        if not isInRaidArea() then task.wait(1); continue end

        if State.autoEquipWeapon then equipWeapon() end

        local enemies = getAliveEnemies()

        if #enemies > 0 then
            -- Sort by distance
            local _, myHRP = getChar()
            if myHRP then
                table.sort(enemies, function(a, b)
                    return (myHRP.Position - a.hrp.Position).Magnitude
                         < (myHRP.Position - b.hrp.Position).Magnitude
                end)
            end
            attackTarget(enemies[1])
        else
            -- No enemies alive = between waves or boss dead
            -- Teleport to boss area and swing (catches spawning enemies)
            local bossPos = State.selectedRaid.bossPos
            if bossPos then
                local _, hrp = getChar()
                if hrp then
                    local dist = (hrp.Position - bossPos.Position).Magnitude
                    if dist > 15 then
                        hrp.CFrame = bossPos
                        task.wait(0.1)
                    end
                end
            end
            swingWeapon()
            task.wait(0.1)
            swingWeapon()
        end
    end
end

-- =============================================
--  RAID CYCLE LOOP
-- =============================================

local function raidCycleLoop()
    while State.running do
        task.wait(3)
        if not State.autoFarm or not State.autoCreateRaid then continue end
        if not State.selectedRaid.working then continue end

        -- Prevent lobby teleport if we started the script while already inside the raid
        if isInRaidArea() and not State.inRaid then
            State.inRaid = true
            print("[AF] Script started inside raid. Teleport to bald hero prevented.")
        end

        if not isInRaidArea() and not State.inRaid then
            local enemies = getAliveEnemies()
            if #enemies == 0 then
                local raid = State.selectedRaid
                print("[AF] In lobby, starting " .. raid.display .. "...")

                if State.autoEquipBestPet then
                    equipBestWarriors()
                    task.wait(0.5)
                end
                if State.autoEquipWeapon then
                    equipWeapon()
                    task.wait(0.3)
                end

                -- Teleport to portal/NPC
                local _, hrp = getChar()
                if hrp then
                    print("[AF] Teleporting to " .. raid.display .. " portal...")
                    hrp.CFrame = raid.portalPos
                    task.wait(2)
                end

                if raid.raidType == "invasion" then
                    -- Step 1: Press E ONCE (small radius to avoid wrong NPC)
                    local _, myHRP = getChar()
                    if myHRP then
                        for _, desc in ipairs(Workspace:GetDescendants()) do
                            if desc:IsA("ProximityPrompt") then
                                local part = desc.Parent
                                if part and part:IsA("BasePart") then
                                    local dist = (myHRP.Position - part.Position).Magnitude
                                    if dist < 10 then
                                        pcall(function() fireproximityprompt(desc) end)
                                        print("[AF] Pressed E (dist=" .. math.floor(dist) .. ")")
                                        break
                                    end
                                end
                            end
                        end
                    end

                    -- Step 2: Wait up to 5s for dialog, do NOT press E again
                    local foundLead = false
                    for attempt = 1, 10 do
                        for _, obj in ipairs(pgui:GetDescendants()) do
                            if obj:IsA("TextLabel") and obj.Visible then
                                if string.find(string.lower(obj.Text), "lead me", 1, true) then
                                    foundLead = true
                                    break
                                end
                            end
                        end
                        if foundLead then break end
                        task.wait(0.5)
                    end

                    -- Step 3: Click "Lead me to the invasion"
                    if foundLead then
                        task.wait(0.3)
                        clickByText("lead me to the invasion")
                        print("[AF] Clicked Lead me!")
                        task.wait(2)
                    else
                        print("[AF] Dialog didn't appear, retrying...")
                        continue
                    end

                    -- Step 4: Wait for Start Invasion UI (same flow as Sunshine)
                    local uiFound = false
                    for attempt = 1, 10 do
                        for _, obj in ipairs(pgui:GetDescendants()) do
                            if obj:IsA("TextLabel") and obj.Visible then
                                if string.find(string.lower(obj.Text), "start invasion", 1, true) then
                                    uiFound = true
                                    break
                                end
                            end
                        end
                        if uiFound then break end
                        task.wait(0.5)
                    end

                    if not uiFound then
                        print("[AF] Start Invasion UI not found, retrying...")
                        continue
                    end

                    -- Step 5: Click Start Invasion -> Yes (exactly like Sunshine Lake)
                    createRaid()
                    task.wait(4)

                else
                    -- BOSS RAID: Use UI click flow (Start Raid -> Yes)
                    local uiFound = false
                    for attempt = 1, 10 do
                        for _, obj in ipairs(pgui:GetDescendants()) do
                            if obj:IsA("TextLabel") and obj.Visible then
                                if string.find(string.lower(obj.Text), raid.startText, 1, true) then
                                    uiFound = true
                                    break
                                end
                            end
                        end
                        if uiFound then break end
                        task.wait(0.5)
                    end

                    if not uiFound then
                        print("[AF] Raid UI didn't appear, retrying...")
                        continue
                    end

                    createRaid()
                    task.wait(4)
                end

                -- Wait for teleport into raid
                local waited = 0
                while not isInRaidArea() and waited < 20 do
                    task.wait(0.5)
                    waited = waited + 0.5
                end

                if isInRaidArea() then
                    print("[AF] In raid area!")
                    task.wait(1)

                    for attempt = 1, 6 do
                        if clickByText("start") then
                            print("[AF] Clicked Start inside raid!")
                            break
                        end
                        task.wait(0.5)
                    end

                    startLobby()
                    task.wait(2)

                    if State.autoEquipWeapon then equipWeapon() end
                    State.inRaid = true
                    print("[AF] Farming started!")
                else
                    print("[AF] Failed to enter raid, retrying...")
                end
            end
        end
    end
end

-- =============================================
--  VICTORY DETECTION LOOP
-- =============================================

local function victoryLoop()
    while State.running do
        task.wait(1)
        if not State.autoFarm then continue end

        -- Auto vote for cards (invasions)
        if State.inRaid and State.selectedRaid.raidType == "invasion" then
            autoVoteCard()
        end

        -- Check for Victory UI
        local foundVictory = false
        for _, obj in ipairs(pgui:GetDescendants()) do
            if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and obj.Visible then
                if obj:IsDescendantOf(pgui:FindFirstChild("AutoFarmGUI")) then continue end
                local t = string.lower(obj.Text)
                if string.find(t, "victory") then
                    foundVictory = true
                    break
                end
            end
        end

        if foundVictory then
            print("[AF] Victory detected!")
            task.wait(3)

            local raid = State.selectedRaid
            sendWebhookLog(raid.display)

            if raid.raidType == "invasion" then
                -- INVASION: Click Replay to restart immediately
                print("[AF] Clicking Replay...")
                local replayed = false
                for attempt = 1, 5 do
                    if clickExact("Replay") then
                        replayed = true
                        break
                    end
                    task.wait(1)
                end

                -- Also fire remote directly as backup
                if not replayed then
                    replayInvasion()
                end

                task.wait(3)
                -- After replay we stay in raid area (new instance)
                -- Don't set inRaid = false, just keep farming
                print("[AF] Replay invasion processing, continuing farm!")

            else
                -- BOSS RAID: Click Continue then leaveRaid
                leaveRaid()
                print("[AF] Called leaveRaid!")
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
                -- raidCycleLoop will handle re-creating
            end
        end

        -- Backup: detect teleport back to lobby
        if State.inRaid and not isInRaidArea() then
            print("[AF] Returned to lobby (teleport detected)")
            State.inRaid = false
        end
    end
end

-- =============================================
--  UTILITY LOOP
-- =============================================

local function utilityLoop()
    while State.running do
        task.wait(3)
        if State.autoClaimAchievement then pcall(claimAchievements) end
        -- Keep weapon equipped at all times
        if State.autoEquipWeapon then equipWeapon() end
    end
end

-- =============================================
--  GUI — REDESIGNED
-- =============================================

local oldGui = pgui:FindFirstChild("AutoFarmGUI")
if oldGui then oldGui:Destroy() end

local sg = Instance.new("ScreenGui", pgui)
sg.Name = "AutoFarmGUI"
sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- Color palette — deep space theme
local C = {
    bg       = Color3.fromRGB(16, 16, 22),
    bgCard   = Color3.fromRGB(24, 24, 34),
    card     = Color3.fromRGB(30, 30, 42),
    cardHi   = Color3.fromRGB(38, 38, 52),
    border   = Color3.fromRGB(48, 48, 66),
    borderHi = Color3.fromRGB(70, 70, 100),
    text     = Color3.fromRGB(225, 225, 235),
    textDim  = Color3.fromRGB(100, 100, 125),
    textMid  = Color3.fromRGB(160, 160, 180),
    accent1  = Color3.fromRGB(120, 90, 255),   -- purple
    accent2  = Color3.fromRGB(60, 200, 160),    -- teal
    accent3  = Color3.fromRGB(255, 180, 50),    -- amber
    accent4  = Color3.fromRGB(255, 80, 120),    -- rose
    accent5  = Color3.fromRGB(80, 160, 255),    -- sky
    green    = Color3.fromRGB(50, 205, 110),
    red      = Color3.fromRGB(220, 60, 70),
    toggleOff = Color3.fromRGB(50, 50, 65),
}

-- =============================================
--  FLOATING BUTTON (pill shaped, gradient)
-- =============================================

local floatBtn = Instance.new("TextButton", sg)
floatBtn.Size = UDim2.new(0, 44, 0, 44)
floatBtn.Position = UDim2.new(0, 8, 0.35, 0)
floatBtn.BackgroundColor3 = C.accent1; floatBtn.Text = ""
floatBtn.TextColor3 = Color3.new(1,1,1); floatBtn.TextSize = 14
floatBtn.Font = Enum.Font.GothamBold; floatBtn.BorderSizePixel = 0; floatBtn.ZIndex = 100
Instance.new("UICorner", floatBtn).CornerRadius = UDim.new(0, 14)
local floatStroke = Instance.new("UIStroke", floatBtn)
floatStroke.Color = Color3.fromRGB(160, 140, 255); floatStroke.Thickness = 1.5; floatStroke.Transparency = 0.4
-- Icon label inside
local floatIcon = Instance.new("TextLabel", floatBtn)
floatIcon.Size = UDim2.new(1,0,1,0); floatIcon.BackgroundTransparency = 1
floatIcon.Text = "AF"; floatIcon.TextColor3 = Color3.new(1,1,1)
floatIcon.TextSize = 13; floatIcon.Font = Enum.Font.GothamBold; floatIcon.ZIndex = 101

local mainFrame -- forward declare
local fDrag = {on=false, s=nil, p=nil}
floatBtn.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
        fDrag.on=true; fDrag.s=i.Position; fDrag.p=floatBtn.Position
        i.Changed:Connect(function()
