package builder

import (
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/dotabuff/manta"
	"github.com/dotabuff/manta/dota"
)

/* Represents a player to pay attention to in the first pass. */
type TopPlayer struct {
	Kills int32
	Name  string
}

type Hero struct {
	Team          uint64
	Entindex      int32
	PreviousItems map[int]struct{}
	LastInventorySave uint32
}

/* Current corpora. */
var corpora = Corpora{Corpora: make(map[string][]*Corpus)}

/*
	Retrieves the top 3 players on the winning team and also gets the start time of the match (horn) in ticks.
*/
func FirstPass(filehandle *os.File) (map[int32]*TopPlayer, uint32, int32) {
	parser := CreateParser(filehandle)

	var startTime uint32
	var winningTeam int32
	var teamIndex int32

	top3 := make(map[int32]*TopPlayer)
	teamComposition := make(map[string]uint64)

	parser.OnEntity(func(ent *manta.Entity, _ manta.EntityOp) error {
		classname := ent.GetClassName()

		if winningTeam != 0 {
			if teamIndex != 0 && len(top3) > 0 {
				parser.Stop()
			} else if classname == "CDOTA_PlayerResource" {
				for i := (winningTeam - 2) * 5; i < (winningTeam-1)*5; i++ {
					id := fmt.Sprintf("%04d", i)
	
					if kills, ok := ent.GetInt32("m_vecPlayerTeamData." + id + ".m_iKills"); ok { // kill count
						if name, ok := ent.GetString("m_vecPlayerData." + id + ".m_iszPlayerName"); ok { // name
							if len(top3) < 3 {
								top3[i] = &TopPlayer{kills, name}
							} else {
								minIndex := MinIndex(top3)
	
								if minPlayer, _ := top3[minIndex]; minPlayer.Kills < kills { // higher than lowest top 3 player, replace
									delete(top3, minIndex)
									top3[i] = &TopPlayer{kills, name}
								}
							}
						}
					}
				}
			} else if (winningTeam == 2 && classname == "CDOTA_DataRadiant") || classname == "CDOTA_DataDire" {
				teamIndex = ent.GetIndex()
			}
		} else if startTime == 0 && classname == RUNE {
			startTime = parser.Tick
		} else if IsHero(ent) {
			name := GetHammerName(parser, ent)

			if _, ok := teamComposition[name]; !ok {
				if team, ok := ent.GetUint64("m_iTeamNum"); ok {
					teamComposition[name] = team
				}
			}
		} else if classname == ANCIENT {
			if health, ok := ent.GetInt32("m_iHealth"); ok && health <= 0 { // ancient dead?
				if team, ok := ent.GetUint64("m_iTeamNum"); ok {
					winningTeam = int32(team) ^ 1 // get the enemy team of the team whose ancient just died (2 ^ 1 == 3, 3 ^ 1 == 2)
				} else {
					log.Fatalf("Error retrieving m_iTeamNum from ancient (tick %d)\n", parser.Tick)
				}
			}
		}

		return nil
	})

	parser.Start()

	corpora.Teams = append(corpora.Teams, teamComposition)

	return top3, startTime, teamIndex
}

