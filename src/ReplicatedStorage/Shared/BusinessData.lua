-- BusinessData: şehirdeki işletmeler (Şehir genişletme, aşama 2). ÜRETİLDİ: tools/plan_businesses.py
-- Elle düzenlenebilir (isim, tür, renk, yazı tipi); aracı yeniden çalıştırmak elle yapılan değişiklikleri siler.
-- Lot = MapData arsa kimliği (harita değişmez). Poi = mevcut önemli yer (varsa). Map = haritada / GPS'te görünür.
-- Type: Businesses.Types'taki tür. Font: Enum.Font adı. Primary/Secondary: tabela/tente ve ayrıntı rengi.
-- Sign: tabela biçimi (Box | Letters | Blade | Awning | Fascia). Unit = "Ground": ofis/apartman binasının zemin
-- kat dükkânı (Solara Centro, aşama 3).
return {
	{ Lot = 1, Type = "fashion", Name = "Atelier Solara", Map = false, Font = "Ubuntu", Primary = { 230, 120, 150 }, Secondary = { 255, 255, 255 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 3, Type = "pharmacy", Name = "VitaPlus Pharmacy", Map = true, Font = "Roboto", Primary = { 80, 170, 90 }, Secondary = { 255, 255, 255 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 6, Type = "sports", Name = "Gol Sports", Map = false, Font = "Kalam", Primary = { 120, 90, 170 }, Secondary = { 255, 230, 120 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 8, Type = "salon", Name = "Studio Cabello", Map = false, Font = "Oswald", Primary = { 240, 160, 60 }, Secondary = { 40, 40, 50 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 9, Type = "bookcafe", Name = "Lectura Café", Map = false, Font = "Merriweather", Primary = { 90, 160, 110 }, Secondary = { 255, 250, 240 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 11, Type = "homegoods", Name = "Casa Clara Home", Map = false, Font = "Ubuntu", Primary = { 200, 70, 70 }, Secondary = { 250, 240, 220 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 14, Type = "internetcafe", Name = "Pixel Lounge", Map = true, Font = "Sarpanch", Primary = { 40, 220, 200 }, Secondary = { 255, 70, 200 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 16, Type = "florist", Name = "Lirio Flowers", Map = false, Font = "TitilliumWeb", Primary = { 230, 120, 150 }, Secondary = { 255, 255, 255 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 17, Type = "stationery", Name = "Papel & Tinta", Map = false, Font = "PatrickHand", Primary = { 120, 90, 170 }, Secondary = { 255, 230, 120 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 19, Type = "music", Name = "Ritmo Music", Map = false, Font = "RobotoCondensed", Primary = { 240, 160, 60 }, Secondary = { 40, 40, 50 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 22, Type = "fashion", Name = "Urban Palm", Map = false, Font = "Highway", Primary = { 90, 160, 110 }, Secondary = { 255, 250, 240 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 24, Type = "cosmetics", Name = "Glow Theory", Map = false, Font = "JosefinSans", Primary = { 200, 70, 70 }, Secondary = { 250, 240, 220 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 25, Type = "restaurant", Name = "Mareas", Map = true, Font = "Bodoni", Primary = { 60, 50, 45 }, Secondary = { 230, 170, 90 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 27, Type = "fashion", Name = "Seda & Sal", Map = false, Font = "Kalam", Primary = { 250, 200, 180 }, Secondary = { 90, 60, 50 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 30, Type = "cosmetics", Name = "Aroma & Piel", Map = false, Font = "AmaticSC", Primary = { 40, 60, 90 }, Secondary = { 240, 200, 120 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 32, Type = "phonerepair", Name = "Pantalla Fix", Map = false, Font = "DenkOne", Primary = { 90, 160, 110 }, Secondary = { 255, 250, 240 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 33, Type = "electronics", Name = "Voltio Electronics", Map = false, Font = "Garamond", Primary = { 50, 140, 160 }, Secondary = { 250, 240, 220 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 39, Type = "fashion", Name = "Moda Brisa", Map = false, Font = "Garamond", Primary = { 70, 90, 110 }, Secondary = { 230, 230, 230 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 45, Type = "electronics", Name = "Neon Tech", Map = false, Font = "Nunito", Primary = { 230, 120, 150 }, Secondary = { 255, 255, 255 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 47, Type = "fastfood", Name = "Grill Shack", Poi = "fastfood_13", Map = true, Font = "Bangers", Primary = { 255, 92, 150 }, Secondary = { 255, 230, 90 }, Sign = "Box" }, -- centro / avenue
	{ Lot = 50, Type = "travel", Name = "Bluewater Trips", Map = false, Font = "TitilliumWeb", Primary = { 200, 70, 70 }, Secondary = { 250, 240, 220 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 52, Type = "general", Name = "Centro General Store", Poi = "general_15", Map = true, Font = "Oswald", Primary = { 70, 100, 150 }, Secondary = { 240, 240, 240 }, Sign = "Box" }, -- centro / avenue
	{ Lot = 53, Type = "jewelry", Name = "Brillo", Map = false, Font = "AmaticSC", Primary = { 120, 90, 170 }, Secondary = { 255, 230, 120 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 55, Type = "shoes", Name = "Huella Shoes", Map = false, Font = "DenkOne", Primary = { 240, 160, 60 }, Secondary = { 40, 40, 50 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 64, Type = "jewelry", Name = "Oro Fino", Map = false, Font = "Merriweather", Primary = { 50, 140, 160 }, Secondary = { 250, 240, 220 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 66, Type = "watches", Name = "Reloj Real", Map = false, Font = "Fondamento", Primary = { 70, 90, 110 }, Secondary = { 230, 230, 230 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 68, Type = "fashion", Name = "Northshore Apparel", Map = false, Font = "PatrickHand", Primary = { 250, 200, 180 }, Secondary = { 90, 60, 50 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 69, Type = "cafe", Name = "Brew & Bay Café", Poi = "cafe_11", Map = true, Font = "AmaticSC", Primary = { 110, 72, 50 }, Secondary = { 240, 226, 200 }, Sign = "Blade" }, -- centro / avenue
	{ Lot = 71, Type = "optics", Name = "Vista Clara Optics", Map = false, Font = "TitilliumWeb", Primary = { 40, 60, 90 }, Secondary = { 240, 200, 120 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 82, Type = "supermarket", Name = "SolMart Supermarket", Poi = "supermarket_9", Map = true, Font = "Ubuntu", Primary = { 230, 70, 50 }, Secondary = { 255, 255, 255 }, Sign = "Box" }, -- centro / avenue
	{ Lot = 84, Type = "cafe", Name = "Daydream Espresso", Map = true, Font = "JosefinSans", Primary = { 110, 72, 50 }, Secondary = { 240, 226, 200 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 87, Type = "cosmetics", Name = "Belleza Sol", Map = false, Font = "Fondamento", Primary = { 90, 160, 110 }, Secondary = { 255, 250, 240 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 98, Type = "books", Name = "Margin Notes", Map = false, Font = "Michroma", Primary = { 230, 120, 150 }, Secondary = { 255, 255, 255 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 100, Type = "sports", Name = "Peak Gear", Map = false, Font = "Highway", Primary = { 50, 140, 160 }, Secondary = { 250, 240, 220 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 101, Type = "phonerepair", Name = "iRepair Centro", Map = false, Font = "PatrickHand", Primary = { 200, 70, 70 }, Secondary = { 250, 240, 220 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 103, Type = "travel", Name = "Rumbo Travel", Map = false, Font = "RobotoCondensed", Primary = { 70, 90, 110 }, Secondary = { 230, 230, 230 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 117, Type = "watches", Name = "Tempo Watches", Map = false, Font = "Michroma", Primary = { 250, 200, 180 }, Secondary = { 90, 60, 50 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 118, Type = "restaurant", Name = "Trattoria Luna", Poi = "restaurant_12", Map = true, Font = "Bodoni", Primary = { 30, 40, 60 }, Secondary = { 220, 180, 110 }, Sign = "Letters" }, -- centro / street
	{ Lot = 119, Type = "fashion", Name = "Linea Mar", Map = false, Font = "JosefinSans", Primary = { 230, 120, 150 }, Secondary = { 255, 255, 255 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 128, Type = "photo", Name = "Click Solara", Map = false, Font = "Michroma", Primary = { 40, 60, 90 }, Secondary = { 240, 200, 120 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 131, Type = "shoes", Name = "Stride Bay", Map = false, Font = "Ubuntu", Primary = { 120, 90, 170 }, Secondary = { 255, 230, 120 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 136, Type = "salon", Name = "Shear Bliss", Map = false, Font = "JosefinSans", Primary = { 120, 90, 170 }, Secondary = { 255, 230, 120 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 138, Type = "gallery", Name = "Galería Norte", Map = false, Font = "Bodoni", Primary = { 240, 160, 60 }, Secondary = { 40, 40, 50 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 141, Type = "books", Name = "Libro Libre", Map = false, Font = "Bodoni", Primary = { 50, 140, 160 }, Secondary = { 250, 240, 220 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 146, Type = "gallery", Name = "Studio Arena", Map = false, Font = "Nunito", Primary = { 40, 60, 90 }, Secondary = { 240, 200, 120 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 147, Type = "electronics", Name = "Pixelpoint", Map = false, Font = "AmaticSC", Primary = { 250, 200, 180 }, Secondary = { 90, 60, 50 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 154, Type = "kids", Name = "Pequeño Mundo", Map = false, Font = "Fondamento", Primary = { 50, 140, 160 }, Secondary = { 250, 240, 220 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 156, Type = "minimarket", Name = "Corner 24", Poi = "convenience_10", Map = true, Font = "GothamBlack", Primary = { 235, 90, 40 }, Secondary = { 255, 255, 255 }, Sign = "Box" }, -- centro / street
	{ Lot = 162, Type = "electronics", Name = "Circuito", Map = false, Font = "Bodoni", Primary = { 70, 90, 110 }, Secondary = { 230, 230, 230 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 163, Type = "optics", Name = "Focus Point", Map = false, Font = "Garamond", Primary = { 240, 160, 60 }, Secondary = { 40, 40, 50 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 165, Type = "fastfood", Name = "Pizza Porto", Poi = "fastfood_14", Map = true, Font = "LuckiestGuy", Primary = { 250, 180, 30 }, Secondary = { 200, 40, 40 }, Sign = "Box" }, -- centro / avenue
	{ Lot = 168, Type = "bookcafe", Name = "Chapter One", Map = false, Font = "Kalam", Primary = { 40, 60, 90 }, Secondary = { 240, 200, 120 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 170, Type = "homegoods", Name = "Nido Interiors", Map = false, Font = "Oswald", Primary = { 90, 160, 110 }, Secondary = { 255, 250, 240 }, Sign = "Fascia", Unit = "Ground" }, -- centro / avenue
	{ Lot = 171, Type = "boutique", Name = "Lino & Seda", Map = false, Font = "Highway", Primary = { 90, 160, 110 }, Secondary = { 255, 250, 240 }, Sign = "Box" }, -- costa / street
	{ Lot = 177, Type = "surf", Name = "Offshore Boards", Map = false, Font = "JosefinSans", Primary = { 200, 70, 70 }, Secondary = { 250, 240, 220 }, Sign = "Box" }, -- costa / street
	{ Lot = 188, Type = "restaurant", Name = "Salt & Ember", Map = true, Font = "JosefinSans", Primary = { 20, 90, 110 }, Secondary = { 250, 240, 220 }, Sign = "Letters" }, -- costa / avenue
	{ Lot = 192, Type = "salon", Name = "Glow Studio", Map = false, Font = "Merriweather", Primary = { 50, 140, 160 }, Secondary = { 250, 240, 220 }, Sign = "Box" }, -- costa / street
	{ Lot = 198, Type = "shoes", Name = "Sole Coast", Map = false, Font = "Ubuntu", Primary = { 120, 90, 170 }, Secondary = { 255, 230, 120 }, Sign = "Box" }, -- costa / avenue
	{ Lot = 199, Type = "pharmacy", Name = "Farmacia Brisa", Map = true, Font = "Nunito", Primary = { 30, 160, 110 }, Secondary = { 255, 255, 255 }, Sign = "Box" }, -- costa / avenue
	{ Lot = 204, Type = "fastfood", Name = "Taco Ola", Poi = "fastfood_23", Map = true, Font = "FredokaOne", Primary = { 230, 60, 40 }, Secondary = { 255, 210, 60 }, Sign = "Box" }, -- costa / avenue
	{ Lot = 210, Type = "tattoo", Name = "Tinta Azul Tattoo", Map = false, Font = "AmaticSC", Primary = { 40, 60, 90 }, Secondary = { 240, 200, 120 }, Sign = "Box" }, -- costa / street
	{ Lot = 211, Type = "cafe", Name = "Tide Café", Poi = "cafe_20", Map = true, Font = "Kalam", Primary = { 40, 120, 130 }, Secondary = { 250, 240, 220 }, Sign = "Blade" }, -- costa / street
	{ Lot = 215, Type = "optics", Name = "Clearview Optics", Map = false, Font = "DenkOne", Primary = { 90, 160, 110 }, Secondary = { 255, 250, 240 }, Sign = "Box" }, -- costa / avenue
	{ Lot = 222, Type = "photo", Name = "Snapshot Studio", Map = false, Font = "Fondamento", Primary = { 70, 90, 110 }, Secondary = { 230, 230, 230 }, Sign = "Box" }, -- costa / street
	{ Lot = 225, Type = "florist", Name = "Petal & Stem", Map = false, Font = "PatrickHand", Primary = { 250, 200, 180 }, Secondary = { 90, 60, 50 }, Sign = "Box" }, -- costa / street
	{ Lot = 229, Type = "restaurant", Name = "Casa Coral", Poi = "restaurant_21", Map = true, Font = "Garamond", Primary = { 120, 40, 40 }, Secondary = { 240, 220, 190 }, Sign = "Letters" }, -- costa / street
	{ Lot = 232, Type = "gelato", Name = "Helados Nube", Map = false, Font = "Bodoni", Primary = { 70, 90, 110 }, Secondary = { 230, 230, 230 }, Sign = "Box" }, -- costa / street
	{ Lot = 237, Type = "bakery", Name = "Miga & Co.", Map = true, Font = "Kalam", Primary = { 150, 82, 52 }, Secondary = { 244, 214, 170 }, Sign = "Awning" }, -- costa / street
	{ Lot = 242, Type = "jewelry", Name = "Gold Coast Jewels", Map = false, Font = "Kalam", Primary = { 250, 200, 180 }, Secondary = { 90, 60, 50 }, Sign = "Box" }, -- costa / street
	{ Lot = 244, Type = "gallery", Name = "Blue Hour Gallery", Map = false, Font = "Nunito", Primary = { 230, 120, 150 }, Secondary = { 255, 255, 255 }, Sign = "Box" }, -- costa / avenue
	{ Lot = 245, Type = "minimarket", Name = "Beach Stop 24", Poi = "convenience_22", Map = true, Font = "Oswald", Primary = { 30, 140, 200 }, Secondary = { 255, 230, 80 }, Sign = "Box" }, -- costa / street
	{ Lot = 247, Type = "cafe", Name = "Brisa Coffee", Map = true, Font = "Fondamento", Primary = { 200, 120, 140 }, Secondary = { 255, 246, 236 }, Sign = "Blade" }, -- costa / avenue
	{ Lot = 254, Type = "greengrocer", Name = "Verano Grocers", Poi = "grocery_24", Map = true, Font = "Kalam", Primary = { 70, 150, 60 }, Secondary = { 255, 220, 80 }, Sign = "Awning" }, -- costa / avenue
	{ Lot = 257, Type = "travel", Name = "Island Hop Tours", Map = false, Font = "Garamond", Primary = { 240, 160, 60 }, Secondary = { 40, 40, 50 }, Sign = "Box" }, -- costa / avenue
	{ Lot = 274, Type = "records", Name = "Vinyl Tide", Map = false, Font = "TitilliumWeb", Primary = { 200, 70, 70 }, Secondary = { 250, 240, 220 }, Sign = "Box" }, -- costa / street
	{ Lot = 279, Type = "sports", Name = "Court & Coast", Map = false, Font = "Michroma", Primary = { 230, 120, 150 }, Secondary = { 255, 255, 255 }, Sign = "Box" }, -- costa / street
	{ Lot = 280, Type = "fastfood", Name = "Wave Wings", Map = true, Font = "LuckiestGuy", Primary = { 255, 92, 150 }, Secondary = { 255, 230, 90 }, Sign = "Box" }, -- costa / avenue
	{ Lot = 281, Type = "boutique", Name = "Coastline Threads", Map = false, Font = "Highway", Primary = { 50, 140, 160 }, Secondary = { 250, 240, 220 }, Sign = "Box" }, -- costa / street
	{ Lot = 311, Type = "restaurant", Name = "Marina Grill", Poi = "restaurant_26", Map = true, Font = "Merriweather", Primary = { 20, 90, 110 }, Secondary = { 250, 240, 220 }, Sign = "Letters" }, -- costa / avenue
	{ Lot = 313, Type = "general", Name = "Harbor Supplies", Poi = "general_28", Map = true, Font = "RobotoCondensed", Primary = { 150, 110, 60 }, Secondary = { 250, 240, 220 }, Sign = "Box" }, -- costa / avenue
	{ Lot = 459, Type = "minimarket", Name = "Heights Mini Mart", Poi = "convenience_30", Map = true, Font = "RobotoCondensed", Primary = { 200, 30, 60 }, Secondary = { 255, 255, 255 }, Sign = "Box" }, -- palm / street
	{ Lot = 597, Type = "cafe", Name = "Morning Palm Café", Poi = "cafe_31", Map = true, Font = "JosefinSans", Primary = { 200, 120, 140 }, Secondary = { 255, 246, 236 }, Sign = "Blade" }, -- palm / street
	{ Lot = 640, Type = "pharmacy", Name = "SolaCare Pharmacy", Map = true, Font = "JosefinSans", Primary = { 40, 120, 200 }, Secondary = { 255, 255, 255 }, Sign = "Box" }, -- riverside / avenue
	{ Lot = 667, Type = "gunshop", Name = "Gulfline Outfitters", Map = true, Font = "Oswald", Primary = { 40, 44, 48 }, Secondary = { 200, 150, 60 }, Sign = "Box" }, -- riverside / street
	{ Lot = 676, Type = "hardware", Name = "Ferretería Faro", Map = false, Font = "AmaticSC", Primary = { 230, 120, 150 }, Secondary = { 255, 255, 255 }, Sign = "Box" }, -- riverside / street
	{ Lot = 679, Type = "dollarstore", Name = "Todo Mil", Map = true, Font = "LuckiestGuy", Primary = { 255, 200, 30 }, Secondary = { 220, 30, 120 }, Sign = "Box" }, -- riverside / street
	{ Lot = 688, Type = "cafe", Name = "Café Malecón", Map = true, Font = "AmaticSC", Primary = { 60, 60, 60 }, Secondary = { 230, 200, 150 }, Sign = "Blade" }, -- riverside / avenue
	{ Lot = 691, Type = "greengrocer", Name = "Verde Fresco", Map = true, Font = "FredokaOne", Primary = { 40, 110, 70 }, Secondary = { 250, 160, 50 }, Sign = "Awning" }, -- riverside / street
	{ Lot = 694, Type = "tattoo", Name = "Inkwave Studio", Map = false, Font = "RobotoCondensed", Primary = { 90, 160, 110 }, Secondary = { 255, 250, 240 }, Sign = "Box" }, -- riverside / street
	{ Lot = 695, Type = "bakkal", Name = "Bodega Paloma", Map = true, Font = "Highway", Primary = { 50, 90, 160 }, Secondary = { 255, 220, 90 }, Sign = "Blade" }, -- riverside / street
	{ Lot = 701, Type = "laundry", Name = "Spin City Wash", Map = false, Font = "Merriweather", Primary = { 70, 90, 110 }, Secondary = { 230, 230, 230 }, Sign = "Box" }, -- riverside / street
	{ Lot = 703, Type = "minimarket", Name = "QuickStop Riverside", Poi = "convenience_37", Map = true, Font = "Ubuntu", Primary = { 60, 170, 90 }, Secondary = { 255, 255, 255 }, Sign = "Box" }, -- riverside / street
	{ Lot = 704, Type = "tailor", Name = "Hilo Fino Tailor", Map = false, Font = "Ubuntu", Primary = { 250, 200, 180 }, Secondary = { 90, 60, 50 }, Sign = "Box" }, -- riverside / street
	{ Lot = 709, Type = "phonerepair", Name = "FixPoint Phones", Map = false, Font = "TitilliumWeb", Primary = { 120, 90, 170 }, Secondary = { 255, 230, 120 }, Sign = "Box" }, -- riverside / street
	{ Lot = 710, Type = "bakery", Name = "Sunrise Bakehouse", Map = true, Font = "Kalam", Primary = { 196, 132, 64 }, Secondary = { 250, 236, 210 }, Sign = "Awning" }, -- riverside / street
	{ Lot = 721, Type = "florist", Name = "Jardín Rosa", Map = false, Font = "Highway", Primary = { 70, 90, 110 }, Secondary = { 230, 230, 230 }, Sign = "Box" }, -- riverside / street
	{ Lot = 727, Type = "bike", Name = "Spoke Coast Bikes", Map = false, Font = "Kalam", Primary = { 230, 120, 150 }, Secondary = { 255, 255, 255 }, Sign = "Box" }, -- riverside / street
	{ Lot = 728, Type = "bakkal", Name = "Don Tito's", Map = true, Font = "PatrickHand", Primary = { 180, 60, 50 }, Secondary = { 250, 236, 200 }, Sign = "Blade" }, -- riverside / street
	{ Lot = 729, Type = "photo", Name = "Lente Dorada", Map = false, Font = "Oswald", Primary = { 50, 140, 160 }, Secondary = { 250, 240, 220 }, Sign = "Box" }, -- riverside / avenue
	{ Lot = 732, Type = "internetcafe", Name = "Byte Harbor", Map = true, Font = "Arcade", Primary = { 120, 80, 255 }, Secondary = { 60, 230, 255 }, Sign = "Letters" }, -- riverside / avenue
	{ Lot = 734, Type = "barber", Name = "Fade Street Barbers", Map = false, Font = "Nunito", Primary = { 200, 70, 70 }, Secondary = { 250, 240, 220 }, Sign = "Box" }, -- riverside / avenue
	{ Lot = 735, Type = "greengrocer", Name = "Riverside Grocery", Poi = "grocery_33", Map = true, Font = "IndieFlower", Primary = { 120, 180, 60 }, Secondary = { 200, 60, 40 }, Sign = "Awning" }, -- riverside / street
	{ Lot = 739, Type = "diner", Name = "Old Mill Diner", Poi = "restaurant_36", Map = true, Font = "Highway", Primary = { 200, 40, 50 }, Secondary = { 240, 240, 240 }, Sign = "Letters" }, -- riverside / street
	{ Lot = 740, Type = "records", Name = "Disco Sol Records", Map = false, Font = "DenkOne", Primary = { 50, 140, 160 }, Secondary = { 250, 240, 220 }, Sign = "Box" }, -- riverside / street
	{ Lot = 750, Type = "pets", Name = "Patitas Pet Shop", Map = false, Font = "Fondamento", Primary = { 240, 160, 60 }, Secondary = { 40, 40, 50 }, Sign = "Box" }, -- riverside / avenue
	{ Lot = 751, Type = "bakery", Name = "Pan del Puerto", Map = true, Font = "PatrickHand", Primary = { 232, 150, 120 }, Secondary = { 255, 244, 230 }, Sign = "Awning" }, -- riverside / street
	{ Lot = 753, Type = "books", Name = "Página Books", Map = false, Font = "Michroma", Primary = { 200, 70, 70 }, Secondary = { 250, 240, 220 }, Sign = "Box" }, -- riverside / street
	{ Lot = 754, Type = "shoes", Name = "Zapatería Mar", Map = false, Font = "PatrickHand", Primary = { 40, 60, 90 }, Secondary = { 240, 200, 120 }, Sign = "Box" }, -- riverside / street
	{ Lot = 756, Type = "music", Name = "Strings & Drums", Map = false, Font = "JosefinSans", Primary = { 250, 200, 180 }, Secondary = { 90, 60, 50 }, Sign = "Box" }, -- riverside / street
	{ Lot = 808, Type = "general", Name = "Pinebrook General Store", Poi = "general_48", Map = true, Font = "DenkOne", Primary = { 60, 130, 120 }, Secondary = { 255, 255, 255 }, Sign = "Box" }, -- pinebrook / street
	{ Lot = 814, Type = "diner", Name = "Sierra Diner", Poi = "restaurant_50", Map = true, Font = "PermanentMarker", Primary = { 40, 150, 170 }, Secondary = { 250, 220, 120 }, Sign = "Letters" }, -- pinebrook / country
	{ Lot = 919, Type = "bike", Name = "Rueda Bike Shop", Map = false, Font = "JosefinSans", Primary = { 40, 60, 90 }, Secondary = { 240, 200, 120 }, Sign = "Box" }, -- vista / street
	{ Lot = 920, Type = "bakkal", Name = "Tienda Rosita", Map = true, Font = "Ubuntu", Primary = { 210, 140, 40 }, Secondary = { 40, 40, 40 }, Sign = "Blade" }, -- vista / street
	{ Lot = 922, Type = "travel", Name = "Viajes Brisa", Map = false, Font = "Oswald", Primary = { 70, 90, 110 }, Secondary = { 230, 230, 230 }, Sign = "Box" }, -- vista / street
	{ Lot = 923, Type = "toys", Name = "Toy Lagoon", Map = false, Font = "RobotoCondensed", Primary = { 50, 140, 160 }, Secondary = { 250, 240, 220 }, Sign = "Box" }, -- vista / street
	{ Lot = 924, Type = "fastfood", Name = "Pollo Rayo", Map = true, Font = "FredokaOne", Primary = { 250, 180, 30 }, Secondary = { 200, 40, 40 }, Sign = "Box" }, -- vista / street
	{ Lot = 925, Type = "diner", Name = "Route 1 Diner", Poi = "restaurant_55", Map = true, Font = "Oswald", Primary = { 30, 60, 110 }, Secondary = { 240, 90, 80 }, Sign = "Letters" }, -- vista / street
	{ Lot = 926, Type = "pets", Name = "Pet Palma", Map = false, Font = "Highway", Primary = { 240, 160, 60 }, Secondary = { 40, 40, 50 }, Sign = "Box" }, -- vista / street
	{ Lot = 927, Type = "minimarket", Name = "Mini Sol 24", Map = true, Font = "GothamBlack", Primary = { 60, 170, 90 }, Secondary = { 255, 255, 255 }, Sign = "Box" }, -- vista / street
	{ Lot = 929, Type = "laundry", Name = "Lavandería Clara", Map = false, Font = "TitilliumWeb", Primary = { 250, 200, 180 }, Secondary = { 90, 60, 50 }, Sign = "Box" }, -- vista / street
	{ Lot = 934, Type = "cafe", Name = "Peak Café", Poi = "cafe_54", Map = true, Font = "Fondamento", Primary = { 60, 60, 60 }, Secondary = { 230, 200, 150 }, Sign = "Blade" }, -- vista / street
	{ Lot = 935, Type = "bakery", Name = "Dulce Harina", Map = true, Font = "Merriweather", Primary = { 150, 82, 52 }, Secondary = { 244, 214, 170 }, Sign = "Awning" }, -- vista / street
	{ Lot = 936, Type = "barber", Name = "Old Razor", Map = false, Font = "Merriweather", Primary = { 240, 160, 60 }, Secondary = { 40, 40, 50 }, Sign = "Box" }, -- vista / street
	{ Lot = 937, Type = "barber", Name = "Clipper Bay", Map = false, Font = "Nunito", Primary = { 120, 90, 170 }, Secondary = { 255, 230, 120 }, Sign = "Box" }, -- vista / street
	{ Lot = 939, Type = "bike", Name = "Pedal Palm", Map = false, Font = "Bodoni", Primary = { 90, 160, 110 }, Secondary = { 255, 250, 240 }, Sign = "Box" }, -- vista / street
	{ Lot = 940, Type = "phonerepair", Name = "Signal Repair", Map = false, Font = "Nunito", Primary = { 250, 200, 180 }, Secondary = { 90, 60, 50 }, Sign = "Box" }, -- vista / street
	{ Lot = 941, Type = "phonerepair", Name = "Celular Rápido", Map = false, Font = "Kalam", Primary = { 200, 70, 70 }, Secondary = { 250, 240, 220 }, Sign = "Box" }, -- vista / street
	{ Lot = 942, Type = "pharmacy", Name = "Farmacia Coral", Map = true, Font = "TitilliumWeb", Primary = { 20, 150, 160 }, Secondary = { 240, 250, 250 }, Sign = "Box" }, -- vista / street
	{ Lot = 945, Type = "optics", Name = "Lens Bay", Map = false, Font = "Michroma", Primary = { 120, 90, 170 }, Secondary = { 255, 230, 120 }, Sign = "Box" }, -- vista / street
	{ Lot = 946, Type = "greengrocer", Name = "Fruta Viva", Map = true, Font = "PatrickHand", Primary = { 150, 190, 70 }, Secondary = { 90, 50, 30 }, Sign = "Awning" }, -- vista / street
	{ Lot = 947, Type = "salon", Name = "Rizos Beauty", Map = false, Font = "PatrickHand", Primary = { 230, 120, 150 }, Secondary = { 255, 255, 255 }, Sign = "Box" }, -- vista / street
	{ Lot = 948, Type = "supermarket", Name = "Norte Market", Poi = "supermarket_53", Map = true, Font = "GothamBlack", Primary = { 70, 170, 80 }, Secondary = { 255, 255, 255 }, Sign = "Box" }, -- vista / street
	{ Lot = 949, Type = "bakkal", Name = "Abasto Luna", Map = true, Font = "PatrickHand", Primary = { 40, 120, 90 }, Secondary = { 250, 240, 210 }, Sign = "Blade" }, -- vista / street
	{ Lot = 951, Type = "books", Name = "Dog-Ear Books", Map = false, Font = "Garamond", Primary = { 90, 160, 110 }, Secondary = { 255, 250, 240 }, Sign = "Box" }, -- vista / street
	{ Lot = 952, Type = "pets", Name = "Bark & Bay", Map = false, Font = "DenkOne", Primary = { 70, 90, 110 }, Secondary = { 230, 230, 230 }, Sign = "Box" }, -- vista / street
	{ Lot = 953, Type = "optics", Name = "Óptica Mirada", Map = false, Font = "AmaticSC", Primary = { 200, 70, 70 }, Secondary = { 250, 240, 220 }, Sign = "Box" }, -- vista / street
	{ Lot = 954, Type = "general", Name = "Norte Hardware", Poi = "general_56", Map = true, Font = "Ubuntu", Primary = { 170, 70, 60 }, Secondary = { 250, 240, 220 }, Sign = "Box" }, -- vista / street
	{ Lot = 957, Type = "dollarstore", Name = "Casa 99", Map = true, Font = "FredokaOne", Primary = { 240, 60, 140 }, Secondary = { 60, 200, 240 }, Sign = "Box" }, -- vista / street
	{ Lot = 958, Type = "books", Name = "Tidewater Books", Map = false, Font = "Ubuntu", Primary = { 40, 60, 90 }, Secondary = { 240, 200, 120 }, Sign = "Box" }, -- vista / street
	{ Lot = 1070, Type = "gelato", Name = "Gelato Brisa", Map = false, Font = "Bodoni", Primary = { 50, 140, 160 }, Secondary = { 250, 240, 220 }, Sign = "Box" }, -- coral / street
	{ Lot = 1071, Type = "surf", Name = "Swell Surf Shop", Map = false, Font = "JosefinSans", Primary = { 230, 120, 150 }, Secondary = { 255, 255, 255 }, Sign = "Box" }, -- coral / street
	{ Lot = 1073, Type = "gallery", Name = "Galería Lumbre", Map = false, Font = "Oswald", Primary = { 240, 160, 60 }, Secondary = { 40, 40, 50 }, Sign = "Box" }, -- coral / street
	{ Lot = 1076, Type = "minimarket", Name = "Island Mart", Poi = "convenience_63", Map = true, Font = "Oswald", Primary = { 235, 90, 40 }, Secondary = { 255, 255, 255 }, Sign = "Box" }, -- coral / street
	{ Lot = 1089, Type = "shoes", Name = "Paso Shoes", Map = false, Font = "Fondamento", Primary = { 50, 140, 160 }, Secondary = { 250, 240, 220 }, Sign = "Box" }, -- coral / street
	{ Lot = 1095, Type = "bakery", Name = "Horno Dorado", Map = true, Font = "Fondamento", Primary = { 196, 132, 64 }, Secondary = { 250, 236, 210 }, Sign = "Awning" }, -- coral / street
	{ Lot = 1096, Type = "boutique", Name = "Boutique Sol", Map = false, Font = "Kalam", Primary = { 120, 90, 170 }, Secondary = { 255, 230, 120 }, Sign = "Box" }, -- coral / street
	{ Lot = 1099, Type = "travel", Name = "Horizonte Travel", Map = false, Font = "Nunito", Primary = { 40, 60, 90 }, Secondary = { 240, 200, 120 }, Sign = "Box" }, -- coral / street
	{ Lot = 1101, Type = "restaurant", Name = "Conch House", Poi = "restaurant_62", Map = true, Font = "JosefinSans", Primary = { 60, 50, 45 }, Secondary = { 230, 170, 90 }, Sign = "Letters" }, -- coral / street
	{ Lot = 1106, Type = "salon", Name = "Salón Aurora", Map = false, Font = "Ubuntu", Primary = { 200, 70, 70 }, Secondary = { 250, 240, 220 }, Sign = "Box" }, -- coral / street
	{ Lot = 1108, Type = "photo", Name = "Foto Flash", Map = false, Font = "Garamond", Primary = { 70, 90, 110 }, Secondary = { 230, 230, 230 }, Sign = "Box" }, -- coral / street
	{ Lot = 1112, Type = "sports", Name = "Deportes Faro", Map = false, Font = "AmaticSC", Primary = { 250, 200, 180 }, Secondary = { 90, 60, 50 }, Sign = "Box" }, -- coral / street
	{ Lot = 1113, Type = "cafe", Name = "Coral Café", Poi = "cafe_61", Map = true, Font = "Kalam", Primary = { 110, 72, 50 }, Secondary = { 240, 226, 200 }, Sign = "Blade" }, -- coral / street
	{ Lot = 1114, Type = "music", Name = "Acorde Music", Map = false, Font = "RobotoCondensed", Primary = { 240, 160, 60 }, Secondary = { 40, 40, 50 }, Sign = "Box" }, -- coral / street
	{ Lot = 1123, Type = "general", Name = "Reef Dive Shop", Poi = "general_64", Map = true, Font = "Merriweather", Primary = { 70, 100, 150 }, Secondary = { 240, 240, 240 }, Sign = "Box" }, -- coral / street
	{ Lot = 1127, Type = "jewelry", Name = "Joyería Perla", Map = false, Font = "Merriweather", Primary = { 90, 160, 110 }, Secondary = { 255, 250, 240 }, Sign = "Box" }, -- coral / street
	{ Lot = 1129, Type = "restaurant", Name = "Azul Kitchen", Map = true, Font = "Merriweather", Primary = { 120, 40, 40 }, Secondary = { 240, 220, 190 }, Sign = "Letters" }, -- coral / avenue
	{ Lot = 1136, Type = "florist", Name = "Flor de Sal", Map = false, Font = "TitilliumWeb", Primary = { 230, 120, 150 }, Secondary = { 255, 255, 255 }, Sign = "Box" }, -- coral / street
	{ Lot = 1137, Type = "toys", Name = "Juguetes Pipo", Map = false, Font = "PatrickHand", Primary = { 120, 90, 170 }, Secondary = { 255, 230, 120 }, Sign = "Box" }, -- coral / street
	{ Lot = 1138, Type = "boutique", Name = "Maré Boutique", Map = false, Font = "Michroma", Primary = { 40, 60, 90 }, Secondary = { 240, 200, 120 }, Sign = "Box" }, -- coral / street
	{ Lot = 1140, Type = "fastfood", Name = "Flamingo Burger", Map = true, Font = "Cartoon", Primary = { 60, 200, 230 }, Secondary = { 255, 255, 255 }, Sign = "Box" }, -- coral / street
	{ Lot = 1156, Type = "bakery", Name = "La Espiga", Map = true, Font = "Merriweather", Primary = { 214, 168, 90 }, Secondary = { 92, 58, 38 }, Sign = "Awning" }, -- drycreek / street
	{ Lot = 1157, Type = "laundry", Name = "Suds & Sun Laundry", Map = false, Font = "Kalam", Primary = { 40, 60, 90 }, Secondary = { 240, 200, 120 }, Sign = "Box" }, -- drycreek / avenue
	{ Lot = 1160, Type = "hardware", Name = "Bolt & Beam", Map = false, Font = "Oswald", Primary = { 90, 160, 110 }, Secondary = { 255, 250, 240 }, Sign = "Box" }, -- drycreek / street
	{ Lot = 1161, Type = "bakkal", Name = "Esquina Siete", Map = true, Font = "DenkOne", Primary = { 40, 120, 90 }, Secondary = { 250, 240, 210 }, Sign = "Blade" }, -- drycreek / street
	{ Lot = 1163, Type = "hardware", Name = "Tornillo Hardware", Map = false, Font = "JosefinSans", Primary = { 120, 90, 170 }, Secondary = { 255, 230, 120 }, Sign = "Box" }, -- drycreek / street
	{ Lot = 1164, Type = "minimarket", Name = "Plains Stop", Poi = "convenience_74", Map = true, Font = "RobotoCondensed", Primary = { 30, 140, 200 }, Secondary = { 255, 230, 80 }, Sign = "Box" }, -- drycreek / street
	{ Lot = 1167, Type = "diner", Name = "Dusty Spur Diner", Poi = "restaurant_70", Map = true, Font = "Antique", Primary = { 240, 170, 40 }, Secondary = { 60, 30, 20 }, Sign = "Letters" }, -- drycreek / street
	{ Lot = 1172, Type = "barber", Name = "Navaja Barber Co.", Map = false, Font = "Bodoni", Primary = { 240, 160, 60 }, Secondary = { 40, 40, 50 }, Sign = "Box" }, -- drycreek / street
	{ Lot = 1174, Type = "general", Name = "Creek Feed & Supply", Poi = "general_71", Map = true, Font = "TitilliumWeb", Primary = { 150, 110, 60 }, Secondary = { 250, 240, 220 }, Sign = "Box" }, -- drycreek / avenue
	{ Lot = 1214, Type = "minimarket", Name = "Bayview Corner Store", Poi = "convenience_76", Map = true, Font = "Ubuntu", Primary = { 200, 30, 60 }, Secondary = { 255, 255, 255 }, Sign = "Box" }, -- bayview / street
	{ Lot = 1222, Type = "cafe", Name = "Harborlight Café", Poi = "cafe_77", Map = true, Font = "JosefinSans", Primary = { 40, 120, 130 }, Secondary = { 250, 240, 220 }, Sign = "Blade" }, -- bayview / street
	{ Lot = 1313, Type = "general", Name = "Punta Garza Bait & Tackle", Poi = "general_80", Map = true, Font = "Oswald", Primary = { 60, 130, 120 }, Secondary = { 255, 255, 255 }, Sign = "Box" }, -- marisma / highway
	{ Lot = 1315, Type = "restaurant", Name = "Garza Seafood Shack", Poi = "restaurant_81", Map = true, Font = "Garamond", Primary = { 30, 40, 60 }, Secondary = { 220, 180, 110 }, Sign = "Letters" }, -- marisma / highway
}
