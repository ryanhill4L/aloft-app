// Package store is the Postgres boundary. The service talks to the Store
// interface; tests use an in-memory fake.
package store

import (
	"context"
	"errors"
	"time"
)

var (
	ErrNotFound      = errors.New("not found")
	ErrCrewFull      = errors.New("crew is full")
	ErrAlreadyInCrew = errors.New("already in a crew")
	ErrCodeCollision = errors.New("crew code already taken")
)

type Profile struct {
	UserID         string
	FirstName      string
	BirthYear      int
	HeightCM       int
	WeightKG       int
	BedtimeMinutes int
	WakeMinutes    int
	Onboarded      bool
}

type Crew struct {
	ID   string
	Code string
}

type Member struct {
	UserID    string
	FirstName string
	// Weather is 0 when the member has not shared for the requested day.
	Weather int
}

type Lift struct {
	ID            string
	FromUserID    string
	FromFirstName string
	Message       string
	SentAt        time.Time
}

type Store interface {
	GetOrCreateProfile(ctx context.Context, userID string) (Profile, error)
	UpdateProfile(ctx context.Context, p Profile) (Profile, error)

	// CrewForUser returns ErrNotFound when the user has no Crew.
	CrewForUser(ctx context.Context, userID string) (Crew, error)
	CreateCrew(ctx context.Context, userID, code string) (Crew, error)
	JoinCrew(ctx context.Context, userID, code string, maxMembers int) (Crew, error)
	CrewMembers(ctx context.Context, crewID string, day time.Time) ([]Member, error)

	SetWeather(ctx context.Context, userID string, day time.Time, weather int) error

	SameCrew(ctx context.Context, a, b string) (bool, error)
	InsertLift(ctx context.Context, from, to, message string) (Lift, error)
	ListLifts(ctx context.Context, to string, limit int) ([]Lift, error)
}
