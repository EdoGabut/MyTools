-- ============================================
-- ALL-IN-ONE: GARDEN SHIELD + AUTO HARVEST
-- ============================================
-- FITUR:
--   [SHIELD]      Weld ke lantai + auto-return ke garden (toggle)
--   [HARVEST]     Auto panen + filter berat/mutasi (toggle)
--   [AUTO SELL]   Jual otomatis (toggle)
-- ============================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui           = game:GetService("CoreGui")
local UserInputService  = game:GetService("UserInputService")

local player = Players.LocalPlayer

local Packet = ReplicatedStorage:WaitForChild("SharedModules")
	:WaitForChild("Packet"):WaitForChild("RemoteEvent")

-- ==================================================================
-- BAGIAN 1: GARDEN SHIELD
-- ==================================================================

local savedCFrame = nil
local activeWeld = nil
local isShieldRunning = false
local isReturning = false

local remoteShieldArgs = {
	buffer.fromstring("\020\000\006Garden~\000\192\151\200C\006\129\018C\b\172\003\195")
}

local function weldToFloor(rootPart)
	if activeWeld then
		activeWeld:Destroy()
		activeWeld = nil
	end
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {player.Character}
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local raycastResult = workspace:Raycast(rootPart.Position, Vector3.new(0, -10, 0), raycastParams)
	if raycastResult and raycastResult.Instance then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = rootPart
		weld.Part1 = raycastResult.Instance
		weld.Parent = rootPart
		activeWeld = weld
	else
		rootPart.Anchored = true
	end
end

local function removeWeld(rootPart)
	if activeWeld then
		activeWeld:Destroy()
		activeWeld = nil
	end
	rootPart.Anchored = false
end

task.spawn(function()
	while task.wait(0.2) do
		if isShieldRunning and savedCFrame then
			local char = player.Character
			if char then
				local rootPart = char:FindFirstChild("HumanoidRootPart")
				local humanoid = char:FindFirstChildOfClass("Humanoid")
				if rootPart and humanoid then
					humanoid.Sit = false
					if not isReturning and not activeWeld then
						weldToFloor(rootPart)
					end
					local distance = (rootPart.Position - savedCFrame.Position).Magnitude
					if distance > 5 and not isReturning then
						isReturning = true
						print("⚠️ Shield: geser " .. math.floor(distance) .. " stud, pulang...")
						removeWeld(rootPart)
						humanoid.Sit = false
						pcall(function()
							Packet:FireServer(unpack(remoteShieldArgs))
						end)
						task.wait(0.2)
						local originalSpeed = humanoid.WalkSpeed
						humanoid.WalkSpeed = 30
						local targetPos = savedCFrame.Position
						while true do
							if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then break end
							local currRoot = player.Character.HumanoidRootPart
							local currHumanoid = player.Character:FindFirstChildOfClass("Humanoid")
							if currHumanoid then
								currHumanoid.Sit = false
								currHumanoid:MoveTo(targetPos)
							end
							if (currRoot.Position - targetPos).Magnitude < 2.5 then break end
							task.wait(0.1)
						end
						rootPart.CFrame = savedCFrame
						humanoid.WalkSpeed = originalSpeed
						weldToFloor(rootPart)
						print("✅ Shield: kembali & weld ulang.")
						isReturning = false
					end
				end
			end
		end
	end
end)

-- ==================================================================
-- BAGIAN 2: AUTO HARVEST + PRIORITY FARM
-- ==================================================================

local ROOT = workspace:WaitForChild("Gardens", 30)

local CONFIG = {
	MAX_WEIGHT          = 80,
	SAVE_WEIGHT         = 150,
	AUTO_ENABLED        = false,
	AUTO_SELL_ENABLED   = false,
	AUTO_SELL_INTERVAL  = 3,
	AUTO_DELAY          = 0.25,
	ONLY_MY_PLOTS       = true,
}

local WEIGHT_K = 9
local CHEAP_MUTATIONS = {
	Electric = true, Gold = true, Frozen = true,
	Rainbow = true, Starstruck = true,
}

local SELL_PAYLOAD = "\015\001\018"
local FAV_PREFIX   = "\179\0004$"

local ALIVE          = true
local isPriorityBusy = false
local MY_PLOT_NAME   = nil

