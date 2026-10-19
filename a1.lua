-- ============================================
-- ALL-IN-ONE v4: WATER + SPRINKLE + CLEANER
-- Fitur:
--   💧 Water & Sprinkle (record + auto fire)
--   🌙 Auto start malam / stop siang
--   🧹 Hapus plot lain (filter 4 lapis)
--   🧹 Hapus _PetVisualClient
-- ============================================

local CoreGui           = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")

local LP = Players.LocalPlayer
local Packet = ReplicatedStorage:WaitForChild("SharedModules")
	:WaitForChild("Packet"):WaitForChild("RemoteEvent")

local ROOT = workspace:WaitForChild("Gardens")

-- ==================================================================
-- CONFIG
-- ==================================================================

local WATER_TOOL_NAME    = "Common Watering Can"
local SPRINKLE_TOOL_NAME = "Super Sprinkler"
local WATER_PREFIX       = "j"
local SPRINKLE_PREFIX    = "8"
local CHECK_INTERVAL     = 3      -- dari 10 → 3 (biar reaksi cepat)
local SPRINKLE_SETTLE    = 1.0
local REC_COUNTDOWN      = 3

local CLEANER_CONFIG = {
	DELETE_OTHER_PLOTS   = true,
	DELETE_PET_VISUAL    = true,
	PLOT_CHECK_INTERVAL  = 3,      -- detik
	PET_CHECK_INTERVAL   = 2,      -- detik
	GARDENS_PATH         = "Workspace.Gardens",
	PET_VISUAL_PATH      = "Workspace._PetVisualClient",
}

local wState = {
	recordingWater    = false,
	recordingSprinkle = false,
	countingWater     = false,
	countingSprinkle  = false,
	waterPayload      = nil,
	sprinklePayload   = nil,
	hasWater          = false,
	hasSprinkle       = false,
	wateringOn        = false,
	sprinkleOn        = false,
	busySprinkle      = false,
}

local ALIVE = true

-- ==================================================================
-- UTIL
-- ==================================================================

local function resolvePath(pathStr)
	pathStr = pathStr:gsub("^%s+", ""):gsub("%s+$", "")
	local segments = {}
	for seg in pathStr:gmatch("[^%.]+") do table.insert(segments, seg) end
	if #segments == 0 or segments[1] ~= "game" then return nil end
	table.remove(segments, 1)
	local node = game
	for _, seg in ipairs(segments) do
		if not node then return nil end
		if seg == "LocalPlayer" then node = LP
		elseif seg == "Players" then node = game:GetService("Players")
		elseif seg == "Workspace" then node = workspace
		elseif seg == "CoreGui" then node = game:GetService("CoreGui")
		elseif seg == "ReplicatedStorage" then node = game:GetService("ReplicatedStorage")
		else
			if node == game:GetService("Players") and seg == LP.Name then
				node = LP
			else
				node = node:FindFirstChild(seg)
			end
		end
	end
	return node
end

-- ==================================================================
-- PLOT DETECTION (4 LAPIS)
-- ==================================================================

local MY_PLOT_NAME = nil

local function isMyPlot(plot)
	-- LAPIS 1: atribut OwnerUserId
	local ok, uid = pcall(function() return plot:GetAttribute("OwnerUserId") end)
	if ok and uid and tonumber(uid) == LP.UserId then
		return true
	end

	-- LAPIS 2: atribut Owner
	local ok2, owner = pcall(function() return plot:GetAttribute("Owner") end)
	if ok2 and owner and (owner == LP.Name or owner == LP.DisplayName) then
		return true
	end

	-- LAPIS 3: plant owner prefix <UserId>_
	local plants = plot:FindFirstChild("Plants")
	if plants then
		for _, plant in ipairs(plants:GetChildren()) do
			local pid = plant.Name:match("^(%d+)_")
			if pid and tonumber(pid) == LP.UserId then
				return true
			end
		end
	end

	-- LAPIS 4: sign text (substring)
	local signs = plot:FindFirstChild("Signs")
	if signs then
		local garden = signs:FindFirstChild("Garden")
		local core   = garden and garden:FindFirstChild("CorePart")
		local sg     = core and core:FindFirstChild("SurfaceGui")
		local playerLbl = sg and sg:FindFirstChild("Player")
		local textLbl   = playerLbl and playerLbl:FindFirstChild("TextLabel")
		if textLbl then
			local txt = textLbl.Text
			if txt:find(LP.DisplayName, 1, true) or txt:find(LP.Name, 1, true) then
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

