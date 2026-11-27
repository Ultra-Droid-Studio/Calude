-- CarModelConfig: dış 3D otomobil modelleri.
-- Kaynak: "LowPoly Cars" — Quaternius (https://quaternius.com), lisans CC0 1.0 (kamu malı; ticari kullanım serbest,
-- atıf zorunlu değil; jenerikte "Araba modelleri: Quaternius" yazılması önerilir).
--
-- Akış: tools/carpack_convert.py → assets/carpack/<Ad>.glb → Studio "Import 3D" → ReplicatedStorage.VehicleModels.<Ad>
-- (Model; içinde parça başına bir MeshPart: Paint, Paint2, Glass, Dark, Trim, Headlight, TailLight, SirenWhite,
-- SirenBlue, Wheel_FL_Tire, Wheel_FL_Rim, ...). Model yoksa araçlar eski kutu görünümle çalışır.
-- Sadece GÖRÜNÜM değişir: fizik (şasi, yaylar, fizik tekerleri, çarpışma kabuğu) VehicleDefinitions'tan aynen gelir.

return {
	Folder = "VehicleModels", -- ReplicatedStorage altında
	Credit = "Araba modelleri: Quaternius (CC0)",

	-- VehicleDefinitions kimliği → model(ler). Birden fazlaysa araç doğarken rastgele seçilir.
	ByDefinition = {
		compact_pico = { "NormalCar2" },
		sedan_vela = { "NormalCar1" },
		sports_rayo = { "SportsCar", "SportsCar2" },
		suv_terra = { "SUV" },
		-- pickup_mesa, van_porter, utility_brisa: pakette karşılığı yok → kutu görünüm
	},

	-- Sadece trafikte (NPC) görülen özel varyantlar: hangi tanımın sürüş ölçüleriyle, hangi olasılıkla
	TrafficVariants = {
		sedan_vela = { { Model = "Taxi", Chance = 0.15 } },
	},

	-- Orijinal görünümlü (dokulu) modeller: rolü olmayan parçalar ("Keep") ve Paint dışındaki roller içe aktarıldığı
	-- gibi kalır (renk, malzeme, doku). Tekerlekler yine Wheel_<FL|FR|RL|RR>_<Tire|Rim> adıyla bulunur ve döner.
	-- Yalnız "Paint" adlı parçalar aracın renk listesinden boyanır (FixedPaint değilse).
	Original = {},

	-- Boyası değişmeyen modeller (taksi sarısı, polis siyah-beyazı); diğerlerinde Paint = aracın renk listesinden
	FixedPaint = { Taxi = true, Cop = true },

	-- Paint2 (ikinci gövde rengi): "Darker" = boyanın koyusu, yoksa orijinal renk
	Paint2Rule = { SportsCar = "Darker" },

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

	-- Modellerin orijinal renkleri (tools/carpack_convert.py → assets/carpack/carpack.json, sRGB)
	Colors = {
		Cop = { Dark = Color3.fromRGB(31, 31, 31), Glass = Color3.fromRGB(53, 53, 53), Headlight = Color3.fromRGB(231, 165, 100), Paint = Color3.fromRGB(216, 216, 216), SirenBlue = Color3.fromRGB(65, 123, 231), SirenWhite = Color3.fromRGB(231, 231, 231), TailLight = Color3.fromRGB(231, 86, 77), Trim = Color3.fromRGB(124, 124, 124), Tire = Color3.fromRGB(31, 31, 31), Rim = Color3.fromRGB(124, 124, 124) },
		NormalCar1 = { Dark = Color3.fromRGB(31, 31, 31), Glass = Color3.fromRGB(53, 53, 53), Headlight = Color3.fromRGB(231, 165, 100), Paint = Color3.fromRGB(159, 194, 231), TailLight = Color3.fromRGB(231, 86, 77), Trim = Color3.fromRGB(124, 124, 124), Tire = Color3.fromRGB(31, 31, 31), Rim = Color3.fromRGB(124, 124, 124) },
		NormalCar2 = { Dark = Color3.fromRGB(31, 31, 31), Glass = Color3.fromRGB(53, 53, 53), Headlight = Color3.fromRGB(231, 165, 100), Paint = Color3.fromRGB(199, 216, 231), Paint2 = Color3.fromRGB(231, 231, 231), TailLight = Color3.fromRGB(231, 86, 77), Trim = Color3.fromRGB(124, 124, 124), Tire = Color3.fromRGB(31, 31, 31), Rim = Color3.fromRGB(124, 124, 124) },
		SUV = { Dark = Color3.fromRGB(31, 31, 31), Glass = Color3.fromRGB(53, 53, 53), Headlight = Color3.fromRGB(231, 165, 100), Paint = Color3.fromRGB(218, 218, 218), TailLight = Color3.fromRGB(231, 86, 77), Trim = Color3.fromRGB(124, 124, 124), Tire = Color3.fromRGB(31, 31, 31), Rim = Color3.fromRGB(124, 124, 124) },
		SportsCar = { Glass = Color3.fromRGB(53, 53, 53), Headlight = Color3.fromRGB(231, 204, 116), Paint = Color3.fromRGB(231, 156, 92), Paint2 = Color3.fromRGB(218, 147, 87), TailLight = Color3.fromRGB(231, 86, 77), Trim = Color3.fromRGB(124, 124, 124), Tire = Color3.fromRGB(31, 31, 31), Rim = Color3.fromRGB(124, 124, 124) },
		SportsCar2 = { Glass = Color3.fromRGB(53, 53, 53), Headlight = Color3.fromRGB(231, 165, 100), Paint = Color3.fromRGB(216, 216, 216), TailLight = Color3.fromRGB(231, 86, 77), Trim = Color3.fromRGB(110, 110, 110), Tire = Color3.fromRGB(31, 31, 31), Rim = Color3.fromRGB(110, 110, 110) },
		Taxi = { Dark = Color3.fromRGB(31, 31, 31), Glass = Color3.fromRGB(53, 53, 53), Headlight = Color3.fromRGB(231, 165, 100), Paint = Color3.fromRGB(231, 201, 67), TailLight = Color3.fromRGB(231, 86, 77), Trim = Color3.fromRGB(124, 124, 124), Tire = Color3.fromRGB(31, 31, 31), Rim = Color3.fromRGB(124, 124, 124) },
	},
}
