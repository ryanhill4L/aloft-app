package config

import (
	"fmt"
	"net/url"
	"os"
)

// Config is read from the environment. See backend/.env.example.
type Config struct {
	Address     string
	DatabaseURL string
	// NeonAuthURL is the Managed Better Auth base URL, for example
	// https://ep-xxx.neonauth.c-16.us-east-1.aws.neon.tech/neondb/auth.
	NeonAuthURL string
}

func Load() (Config, error) {
	cfg := Config{
		Address:     getenv("ADDRESS", ":9090"),
		DatabaseURL: os.Getenv("DATABASE_URL"),
		NeonAuthURL: os.Getenv("NEON_AUTH_URL"),
	}
	if cfg.DatabaseURL == "" {
		return Config{}, fmt.Errorf("DATABASE_URL is required")
	}
	if _, err := url.ParseRequestURI(cfg.NeonAuthURL); err != nil {
		return Config{}, fmt.Errorf("NEON_AUTH_URL is required: %w", err)
	}
	return cfg, nil
}

// JWKSURL and Issuer follow Neon's documented layout: the JWKS sits under the
// auth URL and tokens are issued by its origin.
func (c Config) JWKSURL() string { return c.NeonAuthURL + "/.well-known/jwks.json" }

func (c Config) Issuer() string {
	u, _ := url.Parse(c.NeonAuthURL)
	return u.Scheme + "://" + u.Host
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