local function isMyPlot(plot)
	local plants = plot:FindFirstChild("Plants")
	if plants then
		for _, plant in ipairs(plants:GetChildren()) do
			local ownerId = plant.Name:match("^(%d+)_")
			if ownerId and tonumber(ownerId) == player.UserId then
				return true
			end
		end
	end
	local signs = plot:FindFirstChild("Signs")
	if signs then
		local garden = signs:FindFirstChild("Garden")
		local core   = garden and garden:FindFirstChild("CorePart")
		local sg     = core and core:FindFirstChild("SurfaceGui")
		local playerLbl = sg and sg:FindFirstChild("Player")
		local textLbl   = playerLbl and playerLbl:FindFirstChild("TextLabel")
		if textLbl then
			local txt = textLbl.Text
			if txt:find(player.DisplayName, 1, true) or txt:find(player.Name, 1, true) then
				return true
			end
		end
	end
	return false
end

local function detectMyPlot()
	for _, plot in ipairs(ROOT:GetChildren()) do
		if isMyPlot(plot) then
			MY_PLOT_NAME = plot.Name
			print("✅ Plot terdeteksi:", MY_PLOT_NAME)
			return MY_PLOT_NAME
		end
	end
	return nil
end

local function getMyPlot()
	if not MY_PLOT_NAME or not ROOT:FindFirstChild(MY_PLOT_NAME) then
		MY_PLOT_NAME = nil
		detectMyPlot()
	end
	return MY_PLOT_NAME and ROOT:FindFirstChild(MY_PLOT_NAME) or nil
end

if ROOT then detectMyPlot() end

local function getPlantUuid(plant) return plant.Name:match("_(.+)$") end
local function getFruitIndex(fruit) return fruit.Name:match("_(%d+)$") end
local function getOwnerId(plant)
	local id = plant.Name:match("^(%d+)_")
	return id and tonumber(id) or nil
end

local function getSizeMulti(fruit)
	local ok, val = pcall(function() return fruit:GetAttribute("SizeMulti") end)
	if ok and val then return val end
	local model = fruit:IsA("Model") and fruit or fruit:FindFirstChildOfClass("Model")
	if model then
		local ok2, val2 = pcall(function() return model:GetAttribute("SizeMulti") end)
		if ok2 and val2 then return val2 end
	end
	return nil
end

local function getFruitWeight(fruit)
	local sm = getSizeMulti(fruit)
	if not sm then return nil end
	return sm * WEIGHT_K
end

local function getMutation(fruit)
	local ok, val = pcall(function() return fruit:GetAttribute("Mutation") end)
	if ok and val and val ~= "" and val ~= "None" then return val end
	local model = fruit:IsA("Model") and fruit or fruit:FindFirstChildOfClass("Model")
	if model then
		local ok2, val2 = pcall(function() return model:GetAttribute("Mutation") end)
		if ok2 and val2 and val2 ~= "" and val2 ~= "None" then return val2 end
	end
	return nil
end

local function isCheapMutation(mut)
	if not mut then return false end
	return CHEAP_MUTATIONS[mut] == true
end

