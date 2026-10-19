-- ============================================================
-- GABUNGAN FINAL:
--   [1] ALL-IN-ONE: GARDEN SHIELD + AUTO HARVEST + AUTO SELL
--       (Auto Buy DIHAPUS TOTAL — ditangani script kedua)
--   [2] AUTO BUY ALL: Seed + Gear + Crate (toggle sendiri, 0.5s)
-- ============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui           = game:GetService("CoreGui")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")

local player = Players.LocalPlayer

local Packet = ReplicatedStorage:WaitForChild("SharedModules")
	:WaitForChild("Packet"):WaitForChild("RemoteEvent")

-- ==================================================================
-- BAGIAN 1: ALL-IN-ONE (SHIELD + HARVEST + SELL) — TANPA AUTO BUY
-- ==================================================================

-- ==================================================================
-- BAGIAN 2: GARDEN SHIELD
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
-- BAGIAN 3: AUTO HARVEST + PRIORITY FARM
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

task.spawn(function()
	while ALIVE do
		task.wait(CONFIG.AUTO_SELL_INTERVAL)
		if not ALIVE then break end
		if isPriorityBusy then continue end
		if CONFIG.AUTO_SELL_ENABLED then sellBackpack() end
	end
end)

-- ==================================================================
-- BAGIAN 4: GUI UNIFIED (ALL-IN-ONE)
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

local infoLbl = Instance.new("TextLabel")
infoLbl.Size = UDim2.new(1, -20, 0, 26)
infoLbl.Position = UDim2.new(0, 10, 0, 120)
infoLbl.BackgroundTransparency = 1
infoLbl.Text = "⚙️ Auto Buy: pakai GUI 'Auto Buy All'\n🛡️ Shield & 🌾 Harvest manual"
infoLbl.TextColor3 = Color3.fromRGB(130, 150, 200)
infoLbl.Font = Enum.Font.Gotham
infoLbl.TextSize = 9
infoLbl.TextXAlignment = Enum.TextXAlignment.Left
infoLbl.TextYAlignment = Enum.TextYAlignment.Top
infoLbl.Parent = body

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
	print("🛑 All-in-One dimatikan.")
end)

Players.PlayerRemoving:Connect(function(p)
	if p == player then ALIVE = false end
end)

print("=====================================")
print("✅ ALL-IN-ONE LOADED (tanpa Auto Buy)")
print("   Shield      : OFF (toggle)")
print("   Auto Panen  : OFF (toggle)")
print("   Auto Sell   : OFF (toggle)")
print("=====================================")

-- ============================================================
-- BAGIAN 5: AUTO BUY ALL (dari script kedua)
-- ============================================================

local BUY_INTERVAL = 0.5
local SCAN_INTERVAL = 1

local SHOPS = {
	{
		name = "Seed",
		base = "game.Players.LocalPlayer.PlayerGui.SeedShop.Frame.NormalShop",
		opcode1 = 0xB8,
		opcode2 = 0x00,
		color = Color3.fromRGB(80, 200, 120),
		icon = "🌱",
	},
	{
		name = "Gear",
		base = "game.Players.LocalPlayer.PlayerGui.GearShop.Frame.ScrollingFrame",
		opcode1 = 0xCE,
		opcode2 = 0x00,
		color = Color3.fromRGB(96, 140, 230),
		icon = "💧",
	},
	{
		name = "Crate",
		base = "game.Players.LocalPlayer.PlayerGui.CrateShop.Frame.ScrollingFrame",
		opcode1 = 0xCC,
		opcode2 = 0x00,
		color = Color3.fromRGB(220, 160, 80),
		icon = "📦",
	},
}

local function resolveShopPath(pathStr)
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

local function parseStockLabel(label)
	if not label or not label.Text then return nil end
	return tonumber(label.Text:match("[xX](%d+)")) or tonumber(label.Text:match("(%d+)"))
end

local function buildBuyPayload(op1, op2, itemName)
	local len = #itemName
	if len > 255 then return nil end
	return buffer.fromstring(
		string.char(op1) .. string.char(op2) ..
		string.char(len) .. itemName
	)
end

