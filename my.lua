-- ============================================================
-- Auto Grind + Night Brew + Auto Claim + SeedPack (Night Only)
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

	CLAIM_ENABLED = true,
	CLAIM_CHECK_INTERVAL = 1,
	CLAIM_COOLDOWN = 3,

	NIGHT_WAIT_TIME   = 2,
	NIGHT_CHECK_TIME  = 3,
	POST_CLAIM_WAIT   = 3,

	SEEDPACK_NIGHT_ONLY = true,

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

local phase = "day_farm"
local phaseStart = 0

local isBrewing = false
local claimPending = false
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

local function checkBrewActive()
	local lbl = resolvePath(CONFIG.TIMER_PATH)
	if not lbl or not lbl:IsA("TextLabel") then return false, nil end
	local text = lbl.Text or ""
	local sec = parseTimer(text)
	if sec and sec > 0 then
		return true, text
	end
	return false, text
end

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

-- moveToSeedPack dengan re-evaluate target
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
		if not targetPos then
			return "target_gone", currentPrompt
		end

		local dist = (targetPos - myPos).Magnitude
		if dist <= stopDistance then
			pcall(function() hum:MoveTo(root.Position) end)
			return "reached", currentPrompt
		end
		if tick() - t0 > CONFIG.SEEDPACK_MOVE_TIMEOUT then
			pcall(function() hum:MoveTo(root.Position) end)
			return "timeout", currentPrompt
		end

		if getBetterTarget then
			local better, betterDist = getBetterTarget(currentPrompt, dist)
			if better and better ~= currentPrompt then
				currentPrompt = better
				targetPos = getPromptPosition(currentPrompt)
				if not targetPos then
					return "target_gone", currentPrompt
				end
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
		if not isNight() then return true end

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
				if not isNight() then return true end

				if not currentTarget or not currentTarget.Parent then
					local newPrompts = getSeedPackPrompts()
					if #newPrompts == 0 then
						return true
					end
					local newNearest = findNearestSeedPack(newPrompts, root.Position, triggeredSet)
					if not newNearest then break end
					currentTarget = newNearest
				end

				local function getBetterTarget(currentP, currentDist)
					local p = getSeedPackPrompts()
					local bestP, bestDist = nil, math.huge
					for _, cand in ipairs(p) do
						if cand and cand.Parent
							and cand ~= currentP
							and not triggeredSet[cand]
						then
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
					if bestP and bestDist < (currentDist - 1) then
						return bestP, bestDist
					end
					return nil
				end

				local result, actualTarget = moveToSeedPack(
					hum, root, currentTarget,
					CONFIG.SEEDPACK_STOP_DIST,
					function() return not isRunningFn() or myToken ~= runToken or not isNight() end,
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
	return pcall(function()
		local args = { buffer.fromstring("\195\000^\016Common Seed Pack") }
		remote:FireServer(unpack(args))
	end)
end

local function fireBriar()
	return pcall(function()
		local args = { buffer.fromstring("\195\0009\nBriar Rose") }
		remote:FireServer(unpack(args))
	end)
end

local function fireClaim()
	return pcall(function()
		local args = { buffer.fromstring("\196\000O") }
		remote:FireServer(unpack(args))
	end)
end

-- ============================================================
-- CLAIM WATCHER
-- ============================================================
task.spawn(function()
	while true do
		if isRunning and CONFIG.CLAIM_ENABLED then
			local ready = checkBrewReady()
			local brewing = checkBrewActive()

			isBrewing = brewing

			if ready and (tick() - lastClaimTime) >= CONFIG.CLAIM_COOLDOWN then
				lastClaimTime = tick()
				fireClaim()
				claimPending = true
			end
		else
			isBrewing = false
		end

		task.wait(CONFIG.CLAIM_CHECK_INTERVAL)
	end
end)

-- ============================================================
-- GUI — MINIMALIS MOBILE-FRIENDLY
-- ============================================================
local COLORS = {
	bg        = Color3.fromRGB(22, 22, 28),
	card      = Color3.fromRGB(32, 32, 40),
	cardAlt   = Color3.fromRGB(38, 38, 48),
	text      = Color3.fromRGB(235, 235, 240),
	textDim   = Color3.fromRGB(150, 150, 160),
	accentOn  = Color3.fromRGB(80, 200, 120),
	accentOff = Color3.fromRGB(60, 60, 72),
	stroke    = Color3.fromRGB(70, 70, 85),
	night     = Color3.fromRGB(120, 140, 220),
	day       = Color3.fromRGB(255, 210, 90),
	green     = Color3.fromRGB(80, 200, 120),
	red       = Color3.fromRGB(210, 80, 80),
	yellow    = Color3.fromRGB(230, 190, 120),
	purple    = Color3.fromRGB(170, 130, 230),
}

-- helper shadow
local function addShadow(parent)
	local s = Instance.new("UIStroke")
	s.Color = COLORS.stroke
	s.Thickness = 1
	s.Transparency = 0.5
	s.Parent = parent
	return s
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoGrindBrewMobile"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

-- ===== MAIN FRAME =====
local main = Instance.new("Frame")
main.Size = UDim2.new(0, 210, 0, 240)
main.Position = UDim2.new(0, 12, 0, 60)
main.BackgroundColor3 = COLORS.bg
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = screenGui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)
addShadow(main)

