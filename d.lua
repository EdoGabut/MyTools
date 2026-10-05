-- ============================================================
-- Auto Farm (Monster > Pumpkin) + SeedPack Top Priority
-- + Clear Map (versi baru: include WildPetSpawns)
-- + Force WalkSpeed 30 (set, bukan tambah)
-- + Button Move to WitchCauldron (MoveTo, bukan teleport)
-- ============================================================
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- ============================================================
-- CONFIG
-- ============================================================
local CONFIG = {
	MONSTER_FOLDER = "Workspace.MonsterVisuals",
	PUMPKIN_FOLDER = "Workspace.Pumpkins",
	SEEDPACK_PATH  = "Workspace.Map.SeedPackSpawnServerLocations",

	MONSTER_RANGE  = 10,
	PUMPKIN_RANGE  = 8,

	WALK_SPEED         = 30,
	ATTACK_COOLDOWN    = 0.12,
	RETARGET_INTERVAL  = 0.1,
	SEARCH_INTERVAL    = 0.3,

	SEEDPACK_STOP_DIST      = 5,
	SEEDPACK_MOVE_TIMEOUT   = 15,
	SEEDPACK_MOVE_REFRESH   = 0.15,
	SEEDPACK_IDLE_DELAY     = 0.5,
	SEEDPACK_TRIGGER_COOLDOWN = 0.15,
	SEEDPACK_TRIGGERED_TTL  = 1.5,
	SEEDPACK_BETTER_MARGIN  = 10,   -- minimal 10 stud lebih dekat biar ganti target

	WITCH_CAULDRON_PATH     = "Workspace.WitchCauldron",
	WITCH_CAULDRON_STOP_DIST = 6,

	CLEAR_MAP = {
		DELETE_CHILDREN = {
			"Workspace.Map.Middle",
			"Workspace.Map.Stands",
			"Workspace.NPCS",
			"Workspace.ExplorerStand",
			"Workspace.AuctionStand",
			"Workspace.Map.WildPetSpawns",
		},
		CLEAR_ALL_CHILDREN = {
			"Workspace.Gardens",
		},
		DISABLE_COLLIDER = {
			"Workspace.WitchCauldron",
		},
	},
}

-- ============================================================
-- STATE
-- ============================================================
local isRunning = false
local runToken = 0
local activeHumanoid = nil
local lastClickTime = 0
local speedLoopToken = 0
local moveToCancelToken = 0

-- ============================================================
-- HELPERS
-- ============================================================
local function resolvePath(pathStr)
	if not pathStr or pathStr == "" then return nil end
	pathStr = pathStr:gsub("^%s+", ""):gsub("%s+$", "")
	local segments = {}
	for seg in pathStr:gmatch("[^%.]+") do
		table.insert(segments, seg)
	end
	if #segments == 0 then return nil end

	local node = game
	if segments[1] == "game" then table.remove(segments, 1) end

	for _, seg in ipairs(segments) do
		if not node then return nil end
		if seg == "LocalPlayer" then
			node = player
		else
			node = node:FindFirstChild(seg)
		end
	end
	return node
end

local function waitFolder(pathStr, timeout)
	timeout = timeout or 30
	local folder = resolvePath(pathStr)
	local t = tick()
	while not folder and tick() - t < timeout do
		task.wait(0.5)
		folder = resolvePath(pathStr)
	end
	return folder
end

local function findRootPart(model)
	if not model or not model.Parent then return nil end
	local rp = model:FindFirstChild("RootPart")
	if rp and rp:IsA("BasePart") then return rp end
	rp = model:FindFirstChild("HumanoidRootPart")
	if rp and rp:IsA("BasePart") then return rp end
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then return model.PrimaryPart end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then return d end
	end
	return nil
end