local function harvest(plant, fruit)
	if not ALIVE then return false end
	local uuid  = getPlantUuid(plant)
	local index = getFruitIndex(fruit)
	if not uuid or not index then return false end
	local flag = string.char(#index)
	local payload = ")\001$" .. uuid .. flag .. index
	return pcall(function() Packet:FireServer(buffer.fromstring(payload)) end)
end

local function sellBackpack()
	if not ALIVE then return false end
	return pcall(function() Packet:FireServer(buffer.fromstring(SELL_PAYLOAD)) end)
end

local function favoriteFruit(uuid)
	if not ALIVE or not uuid then return false end
	local payload = FAV_PREFIX .. uuid .. "\001"
	return pcall(function() Packet:FireServer(buffer.fromstring(payload)) end)
end

local function getBackpackUUIDs()
	local uuids = {}
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return uuids end
	for _, item in ipairs(backpack:GetChildren()) do
		local id = item:GetAttribute("Id")
		if id then uuids[id] = item end
	end
	return uuids
end

local function getNewBackpackTools(beforeUUIDs)
	local newTools = {}
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return newTools end
	for _, item in ipairs(backpack:GetChildren()) do
		local id = item:GetAttribute("Id")
		if id and not beforeUUIDs[id] then
			table.insert(newTools, {
				tool     = item,
				uuid     = id,
				name     = item.Name,
				weight   = item:GetAttribute("Weight"),
				mutation = item:GetAttribute("Mutation"),
			})
		end
	end
	return newTools
end

local function isNormalHarvest(e)
	if not e.weight then return false end
	if e.weight <= CONFIG.MAX_WEIGHT then return true end
	if e.mutation and isCheapMutation(e.mutation) then return true end
	return false
end
local function isPriorityTarget(e)
	if not e.weight then return false end
	if e.weight <= CONFIG.MAX_WEIGHT then return false end
	if not e.mutation then return false end
	if isCheapMutation(e.mutation) then return false end
	return true
end
local function isSaveTarget(e)
	if not e.weight then return false end
	if e.weight <= CONFIG.SAVE_WEIGHT then return false end
	if not e.mutation then return false end
	if isCheapMutation(e.mutation) then return false end
	return true
end
local function isSellTarget(e)
	if not e.weight then return false end
	if e.weight <= CONFIG.MAX_WEIGHT then return false end
	if e.weight > CONFIG.SAVE_WEIGHT then return false end
	if not e.mutation then return false end
	if isCheapMutation(e.mutation) then return false end
	return true
end

local function getAllFruits()
	local out = {}
	local plot = getMyPlot()
	if not plot then return out end
	local plants = plot:FindFirstChild("Plants")
	if not plants then return out end
	for _, plant in ipairs(plants:GetChildren()) do
		local skip = false
		if CONFIG.ONLY_MY_PLOTS and getOwnerId(plant) ~= player.UserId then
			skip = true
		end
		if not skip then
			local fruits = plant:FindFirstChild("Fruits")
			if fruits then
				for _, fruit in ipairs(fruits:GetChildren()) do
					table.insert(out, {
						fruit    = fruit,
						plant    = plant,
						weight   = getFruitWeight(fruit),
						mutation = getMutation(fruit),
					})
				end
			end
		end
	end
	return out
end

local function doPriorityFarm()
	if isPriorityBusy then return end
	isPriorityBusy = true
	print("")
	print("🌟 ═══ PRIORITY FARM ═══")
	local prevSell = CONFIG.AUTO_SELL_ENABLED
	CONFIG.AUTO_SELL_ENABLED = false
	task.wait(0.3)
	local totalSaved, totalSold, round = 0, 0, 0
	while ALIVE and round < 10 do
		round = round + 1
		local entries = getAllFruits()
		local saveTargets, sellTargets = {}, {}
		for _, e in ipairs(entries) do
			if isPriorityTarget(e) then
				if isSaveTarget(e) then table.insert(saveTargets, e)
				elseif isSellTarget(e) then table.insert(sellTargets, e) end
			end
		end
		if #saveTargets == 0 and #sellTargets == 0 then
			print(string.format("🌟 Round %d: no target", round)); break
		end
		print(string.format("🌟 Round %d: %d save, %d jual", round, #saveTargets, #sellTargets))
		local beforeUUIDs = getBackpackUUIDs()
		local allTargets = {}
		for _, t in ipairs(saveTargets) do table.insert(allTargets, t) end
		for _, t in ipairs(sellTargets) do table.insert(allTargets, t) end
		for _, t in ipairs(allTargets) do
			if not ALIVE then break end
			harvest(t.plant, t.fruit)
			task.wait(0.15)
		end
		task.wait(0.8)
		local newTools = getNewBackpackTools(beforeUUIDs)
		for _, t in ipairs(newTools) do
			if not ALIVE then break end
			local w, mut = t.weight or 0, t.mutation
			local isCheap = isCheapMutation(mut)
			if w > CONFIG.SAVE_WEIGHT and not isCheap then
				if favoriteFruit(t.uuid) then
					totalSaved = totalSaved + 1
					print(string.format("🌟 💾 SAVE: %s [%s] %.2fkg", t.name, mut or "-", w))
				end
			else
				totalSold = totalSold + 1
				print(string.format("🌟 💰 JUAL: %s [%s] %.2fkg", t.name, mut or "-", w))
			end
			task.wait(0.15)
		end
		if #newTools > 0 then
			task.wait(0.5); sellBackpack()
		end
		task.wait(0.3)
	end
	print(string.format("🌟 Total: %d saved, %d sold", totalSaved, totalSold))
	if prevSell then CONFIG.AUTO_SELL_ENABLED = true end
	print("🌟 ═══════════════════════")
	print("")
	isPriorityBusy = false
end

-- Harvest loop
task.spawn(function()
	while ALIVE do
		task.wait(CONFIG.AUTO_DELAY)
		if not ALIVE then break end
		if isPriorityBusy then continue end
		if CONFIG.AUTO_ENABLED and getMyPlot() then
			local entries = getAllFruits()
			local hasPriority = false
			for _, e in ipairs(entries) do
				if isPriorityTarget(e) then hasPriority = true; break end
			end
			if hasPriority then
				task.spawn(doPriorityFarm)
			else
				for _, e in ipairs(entries) do
					if not ALIVE or isPriorityBusy then break end
					if not CONFIG.AUTO_ENABLED then break end
					if isNormalHarvest(e) then
						harvest(e.plant, e.fruit)
						task.wait(0.08)
					end
				end
			end
		end
	end
end)

-- Sell loop
task.spawn(function()
	while ALIVE do
		task.wait(CONFIG.AUTO_SELL_INTERVAL)
		if not ALIVE then break end
		if isPriorityBusy then continue end
		if CONFIG.AUTO_SELL_ENABLED then sellBackpack() end
	end
end)

-- ==================================================================
-- GUI UNIFIED
-- ==================================================================

local old = CoreGui:FindFirstChild("AllInOneGui")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "AllInOneGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = CoreGui

local FULL_H = 178
local MINI_H = 28

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 190, 0, FULL_H)
main.Position = UDim2.new(0, 20, 0, 60)
main.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 28)
header.BackgroundColor3 = Color3.fromRGB(38, 38, 50)
header.BorderSizePixel = 0
header.Parent = main
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)

