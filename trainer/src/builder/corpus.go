package builder

import (
	"bufio"
	"bytes"
	"fmt"
	"log"
	"os"
)

/* Represents the corpus of examples for one hero. */
type Corpus struct {
	MoveFile *os.File
	ItemFile *os.File
	Move     *bufio.Writer
	Item     *bufio.Writer

	ObservedItems           map[string]int
	ObservedAbilities       []string
	ObservedActiveAbilities map[string]int
	ObservedActiveItems     map[string]int
	ObservedHeroes          map[string]int
}

func NewCorpus(move *os.File, items *os.File) *Corpus {
	moveWriter := bufio.NewWriter(move)
	itemsWriter := bufio.NewWriter(items)

	moveWriter.WriteString("[\n")
	itemsWriter.WriteString("[\n")

	return &Corpus{
		move,
		items,
		moveWriter,
		itemsWriter,
		make(map[string]int),
		[]string{},
		make(map[string]int),
		make(map[string]int),
		make(map[string]int),
	}
}

func (corpus *Corpus) Close() {
	corpus.Move.WriteString("\n]")
	corpus.Move.Flush()

	corpus.Item.WriteString("\n]")
	corpus.Item.Flush()

	corpus.MoveFile.Close()
	corpus.ItemFile.Close()
}

type Corpora struct {
	Corpora map[string][]*Corpus
	Teams   []map[string]uint64
}

/* Returns or creates new corpus files for the given hero. */
func (corpora *Corpora) GetCorpus(hero string) []*Corpus {
	if corpus, ok := corpora.Corpora[hero]; ok {
		return corpus
	} else {
		if err := os.Mkdir("data/"+hero, 493); err != nil && !os.IsExist(err) {
			log.Fatal("Can't create data folder")
		}

		radiantMoveFile, radiantMoveErr := os.Create("data/" + hero + "/2_moveexamples")
		radiantItemsFile, radiantItemErr := os.Create("data/" + hero + "/2_itemsexamples")

		if radiantMoveErr != nil || radiantItemErr != nil {
			log.Fatalf("Error creating corpus files for hero %s, team Radiant\n", hero)
		}

		direMoveFile, direMoveErr := os.Create("data/" + hero + "/3_moveexamples")
		direItemsFile, direItemErr := os.Create("data/" + hero + "/3_itemsexamples")

		if direMoveErr != nil || direItemErr != nil {
			log.Fatalf("Error creating corpus files for hero %s, team Dire\n", hero)
		}

		corpus := []*Corpus{
			NewCorpus(radiantMoveFile, radiantItemsFile),
			NewCorpus(direMoveFile, direItemsFile),
		}

		corpora.Corpora[hero] = corpus
		return corpus
	}
}

/* Closes all the opened corpora files and writes the final ability/items/team composition data. */
func (corpora *Corpora) CloseCorpora() {
	/* Write ability_data.lua */
	activeAbilities := new(bytes.Buffer)
	activeItems := new(bytes.Buffer)
	items := new(bytes.Buffer)
	abilities := new(bytes.Buffer)

	activeAbilities.WriteString("activeAbilities = {") // start of table
	activeItems.WriteString("activeItems = {")
	items.WriteString("items = {")
	abilities.WriteString("abilities = {")

	for hero, corpus := range corpora.Corpora {
		entry := fmt.Sprintf("%s={nil, {", hero) // map hero to team to abilities/items

		activeAbilities.WriteString(entry)
		activeItems.WriteString(entry)
		items.WriteString(entry)
		abilities.WriteString(entry)

		for _, team := range corpus {
			/* Add an entry for the id -> ability/item as well as ability/item -> id */
			for ability, id := range team.ObservedActiveAbilities {
				activeAbilities.WriteString(fmt.Sprintf("[%d]=\"%s\",%s=%d,", id, ability, ability, id))
			}

			for item, id := range team.ObservedActiveItems {
				activeItems.WriteString(fmt.Sprintf("[%d]=\"%s\",%s=%d,", id, item, item, id))
			}

			for item, id := range team.ObservedItems {
				items.WriteString(fmt.Sprintf("[%d]=\"%s\",%s=%d,", id, item, item, id))
			}

			for _, ability := range team.ObservedAbilities {
				abilities.WriteString(fmt.Sprintf("\"%s\",", ability))
			}

			activeAbilities.WriteString("},{") // close the table for that team
			activeItems.WriteString("},{")
			items.WriteString("},{")
			abilities.WriteString("},{")

			team.Close()
		}

		activeAbilities.WriteString("}},") // close the table for that hero
		activeItems.WriteString("}},")
		items.WriteString("}},")
		abilities.WriteString("}},")
	}

	activeAbilities.WriteString("}\n")
	activeItems.WriteString("}\n")
	items.WriteString("}\n")
	abilities.WriteString("}\n")

	if observedFile, err := os.Create("ability_data.lua"); err == nil || os.IsExist(err) {
		writer := bufio.NewWriter(observedFile)

		defer observedFile.Close()
		defer writer.Flush()

		writer.WriteString("-- This is an automatically generated file. Do not modify.\n")
		writer.WriteString("module(\"ability_data\", package.seeall)\n")

		writer.WriteString(activeAbilities.String())
		writer.WriteString(activeItems.String())
		writer.WriteString(items.String())
		writer.WriteString(abilities.String())

		/* Also write team data (which isn't per corpus which is why we're doing it down here) */
		writer.WriteString("teams = {")

		for _, team := range corpora.Teams {
			radiant := new(bytes.Buffer)
			dire := new(bytes.Buffer)

			for hero, team_num := range team {
				if team_num == 2 {
					radiant.WriteString(fmt.Sprintf("\"%s\",", hero))
				} else {
					dire.WriteString(fmt.Sprintf("\"%s\",", hero))
				}
			}

			writer.WriteString("{nil, {")
			writer.WriteString(radiant.String())
			writer.WriteString("},{")
			writer.WriteString(dire.String())
			writer.WriteString("}},")
		}

		writer.WriteString("}\n")
	} else {
		log.Fatalf("Error creating ability_data.lua")
	}
}