local function getPromptPosition(prompt)
	if not prompt or not prompt.Parent then return nil end
	local parent = prompt.Parent
	if parent:IsA("BasePart") then return parent.Position end
	if parent:IsA("Attachment") and parent.Parent and parent.Parent:IsA("BasePart") then
		return parent.Parent.Position
	end
	for _, d in ipairs(parent:GetDescendants()) do
		if d:IsA("BasePart") then return d.Position end
	end
	if parent.Parent then
		for _, d in ipairs(parent.Parent:GetDescendants()) do
			if d:IsA("BasePart") then return d.Position end
		end
	end
	return nil
end

-- ============================================================
-- FORCE WALKSPEED 30
-- Set (bukan tambah). Override kalau server set ulang.
-- ============================================================
local function startSpeedKeeper()
	speedLoopToken += 1
	local myToken = speedLoopToken
	task.spawn(function()
		while myToken == speedLoopToken do
			local char = player.Character
			if char then
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum then
					if hum.WalkSpeed ~= CONFIG.WALK_SPEED then
						pcall(function()
							hum.WalkSpeed = CONFIG.WALK_SPEED
						end)
					end
				end
			end
			task.wait(0.1)
		end
	end)
end

local function stopSpeedKeeper()
	speedLoopToken += 1
end

-- ============================================================
-- CLEAR MAP
-- ============================================================
local function cmLog(msg)
	print(string.format("[ClearMap %s] %s", os.date("%H:%M:%S"), msg))
end

local function cm_deleteChildren(path)
	local target = resolvePath(path)
	if not target then cmLog("✗ tidak ditemukan: " .. path); return end
	local count = 0
	for _, child in ipairs(target:GetChildren()) do
		local ok = pcall(function() child:Destroy() end)
		if ok then count += 1 end
	end
	cmLog(string.format("✓ %s → hapus %d anak", path, count))
end

local function cm_clearAllChildren(path)
	local target = resolvePath(path)
	if not target then cmLog("✗ tidak ditemukan: " .. path); return end
	local before = #target:GetChildren()
	local ok = pcall(function() target:ClearAllChildren() end)
	if ok then
		cmLog(string.format("✓ %s → ClearAllChildren (%d → 0)", path, before))
	else
		cmLog("✗ gagal: " .. path)
	end
end

local function cm_disableCollider(path)
	local target = resolvePath(path)
	if not target then cmLog("✗ tidak ditemukan: " .. path); return end
	local count = 0
	local function disablePart(part)
		if not part:IsA("BasePart") then return end
		part.CanCollide = false
		if part.CanTouch ~= nil then part.CanTouch = false end
		if part.CanQuery ~= nil then part.CanQuery = false end
		count += 1
	end
	disablePart(target)
	for _, d in ipairs(target:GetDescendants()) do disablePart(d) end
	cmLog(string.format("✓ %s → disable collider %d part", path, count))
end

local function runClearMap()
	cmLog("=====================================")
	cmLog("START")
	cmLog("=====================================")
	for _, path in ipairs(CONFIG.CLEAR_MAP.DELETE_CHILDREN) do cm_deleteChildren(path) end
	for _, path in ipairs(CONFIG.CLEAR_MAP.CLEAR_ALL_CHILDREN) do cm_clearAllChildren(path) end
	for _, path in ipairs(CONFIG.CLEAR_MAP.DISABLE_COLLIDER) do cm_disableCollider(path) end
	cmLog("=====================================")
	cmLog("SELESAI")
	cmLog("=====================================")
end

-- ============================================================
-- INPUT
-- ============================================================
local function pressE()
	pcall(function()
		VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
	end)
end

local function releaseE()
	pcall(function()
		VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
	end)
end

local function clickLMB()
	local ok = pcall(function()
		VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
		task.wait(0.02)
		VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
	end)
	if ok then return true end

	local ok2 = pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton1(Vector2.new(0, 0))
	end)
	if ok2 then return true end

	local char = player.Character
	if char then
		local tool = char:FindFirstChildOfClass("Tool")
		if tool then
			pcall(function() tool:Activate() end)
			return true
		end
	end
	return false
