-- Theme: cores, gradientes, fontes, tempos e z-order. Valores vêm do design (HUD v3 / Mobile).
local function hex(h) return Color3.fromHex(h) end
local function pair(a, b) return { hex(a), hex(b) } end

local Theme = { hex = hex, pair = pair }

-- Área segura de referência = telemóvel 844x390 com insets 47/47/21 -> 750x369.
-- Tudo é desenhado nestas unidades; o Stage aplica UIScale para outros ecrãs.
Theme.REF = Vector2.new(750, 369)

Theme.Colors = {
	Outline = hex("0D1119"), Dark = hex("15171C"), White = hex("FFFFFF"), Black = hex("000000"),
	Muted = hex("CFCFD3"), Muted2 = hex("B4B4B8"), Cash = hex("6AE454"), Gold = hex("FFD23C"),
	GoldLight = hex("FFE066"), Danger = hex("FF6A5C"), Warn = hex("FFB04A"), Xp = hex("7FD0FF"),
	Toast = hex("28282A"), Bar = hex("1A1D23"), BarXp = hex("26272B"), Locked = hex("0E1014"),
	Cyan = hex("3FD6FF"), Ok = hex("5FBF10"), Badge = hex("E7413B"), Sand = hex("F4EAD2"),
}

Theme.Grad = {
	Green = pair("7FE46C", "4FC441"), GreenB = pair("62D650", "44B944"), GreenC = pair("6FDC68", "44B944"),
	Red = pair("F0625C", "D63F3B"), RedBtn = pair("F0625C", "CF3934"), Close = pair("E8423B", "C92A24"),
	Blue = pair("5AA8F0", "3382D6"), BlueIdx = pair("3A9CF5", "2787E0"), Orange = pair("FFB853", "F7962B"),
	Pink = pair("F06CBA", "D6479A"), Purple = pair("A06CF0", "7D45D6"), Gold = pair("FFD75A", "F0AA1C"),
	Yellow = pair("FFE066", "F0B81C"), Grey = pair("8C8D91", "6C6D71"), Cyan = pair("22D0DC", "0BA3B4"),
	Xp = pair("7DDCFF", "3AA6F0"), Strip = pair("5C5C5E", "444446"), Header = pair("6E6F73", "535457"),
	Neutral = pair("A8A9AE", "7B7C81"), Forest = pair("5FD44A", "36A228"), Desert = pair("FFBE4E", "F08A1C"),
	Battle = pair("FF8A3C", "E0561C"), Catch = pair("C58BFF", "8A45E0"), Heal = pair("7DDCFF", "2F9FE8"),
	HpGood = pair("7AE860", "4CC33A"), HpMid = pair("FFE066", "F0B81C"), HpLow = pair("FF7466", "E0342A"),
	NodeGreen = pair("4FD146", "3FBD37"), NodeSel = pair("5EE0FF", "2FC6F2"), NodeMax = pair("8EF76C", "6CE64C"),
	NodeHidden = pair("353A44", "2A2E36"), NodeOT = pair("3A3F49", "2A2E36"), NodeOTSel = pair("3D5566", "2C3D4A"),
	Featured = pair("FFD23C", "FF5A9E"), Victory = pair("FFD75A", "F0A81C"), Caught = pair("B98CFF", "7D45D6"),
	Escaped = pair("8C8D91", "5C5D61"), Defeat = pair("F0625C", "B5231E"),
}

Theme.Rarity = {
	Common = pair("5CB8FF", "2F86E8"), Uncommon = pair("8FE35A", "3FAE2A"),
	Rare = pair("C58BFF", "8A45E0"), Neutral = pair("D9C9A6", "A8916A"),
}

Theme.Fonts = {
	-- Measured from the source HTML: Montserrat 900 for titles/buttons, Fredoka 700 for numbers.
	-- Roblox cannot import fonts and has no Fredoka family, so numbers use Fredoka One.
	Title = Font.fromName("Montserrat", Enum.FontWeight.Heavy),
	Num = Font.fromName("FredokaOne"),
	Bold = Font.fromName("Montserrat", Enum.FontWeight.Bold),
	Medium = Font.fromName("Montserrat", Enum.FontWeight.Medium),
	Body = Font.fromName("Montserrat", Enum.FontWeight.SemiBold),
	Label = Font.fromName("Montserrat", Enum.FontWeight.Heavy),
}

-- Tempos (segundos) do design
Theme.T = { Pop = 0.45, Fade = 0.25, Press = 0.08, Toast = 0.5, Bar = 0.6, BarSlow = 0.95, Leaderboard = 0.35, Shake = 0.4, Blur = 0.35, Card = 0.4 }

-- Z-order dos ecrãs (irmãos do Stage)
Theme.Z = { Battle = 2, HUD = 3, Panel = 20, Starter = 22, Research = 25, Toasts = 30, Modal = 40, Summary = 50, Count = 60 }

return Theme
