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
-- ctx (Step): Time (sunucu zamanı), Focus = { {X,Z}... }, Obstacles = { {X,Y,Z,R,Kind,VX?,VZ?}... }, MaxVehicles,
--             Density (0..1), CanSpawn(x,y,z,dist) -> bool (görünürlük), DensityAt(x,z) -> 0..1,
--             IsVisible(x,y,z,dist) -> bool (Yaşayan Şehir: görünen araç kaldırılmaz), MixAt(x,z) -> { kindId = çarpan }
--
-- Yaşayan Şehir eklentileri: yol sınıfına göre doğma ağırlığı (cadde yoğun, ara sokak seyrek), sınıfa göre dönüş
-- tercihi, sarsıntısız kalkış (ivme artışı sınırlı, fren anında), dur-kalk titremesine karşı duruş eşiği,
-- tıkalı çıkışta alternatif yön, rezervasyon kilidi bekçisi, bölgeye göre araç karışımı.

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
	self.Stats = {
		Spawns = 0, Despawns = 0, Rejected = 0, LaneChanges = 0, Entries = 0, RedEntries = 0, Removed = 0,
		Reroutes = 0, Locked = 0, Leaks = 0, Watchdog = 0, WatchdogObstacle = 0,
	}
	self.LaneCache = {}
	self.NextAudit = 5
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

-- mix: { kindId = çarpan } (bölge karışımı; yoksa yapılandırmadaki ağırlıklar)
function TrafficSim:_pickKind(mix)
	local total = self.KindWeight
	if mix then
		total = 0
		for _, k in ipairs(self.Kinds) do
			total = total + (k.Weight or 1) * (mix[k.Id] or 1)
		end
	end
	local r = self.Rng() * total
	for _, k in ipairs(self.Kinds) do
		r = r - (k.Weight or 1) * (mix and mix[k.Id] or 1)
		if r <= 0 then
			return k
		end
	end
	return self.Kinds[1]
end

local TURN_WEIGHT = { S = 0.5, R = 0.26, L = 0.22, U = 0.02 }
-- Dönüş tercihi: üst sınıf yola (cadde/otoyol) çıkan bağlantılar daha olası → trafik ana yollarda toplanır,
-- ara sokaklar seyrek kalır (TurnClassBias = 0 → eski davranış)
function TrafficSim:_turnWeight(c)
	local w = TURN_WEIGHT[c.Turn] or 0.1
	local bias = self.Cfg.TurnClassBias
	local cw = self.Cfg.ClassWeight
	if bias and cw then
		w = w * (1 - bias + bias * (cw[c.To.Kind] or 0.5))
	end
	return w
end