end

-- ============================================================
-- SEEDPACK
-- ============================================================
local function getSeedPackPrompts()
	local folder = resolvePath(CONFIG.SEEDPACK_PATH)
	if not folder then return {} end
	local list = {}
	for _, obj in ipairs(folder:GetDescendants()) do
		if obj:IsA("ProximityPrompt") then
			table.insert(list, obj)
		end
	end
	return list
end

local function findNearestSeedPack(prompts, myPos, skipSet)
	local nearest, nearestDist = nil, math.huge
	for _, p in ipairs(prompts) do
		if p and p.Parent and not (skipSet and skipSet[p]) then
			local pos = getPromptPosition(p)
			if pos then
				local d = (pos - myPos).Magnitude
				if d < nearestDist then
					nearestDist = d
					nearest = p
				end
			end
		end
	end
	return nearest, nearestDist
end

local function triggerSeedPack(prompt)
	if not prompt or not prompt.Parent then return false end
	pcall(function()
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.Enabled = true
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.ClickablePrompt = false
		prompt.MaxActivationDistance = 30
	end)
	pressE()
	task.wait(0.07)
	releaseE()
	return true
end

local function moveToSeedPack(hum, root, prompt, stopDistance, isCancelled, getBetterTarget)
	local t0 = tick()
	local currentPrompt = prompt

	while true do
		if isCancelled() then
			pcall(function() hum:MoveTo(root.Position) end)
			return "cancelled", currentPrompt
		end
		if not root or not root.Parent or not hum or not hum.Parent then
			return "cancelled", currentPrompt
		end
		if not currentPrompt or not currentPrompt.Parent then
			return "target_gone", currentPrompt
		end

		local myPos = root.Position
		local targetPos = getPromptPosition(currentPrompt)
		if not targetPos then return "target_gone", currentPrompt end

		local dist = (targetPos - myPos).Magnitude
		if dist <= stopDistance then
			pcall(function() hum:MoveTo(root.Position) end)
			return "reached", currentPrompt
		end
		if tick() - t0 > CONFIG.SEEDPACK_MOVE_TIMEOUT then
			pcall(function() hum:MoveTo(root.Position) end)
			return "timeout", currentPrompt
		end

		-- Cek apakah ada seedpack lain yang lebih dekat
		if getBetterTarget then
			local better = getBetterTarget(currentPrompt, dist)
			if better and better ~= currentPrompt then
				currentPrompt = better
				targetPos = getPromptPosition(currentPrompt)
				if not targetPos then return "target_gone", currentPrompt end
			end
		end

		hum:MoveTo(targetPos)
		task.wait(CONFIG.SEEDPACK_MOVE_REFRESH)
	end
end

