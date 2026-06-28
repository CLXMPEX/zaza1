-- =============================================
--  AUTO FARM GUI v5 — WEBHOOK + MODIFIER PRIORITY
--  Supports Sunshine Lake + Dark Matter Invasion
-- =============================================

-- ▼▼▼ PASTE YOUR DISCORD WEBHOOK URL HERE ▼▼▼
local WEBHOOK_URL = ""
-- ▲▲▲ Example: "https://discord.com/api/webhooks/123/abc" ▲▲▲

-- ▼▼▼ MODIFIER PRIORITY (1 = highest, picked first) ▼▼▼
-- Reorder these to change which card gets picked first
local ModifierPriority = {
    "Boss Killer",            -- Boss damage boost
    "Espionage",              -- Boss stun + damage
    "Battle Momentum",        -- Damage per wave
    "Overflowing Wealth",     -- More coins/wealth
    "Warrior Reinforcement",  -- Clone a warrior
}
-- ▲▲▲ Move your favorite to the top ▲▲▲

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UIS               = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local HttpService       = game:GetService("HttpService")

local player = Players.LocalPlayer
local pgui   = player:WaitForChild("PlayerGui", 10)

-- =============================================
--  WEBHOOK
-- =============================================

local raidCount = 0

local function sendWebhook(title, description, color, fields)
    if WEBHOOK_URL == "" then return end
    local embed = {
        title = title,
        description = description,
        color = color or 5793266,
        fields = fields or {},
        footer = {text = "Auto Farm v5 | " .. player.Name},
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
    local body = HttpService:JSONEncode({
        embeds = {embed},
    })
    local httpReq = request or http_request or (syn and syn.request)
    if httpReq then
        pcall(function()
            httpReq({
                Url = WEBHOOK_URL,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = body,
            })
        end)
        print("[AF] Webhook sent!")
    end
end

-- Scrape victory screen for rewards info
local function scrapeVictoryInfo()
    local info = {time = "?", damage = "?", drops = {}}
    for _, obj in ipairs(pgui:GetDescendants()) do
        if not obj:IsA("TextLabel") or not obj.Visible then continue end
        if obj:IsDescendantOf(pgui:FindFirstChild("AutoFarmGUI")) then continue end
        local t = obj.Text
        -- Time taken
        if string.find(t, "m%s*%d+s") or string.find(t, "%d+s$") then
            if string.find(t, "%d") and #t < 20 then
                info.time = t
            end
        end
        -- Total damage
        if string.find(t, "%d+%.?%d*[BMKTbmkt]") and #t < 15 then
            if not info.damageSet then
                info.damage = t
            end
        end
        -- Boss Raid title
        if string.find(t, "Boss Raid") or string.find(t, "Invasion") then
            if #t < 60 then info.raidName = t end
        end
    end
    return info
end

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
    createRaid      = getRemote("bossRaids", "create"),
    leaveRaid       = getRemote("bossRaids", "leaveRaid"),
    createInvasion  = getRemote("invasions", "create"),
    replayInvasion  = getRemote("invasions", "replay"),
    voteCard        = getRemote("invasions", "voteCard"),
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
        name = "Sunshine Raid", display = "Sunshine Lake",
        raidType = "bossRaid",
        portalPos = CFrame.new(-653.9, -1471.1, 186.3),
        bossPos = CFrame.new(4982.6, 6007.8, -50.4),
        startText = "start raid", working = true,
    },
    {
        name = "Dark Matter Invasion", display = "Dark Matter",
        raidType = "invasion",
        portalPos = CFrame.new(-1743, -1490, -745),
        bossPos = CFrame.new(5068, 6030, -150),
        startText = "start invasion", working = true,
    },
}

-- =============================================
--  STATE
-- =============================================

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
}
local State = getgenv().AFState

-- =============================================
--  HELPERS
-- =============================================

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

local function getWarriorUUIDs()
    local uuids = {}
    local w = Workspace:FindFirstChild("World")
    local f = w and w:FindFirstChild("Warriors")
    if not f then return uuids end
    for _, w2 in ipairs(f:GetChildren()) do
        if w2:IsA("Model") then table.insert(uuids, w2.Name) end
    end
    return uuids
end

local function isInRaidArea()
    local _, hrp = getChar()
    if not hrp then return false end
    return hrp.Position.Y > RAID_Y_MIN
end

local function getAliveEnemies()
    local enemies = {}
    local folder = getEnemyFolder()
    if not folder then return enemies end
    for _, e in ipairs(folder:GetChildren()) do
        if not e:IsA("Model") then continue end
        local dead = e:GetAttribute("dead")
        if dead ~= false then continue end
        local hrp = e:FindFirstChild("HumanoidRootPart") or e:FindFirstChild("Root")
        if not hrp then continue end
        if hrp.Position.Y < RAID_Y_MIN then continue end
        local hum = e:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health <= 0 then continue end
        local bounds = e:GetAttribute("bounds")
        table.insert(enemies, {
            model = e, uuid = e.Name, hrp = hrp,
            hasHumanoid = hum ~= nil,
            boundsX = bounds and bounds.X or 0,
            state = e:GetAttribute("_battleState") or "none",
        })
    end
    return enemies