/*
	Tracks the actions of the top 3 players on the winning team and constructs examples out of each action.
*/
func SecondPass(filehandle *os.File, top3 map[int32]*TopPlayer, startTime uint32, teamIndex int32) {
	parser := CreateParser(filehandle)

	heroes := make(map[string]*Hero)
	//creep_front := [2]float32{

	parser.OnEntity(func(ent *manta.Entity, _ manta.EntityOp) error {
		if IsHero(ent) {
			hero, ok := heroes[ent.GetClassName()]

			if !ok {
				team, _ := ent.GetUint64("m_iTeamNum")
				heroes[ent.GetClassName()] = &Hero{team, ent.GetIndex(), make(map[int]struct{}), 0}
			} else if hero.Entindex == ent.GetIndex() && parser.Tick / ITEM_PERIOD > hero.LastInventorySave {
				id, ok := ent.GetInt32("m_iPlayerID")

				if _, isTop3 := top3[id]; ok && isTop3 {
					name := GetHammerName(parser, ent)

					team, _ := ent.GetUint64("m_iTeamNum")
					corpus := corpora.GetCorpus(name)[team-2]

					example := &BuildExample{}

					for itemCount := 0; ; itemCount++ {
						if itemHandle, ok := ent.GetUint64(fmt.Sprintf("m_hItems.%04d", itemCount)); ok {
							if item := parser.FindEntity(Handle(itemHandle)); item != nil {
								if name := GetHammerName(parser, item); name != "" {
									id := GetID(corpus.ObservedItems, name)
									example.CurrentInventory[id] = struct{}{}

									if _, ok := hero.PreviousItems[id]; !ok {
										example.NewItems = append(example.NewItems, id)
									}
								}
							}
						} else {
							break
						}
					}

					hero.PreviousItems = example.CurrentInventory

					if len(example.NewItems) > 0 {
						teamID := id % 5
						teamEnt := parser.FindEntity(teamIndex)

						reliableGold, _ := teamEnt.GetInt32(fmt.Sprintf("m_vecDataTeam.%04d.m_iReliableGold", teamID))
						unreliableGold, _ := teamEnt.GetInt32(fmt.Sprintf("m_vecDataTeam.%04d.m_iUnreliableGold", teamID))

						example.DotaTime = DotaTime(parser.Tick, startTime)
						example.Gold = float32(reliableGold + unreliableGold) / 10000.0

						WriteToCorpus(example, corpus.Item)

						hero.LastInventorySave = parser.Tick / ITEM_PERIOD
					}
				}
			}
		}

		return nil
	})

	/* Callback for every unit action. */
	parser.Callbacks.OnCDOTAUserMsg_SpectatorPlayerUnitOrders(func(msg *dota.CDOTAUserMsg_SpectatorPlayerUnitOrders) error {
		if len(msg.GetUnits()) > 0 {
			for _, unit := range msg.GetUnits() { // multiple units can be selected
				entity := parser.FindEntity(unit)

				if entity != nil {
					if IsHero(entity) { // replace with any criterion for producing examples
						id, ok := entity.GetInt32("m_iPlayerID")

						if _, isTop3 := top3[id]; ok && isTop3 {
							/* Construct feature vector. */
							name := GetHammerName(parser, entity)

							team, _ := entity.GetUint64("m_iTeamNum")
							corpus := corpora.GetCorpus(name)[team-2]
							abilityPrefix := strings.SplitN(name, "dota_hero_", 2)[1]

							example := &MoveExample{}

							target := msg.GetTargetIndex()
							ability := msg.GetAbilityIndex()

							coords := GetLocation(entity)

							// Targeted ability or attack
							if target != 0 {
								example.IsAttack = 1.0

								if target == unit {
									example.Target = TargetSelf
									example.MoveX = coords[0]
									example.MoveY = coords[1]
								} else if targetEnt := parser.FindEntity(target); targetEnt != nil {
									targetCoords := GetLocation(targetEnt)

									example.MoveX = targetCoords[0]
									example.MoveY = targetCoords[1]

									if IsHero(targetEnt) {
										targetTeam, _ := targetEnt.GetUint64("m_iTeamNum")

										if targetTeam == team {
											example.Target = TargetFriendlyHero
										} else {
											example.Target = TargetEnemyHero
										}
									} else {
										switch targetEnt.GetClassName() {
										case LANE_CREEP:
											if ability == 0 { // don't bother generating examples for regular attacks
												continue
											} else {
												example.Target = TargetLane
											}

										case JUNGLE_CREEP:
											example.Target = TargetJungle
										case TOWER:
											example.Target = TargetTower
										default:
											example.Target = TargetBuilding
										}
									}
								} else {
									// Manta corner case: packet entities are updated before callbacks so destroyed entities (eaten trees, picked up runes) are gone by this point
									//log.Fatalf("Error retrieving an attack target (entindex %d, tick %d, player %v)\n", target, parser.Tick, entity)
									example.Target = TargetTree // assume tree was eaten for now
									example.MoveX = coords[0]
									example.MoveY = coords[1]
								}
							}

							example.AbilityUsed = 1
							example.ItemUsed = 1

							// Ability used (not necessarily targeted)
							if ability != 0 {
								example.IsAttack = 1.0

								if target == 0 { // CWorld (self or location)
									example.Target = TargetSelf
									example.MoveX = coords[0]
									example.MoveY = coords[1]
								}

								if abilityEnt := parser.FindEntity(ability); abilityEnt != nil {
									if IsItem(abilityEnt) { // item
										if name := GetHammerName(parser, abilityEnt); name != "" {
											example.ItemUsed = GetID(corpus.ObservedActiveItems, name) + 1
										}
									} else if IsAbility(abilityEnt) { // ability
										if name := GetHammerName(parser, abilityEnt); strings.HasPrefix(name, abilityPrefix) {
											example.AbilityUsed = GetID(corpus.ObservedActiveAbilities, name) + 1
										}
									}
								} else {
									// Could be caused by leveling an ability? Silence for now
									//log.Fatalf("Error retrieving an ability (entindex %d, tick %d, player %v)\n", ability, parser.Tick, entity)
									continue
								}
							}

							health, _ := entity.GetInt32("m_iHealth")
							maxHealth, _ := entity.GetInt32("m_iMaxHealth")
							mana, _ := entity.GetFloat32("m_flMana")
							maxMana, _ := entity.GetFloat32("m_flMaxMana")
							level, _ := entity.GetInt32("m_iCurrentLevel")

							movePos := msg.GetPosition()

							example.DotaTime = DotaTime(parser.Tick, startTime)   // DotaTime()
							example.Health = float32(health) / float32(maxHealth) // :GetHealth()
							example.Mana = mana / maxMana                         // :GetMana()
							example.Level = float32(level) / 25.0                 // :GetCurrentLevel()
							example.CreepFront = 0.0                              // GetLaneFrontAmount() FIXME

							// my position
							example.CurrentX = coords[0]
							example.CurrentY = coords[1]

							// everyone else's position
							ally := 0
							enemy := 4

							for _, hero := range heroes {
								if hero.Entindex == entity.GetIndex() {
									continue
								}

								loc := GetLocation(parser.FindEntity(hero.Entindex))

								if hero.Team == team {
									example.OtherX[ally] = loc[0]
									example.OtherY[ally] = loc[1]
									ally++
								} else {
									example.OtherX[enemy] = loc[0]
									example.OtherY[enemy] = loc[1]
									enemy++
								}
							}

							// Retrieve ability cooldowns
							abilityID := 0
							for abilityCount := 0; ; abilityCount++ {
								if abilityHandle, ok := entity.GetUint64(fmt.Sprintf("m_hAbilities.%04d", abilityCount)); ok {
									if ability := parser.FindEntity(Handle(abilityHandle)); ability != nil {
										if name := GetHammerName(parser, ability); strings.HasPrefix(name, abilityPrefix) {
											if level, ok := ability.GetInt32("m_iLevel"); level == 0 || !ok {
												example.AbilityCooldowns = append(example.AbilityCooldowns, 1.0)
											} else if cooldown, ok := ability.GetFloat32("m_fCooldown"); ok {
												example.AbilityCooldowns = append(example.AbilityCooldowns, cooldown/COOLDOWN_SCALE)
											}

											if len(corpus.ObservedAbilities) <= abilityID {
												corpus.ObservedAbilities = append(corpus.ObservedAbilities, name)
											}

											abilityID++
										}
									}
								} else {
									break
								}
							}

							// Retrieve current items
							for itemCount := 0; ; itemCount++ {
								if itemHandle, ok := entity.GetUint64(fmt.Sprintf("m_hItems.%04d", itemCount)); ok {
									if item := parser.FindEntity(Handle(itemHandle)); item != nil {
										if name := GetHammerName(parser, item); name != "" {
											example.CurrentItems = append(example.CurrentItems, GetID(corpus.ObservedItems, name))
										}
									}
								} else {
									break
								}
							}

							if movePos != nil {
								example.MoveX = RemapX(movePos.GetX())
								example.MoveY = RemapY(movePos.GetY())
							}

							WriteToCorpus(example, corpus.Move)
						}
					}
				}
			}
		}

		return nil
	})

	parser.Start()
}

func Start() {
	defer corpora.CloseCorpora()

	log.SetOutput(os.Stdout)

	if err := os.Mkdir("data", 493); err != nil && !os.IsExist(err) {
		log.Fatal("Can't create data folder")
	}

	if len(os.Args) == 1 {
		log.Fatal("usage: corpus_build <demos...>")
	}

	for i, demoName := range os.Args[1:] {
		log.Printf("Demo %d (%s)\n", i+1, demoName)

		filehandle := OpenDemo(demoName)
		defer filehandle.Close()

		top3, startTime, teamIndex := FirstPass(filehandle) // retrieve top 3 players

		for id, player := range top3 {
			log.Println(id, player.Name, player.Kills)
		}

		filehandle.Seek(0, 0) // go back to beginning of demo

		SecondPass(filehandle, top3, startTime, teamIndex) // make examples
	}
}
