require "bots/data/ability_data"
require "bots/dota2_nn/util"

local function ChooseHeroes()
	-- selects heroes for all the bots
	local ids = GetTeamPlayers(GetTeam())

	util.Debug("selecting team composition")

	local team = ability_data.teams[RandomInt(1, #ability_data.teams)][GetTeam()]

	util.Debug("assigning heroes: ")

	for i, id in ipairs(ids) do
		if IsPlayerBot(id) then
			util.Debug(i)
			util.Debug(id .. " (" .. i .. "): " .. team[i])

			SelectHero(id, team[i])
		end
	end

	heroesSelected = true
end

function Think()
	ChooseHeroes()

	Think = function() end
end