detectMyPlot()

-- ==================================================================
-- CLEANER: HAPUS PLOT LAIN
-- ==================================================================

local function deleteOtherPlots()
	if not CLEANER_CONFIG.DELETE_OTHER_PLOTS then return 0 end
	local gardens = resolvePath(CLEANER_CONFIG.GARDENS_PATH)
	if not gardens then return 0 end

	local myName = getMyPlot() and MY_PLOT_NAME or nil
	if not myName then return 0 end

	local deleted = 0
	for _, plot in ipairs(gardens:GetChildren()) do
		if plot.Name ~= myName and not isMyPlot(plot) then
			pcall(function()
				plot:Destroy()
				deleted += 1
			end)
		end
	end
	if deleted > 0 then
		print(string.format("🧹 Hapus %d plot lain", deleted))
	end
	return deleted
end

-- ==================================================================
-- CLEANER: HAPUS _PetVisualClient
-- ==================================================================

local function deletePetVisualClient()
	if not CLEANER_CONFIG.DELETE_PET_VISUAL then return false end
	local target = resolvePath(CLEANER_CONFIG.PET_VISUAL_PATH)
	if target then
		pcall(function() target:Destroy() end)
		if not target.Parent then
			print("🧹 _PetVisualClient dihapus.")
			return true
		end
	end
	return false
end

-- ==================================================================
-- CLEANER: WATCHER
-- ==================================================================

task.spawn(function()
	local gardens = resolvePath(CLEANER_CONFIG.GARDENS_PATH)
	if gardens then
		gardens.ChildAdded:Connect(function(child)
			if not ALIVE then return end
			task.defer(function()
				if not ALIVE then return end
				if MY_PLOT_NAME and child.Name ~= MY_PLOT_NAME and not isMyPlot(child) then
					pcall(function() child:Destroy() end)
					print("🧹 Plot baru dihapus:", child.Name)
				end
			end)
		end)
	end

	workspace.ChildAdded:Connect(function(child)
		if not ALIVE then return end
		if CLEANER_CONFIG.DELETE_PET_VISUAL and child.Name == "_PetVisualClient" then
			task.defer(function()
				if not ALIVE then return end
				pcall(function() child:Destroy() end)
				print("🧹 _PetVisualClient respawn → dihapus.")
			end)
		end
	end)
end)

-- Run initial cleaner
deleteOtherPlots()
deletePetVisualClient()

-- ==================================================================
-- SMART EQUIP
-- ==================================================================

local function ensureToolEquipped(toolName)
	local char = LP.Character or LP.CharacterAdded:Wait()
	if not char then return nil end
	local equipped = char:FindFirstChild(toolName)
	if equipped then return equipped end
	local backpack = LP:FindFirstChild("Backpack")
	if not backpack then
		backpack = LP:WaitForChild("Backpack", 3)
	end
	if not backpack then return nil end
	local tool = backpack:FindFirstChild(toolName)
	if not tool then
		tool = backpack:WaitForChild(toolName, 2)
	end
	if not tool then return nil end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end
	local ok = pcall(function() humanoid:EquipTool(tool) end)
	if not ok then return nil end
	local t0 = os.clock()
	while os.clock() - t0 < 1.0 do
		task.wait(0.05)
		local eq = char:FindFirstChild(toolName)
		if eq then return eq end
	end
	return char:FindFirstChild(toolName)
end

-- ==================================================================
-- SPRINKLER CHECK
-- ==================================================================

