package builder

import (
	"log"
	"math"
	"os"
	"strings"

	"github.com/dotabuff/manta"
)

/* Map and other game constants. */
const MIN_X = -8288.0
const MAX_X = 8288.0

const MIN_Y = -8288.0
const MAX_Y = 8288.0

const CELL_SIZE = 128.0

const COOLDOWN_SCALE = 360.0

const TICKRATE = 30
const ITEM_PERIOD = 1200

/* Useful classnames. */
const TOWER = "CDOTA_BaseNPC_Tower"
const LANE_CREEP = "CDOTA_BaseNPC_Creep_Lane"
const JUNGLE_CREEP = "CDOTA_BaseNPC_Creep_Neutral"
const ANCIENT = "CDOTA_BaseNPC_Fort"
const RUNE = "CDOTA_Item_Rune"

/* Utility functions. */
func IsHero(ent *manta.Entity) bool {
	return strings.HasPrefix(ent.GetClassName(), "CDOTA_Unit_Hero")
}

func IsItem(ent *manta.Entity) bool {
	return strings.HasPrefix(ent.GetClassName(), "CDOTA_Item")
}

func IsAbility(ent *manta.Entity) bool {
	classname := ent.GetClassName()

	return classname == "CDOTABaseAbility" || strings.HasPrefix(classname, "CDOTA_Ability") && classname != "CDOTA_Ability_AttributeBonus"
}

/* Linearly maps coordinate components to [0, 1]. */
func RemapX(x float32) float32 {
	return (x+MIN_X)/(MAX_X-MIN_X) + 1
}

func RemapY(y float32) float32 {
	return (y+MIN_Y)/(MAX_Y-MIN_Y) + 1
}

func GetID(dict map[string]int, name string) int {
	id, ok := dict[name]

	if !ok { // new item
		id = len(dict) + 1
		dict[name] = id
	}

	return id + 1
}

/*
	Retrieves the location of an entity.

	Unlike the standard m_vecOrigin netprop in most Source games, Dota 2 splits an entity's location up into two parts in replays:

	- m_cellX, m_cellY: This represents which "cell" a location is in, with the map split into 128x128 cells.
	- m_offsetX, m_offsetY: This then represents the offset of an entity within the cell, relative to its lower left corner.

	(The Dota 2 map is 16577 x 16577 with the origin at its center as of 7.02. Most current resources for this kind of thing are for 6.xx, be wary!)
	This function takes those components and turns it into a regular Cartesian coordinate, since that's what the bot API uses.
*/
func GetLocation(ent *manta.Entity) []float32 {
	cellX, _ := ent.GetUint64("CBodyComponentBaseAnimatingOverlay.m_cellX")
	cellY, _ := ent.GetUint64("CBodyComponentBaseAnimatingOverlay.m_cellY")

	offsetX, _ := ent.GetFloat32("CBodyComponentBaseAnimatingOverlay.m_vecX")
	offsetY, _ := ent.GetFloat32("CBodyComponentBaseAnimatingOverlay.m_vecY")

	return []float32{
		RemapX(float32(cellX)*CELL_SIZE - (MAX_X*2 + 1) + offsetX),
		RemapY(float32(cellY)*CELL_SIZE - (MAX_Y*2 + 1) + offsetY),
	}
}

/*
	Retrieves the Hammer name of an entity (name used by edicts, which Valve calls the classname).
	This is different from what Manta calls the "classname" (entity.GetClassName()), which is literally the name of the C++ class.
	(Isn't terminology just great).
*/
func GetHammerName(parser *manta.Parser, entity *manta.Entity) string {
	if name_index, ok := entity.GetInt32("m_pEntity.m_nameStringableIndex"); ok {
		if name, ok := parser.LookupStringByIndex("EntityNames", name_index); ok {
			return name
		}
	}

	return ""
}

/* Minimum index (for partial sorting players by kills in the first pass. No point in using a heap for just 3 elements) */
func MinIndex(top map[int32]*TopPlayer) int32 {
	best := int32(math.MaxInt32)
	bestIndex := int32(0)

	for i, player := range top {
		if player.Kills < best {
			best = player.Kills
			bestIndex = i
		}
	}

	return bestIndex
}

/* Opens a demo file. */
func OpenDemo(demo_name string) *os.File {
	filehandle, err := os.Open(demo_name)

	if err != nil {
		log.Fatal("Can't open demo")
	}

	return filehandle
}

/* Creates a Manta parser instance. */
func CreateParser(demo *os.File) *manta.Parser {
	parser, err := manta.NewStreamParser(demo)

	if err != nil {
		log.Fatalf("Unable to create parser: %s\n", err)
	}

	return parser
}

/* Converts a handle to a regular entindex. */
func Handle(i uint64) int32 {
	return int32(i&(1<<14) - 1)
}

/* Converts ticks to in-game time (rough approximation) */
func DotaTime(tick uint32, startTime uint32) float32 {
	return (float32(tick) - float32(startTime)) / (TICKRATE * 3600)
}
