-- PedSim: yaya simülasyonu (Aşama 6). SAF Lua; Roblox API'si yok (tools/test_ambient.py çalıştırır).
--
-- Yaya yalnızca PedGraph üzerinde yürür (kaldırım + kavşaktaki geçitler). Davranış:
--   * Hedef: saate göre (Schedule) bir mola noktası (dükkân, bank, durak) ya da rastgele bir kaldırım düğümü;
--     A* ile yol bulur. Hedefe varınca saate bağlı olasılıkla mola verir (durur, noktaya döner).
--   * Karşıya geçiş: ışıklı kavşakta YAYA YEŞİLİ (kolun trafiği kırmızı, diğer faz yeşil ve süre yetiyor);
--     ışıksızda kolda yaklaşan araç yokken. Uzun beklerse başka yöne döner.
--   * Çarpışmadan kaçınma: aynı kaldırımda karşılaşınca sağa kayma, önündekine yetişince yavaşlama, oyuncuya yol
--     verme; kaldırım kenarına hızla yaklaşan araçtan uzaklaşma.
--
-- ctx (Step): Time, Hour (0..24), Focus, Obstacles { {X,Z,R,Kind,Speed} } (oyuncu/araç), MaxPeds, Density,
--             CanSpawn(x,y,z,dist), DensityAt(x,z), IsVisible(x,y,z,dist)
--
-- Bina kapıları (graph.Entrances, Entrances modülü): saate göre bazı yayaların hedefi bir kapıdır (ev/iş/dükkân/otel).
-- Kapıya varınca: Kapı (kapıya dön, kısa bekle, kapı açılır) → Gir (eşikten geçer, içeride kaybolur, kaldırılır).
-- Bazı yayalar kapıdan çıkarak doğar: Çık (kapı açılır, içeriden belirir, dışarı yürür) → normal yürüyüş.
--
-- Yaşayan Şehir: yön değişimi dönüş hızıyla sınırlı (köşede ani dönme yok), yürüme hızı ivmeli (kalkış/duruş
-- yumuşak; gerçek hız animasyona gider → ayak kayması yok), görünen yaya kaldırılmaz, uzaktakiler sade güncellenir,
-- hedefler daha uzak ve anlamlı (gereksiz karşıya geçmeye ceza), yaya ışığında geç kalan da güvenle geçebilir.

local PedSim = {}
PedSim.__index = PedSim

local sqrt, abs, max, min, floor = math.sqrt, math.abs, math.max, math.min, math.floor
local atan2 = math.atan2 or math.atan -- Luau: atan2; Lua 5.4 (çevrimdışı test): atan(y, x)

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

-- graph: PedGraph; tg: TrafficGraph; traffic: TrafficSim (ArmBusy, araç konumları); cfg: AmbientConfig.Pedestrians
function PedSim.new(graph, tg, traffic, cfg, PG, TG, seed)
	local self = setmetatable({}, PedSim)
	self.Graph, self.TGraph, self.Traffic, self.Cfg, self.PG, self.TG = graph, tg, traffic, cfg, PG, TG
	self.Rng = newRng(seed or 777)
	self.Peds = {}
	self.NextId = 1
	self.Spawned, self.Despawned = {}, {}
	self.Stats = {
		Spawns = 0, Despawns = 0, Rejected = 0, Crossings = 0, CrossOnRed = 0, GaveUp = 0, PathFail = 0,
		Entered = 0, Exited = 0, DoorGoals = 0,
	}
	self.Doors = graph.Entrances -- Entrances.Build sonucu (yoksa kapı davranışı yok)
	self.Time = 0
	graph.CrossPenalty = cfg.CrossPenalty or graph.CrossPenalty -- A*: gereksiz karşıya geçme cezası
	return self
end

function PedSim:_schedule(hour)
	for _, s in ipairs(self.Cfg.Schedule) do
		if hour >= s.From and hour < s.To then
			return s
		end
	end
	return self.Cfg.Schedule[1]
end

local function nearestFocus(foci, x, z)
	local best = math.huge
	for _, f in ipairs(foci) do
		local d = (f.X - x) ^ 2 + (f.Z - z) ^ 2
		if d < best then
			best = d
		end
	end
	return sqrt(best)
end

-- ===== Bina kapıları =====
function PedSim:_doorSchedule(hour)
	local dc = self.Cfg.Doors
	if not dc or not dc.Enabled or not self.Doors then
		return nil
	end
	for _, s in ipairs(dc.Schedule) do
		if hour >= s.From and hour < s.To then
			return s
		end
	end
	return dc.Schedule[1]
end

