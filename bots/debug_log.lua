module("debug_log", package.seeall)

local debug_on = true

local move_msg_template = [[
Time: %f
Health: %d
Mana: %d
Level: %f
Lane status: %f
Ally loc 1: (%f, %f)
Ally loc 2: (%f, %f)
Ally loc 3: (%f, %f)
Ally loc 4: (%f, %f)
Ally loc 5: (%f, %f)
Enemy loc 1: (%f, %f)
Enemy loc 2: (%f, %f)
Enemy loc 3: (%f, %f)
Enemy loc 4: (%f, %f)
Enemy loc 5: (%f, %f)
]]

function Debug(msg)
	if debug_on then
		local bot = GetBot()

		if bot then
			Msg("[dota2_nn] " .. bot:GetUnitName() .. " " .. msg .. "\n")
		else
			Msg("[dota2_nn] anon-e-moose " .. msg .. "\n")
		end
	end
end

function DebugMove(input)
	if debug_on then
		Debug("Move input:")
		Debug(string.format(move_msg_template, unpack(input)))
	end
end
