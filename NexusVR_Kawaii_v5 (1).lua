--[[
	✨ NEXUS VR KAWAII v5.1 ✨   (на базе v4.2)

	v5.1: слайдеры тела подняты выше джойстиков; «руки перед глазами» — руки
	всегда в кадре и двигаются стиком (вбок/вверх/вниз) и ползунком глубины
	(дальше/ближе); при приседе руки, голова и ноги опускаются ровно на столько,
	насколько ушло тело (длина ног измеряется по реальному персонажу).

	Что изменилось:
	  • ФИЗИКА РУК как в твоём скрипте: настоящая рука скина ставится прямо
	    в нужную точку через Shoulder.Transform, сглаживание Lerp, и у каждой
	    руки своё независимое случайное покачивание (скорость, амплитуда,
	    боковое качание, наклон). Пружины, IK и «потолок досягаемости» убраны.
	  • ТОЛЬКО РУКИ СКИНА: нарисованные кисти с пальцами, метка цели и линия
	    удалены полностью. Двигаются родные Arm / UpperArm / LowerArm / Hand.
	  • ОПУСКАНИЕ ВСЕГО ТЕЛА: ползунок «⬇» слева на экране, кнопка 🧎 сверху,
	    клавиша C на ПК и слайдер во вкладке «🧍 Тело». Тело опускается
	    целиком (голова, руки, торс), а у R15 ещё и сгибаются ноги.
	  • Позы, танцы, сидение, джойстики, меню — как в v4.2
	    (кроме жестов пальцами: «Кука» и «Класс» убраны вместе с пальцами).

	ПК: RightShift — меню, C — присесть/встать.
	Подгонка высоты головы: HEAD_BASE. Глубина приседа: MAX_DROP.
]]

local env = (getgenv and getgenv()) or _G
if env.__KawaiiVR then pcall(env.__KawaiiVR.Destroy) end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local plr = Players.LocalPlayer
local cam = workspace.CurrentCamera

local nexus = ReplicatedStorage:WaitForChild("NexusVRCharacterModel", 10)
if not nexus then
	warn("[KawaiiVR] NexusVRCharacterModel не найден — игра не поддерживает Nexus VR")
	return
end
local remote = nexus:WaitForChild("UpdateInputs", 10)
if not remote then
	warn("[KawaiiVR] UpdateInputs не найден")
	return
end
local readyRemote = nexus:FindFirstChild("ReplicationReady")
if readyRemote then readyRemote:FireServer() end

local sin, cos, rad, pi = math.sin, math.cos, math.rad, math.pi
local RENDER_NAME = "KawaiiVR_Step"

