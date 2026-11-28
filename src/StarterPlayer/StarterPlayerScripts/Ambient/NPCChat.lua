-- NPCChat: yayayla yapay zekâlı sohbetin ekranı (sadece bu oyuncuda). Sunucu: NPCChatService (Roblox TextGenerator).
--
--   * Altta sohbet paneli: yayanın adı ve mesleği, son mesajlar, yazı kutusu (Enter ya da "Gönder"), kapat (X).
--   * Yayanın başının üstünde konuşma balonu: beklerken "...", sonra cevap (birkaç saniye görünür).
--   * Sohbet hafızası sunucunun ContextToken'ı ile (burada saklanır, her mesajda geri gönderilir).
-- Hangi yayayla konuşulacağına, yayanın durmasına ve sohbetin bitmesine AmbientController karar verir.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteRegistry = require(Shared.RemoteRegistry)
local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NPCChatConfig"))

local NPCChat = {}

local player = Players.LocalPlayer
local remote: RemoteFunction? = nil
local gui: ScreenGui? = nil
local ui: any = nil
local session: any = nil -- { Model, Seed, Gender, Position, Token, Name, Job, Busy, LastActive, OnClose }
local bubble: BillboardGui? = nil
local bubbleToken = 0

local DARK = Color3.fromRGB(18, 22, 30)
local ACCENT = Color3.fromRGB(255, 150, 70)

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function label(parent: Instance, text: string, size: number, color: Color3, bold: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Parent = parent
	return l
end

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "SolaraNPCChat"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.DisplayOrder = 20
	screen.Enabled = false
	screen.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -16)
	panel.Size = UDim2.new(0.92, 0, 0, 236)
	panel.BackgroundColor3 = DARK
	panel.BackgroundTransparency = 0.12
	panel.Parent = screen
	corner(panel, 14)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(560, 236)
	limit.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 14), UDim.new(0, 14)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 10), UDim.new(0, 12)
	pad.Parent = panel

	local title = label(panel, "", 18, Color3.new(1, 1, 1), true)
	title.Name = "Title"
	title.Size = UDim2.new(1, -40, 0, 22)
	local subtitle = label(panel, "", 14, Color3.fromRGB(180, 190, 205))
	subtitle.Name = "Subtitle"
	subtitle.Position = UDim2.new(0, 0, 0, 22)
	subtitle.Size = UDim2.new(1, -40, 0, 18)

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.Size = UDim2.new(0, 32, 0, 32)
	close.BackgroundColor3 = Color3.fromRGB(50, 56, 68)
	close.Text = "✕"
	close.TextSize = 16
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Font = Enum.Font.GothamBold
	close.Parent = panel
	corner(close, 8)

	local log = Instance.new("Frame")
	log.Name = "Log"
	log.BackgroundTransparency = 1
	log.Position = UDim2.new(0, 0, 0, 46)
	log.Size = UDim2.new(1, 0, 1, -46 - 46)
	log.ClipsDescendants = true
	log.Parent = panel
	local list = Instance.new("UIListLayout")
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 4)
	list.Parent = log

	local box = Instance.new("TextBox")
	box.Name = "Input"
	box.AnchorPoint = Vector2.new(0, 1)
	box.Position = UDim2.new(0, 0, 1, 0)
	box.Size = UDim2.new(1, -104, 0, 38)
	box.BackgroundColor3 = Color3.fromRGB(34, 40, 52)
	box.PlaceholderText = "Bir şey yaz…"
	box.PlaceholderColor3 = Color3.fromRGB(130, 140, 155)
	box.Text = ""
	box.TextColor3 = Color3.new(1, 1, 1)
	box.TextSize = 16
	box.Font = Enum.Font.Gotham
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.ClearTextOnFocus = false
	box.Parent = panel
	corner(box, 8)
	local boxPad = Instance.new("UIPadding")
	boxPad.PaddingLeft = UDim.new(0, 10)
	boxPad.Parent = box

	local send = Instance.new("TextButton")
	send.Name = "Send"
	send.AnchorPoint = Vector2.new(1, 1)
	send.Position = UDim2.new(1, 0, 1, 0)
	send.Size = UDim2.new(0, 96, 0, 38)
	send.BackgroundColor3 = ACCENT
	send.Text = "Gönder"
	send.TextSize = 16
	send.TextColor3 = Color3.fromRGB(30, 20, 10)
	send.Font = Enum.Font.GothamBold
	send.Parent = panel
	corner(send, 8)

	gui = screen
	ui = { Panel = panel, Title = title, Subtitle = subtitle, Close = close, Log = log, Box = box, Send = send, Order = 0 }

	close.Activated:Connect(function()
		NPCChat.Close()
	end)
	send.Activated:Connect(function()
		NPCChat.SendTyped()
	end)
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			NPCChat.SendTyped()
		end
	end)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local t = box.Text
		if utf8.len(t) and utf8.len(t) > Config.MaxMessageLength then
			box.Text = string.sub(t, 1, utf8.offset(t, Config.MaxMessageLength + 1) - 1)
		end
	end)
