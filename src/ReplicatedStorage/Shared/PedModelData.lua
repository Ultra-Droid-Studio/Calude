-- PedModelData: tools/peds_convert.py tarafından üretildi (elle değiştirme).
-- Yaya modelleri (Microsoft Rocketbox, MIT): her biri tek deri (skinned) MeshPart + 20 kemik (Ped_<Id>_<Kemik>).
-- Ölçüler metre, dinlenme pozunda (A-pozu kollar): boy, bacak boyu (uyluk + baldır), kalça yüksekliği.
return {
	Bones = { "Pelvis", "Spine", "Spine1", "Spine2", "Neck", "Head", "LClavicle", "LUpperArm", "LForearm",
		"LHand", "RClavicle", "RUpperArm", "RForearm", "RHand", "LThigh", "LCalf", "LFoot", "RThigh", "RCalf", "RFoot" },
	Peds = {
		{ Id = "F01", Female = true, HeightM = 1.740, LegM = 0.827, PelvisM = 0.924, Triangles = 8966 },
		{ Id = "F02", Female = true, HeightM = 1.729, LegM = 0.827, PelvisM = 0.923, Triangles = 8640 },
		{ Id = "F03", Female = true, HeightM = 1.743, LegM = 0.827, PelvisM = 0.924, Triangles = 8438 },
		{ Id = "F04", Female = true, HeightM = 1.733, LegM = 0.827, PelvisM = 0.927, Triangles = 8270 },
		{ Id = "M01", Female = false, HeightM = 1.806, LegM = 0.796, PelvisM = 0.896, Triangles = 7435 },
		{ Id = "M02", Female = false, HeightM = 1.823, LegM = 0.796, PelvisM = 0.896, Triangles = 7448 },
		{ Id = "M03", Female = false, HeightM = 1.819, LegM = 0.796, PelvisM = 0.896, Triangles = 7810 },
		{ Id = "M04", Female = false, HeightM = 1.801, LegM = 0.796, PelvisM = 0.896, Triangles = 7326 },
		{ Id = "M05", Female = false, HeightM = 1.802, LegM = 0.796, PelvisM = 0.896, Triangles = 7164 },
		{ Id = "M06", Female = false, HeightM = 1.810, LegM = 0.796, PelvisM = 0.896, Triangles = 6950 },
	},
}