local function runSeedPackMode(hum, root, myToken, isRunningFn)
	local triggeredSet = {}
	local handled = false

	while isRunningFn() and myToken == runToken do
		local now = tick()
		for prompt, t in pairs(triggeredSet) do
			if (now - t) > CONFIG.SEEDPACK_TRIGGERED_TTL or not prompt.Parent then
				triggeredSet[prompt] = nil
			end
		end

		local prompts = getSeedPackPrompts()
		if #prompts == 0 then
			if handled then
				task.wait(CONFIG.SEEDPACK_IDLE_DELAY)
				if #getSeedPackPrompts() == 0 then
					return true
				end
			else
				return false
			end
		else
			handled = true
		end

		local myPos = root.Position
		local nearest = findNearestSeedPack(prompts, myPos, triggeredSet)

		if not nearest then
			task.wait(CONFIG.SEEDPACK_IDLE_DELAY)
		else
			local currentTarget = nearest

			while isRunningFn() and myToken == runToken do
				if not currentTarget or not currentTarget.Parent then
					local newPrompts = getSeedPackPrompts()
					if #newPrompts == 0 then return true end
					local newNearest = findNearestSeedPack(newPrompts, root.Position, triggeredSet)
					if not newNearest then break end
					currentTarget = newNearest
				end

				-- Logika: kalau ada seedpack lain yang lebih dekat dari sisa jarak
				-- ke target sekarang, ganti. Guard: jangan ganti kalau sudah dekat.
				local function getBetterTarget(currentP, currentDist)
					if currentDist <= CONFIG.SEEDPACK_STOP_DIST + 2 then
						return nil
					end
					local p = getSeedPackPrompts()
					local bestP, bestDist = nil, math.huge
					for _, cand in ipairs(p) do
						if cand and cand.Parent
							and cand ~= currentP
							and not triggeredSet[cand] then
							local pos = getPromptPosition(cand)
							if pos then
								local d = (pos - root.Position).Magnitude
								if d < bestDist then
									bestDist = d
									bestP = cand
								end
							end
						end
					end
					-- Butuh selisih minimal biar tidak goyang
					if bestP and bestDist < (currentDist - CONFIG.SEEDPACK_BETTER_MARGIN) then
						return bestP
					end
					return nil
				end

				local result, actualTarget = moveToSeedPack(
					hum, root, currentTarget,
					CONFIG.SEEDPACK_STOP_DIST,
					function() return not isRunningFn() or myToken ~= runToken end,
					getBetterTarget
				)

				if actualTarget then currentTarget = actualTarget end

				if result == "cancelled" then break
				elseif result == "reached" then
					if currentTarget and currentTarget.Parent then
						triggerSeedPack(currentTarget)
						triggeredSet[currentTarget] = tick()
					end
					task.wait(CONFIG.SEEDPACK_TRIGGER_COOLDOWN)
					break
				elseif result == "target_gone" then
					currentTarget = nil
				elseif result == "timeout" then
					if currentTarget then triggeredSet[currentTarget] = tick() end
					break
				end
			end
		end
	end
	return true
end

-- ============================================================
-- TARGET FINDERS
-- ============================================================
local function findNearestMonster(monsterFolder, myPos)
	local nearest, nearestRp, nearestDist = nil, nil, math.huge
	if not monsterFolder then return nil, nil end
	for _, child in ipairs(monsterFolder:GetChildren()) do
		if child:IsA("Model") then
			local rp = findRootPart(child)
			if rp and rp.Parent then
				local d = (rp.Position - myPos).Magnitude
				if d < nearestDist then
					nearestDist = d
					nearest = child
					nearestRp = rp
				end
			end
		end
	end
	return nearest, nearestRp, nearestDist
end

local function findNearestPumpkin(pumpkinFolder, myPos)
	local nearest, nearestRp, nearestDist = nil, nil, math.huge
	if not pumpkinFolder then return nil, nil end
	for _, child in ipairs(pumpkinFolder:GetChildren()) do
		local rp
		if child:IsA("Model") then
			rp = findRootPart(child)
		elseif child:IsA("BasePart") then
			rp = child
		end
		if rp and rp.Parent then
			local d = (rp.Position - myPos).Magnitude
			if d < nearestDist then
				nearestDist = d
				nearest = child
				nearestRp = rp
			end
		end
	end
	return nearest, nearestRp, nearestDist
end

