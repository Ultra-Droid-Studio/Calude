-- CarModelConfig: oyundaki tüm otomobillerin 3D modelleri (oyuncunun sürdükleri de, NPC trafiği de).
-- Kaynak: kullanıcının verdiği 12 low-poly araba (cosmo-art "Low Poly Cars", itch.io). tools/cosmo_cars_convert.py
-- görünümü AYNEN korur (aynı üçgenler, aynı renkler) ve tek dosya yazar: assets/cars/SOLARA_Cars.glb.
-- Akış (Studio gerekmez): Open Cloud ile Model olarak yüklenir (numarası WorldGen/AssetIds.Cars) → sunucu açılışta
-- ModelAssetService ile indirip ReplicatedStorage.VehicleModels.<Ad> modellerini kurar. (Studio'da elle içe aktarılıp
-- ReplicatedStorage.VehicleModels'a konursa o kullanılır.) Model yoksa araçlar eski kutu görünümle çalışır.
--
-- Parça adları: <Ad>_<Rol>_<rrggbb> (renk adın içinde; oyun parçayı kendisi boyar), tekerlekler
-- <Ad>_Wheel_<FL|FR|RL|RR>_<Tire|Rim>_<rrggbb> (döner). Sadece GÖRÜNÜM değişir: fizik (şasi, yaylar, fizik
-- tekerleri, çarpışma kabuğu) VehicleDefinitions'tan aynen gelir; model fizikteki dingil mesafesine ölçeklenir.

return {
	Folder = "VehicleModels", -- ReplicatedStorage altında
	Credit = "Araba modelleri: cosmo-art (Low Poly Cars, itch.io)",

	-- Dosyadaki tüm modeller (yükleyici bu adlarla parçaları toplar)
	Models = {
		"Bastion", "Solano", "Vortex", "Strada", "Rossa", "Cresta",
		"Brava", "Furia", "Marlin", "Patrulla", "Chispa", "Mula",
	},

	-- VehicleDefinitions kimliği → model(ler). Birden fazlaysa araç doğarken rastgele seçilir. Oyuncunun sürdüğü
	-- araçlar da trafik de buradan.
	ByDefinition = {
		compact_pico = { "Chispa", "Solano" },
		sedan_vela = { "Solano", "Marlin" },
		sports_rayo = { "Vortex", "Strada", "Rossa", "Brava", "Furia" },
		suv_terra = { "Bastion", "Cresta" },
		pickup_mesa = { "Cresta", "Bastion" },
		van_porter = { "Mula" },
		utility_brisa = { "Mula" },
	},

	-- Sadece trafikte (NPC) görülen özel varyantlar: hangi tanımın sürüş ölçüleriyle, hangi olasılıkla
	TrafficVariants = {
		sedan_vela = { { Model = "Patrulla", Chance = 0.12 } },
	},

	-- Boyası değişmeyen modeller (polis siyah-beyazı); diğerlerinde Paint = aracın renk listesinden
	FixedPaint = { Patrulla = true },

	-- Rengi verilmeyen araçlarda (trafik, rastgele doğan araçlar) modelin KENDİ renginin seçilme olasılığı;
	-- kalanında aracın renk listesinden (VehicleDefinitions.Colors) bir renk
	OriginalPaintChance = 0.35,

	-- Paint2 (ikinci gövde tonu: ayna, kenar şeridi): "Darker" = boyanın koyusu, yoksa modelin kendi rengi
	Paint2Rule = { Brava = "Darker", Furia = "Darker", Chispa = "Darker" },

	-- Parça rolü → malzeme ve saydamlık. Renk parçanın adından gelir (Paint/Paint2 hariç).
	-- Işık rolleri araç ışık sistemiyle yanar: Headlight (gece), TailLight (gece + fren), ReverseLight (geri vites),
	-- IndicatorL/IndicatorR (sinyal / dörtlü).
	Roles = {
		Paint = { Material = Enum.Material.SmoothPlastic, Reflectance = 0.06, Shadow = true },
		Paint2 = { Material = Enum.Material.SmoothPlastic, Reflectance = 0.04, Shadow = true },
		Detail = { Material = Enum.Material.SmoothPlastic, Shadow = true },
		Glass = { Material = Enum.Material.Glass, Transparency = 0.25, Reflectance = 0.1 },
		Headlight = { Material = Enum.Material.SmoothPlastic, Light = "Headlight" },
		TailLight = { Material = Enum.Material.SmoothPlastic, Light = "TailLight" },
		ReverseLight = { Material = Enum.Material.SmoothPlastic, Light = "ReverseLight" },
		IndicatorL = { Material = Enum.Material.SmoothPlastic, Light = "IndicatorL" },
		IndicatorR = { Material = Enum.Material.SmoothPlastic, Light = "IndicatorR" },
		SirenRed = { Material = Enum.Material.SmoothPlastic },
		SirenBlue = { Material = Enum.Material.SmoothPlastic },
		Tire = { Material = Enum.Material.SmoothPlastic, Shadow = true },
		Rim = { Material = Enum.Material.Metal },
	},
}