end

-- =============================================
--  COMBAT
-- =============================================

local function swingWeapon()
    if not R.weaponActivate then return end
    local _, hrp = getChar()
    if not hrp then return end
    pcall(function() R.weaponActivate:FireServer(tick(), hrp.CFrame) end)
end

local function hitEnemy(uuid)
    if not R.sendAndRetreat then return end
    local warriors = getWarriorUUIDs()
    if #warriors == 0 then return end
    pcall(function() R.sendAndRetreat:FireServer(uuid, warriors) end)
end

local function equipWeapon()
    if R.toolbarEquip then pcall(function() R.toolbarEquip:FireServer("weapon") end) end
end

local function attackTarget(target)
    local _, hrp = getChar()
    if hrp and target.hrp then hrp.CFrame = target.hrp.CFrame * CFrame.new(0, 0, 5) end
    task.wait(0.05); swingWeapon()
    task.wait(0.05); hitEnemy(target.uuid)
    task.wait(0.05); swingWeapon()
end

-- =============================================
--  UI CLICK HELPERS
-- =============================================

local function clickByText(searchText)
    searchText = string.lower(searchText)
    for _, obj in ipairs(pgui:GetDescendants()) do
        if obj:IsA("TextLabel") and obj.Visible then
            if obj:IsDescendantOf(pgui:FindFirstChild("AutoFarmGUI")) then continue end
            if string.find(string.lower(obj.Text), searchText, 1, true) then
                -- Walk up to inner
                local current = obj.Parent
                for depth = 1, 8 do
                    if not current or current == pgui then break end
                    if current.Name == "inner" then
                        local tb = current:FindFirstChildOfClass("TextButton")
                        if tb then
                            pcall(function() for _, c in pairs(getconnections(tb.Activated)) do c:Fire() end end)
                            print("[AF] Clicked '" .. searchText .. "'")
                            return true
                        end
                    end
                    current = current.Parent
                end
                -- Fallback: parent descendants
                local parent = obj.Parent
                if parent then
                    for _, desc in ipairs(parent:GetDescendants()) do
                        if desc:IsA("TextButton") then
                            pcall(function() for _, c in pairs(getconnections(desc.Activated)) do c:Fire() end end)
                            print("[AF] Clicked '" .. searchText .. "' (fallback)")
                            return true
                        end
                    end
                end
                -- Fallback: walk up siblings
                parent = obj.Parent
                for depth = 1, 6 do
                    if not parent or parent == pgui then break end
                    for _, child in ipairs(parent:GetChildren()) do
                        if child:IsA("TextButton") then
                            pcall(function() for _, c in pairs(getconnections(child.Activated)) do c:Fire() end end)
                            return true
                        end
                    end
                    parent = parent.Parent
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
                        pcall(function() for _, c in pairs(getconnections(tb.Activated)) do c:Fire() end end)
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

-- =============================================
--  RAID MANAGEMENT
-- =============================================

local function createRaid()
    local raid = State.selectedRaid
    if not raid.working then return false end

    if raid.raidType == "invasion" then
        clickByText("lead me to the invasion")
        task.wait(1)
    end

    if clickByText(raid.startText) then
        task.wait(1.5)
        if State.friendOnly then clickByText("friends only"); task.wait(0.5) end
        task.wait(0.5)
        if clickByText("yes") then return true end
    end

    -- Fallback: direct remote
    if raid.raidType == "invasion" and R.createInvasion then
        pcall(function() R.createInvasion:InvokeServer(raid.name, {friendsOnly = State.friendOnly}) end)
        return true
    elseif raid.raidType == "bossRaid" and R.createRaid then
        pcall(function() R.createRaid:InvokeServer(raid.name, {friendsOnly = State.friendOnly, spawnNormal = false}) end)
        return true
    end
    return false
end

local function startLobby()
    if R.lobbyStart then pcall(function() R.lobbyStart:FireServer() end) end
end

local function leaveRaid()
    if R.leaveRaid then pcall(function() R.leaveRaid:FireServer() end) end
end

local function replayInvasion()
    if R.replayInvasion then pcall(function() R.replayInvasion:InvokeServer() end) end
end

local function equipBestWarriors()
    if R.warriorsEquipBest then pcall(function() R.warriorsEquipBest:FireServer() end) end
end

local function claimAchievements()
    if R.achievementClaim then pcall(function() R.achievementClaim:FireServer() end) end
    if R.achievementClaimGroup then pcall(function() R.achievementClaimGroup:FireServer() end) end
end

-- =============================================
--  MODIFIER VOTING WITH PRIORITY + TIERS
--  Picks highest tier (III > II > I) of highest priority modifier
-- =============================================

-- Tier value: higher = better
local function getTierValue(text)
    if string.find(text, "III") then return 3 end
    if string.find(text, "II") then return 2 end
    if string.find(text, " I") then return 1 end
    return 0 -- no tier (Espionage, etc)
