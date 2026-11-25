-- TrafficSim: NPC araç simülasyonu (Aşama 6). SAF Lua; Roblox API'si yok (tools/test_ambient.py çalıştırır).
--
-- Her araç bir şeritte (lane) ya da kavşak bağlantısında (connector) "S" mesafesindedir. Her adımda:
--   1. Sürüş modeli (IDM): öndeki araç, durma çizgisi, engeller (oyuncu, oyuncu aracı, yaya) ve viraj hızı
--      kısıtlarından en sıkısı ivmeyi belirler → yumuşak hızlanma, güvenli duruş.
--   2. Kavşak izni: ışık (sunucu saatine bağlı), dur levhası (tam duruş + geliş sırası), yol ver (rampa).
--      İzin alan araç bağlantısını REZERVE eder; çakışan bağlantılar (kesişen ya da aynı şeride birleşen) boşalana
--      kadar kimse giremez. Çıkış şeridinde yer yoksa kavşağa girilmez ("kavşağı tıkama").
--   3. Engel arkasında kalırsa çok şeritli yolda yan şeride geçer; çok uzun süre tıkalı kalırsa (oyuncudan uzakta)
--      kaldırılır.
--   4. Oyuncunun çevresinde yoğunluğa göre GEÇERLİ bir şeritte doğar, uzaklaşınca kaldırılır (havuz istemcide).
--
-- ctx (Step): Time (sunucu zamanı), Focus = { {X,Z}... }, Obstacles = { {X,Y,Z,R,Kind}... }, MaxVehicles,
--             Density (0..1), CanSpawn(x,y,z,dist) -> bool (görünürlük), DensityAt(x,z) -> 0..1

local TrafficSim = {}
TrafficSim.__index = TrafficSim

local sqrt, abs, max, min, floor = math.sqrt, math.abs, math.max, math.min, math.floor

local function newRng(seed)
	local state = floor(seed) % 2147483646 + 1
	return function()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end

local function clamp(x, a, b)
	if x < a then
		return a
	elseif x > b then
		return b
	end
	return x
end

-- graph: TrafficGraph.Build sonucu; cfg: AmbientConfig.Traffic; kinds: { {Id, Length, Width, MaxSpeed, Weight} }
-- TG: TrafficGraph modülü (bağımlılık enjeksiyonu; saf Lua testinde require yok)
function TrafficSim.new(graph, cfg, kinds, TG, seed)
	local self = setmetatable({}, TrafficSim)
	self.Graph, self.Cfg, self.Kinds, self.TG = graph, cfg, kinds, TG
	self.Rng = newRng(seed or 12345)
	self.Vehicles = {}
	self.NextId = 1
	self.Time = 0
	self.ReservedNodes = {}
	self.Spawned, self.Despawned = {}, {}
	self.Stats = { Spawns = 0, Despawns = 0, Rejected = 0, LaneChanges = 0, Entries = 0, RedEntries = 0, Removed = 0 }
	local total = 0
	for _, k in ipairs(kinds) do
		total = total + (k.Weight or 1)
	end
	self.KindWeight = total
	return self
end

-- ===== Yardımcılar =====
local function segList(v)
	return v.Seg.Vehicles
end

local function insertSorted(list, v)
	local i = #list
	while i >= 1 and list[i].S > v.S do
		list[i + 1] = list[i]
		i = i - 1
	end
	list[i + 1] = v
end

local function removeFrom(list, v)
	for i = 1, #list do
		if list[i] == v then
			table.remove(list, i)
			return
		end
	end
end

function TrafficSim:_pickKind()
	local r = self.Rng() * self.KindWeight
	for _, k in ipairs(self.Kinds) do
		r = r - (k.Weight or 1)
		if r <= 0 then
			return k
		end
	end
	return self.Kinds[1]
end

