-- CarModelConfig: dış 3D otomobil modelleri.
-- Modeller (orijinal görünüm: doku, malzeme ve renkler aynen; tools/car_prepare.py üçgenleri azaltır, logo ve
-- plakaları çıkarır, tekerlekleri ayırır):
--   Patrol — "Police car", Mateusz Woliński (Sketchfab), CC BY 4.0
--   Vento  — "(FREE) Porsche 911 Carrera 4S", Karol Miklas (Sketchfab), CC BY-SA 4.0 (değiştirilmiş hali de aynı lisansla)
-- Akış: assets/cars/<Ad>.glb → Studio "Import 3D" → ReplicatedStorage.VehicleModels.<Ad> (Model; parçalar:
-- Wheel_<FL|FR|RL|RR>_<Tire|Rim|...> tekerlekler (döner), Paint (Vento boyası, aracın rengini alır), Keep_* diğer her
-- şey (olduğu gibi)). Model yoksa araçlar eski kutu görünümle çalışır.
-- Sadece GÖRÜNÜM değişir: fizik (şasi, yaylar, fizik tekerleri, çarpışma kabuğu) VehicleDefinitions'tan aynen gelir.
-- (Eski Quaternius "LowPoly Cars" paketi kullanıcının isteğiyle kaldırıldı.)

return {
	Folder = "VehicleModels", -- ReplicatedStorage altında
	Credit = "Araba modelleri: Mateusz Woliński (CC BY 4.0), Karol Miklas (CC BY-SA 4.0)",

	-- VehicleDefinitions kimliği → model(ler). Birden fazlaysa araç doğarken rastgele seçilir. Oyuncunun sürdüğü
	-- araçlar da trafik de buradan. (suv_terra, pickup_mesa, van_porter, utility_brisa: model yok → kutu görünüm)
	ByDefinition = {
		compact_pico = { "Vento" },
		sedan_vela = { "Vento" },
		sports_rayo = { "Vento" },
	},

	-- Sadece trafikte (NPC) görülen özel varyantlar: hangi tanımın sürüş ölçüleriyle, hangi olasılıkla
	TrafficVariants = {
		sedan_vela = { { Model = "Patrol", Chance = 0.12 } },
	},

	-- Orijinal görünümlü (dokulu) modeller: rolü olmayan parçalar ("Keep") ve Paint dışındaki roller içe aktarıldığı
	-- gibi kalır (renk, malzeme, doku). Tekerlekler yine Wheel_<FL|FR|RL|RR>_<Tire|Rim> adıyla bulunur ve döner.
	-- Yalnız "Paint" adlı parçalar aracın renk listesinden boyanır (FixedPaint değilse).
	Original = { Patrol = true, Vento = true },

	-- Boyası değişmeyen modeller (taksi sarısı, polis siyah-beyazı); diğerlerinde Paint = aracın renk listesinden
	FixedPaint = { Patrol = true },

	-- Paint2 (ikinci gövde rengi): "Darker" = boyanın koyusu, yoksa orijinal renk
	Paint2Rule = {},

	-- Parça rolü → malzeme ve saydamlık
	Roles = {
		Paint = { Material = Enum.Material.SmoothPlastic, Reflectance = 0.06 },
		Paint2 = { Material = Enum.Material.SmoothPlastic, Reflectance = 0.06 },
		Glass = { Material = Enum.Material.Glass, Transparency = 0.15 },
		Dark = { Material = Enum.Material.SmoothPlastic },
		Trim = { Material = Enum.Material.Metal },
		Headlight = { Material = Enum.Material.SmoothPlastic },
		TailLight = { Material = Enum.Material.SmoothPlastic },
		SirenWhite = { Material = Enum.Material.SmoothPlastic },
		SirenBlue = { Material = Enum.Material.SmoothPlastic },
		Tire = { Material = Enum.Material.SmoothPlastic },
		Rim = { Material = Enum.Material.Metal },
	},

	-- Orijinal görünümlü modellerde sadece Paint rengi kullanılır (FixedPaint ya da renk verilmezse)
	Colors = {
		Vento = { Paint = Color3.fromRGB(168, 168, 168) }, -- kaynağın gümüş boyası
	},
}