local headerFix = Instance.new("Frame")
headerFix.Size = UDim2.new(1, 0, 0, 10)
headerFix.Position = UDim2.new(0, 0, 1, -10)
headerFix.BackgroundColor3 = Color3.fromRGB(38, 38, 50)
headerFix.BorderSizePixel = 0
headerFix.Parent = header

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 20, 0, 20)
minBtn.Position = UDim2.new(0, 4, 0, 4)
minBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
minBtn.Text = "—"
minBtn.TextColor3 = Color3.fromRGB(230, 230, 240)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 12
minBtn.Parent = header
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 5)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -50, 1, 0)
titleLbl.Position = UDim2.new(0, 26, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "🌾 All-in-One"
titleLbl.TextColor3 = Color3.fromRGB(230, 230, 240)
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 11
titleLbl.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 20, 0, 20)
closeBtn.Position = UDim2.new(1, -24, 0, 4)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.Parent = header

local body = Instance.new("Frame")
body.Size = UDim2.new(1, 0, 1, -28)
body.Position = UDim2.new(0, 0, 0, 28)
body.BackgroundTransparency = 1
body.Parent = main

-- Section label helper
local function makeSectionLbl(text, yPos)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -20, 0, 14)
	l.Position = UDim2.new(0, 10, 0, yPos)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = Color3.fromRGB(130, 130, 150)
	l.Font = Enum.Font.GothamBold
	l.TextSize = 9
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = body
	return l
end

