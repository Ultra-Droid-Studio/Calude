-- GraphicsController: oyuncunun grafik tercihlerini YEREL olarak uygular (Aşama 1).
--
-- WeatherService Lighting efektlerini sunucuda bir kez kurar (SolaraBloom, SolaraSunRays, SolaraColor).
-- İstemcideki Enabled/GlobalShadows değişiklikleri sadece bu oyuncuyu etkiler ve sunucu bu
-- özellikleri tekrar yazmadığı için kalıcıdır.
--
-- Not: Roblox'un kendi "Grafik Kalitesi" kaydırıcısı oyun scriptlerinden değiştirilemez
-- (Esc → Ayarlar). Ayarlar ekranı bunu oyuncuya açıkça söyler.

local Lighting = game:GetService("Lighting")

local GraphicsController = {
	Name = "GraphicsController",
	Priority = 2,
}

local controllers

local EFFECT_NAMES = { "SolaraBloom", "SolaraSunRays", "SolaraColor" }

local function applyEffects()
	local enabled = controllers.SettingsController:Get("VisualEffects") ~= false
	for _, name in EFFECT_NAMES do
		local effect = Lighting:FindFirstChild(name)
		if effect and effect:IsA("PostEffect") then
			effect.Enabled = enabled
		end
	end
end

local function applyShadows()
	Lighting.GlobalShadows = controllers.SettingsController:Get("Shadows") ~= false
end

function GraphicsController:Init(allControllers)
	controllers = allControllers
end

function GraphicsController:Start()
	applyEffects()
	applyShadows()
	controllers.SettingsController.Changed:Connect(function(key)
		if key == "VisualEffects" then
			applyEffects()
		elseif key == "Shadows" then
			applyShadows()
		end
	end)
	-- Efektler istemci yüklendikten sonra çoğalırsa da tercihe uysun
	Lighting.ChildAdded:Connect(function(child)
		if table.find(EFFECT_NAMES, child.Name) then
			task.defer(applyEffects)
		end
	end)
end

return GraphicsController