end

local function addLine(who: string, text: string, color: Color3)
	if not ui then
		return
	end
	ui.Order += 1
	local l = label(ui.Log, "", 15, Color3.fromRGB(230, 235, 242))
	l.RichText = false
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Size = UDim2.new(1, 0, 0, 0)
	l.LayoutOrder = ui.Order
	l.Text = who .. ": " .. text
	l.TextColor3 = color
	local lines = {}
	for _, c in ui.Log:GetChildren() do
		if c:IsA("TextLabel") then
			table.insert(lines, c)
		end
	end
	table.sort(lines, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #lines - 6 do -- son 6 satır
		lines[i]:Destroy()
	end
end

-- Yayanın başının üstündeki balon
local function showBubble(model: Model, text: string, seconds: number?)
	local root = model.PrimaryPart
	if not root then
		return
	end
	if not bubble or not bubble.Parent then
		local b = Instance.new("BillboardGui")
		b.Name = "TalkBubble"
		b.Size = UDim2.fromOffset(250, 110)
		b.StudsOffset = Vector3.new(0, 3.9, 0)
		b.LightInfluence = 0
		b.MaxDistance = 70
		b.AlwaysOnTop = false
		local frame = Instance.new("Frame")
		frame.Name = "Box"
		frame.AnchorPoint = Vector2.new(0.5, 1)
		frame.Position = UDim2.new(0.5, 0, 1, 0)
		frame.Size = UDim2.new(1, 0, 0, 0)
		frame.AutomaticSize = Enum.AutomaticSize.Y
		frame.BackgroundColor3 = Color3.new(1, 1, 1)
		frame.BackgroundTransparency = 0.05
		frame.Parent = b
		corner(frame, 10)
		local p = Instance.new("UIPadding")
		p.PaddingLeft, p.PaddingRight, p.PaddingTop, p.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 5), UDim.new(0, 5)
		p.Parent = frame
		local t = Instance.new("TextLabel")
		t.Name = "Text"
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(1, 0, 0, 0)
		t.AutomaticSize = Enum.AutomaticSize.Y
		t.TextWrapped = true
		t.TextSize = 15
		t.Font = Enum.Font.Gotham
		t.TextColor3 = Color3.fromRGB(25, 28, 35)
		t.Parent = frame
		bubble = b
	end
	local b = bubble :: BillboardGui
	b.Adornee = root
	b.Parent = player:FindFirstChildOfClass("PlayerGui") -- BillboardGui doğrudan PlayerGui altında çizilir
	local textLabel = b:FindFirstChild("Box") and (b :: any).Box:FindFirstChild("Text")
	if textLabel then
		textLabel.Text = text
	end
	b.Enabled = true
	bubbleToken += 1
	local my = bubbleToken
	if seconds then
		task.delay(seconds, function()
			if bubbleToken == my and bubble then
				bubble.Enabled = false
			end
		end)
	end
end

local function hideBubble()
	bubbleToken += 1
	if bubble then
		bubble.Enabled = false
	end
end