end

local function autoVoteCard()
    if not R.voteCard then return false end

    -- Step 1: Collect all visible card titles and their GUI objects
    local foundCards = {} -- {modName, fullText, tierValue, guiObj}
    for _, obj in ipairs(pgui:GetDescendants()) do
        if obj:IsA("TextLabel") and obj.Visible then
            if obj:IsDescendantOf(pgui:FindFirstChild("AutoFarmGUI")) then continue end
            local t = obj.Text
            for priIdx, modName in ipairs(ModifierPriority) do
                if string.find(t, modName, 1, true) then
                    table.insert(foundCards, {
                        modName = modName,
                        fullText = t,
                        tier = getTierValue(t),
                        priority = priIdx,
                        obj = obj,
                    })
                end
            end
        end
    end

    if #foundCards == 0 then return false end

    -- Step 2: Sort by priority first, then by tier (highest tier wins)
    table.sort(foundCards, function(a, b)
        if a.priority ~= b.priority then
            return a.priority < b.priority -- lower index = higher priority
        end
        return a.tier > b.tier -- higher tier wins
    end)

    -- Step 3: Click the best card
    local best = foundCards[1]
    local current = best.obj.Parent
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
                print("[AF] Voted: " .. best.fullText .. " (tier " .. best.tier .. ")")
                return true
            end
            break
        end
        current = current.Parent
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
            local _, myHRP = getChar()
            if myHRP then
                table.sort(enemies, function(a, b)
                    return (myHRP.Position - a.hrp.Position).Magnitude < (myHRP.Position - b.hrp.Position).Magnitude
                end)
            end
            attackTarget(enemies[1])
        else
            local bossPos = State.selectedRaid.bossPos
            if bossPos then
                local _, hrp = getChar()
                if hrp and (hrp.Position - bossPos.Position).Magnitude > 15 then
                    hrp.CFrame = bossPos; task.wait(0.1)
                end
            end
            swingWeapon(); task.wait(0.1); swingWeapon()
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

        -- Only create raid if NOT in raid area and NOT marked as in raid
        if not isInRaidArea() and not State.inRaid then
            local enemies = getAliveEnemies()
            if #enemies == 0 then
                local raid = State.selectedRaid
                print("[AF] In lobby, starting " .. raid.display .. "...")

                if State.autoEquipBestPet then equipBestWarriors(); task.wait(0.5) end
                if State.autoEquipWeapon then equipWeapon(); task.wait(0.3) end

                -- Teleport to portal/NPC
                local _, hrp = getChar()
                if hrp then
                    hrp.CFrame = raid.portalPos
                    task.wait(2)
                end

                if raid.raidType == "invasion" then
                    -- Press E ONCE (10 stud radius)
                    local _, myHRP = getChar()
                    if myHRP then
                        for _, desc in ipairs(Workspace:GetDescendants()) do
                            if desc:IsA("ProximityPrompt") then
                                local part = desc.Parent
                                if part and part:IsA("BasePart") then
                                    if (myHRP.Position - part.Position).Magnitude < 10 then
                                        pcall(function() fireproximityprompt(desc) end)
                                        print("[AF] Pressed E")
                                        break
                                    end
                                end
                            end
                        end
                    end

                    -- Wait up to 5s for dialog (do NOT press E again)
                    local foundLead = false
                    for attempt = 1, 10 do
                        for _, obj in ipairs(pgui:GetDescendants()) do
                            if obj:IsA("TextLabel") and obj.Visible then
                                if string.find(string.lower(obj.Text), "lead me", 1, true) then
                                    foundLead = true; break
                                end
                            end
                        end
                        if foundLead then break end
                        task.wait(0.5)
                    end

                    if foundLead then
                        task.wait(0.3)
                        clickByText("lead me to the invasion")
                        task.wait(2)
                    else
                        print("[AF] Dialog didn't appear, retrying...")
                        continue
                    end

                    -- Wait for Start Invasion UI
                    local uiFound = false
                    for attempt = 1, 10 do
                        for _, obj in ipairs(pgui:GetDescendants()) do
                            if obj:IsA("TextLabel") and obj.Visible then
                                if string.find(string.lower(obj.Text), "start invasion", 1, true) then
                                    uiFound = true; break
                                end
                            end
                        end
                        if uiFound then break end
                        task.wait(0.5)
                    end

                    if not uiFound then continue end
                    createRaid()
                    task.wait(4)
                else
                    -- Boss raid flow
                    local uiFound = false
                    for attempt = 1, 10 do
                        for _, obj in ipairs(pgui:GetDescendants()) do
                            if obj:IsA("TextLabel") and obj.Visible then
                                if string.find(string.lower(obj.Text), raid.startText, 1, true) then
                                    uiFound = true; break
                                end
                            end
                        end
                        if uiFound then break end
                        task.wait(0.5)
                    end
                    if not uiFound then continue end
                    createRaid()
                    task.wait(4)
                end

                -- Wait for teleport into raid
                local waited = 0
                while not isInRaidArea() and waited < 20 do
                    task.wait(0.5); waited = waited + 0.5
                end

                if isInRaidArea() then
                    task.wait(1)
                    for attempt = 1, 6 do
                        if clickByText("start") then break end
                        task.wait(0.5)
                    end
                    startLobby(); task.wait(2)
                    if State.autoEquipWeapon then equipWeapon() end
                    State.inRaid = true
                    print("[AF] Farming started!")
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

        -- Auto vote for cards (invasions) — uses priority system
        if State.inRaid and State.selectedRaid.raidType == "invasion" then
            autoVoteCard()
        end

        -- Check for Victory UI
        local foundVictory = false
        for _, obj in ipairs(pgui:GetDescendants()) do
            if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and obj.Visible then
                if obj:IsDescendantOf(pgui:FindFirstChild("AutoFarmGUI")) then continue end
                if string.find(string.lower(obj.Text), "victory") then
                    foundVictory = true; break
                end
            end
        end

        if foundVictory then
            raidCount = raidCount + 1
            print("[AF] Victory #" .. raidCount .. "!")
            task.wait(2)

            -- Scrape rewards and send webhook
            local info = scrapeVictoryInfo()
            sendWebhook(
                "Raid Complete #" .. raidCount,
                "**" .. State.selectedRaid.display .. "** finished!",
                5793266,
                {
                    {name = "Raid", value = info.raidName or State.selectedRaid.display, inline = true},
                    {name = "Time", value = info.time, inline = true},
                    {name = "Damage", value = info.damage, inline = true},
                    {name = "Total Runs", value = tostring(raidCount), inline = true},
                }
            )

            task.wait(1)
            local raid = State.selectedRaid

            if raid.raidType == "invasion" then
                -- INVASION: Click Replay — do NOT leave raid area
                local replayed = false
                for attempt = 1, 5 do
                    if clickExact("Replay") then replayed = true; break end
                    task.wait(1)
                end
                if not replayed then replayInvasion() end
                task.wait(3)
                -- Stay in raid, keep farming — do NOT set inRaid = false
                -- do NOT teleport to Bald Hero
                print("[AF] Replaying invasion #" .. raidCount)
            else
                -- BOSS RAID: Leave and restart
                leaveRaid()
                task.wait(3)
                if isInRaidArea() then
                    for attempt = 1, 5 do
                        clickExact("Continue")
                        task.wait(1); leaveRaid()
                        if not isInRaidArea() then break end
                    end
                end
                task.wait(2)
                State.inRaid = false
            end
        end

        -- Backup: detect unexpected lobby return
        if State.inRaid and not isInRaidArea() then
            print("[AF] Returned to lobby")
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
        if State.autoEquipWeapon then equipWeapon() end
    end