-- ============================================================
-- FARM MODE
-- Prioritas:
--   1. Seedpack
--   2. Monster
--   3. Pumpkin
-- ============================================================
local function runFarmMode(hum, root, monsterFolder, pumpkinFolder, myToken, isRunningFn)
	local currentTarget, currentRp, currentKind = nil, nil, nil
	local lastSearch = 0

	while isRunningFn() and myToken == runToken do
		local prompts = getSeedPackPrompts()
		if #prompts > 0 then return end

		local myPos = root.Position
		local now = tick()

		local monsterTarget, monsterRp = findNearestMonster(monsterFolder, myPos)

		if monsterTarget then
			if currentKind ~= "monster" or currentTarget ~= monsterTarget then
				currentTarget = monsterTarget
				currentRp = monsterRp
				currentKind = "monster"
			end
		else
			if currentKind == "pumpkin" and currentTarget and (not currentTarget.Parent or not currentRp or not currentRp.Parent) then
				currentTarget, currentRp, currentKind = nil, nil, nil
			end

			if currentKind ~= "pumpkin" or not currentTarget then
				if (now - lastSearch) >= CONFIG.SEARCH_INTERVAL then
					lastSearch = now
					local pTarget, pRp = findNearestPumpkin(pumpkinFolder, myPos)
					if pTarget then
						currentTarget = pTarget
						currentRp = pRp
						currentKind = "pumpkin"
					else
						currentTarget, currentRp, currentKind = nil, nil, nil
					end
				end
			end
		end

		if not currentTarget or not currentRp or not currentRp.Parent then
			hum:Move(Vector3.zero, false)
			task.wait(0.15)
		else
			local targetPos = currentRp.Position
			local flatDir = Vector3.new(targetPos.X - myPos.X, 0, targetPos.Z - myPos.Z)
			local dist = flatDir.Magnitude
			local range = (currentKind == "monster") and CONFIG.MONSTER_RANGE or CONFIG.PUMPKIN_RANGE

			if dist <= range then
				hum:Move(Vector3.zero, false)
				local lookAt = CFrame.lookAt(myPos, Vector3.new(targetPos.X, myPos.Y, targetPos.Z))
				root.CFrame = CFrame.new(myPos) * (lookAt - lookAt.Position)

				local tnow = tick()
				if (tnow - lastClickTime) >= CONFIG.ATTACK_COOLDOWN then
					lastClickTime = tnow
					clickLMB()
				end
				task.wait(0.03)
			else
				local goal = Vector3.new(targetPos.X, myPos.Y, targetPos.Z)
				hum:MoveTo(goal)
				task.wait(CONFIG.RETARGET_INTERVAL)
			end
		end
	end
end

-- ============================================================
-- MOVE TO WITCHCAULDRON (MoveTo, bukan teleport)
-- ============================================================
local function moveToWitchCauldron()
	moveToCancelToken += 1
	local myToken = moveToCancelToken

	-- Matikan auto farm dulu biar tidak rebutan
	if isRunning then
		isRunning = false
		runToken += 1
		releaseE()
	end

	task.spawn(function()
		local cauldron = resolvePath(CONFIG.WITCH_CAULDRON_PATH)
		if not cauldron then
			warn("[MoveTo] WitchCauldron tidak ditemukan")
			return
		end

		local targetPart = findRootPart(cauldron) or (cauldron:IsA("BasePart") and cauldron) or nil
		if not targetPart then
			warn("[MoveTo] WitchCauldron tidak punya BasePart")
			return
		end

		local char = player.Character or player.CharacterAdded:Wait()
		local hum = char:WaitForChild("Humanoid")
		local root = char:WaitForChild("HumanoidRootPart")

		local t0 = tick()
		local timeout = 30

		while myToken == moveToCancelToken do
			if not root.Parent or not hum.Parent then return end
			if hum.Health <= 0 then return end

			local myPos = root.Position
			local tPos = targetPart.Position
			local dist = (Vector3.new(tPos.X, myPos.Y, tPos.Z) - myPos).Magnitude

			if dist <= CONFIG.WITCH_CAULDRON_STOP_DIST then
				pcall(function() hum:MoveTo(root.Position) end)
				print("[MoveTo] Sampai di WitchCauldron")
				return
			end

			if tick() - t0 > timeout then
				pcall(function() hum:MoveTo(root.Position) end)
				warn("[MoveTo] Timeout menuju WitchCauldron")
				return
			end

			hum:MoveTo(Vector3.new(tPos.X, myPos.Y, tPos.Z))
			task.wait(0.15)
		end
	end)
end

