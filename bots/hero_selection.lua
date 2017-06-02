require "bots/ability_data"
require "bots/debug_log"

local heroesSelected = false

function Think()
	if not heroesSelected then
		ChooseHeroes()
	end
end

function ChooseHeroes()
	-- selects heroes for all the bots
	local ids = GetTeamPlayers(GetTeam())

	debug_log.Debug("selecting team composition")

	local team = ability_data.teams[RandomInt(1, #ability_data.teams)][GetTeam()]

	debug_log.Debug("assigning heroes: ")

	for i, id in ipairs(ids) do
		if IsPlayerBot(id) then
			debug_log.Debug(i)
			debug_log.Debug(id .. " (" .. i .. "): " .. team[i])
			SelectHero(id, team[i])
		end
	end

	heroesSelected = true
end