-- Slider toggle helper
local function makeSliderToggle(parent, labelText, yPos, getState, setState)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0, 110, 0, 18)
	lbl.Position = UDim2.new(0, 10, 0, yPos)
	lbl.BackgroundTransparency = 1
	lbl.Text = labelText
	lbl.TextColor3 = Color3.fromRGB(200, 200, 220)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 10
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = parent

	local TRACK_W, KNOB_W = 40, 16
	local RANGE = TRACK_W - KNOB_W

	local track = Instance.new("Frame")
	track.Size = UDim2.new(0, TRACK_W, 0, 16)
	track.Position = UDim2.new(1, -TRACK_W - 10, 0, yPos + 1)
	track.BackgroundColor3 = Color3.fromRGB(50, 50, 62)
	track.BorderSizePixel = 0
	track.Parent = parent
	Instance.new("UICorner", track).CornerRadius = UDim.new(0, 8)

	local knob = Instance.new("Frame")
	knob.Size = UDim2.new(0, KNOB_W, 0, 16)
	knob.BackgroundColor3 = Color3.fromRGB(230, 230, 240)
	knob.BorderSizePixel = 0
	knob.Parent = track
	Instance.new("UICorner", knob).CornerRadius = UDim.new(0, 8)

	local function updateVisual()
		local on = getState()
		if on then
			knob.Position = UDim2.new(0, RANGE, 0, 0)
			track.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
		else
			knob.Position = UDim2.new(0, 0, 0, 0)
			track.BackgroundColor3 = Color3.fromRGB(50, 50, 62)
		end
	end

	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			setState(not getState())
			updateVisual()
		end
	end)

	local dragging = false
	knob.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local trackX = track.AbsolutePosition.X
			local relX = input.Position.X - trackX
			local pct = math.clamp((relX - KNOB_W/2) / RANGE, 0, 1)
			local newOn = pct > 0.5
			if newOn ~= getState() then
				setState(newOn)
				updateVisual()
			end
		end
	end)

	updateVisual()
end

-- Section 1: SHIELD
makeSectionLbl("🛡️ GARDEN SHIELD", 4)
makeSliderToggle(body, "Aktifkan Shield", 20,
	function() return isShieldRunning end,
	function(v)
		isShieldRunning = v
		local char = player.Character
		local rootPart = char and char:FindFirstChild("HumanoidRootPart")
		if v then
			if rootPart then
				savedCFrame = rootPart.CFrame
				weldToFloor(rootPart)
				print("🛡️ Shield ON")
			end
		else
			if rootPart then removeWeld(rootPart) end
			savedCFrame = nil
			isReturning = false
			print("🛑 Shield OFF")
		end
	end
)

-- Section 2: HARVEST
makeSectionLbl("🌾 AUTO HARVEST", 52)
makeSliderToggle(body, "🌾 Auto Panen", 68,
	function() return CONFIG.AUTO_ENABLED end,
	function(v)
		CONFIG.AUTO_ENABLED = v
		print("🌾 Auto Panen " .. (v and "ON" or "OFF"))
		if v and not MY_PLOT_NAME then detectMyPlot() end
	end
)
makeSliderToggle(body, "💰 Auto Sell", 90,
	function() return CONFIG.AUTO_SELL_ENABLED end,
	function(v)
		CONFIG.AUTO_SELL_ENABLED = v
		print("💰 Auto Sell " .. (v and "ON" or "OFF"))
	end
)

-- Info box
local infoLbl = Instance.new("TextLabel")
infoLbl.Size = UDim2.new(1, -20, 0, 26)
infoLbl.Position = UDim2.new(0, 10, 0, 120)
infoLbl.BackgroundTransparency = 1
infoLbl.Text = "🛡️ Shield & 🌾 Harvest manual\n💰 Auto Sell manual"
infoLbl.TextColor3 = Color3.fromRGB(130, 150, 200)
infoLbl.Font = Enum.Font.Gotham
infoLbl.TextSize = 9
infoLbl.TextXAlignment = Enum.TextXAlignment.Left
infoLbl.TextYAlignment = Enum.TextYAlignment.Top
infoLbl.Parent = body

-- Minimize logic
local isMinimized = false
minBtn.MouseButton1Click:Connect(function()
	isMinimized = not isMinimized
	body.Visible = not isMinimized
	main.Size = isMinimized and UDim2.new(0, 190, 0, MINI_H) or UDim2.new(0, 190, 0, FULL_H)
	minBtn.Text = isMinimized and "+" or "—"
end)

closeBtn.MouseButton1Click:Connect(function()
	ALIVE = false
	CONFIG.AUTO_ENABLED = false
	CONFIG.AUTO_SELL_ENABLED = false
	isShieldRunning = false
	if gui then gui:Destroy() end
	print("🛑 Semua fitur dimatikan. Script stopped.")
end)

Players.PlayerRemoving:Connect(function(p)
	if p == player then ALIVE = false end
end)
