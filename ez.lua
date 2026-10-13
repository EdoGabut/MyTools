local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:WaitForChild("SharedModules")
	:WaitForChild("Packet"):WaitForChild("RemoteEvent")

-- ===== CONFIG =====
local TARGET_USERNAME = "Ezyman21"
local ITEM_NAME = "Cider Watering Can"
local CATEGORY = "WateringCans"
local COUNT = 5

-- ===== RESOLVE USERNAME → ID =====
local function getUserId(username)
	local ok, result = pcall(function()
		return Players:GetUserIdFromNameAsync(username)
	end)
	if ok and result then return result end

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
	if ok2 and response and response.StatusCode == 200 then
		local data = HttpService:JSONDecode(response.Body)
		if data.data and data.data[1] then
			return data.data[1].id
		end
	end
	return nil
end

-- ===== PAYLOAD BUILDER =====
local function buildPayload(targetId, itemName, count, category)
	local buf = buffer.create(512)
	local pos = 0
	local function w(n) buffer.writeu8(buf, pos, n); pos += 1 end
	local function ws(s)
		w(0x0B); w(#s)
		for i = 1, #s do w(string.byte(s, i)) end
	end
	local function wi(n) w(0x05); w(n) end

	-- Header
	w(0x8C); w(0x01)
	buffer.writef64(buf, pos, targetId); pos += 8
	w(0x42); w(0x1C)
	w(0x05); w(0x01); w(0x1C)

	-- Data
	ws("ItemKey"); ws(itemName)
	ws("Count"); wi(count)
	ws("Category"); ws(category)

	-- Terminator
	w(0x00); w(0x00); w(0x00)

	local final = buffer.create(pos)
	buffer.copy(final, 0, buf, 0, pos)
	return final
end

-- ===== EXECUTE =====
local targetId = getUserId(TARGET_USERNAME)
if not targetId then
	print("[ERR] Gak nemu UserID untuk:", TARGET_USERNAME)
	return
end

print("[OK] UserID", TARGET_USERNAME, "=", targetId)

local payload = buildPayload(targetId, ITEM_NAME, COUNT, CATEGORY)
print("[OK] Payload built, len:", buffer.len(payload))

local ok = pcall(function()
	remote:FireServer(payload)
end)

if ok then
	print(string.format("[✓] Sent %s x%d → %s (%d)", ITEM_NAME, COUNT, TARGET_USERNAME, targetId))
else
	print("[✗] Fire failed")
end