local function hasActiveSprinkler()
	local plot = getMyPlot()
	if not plot then return false, 0 end
	local sprinklers = plot:FindFirstChild("Sprinklers")
	if not sprinklers then return false, 0 end
	local count = 0
	for _, child in ipairs(sprinklers:GetChildren()) do
		local ownerId = child.Name:match("^(%d+)_")
		if not ownerId or tonumber(ownerId) == LP.UserId then
			count += 1
		end
	end
	return count > 0, count
end

-- ==================================================================
-- HOOK (RECORDING)
-- ==================================================================

local hookActive = false
local originalNamecall = nil
local hookedMeta = nil

local function installHook()
	if hookActive then return end
	local ok = pcall(function()
		hookedMeta = getrawmetatable(game)
		if not hookedMeta then error("no metatable") end
		originalNamecall = hookedMeta.__namecall
		if not originalNamecall then error("no __namecall") end
		setreadonly(hookedMeta, false)
		hookedMeta.__namecall = newcclosure(function(self, ...)
			local method = getnamecallmethod()
			if method == "FireServer"
				and typeof(self) == "Instance"
				and self.ClassName == "RemoteEvent" then
				local args = {...}
				for _, v in ipairs(args) do
					if typeof(v) == "buffer" then
						local okStr, str = pcall(function()
							return buffer.readstring(v, 0, buffer.len(v))
						end)
						if okStr and str and #str > 0 then
							local prefix = str:sub(1, 1)
							if prefix == WATER_PREFIX and wState.recordingWater then
								wState.waterPayload = v
								wState.hasWater = true
								wState.recordingWater = false
								_G.__waterRecorded = true
							end
							if prefix == SPRINKLE_PREFIX and wState.recordingSprinkle then
								wState.sprinklePayload = v
								wState.hasSprinkle = true
								wState.recordingSprinkle = false
								_G.__sprinkleRecorded = true
							end
						end
					end
				end
			end
			return originalNamecall(self, ...)
		end)
		setreadonly(hookedMeta, true)
		hookActive = true
	end)
	if not ok then warn("❌ Hook gagal install") end
end

local function uninstallHook()
	if not hookActive then return end
	pcall(function()
		setreadonly(hookedMeta, false)
		hookedMeta.__namecall = originalNamecall
		setreadonly(hookedMeta, true)
	end)
	hookActive = false
end

-- ==================================================================
-- FIRE
-- ==================================================================

local function fireWater()
	if not ALIVE or not wState.waterPayload then return false end
	local char = LP.Character
	if not char then return false end
	local equipped = char:FindFirstChild(WATER_TOOL_NAME)
	if not equipped or not equipped.Parent then
		equipped = ensureToolEquipped(WATER_TOOL_NAME)
		if not equipped then
			warn("[fireWater] tool tidak siap")
			return false
		end
		task.wait(0.1)
	end
	return pcall(function() Packet:FireServer(wState.waterPayload, {equipped}) end)
end

local function fireSprinkle()
	if not ALIVE or not wState.sprinklePayload then return false end
	local char = LP.Character
	if not char then return false end
	local equipped = char:FindFirstChild(SPRINKLE_TOOL_NAME)
	if not equipped or not equipped.Parent then
		equipped = ensureToolEquipped(SPRINKLE_TOOL_NAME)
		if not equipped then return false end
		task.wait(0.15)
	end
	return pcall(function() Packet:FireServer(wState.sprinklePayload, {equipped}) end)
end

-- ==================================================================
-- SHUTDOWN
-- ==================================================================

local function shutdown(reason)
	if not ALIVE then return end
	ALIVE = false
	wState.wateringOn = false
	wState.sprinkleOn = false
	uninstallHook()
	if reason then print("🛑 Shutdown:", reason) end
end

-- ==================================================================
-- GUI
-- ==================================================================

local old = CoreGui:FindFirstChild("WaterAuctionGui")
if old then old:Destroy() end
local old2 = CoreGui:FindFirstChild("WaterSprinkleGui")
if old2 then old2:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "WaterSprinkleGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 9999
gui.Parent = CoreGui

