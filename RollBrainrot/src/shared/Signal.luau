--!strict
-- Minimal typed signal (no BindableEvent, so handlers receive tables by reference).

export type Connection = { Disconnect: (Connection) -> (), Connected: boolean }
export type Signal<T...> = {
	Connect: (Signal<T...>, (T...) -> ()) -> Connection,
	Once: (Signal<T...>, (T...) -> ()) -> Connection,
	Fire: (Signal<T...>, T...) -> (),
	Wait: (Signal<T...>) -> T...,
	DisconnectAll: (Signal<T...>) -> (),
	_handlers: { any },
}

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	return (setmetatable({ _handlers = {} }, Signal) :: any) :: Signal<T...>
end

function Signal.Connect(self: any, fn: (...any) -> ()): Connection
	local conn: any = { Connected = true, _fn = fn }
	function conn.Disconnect(c: any)
		if not c.Connected then
			return
		end
		c.Connected = false
		local i = table.find(self._handlers, c)
		if i then
			table.remove(self._handlers, i)
		end
	end
	table.insert(self._handlers, conn)
	return conn
end

function Signal.Once(self: any, fn: (...any) -> ()): Connection
	local conn: Connection
	conn = Signal.Connect(self, function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal.Fire(self: any, ...: any)
	for _, conn: any in table.clone(self._handlers) do
		if conn.Connected then
			local fn = conn._fn
			task.spawn(fn, ...)
		end
	end
end

function Signal.Wait(self: any): ...any
	local thread = coroutine.running()
	Signal.Once(self, function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal.DisconnectAll(self: any)
	for _, conn: any in self._handlers do
		conn.Connected = false
	end
	table.clear(self._handlers)
end

return Signal
