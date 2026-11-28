-- NPCChatService: yayalarla yapay zekâlı sohbet (Roblox'un kendi dil modeli: TextGenerator; ücretsiz, Roblox denetimli).
--
-- Yayalar her oyuncunun kendi cihazında (AmbientController); sohbet o oyuncuyla yaya arasındadır. İstemci
-- NPCRemotes.Talk'u çağırır: { Seed, Gender ("F"/"M"), Position, Message?, Token? }. Sunucu:
--   * kişiliği tohumdan kendisi üretir (ad, yaş, meslek, huy, ruh hâli) — istemci kişilik metni gönderemez
--   * bağlam ekler: bulunduğu semt, saat (gece/gündüz), yakındaki dükkânlar (harita verisi)
--   * oyuncunun mesajını ve modelin cevabını Roblox metin filtresinden geçirir (TextService)
--   * yazılı sohbete izni olmayan hesaplarda serbest metin yok (TextChatService:CanUserChatAsync): kısa selam
--   * oyuncu başına sıklık sınırı (NPCChatConfig), sohbet hafızası ContextToken ile (istemci saklar, geri gönderir)
-- Model yanıt veremezse (sınır, kesinti, özellik kapalı) yaya kısa hazır bir cümle söyler; oyun bozulmaz.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TextService = game:GetService("TextService")
local TextChatService = game:GetService("TextChatService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteRegistry = require(Shared.RemoteRegistry)
local MapDefinitions = require(Shared.MapDefinitions)
local Businesses = require(Shared.Businesses)
local RateLimiter = require(Shared.Utilities.RateLimiter)
local Log = require(Shared.Utilities.Log).new("NPCChat")
local Config = require(ReplicatedStorage.Modules.NPCChatConfig)

local NPCChatService = {
	Name = "NPCChatService",
	Priority = 70,
}

local limiter = RateLimiter.new(Config.RateCapacity, Config.RateRefillPerSecond)
local canChat: { [Player]: boolean } = {}
-- oyuncu → yaya tohumu → { Generator, Used }
local generators: { [Player]: { [number]: { Generator: Instance, Used: number } } } = {}
local folder: Folder
local warnedFailure = false

local function pick(list, rng: Random)
	return list[rng:NextInteger(1, #list)]
end

-- Tohumdan kişilik (her oyuncuda ve her seferinde aynı yaya için aynı kişi)
function NPCChatService.Persona(seed: number, gender: string)
	local rng = Random.new(math.floor(seed * 1e6) % 2147483647 + 1)
	local female = gender == "F" or (gender ~= "M" and rng:NextNumber() < 0.5)
	local first = pick(if female then Config.FemaleNames else Config.MaleNames, rng)
	local traitA = pick(Config.Traits, rng)
	local traitB = pick(Config.Traits, rng)
	local traits = traitA
	if traitB ~= traitA then
		traits = traitA .. ", " .. traitB
	end
	return {
		Name = first .. " " .. pick(Config.Surnames, rng),
		First = first,
		Female = female,
		Age = rng:NextInteger(22, 66),
		Job = pick(Config.Jobs, rng),
		Traits = traits,
		Mood = pick(Config.Moods, rng),
	}
end

local function districtAt(position: Vector3)
	local best, bestArea = nil, math.huge
	local districts = MapDefinitions.GetData().Districts
	for _, d in districts do
		if position.X >= d.Min.X and position.X <= d.Max.X and position.Z >= d.Min.Y and position.Z <= d.Max.Y then
			local area = (d.Max.X - d.Min.X) * (d.Max.Y - d.Min.Y)
			if area < bestArea then
				best, bestArea = d, area
			end
		end
	end
	return best
end

-- Yakındaki en fazla 4 işletme: "Ad (tür)"
local function nearbyPlaces(position: Vector3): { string }
	local found = {}
	local pois = MapDefinitions.GetData().POIs
	for _, poi in pois do
		local d = (Vector3.new(poi.Position.X, 0, poi.Position.Z) - Vector3.new(position.X, 0, position.Z)).Magnitude
		if d < 260 and poi.Name and poi.Name ~= "" then
			table.insert(found, { Poi = poi, D = d })
		end
	end
	table.sort(found, function(a, b)
		return a.D < b.D
	end)
	local out = {}
	for i = 1, math.min(4, #found) do
		local poi = found[i].Poi
		local t = Businesses.Types[poi.Type]
		table.insert(out, poi.Name .. (if t and t.TR then " (" .. t.TR .. ")" else ""))
	end
	return out
end

local function timeOfDay(): string
	local h = Lighting.ClockTime
	if h < 5 then
		return "gece yarısından sonra"
	elseif h < 11 then
		return "sabah"
	elseif h < 14 then
		return "öğle"
	elseif h < 18 then
		return "öğleden sonra"
	elseif h < 21 then
		return "akşam"
	end
	return "gece"
end

function NPCChatService.SystemPrompt(persona, position: Vector3): string
	local district = districtAt(position)
	local places = nearbyPlaces(position)
	local where = if district then district.Name else "Solara"
	local lines = {
		"Senin adın " .. persona.Name .. ". Solara adlı güneşli bir sahil şehrinde yaşıyorsun. " .. persona.Age
			.. " yaşındasın, " .. persona.Job .. " olarak çalışıyorsun. Kişiliğin: " .. persona.Traits .. ". Şu an "
			.. persona.Mood .. ".",
		"Şu an " .. where .. " semtinde, sokaktasın. Vakit " .. timeOfDay() .. ".",
	}
	if #places > 0 then
		table.insert(lines, "Yakınındaki yerler: " .. table.concat(places, ", ") .. ".")
	end
	table.insert(lines, "Biri sokakta sana yaklaştı ve seninle konuşuyor. Gerçek bir şehir sakini gibi doğal cevap ver.")
	table.insert(lines, "Kurallar: Karşındaki hangi dilde yazarsa o dilde cevap ver (varsayılan Türkçe). En fazla iki kısa cümle"
		.. " kur. Yapay zekâ ya da oyun karakteri olduğunu söyleme. Gerçek markalardan, gerçek kişilerden, siyasetten,"
		.. " dinden, şiddetten ve yetişkin konulardan bahsetme; nazikçe konuyu değiştir. Kişisel bilgi (gerçek ad, adres,"
		.. " telefon, yaş, okul) sorma ve isteme. Para, görev ya da eşya vaat etme. Kaba davranırlarsa kibarca uzaklaş.")
	return table.concat(lines, "\n")
end

local function filterFor(player: Player, text: string, broadcast: boolean): string?
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PrivateChat)
		return if broadcast then filtered:GetNonChatStringForBroadcastAsync() else filtered:GetNonChatStringForUserAsync(player.UserId)
	end)
	return if ok then result else nil
end

local function playerCanChat(player: Player): boolean
	local cached = canChat[player]
	if cached ~= nil then
		return cached
	end
	local ok, result = pcall(function()
		return TextChatService:CanUserChatAsync(player.UserId)
	end)
	local allowed = ok and result == true
	canChat[player] = allowed
	return allowed
end

local function generatorFor(player: Player, seed: number, prompt: string)
	local byPlayer = generators[player]
	if not byPlayer then
		byPlayer = {}
		generators[player] = byPlayer
	end
	local entry = byPlayer[seed]
	if not entry then
		-- oyuncu başına en fazla MaxGenerators sohbet (en eski kullanılan silinir)
		local count, oldestSeed, oldestUsed = 0, nil, math.huge
		for s, e in byPlayer do
			count += 1
			if e.Used < oldestUsed then
				oldestSeed, oldestUsed = s, e.Used
			end
		end
		if count >= Config.MaxGenerators and oldestSeed ~= nil then
			byPlayer[oldestSeed].Generator:Destroy()
			byPlayer[oldestSeed] = nil
		end
		local gen = Instance.new("TextGenerator")
		gen.Name = "NPC_" .. player.UserId .. "_" .. tostring(seed)
		gen.SystemPrompt = prompt
		gen.Temperature = Config.Temperature
		gen.TopP = Config.TopP
		gen.Parent = folder
		entry = { Generator = gen, Used = os.clock() }
		byPlayer[seed] = entry
	end
	entry.Used = os.clock()
	return entry.Generator
end

local function fallback(rng: Random?): string
	local r = rng or Random.new()
	return Config.FallbackLines[r:NextInteger(1, #Config.FallbackLines)]
end

-- Tek konuşma adımı. Döndürür: { Ok, Text, Token?, Name, Job, You? (filtrelenmiş oyuncu mesajı), NoChat? }
function NPCChatService.Talk(player: Player, request: any)
	if not Config.Enabled then
		return { Ok = false, Text = fallback() }
	end
	if type(request) ~= "table" or type(request.Seed) ~= "number" or typeof(request.Position) ~= "Vector3" then
		return { Ok = false, Text = fallback() }
	end
	local pos = request.Position
	if request.Seed ~= request.Seed or math.abs(request.Seed) > 1e6 or pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z then
		return { Ok = false, Text = fallback() } -- NaN / aşırı değer
	end
	local seed = math.floor(request.Seed * 1e6) / 1e6
	local gender = if request.Gender == "F" or request.Gender == "M" then request.Gender else "N"
	local persona = NPCChatService.Persona(seed, gender)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or (root.Position - request.Position).Magnitude > Config.EndDistance + 10 then
		return { Ok = false, Text = "", Name = persona.Name, Job = persona.Job }
	end
	if not limiter:Check(player) then
		return { Ok = false, Text = "Bir saniye, nefes alayım!", Name = persona.Name, Job = persona.Job, Busy = true }
	end
	local message = request.Message
	if message ~= nil and (type(message) ~= "string" or #message == 0 or utf8.len(message) == nil) then
		return { Ok = false, Text = fallback(), Name = persona.Name, Job = persona.Job }
	end
	if message and utf8.len(message) > Config.MaxMessageLength then
		message = string.sub(message, 1, utf8.offset(message, Config.MaxMessageLength + 1) - 1)
	end
	if not playerCanChat(player) then
		-- yazılı sohbete izni olmayan hesap: serbest metin yok, kısa hazır selam
		local r = Random.new(math.floor(seed * 1e6) % 100000 + 1)
		return { Ok = true, NoChat = true, Text = Config.Greetings[r:NextInteger(1, #Config.Greetings)], Name = persona.Name, Job = persona.Job }
	end
	local you = nil
	if message then
		you = filterFor(player, message, true)
		if not you then
			return { Ok = false, Text = fallback(), Name = persona.Name, Job = persona.Job }
		end
	end
	local token = if type(request.Token) == "string" and #request.Token < 20000 then request.Token else nil
	local gen = generatorFor(player, seed, NPCChatService.SystemPrompt(persona, request.Position))
	local userPrompt = you or "(Biri sana yaklaşıp selam verdi. Kısaca kendini tanıtarak selam ver.)"
	local ok, result = pcall(function()
		return (gen :: any):GenerateTextAsync({ UserPrompt = userPrompt, ContextToken = token, MaxTokens = Config.MaxTokens })
	end)
	if not ok or type(result) ~= "table" or type(result.GeneratedText) ~= "string" then
		if not warnedFailure then
			warnedFailure = true
			Log.Warn("TextGenerator yanıt vermedi (özellik kapalı ya da sınır aşıldı olabilir):", result)
		end
		return { Ok = false, Text = fallback(), Name = persona.Name, Job = persona.Job, You = you, Token = token }
	end
	local reply = string.gsub(result.GeneratedText, "^%s+", "")
	reply = string.gsub(reply, "%s+$", "")
	if utf8.len(reply) and utf8.len(reply) > Config.MaxReplyLength then
		reply = string.sub(reply, 1, utf8.offset(reply, Config.MaxReplyLength + 1) - 1) .. "…"
	end
	local shown = if reply ~= "" then filterFor(player, reply, false) else nil
	return {
		Ok = shown ~= nil,
		Text = shown or fallback(),
		Token = if type(result.ContextToken) == "string" then result.ContextToken else token,
		Name = persona.Name,
		Job = persona.Job,
		You = you,
	}
end

function NPCChatService:Init()
	folder = Instance.new("Folder")
	folder.Name = "NPCChatGenerators"
	folder.Parent = ServerStorage
end

function NPCChatService:Start()
	local remote = RemoteRegistry.Get("NPCRemotes", "Talk") :: RemoteFunction
	remote.OnServerInvoke = function(player, request)
		local ok, result = pcall(NPCChatService.Talk, player, request)
		if ok then
			return result
		end
		Log.Warn("Sohbet hatası:", result)
		return { Ok = false, Text = fallback() }
	end
	Players.PlayerRemoving:Connect(function(player)
		canChat[player] = nil
		limiter:Forget(player)
		local byPlayer = generators[player]
		generators[player] = nil
		if byPlayer then
			for _, entry in byPlayer do
				entry.Generator:Destroy()
			end
		end
	end)
	-- kullanılmayan üreticileri temizle
	task.spawn(function()
		while true do
			task.wait(60)
			local now = os.clock()
			for player, byPlayer in generators do
				for seed, entry in byPlayer do
					if now - entry.Used > Config.GeneratorIdleSeconds then
						entry.Generator:Destroy()
						byPlayer[seed] = nil
					end
				end
				if next(byPlayer) == nil then
					generators[player] = nil
				end
			end
		end
	end)
end

return NPCChatService