local function setBusy(busy: boolean)
	if not session or not ui then
		return
	end
	session.Busy = busy
	ui.Send.AutoButtonColor = not busy
	ui.Send.BackgroundTransparency = if busy then 0.5 else 0
	ui.Box.TextEditable = not busy and not session.NoChat
end

-- Sunucuya bir adım (message nil: selamlaşma)
local function ask(message: string?)
	local s = session
	if not s or not remote then
		return
	end
	setBusy(true)
	showBubble(s.Model, "...")
	local ok, result = pcall(function()
		return (remote :: RemoteFunction):InvokeServer({
			Seed = s.Seed, Gender = s.Gender, Position = s.Position, Message = message, Token = s.Token,
		})
	end)
	if session ~= s then
		return -- bu arada sohbet bitti
	end
	setBusy(false)
	if not ok or type(result) ~= "table" then
		showBubble(s.Model, Config.FallbackLines[1], Config.BubbleSeconds)
		return
	end
	if type(result.Name) == "string" and result.Name ~= "" then
		s.Name = result.Name
		ui.Title.Text = result.Name
	end
	if type(result.Job) == "string" then
		ui.Subtitle.Text = result.Job
	end
	if type(result.Token) == "string" then
		s.Token = result.Token
	end
	if type(result.You) == "string" and message then
		addLine("Sen", result.You, Color3.fromRGB(150, 205, 255))
	end
	if result.NoChat and not s.NoChat then
		s.NoChat = true
		ui.Box.TextEditable = false
		ui.Box.PlaceholderText = "Hesap ayarların yazılı sohbete izin vermiyor."
		ui.Send.Visible = false
	end
	local text = if type(result.Text) == "string" then result.Text else ""
	if text ~= "" then
		addLine(s.Name or "Yaya", text, Color3.fromRGB(255, 220, 170))
		showBubble(s.Model, text, Config.BubbleSeconds)
	else
		hideBubble()
	end
	s.LastActive = os.clock()
end

function NPCChat.Init()
	task.spawn(function()
		remote = RemoteRegistry.Get("NPCRemotes", "Talk") :: RemoteFunction
	end)
end

function NPCChat.IsOpen(): boolean
	return session ~= nil
end

-- Son etkinlikten bu yana geçen süre (sn)
function NPCChat.IdleFor(): number
	return if session then os.clock() - session.LastActive else 0
end

-- info: { Model, Seed, Gender ("F"/"M"/"N"), Position (Vector3), OnClose: () -> () }
function NPCChat.Start(info)
	if not gui then
		build()
	end
	NPCChat.Stop()
	session = {
		Model = info.Model, Seed = info.Seed, Gender = info.Gender, Position = info.Position, OnClose = info.OnClose,
		Token = nil, Name = nil, Busy = false, NoChat = false, LastActive = os.clock(),
	}
	for _, c in ui.Log:GetChildren() do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	ui.Title.Text = "…"
	ui.Subtitle.Text = ""
	ui.Box.Text = ""
	ui.Box.PlaceholderText = "Bir şey yaz…"
	ui.Box.TextEditable = true
	ui.Send.Visible = true
	local screen = gui :: ScreenGui
	screen.Enabled = true
	task.spawn(ask, nil) -- yaya selam verir
end

-- Yazılanı gönder
function NPCChat.SendTyped()
	local s = session
	if not s or s.Busy or s.NoChat or not ui then
		return
	end
	local text = string.gsub(ui.Box.Text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	if text == "" then
		return
	end
	ui.Box.Text = ""
	s.LastActive = os.clock()
	task.spawn(ask, text)
end

-- Paneli kapat (oyuncu kapattı): AmbientController'a haber verir
function NPCChat.Close()
	local s = session
	if s and s.OnClose then
		s.OnClose()
	end
	NPCChat.Stop()
end

-- Sohbeti sessizce bitir (AmbientController çağırır)
function NPCChat.Stop()
	session = nil
	hideBubble()
	if gui then
		gui.Enabled = false
	end
	if ui then
		ui.Box:ReleaseFocus()
	end
end

return NPCChat