end

-- =============================================
--  GUI
-- =============================================

local oldGui = pgui:FindFirstChild("AutoFarmGUI")
if oldGui then oldGui:Destroy() end

local sg = Instance.new("ScreenGui", pgui)
sg.Name = "AutoFarmGUI"; sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local C = {
    bg = Color3.fromRGB(16, 16, 22), bgCard = Color3.fromRGB(24, 24, 34),
    card = Color3.fromRGB(30, 30, 42), cardHi = Color3.fromRGB(38, 38, 52),
    border = Color3.fromRGB(48, 48, 66), text = Color3.fromRGB(225, 225, 235),
    textDim = Color3.fromRGB(100, 100, 125), textMid = Color3.fromRGB(160, 160, 180),
    accent1 = Color3.fromRGB(120, 90, 255), accent2 = Color3.fromRGB(60, 200, 160),
    accent3 = Color3.fromRGB(255, 180, 50), accent4 = Color3.fromRGB(255, 80, 120),
    accent5 = Color3.fromRGB(80, 160, 255), green = Color3.fromRGB(50, 205, 110),
    red = Color3.fromRGB(220, 60, 70), toggleOff = Color3.fromRGB(50, 50, 65),
}

-- Float button
local floatBtn = Instance.new("TextButton", sg)
floatBtn.Size = UDim2.new(0, 44, 0, 44)
floatBtn.Position = UDim2.new(0, 8, 0.35, 0)
floatBtn.BackgroundColor3 = C.accent1; floatBtn.Text = ""
floatBtn.BorderSizePixel = 0; floatBtn.ZIndex = 100
Instance.new("UICorner", floatBtn).CornerRadius = UDim.new(0, 14)
local floatStroke = Instance.new("UIStroke", floatBtn)
floatStroke.Color = Color3.fromRGB(160, 140, 255); floatStroke.Thickness = 1.5; floatStroke.Transparency = 0.4
local floatIcon = Instance.new("TextLabel", floatBtn)
floatIcon.Size = UDim2.new(1,0,1,0); floatIcon.BackgroundTransparency = 1
floatIcon.Text = "AF"; floatIcon.TextColor3 = Color3.new(1,1,1)
floatIcon.TextSize = 13; floatIcon.Font = Enum.Font.GothamBold; floatIcon.ZIndex = 101