-- ===== HEADER (drag handle + minimize) =====
local header = Instance.new("Frame")
header.Size = UDim2.new(1, -16, 0, 32)
header.Position = UDim2.new(0, 8, 0, 8)
header.BackgroundColor3 = COLORS.card
header.BorderSizePixel = 0
header.Parent = main
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 8)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -80, 1, 0)
titleLbl.Position = UDim2.new(0, 12, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "Auto Grind + Brew"
titleLbl.TextColor3 = COLORS.text
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 12
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Parent = header

local clockPill = Instance.new("TextLabel")
clockPill.Size = UDim2.new(0, 52, 0, 20)
clockPill.Position = UDim2.new(1, -60, 0.5, -10)
clockPill.BackgroundColor3 = COLORS.day
clockPill.Text = "00:00"
clockPill.TextColor3 = Color3.fromRGB(30, 30, 30)
clockPill.Font = Enum.Font.GothamBold
clockPill.TextSize = 11
clockPill.BorderSizePixel = 0
clockPill.Parent = header
Instance.new("UICorner", clockPill).CornerRadius = UDim.new(0, 6)

-- ===== TOGGLE BUTTON (gede, mobile friendly) =====
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -16, 0, 52)
toggleBtn.Position = UDim2.new(0, 8, 0, 46)
toggleBtn.BackgroundColor3 = COLORS.cardAlt
toggleBtn.BorderSizePixel = 0
toggleBtn.Text = ""
toggleBtn.AutoButtonColor = true
toggleBtn.Parent = main
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 10)
local toggleStroke = addShadow(toggleBtn)
toggleStroke.Color = COLORS.accentOff
toggleStroke.Thickness = 2
toggleStroke.Transparency = 0

local toggleIcon = Instance.new("TextLabel")
toggleIcon.Size = UDim2.new(0, 30, 1, 0)
toggleIcon.Position = UDim2.new(0, 8, 0, 0)
toggleIcon.BackgroundTransparency = 1
toggleIcon.Text = "▶"
toggleIcon.TextColor3 = COLORS.textDim
toggleIcon.Font = Enum.Font.GothamBold
toggleIcon.TextSize = 22
toggleIcon.Parent = toggleBtn

local toggleMainLbl = Instance.new("TextLabel")
toggleMainLbl.Size = UDim2.new(1, -110, 0, 18)
toggleMainLbl.Position = UDim2.new(0, 44, 0, 8)
toggleMainLbl.BackgroundTransparency = 1
toggleMainLbl.Text = "TAP TO START"
toggleMainLbl.TextColor3 = COLORS.text
toggleMainLbl.Font = Enum.Font.GothamBold
toggleMainLbl.TextSize = 13
toggleMainLbl.TextXAlignment = Enum.TextXAlignment.Left
toggleMainLbl.Parent = toggleBtn

