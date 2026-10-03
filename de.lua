-- LocalScript: Clear Map + Disable Collider
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- ============================================================
-- CONFIG
-- ============================================================
local CONFIG = {
	-- Hapus semua anak dari folder ini
	DELETE_CHILDREN = {
		"Workspace.Map.Middle",
		"Workspace.Map.Stands",
		"Workspace.NPCS",
		"Workspace.ExplorerStand",
		"Workspace.AuctionStand",
	},

	-- Khusus Gardens pakai ClearAllChildren()
	CLEAR_ALL_CHILDREN = {
		"Workspace.Gardens",
	},

	-- Disable collider (BasePart)
	DISABLE_COLLIDER = {
		"Workspace.WitchCauldron",
	},
}

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

local function log(msg)
	print(string.format("[%s] %s", os.date("%H:%M:%S"), msg))
end

-- ============================================================
-- CLEAR CHILDREN (pakai :Destroy())
-- ============================================================
local function deleteChildren(path)
	local target = resolvePath(path)
	if not target then
		log("✗ Tidak ditemukan: " .. path)
		return 0
	end

	local count = 0
	for _, child in ipairs(target:GetChildren()) do
		local ok = pcall(function() child:Destroy() end)
		if ok then count += 1 end
	end
	log(string.format("✓ %s → hapus %d anak", path, count))
	return count
end

-- ============================================================
-- CLEAR ALL CHILDREN (khusus Gardens)
-- ============================================================
local function clearAllChildren(path)
	local target = resolvePath(path)
	if not target then
		log("✗ Tidak ditemukan: " .. path)
		return
	end

	local before = #target:GetChildren()
	local ok, err = pcall(function()
		target:ClearAllChildren()
	end)
	if ok then
		log(string.format("✓ %s → ClearAllChildren (%d → 0)", path, before))
	else
		log("✗ Gagal ClearAllChildren " .. path .. ": " .. tostring(err))
	end
end

-- ============================================================
-- DISABLE COLLIDER
-- ============================================================
local function disableCollider(path)
	local target = resolvePath(path)
	if not target then
		log("✗ Tidak ditemukan: " .. path)
		return
	end

	local count = 0

	local function disablePart(part)
		if not part:IsA("BasePart") then return end
		part.CanCollide = false
		if part.CanTouch ~= nil then part.CanTouch = false end
		if part.CanQuery ~= nil then part.CanQuery = false end
		count += 1
	end

	-- Target sendiri kalau BasePart
	disablePart(target)

	-- Semua descendant BasePart
	for _, d in ipairs(target:GetDescendants()) do
		disablePart(d)
	end

	log(string.format("✓ %s → disable collider %d part", path, count))
end

-- ============================================================
-- MAIN
-- ============================================================
local function run()
	log("=====================================")
	log("Clear Map + Disable Collider START")
	log("=====================================")

	-- 1. Hapus anak biasa
	for _, path in ipairs(CONFIG.DELETE_CHILDREN) do
		deleteChildren(path)
	end

	-- 2. ClearAllChildren (khusus Gardens)
	for _, path in ipairs(CONFIG.CLEAR_ALL_CHILDREN) do
		clearAllChildren(path)
	end

	-- 3. Disable collider
	for _, path in ipairs(CONFIG.DISABLE_COLLIDER) do
		disableCollider(path)
	end

	log("=====================================")
	log("SELESAI")
	log("=====================================")
end

run()