local mainFrame
local fDrag = {on=false, s=nil, p=nil}
floatBtn.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
        fDrag.on=true; fDrag.s=i.Position; fDrag.p=floatBtn.Position
        i.Changed:Connect(function()
            if i.UserInputState == Enum.UserInputState.End and fDrag.on then
                local d = i.Position - fDrag.s
                if math.abs(d.X)+math.abs(d.Y) < 10 then
                    State.guiVisible = not State.guiVisible
                    mainFrame.Visible = State.guiVisible
                    floatBtn.BackgroundColor3 = State.guiVisible and C.accent1 or C.accent3
                end
                fDrag.on = false
            end
        end)
    end
end)
UIS.InputChanged:Connect(function(i)
    if fDrag.on and (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseMovement) then
        local d = i.Position - fDrag.s
        floatBtn.Position = UDim2.new(fDrag.p.X.Scale, fDrag.p.X.Offset+d.X, fDrag.p.Y.Scale, fDrag.p.Y.Offset+d.Y)
    end
end)

-- Main frame
mainFrame = Instance.new("Frame", sg)
mainFrame.Name = "Main"; mainFrame.Size = UDim2.new(0, 260, 0, 480)
mainFrame.Position = UDim2.new(0.5, -130, 0.5, -240)
mainFrame.BackgroundColor3 = C.bg; mainFrame.BorderSizePixel = 0; mainFrame.ZIndex = 50
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 16)
local mainStroke = Instance.new("UIStroke", mainFrame)
mainStroke.Color = C.border; mainStroke.Thickness = 1; mainStroke.Transparency = 0.3

-- Title bar
local titleBar = Instance.new("Frame", mainFrame)
titleBar.Size = UDim2.new(1,0,0,44); titleBar.BackgroundColor3 = Color3.fromRGB(22, 20, 35)
titleBar.BorderSizePixel = 0; titleBar.ZIndex = 51
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 16)
local titleFill = Instance.new("Frame", titleBar)
titleFill.Size = UDim2.new(1,0,0,16); titleFill.Position = UDim2.new(0,0,1,-16)
titleFill.BackgroundColor3 = Color3.fromRGB(22, 20, 35); titleFill.BorderSizePixel = 0; titleFill.ZIndex = 51
local accentLine = Instance.new("Frame", titleBar)
accentLine.Size = UDim2.new(0.6,0,0,2); accentLine.Position = UDim2.new(0.02,0,1,-1)
accentLine.BackgroundColor3 = C.accent1; accentLine.BorderSizePixel = 0; accentLine.ZIndex = 52
Instance.new("UICorner", accentLine).CornerRadius = UDim.new(1, 0)

local tt = Instance.new("TextLabel", titleBar)
tt.Size = UDim2.new(1,-50,1,0); tt.Position = UDim2.new(0,14,0,0)
tt.BackgroundTransparency = 1; tt.Text = "Auto Farm"; tt.TextColor3 = C.text
tt.TextSize = 16; tt.Font = Enum.Font.GothamBold; tt.TextXAlignment = Enum.TextXAlignment.Left; tt.ZIndex = 52
local verBadge = Instance.new("TextLabel", titleBar)
verBadge.Size = UDim2.new(0,22,0,14); verBadge.Position = UDim2.new(0,102,0.5,-7)
verBadge.BackgroundColor3 = C.accent1; verBadge.BackgroundTransparency = 0.7
verBadge.Text = "v5"; verBadge.TextColor3 = Color3.fromRGB(180,160,255)
verBadge.TextSize = 9; verBadge.Font = Enum.Font.GothamBold; verBadge.BorderSizePixel = 0; verBadge.ZIndex = 53
Instance.new("UICorner", verBadge).CornerRadius = UDim.new(0, 4)

local cb = Instance.new("TextButton", titleBar)
cb.Size = UDim2.new(0,28,0,28); cb.Position = UDim2.new(1,-36,0,8)
cb.BackgroundColor3 = Color3.fromRGB(60,30,40); cb.Text = "x"; cb.TextColor3 = C.accent4
cb.TextSize = 14; cb.Font = Enum.Font.GothamBold; cb.BorderSizePixel = 0; cb.ZIndex = 54
Instance.new("UICorner", cb).CornerRadius = UDim.new(0, 8)
cb.MouseButton1Click:Connect(function()
    State.guiVisible = false; mainFrame.Visible = false; floatBtn.BackgroundColor3 = C.accent3
end)

-- Drag
local db = Instance.new("TextButton", titleBar)
db.Size = UDim2.new(1,-40,1,0); db.BackgroundTransparency = 1; db.Text = ""; db.ZIndex = 53
local mD = {on=false, s=nil, p=nil}
db.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
        mD.on=true; mD.s=i.Position; mD.p=mainFrame.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if mD.on and (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseMovement) then
        local d = i.Position - mD.s
        mainFrame.Position = UDim2.new(mD.p.X.Scale, mD.p.X.Offset+d.X, mD.p.Y.Scale, mD.p.Y.Offset+d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then mD.on = false end
end)

