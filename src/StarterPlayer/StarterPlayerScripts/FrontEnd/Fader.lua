-- Fader: hafif ekran geçişleri (saydamlık + küçük kayma).
-- CanvasGroup (render dokusu) KULLANMAZ: alt ağaçtaki saydamlık özelliklerini doğrudan tween'ler.
-- Geçiş başlarken mevcut değerler "taban" olarak alınır; gizleme bitince taban geri yazılır,
-- böylece gizli ağaç bir sonraki gösterimde doğru görünür.

local TweenService = game:GetService("TweenService")

local Fader = {}

type Entry = { Instance: Instance, Props: { [string]: number } }
type State = { Base: { Entry }, BasePosition: UDim2, Tweens: { Tween }, Token: number }

local states: { [GuiObject]: State } = {}
local tokenCounter = 0

local function propsFor(inst: Instance): { string }?
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		return { "BackgroundTransparency", "TextTransparency" }
	elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
		return { "BackgroundTransparency", "ImageTransparency" }
	elseif inst:IsA("ScrollingFrame") then
		return { "BackgroundTransparency", "ScrollBarImageTransparency" }
	elseif inst:IsA("GuiObject") then
		return { "BackgroundTransparency" }
	elseif inst:IsA("UIStroke") then
		return { "Transparency" }
	end
	return nil
end

local function capture(root: GuiObject): { Entry }
	local list = {}
	local function add(inst: Instance)
		local names = propsFor(inst)
		if names then
			local props = {}
			for _, name in names do
				props[name] = (inst :: any)[name]
			end
			table.insert(list, { Instance = inst, Props = props })
		end
	end
	add(root)
	for _, d in root:GetDescendants() do
		add(d)
	end
	return list
end

local function setAll(base: { Entry }, value: number?)
	for _, entry in base do
		if entry.Instance.Parent then
			for name, baseValue in entry.Props do
				(entry.Instance :: any)[name] = value or baseValue
			end
		end
	end
end

-- show=true: görünür yap ve içeri sol; show=false: dışarı sol ve gizle.
-- duration 0 → anında. slide: X yönünde kayma (tasarım pikseli). onDone isteğe bağlı.
function Fader.Fade(root: GuiObject, show: boolean, duration: number, slide: number?, onDone: (() -> ())?)
	tokenCounter += 1
	local token = tokenCounter
	local state = states[root]
	if state then
		for _, tween in state.Tweens do
			tween:Cancel()
		end
		table.clear(state.Tweens)
		state.Token = token
	else
		state = { Base = capture(root), BasePosition = root.Position, Tweens = {}, Token = token }
		states[root] = state
	end
	local base, basePosition = state.Base, state.BasePosition
	local offset = UDim2.fromOffset(slide or 0, 0)

	local function finish()
		if states[root] ~= state or state.Token ~= token then
			return
		end
		states[root] = nil
		setAll(base)
		root.Position = basePosition
		root.Visible = show
		if onDone then
			onDone()
		end
	end

	if duration <= 0 then
		finish()
		return
	end

	local info = TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	if show then
		if not root.Visible then
			setAll(base, 1)
			root.Position = basePosition + offset
			root.Visible = true
		end
		for _, entry in base do
			if entry.Instance.Parent then
				table.insert(state.Tweens, TweenService:Create(entry.Instance, info, entry.Props))
			end
		end
		table.insert(state.Tweens, TweenService:Create(root, info, { Position = basePosition }))
	else
		for _, entry in base do
			if entry.Instance.Parent then
				local goal = {}
				for name in entry.Props do
					goal[name] = 1
				end
				table.insert(state.Tweens, TweenService:Create(entry.Instance, info, goal))
			end
		end
		table.insert(state.Tweens, TweenService:Create(root, info, { Position = basePosition - offset }))
	end
	for _, tween in state.Tweens do
		tween:Play()
	end
	task.delay(duration, finish)
end

-- Tek bir GuiObject'in arka plan saydamlığını tween'ler (perde, arka plan katmanları için)
function Fader.Tween(inst: Instance, props: { [string]: any }, duration: number): Tween?
	if duration <= 0 then
		for name, value in props do
			(inst :: any)[name] = value
		end
		return nil
	end
	local tween = TweenService:Create(inst, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

return Fader
