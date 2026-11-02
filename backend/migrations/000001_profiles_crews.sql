-- +goose Up
-- +goose StatementBegin

-- user_id is the Neon Auth (Better Auth) user id, the JWT `sub`.
CREATE TABLE profiles (
    user_id         TEXT PRIMARY KEY,
    first_name      TEXT NOT NULL DEFAULT '',
    birth_year      INTEGER NOT NULL DEFAULT 0,
    height_cm       INTEGER NOT NULL DEFAULT 0,
    weight_kg       INTEGER NOT NULL DEFAULT 0,
    bedtime_minutes INTEGER NOT NULL DEFAULT 1350 CHECK (bedtime_minutes BETWEEN 0 AND 1439),
    wake_minutes    INTEGER NOT NULL DEFAULT 390 CHECK (wake_minutes BETWEEN 0 AND 1439),
    onboarded       BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE crews (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code       TEXT NOT NULL UNIQUE,
    created_by TEXT NOT NULL REFERENCES profiles (user_id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One Crew per person.
CREATE TABLE crew_members (
    crew_id   UUID NOT NULL REFERENCES crews (id) ON DELETE CASCADE,
    user_id   TEXT NOT NULL UNIQUE REFERENCES profiles (user_id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (crew_id, user_id)
);

-- The one word a Crew sees. Never a number.
CREATE TABLE weather_days (
    user_id    TEXT NOT NULL REFERENCES profiles (user_id) ON DELETE CASCADE,
    day        DATE NOT NULL,
    weather    SMALLINT NOT NULL CHECK (weather BETWEEN 1 AND 3),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, day)
);

CREATE TABLE lifts (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_user_id TEXT NOT NULL REFERENCES profiles (user_id) ON DELETE CASCADE,
    to_user_id   TEXT NOT NULL REFERENCES profiles (user_id) ON DELETE CASCADE,
    message      TEXT NOT NULL CHECK (char_length(message) BETWEEN 1 AND 280),
    sent_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX lifts_to_user_sent_at ON lifts (to_user_id, sent_at DESC);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP TABLE lifts;
DROP TABLE weather_days;
DROP TABLE crew_members;
DROP TABLE crews;
DROP TABLE profiles;
-- +goose StatementEnd