local FULL_H = 140
local MINI_H = 28

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 200, 0, FULL_H)
main.Position = UDim2.new(0, 20, 0, 60)
main.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(48, 48, 58)
stroke.Thickness = 1
stroke.Parent = main

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
titleLbl.Text = "💧🌱 Water + Sprinkle"
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
	l.TextColor3 = Color3.fromRGB(120, 120, 145)
	l.Font = Enum.Font.GothamBold
	l.TextSize = 9
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = body
	return l
end

makeSectionLbl("💧 WATER & SPRINKLE", 6)

local waterBtn = Instance.new("TextButton")
waterBtn.Size = UDim2.new(0.5, -13, 0, 32)
waterBtn.Position = UDim2.new(0, 8, 0, 22)
waterBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 140)
waterBtn.Text = "REC Water"
waterBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
waterBtn.Font = Enum.Font.GothamBold
waterBtn.TextSize = 10
waterBtn.Parent = body
Instance.new("UICorner", waterBtn).CornerRadius = UDim.new(0, 6)

local sprBtn = Instance.new("TextButton")
sprBtn.Size = UDim2.new(0.5, -13, 0, 32)
sprBtn.Position = UDim2.new(0.5, 5, 0, 22)
sprBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 70)
sprBtn.Text = "REC Sprinkler"
sprBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
sprBtn.Font = Enum.Font.GothamBold
sprBtn.TextSize = 10
sprBtn.Parent = body
Instance.new("UICorner", sprBtn).CornerRadius = UDim.new(0, 6)

local resetBtn = Instance.new("TextButton")
resetBtn.Size = UDim2.new(1, -16, 0, 24)
resetBtn.Position = UDim2.new(0, 8, 0, 58)
resetBtn.BackgroundColor3 = Color3.fromRGB(90, 45, 45)
resetBtn.Text = "🔄 RESET REKAMAN"
resetBtn.TextColor3 = Color3.fromRGB(255, 230, 230)
resetBtn.Font = Enum.Font.GothamBold
resetBtn.TextSize = 10
resetBtn.Parent = body
Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0, 6)

local resetBtn2 = Instance.new("TextButton")
resetBtn2.Size = UDim2.new(1, -16, 0, 20)
resetBtn2.Position = UDim2.new(0, 8, 0, 86)
resetBtn2.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
resetBtn2.Text = "⏹️ STOP WATER/SPRINKLE"
resetBtn2.TextColor3 = Color3.fromRGB(230, 230, 240)
resetBtn2.Font = Enum.Font.GothamBold
resetBtn2.TextSize = 9
resetBtn2.Parent = body
Instance.new("UICorner", resetBtn2).CornerRadius = UDim.new(0, 6)

-- ==================================================================
-- BUTTON HANDLERS
-- ==================================================================

local function setWaterIdle()
	waterBtn.Text = "REC Water"
	waterBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 140)
end
local function setWaterActive()
	waterBtn.Text = "💧 WATER: ON"
	waterBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
end
local function setWaterOff()
	waterBtn.Text = "💧 WATER: OFF"
	waterBtn.BackgroundColor3 = Color3.fromRGB(45, 60, 90)
end
local function setSprIdle()
	sprBtn.Text = "REC Sprinkler"
	sprBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 70)
end
local function setSprActive()
	sprBtn.Text = "🌱 SPR: ON"
	sprBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
end
local function setSprOff()
	sprBtn.Text = "🌱 SPR: OFF"
	sprBtn.BackgroundColor3 = Color3.fromRGB(50, 70, 55)
end

