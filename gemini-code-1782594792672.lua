-- =============================================
--  AUTO FARM GUI v6 — SUNSHINE + DARK MATTER
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
        bossPos = CFrame.new(4911, 6020, 161),       -- invasion hold/farm position
        startText = "start invasion", -- UI button text
        working = true,
    },
}

local INVASION_HOLD_POS = CFrame.new(4911, 6020, 161)
local INVASION_START_TIMEOUT = 20

local ModifierOptions = {
    "Disabled",
    "Boss Killer",
    "Overflowing Wealth",
    "Espionage",
    "Reinforcement",
    "Momentum",
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
    webhookEnabled       = false,
    webhookUrl           = "",
    webhookRewards       = true,
    autoPickModifiers    = false,
    replayGraceUntil     = 0,
    invasionStartAt      = 0,
    lastModifierVoteAt   = 0,
    modifierPriorities   = {
        "Boss Killer",
        "Overflowing Wealth",
        "Espionage",
        "Reinforcement",
        "Momentum",
    },
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

local function trimText(v)
    v = tostring(v or "")
    return (v:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalizeText(v)
    return string.lower(trimText(v):gsub("%s+", " "))
end

local function getRequestFunction()
    return (syn and syn.request) or http_request or request or (http and http.request)
end

local function collectVisibleText(keywords)
    local lines = {}
    local seen = {}
    for _, obj in ipairs(pgui:GetDescendants()) do
        if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and obj.Visible then
            if obj:IsDescendantOf(pgui:FindFirstChild("AutoFarmGUI")) then continue end
            local text = trimText(obj.Text)
            if text ~= "" then
                local low = string.lower(text)
                local keep = not keywords
                if keywords then
                    for _, kw in ipairs(keywords) do
                        if string.find(low, kw, 1, true) then keep = true; break end
                    end
                end
                if keep and not seen[text] then
                    seen[text] = true
                    table.insert(lines, text)
                end
            end
        end
    end
    return lines
end

local function getVictoryRewards()
    local lines = collectVisibleText({"reward", "gem", "coin", "yen", "xp", "token", "trait", "item", "drop", "essence", "shard", "gold"})
    if #lines == 0 then return "Rewards not detected from UI" end
    return table.concat(lines, "\n")
end

local function sendWebhook(title, description, color)
    if not State.webhookEnabled then return end
    local url = trimText(State.webhookUrl)
    if url == "" then return end
    local req = getRequestFunction()
    if not req then
        warn("[AF] No HTTP request function found for webhook")
        return
    end

    local payload = {
        username = "Auto Farm GUI",
        embeds = {{
            title = title,
            description = description,
            color = color or 5763719,
            fields = {
                { name = "Raid", value = State.selectedRaid and State.selectedRaid.display or "Unknown", inline = true },
                { name = "Player", value = player.Name, inline = true },
            },
            footer = { text = "Auto Farm v6" },
            timestamp = DateTime.now():ToIsoDate(),
        }}
    }

    task.spawn(function()
        local ok, err = pcall(function()
            req({
                Url = url,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode(payload),
            })
        end)
        if not ok then warn("[AF] Webhook failed: " .. tostring(err)) end
    end)
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

local function isSelectedInvasion()
    return State.selectedRaid and State.selectedRaid.raidType == "invasion"
end

local function moveToInvasionHold(reason)
    if not isSelectedInvasion() or not isInRaidArea() then return false end
    local _, hrp = getChar()
    if not hrp then return false end
    hrp.CFrame = INVASION_HOLD_POS
    print("[AF] Holding invasion position" .. (reason and (" (" .. reason .. ")") or ""))
    return true
end

local function invasionStartTimedOut()
    return isSelectedInvasion()
       and (State.invasionStartAt or 0) > 0
       and not isInRaidArea()
       and (tick() - State.invasionStartAt) >= INVASION_START_TIMEOUT
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

local function fireButton(button)
    if not button then return false end
    local fired = false
    pcall(function()
        for _, conn in pairs(getconnections(button.Activated)) do
            conn:Fire()
            fired = true
        end
    end)
    pcall(function()
        for _, conn in pairs(getconnections(button.MouseButton1Click)) do
            conn:Fire()
            fired = true
        end
    end)
    pcall(function()
        button:Activate()
        fired = true
    end)
    return fired
end

local function clickCardFromLabel(label, title, index)
    local current = label
    for d = 1, 12 do
        if not current or current == pgui then break end

        if current:IsA("TextButton") or current:IsA("ImageButton") then
            if fireButton(current) then return true end
        end

        for _, desc in ipairs(current:GetDescendants()) do
            if desc:IsA("TextButton") or desc:IsA("ImageButton") then
                if fireButton(desc) then return true end
            end
        end

        current = current.Parent
    end

    -- Some builds expect the card title, button name, or slot through the remote. Try these after UI clicks.
    if R.voteCard and title then
        local guesses = { title, label.Name, index }
        for _, guess in ipairs(guesses) do
            local ok = pcall(function() R.voteCard:FireServer(guess) end)
            if ok then return true end
            ok = pcall(function() R.voteCard:InvokeServer(guess) end)
            if ok then return true end
        end
    end
    return false
end

local function getVisibleModifierCards()
    local cards = {}
    local seen = {}
    for _, obj in ipairs(pgui:GetDescendants()) do
        if obj:IsA("TextLabel") and obj.Visible then
            if obj:IsDescendantOf(pgui:FindFirstChild("AutoFarmGUI")) then continue end
            local text = trimText(obj.Text)
            if text ~= "" and #text <= 45 and not seen[text] then
                local low = normalizeText(text)
                for _, opt in ipairs(ModifierOptions) do
                    if opt ~= "Disabled" and string.find(low, normalizeText(opt), 1, true) then
                        seen[text] = true
                        table.insert(cards, { label = obj, title = text, key = low, index = #cards + 1 })
                        break
                    end
                end
            end
        end
    end
    return cards
end

local function autoVoteCard()
    if not State.autoPickModifiers then return false end
    if tick() - (State.lastModifierVoteAt or 0) < 2 then return false end
    local cards = getVisibleModifierCards()
    if #cards == 0 then return false end

    for _, wanted in ipairs(State.modifierPriorities or {}) do
        wanted = trimText(wanted)
        if wanted ~= "" and wanted ~= "Disabled" then
            local wantedKey = normalizeText(wanted)
            for _, card in ipairs(cards) do
                if string.find(card.key, wantedKey, 1, true) or string.find(wantedKey, card.key, 1, true) then
                    if clickCardFromLabel(card.label, card.title, card.index) then
                        State.lastModifierVoteAt = tick()
                        print("[AF] Voted priority modifier: " .. card.title)
                        sendWebhook("Modifier picked", "Picked **" .. card.title .. "** from priority list.", 3447003)
                        return true
                    end
                end
            end
        end
    end

    if clickCardFromLabel(cards[1].label, cards[1].title, cards[1].index) then
        State.lastModifierVoteAt = tick()
        print("[AF] Voted fallback modifier: " .. cards[1].title)
        sendWebhook("Modifier picked", "Picked fallback **" .. cards[1].title .. "** because no priority cards were visible.", 15105570)
        return true
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

        local waitingForInvasionReplay = isSelectedInvasion() and tick() < (State.replayGraceUntil or 0) and not invasionStartTimedOut()
        if isSelectedInvasion() and isInRaidArea() then
            State.inRaid = true
            State.invasionStartAt = 0
        end

        if not isInRaidArea() and not State.inRaid and not waitingForInvasionReplay then
            local enemies = getAliveEnemies()
            if #enemies == 0 then
                local raid = State.selectedRaid
                print("[AF] In lobby, starting " .. raid.display .. "...")
                if raid.raidType == "invasion" then
                    State.invasionStartAt = tick()
                end

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
                    State.invasionStartAt = 0
                    if raid.raidType == "invasion" then moveToInvasionHold("started") end
                    print("[AF] Farming started!")
                else
                    if raid.raidType == "invasion" then
                        State.inRaid = false
                        State.replayGraceUntil = 0
                        print("[AF] Invasion did not start in 20 seconds; retrying from bald hero...")
                    else
                        print("[AF] Failed to enter raid, retrying...")
                    end
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
            local rewardText = State.webhookRewards and getVictoryRewards() or "Completed."

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

                State.inRaid = true
                State.invasionStartAt = tick()
                State.replayGraceUntil = tick() + INVASION_START_TIMEOUT
                sendWebhook("Invasion finished", rewardText, 5763719)

                local waitedForReplay = 0
                while State.running and waitedForReplay < INVASION_START_TIMEOUT do
                    task.wait(0.5)
                    waitedForReplay = waitedForReplay + 0.5
                    if isInRaidArea() then
                        State.invasionStartAt = 0
                        moveToInvasionHold("replay")
                        break
                    end
                end

                if not isInRaidArea() then
                    State.inRaid = false
                    State.replayGraceUntil = 0
                    print("[AF] Invasion replay did not start in 20 seconds; will return to bald hero.")
                else
                    print("[AF] Replaying invasion, staying inside raid.")
                end

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

                sendWebhook("Raid finished", rewardText, 5763719)
                task.wait(2)
                State.inRaid = false
                -- raidCycleLoop will handle re-creating
            end
        end

        -- Backup: detect teleport back to lobby
        if State.inRaid and not isInRaidArea() then
            if State.selectedRaid.raidType == "invasion" and tick() < (State.replayGraceUntil or 0) and not invasionStartTimedOut() then
                print("[AF] Invasion replay transition detected; staying in raid mode")
            else
                print("[AF] Returned to lobby (teleport detected)")
                State.inRaid = false
            end
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
            if i.UserInputState == Enum.UserInputState.End and fDrag.on then
                local d = i.Position - fDrag.s
                if math.abs(d.X)+math.abs(d.Y) < 10 then
                    State.guiVisible = not State.guiVisible
                    mainFrame.Visible = State.guiVisible
                    if State.guiVisible then
                        floatBtn.BackgroundColor3 = C.accent1
                        floatIcon.Text = "AF"
                    else
                        floatBtn.BackgroundColor3 = C.accent3
                        floatIcon.Text = "AF"
                    end
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

-- =============================================
--  MAIN FRAME
-- =============================================

mainFrame = Instance.new("Frame", sg)
mainFrame.Name = "Main"; mainFrame.Size = UDim2.new(0, 260, 0, 460)
mainFrame.Position = UDim2.new(0.5, -130, 0.5, -230)
mainFrame.BackgroundColor3 = C.bg; mainFrame.BorderSizePixel = 0
mainFrame.Visible = true; mainFrame.ZIndex = 50
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 16)
local mainStroke = Instance.new("UIStroke", mainFrame)
mainStroke.Color = C.border; mainStroke.Thickness = 1; mainStroke.Transparency = 0.3

-- =============================================
--  TITLE BAR (gradient)
-- =============================================

local titleBar = Instance.new("Frame", mainFrame)
titleBar.Size = UDim2.new(1,0,0,44); titleBar.BackgroundColor3 = Color3.fromRGB(22, 20, 35)
titleBar.BorderSizePixel = 0; titleBar.ZIndex = 51
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 16)
-- Fill bottom corners
local titleFill = Instance.new("Frame", titleBar); titleFill.Size = UDim2.new(1,0,0,16)
titleFill.Position = UDim2.new(0,0,1,-16); titleFill.BackgroundColor3 = Color3.fromRGB(22, 20, 35)
titleFill.BorderSizePixel = 0; titleFill.ZIndex = 51
-- Accent line under title
local accentLine = Instance.new("Frame", titleBar)
accentLine.Size = UDim2.new(0.6, 0, 0, 2); accentLine.Position = UDim2.new(0.02, 0, 1, -1)
accentLine.BackgroundColor3 = C.accent1; accentLine.BorderSizePixel = 0; accentLine.ZIndex = 52
Instance.new("UICorner", accentLine).CornerRadius = UDim.new(1, 0)

-- Title text
local tt = Instance.new("TextLabel", titleBar); tt.Size = UDim2.new(1,-50,1,0); tt.Position = UDim2.new(0,14,0,0)
tt.BackgroundTransparency = 1; tt.Text = "Auto Farm"; tt.TextColor3 = C.text
tt.TextSize = 16; tt.Font = Enum.Font.GothamBold; tt.TextXAlignment = Enum.TextXAlignment.Left; tt.ZIndex = 52
-- Version badge
local verBadge = Instance.new("TextLabel", titleBar)
verBadge.Size = UDim2.new(0, 22, 0, 14); verBadge.Position = UDim2.new(0, 102, 0.5, -7)
verBadge.BackgroundColor3 = C.accent1; verBadge.BackgroundTransparency = 0.7
verBadge.Text = "v6"; verBadge.TextColor3 = Color3.fromRGB(180, 160, 255)
verBadge.TextSize = 9; verBadge.Font = Enum.Font.GothamBold; verBadge.BorderSizePixel = 0; verBadge.ZIndex = 53
Instance.new("UICorner", verBadge).CornerRadius = UDim.new(0, 4)

-- Close button
local cb = Instance.new("TextButton", titleBar); cb.Size = UDim2.new(0,28,0,28); cb.Position = UDim2.new(1,-36,0,8)
cb.BackgroundColor3 = Color3.fromRGB(60, 30, 40); cb.Text = "x"; cb.TextColor3 = C.accent4
cb.TextSize = 14; cb.Font = Enum.Font.GothamBold; cb.BorderSizePixel = 0; cb.ZIndex = 54
Instance.new("UICorner", cb).CornerRadius = UDim.new(0, 8)
cb.MouseButton1Click:Connect(function()
    State.guiVisible = false; mainFrame.Visible = false
    floatBtn.BackgroundColor3 = C.accent3
end)

-- Drag
local db = Instance.new("TextButton", titleBar); db.Size = UDim2.new(1,-40,1,0)
db.BackgroundTransparency = 1; db.Text = ""; db.ZIndex = 53
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

-- =============================================
--  SCROLL AREA
-- =============================================

local sc = Instance.new("ScrollingFrame", mainFrame)
sc.Size = UDim2.new(1,-4,1,-50); sc.Position = UDim2.new(0,2,0,48)
sc.BackgroundTransparency = 1; sc.BorderSizePixel = 0; sc.ScrollBarThickness = 2
sc.ScrollBarImageColor3 = C.accent1
sc.CanvasSize = UDim2.new(0,0,0,0); sc.AutomaticCanvasSize = Enum.AutomaticSize.Y; sc.ZIndex = 51
local scLayout = Instance.new("UIListLayout", sc)
scLayout.Padding = UDim.new(0, 5); scLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
local pd = Instance.new("UIPadding", sc)
pd.PaddingLeft = UDim.new(0,6); pd.PaddingRight = UDim.new(0,6)
pd.PaddingTop = UDim.new(0,4); pd.PaddingBottom = UDim.new(0,8)

-- =============================================
--  WIDGET BUILDERS
-- =============================================
local lo = 0
local function nxt() lo=lo+1; return lo end

-- Section header with icon dot
local function sec(title, color, icon)
    local f = Instance.new("Frame", sc); f.Size = UDim2.new(1,0,0,22); f.BackgroundTransparency = 1
    f.LayoutOrder = nxt(); f.ZIndex = 51
    -- Dot
    local dot = Instance.new("Frame", f); dot.Size = UDim2.new(0,6,0,6)
    dot.Position = UDim2.new(0,2,0.5,-3); dot.BackgroundColor3 = color; dot.BorderSizePixel = 0; dot.ZIndex = 52
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1,0)
    -- Label
    local l = Instance.new("TextLabel", f); l.Size = UDim2.new(1,-14,1,0); l.Position = UDim2.new(0,12,0,0)
    l.BackgroundTransparency = 1; l.Text = string.upper(title)
    l.TextColor3 = color; l.TextSize = 9; l.Font = Enum.Font.GothamBold
    l.TextXAlignment = Enum.TextXAlignment.Left; l.ZIndex = 52
    -- Subtle line
    local ln = Instance.new("Frame", f); ln.Size = UDim2.new(1,-80,0,1); ln.Position = UDim2.new(0,78,0.5,0)
    ln.BackgroundColor3 = C.border; ln.BackgroundTransparency = 0.5; ln.BorderSizePixel = 0; ln.ZIndex = 51
end

-- Toggle with better styling
local function tog(label, stateKey, color)
    local h = Instance.new("Frame", sc); h.Size = UDim2.new(1,0,0,40); h.BackgroundColor3 = C.card
    h.BorderSizePixel = 0; h.LayoutOrder = nxt(); h.ZIndex = 51
    Instance.new("UICorner", h).CornerRadius = UDim.new(0, 10)
    local hStroke = Instance.new("UIStroke", h)
    hStroke.Color = C.border; hStroke.Thickness = 1; hStroke.Transparency = 0.6

    local l = Instance.new("TextLabel", h); l.Size = UDim2.new(1,-60,1,0); l.Position = UDim2.new(0,12,0,0)
    l.BackgroundTransparency = 1; l.Text = label; l.TextColor3 = C.textMid
    l.TextSize = 12; l.Font = Enum.Font.Gotham; l.TextXAlignment = Enum.TextXAlignment.Left; l.ZIndex = 52

    -- Toggle track (wider, more modern)
    local tr = Instance.new("Frame", h); tr.Size = UDim2.new(0,42,0,24); tr.Position = UDim2.new(1,-52,0.5,-12)
    tr.BackgroundColor3 = C.toggleOff; tr.BorderSizePixel = 0; tr.ZIndex = 52
    Instance.new("UICorner", tr).CornerRadius = UDim.new(1, 0)

    -- Knob (circle)
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
        hStroke.Transparency = on and 0.5 or 0.6
        -- Subtle background tint when on
        if on then
            h.BackgroundColor3 = Color3.fromRGB(
                math.clamp(C.card.R*255*0.85 + color.R*255*0.15, 0, 255),
                math.clamp(C.card.G*255*0.85 + color.G*255*0.15, 0, 255),
                math.clamp(C.card.B*255*0.85 + color.B*255*0.15, 0, 255))
        else
            h.BackgroundColor3 = C.card
        end
    end
    b.MouseButton1Click:Connect(function() State[stateKey] = not State[stateKey]; upd() end)
    upd()
end

-- Dropdown with accent color per option
local function drop(label, options, default, onSelect, optColors)
    local h = Instance.new("Frame", sc); h.Size = UDim2.new(1,0,0,52); h.BackgroundColor3 = C.card
    h.BorderSizePixel = 0; h.LayoutOrder = nxt(); h.ClipsDescendants = true; h.ZIndex = 51
    Instance.new("UICorner", h).CornerRadius = UDim.new(0, 10)
    local hStroke2 = Instance.new("UIStroke", h)
    hStroke2.Color = C.border; hStroke2.Transparency = 0.5

    -- Label
    local l = Instance.new("TextLabel", h); l.Size = UDim2.new(1,-14,0,14); l.Position = UDim2.new(0,12,0,5)
    l.BackgroundTransparency = 1; l.Text = label; l.TextColor3 = C.textDim
    l.TextSize = 9; l.Font = Enum.Font.GothamBold; l.TextXAlignment = Enum.TextXAlignment.Left; l.ZIndex = 52

    -- Selected value container
    local sf = Instance.new("Frame", h); sf.Size = UDim2.new(1,-16,0,26); sf.Position = UDim2.new(0,8,0,20)
    sf.BackgroundColor3 = Color3.fromRGB(40, 40, 56); sf.BorderSizePixel = 0; sf.ZIndex = 52
    Instance.new("UICorner", sf).CornerRadius = UDim.new(0, 7)

    -- Arrow indicator
    local arrow = Instance.new("TextLabel", sf); arrow.Size = UDim2.new(0,20,1,0); arrow.Position = UDim2.new(1,-22,0,0)
    arrow.BackgroundTransparency = 1; arrow.Text = "v"; arrow.TextColor3 = C.textDim
    arrow.TextSize = 10; arrow.Font = Enum.Font.GothamBold; arrow.ZIndex = 53

    local st = Instance.new("TextLabel", sf); st.Size = UDim2.new(1,-28,1,0); st.Position = UDim2.new(0,10,0,0)
    st.BackgroundTransparency = 1; st.Text = default or options[1]; st.TextColor3 = C.text
    st.TextSize = 12; st.Font = Enum.Font.GothamBold; st.TextXAlignment = Enum.TextXAlignment.Left; st.ZIndex = 53

    -- Options
    for i, opt in ipairs(options) do
        local ob = Instance.new("TextButton", h); ob.Size = UDim2.new(1,-16,0,34)
        ob.Position = UDim2.new(0,8,0,52+(i-1)*36); ob.BackgroundColor3 = C.cardHi
        ob.Text = ""; ob.BorderSizePixel = 0; ob.ZIndex = 53
        Instance.new("UICorner", ob).CornerRadius = UDim.new(0, 8)

        -- Color dot for each option
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

    -- Toggle open/close
    local ca = Instance.new("TextButton", h); ca.Size = UDim2.new(1,0,0,50)
    ca.BackgroundTransparency = 1; ca.Text = ""; ca.ZIndex = 54
    ca.MouseButton1Click:Connect(function()
        local open = h.Size.Y.Offset > 54
        h.Size = open and UDim2.new(1,0,0,52) or UDim2.new(1,0,0,54+#options*36+4)
        arrow.Text = open and "v" or "^"
    end)
end

local function textBox(label, stateKey, placeholder, color)
    local h = Instance.new("Frame", sc); h.Size = UDim2.new(1,0,0,54); h.BackgroundColor3 = C.card
    h.BorderSizePixel = 0; h.LayoutOrder = nxt(); h.ZIndex = 51
    Instance.new("UICorner", h).CornerRadius = UDim.new(0, 10)
    local hStroke = Instance.new("UIStroke", h)
    hStroke.Color = C.border; hStroke.Thickness = 1; hStroke.Transparency = 0.55

    local l = Instance.new("TextLabel", h); l.Size = UDim2.new(1,-14,0,14); l.Position = UDim2.new(0,12,0,5)
    l.BackgroundTransparency = 1; l.Text = label; l.TextColor3 = color or C.textDim
    l.TextSize = 9; l.Font = Enum.Font.GothamBold; l.TextXAlignment = Enum.TextXAlignment.Left; l.ZIndex = 52

    local b = Instance.new("TextBox", h); b.Size = UDim2.new(1,-16,0,26); b.Position = UDim2.new(0,8,0,22)
    b.BackgroundColor3 = Color3.fromRGB(40, 40, 56); b.BorderSizePixel = 0; b.ZIndex = 52
    b.Text = State[stateKey] or ""; b.PlaceholderText = placeholder or ""; b.ClearTextOnFocus = false
    b.TextColor3 = C.text; b.PlaceholderColor3 = C.textDim; b.TextSize = 11; b.Font = Enum.Font.Gotham
    b.TextXAlignment = Enum.TextXAlignment.Left
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
    b.FocusLost:Connect(function()
        State[stateKey] = trimText(b.Text)
        print("[AF] Updated " .. label)
    end)
end

-- Info panel with left accent bar
local function info(lines)
    local totalH = 8 + #lines * 16
    local h = Instance.new("Frame", sc); h.Size = UDim2.new(1,0,0,totalH)
    h.BackgroundColor3 = Color3.fromRGB(22, 22, 38); h.BorderSizePixel = 0; h.LayoutOrder = nxt(); h.ZIndex = 51
    Instance.new("UICorner", h).CornerRadius = UDim.new(0, 8)
    -- Left accent bar
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

-- Status bar with background
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
statusBar.BackgroundTransparency = 1
statusBar.Text = "Idle"; statusBar.TextColor3 = C.textDim
statusBar.TextSize = 10; statusBar.Font = Enum.Font.Gotham
statusBar.TextXAlignment = Enum.TextXAlignment.Left; statusBar.ZIndex = 52

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
    print("[AF] Selected: " .. State.selectedRaid.display .. " (" .. State.selectedRaid.name .. ")")
end, {C.accent3, C.accent1})  -- amber dot for Sunshine, purple for Dark Matter

info({
    {t = "Sunshine Lake — boss raid, auto leave", c = C.accent3},
    {t = "Dark Matter — invasion, auto replay", c = C.accent1},
    {t = "Remotes loaded: " .. rc, c = C.green},
})

sec("Webhook", C.accent2)
tog("Webhook enabled", "webhookEnabled", C.accent2)
textBox("Webhook URL", "webhookUrl", "https://discord.com/api/webhooks/...", C.accent2)
tog("Include rewards", "webhookRewards", C.accent3)

sec("Modifier Priority", C.accent1)
tog("Auto pick modifiers", "autoPickModifiers", C.accent1)
for i = 1, 5 do
    local default = State.modifierPriorities[i] or ModifierOptions[1]
    drop("Priority " .. i, ModifierOptions, default, function(_, opt)
        State.modifierPriorities[i] = opt
        print("[AF] Modifier priority " .. i .. ": " .. opt)
    end, {C.textDim, C.accent4, C.accent3, C.accent1, C.accent2, C.accent5})
end
info({
    {t = "Turn Auto pick modifiers on for invasion cards", c = C.accent1},
    {t = "Priority 1 is picked first when visible", c = C.accent1},
    {t = "Add missing modifier names to ModifierOptions", c = C.textMid},
})

sec("Farm Controls", C.green)
tog("Auto farm", "autoFarm", C.green)
tog("Friend only", "friendOnly", C.accent3)
tog("Auto create raid", "autoCreateRaid", C.accent2)

sec("Warriors", C.accent2)
tog("Auto equip best", "autoEquipBestPet", C.accent2)

-- =============================================
--  START LOOPS
-- =============================================

task.spawn(farmLoop)
task.spawn(raidCycleLoop)
task.spawn(victoryLoop)
task.spawn(utilityLoop)

-- Status updater
task.spawn(function()
    while State.running do
        task.wait(1)
        if State.autoFarm then
            local enemies = getAliveEnemies()
            local inRaid = isInRaidArea()

            if inRaid then
                if #enemies > 0 then
                    statusBar.Text = "Killing " .. #enemies .. " enemies"
                    statusBar.TextColor3 = C.accent4
                    statusDot.BackgroundColor3 = C.accent4
                else
                    statusBar.Text = "Boss phase — swinging"
                    statusBar.TextColor3 = C.accent1
                    statusDot.BackgroundColor3 = C.accent1
                end
            else
                if State.autoCreateRaid then
                    statusBar.Text = "Lobby — creating " .. State.selectedRaid.display
                    statusBar.TextColor3 = C.accent2
                    statusDot.BackgroundColor3 = C.accent2
                else
                    statusBar.Text = "Lobby — waiting"
                    statusBar.TextColor3 = C.textDim
                    statusDot.BackgroundColor3 = C.textDim
                end
            end
        else
            statusBar.Text = "Idle — turn on Auto Farm"
            statusBar.TextColor3 = C.textDim
            statusDot.BackgroundColor3 = C.textDim
        end
    end
end)

player.CharacterAdded:Connect(function()
    task.wait(2)
    if State.autoEquipWeapon then equipWeapon() end
    if State.autoEquipBestPet then equipBestWarriors() end
end)

print("===========================================")
print("  Auto Farm v6 loaded!")
print("  Sunshine Lake: bossRaid (leaveRaid)")
print("  Dark Matter: invasion (replay)")
print("  Universal enemy detection")
print("  Priority modifier voting toggle for invasions")
print("  Invasion replay hold position: 4911, 6020, 161")
print("  Discord webhook notifications")
print("===========================================")
