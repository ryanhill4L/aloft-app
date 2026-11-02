package store

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/pressly/goose/v3"
	"github.com/stretchr/testify/require"

	"aloft/migrations"
)

// Runs only with ALOFT_TEST_DATABASE_URL set, against a disposable Neon
// branch. Rows are scoped to a random prefix and deleted afterwards.
func openTestDB(t *testing.T) *sql.DB {
	t.Helper()
	url := os.Getenv("ALOFT_TEST_DATABASE_URL")
	if url == "" {
		t.Skip("ALOFT_TEST_DATABASE_URL not set")
	}
	ctx := context.Background()
	db, err := Open(ctx, url)
	require.NoError(t, err)
	goose.SetBaseFS(migrations.FS)
	require.NoError(t, goose.SetDialect("postgres"))
	require.NoError(t, goose.UpContext(ctx, db, "."))
	t.Cleanup(func() { db.Close() })
	return db
}

func TestPostgresCrewFlow(t *testing.T) {
	db := openTestDB(t)
	ctx := context.Background()
	s := NewPostgres(db)
	prefix := fmt.Sprintf("it-%d-", time.Now().UnixNano())
	a, b := prefix+"a", prefix+"b"
	t.Cleanup(func() { db.Exec(`DELETE FROM profiles WHERE user_id LIKE $1`, prefix+"%") })

	p, err := s.GetOrCreateProfile(ctx, a)
	require.NoError(t, err)
	require.Equal(t, 1350, p.BedtimeMinutes)

	p.FirstName, p.Onboarded = "Ryan", true
	p, err = s.UpdateProfile(ctx, p)
	require.NoError(t, err)
	require.Equal(t, "Ryan", p.FirstName)
	_, err = s.UpdateProfile(ctx, Profile{UserID: b, FirstName: "Maya", BedtimeMinutes: 1350, WakeMinutes: 390})
	require.NoError(t, err)

	_, err = s.CrewForUser(ctx, a)
	require.ErrorIs(t, err, ErrNotFound)

	code := prefix[len(prefix)-7 : len(prefix)-1]
	crew, err := s.CreateCrew(ctx, a, code)
	require.NoError(t, err)
	_, err = s.CreateCrew(ctx, b, code)
	require.ErrorIs(t, err, ErrCodeCollision)

	_, err = s.JoinCrew(ctx, b, code, 1)
	require.ErrorIs(t, err, ErrCrewFull)
	_, err = s.JoinCrew(ctx, b, code, 12)
	require.NoError(t, err)
	_, err = s.JoinCrew(ctx, b, code, 12)
	require.ErrorIs(t, err, ErrAlreadyInCrew)

	day := time.Date(2026, 11, 2, 0, 0, 0, 0, time.UTC)
	require.NoError(t, s.SetWeather(ctx, b, day, 1))
	require.NoError(t, s.SetWeather(ctx, b, day, 2))
	members, err := s.CrewMembers(ctx, crew.ID, day)
	require.NoError(t, err)
	require.Len(t, members, 2)
	require.Equal(t, 0, members[0].Weather)
	require.Equal(t, 2, members[1].Weather)

	same, err := s.SameCrew(ctx, a, b)
	require.NoError(t, err)
	require.True(t, same)

	l, err := s.InsertLift(ctx, b, a, "That counts.")
	require.NoError(t, err)
	require.Equal(t, "Maya", l.FromFirstName)
	lifts, err := s.ListLifts(ctx, a, 10)
	require.NoError(t, err)
	require.Len(t, lifts, 1)
}
