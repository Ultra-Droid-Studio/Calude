-- Signal: modüller arası hafif olay sistemi (BindableEvent'e gerek kalmadan).
-- Her dinleyici kendi thread'inde çalışır; biri hata verirse diğerleri etkilenmez.

local Signal = {}
Signal.__index = Signal

export type Connection = { Connected: boolean, Disconnect: (Connection) -> () }
export type Signal = typeof(setmetatable({} :: { _handlers: { [number]: any } }, Signal))

function Signal.new(): Signal
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal.Connect(self: Signal, fn: (...any) -> ()): Connection
	local handler = { fn = fn, Connected = true }
	table.insert(self._handlers, handler)
	local handlers = self._handlers
	local connection = {} :: any
	connection.Connected = true
	function connection.Disconnect(conn: Connection)
		if not conn.Connected then
			return
		end
		conn.Connected = false
		handler.Connected = false
		local index = table.find(handlers, handler)
		if index then
			table.remove(handlers, index)
		end
	end
	return connection
end

function Signal.Once(self: Signal, fn: (...any) -> ()): Connection
	local connection: Connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal.Fire(self: Signal, ...: any)
	-- Kopya üzerinden dön: dinleyici çalışırken bağlantı kopsa da döngü bozulmaz.
	for _, handler in table.clone(self._handlers) do
		if handler.Connected then
			task.spawn(handler.fn, ...)
		end
	end
end

function Signal.Wait(self: Signal): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal.DisconnectAll(self: Signal)
	for _, handler in self._handlers do
		handler.Connected = false
	end
	table.clear(self._handlers)
end

Signal.Destroy = Signal.DisconnectAll

return Signal
