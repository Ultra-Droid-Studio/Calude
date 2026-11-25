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
--             CanSpawn(x,y,z,dist), DensityAt(x,z)

local PedSim = {}
PedSim.__index = PedSim

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

-- graph: PedGraph; tg: TrafficGraph; traffic: TrafficSim (ArmBusy, araç konumları); cfg: AmbientConfig.Pedestrians
function PedSim.new(graph, tg, traffic, cfg, PG, TG, seed)
	local self = setmetatable({}, PedSim)
	self.Graph, self.TGraph, self.Traffic, self.Cfg, self.PG, self.TG = graph, tg, traffic, cfg, PG, TG
	self.Rng = newRng(seed or 777)
	self.Peds = {}
	self.NextId = 1
	self.Spawned, self.Despawned = {}, {}
	self.Stats = { Spawns = 0, Despawns = 0, Rejected = 0, Crossings = 0, CrossOnRed = 0, GaveUp = 0, PathFail = 0 }
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

-- Yeni hedef seç ve yol bul
function PedSim:_newGoal(p, ctx)
	local graph = self.Graph
	local sched = self:_schedule(ctx.Hour or 12)
	local goal
	if #graph.Spots > 0 and self.Rng() < sched.Idle + 0.2 then
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
		local links = self.PG.LinksNear(graph, p.X, p.Z, self.Cfg.GoalRadius)
		for _ = 1, 6 do
			local l = links[1 + floor(self.Rng() * max(#links, 1)) % max(#links, 1)]
			if l then
				local n = (self.Rng() < 0.5) and l.A or l.B
				if n.Comp == p.Node.Comp and n ~= p.Node then
					goal = n
					break
				end
			end
		end
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
		Seed = self.Rng(),
	}
	p.LatCur = p.Lateral
	self.NextId = self.NextId + 1
	self:_startLink(p, link, to)
	p.T = link.Length * (dirForward and t or (1 - t))
	self.Peds[#self.Peds + 1] = p
	self.Spawned[#self.Spawned + 1] = p
	self.Stats.Spawns = self.Stats.Spawns + 1
	return true
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
	if p.Goal and p.Node == p.Goal then
		p.Goal, p.Path = nil, nil
		local sched = self:_schedule(ctx.Hour or 12)
		if p.Node.Spot and self.Rng() < sched.Idle + 0.25 or self.Rng() < sched.Idle * 0.4 then
			p.State = "Mola"
			p.Timer = sched.IdleTime[1] + self.Rng() * (sched.IdleTime[2] - sched.IdleTime[1])
			if p.Node.Spot then
				p.HX, p.HZ = p.Node.Spot.FaceX, p.Node.Spot.FaceZ
			end
			return
		end
	end
	if not p.Path or p.PathIndex > #p.Path then
		if not self:_newGoal(p, ctx) then
			-- hedef yok: rastgele komşu bağlantı (geri dönüş son çare)
			local links = p.Node.Links
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

	for i = #self.Peds, 1, -1 do
		local p = self.Peds[i]
		if p.State == "Mola" then
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
			-- diğer yayalar
			local cx, cz = floor(p.X / CS), floor(p.Z / CS)
			for a = cx - 1, cx + 1 do
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
			for _, o in ipairs(obstacles) do
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
				for _, v in ipairs(vehicles) do
					local dx, dz = v.X - p.X, v.Z - p.Z
					if dx * dx + dz * dz < 400 and inVehicleBox(v, fx, fz, (v.V > 1) and 2.5 or 0.9) then
						slow = 0
					end
				end
			end
			-- yanal konum (geçitte ortada yürü)
			if p.State == "Geç" then
				wantLat = clamp(p.Lateral, -1.5, 1.5)
			end
			local latStep = 1.8 * dt
			p.LatCur = p.LatCur + clamp(wantLat - p.LatCur, -latStep, latStep)
			local step = speed * slow * dt
			p.Moving = slow
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
		if not p.Removed and p.Link then
			local f, t = p.From, p.To
			local L = max(p.Link.Length, 0.01)
			local u = clamp(p.T / L, 0, 1)
			local x = f.X + (t.X - f.X) * u
			local z = f.Z + (t.Z - f.Z) * u
			local lat = p.LatCur
			p.X = x + (-p.DZ) * lat
			p.Z = z + p.DX * lat
			p.HX, p.HZ = p.DX, p.DZ
			if p.Link.Crossing then
				-- uçlarda kaldırım (köşe karesi), ortada yol yüzeyi; kaldırım kenarında yumuşak basamak
				local edgeDist = min(p.T, L - p.T)
				local k = clamp((edgeDist - 3) / 1.2, 0, 1)
				p.Y = graph.Top + (graph.RoadTop - graph.Top) * k
			else
				p.Y = graph.Top
			end
		elseif not p.Removed and p.Node then
			-- düğümde bekliyor / mola: yanal konumu koru (sıçrama olmasın)
			local lat = p.LatCur or 0
			p.X, p.Z, p.Y = p.Node.X + (-(p.DZ or 0)) * lat, p.Node.Z + (p.DX or 0) * lat, graph.Top
		end
	end

	-- kaldırma ve doğurma
	local foci = ctx.Focus or {}
	for i = #self.Peds, 1, -1 do
		local p = self.Peds[i]
		if #foci > 0 and nearestFocus(foci, p.X, p.Z) > cfg.DespawnRadius then
			self:Remove(p, "Uzak")
		end
	end
	local target = floor((ctx.MaxPeds or 0) * clamp(ctx.Density or 1, 0, 1) + 0.5)
	local tries, spawned = 0, 0
	while #self.Peds < target and spawned < cfg.SpawnsPerTick and tries < 8 do
		tries = tries + 1
		if self:_trySpawn(ctx) then
			spawned = spawned + 1
		else
			self.Stats.Rejected = self.Stats.Rejected + 1
		end
	end
	while #self.Peds > target + 2 do
		local far, farD = nil, -1
		for _, p in ipairs(self.Peds) do
			local d = nearestFocus(foci, p.X, p.Z)
			if d > farD then
				far, farD = p, d
			end
		end
		self:Remove(far, "Sınır")
	end
end

-- Saate göre yaya yoğunluk çarpanı
function PedSim:HourDensity(hour)
	return self:_schedule(hour).Density
end

return PedSim
