-- Focus: klavye, gamepad ve fare için TEK odak modeli.
-- Roblox'un GuiService.SelectedObject seçimini kullanmıyoruz; kaydırıcı/seçici satırlarda
-- sol/sağ "değer değiştirir", yukarı/aşağı "satır değiştirir" olmalı. Fare üzerine gelince de odak taşınır,
-- böylece fare ve klavye aynı vurguyu paylaşır.
--
-- Öğe (item):
--   Gui         GuiObject         görünürlük + kaydırma hesabı için
--   OnFocus     (focused, showHighlight) -> ()
--   OnActivate  () -> ()?          Enter / A / tıklama
--   OnAdjust    (dir: -1|1) -> ()? Sol/sağ (kaydırıcı, seçici, anahtar, sekme çubuğu)
--   Scroller    ScrollingFrame?    odaklanınca görünür alana kaydırılır
--   IsEnabled   () -> boolean?     false ise atlanır

local TweenService = game:GetService("TweenService")

local Focus = {}
Focus.__index = Focus

export type Item = {
	Gui: GuiObject,
	OnFocus: (boolean, boolean) -> (),
	OnActivate: (() -> ())?,
	OnAdjust: ((number) -> ())?,
	Scroller: ScrollingFrame?,
	IsEnabled: (() -> boolean)?,
}

-- getScale: ekranın UIScale değeri (CanvasPosition ölçeksiz birimdedir)
function Focus.new(getScale: () -> number, onMove: (() -> ())?)
	return setmetatable({
		_items = {} :: { Item },
		_index = 0,
		_highlight = true,
		_getScale = getScale,
		_onMove = onMove,
	}, Focus)
end

local function enabled(item: Item?): boolean
	return item ~= nil and (item.IsEnabled == nil or item.IsEnabled())
end

function Focus:_ensureVisible(item: Item)
	local scroller = item.Scroller
	if not scroller or not item.Gui.Parent then
		return
	end
	local scale = math.max(self._getScale(), 0.01)
	local top = (item.Gui.AbsolutePosition.Y - scroller.AbsolutePosition.Y) / scale + scroller.CanvasPosition.Y
	local bottom = top + item.Gui.AbsoluteSize.Y / scale
	local view = scroller.AbsoluteWindowSize.Y / scale
	local y = scroller.CanvasPosition.Y
	local margin = 12
	if top - margin < y then
		y = top - margin
	elseif bottom + margin > y + view then
		y = bottom + margin - view
	else
		return
	end
	TweenService:Create(scroller, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CanvasPosition = Vector2.new(0, math.max(0, y)),
	}):Play()
end

function Focus:SetItems(items: { Item }, index: number?)
	local current = self._items[self._index]
	if current then
		current.OnFocus(false, self._highlight)
	end
	self._items = items
	self._index = 0
	if #items > 0 then
		self:Select(index or 1, true)
	end
end

function Focus:Select(index: number, silent: boolean?)
	local count = #self._items
	if count == 0 then
		return
	end
	index = math.clamp(index, 1, count)
	if index == self._index then
		return
	end
	local old = self._items[self._index]
	if old then
		old.OnFocus(false, self._highlight)
	end
	self._index = index
	local item = self._items[index]
	item.OnFocus(true, self._highlight)
	self:_ensureVisible(item)
	if not silent and self._onMove then
		self._onMove()
	end
end

-- delta: -1 yukarı, +1 aşağı. Devre dışı öğeler atlanır, listenin sonunda durur (sarmaz).
function Focus:Move(delta: number): boolean
	local i = self._index
	repeat
		i += delta
	until i < 1 or i > #self._items or enabled(self._items[i])
	if i >= 1 and i <= #self._items then
		self:Select(i)
		return true
	end
	return false
end

function Focus:Adjust(dir: number): boolean
	local item = self._items[self._index]
	if enabled(item) and item.OnAdjust then
		item.OnAdjust(dir)
		return true
	end
	return false
end

function Focus:Activate(): boolean
	local item = self._items[self._index]
	if enabled(item) and item.OnActivate then
		item.OnActivate()
		return true
	end
	return false
end

-- Fare üzerine geldi
function Focus:Hover(item: Item)
	local index = table.find(self._items, item)
	if index and enabled(item) then
		self:Select(index)
	end
end

function Focus:Current(): Item?
	return self._items[self._index]
end

function Focus:GetIndex(): number
	return self._index
end

-- Dokunmatikte odak çerçevesi gizlenir (parmakla seçimde gereksiz), klavye/gamepad'de görünür
function Focus:SetHighlight(show: boolean)
	if self._highlight == show then
		return
	end
	self._highlight = show
	local item = self._items[self._index]
	if item then
		item.OnFocus(true, show)
	end
end

-- Odaklı öğenin görünümünü yeniden uygula (geçiş sonrası)
function Focus:Refresh()
	for i, item in self._items do
		item.OnFocus(i == self._index, self._highlight)
	end
end

return Focus