waterBtn.MouseButton1Click:Connect(function()
	if not ALIVE then return end

	if wState.countingWater then
		wState.countingWater = false
		setWaterIdle()
		return
	end

	if wState.recordingWater then
		wState.recordingWater = false
		setWaterIdle()
		return
	end

	if wState.hasWater then
		wState.wateringOn = not wState.wateringOn
		if wState.wateringOn then setWaterActive() else setWaterOff() end
		return
	end

	local tool = ensureToolEquipped(WATER_TOOL_NAME)
	if not tool then
		waterBtn.Text = "❌ No Tool"
		task.wait(1.0)
		if ALIVE then setWaterIdle() end
		return
	end

	wState.countingWater = true
	task.spawn(function()
		for i = REC_COUNTDOWN, 1, -1 do
			if not ALIVE or not wState.countingWater then
				setWaterIdle()
				return
			end
			waterBtn.Text = string.format("⏱ %ds...", i)
			waterBtn.BackgroundColor3 = Color3.fromRGB(120, 100, 40)
			task.wait(1)
		end
		if not ALIVE or not wState.countingWater then
			setWaterIdle()
			return
		end
		wState.countingWater = false
		wState.recordingWater = true
		waterBtn.Text = "🔴 REC..."
		waterBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
		installHook()
	end)
end)

sprBtn.MouseButton1Click:Connect(function()
	if not ALIVE then return end

	if wState.countingSprinkle then
		wState.countingSprinkle = false
		setSprIdle()
		return
	end

	if wState.recordingSprinkle then
		wState.recordingSprinkle = false
		setSprIdle()
		return
	end

	if wState.hasSprinkle then
		wState.sprinkleOn = not wState.sprinkleOn
		if wState.sprinkleOn then setSprActive() else setSprOff() end
		return
	end

	local tool = ensureToolEquipped(SPRINKLE_TOOL_NAME)
	if not tool then
		sprBtn.Text = "❌ No Tool"
		task.wait(1.0)
		if ALIVE then setSprIdle() end
		return
	end

	wState.countingSprinkle = true
	task.spawn(function()
		for i = REC_COUNTDOWN, 1, -1 do
			if not ALIVE or not wState.countingSprinkle then
				setSprIdle()
				return
			end
			sprBtn.Text = string.format("⏱ %ds...", i)
			sprBtn.BackgroundColor3 = Color3.fromRGB(120, 100, 40)
			task.wait(1)
		end
		if not ALIVE or not wState.countingSprinkle then
			setSprIdle()
			return
		end
		wState.countingSprinkle = false
		wState.recordingSprinkle = true
		sprBtn.Text = "🔴 REC..."
		sprBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
		installHook()
	end)
end)

resetBtn.MouseButton1Click:Connect(function()
	if not ALIVE then return end
	wState.waterPayload     = nil
	wState.sprinklePayload  = nil
	wState.hasWater         = false
	wState.hasSprinkle      = false
	wState.recordingWater   = false
	wState.recordingSprinkle= false
	wState.countingWater    = false
	wState.countingSprinkle = false
	wState.wateringOn       = false
	wState.sprinkleOn       = false
	setWaterIdle()
	setSprIdle()
	print("🔄 Rekaman water & sprinkle di-reset.")
	resetBtn.Text = "✅ RESET!"
	task.wait(1)
	resetBtn.Text = "🔄 RESET REKAMAN"
end)

resetBtn2.MouseButton1Click:Connect(function()
	if not ALIVE then return end
	wState.wateringOn  = false
	wState.sprinkleOn  = false
	wState.busySprinkle = false
	if wState.hasWater then setWaterOff() else setWaterIdle() end
	if wState.hasSprinkle then setSprOff() else setSprIdle() end
	print("⏹️ Water & Sprinkle dimatikan.")
end)

-- ==================================================================
-- MINIMIZE / CLOSE
-- ==================================================================

local isMinimized = false
minBtn.MouseButton1Click:Connect(function()
	isMinimized = not isMinimized
	body.Visible = not isMinimized
	main.Size = isMinimized and UDim2.new(0, 200, 0, MINI_H) or UDim2.new(0, 200, 0, FULL_H)
	minBtn.Text = isMinimized and "+" or "—"
end)

closeBtn.MouseButton1Click:Connect(function()
	shutdown("GUI ditutup")
	if gui then gui:Destroy() end
end)

gui.Destroying:Connect(function() shutdown("GUI Destroying event") end)

Players.PlayerRemoving:Connect(function(p)
	if p == LP then shutdown("Player keluar game") end
end)

