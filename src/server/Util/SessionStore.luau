--!strict
-- Session-locked DataStore wrapper (written for this project, ProfileService-style).
--
-- Guarantees:
--   * Only one server owns a player's data at a time (lock = session id + heartbeat time).
--   * A save never overwrites data locked by another session; if our lock was stolen the
--     profile fires OnLockLost and stops saving (the caller kicks the player).
--   * Stale locks (crashed servers) are stolen after retries.
--   * Every DataStore call is retried with exponential backoff and respects request budgets.
--   * Falls back to an in-memory store in Studio when API access is disabled.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Signal = require(game:GetService("ReplicatedStorage").Shared.Signal)

local SessionStore = {}
SessionStore.__index = SessionStore

local LOCK_STALE_SECONDS = 240 -- a live session refreshes its lock at least every autosave (60s)
local LOAD_ATTEMPTS = 6 -- attempts before stealing a fresh-looking lock
local RETRY_BASE = 2

export type Record = {
	Data: any,
	Meta: { Lock: { Session: string, JobId: string, Time: number }?, SaveCount: number, Created: number },
}

export type Profile = {
	Key: string,
	Data: any,
	UserId: number,
	Released: boolean,
	LastSave: number,
	OnLockLost: Signal.Signal<>,
	Save: (Profile) -> boolean,
	Release: (Profile) -> boolean,
	_store: any,
	_saving: boolean,
}

-- Minimal store interface so tests / Studio can swap in a mock
export type Backend = {
	UpdateAsync: (self: any, key: string, transform: (any) -> ...any) -> any,
}

local MockBackend = {}
MockBackend.__index = MockBackend

function MockBackend.new(): Backend
	return (setmetatable({ _data = {} }, MockBackend) :: any) :: Backend
end

function MockBackend.UpdateAsync(self: any, key: string, transform: (any) -> ...any): any
	local current = self._data[key]
	local decoded = if current then HttpService:JSONDecode(current) else nil
	local result = transform(decoded)
	if result ~= nil then
		self._data[key] = HttpService:JSONEncode(result)
	end
	return result
end

local sessionId = HttpService:GenerateGUID(false)
local jobId = if game.JobId ~= "" then game.JobId else "Studio"

local function now(): number
	return DateTime.now().UnixTimestamp
end

local function waitForBudget()
	local deadline = os.clock() + 10
	while os.clock() < deadline do
		local ok, budget = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
		end)
		if not ok or budget > 0 then
			return
		end
		task.wait(0.5)
	end
end

-- Runs fn with retries. Returns (ok, result).
local function retry(label: string, attempts: number, fn: () -> any): (boolean, any)
	local lastErr
	for attempt = 1, attempts do
		waitForBudget()
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		warn(`[SessionStore] {label} failed (attempt {attempt}/{attempts}): {result}`)
		if attempt < attempts then
			task.wait(RETRY_BASE ^ attempt * 0.5)
		end
	end
	return false, lastErr
end

function SessionStore.new(name: string)
	local self = setmetatable({}, SessionStore)
	self.Name = name
	self.Mock = false
	self._backend = nil :: Backend?
	self._profiles = {} :: { [string]: Profile }

	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(name)
	end)
	if ok then
		self._backend = store :: any
		-- Probe once in Studio: if API access is off, use an in-memory store instead.
		if RunService:IsStudio() then
			local probeOk, err = pcall(function()
				(store :: any):GetAsync("__probe")
			end)
			if not probeOk then
				warn(`[SessionStore] Using in-memory data in Studio ({err})`)
				self._backend = MockBackend.new()
				self.Mock = true
			end
		end
	else
		warn(`[SessionStore] DataStore unavailable ({store}); using in-memory store`)
		self._backend = MockBackend.new()
		self.Mock = true
	end
	return self
end

function SessionStore.withBackend(name: string, backend: Backend)
	local self = setmetatable({}, SessionStore)
	self.Name = name
	self.Mock = true
	self._backend = backend
	self._profiles = {}
	return self
end

local ProfileMethods = {}

