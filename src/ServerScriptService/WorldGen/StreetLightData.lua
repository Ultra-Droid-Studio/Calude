-- StreetLightData: ÜRETİLDİ — tools/streetlights_convert.py. Elle değiştirme; aracı yeniden çalıştır.
-- Kaynak: "Various Low-Poly Street Lights" — KMB3D, CC-BY-4.0 (https://sketchfab.com/3d-models/various-low-poly-street-lights-1173b0c4d9b0400bbeaafbee0e94ca59)
-- Değişiklik: lambalara ayrıldı, ortalandı, kol yola (−Z) bakacak şekilde döndürüldü.
-- Birim: metre; köken = direğin taban merkezi. PoleMin/Max, LampMin/Max: MeshPart sınır kutuları (köken göreli).
-- Offset: .glb dosyasında lambanın X kaydırması (içe aktarmada üst üste binmesinler diye).
return {
	Arm = { Kind = "Arm", Offset = 0.0, Triangles = 804,
		PoleMin = { -0.1667, 0.0000, -1.9010 }, PoleMax = { 0.1667, 4.9666, 0.1410 },
		LampMin = { -0.0987, 4.7002, -1.8667 }, LampMax = { 0.1001, 4.7358, -1.5431 } },
	Classic = { Kind = "Post", Offset = 3.0, Triangles = 1320,
		PoleMin = { -0.3398, 0.0000, -0.3598 }, PoleMax = { 0.3760, 5.2294, 0.3598 },
		LampMin = { -0.2094, 4.6689, -0.2092 }, LampMax = { 0.2089, 4.8586, 0.2092 } },
	Crook = { Kind = "Twin", Offset = 6.0, Triangles = 2410,
		PoleMin = { -0.8857, 0.0000, -0.3064 }, PoleMax = { 0.8929, 5.2536, 0.8893 },
		LampMin = { -0.7363, 4.3785, -0.1650 }, LampMax = { 0.7492, 4.4587, 0.7394 } },
	Double = { Kind = "Double", Offset = 9.0, Triangles = 1462,
		PoleMin = { -0.1667, 0.0000, -1.9135 }, PoleMax = { 0.1667, 4.9666, 1.8921 },
		LampMin = { -0.1019, 4.7002, -1.8791 }, LampMax = { 0.0987, 4.7358, 1.8577 } },
	Globe = { Kind = "Post", Offset = 12.0, Triangles = 925,
		PoleMin = { -0.2355, 0.0000, -0.2247 }, PoleMax = { 0.2370, 4.6638, 0.2247 },
		LampMin = { -0.2270, 4.6384, -0.2307 }, LampMax = { 0.2319, 5.0277, 0.2307 } },
	Lantern = { Kind = "Arm", Offset = 15.0, Triangles = 1204,
		PoleMin = { -0.3021, 0.0000, -1.5380 }, PoleMax = { 0.3021, 5.2536, 0.5035 },
		LampMin = { -0.1526, 4.3368, -1.3933 }, LampMax = { 0.1526, 4.7018, -1.0881 } },
	Twin = { Kind = "Twin", Offset = 18.0, Triangles = 1476,
		PoleMin = { -0.8970, 0.0000, -0.2410 }, PoleMax = { 0.9157, 5.2362, 0.2410 },
		LampMin = { -0.8342, 4.4357, -0.1740 }, LampMax = { 0.8529, 4.9749, 0.1740 } },
	TwinBar = { Kind = "Twin", Offset = 21.0, Triangles = 1330,
		PoleMin = { -1.1675, 0.0000, -0.3698 }, PoleMax = { 1.1743, 4.6895, 0.3698 },
		LampMin = { -1.1498, 4.6895, -0.3522 }, LampMax = { 1.1567, 4.7223, 0.3522 } },
}
