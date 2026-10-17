-- ============================================
-- ALL-IN-ONE: AUTO BUY + GARDEN SHIELD + AUTO HARVEST/MAIL
-- ============================================
-- FITUR:
--   [AUTO BUY]    Gear + Seed + Crate → langsung aktif (tanpa toggle)
--   [SHIELD]      Weld ke lantai + auto-return ke garden (toggle)
--   [HARVEST]     Auto panen + filter berat/mutasi (toggle)
--   [AUTO SELL]   Jual otomatis (toggle)
--   [AUTO MAIL]   Kirim 15 Bloodlit >150kg fav (toggle)
-- ============================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui           = game:GetService("CoreGui")
local UserInputService  = game:GetService("UserInputService")
local HttpService       = game:GetService("HttpService")

local player = Players.LocalPlayer

local Packet = ReplicatedStorage:WaitForChild("SharedModules")
	:WaitForChild("Packet"):WaitForChild("RemoteEvent")

-- ==================================================================
-- BAGIAN 1: AUTO BUY (LANGSUNG AKTIF)
-- ==================================================================

local GEAR_LIST = {
	"Cider Watering Can",
	"Super Cider Watering Can",
	"Common Cider Sprinkler",
	"Uncommon Cider Sprinkler",
	"Rare Cider Sprinkler",
	"Legendary Cider Sprinkler",
	"Super Cider Sprinkler",
	"Rare Magic Mail",
	"Legendary Magic Mail",
	"Super Magic Mail",
	"Candy Basket",
	"Cauldron Charm",
	"Bat Charm",
	"Trowel",
}

local SEED_LIST = {
	"Spirit Venom Spitter",
	"Spirit Venus Fly Trap",
	"Spirit Carrot",
	"Spirit Tulip",
	"Great Pumpkin",
	"Vampire Bloom",
}

local CRATE_LIST = {
	"Gravestone Crate",
	"Halloween Prop Crate",
	"Fog Machine Crate",
}

local function buildGearPayload(name)
	local len = #name
	if len > 255 then return nil end
	return buffer.fromstring("\206\000" .. string.char(len) .. name)
end

local function buildSeedPayload(name)
	local len = #name
	if len > 255 then return nil end
	return buffer.fromstring("\184\000" .. string.char(len) .. name)
end

local function buildCratePayload(name)
	local len = #name
	if len > 255 then return nil end
	return buffer.fromstring("\204\000" .. string.char(len) .. name)
end

local GEAR_BASE  = "game.Players.LocalPlayer.PlayerGui.GearShop.Frame.ScrollingFrame"
local SEED_BASE  = "game.Players.LocalPlayer.PlayerGui.SeedShop.Frame.NormalShop"
local CRATE_BASE = "game.Players.LocalPlayer.PlayerGui.CrateShop.Frame.ScrollingFrame"

local function getGearStockPath(name)
	return GEAR_BASE .. "." .. name .. ".Main_Frame.Stock_Text"
end
local function getSeedStockPath(name)
	return SEED_BASE .. "." .. name .. ".Main_Frame.Stock_Text"
end
local function getCrateStockPath(name)
	return CRATE_BASE .. "." .. name .. ".Main_Frame.Stock_Text"
end

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

local function parseStock(label)
	if not label or not label.Text then return nil end
	return tonumber(label.Text:match("[xX](%d+)")) or tonumber(label.Text:match("(%d+)"))
end

local BUY_INTERVAL = 0.5
local lastStock = {}

local function startAutoBuy(key, kind, stockPath, payloadBuilder)
	task.spawn(function()
		while true do
			local label = resolvePath(stockPath)
			local stock = parseStock(label)
			if stock and stock > 0 then
				local payload = payloadBuilder(key)
				if payload then
					local ok = pcall(function() Packet:FireServer(payload) end)
					if ok and lastStock[key] ~= stock then
						lastStock[key] = stock
						print(string.format("[BUY] %s | %s | stok: %d", kind, key, stock))
					end
				end
			else
				if stock == 0 then lastStock[key] = nil end
			end
			task.wait(BUY_INTERVAL)
		end
	end)
end