local function scanShop(shop)
	local items = {}
	local base = resolveShopPath(shop.base)
	if not base then return items end

	for _, child in ipairs(base:GetChildren()) do
		if child.Name ~= "ItemTemplate" and child.Name ~= "Main_Frame" then
			local mainFrame = child:FindFirstChild("Main_Frame")
			if mainFrame then
				local stockLabel = mainFrame:FindFirstChild("Stock_Text")
				if stockLabel and stockLabel:IsA("TextLabel") then
					local stock = parseStockLabel(stockLabel)
					if stock and stock > 0 then
						table.insert(items, {
							name = child.Name,
							stock = stock,
						})
					end
				end
			end
		end
	end
	table.sort(items, function(a, b) return a.name < b.name end)
	return items
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoBuyAll"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local COLORS = {
	bg        = Color3.fromRGB(22, 22, 28),
	header    = Color3.fromRGB(16, 16, 20),
	card      = Color3.fromRGB(28, 28, 34),
	text      = Color3.fromRGB(235, 235, 240),
	textDim   = Color3.fromRGB(140, 145, 160),
	green     = Color3.fromRGB(80, 190, 120),
	greenHv   = Color3.fromRGB(100, 220, 140),
	red       = Color3.fromRGB(220, 80, 90),
	stroke    = Color3.fromRGB(48, 48, 60),
	disabled  = Color3.fromRGB(70, 70, 85),
}

local function corner(p, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p
end

local FRAME_WIDTH = 280
local FRAME_HEIGHT = 260
local FRAME_HEIGHT_MIN = 42

local mainAB = Instance.new("Frame")
mainAB.Size = UDim2.new(0, FRAME_WIDTH, 0, FRAME_HEIGHT)
mainAB.Position = UDim2.new(0, 220, 0, 15)
mainAB.BackgroundColor3 = COLORS.bg
mainAB.BorderSizePixel = 0
mainAB.Active = true
mainAB.Parent = screenGui
corner(mainAB, 12)

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = COLORS.stroke
mainStroke.Thickness = 1
mainStroke.Parent = mainAB

local dragging, dragStart, startPos
mainAB.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = mainAB.Position
	end
end)
mainAB.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		mainAB.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
	end
end)

local headerAB = Instance.new("Frame")
headerAB.Size = UDim2.new(1, 0, 0, 34)
headerAB.BackgroundColor3 = COLORS.header
headerAB.BorderSizePixel = 0
headerAB.Parent = mainAB
corner(headerAB, 12)

local headerFixAB = Instance.new("Frame")
headerFixAB.Size = UDim2.new(1, 0, 0, 12)
headerFixAB.Position = UDim2.new(0, 0, 1, -12)
headerFixAB.BackgroundColor3 = COLORS.header
headerFixAB.BorderSizePixel = 0
headerFixAB.Parent = headerAB

local toggleTrack = Instance.new("Frame")
toggleTrack.Size = UDim2.new(0, 38, 0, 18)
toggleTrack.Position = UDim2.new(0, 10, 0.5, -9)
toggleTrack.BackgroundColor3 = COLORS.disabled
toggleTrack.BorderSizePixel = 0
toggleTrack.Parent = headerAB
corner(toggleTrack, 9)

local toggleKnob = Instance.new("Frame")
toggleKnob.Size = UDim2.new(0, 14, 0, 14)
toggleKnob.Position = UDim2.new(0, 2, 0.5, -7)
toggleKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
toggleKnob.BorderSizePixel = 0
toggleKnob.Parent = toggleTrack
corner(toggleKnob, 7)

local titleLblAB = Instance.new("TextLabel")
titleLblAB.Size = UDim2.new(1, -110, 1, 0)
titleLblAB.Position = UDim2.new(0, 54, 0, 0)
titleLblAB.BackgroundTransparency = 1
titleLblAB.Text = "🛒 Auto Buy All"
titleLblAB.TextColor3 = COLORS.text
titleLblAB.TextXAlignment = Enum.TextXAlignment.Left
titleLblAB.Font = Enum.Font.GothamBold
titleLblAB.TextSize = 12
titleLblAB.Parent = headerAB

local statusDot = Instance.new("Frame")
statusDot.Size = UDim2.new(0, 8, 0, 8)
statusDot.Position = UDim2.new(1, -76, 0.5, -4)
statusDot.BackgroundColor3 = COLORS.disabled
statusDot.BorderSizePixel = 0
statusDot.Parent = headerAB
corner(statusDot, 4)