function TrafficSim:_pickNext(lane, exclude)
	local outs = lane.Out
	if #outs == 0 then
		return nil
	end
	local total = 0
	for _, c in ipairs(outs) do
		if c ~= exclude then
			total = total + self:_turnWeight(c)
		end
	end
	if total <= 0 then
		return outs[1]
	end
	local r = self.Rng() * total
	local last = outs[#outs]
	for _, c in ipairs(outs) do
		if c ~= exclude then
			r = r - self:_turnWeight(c)
			last = c
			if r <= 0 then
				return c
			end
		end
	end
	return last
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
		if v.Lat ~= 0 then
			-- şerit değiştirirken: yanal kayma ileri gittikçe kapanır (yanal hız ileri hıza bağlı, bkz. Step)
			local close = abs(v.Lat) * max(v.V, 1.5) / max(v.LatRate or 1, 0.1)
			local k = max(0, 1 - d / max(close, 1))
			x, z = x + seg.RX * v.Lat * k, z + seg.RZ * v.Lat * k
		end
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
-- Öngörü (Anticipation, sn): öndeki benden hızlıysa (ör. ışıkta kalktı) boşluğun birazdan açılacağını hesaba katar →
-- kuyruk daha çabuk çözülür. Öndeki yavaşlarsa terim sıfırdır (güvenlik aynı).
local function idm(cfg, v, v0, gap, vLead)
	local a, b = cfg.MaxAccel, cfg.ComfortDecel
	local free = 1 - (v / max(v0, 0.5)) ^ 4
	if not gap then
		return a * free
	end
	if vLead > v and cfg.Anticipation then
		gap = gap + (vLead - v) * cfg.Anticipation
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
	-- +1.5 pay: kuyruğun arkasında duran aracın arka tamponu kavşağın dışında kalsın ("kavşağı tıkama")
	return room >= min(v.Len + self.Cfg.MinGap + 1.5, to.Length * 0.8)
end

-- Çıkış kapalı mı? (oyuncu/oyuncu aracı kavşak içinde ya da çıkış şeridinin başında duruyor). Kapalıysa kavşağa
-- girilmez: araç kavşağın ortasında kalıp diğer yönleri tıkamaz; bir süre sonra başka yöne döner (_reroute).
-- Karşıdan karşıya geçen yaya burada sayılmaz (onu bekleme kuralları zaten çözer).
function TrafficSim:_exitBlocked(v, node, conn)
	local obstacles = self.Obstacles
	if not obstacles or #obstacles == 0 then
		return false
	end
	local lane = conn.To
	local need = v.Len + self.Cfg.MinGap + 2
	-- yanal eşik, sürüşteki engel freniyle aynı (araç: gövde yarı genişliği; insan: şerit yarı genişliği)
	local halfBody = v.Width / 2 + 0.5
	local halfLane = max(conn.From.LaneWidth / 2, halfBody)
	for _, o in ipairs(obstacles) do
		if o.Kind ~= "Pedestrian" then
			local r = o.R or 2
			local lim = ((o.Kind == "Vehicle") and halfBody or halfLane) + r
			local nx, nz = o.X - node.X, o.Z - node.Z
			if nx * nx + nz * nz < 3600 then
				local ox, oz = o.X - lane.X0, o.Z - lane.Z0
				local along = ox * lane.UX + oz * lane.UZ
				local side = abs(ox * lane.RX + oz * lane.RZ)
				if along > -2 and along < need + r and side < max(lane.LaneWidth / 2 + r, lim) then
					return true
				end
				local steps = max(2, floor(conn.Length / 3))
				for i = 0, steps do
					local px, _, pz = self.TG.ConnPoint(conn, conn.Length * i / steps)
					local ex, ez = o.X - px, o.Z - pz
					if ex * ex + ez * ez < lim * lim then
						return true
					end
				end
			end
		end
	end
	return false
end

-- Çıkıştaki yaya geçidinde (hedef şeridin ilk metreleri) karşıya geçen yaya var mı ya da şeridime yaklaşıyor mu?
-- Varsa kavşağa girmeden çizgide beklenir (kavşağın ortasında yaya bekleyip yolu tıkamak yerine).
function TrafficSim:_exitCrosswalkBusy(v, conn)
	local obstacles = self.Obstacles
	if not obstacles or #obstacles == 0 then
		return false
	end
	local lane = conn.To
	local need = v.Len + self.Cfg.MinGap + 2
	for _, o in ipairs(obstacles) do
		if o.Kind == "Pedestrian" then
			local r = o.R or 1.4
			local ox, oz = o.X - lane.X0, o.Z - lane.Z0
			local along = ox * lane.UX + oz * lane.UZ
			if along > -2 and along < need then
				local side = abs(ox * lane.RX + oz * lane.RZ)
				if side < lane.LaneWidth / 2 + r + 8 then
					return true
				end
			end
		end
	end
	return false
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

-- Sarıda: karşıdan gelip artık DURAMAYACAK (kavşağa girmek zorunda) öncelikli araç var mı?
function TrafficSim:_priorityCommitted(node, conn)
	local conflicts = self.TG.Conflicts(self.Graph, node)[conn]
	if not conflicts then
		return false
	end
	local b = self.Cfg.ComfortDecel
	for other in pairs(conflicts) do
		if other.From.Group ~= conn.From.Group then
			for _, w in ipairs(other.From.Vehicles) do
				if w.Next == other and w.V > 1.5 and (other.From.StopS - w.S - w.Len / 2) < w.V * w.V / (2 * b) + 3 then
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
	if self:_exitBlocked(v, node, conn) then
		return false, "Kapalı"
	end
	if self:_exitCrosswalkBusy(v, conn) then
		return false, "Geçit"
	end
	if self:_conflictReserved(node, conn) or self:_tailBlocks(node, conn, v) then
		return false, "Çakışma"
	end
	if control == "Free" then
		return true -- şerit birleşmesi (şerit sayısı azalıyor): sadece rezervasyon + yer kontrolü
	end
	if control == "Signal" then
		local state, left = self.TG.SignalState(self.Graph, node, conn.Phase, time)
		if state == "R" then
			return false, "Kırmızı"
		elseif state == "Y" then
			-- yeşil boyunca karşı akış yüzünden dönemeyen (çizgide bekleyen) sola dönen araç sarıda döner:
			-- karşıdan gelenler durur; sadece artık duramayacak olana yol verir. Kırmızı + tümü kırmızı içinde çıkar.
			local turnL = conn.Turn == "L" or conn.Turn == "U"
			if turnL and (v.LeftWait or 0) > 2 and v.V < 2 and left > 1.2 then
				if self:_priorityCommitted(node, conn) then
					return false, "SolDönüş"
				end
				return true
			end
			if distToStop > (v.V * v.V) / (2 * self.Cfg.ComfortDecel) then
				return false, "Sarı"
			end
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

-- Kuyruk: araç bağlantıdan çıkış şeridine geçtiğinde arkası hâlâ kavşağın içinde olabilir (ör. çıkıştaki yaya
-- geçidinde durdu). Rezervasyon bırakılır (bütün çakışan yönleri kapatmak şebekede kilitlenme yaratır), ama araç
-- arka tamponu kavşaktan çıkana kadar düğümün "kuyruk" listesinde kalır: gövdesi bir bağlantının yolunu GERÇEKTEN
-- kesiyorsa o bağlantıya giriş izni verilmez (_tailBlocks) ve kavşaktaki araç onun önünde durur.
function TrafficSim:_moveToTail(v)
	self:_releaseTail(v)
	local conn, node = v.Reserve, v.ReserveNode
	self:_release(v)
	if node then
		v.TailConn, v.TailNode = conn, node
		node.Tails = node.Tails or {}
		node.Tails[v] = true
	end
end

function TrafficSim:_releaseTail(v)
	local node = v.TailNode
	if node and node.Tails then
		node.Tails[v] = nil
	end
	v.TailConn, v.TailNode = nil, nil
end

-- Noktanın (px,pz) aracın gövde ekseni (arka tampon → ön tampon) doğru parçasına uzaklığının karesi
local function distToBody2(w, px, pz)
	local hl = w.Len / 2
	local ax, az = w.X - w.HX * hl, w.Z - w.HZ * hl
	local ex, ez = w.HX * w.Len, w.HZ * w.Len
	local t = ((px - ax) * ex + (pz - az) * ez) / max(w.Len * w.Len, 0.01)
	t = clamp(t, 0, 1)
	local dx, dz = px - (ax + ex * t), pz - (az + ez * t)
	return dx * dx + dz * dz
end

-- Benim yolum (önümdeki maxAlong stud) w'nin gövdesine değiyor mu? Değiyorsa değdiği yol mesafesi.
function TrafficSim:_pathHitsBody(v, w, maxAlong)
	local lim = (v.Width + w.Width) / 2 + 0.6
	local lim2 = lim * lim
	local along = 0
	while along <= maxAlong do
		local px, pz = self:_pointAhead(v, along)
		if distToBody2(w, px, pz) < lim2 then
			return along
		end
		along = along + 2
	end
	return nil
end

-- Kavşaktan çıkmış ama arkası hâlâ kavşakta duran (kuyruğu tutulan) bir araç bu bağlantının yolunu kesiyor mu?
-- (Kavşak küçük, araç uzun: çıkıştaki yaya geçidinde durunca arkası yandaki yönün şeridine taşabilir.)
function TrafficSim:_tailBlocks(node, conn, v)
	local tails = node.Tails
	if not tails then
		return false
	end
	for w in pairs(tails) do
		if w ~= v and w.TailConn ~= conn then
			local lim = (v.Width + w.Width) / 2 + 0.6
			local lim2 = lim * lim
			for i = 1, #conn.PX do
				if distToBody2(w, conn.PX[i], conn.PZ[i]) < lim2 then
					return true
				end
			end
		end
	end
	return false
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

-- Doğma adayları: odağın çevresindeki şeritler, ağırlık = uzunluk × yol sınıfı ağırlığı (birikimli liste).
-- Önbellek: odak 40 studdan az kıpırdadıysa ve 3 sn geçmediyse yeniden hesaplanmaz (her denemede ızgara taraması yok).
function TrafficSim:_spawnLanes(index, focus)
	local c = self.LaneCache[index]
	if c and (c.X - focus.X) ^ 2 + (c.Z - focus.Z) ^ 2 < 1600 and self.Time - c.T < 3 then
		return c
	end
	local lanes = self.TG.LanesNear(self.Graph, focus.X, focus.Z, self.Cfg.SpawnMax)
	local cw = self.Cfg.ClassWeight or {}
	local cum, total = {}, 0
	for i, l in ipairs(lanes) do
		if l.Length >= 40 and #l.Out > 0 then
			total = total + (cw[l.Kind] or 0.5) * l.Length
		end
		cum[i] = total
	end
	c = { X = focus.X, Z = focus.Z, T = self.Time, Lanes = lanes, Cum = cum, Total = total }
	self.LaneCache[index] = c
	return c
end

function TrafficSim:_trySpawn(ctx)
	local cfg = self.Cfg
	local foci = ctx.Focus
	if #foci == 0 then
		return false
	end
	local fi = 1 + floor(self.Rng() * #foci) % #foci
	local cache = self:_spawnLanes(fi, foci[fi])
	if cache.Total <= 0 then
		return false
	end
	local r = self.Rng() * cache.Total
	local lo, hi = 1, #cache.Lanes
	while lo < hi do
		local mid = floor((lo + hi) / 2)
		if cache.Cum[mid] < r then
			lo = mid + 1
		else
			hi = mid
		end
	end
	local lane = cache.Lanes[lo]
	if lane.Length < 40 or #lane.Out == 0 then
		return false
	end
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
	local kind = self:_pickKind(ctx.MixAt and ctx.MixAt(x, z))
	local b = cfg.ComfortDecel
	local spawnSpeed = min(lane.Speed, kind.MaxSpeed) * (cfg.SpawnSpeedFactor or 0.6)
	-- durma çizgisine kadar konforlu durabilecek hız (ışık kırmızı olabilir: doğduğu an çizgide çakılmasın)
	spawnSpeed = min(spawnSpeed, sqrt(2 * b * max(lane.StopS - s - kind.Length / 2 - 4, 0)))
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
	-- önde: şeridin çıkış bağlantılarındaki ve onların hedef şeritlerinin başındaki araçlar (kavşakta duran araç)
	for _, c in ipairs(lane.Out) do
		for _, w in ipairs(c.Vehicles) do
			if not clear(lane.Length + w.S, w.V, w.Len) then
				return false
			end
		end
		local first = c.To.Vehicles[1]
		if first and not clear(lane.Length + c.Length + first.S, first.V, first.Len) then
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
	local stopAhead = spawnSpeed * spawnSpeed / (2 * b) + 30
	for _, o in ipairs(ctx.Obstacles or {}) do
		local dx, dz = o.X - x, o.Z - z
		-- her engelin dibinde doğma yok; insan (yolda yürüyen oyuncu/yaya) için doğma hızıyla durma mesafesi + pay
		local r = (o.Kind == "Vehicle") and 20 or stopAhead
		if dx * dx + dz * dz < r * r then
			return false
		end
		-- aynı şeritte önde (park etmiş oyuncu aracı vb.): durma mesafesi + 30 stud içinde doğma yok
		local ox, oz = o.X - lane.X0, o.Z - lane.Z0
		local along = ox * lane.UX + oz * lane.UZ
		local side = abs(ox * lane.RX + oz * lane.RZ)
		if side < lane.LaneWidth / 2 + (o.R or 2) + 1 and along > s - 15 and along < s + stopAhead then
			return false
		end
	end
	local v = {
		Id = self.NextId, Kind = kind, Len = kind.Length, Width = kind.Width,
		Seg = lane, OnConn = false, S = s, V = 0, Factor = cfg.SpeedFactor[1] + self.Rng() * (cfg.SpeedFactor[2] - cfg.SpeedFactor[1]),
		Lat = 0, LatRate = 0, Blocked = 0, StopTimer = 0, State = "Sür", Brake = false, Accel = 0, Stuck = 0, Held = 0,
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

-- Kazadan toparlanan aracı trafiğe geri kat (Şehir: çarpışmadan sonra yoluna devam). Araç (x, z) noktasında,
-- (hx, hz) yönüne bakıyor; aynı yöndeki en yakın şeride (uzaklık ≤ maxDist), durma çizgisinin önüne (geçmişse geri
-- alınarak), önünde ve arkasında yer varsa konur (hız 0; IDM ile kalkar). Bulunamazsa nil. Spawned listesine girmez: görseli çağıran
-- verir (aynı model).
function TrafficSim:Rejoin(kind, x, z, hx, hz, maxDist)
	maxDist = maxDist or 14
	local best, bestS, bestD = nil, 0, maxDist
	for _, lane in ipairs(self.TG.LanesNear(self.Graph, x, z, maxDist + 30)) do
		local limit = lane.StopS - kind.Length / 2 - 2 -- durma çizgisinin önünde kal (kavşak kutusuna konmaz)
		if lane.UX * hx + lane.UZ * hz > 0.5 and #lane.Out > 0 and limit >= 4 then
			local ox, oz = x - lane.X0, z - lane.Z0
			local along = ox * lane.UX + oz * lane.UZ
			local s = clamp(along, 4, limit) -- çizgiyi geçmişse birkaç stud geri alınır
			local lat = ox * lane.RX + oz * lane.RZ
			local d = sqrt(lat * lat + (along - s) * (along - s))
			if d < bestD then
				best, bestS, bestD = lane, s, d
			end
		end
	end
	if not best then
		return nil
	end
	for _, w in ipairs(best.Vehicles) do
		if abs(w.S - bestS) < (w.Len + kind.Length) / 2 + 6 then
			return nil -- yer yok (önde/arkada araç)
		end
	end
	local cfg = self.Cfg
	local px, py, pz = self.TG.LanePoint(best, bestS)
	local v = {
		Id = self.NextId, Kind = kind, Len = kind.Length, Width = kind.Width,
		Seg = best, OnConn = false, S = bestS, V = 0, Factor = cfg.SpeedFactor[1] + self.Rng() * (cfg.SpeedFactor[2] - cfg.SpeedFactor[1]),
		Lat = 0, LatRate = 0, Blocked = 0, StopTimer = 0, State = "Sür", Brake = false, Accel = 0, Stuck = 0, Held = 0,
		X = px, Y = py, Z = pz, HX = best.UX, HZ = best.UZ,
	}
	self.NextId = self.NextId + 1
	v.Next = self:_pickNext(best)
	insertSorted(best.Vehicles, v)
	self.Vehicles[#self.Vehicles + 1] = v
	self.Stats.Rejoins = (self.Stats.Rejoins or 0) + 1
	return v
end

function TrafficSim:Remove(v, reason)
	if v.Removed then
		return
	end
	v.Removed = true
	v.RemoveReason = reason
	removeFrom(segList(v), v)
	self:_release(v)
	self:_releaseTail(v)
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
				self:_releaseTail(v)
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

-- ===== Alternatif yön (kapalı/dolu çıkış) =====
-- Çıkış şeridi dolu ya da önü engelli olduğu için uzun süre bekleyen araç, kavşakta başka bir yöne döner
-- (gerçek sürücü gibi: "bu yol kapalı, sağdan dolaşayım"). Sadece durma çizgisinden önce ve izin almadan.
function TrafficSim:_obstacleNear(lane, obstacles, from, to)
	for _, o in ipairs(obstacles) do
		local ox, oz = o.X - lane.X0, o.Z - lane.Z0
		local along = ox * lane.UX + oz * lane.UZ
		local side = abs(ox * lane.RX + oz * lane.RZ)
		if along > from and along < to and side < lane.LaneWidth / 2 + (o.R or 2) then
			return true
		end
	end
	return false
end

function TrafficSim:_reroute(v, obstacles)
	if v.OnConn or v.Reserve or not v.Next then
		return false
	end
	local lane = v.Seg
	local options = {}
	for _, c in ipairs(lane.Out) do
		if c ~= v.Next and c.Turn ~= "U" and self:_targetHasRoom(v, c) and not self:_obstacleNear(c.To, obstacles, -4, 40) then
			options[#options + 1] = c
		end
	end
	if #options == 0 then
		return false
	end
	v.Next = options[1 + floor(self.Rng() * #options) % #options]
	v.Stuck = 0
	if v.WaitNode then
		v.WaitNode.Waiting[v] = nil
		v.WaitNode = nil
	end
	self.Stats.Reroutes = self.Stats.Reroutes + 1
	return true
end

-- ===== Ana adım =====
function TrafficSim:Step(dt, ctx)
	local cfg, TG, graph = self.Cfg, self.TG, self.Graph
	self.Time = self.Time + dt
	local time = ctx.Time or self.Time
	self.Spawned, self.Despawned = {}, {}
	local obstacles = ctx.Obstacles or {}
	self.Obstacles = obstacles
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
		-- Viraj/kavşak yaklaşması: bağlantının güvenli hızına (vt) şerit sonunda inmek için gereken sabit fren.
		-- IDM'in serbest yol terimi v > v0 iken zayıf frenler, sonra bağlantıya girince sert frene geçerdi (arkadaki
		-- araç yetişemezdi). Gereken fren 0.6·konfor frenini aşınca tam o kadar fren: düzgün, öngörülebilir yavaşlama.
		if not v.OnConn and v.Next and v.V > v.Next.MaxSpeed then
			local vt = v.Next.MaxSpeed
			local need = (v.V * v.V - vt * vt) / (2 * max(remaining - 1, 0.5))
			if need > cfg.ComfortDecel * 0.6 then
				accel = min(accel, -need)
			end
		end
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
		local nodeId = v.OnConn and seg.Node or (v.Next and remaining < look and v.Next.Node)
		if nodeId then
			local node = graph.Nodes[nodeId]
			local myGroup = v.OnConn and seg.From.Group or seg.Group
			local pathLen = min(look, (v.OnConn and (seg.Length - v.S) or (remaining + v.Next.Length)) + 4)
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
							elseif c.From.Group == myGroup and ahead > 0 then
								-- aynı şeritten ayrılan (dönüşe giren) araç: rezervasyon bunu korumaz; dönüşte durduysa
								-- arkası hâlâ benim yolumda olabilir → gövdesi yolumu kesiyorsa önünde dur
								local hitAt = self:_pathHitsBody(v, w, pathLen)
								if hitAt then
									local a2 = idm(cfg, v.V, v0, hitAt - v.Len / 2, 0)
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
			-- Kavşakta (ya da izinle girerken): arkası kavşağa taşan duran araç yolumdaysa önünde dur (güvenlik ağı)
			if (v.OnConn or v.Reserve) and node.Tails then
				for w in pairs(node.Tails) do
					if w ~= v and w ~= limitBy and w.Seg ~= (v.OnConn and seg.To or (v.Next and v.Next.To)) then
						local hitAt = self:_pathHitsBody(v, w, pathLen)
						if hitAt then
							local a2 = idm(cfg, v.V, v0, hitAt - v.Len / 2, 0)
							if a2 < accel then
								accel = a2
								limitBy = w
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
					if isFirst and distToStop < approach and not self:_tailBlocks(node, v.Next, v) then
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
						if not ok and (why == "SolDönüş" or why == "Çakışma") and (v.Next.Turn == "L" or v.Next.Turn == "U") then
							v.LeftWait = (v.LeftWait or 0) + dt -- sarıda dönme hakkı için bekleme süresi
						end
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
						v.LeftWait = 0
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
				-- insan (oyuncu/yaya) hareket ediyorsa 2 sn sonraki yeri de denenir: yola doğru yürüyen önceden görülür
				local qx, qz
				if o.Kind ~= "Vehicle" and o.VX and (o.VX * o.VX + o.VZ * o.VZ) > 0.25 then
					qx, qz = o.X + o.VX * 2, o.Z + o.VZ * 2
				end
				while along <= straight + 6 do
					local px, pz = self:_pointAhead(v, along)
					local ex, ez = o.X - px, o.Z - pz
					local e2 = ex * ex + ez * ez
					if qx then
						local fx, fz = qx - px, qz - pz
						e2 = min(e2, fx * fx + fz * fz)
					end
					if e2 < best then
						best, bestAlong = e2, along
					end
					along = along + step
				end
				local lateralLimit = ((o.Kind == "Vehicle") and halfBody or halfLane) + (o.R or 2)
				-- Yaya, yolumun ön tamponun GERİSİNDEKİ bir noktasına en yakınsa gövdenin yanındadır: gövdeden 0.8 stud
				-- açıktaysa ileri giderken ona çarpılmaz (onu beklemek karşılıklı beklemeye yol açar: yaya da gövdeyi
				-- bekler). Yol yayaya doğru dönüyorsa en yakın nokta öndedir → normal kural.
				if o.Kind == "Pedestrian" and bestAlong < v.Len / 2 - 0.5 and sqrt(best) > halfBody + 0.8 then
					lateralLimit = 0
				end
				if sqrt(best) < lateralLimit then
					local og = bestAlong - v.Len / 2 - (o.R or 2)
					local a2 = idm(cfg, v.V, v0, og, 0)
					if a2 < accel then
						accel = a2
						-- karşıya geçen yaya birazdan geçer: onun için şerit değiştirilmez / tıkanma sayılmaz
						limitBy = (o.Kind == "Pedestrian") and "pedestrian" or "obstacle"
					end
					v.State = "Engel"
				end
			end
		end

		-- İzin aldı ama engel (oyuncu/araç) yüzünden kavşağa giremiyor: izni 2 sn sonra bırak (bütün çakışan yönleri
		-- boşuna kapatmasın); sonra "çıkış kapalı" kuralıyla bekler ya da başka yöne döner. Sadece ön tampon durma
		-- çizgisini geçmemişse (kavşağa taşmış araç iznini korur).
		if v.Reserve and not v.OnConn and v.V < 0.3 and limitBy == "obstacle" and v.S + v.Len / 2 <= seg.StopS + 0.5 then
			v.ResHold = (v.ResHold or 0) + dt
			if v.ResHold > 2 then
				self:_release(v)
				v.ResHold = 0
			end
		else
			v.ResHold = 0
		end
		accel = clamp(accel, -cfg.MaxDecel, cfg.MaxAccel)
		-- Dur-kalk titremesi: duran araç küçük bir boşluk açıldı diye santim santim sürünmez (eşik altı → bekle)
		if v.V < 0.25 and accel > 0 and accel < (cfg.StartThreshold or 0) then
			accel = 0
		end
		-- Sarsıntısız kalkış: ivme ARTIŞI saniyede Jerk ile sınırlı (fren her zaman anında uygulanır → güvenlik
		-- etkilenmez). Duran araç negatif ivme hafızasını taşımaz: yeşilde gecikmeden kalkar.
		local prev = v.Accel or 0
		if v.V < 0.05 and prev < 0 then
			prev = 0
		end
		local jerk = cfg.Jerk
		if jerk and accel > prev + jerk * dt then
			accel = prev + jerk * dt
		end
		v.Accel = accel
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
			-- dolu/engelli çıkış yüzünden bekleme (alternatif yön için) ve izinli ama hiç ilerleyemeyen araç (kilit)
			if newV < 0.3 and not v.OnConn and not v.Reserve and (v.State == "Dolu" or v.State == "Kapalı" or v.State == "Engel") then
				v.Stuck = v.Stuck + dt
			else
				v.Stuck = 0
			end
			if newV < 0.3 and (v.Reserve or v.OnConn) and v.State ~= "Engel" then
				v.Held = v.Held + dt
			else
				v.Held = 0
			end
			-- bekçi: hiç kıpırdamadan geçen süre (kırmızı ışıkta bekleme dahil; eşik bir ışık döngüsünden çok uzun)
			if newV < 0.1 then
				v.Idle = (v.Idle or 0) + dt
			else
				v.Idle = 0
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
				self:_moveToTail(v)
				v.Seg, v.OnConn, v.S = lane, false, over
				insertSorted(lane.Vehicles, v)
				v.Next = self:_pickNext(lane)
			end
			-- arka tampon kavşaktan çıktı (ya da araç yeni bir bağlantıya girdi): kuyruk rezervasyonunu bırak
			if v.TailConn and (v.OnConn or v.S >= v.Len / 2 + 0.5) then
				self:_releaseTail(v)
			end
			-- yanal şerit değiştirme geçişi
			if v.Lat ~= 0 then
				-- araba dururken yana kaymaz: yanal hareket ileri harekete bağlı (1.5 stud/sn ve üstünde tam hız;
				-- yavaşken kısa mesafede şerit değiştirir). _pointAhead aynı kuralla yolu tahmin eder.
				local stepLat = v.LatRate * dt * min(newV / 1.5, 1)
				if abs(v.Lat) <= stepLat then
					v.Lat = 0
				else
					v.Lat = v.Lat - stepLat * (v.Lat > 0 and 1 or -1)
				end
			end
		end
	end

	-- 3. Tıkanma: yan şerit, alternatif yön, sonra kaldırma
	for i = #self.Vehicles, 1, -1 do
		local v = self.Vehicles[i]
		if v.Blocked > cfg.LaneChangeAfter and not v.OnConn then
			self:_tryLaneChange(v, obstacles)
		end
		if cfg.RerouteAfter and v.Stuck > cfg.RerouteAfter then
			if not self:_reroute(v, obstacles) then
				v.Stuck = cfg.RerouteAfter * 0.5 -- yarım süre sonra tekrar dene
			end
		end
	end
	-- rezervasyon denetimi (sızıntı olursa düzelt; ucuz, 5 sn'de bir)
	if self.Time >= self.NextAudit then
		self.NextAudit = self.Time + 5
		self.Stats.Leaks = self.Stats.Leaks + self:CheckReservations()
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

	-- 5. Kaldırma (uzak / uzun süre tıkalı / kilitli) ve doğurma.
	-- Görünen araç kaldırılmaz (gözün önünde kaybolma yok): uzak ama görünürse HardDespawnRadius'a kadar yaşar.
	local foci = ctx.Focus or {}
	local isVisible = ctx.IsVisible
	local function hidden(v, d)
		if not isVisible then
			return true
		end
		if (v.VisUntil or 0) > self.Time then
			return false -- yakın zamanda görünür bulundu: her adımda ışın atma
		end
		if isVisible(v.X, v.Y, v.Z, d) then
			v.VisUntil = self.Time + 0.5
			return false
		end
		return true
	end
	local hard = cfg.HardDespawnRadius or math.huge
	for i = #self.Vehicles, 1, -1 do
		local v = self.Vehicles[i]
		local d = nearestFocus(foci, v.X, v.Z)
		if #foci > 0 and (d > hard or (d > cfg.DespawnRadius and hidden(v, d))) then
			self:Remove(v, "Uzak")
		elseif v.Blocked > cfg.BlockedDespawnAfter and d > 60 and hidden(v, d) then
			self:Remove(v, "Tıkalı")
		elseif cfg.LockedAfter and v.Held > cfg.LockedAfter and d > 60 and hidden(v, d) then
			self.Stats.Locked = self.Stats.Locked + 1
			self:Remove(v, "Kilit")
		elseif cfg.IdleWatchdog and (v.Idle or 0) > cfg.IdleWatchdog and d > 60 and hidden(v, d) then
			-- son güvenlik ağı: beklenmedik bir kilitlenme şehri kalıcı tıkamasın. Kuyruğun başı bir engeli (yolda
			-- duran oyuncu/araç) bekliyorsa bu bir kilit değildir; ayrı sayılır (test sadece gerçek kilidi hata sayar).
			local w, hops = v, 0
			while type(w.LimitBy) == "table" and hops < 40 do
				w, hops = w.LimitBy, hops + 1
			end
			if w.LimitBy == "obstacle" then
				self.Stats.WatchdogObstacle = self.Stats.WatchdogObstacle + 1
			else
				self.Stats.Watchdog = self.Stats.Watchdog + 1
			end
			self:Remove(v, "Bekçi")
		end
	end
	local target = floor((ctx.MaxVehicles or 0) * clamp(ctx.Density or 1, 0, 1) + 0.5)
	local tries = 0
	local spawned = 0
	local perTick = cfg.SpawnsPerTick
	if #self.Vehicles < target * 0.6 then
		perTick = perTick * 3 -- hedefin çok altında (ilk giriş, yoğunluk artırıldı): daha hızlı doldur
	end
	while #self.Vehicles < target and spawned < perTick and tries < perTick * 4 do
		tries = tries + 1
		if self:_trySpawn(ctx) then
			spawned = spawned + 1
		else
			self.Stats.Rejected = self.Stats.Rejected + 1
		end
	end
	-- fazlalık (ör. sınır düşürüldü): GÖRÜNMEYENLERİN en uzağını kaldır (görünen kalır, sonra uzaklaşınca gider)
	local excess = #self.Vehicles - (target + 2)
	if excess > 0 then
		local order = {}
		for _, v in ipairs(self.Vehicles) do
			order[#order + 1] = { v, nearestFocus(foci, v.X, v.Z) }
		end
		table.sort(order, function(p, q)
			return p[2] > q[2]
		end)
		local removed, checked = 0, 0
		for _, item in ipairs(order) do
			if removed >= min(excess, 4) or checked >= 12 then
				break -- adım başına sınırlı iş (ışın sayısı)
			end
			checked = checked + 1
			if hidden(item[1], item[2]) then
				self:Remove(item[1], "Sınır")
				removed = removed + 1
			end
		end
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
