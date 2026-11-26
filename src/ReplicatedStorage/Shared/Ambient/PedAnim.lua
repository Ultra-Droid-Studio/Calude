-- PedAnim: NPC yaya animasyonu (Yaşayan Şehir). SAF Lua; Roblox API'si yok (tools/test_ambient.py denetler).
--
-- R15 iskeleti için eklem açıları üretir (PedRenderer bunları Motor6D.Transform'a yazar). Hazır Roblox yürüme
-- animasyonu kullanılmaz: o animasyon Roblox'un hızlı karakter adımına göre çizilmiştir; 4–6 stud/sn yürüyen bir
-- yayada ya ayak kayar ya da ağır çekim görünür. Burada adım, ters kinematikle GERÇEK yürüme hızından üretilir:
--   * Basan ayak yere sabittir (ayak kayması yok): adım boyu = hız / adım sıklığı; basan bacağın açısı, kalçanın
--     ilerleyişine göre her karede yeniden çözülür (iki eklemli IK). Kalça yüksekliği basan bacaktan hesaplanır
--     (doğal inip kalkma).
--   * Salınan ayak yerden kalkar (0.3 stud), öne gelir; ayak bileği tabanı yere paralel tutar.
--   * Kollar karşı bacakla salınır, dirsek hafif bükük; gövde hafif karşı döner.
--   * Hız 0'a inerken adım kısalır ve sıklık düşer → doğal duruş (Stop); hız artarken tersi (StartWalking).
--   * Dönüş: dönüş yönüne hafif eğilme ve başın dönüş yönüne bakması (Turn); yerinde dönüşte kısa ayak adımları.
--   * Duruş (Idle): nefes, ağırlık aktarma, ara sıra etrafa bakma.
--   * Kapı (DoorApproach/EnterBuilding/ExitBuilding): sağ kol kapıyı iter (Reach).
--
-- Ölçüler (PedRenderer ile aynı, stud): kalça eklemi yerden HIP_Y; uyluk L1, baldır L2; ayak bileği yerden ANKLE_Y.

local PedAnim = {}

local sin, cos, sqrt, abs, max, min, pi = math.sin, math.cos, math.sqrt, math.abs, math.max, math.min, math.pi
local atan2 = math.atan2 or math.atan
local acos = math.acos

PedAnim.HIP_Y = 2.7
PedAnim.L1 = 1.2
PedAnim.L2 = 1.2
PedAnim.ANKLE_Y = 0.3
PedAnim.LIFT = 0.32 -- salınan ayağın en yüksek kalkışı

local function clamp(x, a, b)
	if x < a then
		return a
	elseif x > b then
		return b
	end
	return x
end

local function newRng(seed)
	local state = math.floor((seed or 1) * 1000003) % 2147483646 + 1
	return function()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end

-- Adım sıklığı (adım/sn) yürüme hızına göre (insan: 1.4 m/s ≈ 5 stud/sn'de ~2 adım/sn)
function PedAnim.Cadence(v)
	if v <= 0.05 then
		return 0
	end
	local c = 1.5 + 0.14 * v
	if v < 1 then
		c = c * sqrt(v) -- çok yavaşken adımlar seyrekleşir (duruş/kalkış)
	end
	return c
end

-- İki eklemli bacak IK: kalçaya göre hedef ayak bileği (d: ileri +, h: aşağı +) → kalça açısı θ (ileri +), diz κ (≥0)
function PedAnim.LegIK(d, h)
	local L1, L2 = PedAnim.L1, PedAnim.L2
	local r = sqrt(d * d + h * h)
	r = clamp(r, 0.2, (L1 + L2) * 0.9999)
	local c = (r * r - L1 * L1 - L2 * L2) / (2 * L1 * L2)
	local kappa = acos(clamp(c, -1, 1)) -- diz bükülmesi: 0 = düz bacak (r = L1 + L2)
	-- hedef yönü (dikey aşağıdan ileri açı) + uyluğun önde olma payı
	local phiT = atan2(d, h)
	local beta = atan2(L2 * sin(kappa), L1 + L2 * cos(kappa))
	return phiT + beta, kappa
end

-- İleri kinematik (test ve hata ayıklama): kalçaya göre diz ve ayak bileği (d ileri, y yukarı)
function PedAnim.LegFK(theta, kappa)
	local L1, L2 = PedAnim.L1, PedAnim.L2
	local kx, ky = L1 * sin(theta), -L1 * cos(theta)
	local ax, ay = kx + L2 * sin(theta - kappa), ky - L2 * cos(theta - kappa)
	return kx, ky, ax, ay
end

function PedAnim.new(seed)
	local rng = newRng(seed)
	return {
		Rng = rng, Phase = rng() * 2 * pi, Time = rng() * 10, Gait = 0, Look = 0, LookTarget = 0,
		LookTimer = 1 + rng() * 4, Seed = rng(), Reach = 0, Lean = 0, Shuffle = 0, Dist = 0,
		Legs = { { InStance = true, Plant = 0, LiftD = 0 }, { InStance = false, Plant = 0, LiftD = 0 } },
	}
end

-- Bir bacağın ayak konumu (kalçaya göre ileri d) ve kalkışı. ph = bu bacağın evresi (0..π basış, π..2π salınım).
-- Basışta ayağın DÜNYADAKİ yeri saklanır (Plant): d = Plant − kat edilen yol → hız değişse de ayak kaymaz.
local function footOf(leg, ph, s, dist)
	ph = ph % (2 * pi)
	if ph < pi then
		if not leg.InStance then
			leg.InStance = true
			leg.Plant = dist + s / 2 -- salınımın bittiği yer (öne atılan ayak)
		end
		return clamp(leg.Plant - dist, -1.7, 1.7), 0, true
	end
	if leg.InStance then
		leg.InStance = false
		leg.LiftD = clamp(leg.Plant - dist, -1.7, 1.7)
	end
	local u = (ph - pi) / pi
	local us = u * u * (3 - 2 * u)
	local d = leg.LiftD + (s / 2 - leg.LiftD) * us -- salınım: ayak öne gelir
	return d, PedAnim.LIFT * sin(pi * u) * min(1, s / 1.2), false
end

-- st: PedAnim.new; input: { Speed (stud/sn, gerçek), Turn (rad/sn, + sola), Reach (0..1), Dt }
-- Dönüş: pose (açılar radyan; Root ofseti stud)
function PedAnim.Step(st, dt, speed, turn, reach)
	st.Time = st.Time + dt
	local v = max(speed or 0, 0)
	turn = turn or 0
	-- yerinde dönüş: kısa ayak adımları (Turn)
	local shuffleTarget = (v < 0.4 and abs(turn) > 1.2) and 1 or 0
	st.Shuffle = st.Shuffle + (shuffleTarget - st.Shuffle) * min(1, dt * 6)
	local gaitV = max(v, st.Shuffle * 1.2)
	local c = PedAnim.Cadence(gaitV)
	st.Phase = (st.Phase + dt * c * pi) % (2 * pi) -- bir adım = π
	local s = (c > 0) and min(gaitV / c, 2.6) or 0
	if st.Shuffle > 0.5 and v < 0.4 then
		s = min(s, 0.5)
	end
	-- yürüyüş ağırlığı (0 duruş … 1 yürüyüş): duruşa yumuşak geçiş. İlk karede doğrudan hedef (yürürken doğan /
	-- havuzdan alınan yaya ilk adımda ayak kaydırmasın)
	local gaitTarget = clamp(gaitV / 0.8, 0, 1)
	if not st.Started then
		st.Started = true
		st.Gait = gaitTarget
	end
	st.Gait = st.Gait + (gaitTarget - st.Gait) * min(1, dt * 8)
	local g = st.Gait

	local H0 = PedAnim.HIP_Y
	local a = PedAnim.ANKLE_Y
	local reachL = (PedAnim.L1 + PedAnim.L2) * 0.995
	st.Dist = st.Dist + v * dt
	local phL, phR = st.Phase, st.Phase + pi
	local dL, liftL, stL = footOf(st.Legs[1], phL, s, st.Dist)
	local dR, liftR, stR = footOf(st.Legs[2], phR, s, st.Dist)
	-- duruşa geçerken ayaklar gövdenin altına toplanır
	dL, dR = dL * g, dR * g
	liftL, liftR = liftL * g, liftR * g
	-- basan bacağa göre kalça yüksekliği (ayak yere değsin; doğal inip kalkma)
	local dSt = stL and dL or (stR and dR or 0)
	local hipH = min(H0, a + sqrt(max(reachL * reachL - dSt * dSt, 0.01)))
	hipH = H0 + (hipH - H0) * g

	local pose = {}
	local tL, kL = PedAnim.LegIK(dL, hipH - a - liftL)
	local tR, kR = PedAnim.LegIK(dR, hipH - a - liftR)
	pose.LHip, pose.LKnee = tL, kL
	pose.RHip, pose.RKnee = tR, kR
	-- ayak tabanı yere paralel (salınımda uç hafif yukarı)
	pose.LAnkle = -(tL - kL) + (stL and 0 or 0.12 * g)
	pose.RAnkle = -(tR - kR) + (stR and 0 or 0.12 * g)
	pose.LFootD, pose.RFootD, pose.LLift, pose.RLift = dL, dR, liftL, liftR
	pose.LStance, pose.RStance = stL, stR
	pose.HipH = hipH
	pose.StepLength = s * g

	-- kollar: karşı bacakla salınım
	local armAmp = clamp(s * g / 2.2, 0, 1)
	local swingL = sin(phR) * 0.33 * armAmp -- sol kol sağ bacakla (~±19°)
	local swingR = sin(phL) * 0.33 * armAmp
	local t = st.Time
	local breathe = sin(t * 2 * pi * 0.25 + st.Seed * 6)
	pose.LShoulder = swingL + 0.03 * breathe * (1 - g)
	pose.RShoulder = swingR + 0.03 * breathe * (1 - g)
	pose.LShoulderRoll = -0.06 -- kollar gövdeye yapışmasın
	pose.RShoulderRoll = 0.06
	pose.LElbow = 0.12 + 0.25 * max(0, swingL) + 0.08 * g
	pose.RElbow = 0.12 + 0.25 * max(0, swingR) + 0.08 * g

	-- kapıyı itme (sağ kol öne)
	st.Reach = st.Reach + ((reach or 0) - st.Reach) * min(1, dt * 6)
	local r = st.Reach
	pose.RShoulder = pose.RShoulder * (1 - r) + 1.15 * r
	pose.RElbow = pose.RElbow * (1 - r) + 0.35 * r

	-- gövde: karşı dönüş, nefes, ağırlık aktarma (duruşta), dönüşe eğilme
	local leanTarget = clamp(turn * max(v, 1) * 0.018, -0.12, 0.12) -- dönüşün içine eğil (+ sol)
	st.Lean = st.Lean + (leanTarget - st.Lean) * min(1, dt * 5)
	pose.WaistYaw = sin(phL) * 0.07 * g
	pose.WaistPitch = 0.04 * g + 0.012 * breathe * (1 - g)
	pose.RootYaw = -sin(phL) * 0.035 * g
	pose.RootRoll = st.Lean
	pose.RootX = (1 - g) * 0.05 * sin(t * 2 * pi * 0.11 + st.Seed * 9) + g * 0.04 * cos(phL)
	pose.RootY = hipH - H0

	-- baş: duruşta ara sıra etrafa bakar; dönüşte dönüş yönüne
	st.LookTimer = st.LookTimer - dt
	if st.LookTimer <= 0 then
		st.LookTimer = 2.5 + st.Rng() * 5
		st.LookTarget = (st.Rng() < 0.6) and (st.Rng() * 1.1 - 0.55) * (1 - g * 0.7) or 0
	end
	local lookGoal = st.LookTarget + clamp(turn * 0.25, -0.5, 0.5)
	st.Look = st.Look + (lookGoal - st.Look) * min(1, dt * 3)
	pose.NeckYaw = st.Look
	pose.NeckPitch = -pose.WaistPitch * 0.7 - (pose.RootY) * 0.15
	return pose
end

return PedAnim