-- ============================================================
-- MAIN LOOP
-- ============================================================
local function mainLoop()
	local monsterFolder = waitFolder(CONFIG.MONSTER_FOLDER, 10)
	local pumpkinFolder = waitFolder(CONFIG.PUMPKIN_FOLDER, 10)
	waitFolder(CONFIG.SEEDPACK_PATH, 5)

	if not monsterFolder and not pumpkinFolder then
		warn("[AutoFarm] Monster & Pumpkin folder tidak ditemukan")
		return
	end

	local char = player.Character or player.CharacterAdded:Wait()
	local hum = char:WaitForChild("Humanoid")
	local root = char:WaitForChild("HumanoidRootPart")

	hum.AutoRotate = true
	hum.WalkSpeed = CONFIG.WALK_SPEED
	activeHumanoid = hum

	runToken += 1
	local myToken = runToken
	local function isRunningFn() return isRunning and myToken == runToken end

	while isRunningFn() and hum.Health > 0 do
		if not root.Parent then break end

		local prompts = getSeedPackPrompts()
		if #prompts > 0 then
			runSeedPackMode(hum, root, myToken, isRunningFn)
		else
			runFarmMode(hum, root, monsterFolder, pumpkinFolder, myToken, isRunningFn)
		end
	end

	if activeHumanoid == hum and hum.Parent then
		pcall(function() hum:Move(Vector3.zero, false) end)
	end
	releaseE()
end

-- ============================================================
-- GUI MINIMALIS
-- ============================================================
local COLORS = {
	bg        = Color3.fromRGB(22, 22, 28),
	header    = Color3.fromRGB(16, 16, 20),
	text      = Color3.fromRGB(235, 235, 240),
	green     = Color3.fromRGB(80, 200, 120),
	greenHv   = Color3.fromRGB(100, 220, 140),
	red       = Color3.fromRGB(200, 70, 70),
	blue      = Color3.fromRGB(70, 130, 200),
	blueHv    = Color3.fromRGB(90, 150, 220),
	accentOff = Color3.fromRGB(60, 60, 72),
	stroke    = Color3.fromRGB(60, 60, 72),
}

local function corner(p, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoFarmMini"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

local FRAME_WIDTH = 170
local FRAME_HEIGHT = 118  -- dinaikkan karena ada button tambahan

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, FRAME_WIDTH, 0, FRAME_HEIGHT)
frame.Position = UDim2.new(0, 12, 0, 60)
frame.BackgroundColor3 = COLORS.bg
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = screenGui
corner(frame, 10)

local stroke = Instance.new("UIStroke")
stroke.Color = COLORS.stroke
stroke.Transparency = 0.4
stroke.Parent = frame

local dragging, dragStart, startPos
frame.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = frame.Position
	end
end)
frame.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		frame.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
	end
end)

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 24)
header.BackgroundColor3 = COLORS.header
header.BorderSizePixel = 0
header.Parent = frame
corner(header, 10)

local headerFix = Instance.new("Frame")
headerFix.Size = UDim2.new(1, 0, 0, 8)
headerFix.Position = UDim2.new(0, 0, 1, -8)
headerFix.BackgroundColor3 = COLORS.header
headerFix.BorderSizePixel = 0
headerFix.Parent = header

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -60, 1, 0)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.Text = "Auto Farm"
title.TextColor3 = COLORS.text
title.Font = Enum.Font.GothamBold
title.TextSize = 11
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local function makeHeaderBtn(xOffset, bg, txt)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 18, 0, 18)
	b.Position = UDim2.new(1, xOffset, 0, 3)
	b.BackgroundColor3 = bg
	b.Text = txt
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Parent = header
	corner(b, 5)
	return b
end

local minimizeBtn = makeHeaderBtn(-42, COLORS.accentOff, "—")
local closeBtn    = makeHeaderBtn(-21, COLORS.red, "×")

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -16, 0, 32)
toggleBtn.Position = UDim2.new(0, 8, 0, 32)
toggleBtn.BackgroundColor3 = COLORS.green
toggleBtn.Text = "▶ START"
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 13
toggleBtn.BorderSizePixel = 0
toggleBtn.AutoButtonColor = false
toggleBtn.Parent = frame
corner(toggleBtn, 8)