--------------------------------------------------------------------
-- ПОДКЛЮЧЕНИЯ
--------------------------------------------------------------------
local conns, dead = {}, false
local function bind(signal, fn)
	local c = signal:Connect(fn)
	conns[#conns + 1] = c
	return c
end

--------------------------------------------------------------------
-- КОНСТАНТЫ
--------------------------------------------------------------------
local HEAD_BASE = 2.0       -- высота головы над HumanoidRootPart
local MAX_DROP = 1.8        -- насколько максимум можно опустить тело (студы)
local JOY, JOY_R = 120, 50
local SIT_ANIM_R15 = "rbxassetid://2506281703"
local SIT_ANIM_R6 = "rbxassetid://178130996"

--------------------------------------------------------------------
-- НАСТРОЙКИ И СОСТОЯНИЕ
--------------------------------------------------------------------
local Config = {
	Smooth = 0.25,        -- как в твоём скрипте (Lerp 0.25)
	SendRate = 30,
	Sensitivity = 1.0,
	SwayAmount = 1.0,     -- множитель случайного покачивания (1 = как в оригинале)
	IdleSway = true,
	Breathing = true,
	HideHead = true,
	HideArms = false,
	AimMode = false,
	Mirror = false,
	Sit = false,
	RealSit = false,      -- true = старый режим через Humanoid.Sit (садится на сиденья)
	SitDrop = 1.0,        -- насколько опускается тело при сидении на месте
	BodyDrop = 0,         -- присед: насколько опущено всё тело (0..MAX_DROP)
	LegBend = true,       -- сгибать ноги (R15) при приседе, видно только тебе
	LockL = false,
	LockR = false,
	SplitDepth = false,
	ShowHUD = true,
	FOV = 70,
	AutoReturn = 0,
	PoseJoy = 1.0,        -- насколько стик/глубина сдвигают позы (0 = не двигают)
	DanceHop = true,      -- подпрыгивать в такт танцу
	RestView = true,      -- руки перед глазами (всегда в кадре)
}

local State = { pose = nil, poseStart = 0 }

pcall(function()
	plr.CameraMaxZoomDistance = 128
	plr.CameraMinZoomDistance = 0.5
	plr.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Invisicam
end)

--------------------------------------------------------------------
-- ПОЗЫ
-- l/r = положение руки в пространстве тела (x вправо, y вверх, z вперёд = минус)
-- третий результат/параметр h = поворот головы (необязательно)
--------------------------------------------------------------------
local function C(x, y, z, rx, ry, rz)
	return CFrame.new(x, y, z) * CFrame.Angles(rad(rx or 0), rad(ry or 0), rad(rz or 0))
end
local function H(rx, ry, rz)
	return CFrame.Angles(rad(rx or 0), rad(ry or 0), rad(rz or 0))
end

local LD = C(-0.8, -0.3, -0.5, 10, 0, -5)
local RD = C(0.8, -0.3, -0.5, 10, 0, 5)

local PoseList, Poses = {}, {}
local function add(key, emoji, name, cat, a, b, h)
	local p = { key = key, emoji = emoji, name = name, cat = cat }
	if type(a) == "function" then
		p.fn = a
	else
		p.l, p.r, p.h = a, b, h
	end
	Poses[key] = p
	PoseList[#PoseList + 1] = p
end

-- ══ Приветы ══
add("wave", "👋", "Привет", "Приветы", function(e)
	local w = sin(e * 4)
	return C(-1.2, -0.2, -0.8, 0, 0, -10), C(1.2, 1.8 + w * 0.2, -0.6, -20 + w * 30, -20, 10 + w * 15), H(0, 0, 4)
end)
add("wave_l", "🖐️", "Левой", "Приветы", function(e)
	local w = sin(e * 4)
	return C(-1.2, 1.8 + w * 0.2, -0.6, -20 + w * 30, 20, -10 - w * 15), C(1.2, -0.2, -0.8, 0, 0, 10), H(0, 0, -4)
end)
add("wave_both", "👐", "Двумя руками", "Приветы", function(e)
	local w = sin(e * 4)
	return C(-1.2, 1.8 - w * 0.2, -0.6, -20 - w * 30, 20, -10 - w * 15),
		C(1.2, 1.8 + w * 0.2, -0.6, -20 + w * 30, -20, 10 + w * 15)
end)
add("palms", "🤚", "Ладошки", "Приветы", function(e)
	local w = sin(e * 6)
	return C(-0.55, 1.5, -0.95, 0, 0, -10 + w * 20), C(0.55, 1.5, -0.95, 0, 0, 10 - w * 20), H(0, 0, w * 3)
end)
add("hello_cute", "🥰", "Приветик", "Приветы", function(e)
	local w = sin(e * 5)
	return LD, C(0.5, 1.85 + w * 0.04, -0.55, -50, -20, 20 + w * 18), H(0, 0, 10 + w * 3)
end)
add("kiss", "😘", "Воздушный поцелуй", "Приветы", function(e)
	local p = (e % 2) / 2
	local mouth = C(0.15, 1.75, -0.55, -60, -10, 10)
	local out = C(1.0, 1.5, -1.4, -30, -30, 15)
	local r = (p < 0.4) and mouth or mouth:Lerp(out, (p - 0.4) / 0.6)
	return LD, r, H(0, 0, 8)
end)
add("salute", "🫡", "Салют", "Приветы", C(-0.9, -0.1, -0.6, 0, 0, -8), C(0.8, 1.6, -0.3, -70, -30, 20))
add("handshake", "🤝", "Рукопожатие", "Приветы", function(e)
	return C(-0.9, -0.2, -0.6, 10, 0, -6), C(0.6, 1.0 + sin(e * 6) * 0.08, -1.2, -30, -10, 15)
end)
add("fistbump", "👊", "Кулачок", "Приветы", C(-0.9, -0.2, -0.6, 10, 0, -6), C(0.7, 1.2, -1.2, -45, -15, 25))
add("bow", "🙇", "Поклон", "Приветы", function(e)
	local s = (1 - cos(math.min(e, 1) * pi)) / 2
	return C(-0.4, 0.3, -0.55, 20, 0, -10), C(0.4, 0.3, -0.55, 20, 0, 10), H(-32 * s, 0, 0)
end)
add("come", "🫵", "Иди сюда", "Приветы", function(e)
	local w = sin(e * 8)
	return LD, C(0.8, 1.3 + w * 0.1, -1.3, -40 + w * 25, -15, 15)
end)
add("stop", "✋", "Стоп", "Приветы", LD, C(0.7, 1.5, -1.5, -80, -10, 10))

-- ══ Базовые ══
add("hands_down", "⬇️", "Опустить", "Базовые", LD, RD)
add("raise_hand", "🙋", "Поднять", "Базовые", C(-0.9, -0.1, -0.6, 0, 0, -8), C(1.0, 1.9, -0.5, -75, 0, 15))
add("point", "☝️", "Указать", "Базовые", C(-0.9, -0.2, -0.6, 15, 0, -8), C(1.6, 1.4, -1.3, -15, -40, 8))
add("hug", "🤗", "Обнять", "Базовые", function(e)
	local t = math.min(e / 1.5, 1)
	return C(-0.5 + t * 0.1, 1.4 - t * 0.2, -0.7, -35, 50, -25), C(0.5 - t * 0.1, 1.4 - t * 0.2, -0.7, -35, -50, 25), H(0, 0, 6)
end)
add("hips", "🧍", "В бока", "Базовые", C(-0.95, 0.5, 0.1, 0, 0, -35), C(0.95, 0.5, 0.1, 0, 0, 35))

-- ══ Милота ══
add("kawaii", "🥺", "Няшка", "Милота", C(-0.6, 1.6, -0.4, -45, 30, -30), C(0.6, 1.6, -0.4, -45, -30, 30), H(0, 0, 10))
add("shy", "👉👈", "Стесняюсь", "Милота", C(-0.3, 0.9, -0.6, 20, -15, -20), C(0.3, 0.9, -0.6, 20, 15, 20), H(-14, 0, 6))
add("heart", "💖", "Сердце", "Милота", C(-0.4, 1.7, -0.6, -50, 35, -40), C(0.4, 1.7, -0.6, -50, -35, 40))
add("heart_hands", "🫶", "Сердечки", "Милота", C(-0.5, 1.6, -0.6, -55, 30, -35), C(0.5, 1.6, -0.6, -55, -30, 35))
add("cat", "🐱", "Кошечка", "Милота", function(e)
	local w = sin(e * 5)
	return C(-0.45, 1.15 + w * 0.06, -0.65, -60, 15, -20), C(0.45, 1.15 - w * 0.06, -0.65, -60, -15, 20), H(0, 0, 10 + w * 3)
end)
add("bunny", "🐰", "Зайчик", "Милота", function(e)
	local w = sin(e * 6)
	return C(-0.3, 2.6, -0.15, 0, 0, -5 + w * 15), C(0.3, 2.6, -0.15, 0, 0, 5 - w * 15), H(0, 0, w * 4)
end)
add("heart_big", "💞", "Сердце над головой", "Милота", function(e)
	local p = sin(e * 5) * 0.04
	return C(-0.25, 2.5 + p, -0.1, 0, 0, -30), C(0.25, 2.5 + p, -0.1, 0, 0, 30)
end)
add("hide_face", "🙈", "Спрятаться", "Милота", C(-0.25, 2.0, -0.55, -80, 15, -10), C(0.25, 2.0, -0.55, -80, -15, 10), H(-10, 0, 0))
add("headpat", "🫳", "Погладить", "Милота", function(e)
	return LD, C(0.4, 0.9 + 0.12 * sin(e * 7), -1.5, -70, 0, 0)
end)
add("sleep", "😴", "Спатки", "Милота", C(-0.5, 0.8, -0.5, 10, 0, -10), C(0.5, 1.7, -0.45, -50, -10, 20), H(0, 0, 18))

-- ══ Эмоции ══
add("think", "🤔", "Думаю", "Эмоции", C(-1.0, -0.1, -0.8, 0, 0, -10), C(0.4, 1.5, -0.5, -60, -20, 15), H(0, 0, 8))
add("shock", "😱", "Шок", "Эмоции", C(-0.8, 1.6, -0.5, -60, 40, -30), C(0.8, 1.6, -0.5, -60, -40, 30), H(8, 0, 0))
add("facepalm", "🤦", "Facepalm", "Эмоции", C(-0.9, 0, -0.7, 0, 0, -10), C(0.3, 1.8, -0.4, -80, -15, 10), H(-18, 0, 0))
add("shrug", "🤷", "Пожать", "Эмоции", C(-1.3, 1.4, -0.6, -50, 20, -35), C(1.3, 1.4, -0.6, -50, -20, 35), H(0, 0, 8))
add("sassy", "💁", "Дерзко", "Эмоции", C(-0.9, 0.5, -0.1, 0, 0, -30), C(1.2, 1.3, -0.6, -40, -25, 20), H(0, 12, 6))
add("cry", "😭", "Плачу", "Эмоции", function(e)
	local s = sin(e * 14) * 3
	return C(-0.4, 1.9, -0.45, -55 + s, 25, -25), C(0.4, 1.9, -0.45, -55 - s, -25, 25), H(-12, 0, 0)
end)
add("nod", "🙂", "Да", "Эмоции", function(e)
	return C(-0.5, 0.6, -0.6, 10, 0, -10), C(0.5, 0.6, -0.6, 10, 0, 10), H(-6 - 12 * (0.5 + 0.5 * sin(e * 7)), 0, 0)
end)
add("shake", "🙅", "Нет", "Эмоции", function(e)
	return C(-0.5, 0.6, -0.6, 10, 0, -10), C(0.5, 0.6, -0.6, 10, 0, 10), H(0, 25 * sin(e * 8), 0)
end)
add("cross_arms", "❌", "Крест", "Эмоции", C(0.4, 1.1, -0.6, -30, -60, 20), C(-0.4, 1.1, -0.6, -30, 60, -20))

-- ══ Действия ══
add("pray", "🙏", "Молитва", "Действия", C(0, 1.3, -0.5, -45, -10, -15), C(0, 1.3, -0.5, -45, 10, 15))
add("photo", "📸", "Фото", "Действия", C(-0.4, 1.7, -0.6, -60, 20, -25), C(0.4, 1.7, -0.6, -60, -20, 25))
add("guitar", "🎸", "Гитара", "Действия", function(e)
	return C(-0.8, 1.0, -0.8, -35, 20, -25), C(0.6, 0.8 + sin(e * 9) * 0.07, -0.6, -45, -30, 20)
end)
add("sing", "🎤", "Пение", "Действия", C(-0.9, 0, -0.7, 0, 0, -10), C(0.5, 1.6, -0.5, -50, -20, 15), H(10, 0, 0))
add("flex", "💪", "Бицепс", "Действия", C(-1.4, 1.5, -0.3, -80, 30, -40), C(1.4, 1.5, -0.3, -80, -30, 40))
add("offering", "🤲", "Дар", "Действия", C(-0.5, 1.0, -0.9, -40, 10, -20), C(0.5, 1.0, -0.9, -40, -10, 20))
add("clap", "👏", "Хлопать", "Действия", function(e)
	local x = 0.12 + (0.5 + 0.5 * sin(e * 12)) * 0.35
	return C(-x, 1.3, -0.7, -40, 15, -20), C(x, 1.3, -0.7, -40, -15, 20)
end)
add("praise", "🙌", "Радость", "Действия", C(-0.7, 2.3, -0.3, -60, 25, -30), C(0.7, 2.3, -0.3, -60, -25, 30))
add("naruto", "🥷", "Наруто", "Действия", C(-0.6, 0.2, 0.9, 120, 0, -20), C(0.6, 0.2, 0.9, 120, 0, 20))
add("box", "🥊", "Бокс", "Действия", function(e)
	local p = sin(e * 7)
	return C(-0.5, 1.2, -0.7 - p * 0.5, -50, 10, -10), C(0.5, 1.2, -0.7 + p * 0.5, -50, -10, 10)
end)
add("zombie", "🧟", "Зомби", "Действия", function(e)
	local w = sin(e * 2) * 0.1
	return C(-0.5, 1.3 + w, -1.6, -75, 0, -5), C(0.5, 1.3 - w, -1.6, -75, 0, 5), H(-10, 0, 8)
end)
add("meditate", "🧘", "Медитация", "Действия", C(-0.8, 0.5, -0.5, -30, 0, -25), C(0.8, 0.5, -0.5, -30, 0, 25), H(-6, 0, 0))
add("robot", "🤖", "Робот", "Действия", function(e)
	local steps = {
		{ C(-1.0, 2.0, -0.3), C(1.0, 0.4, -0.4) },
		{ C(-1.0, 1.2, -1.2), C(1.0, 1.2, -1.2) },
		{ C(-1.0, 0.4, -0.4), C(1.0, 2.0, -0.3) },
		{ C(-1.8, 1.3, -0.2), C(1.8, 1.3, -0.2) },
	}
	local i = math.floor(e * 3) % 4 + 1
	return steps[i][1], steps[i][2], H(0, (i % 2 == 0) and 22 or -22, 0)
end)
add("superman", "🦸", "Супергерой", "Действия", C(-0.6, 0.5, -0.3, 0, 0, -30), C(0.9, 2.6, -1.2, -80, 0, 10), H(-10, 0, 0))

-- ══ Танцы ══
add("dance", "💃", "Танец", "Танцы", function(e)
	local s = sin(e * 2)
	return C(-1.2, 1.5 + s * 0.3, -0.8, s * 25, 0, -25), C(1.2, 1.5 - s * 0.3, -0.8, -s * 25, 0, 25), H(0, 0, s * 8)
end)
add("rampage", "🔥", "Rampage", "Танцы", function(e)
	local phase = math.floor(e / 2.8) % 3
	local beat = e * 9
	if phase == 0 then
		local t = e * 8
		local lc, ls = cos(t), sin(t)
		local rc, rs = cos(t + pi), sin(t + pi)
		return C(-1.25, 1.4 + ls * 1.1, -0.2 - lc * 1.1, -40 + ls * 40, 0, -25),
			C(1.25, 1.4 + rs * 1.1, -0.2 - rc * 1.1, -40 + rs * 40, 0, 25),
			H(-18 + 24 * sin(beat * 2), 14 * sin(beat), 7 * sin(beat))
	elseif phase == 1 then
		local p = 0.5 + 0.5 * sin(beat)
		local q = 0.5 + 0.5 * sin(beat + pi)
		return C(-1.1 - q * 0.3, 0.6 + q * 1.9, -0.5 - q * 0.5, -70 * q, 20, -30 * q),
			C(1.1 + p * 0.3, 0.6 + p * 1.9, -0.5 - p * 0.5, -70 * p, -20, 30 * p),
			H(-22 + 28 * sin(beat * 2), 10 * sin(beat), 6 * sin(beat))
	else
		local s = sin(beat * 2)
		local q = 0.5 + 0.5 * sin(beat)
		return C(-0.9, 2.1 + q * 0.5, -0.2, -30, 20, -20 + s * 10),
			C(0.9, 2.1 + (1 - q) * 0.5, -0.2, -30, -20, 20 + s * 10),
			H(-20 + 28 * s, 12 * sin(beat), 8 * sin(beat))
	end
end)
add("floss", "🕴️", "Floss", "Танцы", function(e)
	local s = sin(e * 6)
	return C(-0.4 + s * 1.2, 0.6, -0.1 - s * 0.5, 0, 0, -20), C(0.4 + s * 1.2, 0.6, -0.1 + s * 0.5, 0, 0, 20), H(0, 0, -s * 6)
end)
add("headbang", "🤘", "Headbang", "Танцы", function(e)
	local b = 0.5 + 0.5 * sin(e * 9)
	return C(-1.2, 2.0, -0.3, -40, 20, -30), C(1.2, 2.0, -0.3, -40, -20, 30), H(-10 - 32 * b, 0, 0)
end)
add("chicken", "🐔", "Курочка", "Танцы", function(e)
	local f = math.abs(sin(e * 6))
	return C(-1.4, 0.7 + f * 0.7, 0.15, 0, 0, -50), C(1.4, 0.7 + f * 0.7, 0.15, 0, 0, 50), H(10 * sin(e * 12), 0, 0)
end)
add("sprinkler", "💦", "Разбрызгиватель", "Танцы", function(e)
	local phi = (math.floor(e * 4) % 7) * 0.25 - 0.1
	return C(-0.35, 2.1, 0.15, 0, 0, -10), C(1.0 + cos(phi) * 1.7, 1.4, -sin(phi) * 1.7, 0, 0, 90), H(0, -phi * 20, 0)
end)
add("swing", "🎶", "Свинг", "Танцы", function(e)
	local s = sin(e * 3)
	return C(-1.3, 0.9 + s * 0.3, -0.6, 0, 0, -25), C(1.3, 0.9 - s * 0.3, -0.6, 0, 0, 25), H(0, 0, s * 8)
end)
add("disco", "🕺", "Диско", "Танцы", function(e)
	local a, b = sin(e * 6), cos(e * 6)
	return C(-1.2, 1.5 + a * 0.4, -0.7, -30 + a * 30, 0, -30), C(1.2, 1.5 + b * 0.4, -0.7, -30 + b * 30, 0, 30)
end)
add("wings", "🦋", "Крылья", "Танцы", function(e)
	local v = sin(e)
	return C(-2.0, 1.4 + v * 0.3, -0.4, -30, 0, -45 + v * 10), C(2.0, 1.4 - v * 0.3, -0.4, -30, 0, 45 - v * 10)
end)
add("circus", "🎪", "Цирк", "Танцы", function(e)
	local w, s = sin(e * 4), sin(e * 2)
	return C(-1.5 + s * 0.3, 1.7 + w * 0.2, -0.8, -40 + w * 20, 0, -30), C(1.5 - s * 0.3, 1.7 - w * 0.2, -0.8, -40 - w * 20, 0, 30)
end)
add("dramatic", "🎭", "Драма", "Танцы", C(-1.0, 2.2, -0.7, -70, 30, -35), C(0.5, 1.8, -0.8, -50, -20, 25), H(10, 0, -10))
add("dab", "😎", "Дэб", "Танцы", C(-1.4, 1.9, -0.6, -50, 30, -40), C(0.3, 1.6, -0.9, 10, -20, 15), H(-20, 0, 0))
add("tpose", "🤸", "T-поза", "Танцы", C(-3.0, 1.4, 0, 0, 0, -90), C(3.0, 1.4, 0, 0, 0, 90))
add("cheer", "🎉", "Ура!", "Танцы", function(e)
	local s = sin(e * 6)
	return C(-1.1, 2.4 + s * 0.25, -0.3, -20, 0, -20), C(1.1, 2.4 - s * 0.25, -0.3, -20, 0, 20), H(8, 0, 0)
end)
add("ballet", "🩰", "Балет", "Танцы", function(e)
	local s = sin(e * 2)
	return C(-1.0, 2.2 + s * 0.1, -0.2, 0, 0, -20), C(1.0, 2.2 - s * 0.1, -0.2, 0, 0, 20), H(0, 0, s * 8)
end)
add("hype", "🙌", "Hype", "Танцы", function(e)
	local s = sin(e * 8)
	local up = 0.5 + 0.5 * s
	return C(-1.0, 0.8 + up * 1.6, -0.3, -30, 0, -25), C(1.0, 0.8 + (1 - up) * 1.6, -0.3, -30, 0, 25),
		H(-8 - 14 * (0.5 + 0.5 * sin(e * 16)), 0, s * 5)
end)
add("neko", "🐾", "Неко-танец", "Танцы", function(e)
	local s, b = sin(e * 4), 0.5 + 0.5 * sin(e * 8)
	return C(-0.45 + s * 0.25, 1.2 + b * 0.15, -0.65, -65, 15, -20),
		C(0.45 + s * 0.25, 1.2 + (1 - b) * 0.15, -0.65, -65, -15, 20), H(0, 12 * s, 10 * s)
end)
add("wavedance", "🌊", "Волна", "Танцы", function(e)
	local a, b = sin(e * 4), sin(e * 4 - 1.2)
	return C(-1.5, 1.3 + a * 0.6, -0.3, 0, 0, -50 + a * 20), C(1.5, 1.3 + b * 0.6, -0.3, 0, 0, 50 - b * 20), H(0, 0, a * 7)
end)
add("shuffle", "🕺", "Шаффл", "Танцы", function(e)
	local s = sin(e * 7)
	return C(-0.9, 0.4, -0.3 - s * 0.7, 20, 0, -10), C(0.9, 0.4, -0.3 + s * 0.7, 20, 0, 10), H(0, 10 * s, 5 * s)
end)
add("lasso", "🤠", "Ковбой", "Танцы", function(e)
	local t = e * 7
	return C(-0.55, 1.0 + math.abs(sin(t)) * 0.2, -0.9, -40, 10, -15),
		C(0.9 + cos(t) * 0.45, 2.1, -0.4 + sin(t) * 0.45, -60, 0, 20), H(0, 0, 6 * sin(t))
end)

-- ══ Знаки ══
add("peace", "✌️", "Победа", "Знаки", C(-1.2, 1.5, -0.7, -30, 15, -20), C(1.2, 1.5, -0.7, -30, -15, 20))
add("ok", "👌", "Окей", "Знаки", C(-1.1, 1.3, -0.7, -35, 15, -20), C(1.1, 1.3, -0.7, -35, -15, 20))
add("rock", "🤟", "Рок", "Знаки", C(-1.3, 1.7, -0.7, -40, 25, -30), C(1.3, 1.7, -0.7, -40, -25, 30))
add("vulcan", "🖖", "Вулкан", "Знаки", C(-1.2, 1.5, -0.6, -40, 20, -25), C(1.2, 1.5, -0.6, -40, -20, 25))
add("shaka", "🤙", "Шака", "Знаки", function(e)
	local w = sin(e * 8) * 12
	return C(-1.3, 1.3, -0.7, -35, 20, -25 + w), C(1.3, 1.3, -0.7, -35, -20, 25 - w)
end)
add("snap", "🫰", "Щелчок", "Знаки", function(e)
	local w = sin(e * 5) * 0.1
	return C(-1.0, 1.3 + w, -0.7, -35, 20, -25), C(1.0, 1.3 - w, -0.7, -35, -20, 25)
end)

-- прыжки в такт (секунд между прыжками)
Poses.rampage.hop = 1.4
Poses.hype.hop = 1.2

local Categories = { "Все", "Приветы", "Милота", "Базовые", "Эмоции", "Действия", "Танцы", "Знаки" }

-- кружочки быстрого доступа (ключи поз) — меняй как хочешь
local QuickPoses = {
	"hands_down", "wave", "wave_both", "palms", "hello_cute", "hug", "heart", "kawaii", "kiss",
	"cat", "bunny", "heart_big", "clap", "bow", "dance", "rampage", "hype", "neko", "peace",
}

-- базовое положение рук в обычном режиме (те же числа, что в твоём скрипте)
local Base = {
	stand = { x = 1.0, y = -0.2, z = -0.8, rx = 0, rz = 10, gx = 1.8, gy = 3.0 },
	sit = { x = 0.9, y = -0.1, z = -0.9, rx = 0, rz = 8, gx = 1.6, gy = 2.6 },
	aim = { x = 0.55, y = -0.5, z = -1.2, rx = 80, rz = 4, gx = 1.3, gy = 1.3 },
}

--------------------------------------------------------------------
-- UI: БАЗА
--------------------------------------------------------------------
local T = {
	bg = Color3.fromRGB(22, 22, 30),
	item = Color3.fromRGB(44, 44, 60),
	off = Color3.fromRGB(70, 70, 85),
	text = Color3.fromRGB(255, 255, 255),
	sub = Color3.fromRGB(170, 170, 190),
	pink = Color3.fromRGB(255, 105, 180),
	blue = Color3.fromRGB(135, 206, 250),
	yellow = Color3.fromRGB(255, 220, 100),
	mint = Color3.fromRGB(152, 255, 204),
	purple = Color3.fromRGB(200, 162, 255),
}
local palette = { T.pink, T.blue, T.mint, T.purple, T.yellow }

local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
local function round(o, r) return mk("UICorner", { CornerRadius = UDim.new(0, r) }, o) end
local function outline(o, color, th, tr)
	return mk("UIStroke", {
		Color = color, Thickness = th or 1, Transparency = tr or 0.6,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, o)
end

local function lower(s)
	local out = {}
	for _, c in utf8.codes(s) do
		local ch = c
		if ch >= 0x410 and ch <= 0x42F then ch = ch + 32
		elseif ch == 0x401 then ch = 0x451
		elseif ch < 128 then ch = string.byte(string.lower(string.char(ch))) end
		out[#out + 1] = utf8.char(ch)
	end
	return table.concat(out)
end

local function makeDrag(gui, h)
	local active, startPos
	bind(gui.InputBegan, function(input)
		if active then return end
		local ut = input.UserInputType
		if ut == Enum.UserInputType.Touch or ut == Enum.UserInputType.MouseButton1 then
			active = input
			startPos = Vector2.new(input.Position.X, input.Position.Y)
			if h.began then h.began(startPos) end
			local c
			c = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					c:Disconnect()
					active = nil
					if h.ended then h.ended() end
				end
			end)
		end
	end)
	bind(UserInputService.InputChanged, function(input)
		if not active then return end
		if input == active
			or (input.UserInputType == Enum.UserInputType.MouseMovement and active.UserInputType == Enum.UserInputType.MouseButton1) then
			local p = Vector2.new(input.Position.X, input.Position.Y)
			h.moved(p - startPos, p)
		end
	end)
end

local ParentGui
do
	local okCore, core = pcall(function() return game:GetService("CoreGui") end)
	if gethui then
		ParentGui = gethui()
	elseif okCore and core and core:FindFirstChild("RobloxGui") then
		ParentGui = core:FindFirstChild("RobloxGui")
	else
		ParentGui = plr:WaitForChild("PlayerGui")
	end
end
if ParentGui:FindFirstChild("NexusVR_Kawaii") then ParentGui.NexusVR_Kawaii:Destroy() end

local gui = mk("ScreenGui", {
	Name = "NexusVR_Kawaii", ResetOnSpawn = false, DisplayOrder = 99999, IgnoreGuiInset = true,
}, ParentGui)

local hud = mk("Frame", { Name = "HUD", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0 }, gui)

--------------------------------------------------------------------
-- УВЕДОМЛЕНИЯ
--------------------------------------------------------------------
local toast = mk("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -175),
	AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30),
	BackgroundColor3 = T.bg, BackgroundTransparency = 1, TextTransparency = 1, Text = "",
	Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = T.text, BorderSizePixel = 0,
}, gui)
round(toast, 15)
mk("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, toast)
local toastStroke = outline(toast, T.pink, 1.5, 1)
local toastId = 0
local function showToast(text)
	toastId = toastId + 1
	local id = toastId
	toast.Text = text
	local ti = TweenInfo.new(0.15)
	TweenService:Create(toast, ti, { BackgroundTransparency = 0.15, TextTransparency = 0 }):Play()
	TweenService:Create(toastStroke, ti, { Transparency = 0.4 }):Play()
	task.delay(1.6, function()
		if id ~= toastId or dead then return end
		local to = TweenInfo.new(0.3)
		TweenService:Create(toast, to, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		TweenService:Create(toastStroke, to, { Transparency = 1 }):Play()
	end)
end

--------------------------------------------------------------------
-- СИДЕНИЕ НА МЕСТЕ + ОПУСКАНИЕ ТЕЛА
--------------------------------------------------------------------
local Rig = {}
local sitStamp = 0
local sitApplied, realSat = false, false
local sitTrack, savedMove

local hipBase = nil          -- исходный HipHeight текущего персонажа
local dropActive = false     -- мы сейчас меняем HipHeight
local crouchCur, sitCur = 0, 0 -- сглаженные значения опускания
local lastRootY, lastTotalDrop, lastDropChange = nil, 0, 0 -- чтобы руки опускались вместе с телом

local function standUp()
	local hum = Rig.hum
	if sitApplied and hum and hum.Parent and savedMove then
		pcall(function()
			hum.WalkSpeed = savedMove.speed
			hum.JumpPower = savedMove.jp
			hum.JumpHeight = savedMove.jh
		end)
	end
	if sitTrack then
		pcall(function() sitTrack:Stop(0.2) end)
		sitTrack = nil
	end
	sitApplied = false
	savedMove = nil
end

local function sitDown()
	local hum = Rig.hum
	if not (hum and hum.Parent) then return end
	savedMove = { speed = hum.WalkSpeed, jp = hum.JumpPower, jh = hum.JumpHeight }
	sitApplied = true
	pcall(function()
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.JumpHeight = 0
	end)
	-- анимация сидения (стандартная Roblox)
	pcall(function()
		local animator = hum:FindFirstChildOfClass("Animator")
		if not animator then return end
		local anim = Instance.new("Animation")
		anim.AnimationId = (hum.RigType == Enum.HumanoidRigType.R15) and SIT_ANIM_R15 or SIT_ANIM_R6
		local track = animator:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action4
		track.Looped = true
		track:Play(0.2)
		sitTrack = track
	end)
end

local function applySit()
	sitStamp = os.clock()
	local hum = Rig.hum
	if not (hum and hum.Parent) then return end
	if sitApplied then standUp() end
	if Config.Sit and Config.RealSit then
		pcall(function() hum.Sit = true end)
		realSat = true
	else
		if realSat then
			pcall(function() hum.Sit = false end)
			realSat = false
		end
		if Config.Sit then sitDown() end
	end
end

-- плавно опускаем корень персонажа через HipHeight (тело, голова и руки едут вместе)
local function updateDrop(dt, hum)
	local k = 1 - math.exp(-12 * dt)
	crouchCur = crouchCur + (Config.BodyDrop - crouchCur) * k
	local sitWant = (Config.Sit and not Config.RealSit) and Config.SitDrop or 0
	sitCur = sitCur + (sitWant - sitCur) * k
	if not (hum and hum.Parent and hipBase) then return end
	local total = crouchCur + sitCur
	if total > 0.005 then
		local want = hipBase - total
		if math.abs(hum.HipHeight - want) > 1e-3 then hum.HipHeight = want end
		dropActive = true
	elseif dropActive then
		hum.HipHeight = hipBase
		dropActive = false
	end
end

--------------------------------------------------------------------
-- ОПЦИИ
--------------------------------------------------------------------
local optionListeners = {}
local OptionNames = {
	Sit = "🪑 Сидение", RealSit = "🪑 Режим Humanoid.Sit", AimMode = "🎯 Прицел",
	Mirror = "🪞 Зеркало", LockL = "🔒 Левая рука", LockR = "🔒 Правая рука",
	SplitDepth = "↔ Раздельная глубина", DanceHop = "🦘 Прыжки в такт", LegBend = "🦵 Сгибание ног", RestView = "👁 Руки перед глазами",
}

local function setOption(key, val, silent)
	if Config[key] == val then return end
	Config[key] = val
	if key == "Sit" or key == "RealSit" then applySit() end
	for _, f in ipairs(optionListeners[key] or {}) do f(val) end
	if not silent and OptionNames[key] then
		showToast(OptionNames[key] .. (val and ": вкл" or ": выкл"))
	end
end

local function onOption(key, fn)
	optionListeners[key] = optionListeners[key] or {}
	table.insert(optionListeners[key], fn)
	fn(Config[key])
end

--------------------------------------------------------------------
-- ВЫБОР ПОЗ
--------------------------------------------------------------------
local poseButtons, quickPoseButtons = {}, {}

local function paintPoses()
	for _, e in ipairs(poseButtons) do
		local on = State.pose == e.pose.key
		e.btn.BackgroundColor3 = on and T.pink or T.item
		e.btn.TextColor3 = on and T.bg or T.text
		e.stroke.Transparency = on and 0 or 0.8
	end
	for key, q in pairs(quickPoseButtons) do
		local on = State.pose == key
		q.btn.BackgroundColor3 = on and q.color or T.bg
		q.btn.BackgroundTransparency = on and 0.05 or 0.3
	end
end

local function setPose(key)
	if State.pose == key then
		State.pose = nil
		showToast("↩ Поза снята")
	else
		State.pose = key
		State.poseStart = os.clock()
		-- «Опустить» — по-настоящему опускает: снимает фиксацию рук
		if key == "hands_down" then
			setOption("LockL", false, true)
			setOption("LockR", false, true)
		end
		local p = Poses[key]
		showToast(p.emoji .. " " .. p.name)
	end
	paintPoses()
end

--------------------------------------------------------------------
-- HUD: ДЖОЙСТИКИ И СЛАЙДЕРЫ
--------------------------------------------------------------------
local function makeJoystick(pos, color, tag)
	local pad = mk("Frame", {
		Size = UDim2.fromOffset(JOY, JOY), Position = pos, BackgroundColor3 = T.bg,
		BackgroundTransparency = 0.45, BorderSizePixel = 0, Active = true,
	}, hud)
	round(pad, JOY / 2)
	outline(pad, color, 2, 0.5)
	local ring = mk("Frame", {
		Size = UDim2.fromOffset(JOY * 0.5, JOY * 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1,
	}, pad)
	round(ring, JOY / 4)
	outline(ring, color, 1, 0.8)
	mk("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = tag,
		Font = Enum.Font.GothamBlack, TextSize = 18, TextColor3 = color, TextTransparency = 0.7,
	}, pad)
	local thumb = mk("Frame", {
		Size = UDim2.fromOffset(46, 46), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = color,
		BackgroundTransparency = 0.1, BorderSizePixel = 0,
	}, pad)
	round(thumb, 23)
	outline(thumb, T.text, 2, 0.7)

	local obj = { vec = Vector2.zero, dragging = false }
	makeDrag(pad, {
		began = function() obj.dragging = true end,
		moved = function(d)
			local m = d.Magnitude
			if m < 3 then
				obj.vec = Vector2.zero
				return
			end
			local dir = d.Unit
			obj.vec = Vector2.new(dir.X, -dir.Y) * (math.min(m, JOY_R) / JOY_R)
		end,
		ended = function() obj.dragging = false end,
	})
	function obj.update(dt)
		if not obj.dragging then
			obj.vec = obj.vec:Lerp(Vector2.zero, 1 - 0.86 ^ (dt * 60))
		end
		thumb.Position = UDim2.new(0.5, obj.vec.X * JOY_R, 0.5, -obj.vec.Y * JOY_R)
	end
	return obj
end

-- rest = значение, к которому возвращает двойной тап (по умолчанию 0 = середина)
local function makeVSlider(pos, height, color, icon, rest)
	rest = rest or 0
	local f = mk("Frame", {
		Size = UDim2.fromOffset(38, height), Position = pos, BackgroundColor3 = T.bg,
		BackgroundTransparency = 0.45, BorderSizePixel = 0, Active = true,
	}, hud)
	round(f, 12)
	outline(f, color, 2, 0.55)
	mk("TextLabel", {
		Text = icon, Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, TextSize = 12,
		Font = Enum.Font.GothamBold, TextColor3 = T.text,
	}, f)
	local travel = (height - 52) / 2
	local bar = mk("Frame", {
		Size = UDim2.new(0, 4, 1, -52), Position = UDim2.new(0.5, -2, 0, 26),
		BackgroundColor3 = T.off, BorderSizePixel = 0,
	}, f)
	round(bar, 2)
	local knob = mk("Frame", {
		Size = UDim2.fromOffset(28, 28), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = color, BorderSizePixel = 0,
	}, f)
	round(knob, 14)
	outline(knob, T.text, 2, 0.7)

	local obj = { value = rest, onChange = nil }
	local function render() knob.Position = UDim2.new(0.5, 0, 0.5, -obj.value * travel) end
	function obj.set(v)
		obj.value = math.clamp(v, -1, 1)
		render()
	end
	local function user(v)
		obj.set(v)
		if obj.onChange then obj.onChange(obj.value) end
	end
	local startV, lastTap = 0, 0
	makeDrag(f, {
		began = function()
			local n = os.clock()
			if n - lastTap < 0.3 then user(rest) end
			lastTap = n
			startV = obj.value
		end,
		moved = function(d) user(startV - d.Y / travel) end,
	})
	render()
	return obj
end

local sliderRender = {} -- key -> функция перерисовки слайдера в меню

local joyL = makeJoystick(UDim2.new(0, 20, 1, -150), T.pink, "L")
local joyR = makeJoystick(UDim2.new(1, -140, 1, -150), T.blue, "R")
local depthL = makeVSlider(UDim2.new(0, 148, 1, -165), 135, Color3.fromRGB(255, 140, 170), "↕Z")
local depthR = makeVSlider(UDim2.new(1, -186, 1, -165), 135, Color3.fromRGB(160, 210, 255), "↕Z")
local headSlider = makeVSlider(UDim2.new(0, 8, 0, 58), 130, T.yellow, "🧍")
-- слайдер опускания всего тела: вверху = стоим, внизу = максимально низко
local bodySlider = makeVSlider(UDim2.new(0, 54, 0, 58), 130, T.mint, "⬇", 1)

depthL.onChange = function(v) if not Config.SplitDepth then depthR.set(v) end end
depthR.onChange = function(v) if not Config.SplitDepth then depthL.set(v) end end
onOption("SplitDepth", function(v) if not v then depthR.set(depthL.value) end end)

local function setDrop(v)
	Config.BodyDrop = math.clamp(v, 0, MAX_DROP)
	bodySlider.set(1 - 2 * Config.BodyDrop / MAX_DROP)
	if sliderRender.BodyDrop then sliderRender.BodyDrop() end
end
bodySlider.onChange = function(v)
	Config.BodyDrop = (1 - v) / 2 * MAX_DROP
	if sliderRender.BodyDrop then sliderRender.BodyDrop() end
end

local function toggleCrouch()
	if Config.BodyDrop > 0.05 then
		setDrop(0)
		showToast("🧍 Встал")
	else
		setDrop(1.3)
		showToast("🧎 Присел")
	end
end

local uiHidden = false
onOption("ShowHUD", function(v) hud.Visible = v and not uiHidden end)

local reseed
local function resetAll()
	State.pose = nil
	for _, k in ipairs({ "Sit", "AimMode", "Mirror", "LockL", "LockR" }) do setOption(k, false, true) end
	headSlider.set(0)
	depthL.set(0)
	depthR.set(0)
	setDrop(0)
	reseed()
	paintPoses()
	showToast("🔄 Сброс")
end

--------------------------------------------------------------------
-- ВЕРХНИЕ КРУЖОЧКИ
--------------------------------------------------------------------
local function circle(parent, order, icon, color, size)
	local b = mk("TextButton", {
		Size = UDim2.fromOffset(size or 38, size or 38), BackgroundColor3 = T.bg, BackgroundTransparency = 0.3,
		Text = icon, TextSize = 16, Font = Enum.Font.GothamBold, TextColor3 = T.text,
		AutoButtonColor = false, BorderSizePixel = 0, LayoutOrder = order,
	}, parent)
	round(b, 22)
	outline(b, color, 2, 0.4)
	return b
end

local quick = mk("Frame", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8),
	AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1,
}, gui)
mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
}, quick)

