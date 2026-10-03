-- ============================================================
-- Auto Grind + Night Brew + Auto Claim (Fixed)
-- ============================================================
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer

local remote = ReplicatedStorage:WaitForChild("SharedModules")
	:WaitForChild("Packet"):WaitForChild("RemoteEvent")

-- ============================================================
-- CONFIG
-- ============================================================
local CONFIG = {
	MONSTER_FOLDER = "Workspace.MonsterVisuals",
	PUMPKIN_FOLDER = "Workspace.Pumpkins",
	MONSTER_RANGE = 10,
	PUMPKIN_RANGE = 5,
	ATTACK_COOLDOWN = 0.12,
	RETARGET_INTERVAL = 0.1,

	SEEDPACK_PATH = "Workspace.Map.SeedPackSpawnServerLocations",
	SEEDPACK_STOP_DIST = 5,
	SEEDPACK_MOVE_TIMEOUT = 15,
	SEEDPACK_MOVE_REFRESH = 0.15,
	SEEDPACK_IDLE_DELAY = 0.5,
	SEEDPACK_TRIGGER_COOLDOWN = 0.1,
	SEEDPACK_TRIGGERED_TTL = 1.5,

	WALK_SPEED = 30,

	WITCH_GUI_PATHS = {
		"game.Players.LocalPlayer.PlayerGui.WitchCauldron",
		"Workspace.WitchCauldron",
	},
	TIMER_PATH = "Workspace.WitchCauldron.WitchCauldron.WitchCauldron.Water.BrewTimer.TextLabel",

	SEED_SPIRETHORN = "Spirethorn Seed",
	SEED_BRIAR = "Briar Rose Seed",
	BRAIN_MIN = 4,

	BACKPACK_PATH_PARTS = {
		"BackpackGui", "Backpack", "Inventory",
		"ScrollingFrame", "UIGridFrame",
	},

	NIGHT_START = 18,
	NIGHT_END = 6,

	NIGHT_WAIT_BEFORE_CHECK = 3,
	NIGHT_CHECK_DURATION = 3,
	NIGHT_CHECK_INTERVAL = 0.5,

	CLAIM_ENABLED = true,
	CLAIM_CHECK_INTERVAL = 1,
	CLAIM_COOLDOWN = 3,

	DELETE_CHILDREN = {
		"Workspace.Map.Middle",
		"Workspace.Map.Stands",
		"Workspace.NPCS",
		"Workspace.ExplorerStand",
		"Workspace.AuctionStand",
	},
	CLEAR_ALL = {
		"Workspace.Gardens",
	},
	DISABLE_COLLIDER = {
		"Workspace.WitchCauldron",
	},
}

-- ============================================================
-- STATE
-- ============================================================
local isRunning = false
local runToken = 0
local activeHumanoid = nil
local lastClickTime = 0

local firedThisNight = false
local nightHandled = false
local nightPhase = "idle"

-- Brew state (global untuk koordinasi)
local isBrewing = false           -- timer masih aktif
local brewJustClaimed = false     -- flag: baru aja claim, perlu re-evaluate
local lastClaimTime = 0

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

local function waitFolder(pathStr)
	local folder = resolvePath(pathStr)
	local t = tick()
	while not folder and tick() - t < 30 do
		task.wait(0.5)
		folder = resolvePath(pathStr)
	end
	return folder
end

local function isNight()
	local clockTime = Lighting.ClockTime or 0
	local h = math.floor(clockTime) % 24
	return h >= CONFIG.NIGHT_START or h < CONFIG.NIGHT_END
end

local function isPrimary(lbl)
	if lbl.Parent and lbl.Parent:IsA("TextLabel") then return false end
	return true
end

local function parseTimer(text)
	if not text or text == "" then return nil end
	text = text:lower():gsub("%s+", " ")

	local mm, ss = text:match("(%d+)m%s*(%d+)s")
	if mm and ss then return tonumber(mm) * 60 + tonumber(ss) end

	local m = text:match("(%d+)m")
	if m then return tonumber(m) * 60 end

	local s = text:match("(%d+)s")
	if s then return tonumber(s) end

	if text:lower() == "ready" then return 0 end

	local n = text:match("^(%d+)$")
	if n then return tonumber(n) end

	return nil
