--!strict
-- Client mirror of the player's replicated data (read-only; the server is authoritative).
-- Subscribe with ClientState.observe(key, fn) - fn runs now (if loaded) and on every change.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Signal = require(Shared:WaitForChild("Signal"))

local ClientState = {}

ClientState.data = {} :: { [string]: any }
ClientState.loaded = false
ClientState.Loaded = Signal.new() :: Signal.Signal<>
ClientState.Changed = Signal.new() :: Signal.Signal<string, any>

local keySignals: { [string]: Signal.Signal<any> } = {}

local function signalFor(key: string): Signal.Signal<any>
	local s = keySignals[key]
	if not s then
		s = Signal.new()
		keySignals[key] = s
	end
	return s
end

function ClientState.get(key: string): any
	return ClientState.data[key]
end

-- Runs fn(value) immediately if the key is present, and on every later change.
function ClientState.observe(key: string, fn: (any) -> ()): Signal.Connection
	if ClientState.data[key] ~= nil then
		task.spawn(fn, ClientState.data[key])
	end
	return signalFor(key):Connect(fn)
end

function ClientState.derived(): { [string]: any }
	return ClientState.data.Derived or {}
end

function ClientState.hasPass(key: string): boolean
	local passes = ClientState.data.Passes
	return passes ~= nil and passes[key] == true
end

function ClientState.waitLoaded()
	if not ClientState.loaded then
		ClientState.Loaded:Wait()
	end
end

function ClientState.start()
	Net.Client.on("State", function(changes: { [string]: any })
		for key, value in changes do
			ClientState.data[key] = value
		end
		for key, value in changes do
			signalFor(key):Fire(value)
			ClientState.Changed:Fire(key, value)
		end
		if changes.Loaded and not ClientState.loaded then
			ClientState.loaded = true
			ClientState.Loaded:Fire()
		end
	end)
end

return ClientState
