// Package migrations embeds the goose SQL files so the binary migrates itself.
package migrations

import "embed"

//go:embed *.sql
var FS embed.FS
