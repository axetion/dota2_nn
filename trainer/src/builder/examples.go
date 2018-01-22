package builder

import (
	"bufio"
	"encoding/json"
	"fmt"
	"log"
)

func WriteToCorpus(example interface{}, file *bufio.Writer) {
	if output, err := json.MarshalIndent(example, "", "\t"); err == nil {
		file.WriteString(fmt.Sprintf("%s,", output))
	} else {
		log.Fatal("Failed to serialize example")
	}
}

/* Represents a move/attack example. */
type MoveExample struct {
	MoveInputExample  `json:"input"`
	MoveOutputExample `json:"output"`
}

type MoveInputExample struct {
	DotaTime   float32 `json:"1"`
	Health     float32 `json:"2"`
	Mana       float32 `json:"3"`
	CreepFront float32 `json:"4"`
	Level      float32 `json:"5"`
	CurrentX   float32 `json:"6"`
	CurrentY   float32 `json:"7"`

	OtherX [9]float32 `json:"8"`
	OtherY [9]float32 `json:"9"`

	MoveInputLabels `json:"labels,omitempty"`
}

type MoveInputLabels struct {
	AbilityCooldowns []float32 `json:"1"`
	CurrentItems     []int     `json:"2"`
}

/* Target types. */
const (
	TargetTower = iota + 1
	TargetBuilding
	TargetSelf
	TargetTree
	TargetJungle
	TargetLane
	TargetEnemyHero
	TargetFriendlyHero
)

type MoveOutputExample struct {
	IsAttack float32 `json:"1"`
	MoveX    float32 `json:"2"`
	MoveY    float32 `json:"3"`

	MoveOutputLabels `json:"labels,omitempty"`
}

type MoveOutputLabels struct {
	Target      int `json:"1"`
	AbilityUsed int `json:"2"`
	ItemUsed    int `json:"3"`
}

/* Represents an item/ability build example. */
type BuildExample struct {
	BuildInputExample  `json:"input"`
	BuildOutputExample `json:"output"`
}

type BuildInputExample struct {
	DotaTime      float32 `json:"1"`
	Gold float32 `json:"2"`

	BuildInputLabels `json:"labels"`
}

type BuildInputLabels struct {
	Heroes           []int            `json:"1,omitempty"`
	CurrentInventory map[int]struct{} `json:"2,omitempty"`
}

type BuildOutputExample struct {
	BuildOutputLabels `json:"labels"`
}

type BuildOutputLabels struct {
	NewItems    []int `json:"1,omitempty"`
}