-- Scroll
local sc = Instance.new("ScrollingFrame", mainFrame)
sc.Size = UDim2.new(1,-4,1,-50); sc.Position = UDim2.new(0,2,0,48)
sc.BackgroundTransparency = 1; sc.BorderSizePixel = 0; sc.ScrollBarThickness = 2
sc.ScrollBarImageColor3 = C.accent1
sc.CanvasSize = UDim2.new(0,0,0,0); sc.AutomaticCanvasSize = Enum.AutomaticSize.Y; sc.ZIndex = 51
Instance.new("UIListLayout", sc).Padding = UDim.new(0, 5)
local pd = Instance.new("UIPadding", sc)
pd.PaddingLeft = UDim.new(0,6); pd.PaddingRight = UDim.new(0,6)
pd.PaddingTop = UDim.new(0,4); pd.PaddingBottom = UDim.new(0,8)

-- =============================================
--  WIDGET BUILDERS
-- =============================================
local lo = 0
local function nxt() lo=lo+1; return lo end

local function sec(title, color)
    local f = Instance.new("Frame", sc); f.Size = UDim2.new(1,0,0,22); f.BackgroundTransparency = 1; f.LayoutOrder = nxt(); f.ZIndex = 51
    local dot = Instance.new("Frame", f); dot.Size = UDim2.new(0,6,0,6); dot.Position = UDim2.new(0,2,0.5,-3)
    dot.BackgroundColor3 = color; dot.BorderSizePixel = 0; dot.ZIndex = 52
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1,0)
    local l = Instance.new("TextLabel", f); l.Size = UDim2.new(1,-14,1,0); l.Position = UDim2.new(0,12,0,0)
    l.BackgroundTransparency = 1; l.Text = string.upper(title); l.TextColor3 = color
    l.TextSize = 9; l.Font = Enum.Font.GothamBold; l.TextXAlignment = Enum.TextXAlignment.Left; l.ZIndex = 52
    local ln = Instance.new("Frame", f); ln.Size = UDim2.new(1,-80,0,1); ln.Position = UDim2.new(0,78,0.5,0)
    ln.BackgroundColor3 = C.border; ln.BackgroundTransparency = 0.5; ln.BorderSizePixel = 0; ln.ZIndex = 51
end

local function tog(label, stateKey, color)
    local h = Instance.new("Frame", sc); h.Size = UDim2.new(1,0,0,40); h.BackgroundColor3 = C.card
    h.BorderSizePixel = 0; h.LayoutOrder = nxt(); h.ZIndex = 51
    Instance.new("UICorner", h).CornerRadius = UDim.new(0, 10)
    local hStroke = Instance.new("UIStroke", h); hStroke.Color = C.border; hStroke.Thickness = 1; hStroke.Transparency = 0.6
    local l = Instance.new("TextLabel", h); l.Size = UDim2.new(1,-60,1,0); l.Position = UDim2.new(0,12,0,0)
    l.BackgroundTransparency = 1; l.Text = label; l.TextColor3 = C.textMid
    l.TextSize = 12; l.Font = Enum.Font.Gotham; l.TextXAlignment = Enum.TextXAlignment.Left; l.ZIndex = 52
    local tr = Instance.new("Frame", h); tr.Size = UDim2.new(0,42,0,24); tr.Position = UDim2.new(1,-52,0.5,-12)
    tr.BackgroundColor3 = C.toggleOff; tr.BorderSizePixel = 0; tr.ZIndex = 52
    Instance.new("UICorner", tr).CornerRadius = UDim.new(1, 0)
    local kn = Instance.new("Frame", tr); kn.Size = UDim2.new(0,20,0,20); kn.Position = UDim2.new(0,2,0,2)
    kn.BackgroundColor3 = Color3.fromRGB(120,120,135); kn.BorderSizePixel = 0; kn.ZIndex = 53
    Instance.new("UICorner", kn).CornerRadius = UDim.new(1, 0)
    local b = Instance.new("TextButton", h); b.Size = UDim2.new(1,0,1,0); b.BackgroundTransparency = 1; b.Text = ""; b.ZIndex = 54
    local function upd()
        local on = State[stateKey]
        tr.BackgroundColor3 = on and color or C.toggleOff
        kn.Position = on and UDim2.new(0,20,0,2) or UDim2.new(0,2,0,2)
        kn.BackgroundColor3 = on and Color3.new(1,1,1) or Color3.fromRGB(120,120,135)
        l.TextColor3 = on and C.text or C.textMid
        hStroke.Color = on and color or C.border
        if on then
            h.BackgroundColor3 = Color3.fromRGB(
                math.clamp(C.card.R*255*0.85 + color.R*255*0.15, 0, 255),
                math.clamp(C.card.G*255*0.85 + color.G*255*0.15, 0, 255),
                math.clamp(C.card.B*255*0.85 + color.B*255*0.15, 0, 255))
        else h.BackgroundColor3 = C.card end
    end
    b.MouseButton1Click:Connect(function() State[stateKey] = not State[stateKey]; upd() end)
    upd()
end

