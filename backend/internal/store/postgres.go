package store

import (
	"context"
	"database/sql"
	"errors"
	"slices"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/stdlib"
)

type Postgres struct {
	db *sql.DB
}

// Open connects with pool settings tuned for Neon: idle connections are
// recycled before Neon's autosuspend closes them.
func Open(ctx context.Context, databaseURL string) (*sql.DB, error) {
	cfg, err := pgx.ParseConfig(databaseURL)
	if err != nil {
		return nil, err
	}
	// Neon's pooler runs PgBouncer in transaction mode, where named prepared
	// statements collide across server connections.
	cfg.DefaultQueryExecMode = pgx.QueryExecModeExec
	db := stdlib.OpenDB(*cfg)
	db.SetConnMaxIdleTime(4 * time.Minute)
	db.SetConnMaxLifetime(30 * time.Minute)
	db.SetMaxIdleConns(4)
	db.SetMaxOpenConns(20)
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		db.Close()
		return nil, err
	}
	return db, nil
}

func NewPostgres(db *sql.DB) *Postgres { return &Postgres{db: db} }

const profileColumns = `user_id, first_name, birth_year, height_cm, weight_kg, bedtime_minutes, wake_minutes, onboarded`

func scanProfile(row interface{ Scan(...any) error }) (Profile, error) {
	var p Profile
	err := row.Scan(&p.UserID, &p.FirstName, &p.BirthYear, &p.HeightCM, &p.WeightKG, &p.BedtimeMinutes, &p.WakeMinutes, &p.Onboarded)
	return p, err
}

func (s *Postgres) GetOrCreateProfile(ctx context.Context, userID string) (Profile, error) {
	return scanProfile(s.db.QueryRowContext(ctx, `
		INSERT INTO profiles (user_id) VALUES ($1)
		ON CONFLICT (user_id) DO UPDATE SET user_id = EXCLUDED.user_id
		RETURNING `+profileColumns, userID))
}

func (s *Postgres) UpdateProfile(ctx context.Context, p Profile) (Profile, error) {
	return scanProfile(s.db.QueryRowContext(ctx, `
		INSERT INTO profiles (user_id, first_name, birth_year, height_cm, weight_kg, bedtime_minutes, wake_minutes, onboarded)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		ON CONFLICT (user_id) DO UPDATE SET
			first_name = EXCLUDED.first_name,
			birth_year = EXCLUDED.birth_year,
			height_cm = EXCLUDED.height_cm,
			weight_kg = EXCLUDED.weight_kg,
			bedtime_minutes = EXCLUDED.bedtime_minutes,
			wake_minutes = EXCLUDED.wake_minutes,
			onboarded = EXCLUDED.onboarded,
			updated_at = now()
		RETURNING `+profileColumns,
		p.UserID, p.FirstName, p.BirthYear, p.HeightCM, p.WeightKG, p.BedtimeMinutes, p.WakeMinutes, p.Onboarded))
}

func (s *Postgres) CrewForUser(ctx context.Context, userID string) (Crew, error) {
	var c Crew
	err := s.db.QueryRowContext(ctx, `
		SELECT c.id, c.code FROM crews c
		JOIN crew_members m ON m.crew_id = c.id
		WHERE m.user_id = $1`, userID).Scan(&c.ID, &c.Code)
	if errors.Is(err, sql.ErrNoRows) {
		return Crew{}, ErrNotFound
	}
	return c, err
}