local TURN_WEIGHT = { S = 0.5, R = 0.26, L = 0.22, U = 0.02 }
function TrafficSim:_pickNext(lane)
	local outs = lane.Out
	if #outs == 0 then
		return nil
	end
	local total = 0
	for _, c in ipairs(outs) do
		total = total + (TURN_WEIGHT[c.Turn] or 0.1)
	end
	local r = self.Rng() * total
	for _, c in ipairs(outs) do
		r = r - (TURN_WEIGHT[c.Turn] or 0.1)
		if r <= 0 then
			return c
		end
	end
	return outs[#outs]
end

-- d stud ilerideki yol noktası (x, z)
function TrafficSim:_pointAhead(v, d)
	local TG = self.TG
	local seg, s = v.Seg, v.S + d
	if v.OnConn then
		if s <= seg.Length then
			local x, _, z = TG.ConnPoint(seg, s)
			return x, z
		end
		local x, _, z = TG.LanePoint(seg.To, s - seg.Length)
		return x, z
	end
	if s <= seg.Length or not v.Next then
		local x, _, z = TG.LanePoint(seg, s)
		return x, z
	end
	s = s - seg.Length
	if s <= v.Next.Length then
		local x, _, z = TG.ConnPoint(v.Next, s)
		return x, z
	end
	local x, _, z = TG.LanePoint(v.Next.To, s - v.Next.Length)
	return x, z
end

-- IDM ivmesi. gap: önündeki engele net boşluk; vLead: onun hızı. gap nil → serbest yol
local function idm(cfg, v, v0, gap, vLead)
	local a, b = cfg.MaxAccel, cfg.ComfortDecel
	local free = 1 - (v / max(v0, 0.5)) ^ 4
	if not gap then
		return a * free
	end
	local sStar = cfg.MinGap + max(0, v * cfg.Headway + v * (v - vLead) / (2 * sqrt(a * b)))
	local g = max(gap, 0.05)
	return a * (free - (sStar / g) ^ 2)
end

-- ===== Kavşak izni =====
function TrafficSim:_targetHasRoom(v, conn)
	local to = conn.To
	local first = to.Vehicles[1]
	local room = first and (first.S - first.Len / 2) or to.Length
	local entering = 0
	for _, c in ipairs(to.In) do
		for _, w in ipairs(c.Vehicles) do
			room = room - (w.Len + self.Cfg.MinGap)
			entering = entering + 1
		end
	end
	if not first and entering == 0 then
		return true -- boş şerit: aracın boyundan kısa olsa bile girilebilir (kısa ara şeritler)
	end
	return room >= min(v.Len + self.Cfg.MinGap, to.Length * 0.8)
end

function TrafficSim:_conflictReserved(node, conn)
	local conflicts = self.TG.Conflicts(self.Graph, node)[conn]
	if not conflicts then
		return false
	end
	for other in pairs(conflicts) do
		if (node.Reserved[other] or 0) > 0 then
			return true
		end
	end
	return false
end

-- Önceliği olan (çakışan) bir araç kavşağa yaklaşıyor mu? (sol dönüş / rampa yol verir)
function TrafficSim:_priorityApproaching(node, conn, onlyStraight)
	local conflicts = self.TG.Conflicts(self.Graph, node)[conn]
	if not conflicts then
		return false
	end
	local look = self.Cfg.YieldLookAhead
	for other in pairs(conflicts) do
		if other.From.Group ~= conn.From.Group and (not onlyStraight or other.Turn ~= "L") then
			for _, w in ipairs(other.From.Vehicles) do
				if w.Next == other and (other.From.Length - w.S) < look and w.V > 1.5 then
					return true
				end
			end
		end
	end
	return false
end

function TrafficSim:_canEnter(v, node, conn, distToStop, time)
	local control = node.Control
	if control == "Free" and #conn.To.In <= 1 then
		return true
	end
	if not self:_targetHasRoom(v, conn) then
		return false, "Dolu"
	end
	if self:_conflictReserved(node, conn) then
		return false, "Çakışma"
	end
	if control == "Free" then
		return true -- şerit birleşmesi (şerit sayısı azalıyor): sadece rezervasyon + yer kontrolü
	end
	if control == "Signal" then
		local state = self.TG.SignalState(self.Graph, node, conn.Phase, time)
		if state == "R" then
			return false, "Kırmızı"
		elseif state == "Y" and distToStop > (v.V * v.V) / (2 * self.Cfg.ComfortDecel) then
			return false, "Sarı"
		end
		if (conn.Turn == "L" or conn.Turn == "U") and self:_priorityApproaching(node, conn, true) then
			return false, "SolDönüş"
		end
		return true
	elseif control == "Stop" then
		if (v.StopTimer or 0) < self.Cfg.StopSignWait then
			return false, "Dur"
		end
		-- geliş sırası: benden önce durmuş ve çakışan yöne gidecek biri varsa bekle
		local conflicts = self.TG.Conflicts(self.Graph, node)[conn] or {}
		for w, arrived in pairs(node.Waiting) do
			if w ~= v and w.Next and conflicts[w.Next] and arrived < (node.Waiting[v] or math.huge) then
				return false, "Sıra"
			end
		end
		return true
	end
	-- Yield: rampadan gelen ana yola yol verir
	if conn.From.Kind == "ramp" and self:_priorityApproaching(node, conn, false) then
		return false, "YolVer"
	end
	return true
end

function TrafficSim:_reserve(v, node, conn)
	node.Reserved[conn] = (node.Reserved[conn] or 0) + 1
	self.ReservedNodes[node] = true
	v.Reserve = conn
	v.ReserveNode = node
end

function TrafficSim:_release(v)
	local conn, node = v.Reserve, v.ReserveNode
	if conn and node then
		node.Reserved[conn] = max((node.Reserved[conn] or 1) - 1, 0)
	end
	v.Reserve, v.ReserveNode = nil, nil
end

-- ===== Doğurma / kaldırma =====
local function nearestFocus(foci, x, z)
	local best = math.huge
	for _, f in ipairs(foci) do
		local dx, dz = f.X - x, f.Z - z
		local d = dx * dx + dz * dz
		if d < best then
			best = d
		end
	end
	return sqrt(best)
end

function TrafficSim:_trySpawn(ctx)
	local cfg = self.Cfg
	local foci = ctx.Focus
	if #foci == 0 then
		return false
	end
	local focus = foci[1 + floor(self.Rng() * #foci) % #foci]
	local lanes = self.TG.LanesNear(self.Graph, focus.X, focus.Z, cfg.SpawnMax)
	if #lanes == 0 then
		return false
	end
	local lane = lanes[1 + floor(self.Rng() * #lanes) % #lanes]
	if lane.Length < 40 or #lane.Out == 0 then
		return false
	end
	local kind = self:_pickKind()
	local s = 12 + self.Rng() * (lane.Length - 24)
	local x, y, z = self.TG.LanePoint(lane, s)
	local d = nearestFocus(foci, x, z)
	if d < cfg.SpawnMin or d > cfg.SpawnMax then
		return false
	end
	if ctx.CanSpawn and not ctx.CanSpawn(x, y, z, d) then
		return false
	end
	if ctx.DensityAt and self.Rng() > max(ctx.DensityAt(x, z), cfg.DensityFloor) then
		return false
	end
	local b = cfg.ComfortDecel
	local spawnSpeed = min(lane.Speed, kind.MaxSpeed) * 0.6
	local function clear(ws, wv, wlen)
		local need = (wlen + kind.Length) / 2 + 14
		if ws < s then
			need = need + wv * wv / (2 * b) -- arkadan gelen durabilmeli
		else
			need = need + spawnSpeed * spawnSpeed / (2 * b)
		end
		return abs(ws - s) >= need
	end
	for _, w in ipairs(lane.Vehicles) do
		if not clear(w.S, w.V, w.Len) then
			return false
		end
	end
	for _, c in ipairs(lane.In) do
		for _, w in ipairs(c.Vehicles) do
			if not clear(-(c.Length - w.S), w.V, w.Len) then
				return false
			end
		end
		for _, w in ipairs(c.From.Vehicles) do
			if w.Next == c and not clear(-(c.Length + c.From.Length - w.S), w.V, w.Len) then
				return false
			end
		end
	end
	if s > lane.StopS - kind.Length then
		return false -- durma çizgisinin içinde doğma
	end
	for _, o in ipairs(ctx.Obstacles or {}) do
		local dx, dz = o.X - x, o.Z - z
		if dx * dx + dz * dz < 400 then
			return false
		end
	end
	local v = {
		Id = self.NextId, Kind = kind, Len = kind.Length, Width = kind.Width,
		Seg = lane, OnConn = false, S = s, V = 0, Factor = cfg.SpeedFactor[1] + self.Rng() * (cfg.SpeedFactor[2] - cfg.SpeedFactor[1]),
		Lat = 0, LatRate = 0, Blocked = 0, StopTimer = 0, State = "Sür", Brake = false,
		X = x, Y = y, Z = z, HX = lane.UX, HZ = lane.UZ,
	}
	v.V = spawnSpeed
	self.NextId = self.NextId + 1
	v.Next = self:_pickNext(lane)
	insertSorted(lane.Vehicles, v)
	self.Vehicles[#self.Vehicles + 1] = v
	self.Spawned[#self.Spawned + 1] = v
	self.Stats.Spawns = self.Stats.Spawns + 1
	return true
end

function TrafficSim:Remove(v, reason)
	if v.Removed then
		return
	end
	v.Removed = true
	v.RemoveReason = reason
	removeFrom(segList(v), v)
	self:_release(v)
	if v.WaitNode then
		v.WaitNode.Waiting[v] = nil
		v.WaitNode = nil
	end
	for i = #self.Vehicles, 1, -1 do
		if self.Vehicles[i] == v then
			table.remove(self.Vehicles, i)
			break
		end
	end
	self.Despawned[#self.Despawned + 1] = v
	self.Stats.Despawns = self.Stats.Despawns + 1
end

-- ===== Şerit değiştirme =====
function TrafficSim:_tryLaneChange(v, obstacles)
	if v.OnConn or v.Reserve then
		return false
	end
	local lane = v.Seg
	for _, delta in ipairs({ 1, -1 }) do
		local target = lane.Group[lane.Index + delta]
		if target then
			local ok = true
			for _, w in ipairs(target.Vehicles) do
				local need = (w.Len + v.Len) / 2 + 8
				if w.S < v.S then
					need = need + w.V * w.V / (2 * self.Cfg.ComfortDecel) -- arkadan gelen durabilmeli
				end
				if abs(w.S - v.S) < need then
					ok = false
					break
				end
			end
			-- hedef şeritte (benim yanımda ya da biraz önümde) engel var mı?
			if ok then
				for _, o in ipairs(obstacles or {}) do
					local ox, oz = o.X - target.X0, o.Z - target.Z0
					local along = ox * target.UX + oz * target.UZ
					local side = abs(ox * target.RX + oz * target.RZ)
					if side < v.Width / 2 + (o.R or 2) + 0.5 and along > v.S - v.Len and along < v.S + v.Len + (o.R or 2) + 25 then
						ok = false
						break
					end
				end
			end
			if ok and v.S < target.StopS - v.Len then
				removeFrom(lane.Vehicles, v)
				v.Seg = target
				insertSorted(target.Vehicles, v)
				v.Lat = v.Lat + (lane.Offset - target.Offset)
				v.LatRate = abs(v.Lat) / self.Cfg.LaneChangeTime
				v.Next = self:_pickNext(target)
				v.Blocked = 0
				if v.WaitNode then
					v.WaitNode.Waiting[v] = nil
					v.WaitNode = nil
				end
				self.Stats.LaneChanges = self.Stats.LaneChanges + 1
				return true
			end
		end
	end
	return false
end

-- ===== Ana adım =====
function TrafficSim:Step(dt, ctx)
	local cfg, TG, graph = self.Cfg, self.TG, self.Graph
	self.Time = self.Time + dt
	local time = ctx.Time or self.Time
	self.Spawned, self.Despawned = {}, {}
	local obstacles = ctx.Obstacles or {}
	local look = cfg.LookAhead

	-- 1. Kararlar (mevcut durumdan; sıra bağımsız)
	for _, v in ipairs(self.Vehicles) do
		local seg = v.Seg
		local list = seg.Vehicles
		local myIndex = 0
		for i = 1, #list do
			if list[i] == v then
				myIndex = i
				break
			end
		end
		-- istenen hız
		local v0
		local remaining = seg.Length - v.S
		if v.OnConn then
			v0 = seg.MaxSpeed
		else
			v0 = min(seg.Speed * v.Factor, v.Kind.MaxSpeed * 0.92)
			if v.Next then
				local vt = v.Next.MaxSpeed
				v0 = min(v0, sqrt(vt * vt + 2 * cfg.ComfortDecel * max(remaining - 4, 0)))
			end
		end
		local accel = idm(cfg, v.V, v0, nil, 0)
		local limitBy = nil

		-- öndeki araç
		local gap, vLead
		local leader = list[myIndex + 1]
		if leader then
			gap = leader.S - leader.Len / 2 - v.S - v.Len / 2
			vLead = leader.V
			limitBy = leader
		else
			local ahead = remaining
			local nextSeg = v.OnConn and seg.To or v.Next
			local hops = 0
			while nextSeg and ahead < look and hops < 2 do
				local first = nextSeg.Vehicles[1]
				if first then
					gap = ahead + first.S - first.Len / 2 - v.Len / 2
					vLead = first.V
					limitBy = first
					break
				end
				ahead = ahead + nextSeg.Length
				hops = hops + 1
				if nextSeg.To and not nextSeg.Edge then
					nextSeg = nextSeg.To -- connector → lane
				else
					nextSeg = nil
				end
			end
		end
		if gap and gap < look then
			accel = min(accel, idm(cfg, v.V, v0, gap, vLead))
		end
		-- Kavşak içinde (bağlantı üstünde) ya da kavşağa girerken: aynı düğümdeki diğer bağlantılarda önümde
		-- duran/yavaşlayan araç (aynı şeritten ayrılan ya da aynı şeride birleşen eğriler başta/sonda üst üste biner)
		local nodeId = v.OnConn and seg.Node or (v.Reserve and v.Next and v.Next.Node)
		if nodeId then
			local node = graph.Nodes[nodeId]
			for _, c in ipairs(node.Connectors) do
				if c ~= seg and #c.Vehicles > 0 then
					for _, w in ipairs(c.Vehicles) do
						if w ~= v then
							local dx, dz = w.X - v.X, w.Z - v.Z
							local ahead = dx * v.HX + dz * v.HZ
							local side = abs(-dx * v.HZ + dz * v.HX)
							local sameFlow = (w.HX * v.HX + w.HZ * v.HZ) > 0.3 -- karşıdan/çaprazdan geleni rezervasyon çözer
							if sameFlow and ahead > 0 and side < (v.Width + w.Width) / 2 + 0.6 then
								local g2 = ahead - (v.Len + w.Len) / 2
								local a2 = idm(cfg, v.V, v0, g2, w.V * max(w.HX * v.HX + w.HZ * v.HZ, 0))
								if a2 < accel then
									accel = a2
									limitBy = w
								end
							end
						end
					end
				end
			end
		end

		-- durma çizgisi / kavşak izni
		v.State = "Sür"
		if not v.OnConn then
			if not v.Next then
				local g = remaining - v.Len / 2 - 1
				accel = min(accel, idm(cfg, v.V, v0, g + cfg.MinGap, 0))
				v.State = "Yol sonu"
			elseif not v.Reserve then
				local node = graph.Nodes[seg.To]
				local distToStop = seg.StopS - v.S - v.Len / 2
				local approach = max(cfg.ApproachDistance, v.V * v.V / (2 * cfg.ComfortDecel) + 8)
				local isFirst = myIndex == #list
				-- serbest düğüm; ama iki şeridin tek şeride birleştiği yerde sıra/rezervasyon gerekir
				local free = node.Control == "Free" and #v.Next.To.In <= 1
				if free then
					if isFirst and distToStop < approach then
						self:_reserve(v, node, v.Next)
					end
				elseif distToStop < approach then
					-- dur levhası: tam duruş sayacı ve geliş sırası
					if node.Control == "Stop" and isFirst and distToStop < 3 and v.V < 0.6 then
						v.StopTimer = (v.StopTimer or 0) + dt
						if not node.Waiting[v] then
							node.Waiting[v] = time
							v.WaitNode = node
						end
					end
					local ok, why = false, "Sırada"
					if isFirst then
						ok, why = self:_canEnter(v, node, v.Next, distToStop, time)
					end
					if ok then
						if node.Control == "Signal" and TG.SignalState(graph, node, v.Next.Phase, time) == "R" then
							self.Stats.RedEntries = self.Stats.RedEntries + 1
						end
						self:_reserve(v, node, v.Next)
						if v.WaitNode then
							v.WaitNode.Waiting[v] = nil
							v.WaitNode = nil
						end
						v.StopTimer = 0
						self.Stats.Entries = self.Stats.Entries + 1
					else
						local g = distToStop + cfg.MinGap - 1
						accel = min(accel, idm(cfg, v.V, v0, g, 0))
						v.State = why or "Bekle"
						if not limitBy or g < (gap or math.huge) then
							limitBy = "stop"
						end
					end
				end
			end
		end

		-- engeller (oyuncular, oyuncu araçları, yayalar)
		local hx, hz = v.HX, v.HZ
		-- yanal eşik: araçlar için gövde yarı genişliği (yol kenarına park etmiş araç şeridi kapatmaz);
		-- insanlar için şerit yarı genişliği (şeride yaklaşan yayayı önceden fark et, öngörülü fren)
		local halfBody = v.Width / 2 + 0.5
		local halfLane = max((v.OnConn and seg.From.LaneWidth or seg.LaneWidth) / 2, halfBody)
		for _, o in ipairs(obstacles) do
			local dx, dz = o.X - v.X, o.Z - v.Z
			local d2 = dx * dx + dz * dz
			if d2 < look * look and abs((o.Y or v.Y) - v.Y) < 7 and dx * hx + dz * hz > -v.Len / 2 then
				local straight = sqrt(d2)
				local best, bestAlong = math.huge, 0
				local step = 3
				local along = 0
				while along <= straight + 6 do
					local px, pz = self:_pointAhead(v, along)
					local ex, ez = o.X - px, o.Z - pz
					local e2 = ex * ex + ez * ez
					if e2 < best then
						best, bestAlong = e2, along
					end
					along = along + step
				end
				local lateralLimit = ((o.Kind == "Vehicle") and halfBody or halfLane) + (o.R or 2)
				if sqrt(best) < lateralLimit then
					local og = bestAlong - v.Len / 2 - (o.R or 2)
					local a2 = idm(cfg, v.V, v0, og, 0)
					if a2 < accel then
						accel = a2
						limitBy = "obstacle"
					end
					v.State = "Engel"
				end
			end
		end

		v.Accel = clamp(accel, -cfg.MaxDecel, cfg.MaxAccel)
		v.LimitBy = limitBy
	end

	-- 2. Entegrasyon ve geçişler
	for i = #self.Vehicles, 1, -1 do
		local v = self.Vehicles[i]
		if v then
			local oldV = v.V
			local newV = max(0, v.V + v.Accel * dt)
			local ds = (oldV + newV) / 2 * dt
			v.V = newV
			v.Brake = v.Accel < -2 or (newV < 0.5 and v.State ~= "Sür")
			if not v.OnConn and v.Next and not v.Reserve then
				-- izinsiz durma çizgisini geçme
				ds = min(ds, max(v.Seg.StopS - v.Len / 2 - v.S, 0) + 0.01)
			end
			v.S = v.S + ds
			-- tıkanma takibi (ışık/sırada beklemek tıkanma sayılmaz)
			if newV < 0.3 and (v.LimitBy == "obstacle" or (type(v.LimitBy) == "table" and (v.LimitBy.Blocked or 0) > 2)) then
				v.Blocked = v.Blocked + dt
			elseif newV > 1 then
				v.Blocked = 0
			end
			-- şerit sonu → bağlantı → yeni şerit
			if not v.OnConn and v.S >= v.Seg.Length then
				if v.Next and v.Reserve then
					local over = v.S - v.Seg.Length
					removeFrom(v.Seg.Vehicles, v)
					v.Seg, v.OnConn, v.S = v.Next, true, over
					insertSorted(v.Seg.Vehicles, v)
				else
					v.S = v.Seg.Length - 0.01
					v.V = 0
				end
			end
			if v.OnConn and v.S >= v.Seg.Length then
				local over = v.S - v.Seg.Length
				local lane = v.Seg.To
				removeFrom(v.Seg.Vehicles, v)
				self:_release(v)
				v.Seg, v.OnConn, v.S = lane, false, over
				insertSorted(lane.Vehicles, v)
				v.Next = self:_pickNext(lane)
			end
			-- yanal şerit değiştirme geçişi
			if v.Lat ~= 0 then
				local stepLat = v.LatRate * dt
				if abs(v.Lat) <= stepLat then
					v.Lat = 0
				else
					v.Lat = v.Lat - stepLat * (v.Lat > 0 and 1 or -1)
				end
			end
		end
	end

	-- 3. Tıkanma: yan şerit, sonra kaldırma
	for i = #self.Vehicles, 1, -1 do
		local v = self.Vehicles[i]
		if v.Blocked > cfg.LaneChangeAfter and not v.OnConn then
			self:_tryLaneChange(v, obstacles)
		end
	end

	-- 4. Konum ve yön
	for _, v in ipairs(self.Vehicles) do
		local x, y, z, hx, hz
		if v.OnConn then
			x, y, z, hx, hz = TG.ConnPoint(v.Seg, v.S)
		else
			x, y, z, hx, hz = TG.LanePoint(v.Seg, v.S)
			if v.Lat ~= 0 then
				x, z = x + v.Seg.RX * v.Lat, z + v.Seg.RZ * v.Lat
			end
		end
		v.X, v.Y, v.Z, v.HX, v.HZ = x, y, z, hx, hz
		-- eğim (rampa/köprü): görüntüde aracın burnu yolla birlikte kalksın
		local seg = v.Seg
		if v.OnConn then
			v.Slope = (seg.PY[#seg.PY] - seg.PY[1]) / max(seg.Length, 0.5)
		else
			v.Slope = (seg.Y1 - seg.Y0) / max(seg.Length, 0.5)
		end
	end

	-- 5. Kaldırma (uzak / uzun süre tıkalı) ve doğurma
	local foci = ctx.Focus or {}
	for i = #self.Vehicles, 1, -1 do
		local v = self.Vehicles[i]
		local d = nearestFocus(foci, v.X, v.Z)
		if #foci > 0 and d > cfg.DespawnRadius then
			self:Remove(v, "Uzak")
		elseif v.Blocked > cfg.BlockedDespawnAfter and d > 60 then
			self:Remove(v, "Tıkalı")
		end
	end
	local target = floor((ctx.MaxVehicles or 0) * clamp(ctx.Density or 1, 0, 1) + 0.5)
	local tries = 0
	local spawned = 0
	while #self.Vehicles < target and spawned < cfg.SpawnsPerTick and tries < 8 do
		tries = tries + 1
		if self:_trySpawn(ctx) then
			spawned = spawned + 1
		else
			self.Stats.Rejected = self.Stats.Rejected + 1
		end
	end
	-- fazlalık (ör. sınır düşürüldü): en uzaktakini kaldır
	while #self.Vehicles > target + 2 do
		local far, farD = nil, -1
		for _, v in ipairs(self.Vehicles) do
			local d = nearestFocus(foci, v.X, v.Z)
			if d > farD then
				far, farD = v, d
			end
		end
		self:Remove(far, "Sınır")
	end
end

-- ===== Yaya sistemi için sorgular =====
-- Kolda (edgeId) düğüme yakın araç var mı? (ışıksız geçitte karşıya geçme kararı)
function TrafficSim:ArmBusy(node, edgeId, radius)
	for _, v in ipairs(self.Vehicles) do
		local seg = v.Seg
		if v.OnConn then
			if seg.Node == node.Id and (seg.From.Edge == edgeId or seg.To.Edge == edgeId) then
				return true
			end
		elseif seg.Edge == edgeId then
			if seg.To == node.Id and (seg.Length - v.S) < radius and v.V > 0.5 then
				return true
			elseif seg.To == node.Id and (seg.Length - v.S) < 12 then
				return true -- çizgide bekleyen de geçidin önünde
			elseif seg.From == node.Id and v.S < 10 then
				return true
			end
		end
	end
	return false
end

-- Hata ayıklama: düğüm rezervasyonlarını araçlardan yeniden kur (sızıntı denetimi)
function TrafficSim:CheckReservations()
	local actual = {}
	for _, v in ipairs(self.Vehicles) do
		if v.Reserve then
			actual[v.Reserve] = (actual[v.Reserve] or 0) + 1
		end
	end
	local leaks = 0
	for node in pairs(self.ReservedNodes) do
		for conn, n in pairs(node.Reserved) do
			if (actual[conn] or 0) ~= n then
				leaks = leaks + 1
				node.Reserved[conn] = actual[conn] or 0
			end
		end
	end
	return leaks
end

return TrafficSim
