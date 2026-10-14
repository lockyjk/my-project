--!nocheck
-- Upload the Higgsfield UI art to Roblox and wire the ids into GameConfig.UIImages.
--
--   1. Unzip RollBrainrot_UI_Art.zip into RollBrainrot/assets/ui/  (coins.png, menu_Zoo.png, ...)
--   2. Create an Open Cloud API key (create.roblox.com → Open Cloud → API Keys) with the
--      "Assets" API, Read + Write, and your IP allowed.
--   3. ROBLOX_API_KEY=... ROBLOX_USER_ID=<your user id> lune run scripts/upload-ui-art
--      (or ROBLOX_GROUP_ID=<group id> instead of ROBLOX_USER_ID for a group game)
--
-- Keys that already have an id in GameConfig are skipped, so it is safe to re-run.

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")

local CONFIG = "src/shared/GameConfig.luau"
local DIR = "assets/ui"

local apiKey = process.env.ROBLOX_API_KEY
local userId = process.env.ROBLOX_USER_ID
local groupId = process.env.ROBLOX_GROUP_ID
if not apiKey or not (userId or groupId) then
	print("Set ROBLOX_API_KEY and ROBLOX_USER_ID (or ROBLOX_GROUP_ID). See the header of this script.")
	process.exit(1)
end
local creator = if groupId then { groupId = groupId } else { userId = userId }

local source = fs.readFile(CONFIG)
local block = source:match("GameConfig%.UIImages = (%b{})")
assert(block, "GameConfig.UIImages not found")

local function upload(key: string, bytes: string): string
	local boundary = "----RollBrainrot" .. tostring(math.random(1e9))
	local meta = serde.encode("json", {
		assetType = "Decal",
		displayName = "RB_" .. key,
		description = "Roll Brainrot UI art: " .. key,
		creationContext = { creator = creator },
	})
	local body = table.concat({
		`--{boundary}\r\nContent-Disposition: form-data; name="request"\r\n\r\n{meta}\r\n`,
		`--{boundary}\r\nContent-Disposition: form-data; name="fileContent"; filename="{key}.png"\r\n`,
		`Content-Type: image/png\r\n\r\n{bytes}\r\n--{boundary}--\r\n`,
	})
	local res = net.request({
		url = "https://apis.roblox.com/assets/v1/assets",
		method = "POST",
		headers = { ["x-api-key"] = apiKey, ["content-type"] = `multipart/form-data; boundary={boundary}` },
		body = body,
	})
	assert(res.ok, `{key}: upload failed {res.statusCode} {res.body}`)
	local op = serde.decode("json", res.body)
	local opId = op.operationId or (op.path and op.path:match("operations/(.+)"))
	for _ = 1, 30 do
		if op.done and op.response then
			return tostring(op.response.assetId)
		end
		task.wait(1)
		local poll = net.request({
			url = `https://apis.roblox.com/assets/v1/operations/{opId}`,
			headers = { ["x-api-key"] = apiKey },
		})
		assert(poll.ok, `{key}: poll failed {poll.statusCode} {poll.body}`)
		op = serde.decode("json", poll.body)
	end
	error(`{key}: timed out waiting for Roblox to process the upload`)
end

local done, skipped, missing = 0, 0, {}
for key, value in block:gmatch('([%w_]+) = "([^"]*)"') do
	local path = `{DIR}/{key}.png`
	if value ~= "" then
		skipped += 1
	elseif not fs.isFile(path) then
		table.insert(missing, path)
	else
		local id = upload(key, fs.readFile(path))
		source = source:gsub(`(\n%s*{key} = )""`, `%1"rbxassetid://{id}"`, 1)
		fs.writeFile(CONFIG, source) -- write as we go so a failure part-way keeps progress
		done += 1
		print(`✔ {key} → rbxassetid://{id}`)
	end
end

print(`\nuploaded {done}, already set {skipped}, missing {#missing}`)
for _, m in missing do
	print("  missing " .. m)
end