func (s *Postgres) CreateCrew(ctx context.Context, userID, code string) (Crew, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Crew{}, err
	}
	defer tx.Rollback()

	var c Crew
	err = tx.QueryRowContext(ctx, `INSERT INTO crews (code, created_by) VALUES ($1, $2) RETURNING id, code`, code, userID).Scan(&c.ID, &c.Code)
	if err != nil {
		return Crew{}, mapUnique(err, ErrCodeCollision, "crews_code_key")
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO crew_members (crew_id, user_id) VALUES ($1, $2)`, c.ID, userID); err != nil {
		return Crew{}, mapUnique(err, ErrAlreadyInCrew, "crew_members_pkey", "crew_members_user_id_key")
	}
	return c, tx.Commit()
}

func (s *Postgres) JoinCrew(ctx context.Context, userID, code string, maxMembers int) (Crew, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Crew{}, err
	}
	defer tx.Rollback()

	var c Crew
	// The row lock serializes joins so the member cap holds under concurrency.
	err = tx.QueryRowContext(ctx, `SELECT id, code FROM crews WHERE code = $1 FOR UPDATE`, code).Scan(&c.ID, &c.Code)
	if errors.Is(err, sql.ErrNoRows) {
		return Crew{}, ErrNotFound
	}
	if err != nil {
		return Crew{}, err
	}
	var n int
	if err := tx.QueryRowContext(ctx, `SELECT count(*) FROM crew_members WHERE crew_id = $1`, c.ID).Scan(&n); err != nil {
		return Crew{}, err
	}
	if n >= maxMembers {
		return Crew{}, ErrCrewFull
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO crew_members (crew_id, user_id) VALUES ($1, $2)`, c.ID, userID); err != nil {
		return Crew{}, mapUnique(err, ErrAlreadyInCrew, "crew_members_pkey", "crew_members_user_id_key")
	}
	return c, tx.Commit()
}

func (s *Postgres) CrewMembers(ctx context.Context, crewID string, day time.Time) ([]Member, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT p.user_id, p.first_name, COALESCE(w.weather, 0)
		FROM crew_members m
		JOIN profiles p ON p.user_id = m.user_id
		LEFT JOIN weather_days w ON w.user_id = m.user_id AND w.day = $2
		WHERE m.crew_id = $1
		ORDER BY m.joined_at`, crewID, day.Format(time.DateOnly))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Member
	for rows.Next() {
		var m Member
		if err := rows.Scan(&m.UserID, &m.FirstName, &m.Weather); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

func (s *Postgres) SetWeather(ctx context.Context, userID string, day time.Time, weather int) error {
	_, err := s.db.ExecContext(ctx, `
		INSERT INTO weather_days (user_id, day, weather) VALUES ($1, $2, $3)
		ON CONFLICT (user_id, day) DO UPDATE SET weather = EXCLUDED.weather, updated_at = now()`,
		userID, day.Format(time.DateOnly), weather)
	return err
}

func (s *Postgres) SameCrew(ctx context.Context, a, b string) (bool, error) {
	var same bool
	err := s.db.QueryRowContext(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM crew_members x JOIN crew_members y ON x.crew_id = y.crew_id
			WHERE x.user_id = $1 AND y.user_id = $2
		)`, a, b).Scan(&same)
	return same, err
}

func (s *Postgres) InsertLift(ctx context.Context, from, to, message string) (Lift, error) {
	l := Lift{FromUserID: from, Message: message}
	err := s.db.QueryRowContext(ctx, `
		WITH ins AS (
			INSERT INTO lifts (from_user_id, to_user_id, message) VALUES ($1, $2, $3)
			RETURNING id, sent_at
		)
		SELECT ins.id, ins.sent_at, p.first_name FROM ins JOIN profiles p ON p.user_id = $1`,
		from, to, message).Scan(&l.ID, &l.SentAt, &l.FromFirstName)
	return l, err
}

func (s *Postgres) ListLifts(ctx context.Context, to string, limit int) ([]Lift, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT l.id, l.from_user_id, p.first_name, l.message, l.sent_at
		FROM lifts l JOIN profiles p ON p.user_id = l.from_user_id
		WHERE l.to_user_id = $1
		ORDER BY l.sent_at DESC
		LIMIT $2`, to, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Lift
	for rows.Next() {
		var l Lift
		if err := rows.Scan(&l.ID, &l.FromUserID, &l.FromFirstName, &l.Message, &l.SentAt); err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, rows.Err()
}

func mapUnique(err, mapped error, constraints ...string) error {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" && slices.Contains(constraints, pgErr.ConstraintName) {
		return mapped
	}
	return err
}