local function modeBtn(order, icon, key, color, onClick)
	local b = circle(quick, order, icon, color, 38)
	if key then
		onOption(key, function(v)
			b.BackgroundColor3 = v and color or T.bg
			b.BackgroundTransparency = v and 0.05 or 0.3
		end)
	end
	bind(b.MouseButton1Click, onClick or function() setOption(key, not Config[key]) end)
	return b
end
modeBtn(1, "🪑", "Sit", T.purple)
modeBtn(2, "🎯", "AimMode", T.mint)
modeBtn(3, "🪞", "Mirror", T.blue)
modeBtn(4, "🔒L", "LockL", T.pink)
modeBtn(5, "🔒R", "LockR", T.blue)
local crouchBtn = modeBtn(6, "🧎", nil, T.mint, toggleCrouch)
modeBtn(7, "🔄", nil, T.yellow, resetAll)
modeBtn(8, "👁", "RestView", T.pink)

local animBar = mk("ScrollingFrame", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 52), Size = UDim2.new(1, -200, 0, 42),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0, CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X,
}, gui)
mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
	VerticalAlignment = Enum.VerticalAlignment.Center, HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, animBar)

do
	local sitB = circle(animBar, 0, "🪑", T.purple, 40)
	onOption("Sit", function(v)
		sitB.BackgroundColor3 = v and T.purple or T.bg
		sitB.BackgroundTransparency = v and 0.05 or 0.3
	end)
	bind(sitB.MouseButton1Click, function() setOption("Sit", not Config.Sit) end)

	for i, key in ipairs(QuickPoses) do
		local p = Poses[key]
		if p then
			local color = palette[(i - 1) % #palette + 1]
			local b = circle(animBar, i, p.emoji, color, 40)
			quickPoseButtons[key] = { btn = b, color = color }
			bind(b.MouseButton1Click, function() setPose(key) end)
		end
	end
end

--------------------------------------------------------------------
-- ОКНО С ВКЛАДКАМИ
--------------------------------------------------------------------
local WIN_W, WIN_H = 300, 290
local win = mk("Frame", {
	Name = "Window", Size = UDim2.fromOffset(WIN_W, WIN_H), Position = UDim2.new(1, -WIN_W - 12, 0, 100),
	BackgroundColor3 = T.bg, BackgroundTransparency = 0.06, BorderSizePixel = 0, Visible = false, Active = true,
}, gui)
round(win, 14)
outline(win, T.pink, 1.5, 0.5)

local titleBar = mk("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, Active = true }, win)
mk("TextLabel", {
	Text = "✨ VR Kawaii v5.1", Size = UDim2.new(1, -80, 1, 0), Position = UDim2.fromOffset(12, 0),
	TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBold, TextSize = 14,
	TextColor3 = T.text, BackgroundTransparency = 1,
}, titleBar)

local function titleBtn(offsetX, text)
	local b = mk("TextButton", {
		Size = UDim2.fromOffset(26, 22), Position = UDim2.new(1, offsetX, 0, 6), BackgroundColor3 = T.item,
		BackgroundTransparency = 0.2, Text = text, TextColor3 = T.text, Font = Enum.Font.GothamBold,
		TextSize = 12, AutoButtonColor = false, BorderSizePixel = 0,
	}, win)
	round(b, 7)
	return b
end
local collapseBtn = titleBtn(-62, "—")
local closeBtn = titleBtn(-32, "✕")

local winStartPos
makeDrag(titleBar, {
	began = function() winStartPos = win.Position end,
	moved = function(d)
		win.Position = UDim2.new(
			winStartPos.X.Scale, winStartPos.X.Offset + d.X,
			winStartPos.Y.Scale, winStartPos.Y.Offset + d.Y
		)
	end,
})

local body = mk("Frame", { Size = UDim2.new(1, 0, 1, -36), Position = UDim2.fromOffset(0, 36), BackgroundTransparency = 1 }, win)
local collapsed = false
bind(collapseBtn.MouseButton1Click, function()
	collapsed = not collapsed
	body.Visible = not collapsed
	win.Size = collapsed and UDim2.fromOffset(WIN_W, 36) or UDim2.fromOffset(WIN_W, WIN_H)
	collapseBtn.Text = collapsed and "▢" or "—"
end)
bind(closeBtn.MouseButton1Click, function() win.Visible = false end)

local tabsBar = mk("Frame", { Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(8, 0), BackgroundTransparency = 1 }, body)
mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, tabsBar)

local pages, tabButtons = {}, {}
local function selectTab(i)
	for idx, p in ipairs(pages) do p.Visible = (idx == i) end
	for idx, b in ipairs(tabButtons) do
		b.BackgroundColor3 = (idx == i) and T.pink or T.item
		b.TextColor3 = (idx == i) and T.bg or T.text
	end
end
local function addTab(order, text)
	local b = mk("TextButton", {
		Size = UDim2.new(1 / 4, -3, 1, 0), BackgroundColor3 = T.item, Text = text, Font = Enum.Font.GothamBold,
		TextSize = 11, TextColor3 = T.text, AutoButtonColor = false, BorderSizePixel = 0, LayoutOrder = order,
	}, tabsBar)
	round(b, 8)
	tabButtons[order] = b
	bind(b.MouseButton1Click, function() selectTab(order) end)
end
addTab(1, "✨ Позы")
addTab(2, "🎮 Упр.")
addTab(3, "🧍 Тело")
addTab(4, "👁 Вид")

local PAGE_POS, PAGE_SIZE = UDim2.fromOffset(8, 30), UDim2.new(1, -16, 1, -36)

local function newListPage()
	local sf = mk("ScrollingFrame", {
		Size = PAGE_SIZE, Position = PAGE_POS, BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 3, ScrollBarImageColor3 = T.pink, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false,
	}, body)
	mk("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, sf)
	mk("UIPadding", { PaddingRight = UDim.new(0, 5) }, sf)
	pages[#pages + 1] = sf
	return sf
end

local function rowFrame(class, parent, h, order)
	local r = mk(class, {
		Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = T.item, BackgroundTransparency = 0.2,
		BorderSizePixel = 0, LayoutOrder = order,
	}, parent)
	round(r, 8)
	return r
end
local function rowLabel(parent, text, w)
	return mk("TextLabel", {
		Text = text, Size = UDim2.new(1, w or -60, 0, 28), Position = UDim2.fromOffset(10, 0),
		BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = T.text,
	}, parent)
end

local function addToggle(parent, order, text, key)
	local row = rowFrame("TextButton", parent, 30, order)
	row.Text = ""
	row.AutoButtonColor = false
	rowLabel(row, text)
	local pill = mk("Frame", {
		Size = UDim2.fromOffset(38, 20), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
		BackgroundColor3 = T.off, BorderSizePixel = 0,
	}, row)
	round(pill, 10)
	local dot = mk("Frame", {
		Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 10, 0.5, 0),
		BackgroundColor3 = T.text, BorderSizePixel = 0,
	}, pill)
	round(dot, 8)
	onOption(key, function(v)
		local ti = TweenInfo.new(0.15)
		TweenService:Create(pill, ti, { BackgroundColor3 = v and T.pink or T.off }):Play()
		TweenService:Create(dot, ti, { Position = UDim2.new(0, v and 28 or 10, 0.5, 0) }):Play()
	end)
	bind(row.MouseButton1Click, function() setOption(key, not Config[key]) end)
end

local function addSlider(parent, scroller, order, text, key, min, max, step, fmt, onChange)
	local row = rowFrame("Frame", parent, 44, order)
	row.Active = true
	rowLabel(row, text, -80)
	local val = mk("TextLabel", {
		Size = UDim2.new(0, 70, 0, 28), Position = UDim2.new(1, -78, 0, 0), BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = T.blue,
	}, row)
	local track = mk("Frame", {
		Size = UDim2.new(1, -20, 0, 6), Position = UDim2.new(0, 10, 1, -14), BackgroundColor3 = T.off, BorderSizePixel = 0,
	}, row)
	round(track, 3)
	local fill = mk("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.blue, BorderSizePixel = 0 }, track)
	round(fill, 3)
	local dot = mk("Frame", {
		Size = UDim2.fromOffset(14, 14), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
		BackgroundColor3 = T.text, BorderSizePixel = 0,
	}, track)
	round(dot, 7)
	local function render()
		local a = (Config[key] - min) / (max - min)
		fill.Size = UDim2.fromScale(a, 1)
		dot.Position = UDim2.new(a, 0, 0.5, 0)
		val.Text = type(fmt) == "function" and fmt(Config[key]) or string.format(fmt, Config[key])
	end
	render()
	sliderRender[key] = render
	local startVal
	makeDrag(row, {
		began = function()
			startVal = Config[key]
			scroller.ScrollingEnabled = false
		end,
		moved = function(d)
			local w = math.max(track.AbsoluteSize.X, 1)
			local v = startVal + d.X / w * (max - min)
			Config[key] = math.clamp(math.round(v / step) * step, min, max)
			render()
			if onChange then onChange(Config[key]) end
		end,
		ended = function() scroller.ScrollingEnabled = true end,
	})
end

local function addButton(parent, order, text, color, fn)
	local b = rowFrame("TextButton", parent, 30, order)
	b.Text = text
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	b.TextColor3 = T.text
	b.AutoButtonColor = false
	outline(b, color, 1.5, 0.4)
	bind(b.MouseButton1Click, fn)
end

-- ВКЛАДКА 1: ПОЗЫ
local posePage = mk("Frame", { Size = PAGE_SIZE, Position = PAGE_POS, BackgroundTransparency = 1 }, body)
pages[1] = posePage

local search = mk("TextBox", {
	Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = T.item, BackgroundTransparency = 0.2,
	PlaceholderText = "🔍 Поиск позы...", PlaceholderColor3 = T.sub, Text = "", ClearTextOnFocus = false,
	Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = T.text, BorderSizePixel = 0,
}, posePage)
round(search, 8)

local chips = mk("ScrollingFrame", {
	Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 30), BackgroundTransparency = 1,
	BorderSizePixel = 0, ScrollBarThickness = 0, CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X,
}, posePage)
mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, chips)

local grid = mk("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, -60), Position = UDim2.fromOffset(0, 60), BackgroundTransparency = 1,
	BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = T.pink, CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, posePage)
mk("UIGridLayout", {
	CellSize = UDim2.new(1 / 3, -5, 0, 32), CellPadding = UDim2.fromOffset(5, 5), SortOrder = Enum.SortOrder.LayoutOrder,
}, grid)

local filterCat, filterText = "Все", ""
local function refreshGrid()
	for _, e in ipairs(poseButtons) do
		local okCat = (filterCat == "Все") or e.pose.cat == filterCat
		local okText = filterText == "" or e.hay:find(filterText, 1, true) ~= nil
		e.btn.Visible = okCat and okText
	end
end

for i, p in ipairs(PoseList) do
	local b = mk("TextButton", {
		BackgroundColor3 = T.item, BackgroundTransparency = 0.15, Text = p.emoji .. " " .. p.name,
		Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = T.text, TextTruncate = Enum.TextTruncate.AtEnd,
		AutoButtonColor = false, BorderSizePixel = 0, LayoutOrder = i,
	}, grid)
	round(b, 8)
	local st = outline(b, T.pink, 1, 0.8)
	poseButtons[#poseButtons + 1] = { btn = b, stroke = st, pose = p, hay = lower(p.name) .. " " .. p.key }
	bind(b.MouseButton1Click, function() setPose(p.key) end)
end

local chipButtons = {}
for i, cat in ipairs(Categories) do
	local c = mk("TextButton", {
		Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.item,
		Text = cat, Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = T.text,
		AutoButtonColor = false, BorderSizePixel = 0, LayoutOrder = i,
	}, chips)
	round(c, 12)
	mk("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, c)
	chipButtons[cat] = c
	bind(c.MouseButton1Click, function()
		filterCat = cat
		for name, btn in pairs(chipButtons) do
			btn.BackgroundColor3 = (name == cat) and T.mint or T.item
			btn.TextColor3 = (name == cat) and T.bg or T.text
		end
		refreshGrid()
	end)
end
chipButtons["Все"].BackgroundColor3 = T.mint
chipButtons["Все"].TextColor3 = T.bg

bind(search:GetPropertyChangedSignal("Text"), function()
	local ok, res = pcall(lower, search.Text)
	filterText = ok and res or ""
	refreshGrid()
end)

-- ВКЛАДКА 2: УПРАВЛЕНИЕ
local ctrlPage = newListPage()
addToggle(ctrlPage, 0, "👁 Руки перед глазами", "RestView")
addToggle(ctrlPage, 1, "🎯 Прицел: руки за камерой", "AimMode")
addToggle(ctrlPage, 2, "🪞 Зеркало (R двигает обе)", "Mirror")
addToggle(ctrlPage, 3, "🔒 Зафиксировать левую руку", "LockL")
addToggle(ctrlPage, 4, "🔒 Зафиксировать правую руку", "LockR")
addToggle(ctrlPage, 5, "↔ Раздельная глубина рук", "SplitDepth")
addToggle(ctrlPage, 6, "🌊 Живое покачивание рук", "IdleSway")
addToggle(ctrlPage, 7, "💨 Дыхание головы", "Breathing")
addToggle(ctrlPage, 8, "🦘 Прыгать в такт танцу", "DanceHop")
addSlider(ctrlPage, ctrlPage, 9, "Чувствительность", "Sensitivity", 0.5, 2, 0.05, "%.2f×")
addSlider(ctrlPage, ctrlPage, 10, "Сила покачивания", "SwayAmount", 0, 2, 0.05, "%.2f×")
addSlider(ctrlPage, ctrlPage, 11, "Авто-снятие позы", "AutoReturn", 0, 10, 1, function(v)
	return v == 0 and "выкл" or string.format("%.0f с", v)
end)
addSlider(ctrlPage, ctrlPage, 12, "🕹 Джойстик в позах (0 = выкл)", "PoseJoy", 0, 1.5, 0.05, "%.2f×")

-- ВКЛАДКА 3: ТЕЛО (присед, сидение)
local bodyPage = newListPage()
addSlider(bodyPage, bodyPage, 1, "⬇ Опустить всё тело", "BodyDrop", 0, MAX_DROP, 0.05, "%.2f", function(v)
	bodySlider.set(1 - 2 * v / MAX_DROP)
end)
addToggle(bodyPage, 2, "🦵 Сгибать ноги (R15, видно только тебе)", "LegBend")
addButton(bodyPage, 3, "🧎 Присесть / встать", T.mint, toggleCrouch)
addToggle(bodyPage, 4, "🪑 Сидение (на месте)", "Sit")
addSlider(bodyPage, bodyPage, 5, "Насколько присесть при сидении", "SitDrop", 0, 1.8, 0.05, "%.2f")
addToggle(bodyPage, 6, "🪑 Садиться на сиденья (Humanoid.Sit)", "RealSit")

-- ВКЛАДКА 4: ВИД
local viewPage = newListPage()
addToggle(viewPage, 1, "🕹 Показывать джойстики", "ShowHUD")
addToggle(viewPage, 2, "🙈 Скрывать голову (от 1-го лица)", "HideHead")
addToggle(viewPage, 3, "👐 Скрывать свои руки", "HideArms")
addSlider(viewPage, viewPage, 4, "Поле зрения (FOV)", "FOV", 50, 120, 1, "%.0f°")
addSlider(viewPage, viewPage, 5, "Отзывчивость рук", "Smooth", 0.05, 0.6, 0.01, "%.2f")
addSlider(viewPage, viewPage, 6, "Частота отправки", "SendRate", 10, 60, 1, "%.0f Гц")
addButton(viewPage, 7, "🔄 Сбросить всё", T.yellow, resetAll)

local unload
addButton(viewPage, 8, "🗑 Выгрузить скрипт", Color3.fromRGB(255, 100, 100), function() unload() end)

selectTab(1)

--------------------------------------------------------------------
-- КНОПКИ ☰ И 👁
--------------------------------------------------------------------
local menuBtn = mk("TextButton", {
	Size = UDim2.fromOffset(38, 38), Position = UDim2.new(1, -50, 0, 8), BackgroundColor3 = T.bg,
	BackgroundTransparency = 0.25, Text = "☰", TextSize = 18, Font = Enum.Font.GothamBold,
	TextColor3 = T.text, AutoButtonColor = false, BorderSizePixel = 0, Visible = false,
}, gui)
round(menuBtn, 19)
outline(menuBtn, T.mint, 2, 0.5)
bind(menuBtn.MouseButton1Click, function() win.Visible = not win.Visible end)

local eyeBtn = mk("TextButton", {
	Size = UDim2.fromOffset(38, 38), Position = UDim2.new(1, -94, 0, 8), BackgroundColor3 = T.bg,
	BackgroundTransparency = 0.25, Text = "👁", TextSize = 16, Font = Enum.Font.GothamBold,
	TextColor3 = T.text, AutoButtonColor = false, BorderSizePixel = 0, Visible = false,
}, gui)
round(eyeBtn, 19)
outline(eyeBtn, T.pink, 2, 0.5)

local function setUIHidden(v)
	uiHidden = v
	hud.Visible = (not v) and Config.ShowHUD
	quick.Visible = not v
	animBar.Visible = not v
	menuBtn.Visible = not v
	if v then win.Visible = false end
	eyeBtn.Text = v and "🙈" or "👁"
	eyeBtn.BackgroundTransparency = v and 0.6 or 0.25
	if v then showToast("🙈 Интерфейс скрыт — нажми 🙈 чтобы вернуть") end
end
bind(eyeBtn.MouseButton1Click, function() setUIHidden(not uiHidden) end)

bind(UserInputService.InputBegan, function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.RightShift then
		win.Visible = not win.Visible
	elseif input.KeyCode == Enum.KeyCode.C then
		toggleCrouch()
	end
end)

-- прыжок = встать из сидения
bind(UserInputService.JumpRequest, function()
	if Config.Sit then setOption("Sit", false) end
end)

--------------------------------------------------------------------
-- РИГ ПЕРСОНАЖА
--------------------------------------------------------------------
local headParts, armParts = {}, {}
local ARM_NAMES = {
	["Left Arm"] = true, ["Right Arm"] = true, LeftUpperArm = true, RightUpperArm = true,
	LeftLowerArm = true, RightLowerArm = true, LeftHand = true, RightHand = true,
}

-- noclip для рук: запоминаем, у каких частей мы выключили CanCollide, чтобы вернуть при выгрузке
local origCollide = setmetatable({}, { __mode = "k" })
local function noclipLimbs()
	for _, p in ipairs(armParts) do
		if p.Parent and p.CanCollide then
			origCollide[p] = true
			p.CanCollide = false
		end
	end
end

local function classify(d)
	if d:IsA("BasePart") then
		if d.Name == "Head" then
			headParts[#headParts + 1] = d
		elseif ARM_NAMES[d.Name] then
			armParts[#armParts + 1] = d
		elseif d.Parent and d.Parent:IsA("Accessory") then
			local att = d:FindFirstChildOfClass("Attachment")
			if att and (att.Name:find("Hat") or att.Name:find("Hair") or att.Name:find("Face")) then
				headParts[#headParts + 1] = d
			end
		end
	elseif d:IsA("Decal") and d.Parent and d.Parent.Name == "Head" then
		headParts[#headParts + 1] = d
	end
end

-- плечо + (для R15) локоть и запястье, которые держим прямыми
local function buildArm(c, side)
	local sh = c:FindFirstChild(side .. " Shoulder", true) or c:FindFirstChild(side .. "Shoulder", true)
	if not (sh and sh:IsA("Motor6D") and sh.Part0 and sh.Part1) then return nil end
	local arm = { sh = sh }
	local el = c:FindFirstChild(side .. "Elbow", true)
	local wr = c:FindFirstChild(side .. "Wrist", true)
	if el and el:IsA("Motor6D") then arm.el = el end
	if wr and wr:IsA("Motor6D") then arm.wr = wr end
	-- длина руки от центра плеча до кончика кисти: нужна, чтобы кисть была там, где задано
	local len
	if arm.el and arm.wr and arm.wr.Part1 then
		len = math.abs(arm.el.C0.Position.Y)
			+ math.abs(arm.wr.C0.Position.Y - arm.el.C1.Position.Y)
			+ arm.wr.Part1.Size.Y / 2 + arm.wr.C1.Position.Y
	else
		len = sh.Part1.Size.Y / 2
	end
	arm.len = math.clamp(len, 0.8, 3.5)
	return arm
end

-- ноги R15: бёдро, колено, лодыжка + длины костей для сгибания
local function buildLeg(c, side)
	local hip = c:FindFirstChild(side .. "Hip", true)
	local knee = c:FindFirstChild(side .. "Knee", true)
	local ankle = c:FindFirstChild(side .. "Ankle", true)
	if not (hip and knee and ankle) then return nil end
	if not (hip:IsA("Motor6D") and knee:IsA("Motor6D") and ankle:IsA("Motor6D")) then return nil end
	local a = (knee.C0.Position - hip.C1.Position).Magnitude
	local b = (ankle.C0.Position - knee.C1.Position).Magnitude
	if a < 0.2 or b < 0.2 then return nil end
	return { hip = hip, knee = knee, ankle = ankle, a = a, b = b, D0 = a + b, active = false }
end

local function scanMotors()
	local c = Rig.char
	if not c then return end
	Rig.neck = Rig.neck or c:FindFirstChild("Neck", true)
	Rig.armL = Rig.armL or buildArm(c, "Left")
	Rig.armR = Rig.armR or buildArm(c, "Right")
	Rig.legL = Rig.legL or buildLeg(c, "Left")
	Rig.legR = Rig.legR or buildLeg(c, "Right")
end

local inited = false

local function hookCharacter(char)
	for k in pairs(Rig) do Rig[k] = nil end
	table.clear(headParts)
	table.clear(armParts)
	sitApplied, realSat, sitTrack, savedMove = false, false, nil, nil
	hipBase, dropActive = nil, false
	lastRootY = nil
	inited = false
	if Config.Sit then setOption("Sit", false, true) end
	Rig.char = char
	task.spawn(function()
		local root = char:WaitForChild("HumanoidRootPart", 10)
		local hum = char:WaitForChild("Humanoid", 10)
		if not root or not hum or Rig.char ~= char or dead then return end
		Rig.root, Rig.hum = root, hum
		task.wait(0.4)
		if Rig.char ~= char or dead then return end
		hipBase = hum.HipHeight
		scanMotors()
		for _, tr in ipairs(hum:GetPlayingAnimationTracks()) do tr:Stop(0) end
		for _, d in ipairs(char:GetDescendants()) do classify(d) end
		noclipLimbs()
	end)
	bind(char.DescendantAdded, function(d)
		task.delay(0.2, function()
			if Rig.char == char and not dead then
				classify(d)
				noclipLimbs()
			end
		end)
	end)
end

bind(plr.CharacterAdded, hookCharacter)
if plr.Character then hookCharacter(plr.Character) end

local function setModifier(list, v)
	for i = #list, 1, -1 do
		local p = list[i]
		if p.Parent then p.LocalTransparencyModifier = v else table.remove(list, i) end
	end
end

local function updateVisibility()
	local firstPerson = (cam.CFrame.Position - cam.Focus.Position).Magnitude < 5
	setModifier(headParts, (Config.HideHead and firstPerson) and 1 or 0)
	setModifier(armParts, Config.HideArms and 1 or 0) -- руки скина видны всегда, пока не скрыты вручную
end

--------------------------------------------------------------------
-- РУКИ: как в твоём скрипте — родная рука ставится прямо в CFrame цели
-- (Part1.CFrame = handCF), локоть и запястье прямые.
--------------------------------------------------------------------
local currentL, currentR = CFrame.new(), CFrame.new()
local headCF = CFrame.new()
local headOff = CFrame.new()

local function driveArm(arm, handCF)
	local sh = arm.sh
	if not (sh.Parent and sh.Part0) then return end
	sh.Transform = sh.C0:Inverse() * sh.Part0.CFrame:Inverse() * handCF * sh.C1
	if arm.el and arm.el.Parent then arm.el.Transform = CFrame.new() end
	if arm.wr and arm.wr.Parent then arm.wr.Transform = CFrame.new() end
end

-- сгибание ног при приседе: двухкостный IK в вертикальной плоскости,
-- лодыжка остаётся под бедром, стопа остаётся ровной
local function applyLegs()
	local on = Config.LegBend and not Config.Sit and crouchCur > 0.03
	for _, leg in ipairs({ Rig.legL or false, Rig.legR or false }) do
		if leg and leg.hip.Parent and leg.knee.Parent and leg.ankle.Parent then
			if on then
				local a, b = leg.a, leg.b
				local L = a + b
				local D = math.clamp(leg.D0 - crouchCur, L * 0.25, leg.D0)
				local ca = math.clamp((a * a + D * D - b * b) / (2 * a * D), -1, 1)
				local cp = math.clamp((a * a + b * b - D * D) / (2 * a * b), -1, 1)
				local alpha = math.acos(ca)       -- бедро вперёд
				local bend = pi - math.acos(cp)   -- сгиб колена
				local gamma = bend - alpha        -- голень назад
				leg.hip.Transform = CFrame.Angles(alpha, 0, 0)
				leg.knee.Transform = CFrame.Angles(-bend, 0, 0)
				leg.ankle.Transform = CFrame.Angles(gamma, 0, 0)
				leg.active = true
			elseif leg.active then
				leg.hip.Transform = CFrame.new()
				leg.knee.Transform = CFrame.new()
				leg.ankle.Transform = CFrame.new()
				leg.active = false
			else
				-- пока стоим на земле, измеряем реальное расстояние бедро–лодыжка
				local hum = Rig.hum
				if hum and not Config.Sit and crouchCur < 0.02 and hum.FloorMaterial ~= Enum.Material.Air
					and hum.MoveDirection.Magnitude < 0.1 and leg.hip.Part0 and leg.ankle.Part0 then
					local hp = (leg.hip.Part0.CFrame * leg.hip.C0).Position
					local ap = (leg.ankle.Part0.CFrame * leg.ankle.C0).Position
					local dy = hp.Y - ap.Y
					local L = leg.a + leg.b
					if dy > L * 0.5 and dy <= L * 1.02 then
						leg.D0 = leg.D0 + (math.min(dy, L) - leg.D0) * 0.1
					end
				end
			end
		end
	end
end

local function applyMotors()
	local neck = Rig.neck
	if neck and neck.Parent and neck.Part0 then
		neck.Transform = neck.C0:Inverse() * neck.Part0.CFrame:Inverse() * headCF * neck.C1
	end
	if Rig.armL then driveArm(Rig.armL, currentL) end
	if Rig.armR then driveArm(Rig.armR, currentR) end
	applyLegs()
end

--------------------------------------------------------------------
-- СЛУЧАЙНОЕ ПОКАЧИВАНИЕ (формулы из твоего скрипта, у каждой руки своё)
--------------------------------------------------------------------
local Idle = {
	L = { cycle = 0, speed = 1.3, inten = 0.2, rotK = 0.8 },
	R = { cycle = 0, speed = 1.3, inten = 0.2, rotK = 0.9 },
}

reseed = function()
	for _, s in pairs(Idle) do
		s.speed = math.random(10, 18) / 10   -- скорость 1.0–1.8
		s.inten = math.random(15, 30) / 100  -- амплитуда 0.15–0.30
		s.cycle = math.random() * 20
	end
end
reseed()

-- sw = вверх/вниз, sd = вбок, rot = наклон
local function idleOffsets(s)
	if not Config.IdleSway then return 0, 0, 0 end
	local k = Config.SwayAmount
	local sw = sin(s.cycle) * s.inten * k
	local sd = cos(s.cycle * 0.7) * s.inten * 0.6 * k
	local rot = sin(s.cycle * s.rotK) * 12 * k
	return sw, sd, rot
end

local function freeHand(b, sgn, joy, depth, s)
	local sens = Config.Sensitivity
	local sw, sd, rot = idleOffsets(s)
	local pos = Vector3.new(
		sgn * b.x + joy.X * b.gx * sens + sd,
		b.y + joy.Y * b.gy * sens + sw,
		b.z - depth * 1.5
	)
	local rotCF = CFrame.Angles(
		rad(b.rx + joy.Y * 50 + rot),
		rad(-joy.X * 25 + sd * 20),
		rad(sgn * b.rz + sw * 15)
	)
	return CFrame.new(pos) * rotCF
end

-- «руки перед глазами»: кисть задаётся в системе взгляда (курсор камеры),
-- поэтому всегда в кадре. Стик двигает кисть вбок/вверх/вниз, ползунок Z — дальше/ближе.
local function viewFrame(eye)
	local look = cam.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local pitch = math.asin(math.clamp(look.Y, -1, 1))
	return CFrame.new(eye) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch * 0.75, 0, 0)
end

local function viewHand(frame, sgn, joy, depth, s, arm)
	local sens = Config.Sensitivity
	local sw, sd, rot = idleOffsets(s)
	local hand = Vector3.new(
		sgn * 0.55 + joy.X * 1.4 * sens + sd,
		-0.7 + joy.Y * 1.2 * sens + sw,
		-1.7 - depth * 1.2
	)
	local theta = rad(14 - joy.Y * 28 + rot * 0.5 + sw * 12) -- наклон вниз
	local phi = rad(-sgn * 5 + joy.X * 20 + sd * 20)          -- поворот вбок
	local dirW = frame:VectorToWorldSpace(Vector3.new(
		sin(phi) * cos(theta), -sin(theta), -cos(phi) * cos(theta)
	))
	local len = (arm and arm.len) or 2
	local pos = frame:PointToWorldSpace(hand) - dirW * len -- центр руки так, чтобы КИСТЬ была в точке hand
	local up = -dirW
	local right = frame.RightVector
	right = right - up * right:Dot(up)
	if right.Magnitude < 1e-3 then right = Vector3.new(1, 0, 0) end
	return CFrame.fromMatrix(pos, right.Unit, up)
end

-- лёгкое покачивание поверх поз
local function poseSway(s)
	if not Config.IdleSway then return CFrame.new() end
	local k = Config.SwayAmount * 0.4
	return CFrame.new(cos(s.cycle * 0.7) * s.inten * 0.6 * k, sin(s.cycle) * s.inten * k, 0)
end

-- джойстик и ползунок глубины сдвигают руку ПОВЕРХ любой позы:
-- стик вниз = руки вниз, вверх = вверх, в стороны = в стороны
local function poseAdjust(cf, joy, depth)
	local k = Config.PoseJoy
	if k <= 0 then return cf end
	local s = Config.Sensitivity * k
	local b = Base.stand
	local off = Vector3.new(joy.X * b.gx * s, joy.Y * b.gy * s, -depth * 1.5 * k)
	if off.Magnitude < 0.001 then return cf end
	local tilt = CFrame.Angles(rad(joy.Y * 50 * k), rad(-joy.X * 25 * k), 0)
	return CFrame.new(cf.Position + off) * (tilt * cf.Rotation)
end

--------------------------------------------------------------------
-- ГЛАВНЫЙ ЦИКЛ
--------------------------------------------------------------------
local lockedRelL, lockedRelR
local lastSend, lastScan, lastHop, lastNoclip = 0, 0, 0, 0

local function step(dt)
	cam = workspace.CurrentCamera or cam
	if cam.FieldOfView ~= Config.FOV then cam.FieldOfView = Config.FOV end

	joyL.update(dt)
	joyR.update(dt)

	local root, hum = Rig.root, Rig.hum
	if root and root.Parent then
		local now = os.clock()
		if not (Rig.neck and Rig.armL and Rig.armR and Rig.legL and Rig.legR) and now - lastScan > 1 then
			lastScan = now
			scanMotors()
		end

		-- noclip для рук: игра могла вернуть CanCollide обратно — выключаем снова
		if now - lastNoclip > 0.5 then
			lastNoclip = now
			noclipLimbs()
		end

		-- сидение на месте: держим параметры, пока сидим
		if sitApplied and savedMove and hum then
			if hum.WalkSpeed ~= 0 then hum.WalkSpeed = 0 end
			if hum.JumpPower ~= 0 then hum.JumpPower = 0 end
			if hum.JumpHeight ~= 0 then hum.JumpHeight = 0 end
		end
		-- старый режим Humanoid.Sit: прыжок снимает сидение
		if Config.Sit and Config.RealSit and hum and not hum.Sit and now - sitStamp > 0.8 then
			setOption("Sit", false)
		end

		-- опускание всего тела (присед / сидение)
		updateDrop(dt, hum)

		-- пока тело опускается/поднимается, руки едут вместе с ним без отставания
		local totalDrop = crouchCur + sitCur
		if math.abs(totalDrop - lastTotalDrop) > 1e-4 then lastDropChange = now end
		lastTotalDrop = totalDrop
		local rootY = root.Position.Y
		if lastRootY and inited and now - lastDropChange < 0.6 then
			local dy = rootY - lastRootY
			if math.abs(dy) < 3 then
				local off = Vector3.new(0, dy, 0)
				currentL = currentL + off
				currentR = currentR + off
			end
		end
		lastRootY = rootY

		-- независимые циклы покачивания для каждой руки
		for _, s in pairs(Idle) do s.cycle = s.cycle + dt * s.speed end

		local rootCF = root.CFrame
		local bob = Config.Breathing and sin(now * 1.7) * 0.012 or 0
		local a = 1 - (1 - Config.Smooth) ^ (dt * 60)

		local headPos = rootCF.Position + Vector3.new(0, HEAD_BASE + headSlider.value * 1.5 + bob, 0)
		local bodyCF = rootCF

		local jl, jr = joyL.vec, joyR.vec
		local zl, zr = depthL.value, depthR.value
		if not Config.SplitDepth then zr = zl end
		if Config.Mirror then
			jl = Vector2.new(-jr.X, jr.Y)
			zl = zr
		end

		local pose = State.pose and Poses[State.pose]
		local e = 0
		if pose then
			e = now - State.poseStart
			if Config.AutoReturn > 0 and e > Config.AutoReturn then
				State.pose = nil
				pose = nil
				paintPoses()
			end
		end

		-- прыжки в такт танцу
		if pose and pose.hop and Config.DanceHop and hum and not Config.Sit and now - lastHop > pose.hop then
			lastHop = now
			if hum.FloorMaterial ~= Enum.Material.Air then hum.Jump = true end
		end

		local targetL, targetR
		local targetHead = CFrame.new()
		if pose then
			local l, r, hh
			if pose.fn then l, r, hh = pose.fn(e) else l, r, hh = pose.l, pose.r, pose.h end
			if hh then targetHead = hh end
			-- стик и глубина двигают позу (вниз = руки опускаются)
			l = poseAdjust(l, jl, zl)
			r = poseAdjust(r, jr, zr)
			targetL = bodyCF * l * poseSway(Idle.L)
			targetR = bodyCF * r * poseSway(Idle.R)
		else
			local mode = Config.AimMode and "aim" or (Config.Sit and "sit" or "stand")
			if mode ~= "aim" and Config.RestView then
				local vf = viewFrame(headPos)
				targetL = viewHand(vf, -1, jl, zl, Idle.L, Rig.armL)
				targetR = viewHand(vf, 1, jr, zr, Idle.R, Rig.armR)
			else
				local frame = (mode == "aim") and (CFrame.new(headPos) * cam.CFrame.Rotation) or bodyCF
				local b = Base[mode]
				targetL = frame * freeHand(b, -1, jl, zl, Idle.L)
				targetR = frame * freeHand(b, 1, jr, zr, Idle.R)
			end
		end

		-- голова: камера + поворот позы
		headOff = headOff:Lerp(targetHead, a)
		headCF = CFrame.new(headPos) * cam.CFrame.Rotation * headOff

		-- фиксация (относительно тела)
		if Config.LockL and lockedRelL then targetL = rootCF * lockedRelL
		else lockedRelL = rootCF:ToObjectSpace(targetL) end
		if Config.LockR and lockedRelR then targetR = rootCF * lockedRelR
		else lockedRelR = rootCF:ToObjectSpace(targetR) end

		-- простое сглаживание, как в твоём скрипте
		if not inited
			or (currentL.Position - targetL.Position).Magnitude > 20
			or (currentR.Position - targetR.Position).Magnitude > 20 then
			currentL, currentR = targetL, targetR
			inited = true
		else
			currentL = currentL:Lerp(targetL, a)
			currentR = currentR:Lerp(targetR, a)
		end

		-- отправка остальным игрокам
		if now - lastSend >= 1 / Config.SendRate then
			lastSend = now
			remote:FireServer(headCF, currentL, currentR)
		end
	end

	updateVisibility()
	applyMotors()
end

RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Last.Value, step)
bind(RunService.Stepped, applyMotors)

--------------------------------------------------------------------
-- ВЫГРУЗКА
--------------------------------------------------------------------
unload = function()
	if dead then return end
	dead = true
	pcall(function() RunService:UnbindFromRenderStep(RENDER_NAME) end)
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	table.clear(conns)
	standUp()
	if realSat and Rig.hum then pcall(function() Rig.hum.Sit = false end) end
	if hipBase and Rig.hum then pcall(function() Rig.hum.HipHeight = hipBase end) end
	for _, list in ipairs({ headParts, armParts }) do
		for _, p in ipairs(list) do pcall(function() p.LocalTransparencyModifier = 0 end) end
	end
	for p in pairs(origCollide) do pcall(function() p.CanCollide = true end) end
	local motors = { Rig.neck }
	for _, arm in ipairs({ Rig.armL or false, Rig.armR or false }) do
		if arm then
			motors[#motors + 1] = arm.sh
			motors[#motors + 1] = arm.el
			motors[#motors + 1] = arm.wr
		end
	end
	for _, leg in ipairs({ Rig.legL or false, Rig.legR or false }) do
		if leg then
			motors[#motors + 1] = leg.hip
			motors[#motors + 1] = leg.knee
			motors[#motors + 1] = leg.ankle
		end
	end
	for _, m in ipairs(motors) do
		if m then pcall(function() m.Transform = CFrame.new() end) end
	end
	pcall(function() gui:Destroy() end)
	env.__KawaiiVR = nil
end
env.__KawaiiVR = { Destroy = unload }

--------------------------------------------------------------------
-- ИНТРО
--------------------------------------------------------------------
hud.Visible = false
local intro = mk("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Active = true,
}, gui)
mk("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 192, 203)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(135, 206, 250)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 162, 255)),
	}),
	Rotation = 45,
}, intro)
local introText = mk("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 100),
	BackgroundTransparency = 1, Text = "✨ VR KAWAII v5.1 ✨", TextColor3 = T.text,
	TextSize = 38, Font = Enum.Font.GothamBlack, TextTransparency = 1,
}, intro)
local introStroke = mk("UIStroke", { Color = T.pink, Thickness = 4, Transparency = 1 }, introText)

task.spawn(function()
	task.wait(0.3)
	if dead then return end
	local fi = TweenInfo.new(0.9, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(introText, fi, { TextTransparency = 0 }):Play()
	TweenService:Create(introStroke, fi, { Transparency = 0.3 }):Play()
	task.wait(1.6)
	if dead then return end
	local fo = TweenInfo.new(0.7, Enum.EasingStyle.Quad)
	TweenService:Create(introText, fo, { TextTransparency = 1 }):Play()
	TweenService:Create(introStroke, fo, { Transparency = 1 }):Play()
	TweenService:Create(intro, fo, { BackgroundTransparency = 1 }):Play()
	task.wait(0.75)
	if dead then return end
	intro:Destroy()
	hud.Visible = Config.ShowHUD and not uiHidden
	menuBtn.Visible = not uiHidden
	eyeBtn.Visible = true
	showToast("✨ Готово! Слайдер ⬇ слева или кнопка 🧎 — опустить всё тело")
end)

print("✨ VR KAWAII v5.1 загружен ✨")