local minBtnAB = Instance.new("TextButton")
minBtnAB.Size = UDim2.new(0, 24, 0, 24)
minBtnAB.Position = UDim2.new(1, -56, 0, 5)
minBtnAB.BackgroundColor3 = COLORS.card
minBtnAB.Text = "—"
minBtnAB.TextColor3 = COLORS.text
minBtnAB.Font = Enum.Font.GothamBold
minBtnAB.TextSize = 12
minBtnAB.Parent = headerAB
corner(minBtnAB, 6)

local closeBtnAB = Instance.new("TextButton")
closeBtnAB.Size = UDim2.new(0, 24, 0, 24)
closeBtnAB.Position = UDim2.new(1, -30, 0, 5)
closeBtnAB.BackgroundColor3 = COLORS.red
closeBtnAB.Text = "✕"
closeBtnAB.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtnAB.Font = Enum.Font.GothamBold
closeBtnAB.TextSize = 12
closeBtnAB.Parent = headerAB
corner(closeBtnAB, 6)

local toggleClick = Instance.new("TextButton")
toggleClick.Size = UDim2.new(0, 50, 1, 0)
toggleClick.Position = UDim2.new(0, 6, 0, 0)
toggleClick.BackgroundTransparency = 1
toggleClick.Text = ""
toggleClick.BorderSizePixel = 0
toggleClick.Parent = headerAB

local bodyAB = Instance.new("Frame")
bodyAB.Size = UDim2.new(1, -16, 1, -42)
bodyAB.Position = UDim2.new(0, 8, 0, 38)
bodyAB.BackgroundTransparency = 1
bodyAB.Parent = mainAB

local listFrame = Instance.new("ScrollingFrame")
listFrame.Size = UDim2.new(1, 0, 1, 0)
listFrame.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
listFrame.BorderSizePixel = 0
listFrame.ScrollBarThickness = 3
listFrame.ScrollBarImageColor3 = COLORS.stroke
listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
listFrame.Parent = bodyAB
corner(listFrame, 8)

local listStroke = Instance.new("UIStroke")
listStroke.Color = COLORS.stroke
listStroke.Thickness = 1
listStroke.Parent = listFrame

local listPad = Instance.new("UIPadding", listFrame)
listPad.PaddingTop = UDim.new(0, 6)
listPad.PaddingBottom = UDim.new(0, 6)
listPad.PaddingLeft = UDim.new(0, 6)
listPad.PaddingRight = UDim.new(0, 6)

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 3)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = listFrame

local isRunningAB = false
local shopData = {}
local lastStockAB = {}

local function setToggleVisual(on)
	if on then
		TweenService:Create(toggleTrack, TweenInfo.new(0.15), {
			BackgroundColor3 = COLORS.green
		}):Play()
		TweenService:Create(toggleKnob, TweenInfo.new(0.15), {
			Position = UDim2.new(1, -16, 0.5, -7)
		}):Play()
		TweenService:Create(statusDot, TweenInfo.new(0.15), {
			BackgroundColor3 = COLORS.green
		}):Play()
	else
		TweenService:Create(toggleTrack, TweenInfo.new(0.15), {
			BackgroundColor3 = COLORS.disabled
		}):Play()
		TweenService:Create(toggleKnob, TweenInfo.new(0.15), {
			Position = UDim2.new(0, 2, 0.5, -7)
		}):Play()
		TweenService:Create(statusDot, TweenInfo.new(0.15), {
			BackgroundColor3 = COLORS.disabled
		}):Play()
	end
end

