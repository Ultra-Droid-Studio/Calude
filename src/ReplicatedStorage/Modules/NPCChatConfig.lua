-- NPCChatConfig: yayalarla yapay zekâlı sohbet (Roblox TextGenerator; NPCChatService / Ambient/NPCChat).
-- Kişilik sunucuda yayanın tohumundan (seed) üretilir; istemci sadece tohum, cinsiyet ve konum gönderir.

return {
	Enabled = true,

	-- Etkileşim
	PromptKey = Enum.KeyCode.E,
	PromptGamepad = Enum.KeyCode.ButtonX,
	PromptDistance = 7, -- stud: "Konuş" istemi
	EndDistance = 16, -- stud: oyuncu bu kadar uzaklaşınca sohbet biter, yaya yürümeye devam eder
	IdleTimeout = 60, -- sn: mesaj yazılmazsa sohbet biter
	MaxMessageLength = 140, -- karakter (oyuncunun mesajı)
	BubbleSeconds = 9, -- cevap balonu görünür kalma süresi

	-- Sunucu sınırları (oyuncu başına): 3 hak, 4 sn'de bir dolar → dakikada ~15 mesaj
	RateCapacity = 3,
	RateRefillPerSecond = 0.25,
	GeneratorIdleSeconds = 300, -- kullanılmayan sohbet üretici (TextGenerator) bu süre sonra silinir
	MaxGenerators = 6, -- oyuncu başına aynı anda tutulan sohbet (yaya) sayısı

	-- Model ayarları (TextGenerator: Temperature 0.4–1.0, TopP 0.5–1.0)
	MaxTokens = 90,
	Temperature = 0.85,
	TopP = 0.9,
	MaxReplyLength = 260, -- karakter (uzun cevaplar kırpılır)

	-- Kişilik malzemesi
	FemaleNames = {
		"Elif", "Zeynep", "Defne", "Ayşe", "Selin", "Ece", "Melis", "Derya", "Sofía", "Valeria", "Lucía", "Camila",
		"İrem", "Naz", "Ceren", "Isabel", "Gül", "Pınar", "Marta", "Elena",
	},
	MaleNames = {
		"Mert", "Emre", "Can", "Burak", "Kerem", "Ahmet", "Ozan", "Deniz", "Carlos", "Diego", "Mateo", "Javier",
		"Tolga", "Barış", "Kaan", "Luis", "Andrés", "Murat", "Serkan", "Pablo",
	},
	Surnames = {
		"Yılmaz", "Kaya", "Demir", "Aydın", "Öztürk", "Arslan", "García", "Morales", "Navarro", "Ruiz", "Ortega", "Vega",
		"Şahin", "Koç", "Çelik", "Reyes", "Castro", "Doğan", "Polat", "Herrera",
	},
	Jobs = {
		"avukat", "muhasebeci", "emlakçı", "banka çalışanı", "mimar", "yazılımcı", "gazeteci", "doktor", "satış müdürü",
		"restoran işletmecisi", "otel müdürü", "reklamcı", "sigortacı", "fotoğrafçı", "öğretmen", "turizm rehberi",
		"tasarımcı", "müzik yapımcısı", "eczacı", "girişimci",
	},
	Traits = {
		"neşeli", "alaycı ama iyi niyetli", "biraz telaşlı", "sakin", "meraklı", "konuşkan", "kısa ve net konuşan",
		"esprili", "biraz kaygılı", "kendinden emin", "nazik", "romantik", "pratik", "dedikoducu", "iyimser",
		"hafif huysuz ama yardımsever",
	},
	Moods = {
		"keyfi yerinde", "biraz yorgun", "işe yetişmeye çalışıyor", "rahat bir gününde", "aklı bir işte",
		"az önce güzel bir haber almış", "kahve arıyor", "trafikten şikâyetçi",
	},

	-- Model yanıt vermezse / sohbet kapalı hesaplarda
	FallbackLines = {
		"Kusura bakma, şu an aklım başka yerde.",
		"Hmm, ne diyecektim... unuttum!",
		"Şu an biraz acelem var, sonra konuşalım mı?",
	},
	Greetings = {
		"Merhaba! Güzel bir gün, değil mi?",
		"Selam! Solara'da hayat hep hareketli.",
		"Merhaba, nasılsın?",
	},
}