local function drop(label, options, default, onSelect, optColors)
    local h = Instance.new("Frame", sc); h.Size = UDim2.new(1,0,0,52); h.BackgroundColor3 = C.card
    h.BorderSizePixel = 0; h.LayoutOrder = nxt(); h.ClipsDescendants = true; h.ZIndex = 51
    Instance.new("UICorner", h).CornerRadius = UDim.new(0, 10)
    local hStroke2 = Instance.new("UIStroke", h); hStroke2.Color = C.border; hStroke2.Transparency = 0.5
    local l = Instance.new("TextLabel", h); l.Size = UDim2.new(1,-14,0,14); l.Position = UDim2.new(0,12,0,5)
    l.BackgroundTransparency = 1; l.Text = label; l.TextColor3 = C.textDim
    l.TextSize = 9; l.Font = Enum.Font.GothamBold; l.TextXAlignment = Enum.TextXAlignment.Left; l.ZIndex = 52
    local sf = Instance.new("Frame", h); sf.Size = UDim2.new(1,-16,0,26); sf.Position = UDim2.new(0,8,0,20)
    sf.BackgroundColor3 = Color3.fromRGB(40,40,56); sf.BorderSizePixel = 0; sf.ZIndex = 52
    Instance.new("UICorner", sf).CornerRadius = UDim.new(0, 7)
    local arrow = Instance.new("TextLabel", sf); arrow.Size = UDim2.new(0,20,1,0); arrow.Position = UDim2.new(1,-22,0,0)
    arrow.BackgroundTransparency = 1; arrow.Text = "v"; arrow.TextColor3 = C.textDim; arrow.TextSize = 10; arrow.Font = Enum.Font.GothamBold; arrow.ZIndex = 53
    local st = Instance.new("TextLabel", sf); st.Size = UDim2.new(1,-28,1,0); st.Position = UDim2.new(0,10,0,0)
    st.BackgroundTransparency = 1; st.Text = default or options[1]; st.TextColor3 = C.text
    st.TextSize = 12; st.Font = Enum.Font.GothamBold; st.TextXAlignment = Enum.TextXAlignment.Left; st.ZIndex = 53
    for i, opt in ipairs(options) do
        local ob = Instance.new("TextButton", h); ob.Size = UDim2.new(1,-16,0,34)
        ob.Position = UDim2.new(0,8,0,52+(i-1)*36); ob.BackgroundColor3 = C.cardHi
        ob.Text = ""; ob.BorderSizePixel = 0; ob.ZIndex = 53
        Instance.new("UICorner", ob).CornerRadius = UDim.new(0, 8)
        local oDot = Instance.new("Frame", ob); oDot.Size = UDim2.new(0,8,0,8)
        oDot.Position = UDim2.new(0,10,0.5,-4); oDot.BorderSizePixel = 0; oDot.ZIndex = 54
        oDot.BackgroundColor3 = (optColors and optColors[i]) or C.accent5
        Instance.new("UICorner", oDot).CornerRadius = UDim.new(1,0)
        local oLbl = Instance.new("TextLabel", ob); oLbl.Size = UDim2.new(1,-30,1,0); oLbl.Position = UDim2.new(0,24,0,0)
        oLbl.BackgroundTransparency = 1; oLbl.Text = opt; oLbl.TextColor3 = C.text
        oLbl.TextSize = 12; oLbl.Font = Enum.Font.Gotham; oLbl.TextXAlignment = Enum.TextXAlignment.Left; oLbl.ZIndex = 54
        ob.MouseButton1Click:Connect(function()
            st.Text = opt; h.Size = UDim2.new(1,0,0,52); arrow.Text = "v"
            if onSelect then onSelect(i, opt) end
        end)
    end
    local ca = Instance.new("TextButton", h); ca.Size = UDim2.new(1,0,0,50)
    ca.BackgroundTransparency = 1; ca.Text = ""; ca.ZIndex = 54
    ca.MouseButton1Click:Connect(function()
        local open = h.Size.Y.Offset > 54
        h.Size = open and UDim2.new(1,0,0,52) or UDim2.new(1,0,0,54+#options*36+4)
        arrow.Text = open and "v" or "^"
    end)
end

local function info(lines)
    local totalH = 8 + #lines * 16
    local h = Instance.new("Frame", sc); h.Size = UDim2.new(1,0,0,totalH)
    h.BackgroundColor3 = Color3.fromRGB(22,22,38); h.BorderSizePixel = 0; h.LayoutOrder = nxt(); h.ZIndex = 51
    Instance.new("UICorner", h).CornerRadius = UDim.new(0, 8)
    local bar = Instance.new("Frame", h); bar.Size = UDim2.new(0,3,0.7,0); bar.Position = UDim2.new(0,0,0.15,0)
    bar.BackgroundColor3 = C.accent1; bar.BorderSizePixel = 0; bar.ZIndex = 52
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1,0)
    for i, ln in ipairs(lines) do
        local lb = Instance.new("TextLabel", h); lb.Size = UDim2.new(1,-18,0,14)
        lb.Position = UDim2.new(0,12,0,3+(i-1)*16); lb.BackgroundTransparency = 1
        lb.Text = ln.t; lb.TextColor3 = ln.c or C.textDim; lb.TextSize = 10
        lb.Font = Enum.Font.Gotham; lb.TextXAlignment = Enum.TextXAlignment.Left; lb.TextWrapped = true; lb.ZIndex = 52
    end