local function rebuildList()
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	local totalItems = 0
	local order = 0

	for _, shop in ipairs(SHOPS) do
		local items = shopData[shop.name] or {}
		if #items > 0 then
			order += 1
			local sectionHeader = Instance.new("TextLabel")
			sectionHeader.Size = UDim2.new(1, 0, 0, 16)
			sectionHeader.BackgroundTransparency = 1
			sectionHeader.Text = string.format("%s %s (%d)", shop.icon, shop.name, #items)
			sectionHeader.TextColor3 = shop.color
			sectionHeader.Font = Enum.Font.GothamBold
			sectionHeader.TextSize = 10
			sectionHeader.TextXAlignment = Enum.TextXAlignment.Left
			sectionHeader.LayoutOrder = order
			sectionHeader.Parent = listFrame

			for _, item in ipairs(items) do
				order += 1
				local row = Instance.new("Frame")
				row.Size = UDim2.new(1, 0, 0, 20)
				row.BackgroundColor3 = COLORS.card
				row.BorderSizePixel = 0
				row.LayoutOrder = order
				row.Parent = listFrame
				corner(row, 4)

				local dot = Instance.new("Frame")
				dot.Size = UDim2.new(0, 5, 0, 5)
				dot.Position = UDim2.new(0, 6, 0.5, -2.5)
				dot.BackgroundColor3 = shop.color
				dot.BorderSizePixel = 0
				dot.Parent = row
				corner(dot, 2.5)

				local nameLbl = Instance.new("TextLabel")
				nameLbl.Size = UDim2.new(1, -60, 1, 0)
				nameLbl.Position = UDim2.new(0, 16, 0, 0)
				nameLbl.BackgroundTransparency = 1
				nameLbl.Text = item.name
				nameLbl.TextColor3 = COLORS.text
				nameLbl.Font = Enum.Font.GothamMedium
				nameLbl.TextSize = 9
				nameLbl.TextXAlignment = Enum.TextXAlignment.Left
				nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
				nameLbl.Parent = row

				local stockLbl = Instance.new("TextLabel")
				stockLbl.Size = UDim2.new(0, 40, 1, 0)
				stockLbl.Position = UDim2.new(1, -44, 0, 0)
				stockLbl.BackgroundTransparency = 1
				stockLbl.Text = "x" .. item.stock
				stockLbl.TextColor3 = shop.color
				stockLbl.Font = Enum.Font.Code
				stockLbl.TextSize = 9
				stockLbl.TextXAlignment = Enum.TextXAlignment.Right
				stockLbl.Parent = row

				totalItems += 1
			end
		end
	end

	if totalItems == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, 0, 0, 40)
		empty.BackgroundTransparency = 1
		empty.Text = "📭 Gak ada stock / shop gak kebuka"
		empty.TextColor3 = COLORS.textDim
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 10
		empty.TextXAlignment = Enum.TextXAlignment.Center
		empty.Parent = listFrame
	end
end

local function refreshAll()
	for _, shop in ipairs(SHOPS) do
		shopData[shop.name] = scanShop(shop)
	end
	rebuildList()
end

local function startAutoBuy()
	task.spawn(function()
		while screenGui.Parent do
			if isRunningAB then
				for _, shop in ipairs(SHOPS) do
					if not isRunningAB then break end
					local items = shopData[shop.name] or {}
					for _, item in ipairs(items) do
						if not isRunningAB then break end
						if item.stock and item.stock > 0 then
							local payload = buildBuyPayload(shop.opcode1, shop.opcode2, item.name)
							if payload then
								pcall(function()
									Packet:FireServer(payload)
								end)
							end
						end
					end
				end
			end
			task.wait(BUY_INTERVAL)
		end
	end)
end

local function toggleRun()
	isRunningAB = not isRunningAB
	setToggleVisual(isRunningAB)
	print("[AutoBuyAll] " .. (isRunningAB and "ON" or "OFF"))
end

toggleClick.MouseButton1Click:Connect(toggleRun)

local isMinimizedAB = false
minBtnAB.MouseButton1Click:Connect(function()
	isMinimizedAB = not isMinimizedAB
	if isMinimizedAB then
		bodyAB.Visible = false
		mainAB.Size = UDim2.new(0, FRAME_WIDTH, 0, FRAME_HEIGHT_MIN)
		minBtnAB.Text = "+"
	else
		bodyAB.Visible = true
		mainAB.Size = UDim2.new(0, FRAME_WIDTH, 0, FRAME_HEIGHT)
		minBtnAB.Text = "—"
	end
end)

closeBtnAB.MouseButton1Click:Connect(function()
	isRunningAB = false
	screenGui:Destroy()
end)

refreshAll()
startAutoBuy()
setToggleVisual(false)

task.spawn(function()
	while screenGui.Parent do
		task.wait(SCAN_INTERVAL)
		refreshAll()
	end
end)

print("✅ Auto Buy All loaded (interval " .. BUY_INTERVAL .. "s)")
print("   Toggle di header buat ON/OFF")