-- yarıçap içindeki kapılardan kullanım ağırlığına göre rastgele biri (filter: ek koşul)
function PedSim:_pickDoor(x, z, radius, weights, filter)
	local reg = self.Doors
	local cands, total = {}, 0
	local r2 = radius * radius
	for i = floor((x - radius) / 96), floor((x + radius) / 96) do
		for j = floor((z - radius) / 96), floor((z + radius) / 96) do
			for _, e in ipairs(reg.Grid[i .. ":" .. j] or {}) do
				local d2 = (e.X - x) ^ 2 + (e.Z - z) ^ 2
				local w = weights[e.Use] or 0
				if d2 < r2 and w > 0 and (not filter or filter(e, d2)) then
					total = total + w
					cands[#cands + 1] = { e, total }
				end
			end
		end
	end
	if total <= 0 then
		return nil
	end
	local r = self.Rng() * total
	for _, c in ipairs(cands) do
		if r <= c[2] then
			return c[1]
		end
	end
	return cands[#cands][1]
end

-- Kapı kullanımda mı (biri giriyor/çıkıyor)? → kapı açık kalır, sıradaki bekler
function PedSim:_doorBusy(e)
	return (e.BusyUntil or 0) > self.Time
end

-- Kapıdan çıkarak doğ (görünür yerde de olabilir: insan binadan çıkıyor)
function PedSim:_trySpawnDoor(ctx, sched)
	local cfg = self.Cfg
	local foci = ctx.Focus or {}
	if #foci == 0 then
		return false
	end
	local focus = foci[1 + floor(self.Rng() * #foci) % #foci]
	local minD2 = (cfg.Doors.SpawnMinDistance or 15) ^ 2
	local e = self:_pickDoor(focus.X, focus.Z, cfg.SpawnMax, sched.Exit, function(door, d2)
		return d2 > minD2 and not self:_doorBusy(door) and (self.Graph.ComponentSizes[door.Walk.Comp] or 0) >= 6
	end)
	if not e then
		return false
	end
	if ctx.DensityAt and self.Rng() > max(ctx.DensityAt(e.X, e.Z), cfg.DensityFloor) then
		return false
	end
	for _, q in ipairs(self.Peds) do
		if (q.X - e.OutX) ^ 2 + (q.Z - e.OutZ) ^ 2 < 9 then
			return false
		end
	end
	local depth = cfg.Doors.Depth or 1.8
	local p = {
		Id = self.NextId, Node = e.Node, X = e.X - e.NX * depth, Y = e.Y, Z = e.Z - e.NZ * depth, HX = e.NX, HZ = e.NZ,
		WX = e.NX, WZ = e.NZ, Speed = cfg.WalkSpeed[1] + self.Rng() * (cfg.WalkSpeed[2] - cfg.WalkSpeed[1]),
		Lateral = (self.Rng() * 2 - 1) * cfg.SidewalkSpread * 0.7, LatCur = 0, State = "Çık", Timer = 0, Moving = 0,
		Seed = self.Rng(), CurSpeed = 0, Door = e, Fade = 1, DX = e.NX, DZ = e.NZ,
	}
	self.NextId = self.NextId + 1
	e.BusyUntil = self.Time + (cfg.Doors.ExitTime or 1.1) + 0.4
	self.Peds[#self.Peds + 1] = p
	self.Spawned[#self.Spawned + 1] = p
	self.Stats.Spawns = self.Stats.Spawns + 1
	self.Stats.Exited = self.Stats.Exited + 1
	return true
end

-- Yeni hedef seç ve yol bul
function PedSim:_newGoal(p, ctx)
	local graph = self.Graph
	local sched = self:_schedule(ctx.Hour or 12)
	local goal
	local ds = self:_doorSchedule(ctx.Hour or 12)
	if ds and self.Rng() < ds.Goal then
		-- bir binaya git (eve dön, işe/dükkâna gir): aynı kaldırım ağında, birkaç adım ötede
		local minD2 = (self.Cfg.Doors.GoalMinDistance or 30) ^ 2
		local comp = p.Node.Comp
		local e = self:_pickDoor(p.X, p.Z, self.Cfg.GoalRadius, ds.Enter, function(door, d2)
			return d2 > minD2 and door.Node.Comp == comp
		end)
		if e then
			goal = e.Node
			self.Stats.DoorGoals = self.Stats.DoorGoals + 1
		end
	end
	if not goal and #graph.Spots > 0 and self.Rng() < sched.Idle + 0.2 then
		-- yakın bir mola noktası
		for _ = 1, 6 do
			local s = graph.Spots[1 + floor(self.Rng() * #graph.Spots) % #graph.Spots]
			if s.Comp == p.Node.Comp and (s.X - p.X) ^ 2 + (s.Z - p.Z) ^ 2 < self.Cfg.GoalRadius ^ 2 and s ~= p.Node then
				goal = s
				break
			end
		end
	end
	if not goal then
		-- rastgele ama anlamlı uzaklıkta bir kaldırım noktası (çok yakın hedef = olduğu yerde dönüp durma)
		local links = self.PG.LinksNear(graph, p.X, p.Z, self.Cfg.GoalRadius)
		local minD2 = (self.Cfg.GoalMinDistance or 0) ^ 2
		local fallback
		for _ = 1, 8 do
			local l = links[1 + floor(self.Rng() * max(#links, 1)) % max(#links, 1)]
			if l then
				local n = (self.Rng() < 0.5) and l.A or l.B
				if n.Comp == p.Node.Comp and n ~= p.Node then
					if (n.X - p.X) ^ 2 + (n.Z - p.Z) ^ 2 >= minD2 then
						goal = n
						break
					end
					fallback = fallback or n
				end
			end
		end
		goal = goal or fallback
	end
	if not goal then
		return false
	end
	local path = self.PG.Path(graph, p.Node, goal, 700)
	if not path or #path == 0 then
		self.Stats.PathFail = self.Stats.PathFail + 1
		return false
	end
	p.Path, p.PathIndex, p.Goal = path, 1, goal
	return true
end

function PedSim:_startLink(p, link, toNode)
	p.Link = link
	p.From = p.Node
	p.To = toNode
	p.T = 0
	local dx, dz = toNode.X - p.From.X, toNode.Z - p.From.Z
	local l = max(sqrt(dx * dx + dz * dz), 0.01)
	p.DX, p.DZ = dx / l, dz / l
end

function PedSim:_trySpawn(ctx)
	local cfg = self.Cfg
	local foci = ctx.Focus or {}
	if #foci == 0 then
		return false
	end
	local focus = foci[1 + floor(self.Rng() * #foci) % #foci]
	local links = self.PG.LinksNear(self.Graph, focus.X, focus.Z, cfg.SpawnMax)
	if #links == 0 then
		return false
	end
	local link = links[1 + floor(self.Rng() * #links) % #links]
	local t = self.Rng()
	local x = link.A.X + (link.B.X - link.A.X) * t
	local z = link.A.Z + (link.B.Z - link.A.Z) * t
	local d = nearestFocus(foci, x, z)
	if d < cfg.SpawnMin or d > cfg.SpawnMax then
		return false
	end
	if ctx.CanSpawn and not ctx.CanSpawn(x, self.Graph.Top, z, d) then
		return false
	end
	if ctx.DensityAt and self.Rng() > max(ctx.DensityAt(x, z), cfg.DensityFloor) then
		return false
	end
	for _, q in ipairs(self.Peds) do
		if (q.X - x) ^ 2 + (q.Z - z) ^ 2 < 9 then
			return false
		end
	end
	local dirForward = self.Rng() < 0.5
	local from, to = link.A, link.B
	if not dirForward then
		from, to = link.B, link.A
	end
	local p = {
		Id = self.NextId, Node = from, X = x, Y = self.Graph.Top, Z = z, HX = 0, HZ = 1,
		Speed = cfg.WalkSpeed[1] + self.Rng() * (cfg.WalkSpeed[2] - cfg.WalkSpeed[1]),
		Lateral = (self.Rng() * 2 - 1) * cfg.SidewalkSpread * 0.7, LatCur = 0, State = "Yürü", Timer = 0, Moving = 0,
		Seed = self.Rng(), CurSpeed = 0,
	}
	p.LatCur = p.Lateral
	self.NextId = self.NextId + 1
	self:_startLink(p, link, to)
	p.T = link.Length * (dirForward and t or (1 - t))
	p.HX, p.HZ = p.DX, p.DZ
	p.CurSpeed = p.Speed -- görünmeyen yerde, yürürken doğar
	self.Peds[#self.Peds + 1] = p
	self.Spawned[#self.Spawned + 1] = p
	self.Stats.Spawns = self.Stats.Spawns + 1
	return true
end

-- Kazadan sonra ayağa kalkan yayayı yeniden yürüt (aynı görünüm: seed, hız). (x, z) noktasına en yakın kaldırım
-- bağlantısına (karşıya geçiş değil, ≤ maxDist) konur, (hx, hz) yönüne en yakın uçtan devam eder. Bulunamazsa nil.
-- Spawned listesine girmez: görseli çağıran verir (aynı model).
function PedSim:Rejoin(x, z, hx, hz, seed, speed, maxDist)
	maxDist = maxDist or 18
	local best, bestT, bestD = nil, 0, maxDist * maxDist
	for _, link in ipairs(self.PG.LinksNear(self.Graph, x, z, maxDist)) do
		if not link.Crossing and not link.Door and link.Length > 0.5 then
			local ax, az = link.A.X, link.A.Z
			local dx, dz = link.B.X - ax, link.B.Z - az
			local t = clamp(((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz), 0, 1)
			local qx, qz = ax + dx * t, az + dz * t
			local d2 = (qx - x) ^ 2 + (qz - z) ^ 2
			if d2 < bestD then
				best, bestT, bestD = link, t, d2
			end
		end
	end
	if not best then
		return nil
	end
	local dx, dz = best.B.X - best.A.X, best.B.Z - best.A.Z
	local forward = dx * (hx or 0) + dz * (hz or 0) >= 0
	local from, to = best.A, best.B
	if not forward then
		from, to = best.B, best.A
	end
	local cfg = self.Cfg
	local p = {
		Id = self.NextId, Node = from, X = x, Y = self.Graph.Top, Z = z, HX = hx or 0, HZ = hz or 1,
		Speed = speed or (cfg.WalkSpeed[1] + self.Rng() * (cfg.WalkSpeed[2] - cfg.WalkSpeed[1])),
		Lateral = (self.Rng() * 2 - 1) * cfg.SidewalkSpread * 0.7, LatCur = 0, State = "Yürü", Timer = 0, Moving = 0,
		Seed = seed or self.Rng(), CurSpeed = 0,
	}
	self.NextId = self.NextId + 1
	self:_startLink(p, best, to)
	p.T = best.Length * (forward and bestT or (1 - bestT))
	p.X = best.A.X + dx * bestT
	p.Z = best.A.Z + dz * bestT
	p.HX, p.HZ = p.DX, p.DZ
	self.Peds[#self.Peds + 1] = p
	self.Stats.Rejoins = (self.Stats.Rejoins or 0) + 1
	return p
end

function PedSim:Remove(p, reason)
	if p.Removed then
		return
	end
	p.Removed = true
	p.RemoveReason = reason
	for i = #self.Peds, 1, -1 do
		if self.Peds[i] == p then
			table.remove(self.Peds, i)
			break
		end
	end
	self.Despawned[#self.Despawned + 1] = p
	self.Stats.Despawns = self.Stats.Despawns + 1
end

-- Düğüme varınca: yol varsa sıradakine, yoksa yeni hedef; geçitse izin bekle
function PedSim:_arrive(p, ctx)
	p.Node = p.To
	p.Link = nil
	if p.Node.Door and p.Goal == p.Node then
		-- DoorApproach: kapıya dön, kısa bekle (kapı açılır), sonra gir
		local e = p.Node.Door
		local dc = self.Cfg.Doors
		p.Goal, p.Path = nil, nil
		p.Door = e
		p.State = "Kapı"
		p.Timer = dc.PauseTime[1] + self.Rng() * (dc.PauseTime[2] - dc.PauseTime[1])
		p.WX, p.WZ = -e.NX, -e.NZ
		return
	end
	if p.Goal and p.Node == p.Goal then
		p.Goal, p.Path = nil, nil
		local sched = self:_schedule(ctx.Hour or 12)
		if p.Node.Spot and self.Rng() < sched.Idle + 0.25 or self.Rng() < sched.Idle * 0.4 then
			p.State = "Mola"
			p.Timer = sched.IdleTime[1] + self.Rng() * (sched.IdleTime[2] - sched.IdleTime[1])
			if p.Node.Spot then
				p.WX, p.WZ = p.Node.Spot.FaceX, p.Node.Spot.FaceZ -- noktaya doğru (dönüş hızıyla) dön
			end
			return
		end
	end
	if not p.Path or p.PathIndex > #p.Path then
		if not self:_newGoal(p, ctx) then
			-- hedef yok: rastgele komşu bağlantı (geri dönüş son çare)
			local links = {}
			for _, l in ipairs(p.Node.Links) do
				if not l.Door or p.Node.Door then
					links[#links + 1] = l -- kapı bağlantısına rastgele sapma yok (kapıdaysa çıkış yolu o)
				end
			end
			if #links == 0 then
				self:Remove(p, "Çıkmaz")
				return
			end
			local l = links[1 + floor(self.Rng() * #links) % #links]
			p.Path, p.PathIndex = { { Node = (l.A == p.Node) and l.B or l.A, Link = l } }, 1
		end
	end
	local step = p.Path[p.PathIndex]
	p.PathIndex = p.PathIndex + 1
	if step.Link.Crossing then
		p.State = "Bekle"
		p.Timer = 0
		p.PendingLink, p.PendingNode = step.Link, step.Node
	else
		self:_startLink(p, step.Link, step.Node)
		p.State = "Yürü"
	end
end

-- Nokta (x, z) bir aracın (pay kadar genişletilmiş) gövde kutusunda mı?
local function inVehicleBox(v, x, z, pad)
	local dx, dz = x - v.X, z - v.Z
	local along = dx * v.HX + dz * v.HZ
	local side = -dx * v.HZ + dz * v.HX
	return abs(along) < v.Len / 2 + pad and abs(side) < v.Width / 2 + pad
end

-- Geçit şeridinin üstünde/yanında araç var mı (dönen ya da geçide taşmış araç)
function PedSim:_crossingOccupied(link)
	local ax, az, bx, bz = link.A.X, link.A.Z, link.B.X, link.B.Z
	local dx, dz = bx - ax, bz - az
	local L2 = max(dx * dx + dz * dz, 0.01)
	local vehicles = self.Traffic and self.Traffic.Vehicles or {}
	for _, v in ipairs(vehicles) do
		local t = clamp(((v.X - ax) * dx + (v.Z - az) * dz) / L2, 0, 1)
		local px, pz = ax + dx * t, az + dz * t
		local reach = v.Len / 2 + 3 + (v.V > 1 and v.V * 0.8 or 0)
		if (v.X - px) ^ 2 + (v.Z - pz) ^ 2 < reach * reach and abs(v.Y - self.Graph.RoadTop) < 4 then
			return true
		end
	end
	return false
end

function PedSim:_mayCross(p, link, time)
	local tnode = self.TGraph.Nodes[link.Node]
	if not tnode then
		return true
	end
	if self:_crossingOccupied(link) then
		return false
	end
	local crossSeconds = link.Length / (p.Speed * self.Cfg.CrossSpeedFactor) + 1.5
	if link.Signal then
		return (self.TG.WalkAllowed(self.TGraph, tnode, link.ArmPhase, time, crossSeconds))
	end
	if link.ArmEdge and self.Traffic and self.Traffic:ArmBusy(tnode, link.ArmEdge, self.Cfg.CrossGapRadius) then
		return false
	end
	return true
end

function PedSim:Step(dt, ctx)
	local cfg = self.Cfg
	local graph = self.Graph
	local time = ctx.Time or 0
	self.Time = self.Time + dt
	local foci = ctx.Focus or {}
	local fullR2 = (cfg.FullUpdateRadius or math.huge) ^ 2
	self.Spawned, self.Despawned = {}, {}
	local obstacles = ctx.Obstacles or {}
	local vehicles = self.Traffic and self.Traffic.Vehicles or {}

	-- komşuluk ızgarası (yaya ↔ yaya)
	local cell = {}
	local CS = 6
	for _, p in ipairs(self.Peds) do
		local k = floor(p.X / CS) .. ":" .. floor(p.Z / CS)
		cell[k] = cell[k] or {}
		table.insert(cell[k], p)
	end

	local dc = cfg.Doors
	for i = #self.Peds, 1, -1 do
		local p = self.Peds[i]
		if p.State == "Kapı" then
			-- kapının önünde, kapıya dönük; sıradaki biri giriyor/çıkıyorsa bekler
			local e = p.Door
			p.Moving, p.CurSpeed = 0, 0
			p.X, p.Z, p.Y = e.OutX, e.OutZ, e.Y
			p.Timer = p.Timer - dt
			if p.Timer < 0.35 then
				e.OpenUntil = self.Time + 0.8 -- kapı açılmaya başlar
			end
			if p.Timer <= 0 and not self:_doorBusy(e) then
				p.State, p.Timer = "Gir", 0
				e.BusyUntil = self.Time + dc.EnterTime + 0.2
			end
		elseif p.State == "Gir" or p.State == "Çık" then
			-- EnterBuilding / ExitBuilding: kapı boşluğundan geçiş (duvar içinden değil), eşikte kararma
			local e = p.Door
			p.Timer = p.Timer + dt
			local dur = (p.State == "Gir") and dc.EnterTime or dc.ExitTime
			local k = clamp(p.Timer / dur, 0, 1)
			local depth = dc.Depth or 1.8
			local inX, inZ = e.X - e.NX * depth, e.Z - e.NZ * depth
			local ax, az, bx, bz = e.OutX, e.OutZ, inX, inZ
			if p.State == "Çık" then
				ax, az, bx, bz = inX, inZ, e.OutX, e.OutZ
			end
			-- yumuşak başla/bitir (smoothstep): kapıda dururken hız 0'dan artar, içeride/kapı önünde 0'a iner
			local ks = k * k * (3 - 2 * k)
			p.X, p.Z, p.Y = ax + (bx - ax) * ks, az + (bz - az) * ks, e.Y
			local dx, dz = bx - ax, bz - az
			local l = max(sqrt(dx * dx + dz * dz), 0.01)
			p.WX, p.WZ = dx / l, dz / l
			p.CurSpeed = l * 6 * k * (1 - k) / dur
			p.Moving = p.CurSpeed / max(p.Speed, 0.1)
			e.OpenUntil = self.Time + 0.8
			if p.State == "Gir" then
				p.Fade = clamp((k - 0.35) / 0.55, 0, 1) -- eşikten geçerken kararır
				if k >= 1 then
					self.Stats.Entered = self.Stats.Entered + 1
					self:Remove(p, "Bina")
				end
			else
				p.Fade = 1 - clamp(k / 0.5, 0, 1)
				if k >= 1 then
					p.Fade = 0
					p.State = "Yürü"
					p.Node = e.Node
					p.To = e.Node
					p.Door = nil
					self:_arrive(p, ctx) -- yeni hedef ve yol (kapı bağlantısından kaldırıma)
				end
			end
		elseif p.State == "Mola" then
			p.Timer = p.Timer - dt
			p.Moving = 0
			if p.Timer <= 0 then
				p.State = "Yürü"
				self:_arrive(p, ctx)
			end
		elseif p.State == "Bekle" then
			p.Moving = 0
			p.Timer = p.Timer + dt
			local link = p.PendingLink
			if self:_mayCross(p, link, time) then
				if link.Signal and self.TGraph.Nodes[link.Node] then
					local ok = self.TG.WalkAllowed(self.TGraph, self.TGraph.Nodes[link.Node], link.ArmPhase, time, 0)
					if not ok then
						self.Stats.CrossOnRed = self.Stats.CrossOnRed + 1
					end
				end
				self:_startLink(p, link, p.PendingNode)
				p.State = "Geç"
				p.PendingLink, p.PendingNode = nil, nil
				self.Stats.Crossings = self.Stats.Crossings + 1
			elseif not link.Signal and p.Timer > cfg.CrossWaitGiveUp then
				-- vazgeç: başka hedef
				p.PendingLink, p.PendingNode, p.Path, p.Goal = nil, nil, nil, nil
				self.Stats.GaveUp = self.Stats.GaveUp + 1
				local links = {}
				for _, l in ipairs(p.Node.Links) do
					if not l.Crossing then
						links[#links + 1] = l
					end
				end
				if #links > 0 then
					local l = links[1 + floor(self.Rng() * #links) % #links]
					self:_startLink(p, l, (l.A == p.Node) and l.B or l.A)
					p.State = "Yürü"
				else
					p.Timer = 0
				end
			end
		end

		if (p.State == "Yürü" or p.State == "Geç") and p.Link then
			local speed = p.Speed * ((p.State == "Geç") and cfg.CrossSpeedFactor or 1)
			local wantLat = p.Lateral
			local slow = 1
			-- uzak (görüş detayı yok) ve kaldırımdaki yaya: komşu/engel taraması yapılmaz (maliyet LOD)
			local near = true
			if #foci > 0 and p.State ~= "Geç" and not p.Link.Crossing then
				local f = foci[1]
				local best = (f.X - p.X) ^ 2 + (f.Z - p.Z) ^ 2
				for k = 2, #foci do
					local d2 = (foci[k].X - p.X) ^ 2 + (foci[k].Z - p.Z) ^ 2
					if d2 < best then
						best = d2
					end
				end
				near = best < fullR2
			end
			-- diğer yayalar
			local cx, cz = floor(p.X / CS), floor(p.Z / CS)
			for a = cx - 1, (near and cx + 1 or cx - 2) do
				for b = cz - 1, cz + 1 do
					for _, q in ipairs(cell[a .. ":" .. b] or {}) do
						if q ~= p then
							local dx, dz = q.X - p.X, q.Z - p.Z
							local d2 = dx * dx + dz * dz
							if d2 < 36 then
								local ahead = dx * p.DX + dz * p.DZ
								local side = dx * (-p.DZ) + dz * p.DX -- + sağ
								if ahead > 0 and abs(side) < cfg.PersonalSpace then
									if q.Link == p.Link and q.DX * p.DX + q.DZ * p.DZ < -0.5 then
										wantLat = cfg.SidewalkSpread * 0.8 -- karşıdan gelen: sağa kay
									elseif ahead < 2.5 then
										slow = min(slow, (q.Moving or 0) > 0 and 0.6 or 0.25)
										wantLat = clamp(p.LatCur - (side > 0 and 1.5 or -1.5), -cfg.SidewalkSpread, cfg.SidewalkSpread)
									end
								end
							end
						end
					end
				end
			end
			-- oyuncular ve araçlar
			for _, o in ipairs(near and obstacles or {}) do
				local dx, dz = o.X - p.X, o.Z - p.Z
				local d2 = dx * dx + dz * dz
				local r = (o.Kind == "Vehicle") and cfg.VehicleFleeRadius or cfg.PlayerAvoidRadius
				if d2 < r * r then
					local ahead = dx * p.DX + dz * p.DZ
					local side = dx * (-p.DZ) + dz * p.DX
					if o.Kind == "Vehicle" and (o.Speed or 0) > 6 then
						wantLat = (side > 0) and -cfg.SidewalkSpread or cfg.SidewalkSpread -- uzaklaş
						if p.State ~= "Geç" then
							slow = min(slow, 0.3)
						end
					elseif ahead > -0.5 then
						wantLat = (side > 0) and -cfg.SidewalkSpread or cfg.SidewalkSpread
						if ahead < 2.2 then
							slow = min(slow, 0.15)
						end
					end
				end
			end
			-- önündeki araç (duran ya da geçen): gövde kutusuna yürüme (araç zaten yayaya yol verir; çift güvenlik)
			if p.State == "Geç" or p.Link.Crossing then
				local fx, fz = p.X + p.DX * 1.6, p.Z + p.DZ * 1.6
				-- Duran araç kendisini bekliyorsa ikisi birbirini beklemesin: 2.5 sn'den uzun bekleyen yaya duran aracın
				-- köşesinden daha yakın (0.5 pay) geçer. Hareketli araç için pay her zaman büyük.
				if (p.BoxWait or 0) > 2.5 then
					p.SqueezeLink = p.Link -- bu geçit boyunca yakın geçebilir
				end
				local stillPad = (p.SqueezeLink == p.Link) and 0.5 or 0.9
				local blocker = nil
				for _, v in ipairs(vehicles) do
					local dx, dz = v.X - p.X, v.Z - p.Z
					if dx * dx + dz * dz < 400 then
						if v.V > 1 then
							if inVehicleBox(v, fx, fz, 2.5) then
								slow = 0
							end
						elseif inVehicleBox(v, fx, fz, stillPad) then
							slow = 0
							blocker = v
						end
					end
				end
				p.BoxWait = blocker and ((p.BoxWait or 0) + dt) or 0
				-- Etrafından dolaş: duran aracın burnu geçide taşmışsa (yaya onu, o yayayı bekliyor) aracın gövdesinin
				-- yanından 1 stud açıkta geçecek yanal konuma kay (geçidin dışına en fazla 4 stud).
				if blocker and p.BoxWait > 2.5 then
					local lx, lz = -p.DZ, p.DX
					local f = p.From
					local lmin, lmax = math.huge, -math.huge
					local sx, sz = -blocker.HZ, blocker.HX
					for _, a in ipairs({ -1, 1 }) do
						for _, c in ipairs({ -1, 1 }) do
							local cx = blocker.X + blocker.HX * blocker.Len / 2 * a + sx * blocker.Width / 2 * c
							local cz = blocker.Z + blocker.HZ * blocker.Len / 2 * a + sz * blocker.Width / 2 * c
							local lat = (cx - f.X) * lx + (cz - f.Z) * lz
							lmin, lmax = min(lmin, lat), max(lmax, lat)
						end
					end
					local left, right = lmin - 1, lmax + 1
					local target = (abs(left - p.LatCur) <= abs(right - p.LatCur)) and left or right
					if abs(target) > 4 then
						target = (target == left) and right or left -- diğer taraf
					end
					if abs(target) <= 4 then
						p.Detour, p.DetourLink = target, p.Link
					end
				end
			end
			-- yanal konum (geçitte ortada yürü; araç etrafından dolaşırken o yanal konumda)
			if p.State == "Geç" then
				wantLat = clamp(p.Lateral, -1.5, 1.5)
			end
			if p.Detour and p.DetourLink == p.Link then
				wantLat = p.Detour
			end
			if p.Link.Door then
				wantLat = 0 -- kapıya giden yolda kapının ortasına yürü
			end
			local latStep = 1.8 * dt
			p.LatCur = p.LatCur + clamp(wantLat - p.LatCur, -latStep, latStep)
			-- hız rampası: kalkış ve yavaşlama ivmeli; engel/araç kutusu yüzünden "dur" (slow = 0) anında
			local target = speed * slow
			-- karşıya geçmeden önce (geçit başında bekleyecek) ve hedefte yavaşlayarak dur
			local nextStep = p.Path and p.Path[p.PathIndex]
			if (nextStep and nextStep.Link.Crossing) or (p.Goal and p.To == p.Goal) then
				local rest = max(p.Link.Length - p.T, 0)
				target = min(target, max(sqrt(2 * (cfg.WalkDecel or 8) * rest), 1.2))
			end
			local cur = p.CurSpeed or target
			if slow == 0 then
				cur = 0
			elseif target > cur then
				cur = min(target, cur + (cfg.WalkAccel or 6) * dt)
			else
				cur = max(target, cur - (cfg.WalkDecel or 8) * dt)
			end
			p.CurSpeed = cur
			local step = cur * dt
			p.Moving = cur / max(p.Speed, 0.1) -- animasyon adım hızı gerçek hıza bağlı (ayak kayması yok)
			p.T = p.T + step
			if p.T >= p.Link.Length then
				p.T = p.Link.Length
				if p.State == "Geç" then
					p.State = "Yürü"
				end
				self:_arrive(p, ctx)
			end
		end

		-- konum
		local doorState = p.State == "Kapı" or p.State == "Gir" or p.State == "Çık" -- konum yukarıda ayarlandı
		if not doorState and not p.Removed and p.Link then
			local f, t = p.From, p.To
			local L = max(p.Link.Length, 0.01)
			local u = clamp(p.T / L, 0, 1)
			local x = f.X + (t.X - f.X) * u
			local z = f.Z + (t.Z - f.Z) * u
			local lat = p.LatCur
			p.X = x + (-p.DZ) * lat
			p.Z = z + p.DX * lat
			p.WX, p.WZ = p.DX, p.DZ
			if p.Link.Crossing then
				-- uçlarda kaldırım (köşe karesi), ortada yol yüzeyi; kaldırım kenarında yumuşak basamak
				local edgeDist = min(p.T, L - p.T)
				local k = clamp((edgeDist - 3) / 1.2, 0, 1)
				p.Y = graph.Top + (graph.RoadTop - graph.Top) * k
			elseif p.Link.Door then
				p.Y = f.Y + (t.Y - f.Y) * clamp((u - 0.7) / 0.3, 0, 1) -- basamaklı kapıda son kısımda yüksel
			else
				p.Y = graph.Top
			end
		elseif not doorState and not p.Removed and p.Node then
			-- düğümde bekliyor / mola: yanal konumu koru (sıçrama olmasın)
			local lat = p.LatCur or 0
			p.X, p.Z, p.Y = p.Node.X + (-(p.DZ or 0)) * lat, p.Node.Z + (p.DX or 0) * lat, graph.Top
			p.CurSpeed, p.Moving = 0, 0
			if p.State == "Bekle" and p.PendingNode then
				-- geçidin karşısına dön (ışığı bekliyor)
				local dx, dz = p.PendingNode.X - p.Node.X, p.PendingNode.Z - p.Node.Z
				local l = sqrt(dx * dx + dz * dz)
				if l > 0.01 then
					p.WX, p.WZ = dx / l, dz / l
				end
			elseif p.State == "Mola" and p.Node.Spot then
				p.WX, p.WZ = p.Node.Spot.FaceX, p.Node.Spot.FaceZ
			end
		end
		-- yön: istenen yöne dönüş hızıyla dön (köşede ani dönme yok)
		if not p.Removed and p.WX then
			local hx, hz = p.HX or p.WX, p.HZ or p.WZ
			local cross = hx * p.WZ - hz * p.WX
			local dot = hx * p.WX + hz * p.WZ
			local ang = atan2(cross, dot)
			local maxTurn = (cfg.TurnRate or 6) * dt
			if abs(ang) <= maxTurn then
				hx, hz = p.WX, p.WZ
			else
				local a = (ang > 0) and maxTurn or -maxTurn
				local c, s2 = math.cos(a), math.sin(a)
				hx, hz = hx * c - hz * s2, hx * s2 + hz * c
			end
			p.HX, p.HZ = hx, hz
		end
	end

	-- kaldırma ve doğurma. Görünen yaya kaldırılmaz (HardDespawnRadius'a kadar).
	local isVisible = ctx.IsVisible
	local selfTime = self.Time
	local function hidden(p, d)
		if not isVisible then
			return true
		end
		if (p.VisUntil or 0) > selfTime then
			return false
		end
		if isVisible(p.X, p.Y, p.Z, d) then
			p.VisUntil = selfTime + 0.5
			return false
		end
		return true
	end
	local hard = cfg.HardDespawnRadius or math.huge
	for i = #self.Peds, 1, -1 do
		local p = self.Peds[i]
		if #foci > 0 then
			local d = nearestFocus(foci, p.X, p.Z)
			if d > hard or (d > cfg.DespawnRadius and hidden(p, d)) then
				self:Remove(p, "Uzak")
			end
		end
	end
	local target = floor((ctx.MaxPeds or 0) * clamp(ctx.Density or 1, 0, 1) + 0.5)
	local tries, spawned = 0, 0
	local perTick = cfg.SpawnsPerTick
	if #self.Peds < target * 0.6 then
		perTick = perTick * 3
	end
	local ds = self:_doorSchedule(ctx.Hour or 12)
	while #self.Peds < target and spawned < perTick and tries < perTick * 4 do
		tries = tries + 1
		local ok
		if ds and self.Rng() < ds.Spawn then
			ok = self:_trySpawnDoor(ctx, ds)
		else
			ok = self:_trySpawn(ctx)
		end
		if ok then
			spawned = spawned + 1
		else
			self.Stats.Rejected = self.Stats.Rejected + 1
		end
	end
	local excess = #self.Peds - (target + 2)
	if excess > 0 then
		local order = {}
		for _, p in ipairs(self.Peds) do
			order[#order + 1] = { p, nearestFocus(foci, p.X, p.Z) }
		end
		table.sort(order, function(a, b)
			return a[2] > b[2]
		end)
		local removed, checked = 0, 0
		for _, item in ipairs(order) do
			if removed >= min(excess, 4) or checked >= 12 then
				break
			end
			checked = checked + 1
			if hidden(item[1], item[2]) then
				self:Remove(item[1], "Sınır")
				removed = removed + 1
			end
		end
	end
end

-- Saate göre yaya yoğunluk çarpanı
function PedSim:HourDensity(hour)
	return self:_schedule(hour).Density
end

return PedSim
