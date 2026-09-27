--!strict
-- Number and time formatting for big simulator numbers.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "Ud", "Dd", "Td", "Qad", "Qid" }

-- 1234 -> "1.23K", 999 -> "999", 1.5e15 -> "1.5Qa"
function Format.short(n: number): string
	if n ~= n then
		return "0"
	end
	local negative = n < 0
	n = math.abs(n)
	if n < 1000 then
		local s = if n % 1 == 0 then tostring(math.floor(n)) else string.format("%.1f", n)
		return if negative then "-" .. s else s
	end
	local tier = math.min(#SUFFIXES - 1, math.floor(math.log10(n) / 3))
	local scaled = n / 10 ^ (tier * 3)
	local text
	if scaled >= 100 then
		text = string.format("%d", math.floor(scaled))
	elseif scaled >= 10 then
		text = string.format("%.1f", math.floor(scaled * 10) / 10)
	else
		text = string.format("%.2f", math.floor(scaled * 100) / 100)
	end
	text = text:gsub("%.?0+$", "")
	return (if negative then "-" else "") .. text .. SUFFIXES[tier + 1]
end

-- 1234567 -> "1,234,567"
function Format.commas(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""):gsub("^%-,", "-"))
end

-- 3725 -> "1h 2m", 65 -> "1m 05s", 9 -> "9s"
function Format.duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor(seconds % 3600 / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%dh %dm", h, m)
	elseif m > 0 then
		return string.format("%dm %02ds", m, s)
	end
	return string.format("%ds", s)
end

-- 65 -> "1:05"
function Format.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local m = math.floor(seconds / 60)
	return string.format("%d:%02d", m, seconds % 60)
end

-- 0.0049 -> "0.49%", 0.0000012 -> "1 in 833,333"
function Format.chance(p: number): string
	if p <= 0 then
		return "0%"
	end
	if p < 0.0001 then
		return "1 in " .. Format.commas(math.floor(1 / p + 0.5))
	end
	local pct = p * 100
	if pct >= 10 then
		return string.format("%.1f%%", pct)
	elseif pct >= 1 then
		return string.format("%.2f%%", pct)
	end
	return (string.format("%.3f%%", pct):gsub("0+%%$", "%%"))
end

function Format.percentBonus(bonus: number): string
	return "+" .. Format.short(math.floor(bonus * 100 + 0.5)) .. "%"
end

return Format