-- ==================================================================
-- UI UPDATE LOOP (RECORDED + TIME LOGIC + FIRE LANGSUNG)
-- ==================================================================

task.spawn(function()
	while ALIVE and gui.Parent do
		task.wait(0.5)
		if not ALIVE then break end

		if _G.__waterRecorded then
			_G.__waterRecorded = nil
			wState.hasWater = true
			setWaterOff()
			print("✅ Water payload recorded")
		end
		if _G.__sprinkleRecorded then
			_G.__sprinkleRecorded = nil
			wState.hasSprinkle = true
			setSprOff()
			print("✅ Sprinkle payload recorded")
		end

		-- Time logic malam/siang
		if wState.hasWater and wState.hasSprinkle then
			local clockTime = Lighting.ClockTime
			local isNight = (clockTime >= 18.0 or clockTime < 6.0)
			if isNight then
				if not wState.wateringOn or not wState.sprinkleOn then
					wState.wateringOn = true
					wState.sprinkleOn = true
					setWaterActive()
					setSprActive()
					print("🌙 Malam → AUTO START")

					-- ⚡ FIRE LANGSUNG (jangan tunggu main loop)
					task.spawn(function()
						if not ALIVE then return end
						local has = hasActiveSprinkler()
						if not has and wState.hasSprinkle then
							fireSprinkle()
							task.wait(SPRINKLE_SETTLE)
							if not ALIVE then return end
							has = hasActiveSprinkler()
						end
						if ALIVE and wState.hasWater then
							fireWater()
							print("💧 Water fired on night start")
						end
					end)
				end
			else
				if wState.wateringOn or wState.sprinkleOn then
					wState.wateringOn = false
					wState.sprinkleOn = false
					setWaterOff()
					setSprOff()
					print("☀️ Siang → AUTO STOP")
				end
			end
		end
	end
end)

-- ==================================================================
-- MAIN LOOP (WATER + SPRINKLE + CLEANER)
-- ==================================================================

task.spawn(function()
	local lastPlotCheck = 0
	local lastPetCheck  = 0

	while ALIVE and gui.Parent do
		task.wait(CHECK_INTERVAL)
		if not ALIVE then break end

		-- Water & Sprinkle
		local has = hasActiveSprinkler()

		if wState.sprinkleOn and wState.hasSprinkle and not has and not wState.busySprinkle then
			wState.busySprinkle = true
			local ok, err = pcall(function()
				local fired = fireSprinkle()
				if fired then
					task.wait(SPRINKLE_SETTLE)
					hasActiveSprinkler()
				end
			end)
			wState.busySprinkle = false
			has = hasActiveSprinkler()   -- ⚡ update
			if not ok then warn("fireSprinkle error:", err) end
		end

		if wState.wateringOn and wState.hasWater and has then
			local ok, err = pcall(fireWater)
			if not ok then warn("fireWater error:", err) end
		end

		-- Cleaner (pakai timer sendiri)
		local now = os.clock()
		if CLEANER_CONFIG.DELETE_OTHER_PLOTS
			and now - lastPlotCheck >= CLEANER_CONFIG.PLOT_CHECK_INTERVAL then
			lastPlotCheck = now
			deleteOtherPlots()
		end
		if CLEANER_CONFIG.DELETE_PET_VISUAL
			and now - lastPetCheck >= CLEANER_CONFIG.PET_CHECK_INTERVAL then
			lastPetCheck = now
			deletePetVisualClient()
		end
	end
end)

-- ==================================================================
-- INIT
-- ==================================================================

installHook()
print("=====================================")
print("✅ Water + Sprinkle + Cleaner loaded")
print("   Plot:", MY_PLOT_NAME or "(belum terdeteksi)")
print("   Hapus plot lain :", CLEANER_CONFIG.DELETE_OTHER_PLOTS and "ON" or "OFF")
print("   Hapus PetVisual :", CLEANER_CONFIG.DELETE_PET_VISUAL and "ON" or "OFF")
print("   CHECK_INTERVAL  :", CHECK_INTERVAL, "detik")
print("=====================================")