-- Loads and locks a profile. Returns nil if loading failed (caller should kick).
-- `prepare(data)` receives the raw saved data (or nil) and must return data to use; it is
-- where migrations and reconciliation run.
function SessionStore.Load(self: any, key: string, userId: number, prepare: (any) -> any): Profile?
	local backend = self._backend :: any
	local record: Record? = nil
	for attempt = 1, LOAD_ATTEMPTS do
		local blocked = false
		local steal = attempt == LOAD_ATTEMPTS
		local ok, result = retry(`Load {key}`, 3, function()
			return backend:UpdateAsync(key, function(old: Record?): ...any
				local rec: Record = old or { Data = nil, Meta = { SaveCount = 0, Created = now() } }
				rec.Meta = rec.Meta or { SaveCount = 0, Created = now() }
				local lock = rec.Meta.Lock
				if lock and lock.Session ~= sessionId and now() - lock.Time < LOCK_STALE_SECONDS and not steal then
					blocked = true
					return nil -- cancel the write; someone else holds the lock
				end
				if lock and lock.Session ~= sessionId then
					warn(`[SessionStore] Taking over lock for {key} from job {lock.JobId}`)
				end
				rec.Meta.Lock = { Session = sessionId, JobId = jobId, Time = now() }
				return rec, { userId }
			end)
		end)
		if not ok then
			return nil
		end
		if not blocked then
			record = result
			break
		end
		task.wait(5)
	end
	if not record then
		return nil
	end

	local okPrepare, data = pcall(prepare, record.Data)
	if not okPrepare then
		warn(`[SessionStore] prepare failed for {key}: {data}`)
		-- release the lock so the newer server (if any) keeps working
		retry(`Unlock {key}`, 2, function()
			return backend:UpdateAsync(key, function(old: Record?): ...any
				if old and old.Meta and old.Meta.Lock and old.Meta.Lock.Session == sessionId then
					old.Meta.Lock = nil
					return old, { userId }
				end
				return nil
			end)
		end)
		return nil
	end

	local profile = setmetatable({
		Key = key,
		Data = data,
		UserId = userId,
		Released = false,
		LastSave = os.clock(),
		OnLockLost = Signal.new(),
		_store = self,
		_saving = false,
	}, { __index = ProfileMethods }) :: any
	self._profiles[key] = profile
	return profile :: Profile
end

local function write(profile: any, release: boolean): boolean
	local store = profile._store
	local backend = store._backend
	local lost = false
	local ok = retry(`Save {profile.Key}`, 4, function()
		return backend:UpdateAsync(profile.Key, function(old: Record?): ...any
			local rec: Record = old or { Data = nil, Meta = { SaveCount = 0, Created = now() } }
			local lock = rec.Meta and rec.Meta.Lock
			if lock and lock.Session ~= sessionId then
				lost = true
				return nil
			end
			rec.Data = profile.Data
			rec.Meta.SaveCount = (rec.Meta.SaveCount or 0) + 1
			rec.Meta.Lock = if release then nil else { Session = sessionId, JobId = jobId, Time = now() }
			return rec, { profile.UserId }
		end)
	end)
	if lost then
		profile.Released = true
		store._profiles[profile.Key] = nil
		profile.OnLockLost:Fire()
		return false
	end
	if ok then
		profile.LastSave = os.clock()
	end
	return ok
end

-- Saves now. Returns true only if the data is durably written.
function ProfileMethods.Save(profile: any): boolean
	if profile.Released then
		return false
	end
	while profile._saving do
		task.wait()
	end
	profile._saving = true
	local ok = write(profile, false)
	profile._saving = false
	return ok
end

-- Final save + unlock. Safe to call twice.
function ProfileMethods.Release(profile: any): boolean
	if profile.Released then
		return true
	end
	while profile._saving do
		task.wait()
	end
	profile._saving = true
	profile.Released = true
	local ok = write(profile, true)
	profile._saving = false
	profile._store._profiles[profile.Key] = nil
	return ok
end

-- Periodic autosave of every live profile (staggered)
function SessionStore.StartAutoSave(self: any, interval: number)
	task.spawn(function()
		while true do
			task.wait(interval)
			local profiles = {}
			for _, p in self._profiles do
				table.insert(profiles, p)
			end
			for i, p in profiles do
				task.delay((i - 1) * (interval / math.max(1, #profiles)) * 0.5, function()
					if not p.Released then
						p:Save()
					end
				end)
			end
		end
	end)
end

-- Release every profile in parallel (BindToClose)
function SessionStore.ReleaseAll(self: any)
	for _, p in self._profiles do
		if not p.Released then
			task.spawn(function()
				p:Release()
			end)
		end
	end
	-- Release() removes each profile from _profiles once its final write finishes
	local deadline = os.clock() + 25
	while next(self._profiles) ~= nil and os.clock() < deadline do
		task.wait(0.1)
	end
end

SessionStore.MockBackend = MockBackend
SessionStore._sessionId = sessionId

return SessionStore
