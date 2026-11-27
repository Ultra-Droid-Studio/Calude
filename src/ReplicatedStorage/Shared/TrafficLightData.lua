-- TrafficLightData: tools/trafficlights_convert.py tarafından üretildi (elle değiştirme).
-- Trafik ışığı modellerinin (Kenney City Builder Bits, CC0) ölçüleri, kaynak biriminde: direğin ayağı = (0, 0, 0),
-- yanan camlar -Z'ye bakar, kol/başlık +X'e uzanır. Oyun içe aktarılan parçaları bu ölçülerle kalibre eder
-- (içe aktarıcının ölçeği ve konumu önemli değil) ve StudsPerUnit ile büyütür.
return {
	StudsPerUnit = 16.0,
	Types = {
		A = {
			Min = { -0.0399, 0.0000, -0.1107 },
			Max = { 0.1346, 0.7295, 0.0399 },
			PoleMin = { -0.0301, 0.0000, -0.0301 },
			PoleMax = { 0.0809, 0.7213, 0.0301 },
			Lens = { Red = { -0.0000, 0.6874, -0.0972 }, Yellow = { -0.0000, 0.6214, -0.0972 }, Green = { -0.0000, 0.5553, -0.0972 } },
			-- parçaların sınır kutusu ortaları (kalibrasyon noktaları)
			PoleCenter = { 0.0254, 0.3607, 0.0000 }, RedCenter = { -0.0000, 0.6874, -0.0982 }, GreenCenter = { -0.0000, 0.5553, -0.0982 },
		},
		B = {
			Min = { -0.0398, 0.0000, -0.1107 },
			Max = { 0.2392, 0.9599, 0.0399 },
			PoleMin = { -0.0301, 0.0000, -0.0345 },
			PoleMax = { 0.2392, 0.9599, 0.0345 },
			Lens = { Red = { -0.0000, 0.6874, -0.0972 }, Yellow = { -0.0000, 0.6213, -0.0972 }, Green = { -0.0000, 0.5553, -0.0972 } },
			-- parçaların sınır kutusu ortaları (kalibrasyon noktaları)
			PoleCenter = { 0.1045, 0.4800, 0.0000 }, RedCenter = { -0.0000, 0.6874, -0.0983 }, GreenCenter = { -0.0000, 0.5553, -0.0983 },
		},
		C = {
			Min = { -0.0337, 0.0000, -0.1346 },
			Max = { 0.7641, 0.9695, 0.1370 },
			PoleMin = { -0.0301, 0.0000, -0.0809 },
			PoleMax = { 0.7641, 0.9305, 0.0301 },
			Lens = { Red = { 0.6640, 0.9274, -0.0772 }, Yellow = { 0.6640, 0.8614, -0.0772 }, Green = { 0.6640, 0.7953, -0.0772 } },
			-- parçaların sınır kutusu ortaları (kalibrasyon noktaları)
			PoleCenter = { 0.3670, 0.4652, -0.0254 }, RedCenter = { 0.6640, 0.9274, -0.0783 }, GreenCenter = { 0.6640, 0.7953, -0.0783 },
		},
	},
}