end

-- Cek apakah brew sedang aktif (timer > 0)
local function checkBrewActive()
	local lbl = resolvePath(CONFIG.TIMER_PATH)
	if not lbl or not lbl:IsA("TextLabel") then return false, nil end
	local text = lbl.Text or ""
	local sec = parseTimer(text)
	-- Brew aktif kalau: parse berhasil DAN sec > 0 (belum Ready)
	if sec and sec > 0 then
		return true, text
	end
	return false, text
end

-- Cek apakah brew Ready (sec == 0 atau text "Ready")
local function checkBrewReady()
	local lbl = resolvePath(CONFIG.TIMER_PATH)
	if not lbl or not lbl:IsA("TextLabel") then return false end
	local text = (lbl.Text or ""):lower()
	if text == "ready" then return true end
	local sec = parseTimer(text)
	return sec ~= nil and sec <= 0
end

-- ============================================================
-- CLEAR WORLD
-- ============================================================
local function clearWorld()
	for _, path in ipairs(CONFIG.DELETE_CHILDREN) do
		local target = resolvePath(path)
		if target then
			for _, child in ipairs(target:GetChildren()) do
				pcall(function() child:Destroy() end)
			end
		end
	end

	for _, path in ipairs(CONFIG.CLEAR_ALL) do
		local target = resolvePath(path)
		if target then
			pcall(function() target:ClearAllChildren() end)
		end
	end

	for _, path in ipairs(CONFIG.DISABLE_COLLIDER) do
		local target = resolvePath(path)
		if target then
			if target:IsA("BasePart") then
				target.CanCollide = false
				target.CanTouch = false
				target.CanQuery = false
			end
			for _, d in ipairs(target:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CanCollide = false
					d.CanTouch = false
					d.CanQuery = false
				end
			end
		end
	end
end

-- ============================================================
-- POSITION HELPERS
-- ============================================================
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

local function moveToSeedPack(hum, root, prompt, stopDistance, isCancelled)
	local t0 = tick()
	while true do
		if isCancelled() then
			pcall(function() hum:MoveTo(root.Position) end)
			return "cancelled"
		end
		if not root or not root.Parent or not hum or not hum.Parent then
			return "cancelled"
		end
		if not prompt or not prompt.Parent then
			return "target_gone"
		end
		local targetPos = getPromptPosition(prompt)
		if not targetPos then
			return "target_gone"
		end
		local myPos = root.Position
		local dist = (targetPos - myPos).Magnitude
		if dist <= stopDistance then
			pcall(function() hum:MoveTo(root.Position) end)
			return "reached"
		end
		if tick() - t0 > CONFIG.SEEDPACK_MOVE_TIMEOUT then
			pcall(function() hum:MoveTo(root.Position) end)
			return "timeout"
		end
		hum:MoveTo(targetPos)
		task.wait(CONFIG.SEEDPACK_MOVE_REFRESH)
	end
end

local function runSeedPackMode(hum, root, myToken, isRunningFn)
	local triggeredSet = {}
	local handled = false

	while isRunningFn() and myToken == runToken do
		if isNight() then return true end

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
				if isNight() then return true end

				if not currentTarget or not currentTarget.Parent then
					local newPrompts = getSeedPackPrompts()
					if #newPrompts == 0 then
						return true
					end
					local newNearest = findNearestSeedPack(newPrompts, root.Position, triggeredSet)
					if not newNearest then break end
					currentTarget = newNearest
				end

				local result = moveToSeedPack(
					hum, root, currentTarget,
					CONFIG.SEEDPACK_STOP_DIST,
					function() return not isRunningFn() or myToken ~= runToken or isNight() end
				)

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
					if currentTarget then
						triggeredSet[currentTarget] = tick()
					end
					break
				end
			end
		end
	end
	return true
end

-- ============================================================
-- FARM TARGET
-- ============================================================
local function findBestFarmTarget(monsterFolder, pumpkinFolder, myPos)
	local best, bestDist, bestKind = nil, math.huge, nil

	if monsterFolder then
		for _, child in ipairs(monsterFolder:GetChildren()) do
			if child:IsA("Model") then
				local rp = findRootPart(child)
				if rp then
					local d = (rp.Position - myPos).Magnitude
					if d < bestDist then
						bestDist = d; best = child; bestKind = "monster"
					end
				end
			end
		end
	end

	if pumpkinFolder then
		for _, child in ipairs(pumpkinFolder:GetChildren()) do
			local rp
			if child:IsA("Model") then
				rp = findRootPart(child)
			elseif child:IsA("BasePart") then
				rp = child
			end
			if rp then
				local d = (rp.Position - myPos).Magnitude
				if d < bestDist then
					bestDist = d; best = child; bestKind = "pumpkin"
				end
			end
		end
	end

	if not best then return nil end
	local rp = findRootPart(best) or (best:IsA("BasePart") and best)
	local realDist = rp and (rp.Position - myPos).Magnitude or 0
	return best, realDist, bestKind
end

-- ============================================================
-- NIGHT BREW HELPERS
-- ============================================================
local function scanSeedInGui()
	local found = {}
	for _, path in ipairs(CONFIG.WITCH_GUI_PATHS) do
		local root = resolvePath(path)
		if root then
			for _, obj in ipairs(root:GetDescendants()) do
				if obj:IsA("TextLabel") and isPrimary(obj) then
					if obj.Text == CONFIG.SEED_SPIRETHORN
					or obj.Text == CONFIG.SEED_BRIAR then
						found[obj.Text] = true
					end
				end
			end
		end
	end
	return found
end

local function getBackpackGrid()
	local node = player:FindFirstChild("PlayerGui")
	if not node then return nil end
	for _, name in ipairs(CONFIG.BACKPACK_PATH_PARTS) do
		node = node:FindFirstChild(name)
		if not node then return nil end
	end
	return node
end

local function parseCount(text)
	if not text or text == "" then return 0 end
	local num = text:match("%d+")
	return tonumber(num) or 0
end

local function scanBackpackMap()
	local map = {}
	local grid = getBackpackGrid()
	if not grid then return map end

	for _, slot in ipairs(grid:GetChildren()) do
		if slot:IsA("Frame") or slot:IsA("TextButton") or slot:IsA("ImageButton") then
			local tn = slot:FindFirstChild("ToolName")
			local tc = slot:FindFirstChild("ToolCount")
			if tn and tn:IsA("TextLabel") and tn.Text ~= "" then
				local count = 1
				if tc and tc:IsA("TextLabel") then
					count = parseCount(tc.Text)
					if count == 0 then count = 1 end
				end
				map[tn.Text] = (map[tn.Text] or 0) + count
			end
		end
	end
	return map
end

local function lookupCount(map, itemName)
	if map[itemName] then return map[itemName] end
	local target = itemName:lower():gsub("^%s+", ""):gsub("%s+$", "")
	for name, count in pairs(map) do
		local norm = name:lower():gsub("^%s+", ""):gsub("%s+$", "")
		if norm == target then return count end
	end
	return 0
end

local function fireSpirethorn()
	local ok = pcall(function()
		local args = { buffer.fromstring("\195\000^\016Common Seed Pack") }
		remote:FireServer(unpack(args))
	end)
	return ok
end

local function fireBriar()
	local ok = pcall(function()
		local args = { buffer.fromstring("\195\0009\nBriar Rose") }
		remote:FireServer(unpack(args))
	end)
	return ok
end

local function fireClaim()
	local ok = pcall(function()
		local args = { buffer.fromstring("\196\000O") }
		remote:FireServer(unpack(args))
	end)
	return ok
end

-- ============================================================
-- NIGHT CHECK (fix: skip kalau brew masih aktif)
-- ============================================================
local function doNightCheck(hum, isRunningFn)
	if hum and hum.Parent then
		pcall(function() hum:Move(Vector3.zero, false) end)
	end

	-- === GUARD: kalau brew masih aktif, skip ===
	local brewing, timerText = checkBrewActive()
	if brewing then
		nightPhase = "brewing"
		firedThisNight = true  -- malam ini di-skip, tidak perlu cek lagi
		return
	end

	-- === FASE 1: WAIT 3 DETIK ===
	nightPhase = "waiting"
	local t0 = tick()
	while tick() - t0 < CONFIG.NIGHT_WAIT_BEFORE_CHECK do
		if not isRunningFn() then
			nightPhase = "idle"
			return
		end
		task.wait(0.2)
	end

	-- === FASE 2: CHECK 3 DETIK ===
	nightPhase = "checking"
	local t1 = tick()
	local fired = false

	while tick() - t1 < CONFIG.NIGHT_CHECK_DURATION do
		if not isRunningFn() then break end

		local seeds = scanSeedInGui()
		local map = scanBackpackMap()
		local brain = lookupCount(map, "Brain")

		local hasSpiret = seeds[CONFIG.SEED_SPIRETHORN]
		local hasBriar = seeds[CONFIG.SEED_BRIAR]
		local brainOk = brain >= CONFIG.BRAIN_MIN

		if hasBriar and brainOk then
			fireBriar()
			fired = true
		elseif hasSpiret and hasBriar and not brainOk then
			fireSpirethorn()
			fired = true
		elseif hasSpiret and not hasBriar then
			fireSpirethorn()
			fired = true
		end

		if fired then break end

		task.wait(CONFIG.NIGHT_CHECK_INTERVAL)
	end

	if fired then
		nightPhase = "fired"
	else
		nightPhase = "no_seed"
	end
	firedThisNight = true
end

-- ============================================================
-- CLAIM WATCHER + BREW STATE TRACKER (background)
-- ============================================================
task.spawn(function()
	local wasReady = false

	while true do
		if isRunning and CONFIG.CLAIM_ENABLED then
			local ready = checkBrewReady()
			local brewing, _ = checkBrewActive()

			-- Update brew state
			isBrewing = brewing

			-- Claim saat Ready
			if ready and (tick() - lastClaimTime) >= CONFIG.CLAIM_COOLDOWN then
				lastClaimTime = tick()
				fireClaim()
				brewJustClaimed = true
				wasReady = true
			else
				-- Reset flag kalau timer sudah tidak Ready
				if wasReady and not ready then
					wasReady = false
					-- Setelah claim + timer hilang:
					-- reset night state biar bisa cek seed lagi kalau masih malam
					if isNight() then
						firedThisNight = false
						nightHandled = false
						nightPhase = "idle"
					end
					brewJustClaimed = false
				end
			end
		else
			isBrewing = false
		end

		task.wait(CONFIG.CLAIM_CHECK_INTERVAL)
	end
end)

-- ============================================================
-- GUI
-- ============================================================
local COLORS = {
	bg        = Color3.fromRGB(24, 24, 28),
	row       = Color3.fromRGB(30, 30, 36),
	text      = Color3.fromRGB(225, 225, 230),
	textDim   = Color3.fromRGB(140, 140, 150),
	accentOn  = Color3.fromRGB(80, 200, 120),
	accentOff = Color3.fromRGB(55, 55, 65),
	stroke    = Color3.fromRGB(60, 60, 72),
	night     = Color3.fromRGB(120, 140, 220),
	day       = Color3.fromRGB(255, 220, 100),
	green     = Color3.fromRGB(80, 200, 120),
	red       = Color3.fromRGB(200, 70, 70),
	yellow    = Color3.fromRGB(230, 190, 120),
	purple    = Color3.fromRGB(160, 120, 220),
}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoGrindBrewCombined"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 200, 0, 200)
main.Position = UDim2.new(0, 20, 0.5, -100)
main.BackgroundColor3 = COLORS.bg
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = screenGui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = COLORS.stroke
mainStroke.Thickness = 1
mainStroke.Transparency = 0.4
mainStroke.Parent = main

local clockPill = Instance.new("TextLabel")
clockPill.Size = UDim2.new(0, 60, 0, 18)
clockPill.Position = UDim2.new(1, -70, 0, 6)
clockPill.BackgroundColor3 = COLORS.day
clockPill.Text = "00:00"
clockPill.TextColor3 = Color3.fromRGB(255, 255, 255)
clockPill.Font = Enum.Font.Code
clockPill.TextSize = 10
clockPill.BorderSizePixel = 0
clockPill.Parent = main
Instance.new("UICorner", clockPill).CornerRadius = UDim.new(0, 4)

local toggleRow = Instance.new("Frame")
toggleRow.Size = UDim2.new(1, -20, 0, 36)
toggleRow.Position = UDim2.new(0, 10, 0, 10)
toggleRow.BackgroundColor3 = COLORS.row
toggleRow.BorderSizePixel = 0
toggleRow.Parent = main
Instance.new("UICorner", toggleRow).CornerRadius = UDim.new(0, 7)

local toggleLbl = Instance.new("TextLabel")
toggleLbl.Size = UDim2.new(1, -70, 1, 0)
toggleLbl.Position = UDim2.new(0, 12, 0, 0)
toggleLbl.BackgroundTransparency = 1
toggleLbl.Text = "Auto Grind + Brew"
toggleLbl.TextColor3 = COLORS.text
toggleLbl.Font = Enum.Font.GothamMedium
toggleLbl.TextSize = 12
toggleLbl.TextXAlignment = Enum.TextXAlignment.Left
toggleLbl.Parent = toggleRow

local track = Instance.new("Frame")
track.Size = UDim2.new(0, 42, 0, 20)
track.Position = UDim2.new(1, -54, 0.5, -10)
track.BackgroundColor3 = COLORS.accentOff
track.BorderSizePixel = 0
track.Parent = toggleRow
Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

local knob = Instance.new("Frame")
knob.Size = UDim2.new(0, 16, 0, 16)
knob.Position = UDim2.new(0, 2, 0.5, -8)
knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
knob.BorderSizePixel = 0
knob.Parent = track
Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

local toggleClick = Instance.new("TextButton")
toggleClick.Size = UDim2.new(1, 0, 1, 0)
toggleClick.BackgroundTransparency = 1
toggleClick.Text = ""
toggleClick.BorderSizePixel = 0
toggleClick.Parent = toggleRow

local function setToggle(on)
	TweenService:Create(track, TweenInfo.new(0.15), {
		BackgroundColor3 = on and COLORS.accentOn or COLORS.accentOff
	}):Play()
	TweenService:Create(knob, TweenInfo.new(0.15), {
		Position = on and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
	}):Play()
	toggleLbl.TextColor3 = on and Color3.fromRGB(150, 240, 170) or COLORS.text
end

local function makeRow(y, label)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -20, 0, 22)
	row.Position = UDim2.new(0, 10, 0, y)
	row.BackgroundColor3 = COLORS.row
	row.BorderSizePixel = 0
	row.Parent = main
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(1, -60, 1, 0)
	nameLbl.Position = UDim2.new(0, 8, 0, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = label
	nameLbl.TextColor3 = COLORS.text
	nameLbl.Font = Enum.Font.GothamMedium
	nameLbl.TextSize = 10
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Parent = row

	local valLbl = Instance.new("TextLabel")
	valLbl.Size = UDim2.new(0, 55, 1, 0)
	valLbl.Position = UDim2.new(1, -60, 0, 0)
	valLbl.BackgroundTransparency = 1
	valLbl.Text = "-"
	valLbl.TextColor3 = COLORS.textDim
	valLbl.Font = Enum.Font.GothamBold
	valLbl.TextSize = 10
	valLbl.TextXAlignment = Enum.TextXAlignment.Right
	valLbl.Parent = row

	return valLbl
end

local rowStatus = makeRow(52, "Status")
local rowSpiret = makeRow(78, "Spirethorn")
local rowBriar  = makeRow(104, "Briar Rose")
local rowBrain  = makeRow(130, "Brain")
local rowTimer  = makeRow(156, "Timer")

-- ============================================================
-- UI UPDATE
-- ============================================================
task.spawn(function()
	while screenGui.Parent do
		local night = isNight()
		local clockTime = Lighting.ClockTime or 0
		local hh = math.floor(clockTime) % 24
		local mm = math.floor((clockTime - math.floor(clockTime)) * 60)
		clockPill.Text = string.format("%02d:%02d", hh, mm)
		clockPill.BackgroundColor3 = night and COLORS.night or COLORS.day

		local seeds = scanSeedInGui()
		local map = scanBackpackMap()
		local brain = lookupCount(map, "Brain")
		local timerLbl = resolvePath(CONFIG.TIMER_PATH)
		local timerText = timerLbl and timerLbl.Text or ""

		-- Status
		if not isRunning then
			rowStatus.Text = "idle"
			rowStatus.TextColor3 = COLORS.textDim
		elseif isBrewing then
			rowStatus.Text = "🍺 brewing..."
			rowStatus.TextColor3 = COLORS.purple
		elseif not night then
			rowStatus.Text = "⚔ farming"
			rowStatus.TextColor3 = COLORS.green
		else
			-- Malam, tidak brewing
			if nightPhase == "waiting" then
				rowStatus.Text = "🌙 wait " .. CONFIG.NIGHT_WAIT_BEFORE_CHECK .. "s"
				rowStatus.TextColor3 = COLORS.night
			elseif nightPhase == "checking" then
				rowStatus.Text = "🔍 checking..."
				rowStatus.TextColor3 = COLORS.yellow
			elseif nightPhase == "fired" then
				rowStatus.Text = "✓ FIRED"
				rowStatus.TextColor3 = COLORS.green
			elseif nightPhase == "no_seed" then
				rowStatus.Text = "💤 no seed"
				rowStatus.TextColor3 = COLORS.textDim
			elseif nightPhase == "brewing" then
				rowStatus.Text = "🍺 brewing"
				rowStatus.TextColor3 = COLORS.purple
			else
				rowStatus.Text = "🌙 night"
				rowStatus.TextColor3 = COLORS.night
			end
		end

		if seeds[CONFIG.SEED_SPIRETHORN] then
			rowSpiret.Text = "✓ ADA"
			rowSpiret.TextColor3 = COLORS.green
		else
			rowSpiret.Text = "✗ -"
			rowSpiret.TextColor3 = COLORS.textDim
		end

		if seeds[CONFIG.SEED_BRIAR] then
			rowBriar.Text = "✓ ADA"
			rowBriar.TextColor3 = COLORS.green
		else
			rowBriar.Text = "✗ -"
			rowBriar.TextColor3 = COLORS.textDim
		end

		if brain >= CONFIG.BRAIN_MIN then
			rowBrain.Text = "x" .. brain .. " ✓"
			rowBrain.TextColor3 = COLORS.green
		else
			rowBrain.Text = "x" .. brain
			rowBrain.TextColor3 = (brain > 0) and COLORS.yellow or COLORS.textDim
		end

		if timerText and timerText ~= "" then
			rowTimer.Text = timerText
			rowTimer.TextColor3 = COLORS.night
		else
			rowTimer.Text = "-"
			rowTimer.TextColor3 = COLORS.textDim
		end

		task.wait(0.5)
	end
end)

-- ============================================================
-- MAIN LOOP
-- ============================================================
local function mainLoop()
	local monsterFolder = waitFolder(CONFIG.MONSTER_FOLDER)
	local pumpkinFolder = waitFolder(CONFIG.PUMPKIN_FOLDER)
	if not monsterFolder or not pumpkinFolder then
		warn("[AutoGrind] Folder monster/pumpkin tidak ditemukan")
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

	local currentTarget = nil
	local currentKind = nil
	local lastSearch = 0

	local function isRunningFn() return isRunning and myToken == runToken end

	while isRunningFn() and hum.Health > 0 do
		if not root.Parent then break end

		local night = isNight()

		-- === CEK BREW STATE ===
		local brewing = checkBrewActive()
		isBrewing = brewing

		-- Kalau brew aktif → skip semua logic night, lanjut farming
		if brewing then
			-- Update phase kalau night
			if night and nightPhase ~= "brewing" then
				nightPhase = "brewing"
				nightHandled = true
				firedThisNight = true
			end
		else
			-- Brew tidak aktif
			-- Malam + belum handle → cek seed
			if night and not nightHandled then
				nightHandled = true
				firedThisNight = false

				hum:Move(Vector3.zero, false)
				doNightCheck(hum, isRunningFn)

				currentTarget = nil
				currentKind = nil
				lastSearch = 0
				task.wait(0.3)
			end

			-- Siang → reset
			if not night and nightHandled then
				nightHandled = false
				firedThisNight = false
				nightPhase = "idle"
			end
		end

		-- Prioritas 1: SeedPack
		local seedPackPrompts = getSeedPackPrompts()
		if #seedPackPrompts > 0 then
			runSeedPackMode(hum, root, myToken, isRunningFn)
			currentTarget = nil
			currentKind = nil
			lastSearch = 0
		else
			-- Prioritas 2: Farm
			hum.WalkSpeed = CONFIG.WALK_SPEED
			local myPos = root.Position
			local now = tick()

			local targetRp
			if currentTarget and currentTarget.Parent then
				if currentTarget:IsA("Model") then
					targetRp = findRootPart(currentTarget)
				elseif currentTarget:IsA("BasePart") then
					targetRp = currentTarget
				end
			end
			if not currentTarget or not currentTarget.Parent or not targetRp then
				currentTarget = nil
				currentKind = nil
			end

			if not currentTarget and (now - lastSearch) >= 0.3 then
				lastSearch = now
				local best, _, kind = findBestFarmTarget(monsterFolder, pumpkinFolder, myPos)
				if best then
					currentTarget = best
					currentKind = kind
				end
			end

			if not currentTarget then
				hum:Move(Vector3.zero, false)
				task.wait(0.15)
			else
				targetRp = (currentTarget:IsA("Model") and findRootPart(currentTarget))
					or (currentTarget:IsA("BasePart") and currentTarget)
					or nil

				if targetRp then
					local targetPos = targetRp.Position
					local flatDir = Vector3.new(targetPos.X - myPos.X, 0, targetPos.Z - myPos.Z)
					local distance = flatDir.Magnitude
					local range = (currentKind == "pumpkin") and CONFIG.PUMPKIN_RANGE or CONFIG.MONSTER_RANGE

					if distance <= range then
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
	end

	if activeHumanoid == hum and hum.Parent then
		pcall(function() hum:Move(Vector3.zero, false) end)
	end
	releaseE()
end

-- ============================================================
-- START / STOP
-- ============================================================
local function stopLoop()
	isRunning = false
	runToken += 1
	setToggle(false)
	releaseE()

	nightPhase = "idle"
	nightHandled = false
	firedThisNight = false
	isBrewing = false
	brewJustClaimed = false

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

local function startLoop()
	clearWorld()
	isRunning = true
	firedThisNight = false
	nightHandled = false
	nightPhase = "idle"
	isBrewing = false
	brewJustClaimed = false
	setToggle(true)
	task.spawn(mainLoop)
end

toggleClick.MouseButton1Click:Connect(function()
	if isRunning then
		stopLoop()
	else
		startLoop()
	end
end)

player.CharacterAdded:Connect(function()
	if isRunning then
		stopLoop()
	end
end)