print("=====================================")
print("[AutoBuy] Starting... (langsung aktif)")
print(string.format("[AutoBuy] Gear:%d | Seeds:%d | Crates:%d",
	#GEAR_LIST, #SEED_LIST, #CRATE_LIST))
print("=====================================")

for _, name in ipairs(GEAR_LIST) do
	startAutoBuy(name, "GEAR", getGearStockPath(name), buildGearPayload)
end
for _, name in ipairs(SEED_LIST) do
	startAutoBuy(name, "SEED", getSeedStockPath(name), buildSeedPayload)
end
for _, name in ipairs(CRATE_LIST) do
	startAutoBuy(name, "CRATE", getCrateStockPath(name), buildCratePayload)
end

print("[AutoBuy] Semua item auto-buy sudah aktif.")

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
-- BAGIAN 3: AUTO HARVEST + PRIORITY FARM + AUTO MAIL
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

	MAIL_ENABLED        = true,   -- default OFF (kirim ke orang lain)
	MAIL_TARGET_USER    = "Andri21649",
	MAIL_TARGET_ID      = nil,
	MAIL_TRIGGER_MUT    = "Bloodlit",
	MAIL_TRIGGER_WEIGHT = 150,
	MAIL_TRIGGER_COUNT  = 15,
	MAIL_CATEGORY       = "HarvestedFruits",
	MAIL_CHECK_INTERVAL = 5,
}

local WEIGHT_K = 9
local CHEAP_MUTATIONS = {
	Electric = true, Gold = true, Frozen = true,
	Rainbow = true, Starstruck = true,
}

local SELL_PAYLOAD = "\015\001\018"
local FAV_PREFIX   = "\179\0004$"
local UNFAV_PREFIX = "\179\0006$"

local ALIVE          = true
local isPriorityBusy = false
local isMailBusy     = false
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

local function unfavoriteFruit(uuid)
	if not ALIVE or not uuid then return false end
	local payload = UNFAV_PREFIX .. uuid .. "\000"
	return pcall(function() Packet:FireServer(buffer.fromstring(payload)) end)
end

local function resolveUsername(username)
	local ok, userId = pcall(function()
		return Players:GetUserIdFromNameAsync(username)
	end)
	if ok and userId then return userId end
	local ok2, response = pcall(function()
		return request({
			Url = "https://users.roblox.com/v1/usernames/users",
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = HttpService:JSONEncode({
				usernames = { username },
				excludeBannedUsers = false
			})
		})
	end)
	if ok2 and response and response.Body then
		local data = HttpService:JSONDecode(response.Body)
		if data.data and data.data[1] then return data.data[1].id end
	end
	return nil
end

local function buildMultiEntryPayload(targetUserId, entries)
	local CATEGORY = CONFIG.MAIL_CATEGORY
	local needed = 16
	for _, e in ipairs(entries) do
		needed = needed + 3
			+ (2 + #"ItemKey") + (2 + #e.uuid)
			+ (2 + #"Count")   + 3
			+ (2 + #"Category")+ (2 + #CATEGORY)
			+ 1
	end
	needed = needed + 4

	local buf = buffer.create(needed)
	local pos = 0
	buffer.writeu8(buf, pos, 0x8C); pos += 1
	buffer.writeu8(buf, pos, 0x01); pos += 1
	buffer.writeu8(buf, pos, 0x69); pos += 1
	buffer.writef64(buf, pos, targetUserId); pos += 8
	buffer.writeu8(buf, pos, 0x1C); pos += 1

	local function writeString(s)
		buffer.writeu8(buf, pos, 0x0B); pos += 1
		buffer.writeu8(buf, pos, #s);  pos += 1
		for i = 1, #s do
			buffer.writeu8(buf, pos, string.byte(s, i)); pos += 1
		end
	end
	local function writeInt(n)
		buffer.writeu8(buf, pos, 0x05); pos += 1
		buffer.writeu8(buf, pos, n % 256); pos += 1
	end
	for i, entry in ipairs(entries) do
		buffer.writeu8(buf, pos, 0x05); pos += 1
		buffer.writeu8(buf, pos, i % 256); pos += 1
		buffer.writeu8(buf, pos, 0x1C); pos += 1
		writeString("ItemKey");  writeString(entry.uuid)
		writeString("Count");    writeInt(entry.count or 1)
		writeString("Category"); writeString(CATEGORY)
		buffer.writeu8(buf, pos, 0x00); pos += 1
	end
	buffer.writeu8(buf, pos, 0x00); pos += 1
	buffer.writeu8(buf, pos, 0x00); pos += 1
	buffer.writeu8(buf, pos, 0x00); pos += 1

	local final = buffer.create(pos)
	buffer.copy(final, 0, buf, 0, pos)
	return final
end

local function sendMail(targetUserId, entries)
	if not ALIVE or not targetUserId or #entries == 0 then return false end
	local payload = buildMultiEntryPayload(targetUserId, entries)
	return pcall(function() Packet:FireServer(payload) end)
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

local function getMailCandidates()
	local list = {}
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return list end
	local targetMut = CONFIG.MAIL_TRIGGER_MUT:lower()
	for _, item in ipairs(backpack:GetChildren()) do
		local uuid  = item:GetAttribute("Id")
		local isFav = item:GetAttribute("IsFavorite")
		local w     = item:GetAttribute("Weight")
		local mut   = item:GetAttribute("Mutation")
		if uuid and isFav == true and w and mut then
			if w > CONFIG.MAIL_TRIGGER_WEIGHT and tostring(mut):lower() == targetMut then
				table.insert(list, {
					tool = item, uuid = uuid, name = item.Name,
					weight = w, mutation = mut,
				})
			end
		end
	end
	return list
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
	if isPriorityBusy or isMailBusy then return end
	isPriorityBusy = true
	print("")
	print("🌟 ═══ PRIORITY FARM ═══")
	local prevSell = CONFIG.AUTO_SELL_ENABLED
	CONFIG.AUTO_SELL_ENABLED = false
	task.wait(0.3)
	local totalSaved, totalSold, round = 0, 0, 0
	while ALIVE and not isMailBusy and round < 10 do
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
			if not ALIVE or isMailBusy then break end
			harvest(t.plant, t.fruit)
			task.wait(0.15)
		end
		task.wait(0.8)
		local newTools = getNewBackpackTools(beforeUUIDs)
		for _, t in ipairs(newTools) do
			if not ALIVE or isMailBusy then break end
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
		if #newTools > 0 and not isMailBusy then
			task.wait(0.5); sellBackpack()
		end
		task.wait(0.3)
	end
	print(string.format("🌟 Total: %d saved, %d sold", totalSaved, totalSold))
	if prevSell and not isMailBusy then CONFIG.AUTO_SELL_ENABLED = true end
	print("🌟 ═══════════════════════")
	print("")
	isPriorityBusy = false
end

local function doMailMode()
	if isMailBusy then return end
	isMailBusy = true
	print("")
	print("📬 ═══ AUTO MAIL MODE ═══")
	local prevAuto = CONFIG.AUTO_ENABLED
	local prevSell = CONFIG.AUTO_SELL_ENABLED
	CONFIG.AUTO_ENABLED      = false
	CONFIG.AUTO_SELL_ENABLED = false

	if not CONFIG.MAIL_TARGET_ID then
		print("📬 Resolving target:", CONFIG.MAIL_TARGET_USER)
		local id = resolveUsername(CONFIG.MAIL_TARGET_USER)
		if id then
			CONFIG.MAIL_TARGET_ID = id
			print("📬 ✅ Target ID:", id)
		else
			print("📬 ❌ Gagal resolve. Dibatalkan.")
			CONFIG.AUTO_ENABLED      = prevAuto
			CONFIG.AUTO_SELL_ENABLED = prevSell
			isMailBusy = false
			return
		end
	end

	-- Guard: jangan kirim ke diri sendiri
	if CONFIG.MAIL_TARGET_ID == player.UserId then
		warn("📬 ❌ Target == LocalPlayer. Dibatalkan.")
		CONFIG.AUTO_ENABLED      = prevAuto
		CONFIG.AUTO_SELL_ENABLED = prevSell
		isMailBusy = false
		return
	end

	task.wait(0.3)
	local candidates = getMailCandidates()
	print(string.format("📬 Kandidat: %d (butuh %d)", #candidates, CONFIG.MAIL_TRIGGER_COUNT))
	if #candidates < CONFIG.MAIL_TRIGGER_COUNT then
		print("📬 ❌ Kandidat kurang. Dibatalkan.")
		CONFIG.AUTO_ENABLED      = prevAuto
		CONFIG.AUTO_SELL_ENABLED = prevSell
		isMailBusy = false
		return
	end

	table.sort(candidates, function(a, b) return (a.weight or 0) > (b.weight or 0) end)
	local picked = {}
	for i = 1, CONFIG.MAIL_TRIGGER_COUNT do table.insert(picked, candidates[i]) end

	print("📬 Unfavorite 15 buah...")
	for _, t in ipairs(picked) do
		if not ALIVE then break end
		unfavoriteFruit(t.uuid)
		task.wait(0.15)
	end
	task.wait(1)

	local mailEntries = {}
	for _, t in ipairs(picked) do
		table.insert(mailEntries, { uuid = t.uuid, count = 1, name = t.name })
	end

	print(string.format("📬 Kirim %d item → %s (ID %d)",
		#mailEntries, CONFIG.MAIL_TARGET_USER, CONFIG.MAIL_TARGET_ID))
	if sendMail(CONFIG.MAIL_TARGET_ID, mailEntries) then
		print("📬 ✅ Mail terkirim!")
		if mailStatusLbl then
			mailStatusLbl.Text = string.format("📬 ✅ sent %d → %s",
				#mailEntries, CONFIG.MAIL_TARGET_USER)
			mailStatusLbl.TextColor3 = Color3.fromRGB(150, 255, 150)
		end
	else
		print("📬 ❌ Gagal kirim mail.")
	end
	task.wait(1)

	CONFIG.AUTO_ENABLED      = prevAuto
	CONFIG.AUTO_SELL_ENABLED = prevSell
	print("📬 ═══ SELESAI ═══")
	print("")
	isMailBusy = false
end

-- Harvest loop
task.spawn(function()
	while ALIVE do
		task.wait(CONFIG.AUTO_DELAY)
		if not ALIVE then break end
		if isPriorityBusy or isMailBusy then continue end
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
					if not ALIVE or isPriorityBusy or isMailBusy then break end
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
		if isPriorityBusy or isMailBusy then continue end
		if CONFIG.AUTO_SELL_ENABLED then sellBackpack() end
	end
end)

-- Mail check loop
task.spawn(function()
	while ALIVE do
		task.wait(CONFIG.MAIL_CHECK_INTERVAL)
		if not ALIVE then break end
		if isMailBusy or isPriorityBusy then continue end
		if not CONFIG.MAIL_ENABLED then continue end
		local candidates = getMailCandidates()
		local n = #candidates
		if mailStatusLbl then
			mailStatusLbl.Text = string.format("📬 %d/%d Bloodlit >150kg fav",
				n, CONFIG.MAIL_TRIGGER_COUNT)
			mailStatusLbl.TextColor3 = (n >= CONFIG.MAIL_TRIGGER_COUNT)
				and Color3.fromRGB(150, 255, 150)
				or Color3.fromRGB(180, 200, 255)
		end
		if n >= CONFIG.MAIL_TRIGGER_COUNT then
			print(string.format("📬 Trigger! %d Bloodlit", n))
			task.spawn(doMailMode)
		end
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

local FULL_H = 210
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
makeSliderToggle(body, "📬 Auto Mail", 112,
	function() return CONFIG.MAIL_ENABLED end,
	function(v)
		CONFIG.MAIL_ENABLED = v
		print("📬 Auto Mail " .. (v and "ON" or "OFF"))
	end
)

-- Mail status label (dideklarasikan global supaya bisa diakses loop mail)
mailStatusLbl = Instance.new("TextLabel")
mailStatusLbl.Size = UDim2.new(1, -20, 0, 14)
mailStatusLbl.Position = UDim2.new(0, 10, 0, 134)
mailStatusLbl.BackgroundTransparency = 1
mailStatusLbl.Text = "📬 target: -"
mailStatusLbl.TextColor3 = Color3.fromRGB(180, 200, 255)
mailStatusLbl.Font = Enum.Font.Gotham
mailStatusLbl.TextSize = 9
mailStatusLbl.TextXAlignment = Enum.TextXAlignment.Left
mailStatusLbl.TextTruncate = Enum.TextTruncate.AtEnd
mailStatusLbl.Parent = body

-- Info box
local infoLbl = Instance.new("TextLabel")
infoLbl.Size = UDim2.new(1, -20, 0, 26)
infoLbl.Position = UDim2.new(0, 10, 0, 152)
infoLbl.BackgroundTransparency = 1
infoLbl.Text = "⚙️ Auto Buy: ON (background)\n🛡️ Shield & 🌾 Harvest manual"
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
	CONFIG.MAIL_ENABLED = false
	isShieldRunning = false
	if gui then gui:Destroy() end
	print("🛑 Semua fitur dimatikan. Script stopped.")
end)

-- ==================================================================
-- INIT / BACKGROUND TASK
-- ==================================================================

task.spawn(function()
	local id = resolveUsername(CONFIG.MAIL_TARGET_USER)
	if id then
		CONFIG.MAIL_TARGET_ID = id
		if mailStatusLbl then
			mailStatusLbl.Text = string.format("📬 target: %s (%d)",
				CONFIG.MAIL_TARGET_USER, id)
		end
		print("📬 Target ID resolved:", id)
	end
end)

Players.PlayerRemoving:Connect(function(p)
	if p == player then ALIVE = false end
end)
