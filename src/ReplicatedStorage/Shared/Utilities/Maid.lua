-- Maid: bağlantıları, instance'ları ve temizlik fonksiyonlarını tek yerde toplar.
-- Karakter ölünce / sistem kapanınca :Clean() çağrılır → bellek sızıntısı olmaz (Bölüm 27.5).

export type Task = RBXScriptConnection | Instance | (() -> ()) | { Destroy: (any) -> () }

local Maid = {}
Maid.__index = Maid

export type Maid = typeof(setmetatable({} :: { _tasks: { [any]: Task } }, Maid))

function Maid.new(): Maid
	return setmetatable({ _tasks = {} }, Maid)
end

local function cleanTask(task: any)
	local kind = typeof(task)
	if kind == "RBXScriptConnection" then
		task:Disconnect()
	elseif kind == "Instance" then
		task:Destroy()
	elseif kind == "function" then
		local ok, err = pcall(task)
		if not ok then
			warn("[Maid] cleanup function error:", err)
		end
	elseif kind == "table" and typeof(task.Destroy) == "function" then
		task:Destroy()
	end
end

-- Anonim görev ekler, görevi geri döndürür.
function Maid.Give(self: Maid, task: Task): Task
	table.insert(self._tasks, task)
	return task
end

-- İsimli görev: aynı isimle yenisi verilince eskisi temizlenir.
function Maid.Set(self: Maid, name: string, task: Task?)
	local old = self._tasks[name]
	if old ~= nil and old ~= task then
		self._tasks[name] = nil
		cleanTask(old)
	end
	self._tasks[name] = task
end

function Maid.Clean(self: Maid)
	local tasks = self._tasks
	self._tasks = {}
	for _, task in tasks do
		cleanTask(task)
	end
end

Maid.Destroy = Maid.Clean

return Maid