local toggleSubLbl = Instance.new("TextLabel")
toggleSubLbl.Size = UDim2.new(1, -110, 0, 16)
toggleSubLbl.Position = UDim2.new(0, 44, 0, 26)
toggleSubLbl.BackgroundTransparency = 1
toggleSubLbl.Text = "idle"
toggleSubLbl.TextColor3 = COLORS.textDim
toggleSubLbl.Font = Enum.Font.Gotham
toggleSubLbl.TextSize = 11
toggleSubLbl.TextXAlignment = Enum.TextXAlignment.Left
toggleSubLbl.Parent = toggleBtn

-- ===== INFO LIST =====
local infoFrame = Instance.new("Frame")
infoFrame.Size = UDim2.new(1, -16, 0, 128)
infoFrame.Position = UDim2.new(0, 8, 0, 104)
infoFrame.BackgroundColor3 = COLORS.card
infoFrame.BorderSizePixel = 0
infoFrame.Parent = main
Instance.new("UICorner", infoFrame).CornerRadius = UDim.new(0, 10)

local function makeInfoRow(parent, y, label, initial)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -12, 0, 22)
	row.Position = UDim2.new(0, 6, 0, y)
	row.BackgroundColor3 = COLORS.cardAlt
	row.BorderSizePixel = 0
	row.Parent = parent
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(1, -70, 1, 0)
	nameLbl.Position = UDim2.new(0, 10, 0, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = label
	nameLbl.TextColor3 = COLORS.text
	nameLbl.Font = Enum.Font.GothamMedium
	nameLbl.TextSize = 11
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Parent = row

	local valLbl = Instance.new("TextLabel")
	valLbl.Size = UDim2.new(0, 66, 1, 0)
	valLbl.Position = UDim2.new(1, -72, 0, 0)
	valLbl.BackgroundTransparency = 1
	valLbl.Text = initial
	valLbl.TextColor3 = COLORS.textDim
	valLbl.Font = Enum.Font.GothamBold
	valLbl.TextSize = 11
	valLbl.TextXAlignment = Enum.TextXAlignment.Right
	valLbl.Parent = row

	return valLbl
end

local rowSpiret = makeInfoRow(infoFrame, 6,   "Spirethorn", "✗ -")
local rowBriar  = makeInfoRow(infoFrame, 32,  "Briar Rose", "✗ -")
local rowBrain  = makeInfoRow(infoFrame, 58,  "Brain",      "x0")
local rowTimer  = makeInfoRow(infoFrame, 84,  "Timer",      "-")
-- row 110 free 18px, biar nafas

-- ===== TOGGLE LOGIC =====
local function setToggleUI(on)
	TweenService:Create(toggleStroke, TweenInfo.new(0.18), {
		Color = on and COLORS.accentOn or COLORS.accentOff
	}):Play()
	toggleIcon.Text = on and "■" or "▶"
	toggleIcon.TextColor3 = on and COLORS.green or COLORS.textDim
	toggleMainLbl.Text = on and "RUNNING" or "TAP TO START"
	toggleMainLbl.TextColor3 = on and Color3.fromRGB(150, 240, 170) or COLORS.text
end

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
		clockPill.TextColor3 = night and Color3.fromRGB(255,255,255) or Color3.fromRGB(30,30,30)

		local seeds = scanSeedInGui()
		local map = scanBackpackMap()
		local brain = lookupCount(map, "Brain")
		local timerLbl = resolvePath(CONFIG.TIMER_PATH)
		local timerText = timerLbl and timerLbl.Text or ""

		-- sub label status
		if not isRunning then
			toggleSubLbl.Text = "idle"
			toggleSubLbl.TextColor3 = COLORS.textDim
		elseif phase == "post_claim" then
			toggleSubLbl.Text = "✓ claimed, wait"
			toggleSubLbl.TextColor3 = COLORS.green
		elseif phase == "brewing" or isBrewing then
			toggleSubLbl.Text = "🍺 brewing..."
			toggleSubLbl.TextColor3 = COLORS.purple
		elseif phase == "night_wait" then
			toggleSubLbl.Text = "🌙 wait " .. CONFIG.NIGHT_WAIT_TIME .. "s"
			toggleSubLbl.TextColor3 = COLORS.night
		elseif phase == "night_check" then
			toggleSubLbl.Text = "🔍 checking..."
			toggleSubLbl.TextColor3 = COLORS.yellow
		elseif phase == "night_farm" then
			toggleSubLbl.Text = "🌙📦 seedpack"
			toggleSubLbl.TextColor3 = COLORS.green
		elseif phase == "day_farm" and not night then
			toggleSubLbl.Text = "⚔ farming"
			toggleSubLbl.TextColor3 = COLORS.green
		else
			toggleSubLbl.Text = "🌙 night"
			toggleSubLbl.TextColor3 = COLORS.night
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
local function enterPhase(newPhase)
	phase = newPhase
	phaseStart = tick()
end

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
	local function isRunningFn() return isRunning and myToken == runToken end

	claimPending = false
	enterPhase("day_farm")

	local currentTarget = nil
	local currentKind = nil
	local lastSearch = 0

	local function doFarm()
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
			return
		end

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

	local function doNightFarm()
		if isNight() and CONFIG.SEEDPACK_NIGHT_ONLY then
			local prompts = getSeedPackPrompts()
			if #prompts > 0 then
				runSeedPackMode(hum, root, myToken, isRunningFn)
				currentTarget = nil
				currentKind = nil
				lastSearch = 0
				return
			end
		end
		doFarm()
	end

	local function doNightScanFire()
		local seeds = scanSeedInGui()
		local map = scanBackpackMap()
		local brain = lookupCount(map, "Brain")

		local hasSpiret = seeds[CONFIG.SEED_SPIRETHORN]
		local hasBriar = seeds[CONFIG.SEED_BRIAR]
		local brainOk = brain >= CONFIG.BRAIN_MIN

		if hasBriar and brainOk then
			fireBriar()
			return true
		elseif hasSpiret and hasBriar and not brainOk then
			fireSpirethorn()
			return true
		elseif hasSpiret and not hasBriar then
			fireSpirethorn()
			return true
		end
		return false
	end

	while isRunningFn() and hum.Health > 0 do
		if not root.Parent then break end

		local night = isNight()
		local now = tick()

		if claimPending then
			claimPending = false
			hum:Move(Vector3.zero, false)
			enterPhase("post_claim")
		end

		if phase == "post_claim" then
			hum:Move(Vector3.zero, false)
			if (now - phaseStart) >= CONFIG.POST_CLAIM_WAIT then
				if isNight() then
					enterPhase("night_wait")
				else
					enterPhase("day_farm")
				end
			end

		elseif phase == "night_wait" then
			hum:Move(Vector3.zero, false)
			if not night then
				enterPhase("day_farm")
			elseif (now - phaseStart) >= CONFIG.NIGHT_WAIT_TIME then
				enterPhase("night_check")
			end

		elseif phase == "night_check" then
			if not night then
				enterPhase("day_farm")
			elseif (now - phaseStart) >= CONFIG.NIGHT_CHECK_TIME then
				if isBrewing then
					enterPhase("brewing")
				else
					enterPhase("night_farm")
				end
			else
				hum:Move(Vector3.zero, false)
				local fired = doNightScanFire()
				if fired then
					enterPhase("brewing")
				else
					task.wait(CONFIG.NIGHT_CHECK_INTERVAL)
				end
			end

		elseif phase == "night_farm" then
			if not night then
				enterPhase("day_farm")
			elseif isBrewing then
				enterPhase("brewing")
			else
				doNightFarm()
			end

		elseif phase == "brewing" then
			if not isBrewing then
				enterPhase(isNight() and "night_farm" or "day_farm")
			else
				if isNight() then
					doNightFarm()
				else
					doFarm()
				end
			end

		else -- day_farm
			if night then
				hum:Move(Vector3.zero, false)
				enterPhase("night_wait")
			else
				doFarm()
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
	setToggleUI(false)
	releaseE()

	phase = "day_farm"
	isBrewing = false
	claimPending = false

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
	phase = "day_farm"
	phaseStart = tick()
	isBrewing = false
	claimPending = false
	setToggleUI(true)
	task.spawn(mainLoop)
end

toggleBtn.MouseButton1Click:Connect(function()
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
