-- AnimationConfig: ÖZEL eylem animasyonları (yeme, içme, selamlama, araç binme...).
--
-- ÖNEMLİ — avatar kuralı:
--   Yürüme/koşma/zıplama/düşme animasyonlarını OYUNCUNUN KENDİ AVATARI belirler.
--   Roblox'un varsayılan "Animate" scripti, oyuncunun hesabındaki animasyon paketini
--   (ör. Ninja, Robot, Stylish) otomatik kullanır. Bu yüzden o scripti DEĞİŞTİRMİYORUZ.
--
-- Buradaki ID'ler, Animation Editor'de oluşturup Roblox'a yüklediğin animasyonlar olacak.
-- ID boş ("") ise AnimationController o animasyonu sessizce atlar (oyun bozulmaz).
-- R6 ve R15 için AYRI animasyon gerekir; iskeletler farklıdır.

local AnimationConfig = {}

AnimationConfig.Actions = {
	-- Sosyal (Aşama 5)
	Greet = { R15 = "", R6 = "", Looped = false, Priority = Enum.AnimationPriority.Action },
	TalkIdle = { R15 = "", R6 = "", Looped = true, Priority = Enum.AnimationPriority.Action },
	Listen = { R15 = "", R6 = "", Looped = true, Priority = Enum.AnimationPriority.Action },
	-- Tüketim (Aşama 7)
	Eat = { R15 = "", R6 = "", Looped = false, Priority = Enum.AnimationPriority.Action },
	Drink = { R15 = "", R6 = "", Looped = false, Priority = Enum.AnimationPriority.Action },
	-- Araçlar (Aşama 3)
	CarEnter = { R15 = "", R6 = "", Looped = false, Priority = Enum.AnimationPriority.Action2 },
	CarExit = { R15 = "", R6 = "", Looped = false, Priority = Enum.AnimationPriority.Action2 },
	DriveIdle = { R15 = "", R6 = "", Looped = true, Priority = Enum.AnimationPriority.Action },
	BikeRide = { R15 = "", R6 = "", Looped = true, Priority = Enum.AnimationPriority.Action },
	BikeLeanLeft = { R15 = "", R6 = "", Looped = true, Priority = Enum.AnimationPriority.Action2 },
	BikeLeanRight = { R15 = "", R6 = "", Looped = true, Priority = Enum.AnimationPriority.Action2 },
	-- Ekipman (Aşama 6)
	WeaponEquip = { R15 = "", R6 = "", Looped = false, Priority = Enum.AnimationPriority.Action },
	WeaponIdle = { R15 = "", R6 = "", Looped = true, Priority = Enum.AnimationPriority.Idle },
	Reload = { R15 = "", R6 = "", Looped = false, Priority = Enum.AnimationPriority.Action2 },
}

AnimationConfig.DefaultFadeTime = 0.18

return AnimationConfig