end

-- Status bar
local statusHolder = Instance.new("Frame", sc)
statusHolder.Size = UDim2.new(1,0,0,28); statusHolder.BackgroundColor3 = C.bgCard
statusHolder.BorderSizePixel = 0; statusHolder.LayoutOrder = 999; statusHolder.ZIndex = 51
Instance.new("UICorner", statusHolder).CornerRadius = UDim.new(0, 8)
local statusDot = Instance.new("Frame", statusHolder)
statusDot.Size = UDim2.new(0,6,0,6); statusDot.Position = UDim2.new(0,10,0.5,-3)
statusDot.BackgroundColor3 = C.textDim; statusDot.BorderSizePixel = 0; statusDot.ZIndex = 52
Instance.new("UICorner", statusDot).CornerRadius = UDim.new(1,0)
local statusBar = Instance.new("TextLabel", statusHolder)
statusBar.Size = UDim2.new(1,-24,1,0); statusBar.Position = UDim2.new(0,22,0,0)
statusBar.BackgroundTransparency = 1; statusBar.Text = "Idle"; statusBar.TextColor3 = C.textDim
statusBar.TextSize = 10; statusBar.Font = Enum.Font.Gotham; statusBar.TextXAlignment = Enum.TextXAlignment.Left; statusBar.ZIndex = 52

-- =============================================
--  LAYOUT
-- =============================================

sec("Combat", C.accent5)
tog("Auto equip weapon", "autoEquipWeapon", C.accent5)
tog("Auto use weapon", "autoUseWeapon", C.accent5)
tog("Auto claim achievement", "autoClaimAchievement", C.accent5)

sec("Raid Selection", C.accent4)
local raidNames = {}
for _, r in ipairs(RaidList) do table.insert(raidNames, r.display) end
drop("Select raid", raidNames, RaidList[1].display, function(idx)
    State.selectedRaid = RaidList[idx]
end, {C.accent3, C.accent1})

sec("Farm Controls", C.green)
tog("Auto farm", "autoFarm", C.green)
tog("Friend only", "friendOnly", C.accent3)
tog("Auto create raid", "autoCreateRaid", C.accent2)

sec("Warriors", C.accent2)
tog("Auto equip best", "autoEquipBestPet", C.accent2)

sec("Modifier Priority", C.accent3)
-- Show current priority order
local priLines = {}
for i, mod in ipairs(ModifierPriority) do
    table.insert(priLines, {t = i .. ". " .. mod, c = i == 1 and C.accent3 or C.textMid})
end
table.insert(priLines, {t = "Edit priority at top of script", c = C.textDim})
info(priLines)

sec("Webhook", C.accent5)
info({
    {t = WEBHOOK_URL ~= "" and "Webhook: Connected" or "Webhook: Not set", c = WEBHOOK_URL ~= "" and C.green or C.textDim},
    {t = "Paste URL at top of script", c = C.textDim},
    {t = "Sends on every raid victory", c = C.textDim},
})

-- =============================================
--  START LOOPS
-- =============================================

task.spawn(farmLoop)
task.spawn(raidCycleLoop)
task.spawn(victoryLoop)
task.spawn(utilityLoop)

task.spawn(function()
    while State.running do
        task.wait(1)
        if State.autoFarm then
            local enemies = getAliveEnemies()
            local inRaid = isInRaidArea()
            if inRaid then
                if #enemies > 0 then
                    statusBar.Text = "Killing " .. #enemies .. " | Runs: " .. raidCount
                    statusBar.TextColor3 = C.accent4; statusDot.BackgroundColor3 = C.accent4
                else
                    statusBar.Text = "Boss phase | Runs: " .. raidCount
                    statusBar.TextColor3 = C.accent1; statusDot.BackgroundColor3 = C.accent1
                end
            else
                statusBar.Text = State.autoCreateRaid and ("Lobby — " .. State.selectedRaid.display) or "Lobby"
                statusBar.TextColor3 = C.accent2; statusDot.BackgroundColor3 = C.accent2
            end
        else
            statusBar.Text = "Idle | Runs: " .. raidCount
            statusBar.TextColor3 = C.textDim; statusDot.BackgroundColor3 = C.textDim
        end
    end
end)

player.CharacterAdded:Connect(function()
    task.wait(2)
    if State.autoEquipWeapon then equipWeapon() end
    if State.autoEquipBestPet then equipBestWarriors() end
end)

print("===========================================")
print("  Auto Farm v5 loaded!")
print("  Webhook: " .. (WEBHOOK_URL ~= "" and "ON" or "OFF"))
print("  Modifier priority: " .. ModifierPriority[1] .. " (top)")
print("  Invasion: replay without leaving")
print("===========================================")