local witchBtn = Instance.new("TextButton")
witchBtn.Size = UDim2.new(1, -16, 0, 28)
witchBtn.Position = UDim2.new(0, 8, 0, 70)
witchBtn.BackgroundColor3 = COLORS.blue
witchBtn.Text = "⚗ Move to WitchCauldron"
witchBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
witchBtn.Font = Enum.Font.GothamBold
witchBtn.TextSize = 11
witchBtn.BorderSizePixel = 0
witchBtn.AutoButtonColor = false
witchBtn.Parent = frame
corner(witchBtn, 8)

local function setToggleUI(on)
	if on then
		toggleBtn.Text = "■ STOP"
		toggleBtn.BackgroundColor3 = COLORS.red
	else
		toggleBtn.Text = "▶ START"
		toggleBtn.BackgroundColor3 = COLORS.green
	end
end

-- ============================================================
-- START / STOP
-- ============================================================
local function startLoop()
	if isRunning then return end
	isRunning = true
	moveToCancelToken += 1  -- batalkan moveTo kalau ada
	setToggleUI(true)
	startSpeedKeeper()
	task.spawn(mainLoop)
end

local function stopLoop()
	isRunning = false
	runToken += 1
	setToggleUI(false)
	releaseE()

	local hum = activeHumanoid
	activeHumanoid = nil
	if hum and hum.Parent then
		pcall(function()
			hum:Move(Vector3.zero, false)
			local root = hum.RootPart
			if root then hum:MoveTo(root.Position) end
		end)
	end
end

toggleBtn.MouseButton1Click:Connect(function()
	if isRunning then stopLoop() else startLoop() end
end)

toggleBtn.MouseEnter:Connect(function()
	if not isRunning then
		TweenService:Create(toggleBtn, TweenInfo.new(0.1), {
			BackgroundColor3 = COLORS.greenHv
		}):Play()
	end
end)
toggleBtn.MouseLeave:Connect(function()
	if not isRunning then
		TweenService:Create(toggleBtn, TweenInfo.new(0.1), {
			BackgroundColor3 = COLORS.green
		}):Play()
	end
end)

witchBtn.MouseButton1Click:Connect(function()
	moveToWitchCauldron()
end)

witchBtn.MouseEnter:Connect(function()
	TweenService:Create(witchBtn, TweenInfo.new(0.1), {
		BackgroundColor3 = COLORS.blueHv
	}):Play()
end)
witchBtn.MouseLeave:Connect(function()
	TweenService:Create(witchBtn, TweenInfo.new(0.1), {
		BackgroundColor3 = COLORS.blue
	}):Play()
end)

-- ============================================================
-- MINIMIZE / CLOSE
-- ============================================================
local minimized = false
local savedSize = FRAME_HEIGHT

minimizeBtn.MouseButton1Click:Connect(function()
	minimized = not minimized
	if minimized then
		savedSize = frame.Size.Y.Offset
		TweenService:Create(frame, TweenInfo.new(0.2), {
			Size = UDim2.new(0, FRAME_WIDTH, 0, 24)
		}):Play()
		toggleBtn.Visible = false
		witchBtn.Visible = false
	else
		TweenService:Create(frame, TweenInfo.new(0.2), {
			Size = UDim2.new(0, FRAME_WIDTH, 0, savedSize)
		}):Play()
		toggleBtn.Visible = true
		witchBtn.Visible = true
	end
end)

closeBtn.MouseButton1Click:Connect(function()
	stopLoop()
	stopSpeedKeeper()
	screenGui:Destroy()
end)

player.CharacterAdded:Connect(function()
	if isRunning then stopLoop() end
end)

-- ============================================================
-- EXECUTE
-- ============================================================
runClearMap()
setToggleUI(false)
