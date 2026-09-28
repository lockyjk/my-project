--[[
	⛏  DIG DEEP SYNC  ·  Roblox Studio plugin

	Keeps your Dig Deep game up to date without new files. Whenever you open a place that
	has DigDeepServer in it (and whenever you click "Update Dig Deep" on the Plugins tab),
	it downloads the newest DigDeepServer and DigDeepClient scripts from GitHub and puts
	them into the game you have open. Then just press Play.

	Install once: Studio > Plugins tab > "Plugins Folder", put this file in that folder,
	then restart Studio. Allow the two permissions Studio asks for (web requests to
	raw.githubusercontent.com, and changing scripts).
]]

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

-- Plugins also run inside play-test sessions; only touch the game while editing.
if not RunService:IsEdit() then
	return
end

local BASE = "https://raw.githubusercontent.com/lockyjk/my-project/refs/heads/claude/awesome-meitner-7chhsq/dig-deep/"

local function fetch(file)
	-- the time in the URL skips GitHub's cache, so you always get the newest version
	local ok, body = pcall(function()
		return HttpService:GetAsync(BASE .. file .. "?t=" .. os.time(), true)
	end)
	if not ok then
		return nil, tostring(body)
	end
	-- make sure it is really the script, not an error page
	if not string.find(body, "DIG DEEP", 1, true) then
		return nil, "unexpected content"
	end
	return body
end

local function put(parent, className, name, source)
	local script = parent:FindFirstChild(name)
	if script and not script:IsA(className) then
		script:Destroy()
		script = nil
	end
	if not script then
		script = Instance.new(className)
		script.Name = name
		script.Parent = parent
	end
	if script.Source ~= source then
		script.Source = source
		return true
	end
	return false
end

local busy = false
local function update(manual)
	if busy then
		return
	end
	busy = true
	local server, serverErr = fetch("DigDeepServer.server.luau")
	local client, clientErr = fetch("DigDeepClient.client.luau")
	if not server or not client then
		warn("[Dig Deep Sync] Couldn't download the newest scripts: " .. tostring(serverErr or clientErr) .. ". Check your internet, and that Studio is allowed to reach raw.githubusercontent.com.")
		busy = false
		return
	end
	-- every place has StarterPlayerScripts (it can't be created from code)
	local starterScripts = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts", 5)
	if not starterScripts then
		warn("[Dig Deep Sync] This place has no StarterPlayer > StarterPlayerScripts.")
		busy = false
		return
	end
	local okRec, recording = pcall(function()
		return ChangeHistoryService:TryBeginRecording("Update Dig Deep")
	end)
	recording = if okRec then recording else nil
	local changed = put(game:GetService("ServerScriptService"), "Script", "DigDeepServer", server)
	changed = put(starterScripts, "LocalScript", "DigDeepClient", client) or changed
	-- the world settings the game needs
	workspace.FallenPartsDestroyHeight = -4000
	pcall(function()
		workspace.StreamingEnabled = false
	end)
	if recording then
		pcall(function()
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
		end)
	end
	if changed then
		print("✅ [Dig Deep Sync] Updated to the newest Dig Deep. Press Play!")
	elseif manual then
		print("✅ [Dig Deep Sync] You already have the newest Dig Deep.")
	end
	busy = false
end

local toolbar = plugin:CreateToolbar("Dig Deep")
local button = toolbar:CreateButton("Update Dig Deep", "Download the newest Dig Deep scripts into this game", "rbxasset://textures/ui/GuiImagePlaceholder.png")
button.ClickableWhenViewportHidden = true
button.Click:Connect(function()
	update(true)
end)

-- Update automatically when a Dig Deep game is opened
task.defer(function()
	if game:GetService("ServerScriptService"):FindFirstChild("DigDeepServer") then
		update(false)
	end
end)
