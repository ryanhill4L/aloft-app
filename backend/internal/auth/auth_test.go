package auth

import (
	"crypto/ed25519"
	"crypto/rand"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/stretchr/testify/require"
)

const issuer = "https://ep-test.neonauth.example.neon.tech"

func TestJWTVerifier(t *testing.T) {
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	require.NoError(t, err)
	_, otherPriv, err := ed25519.GenerateKey(rand.Reader)
	require.NoError(t, err)

	v := JWTVerifier{
		Keyfunc: func(*jwt.Token) (any, error) { return pub, nil },
		Issuer:  issuer,
	}

	sign := func(key ed25519.PrivateKey, claims jwt.MapClaims) string {
		s, err := jwt.NewWithClaims(jwt.SigningMethodEdDSA, claims).SignedString(key)
		require.NoError(t, err)
		return s
	}
	future := time.Now().Add(10 * time.Minute).Unix()

	tests := []struct {
		name    string
		token   string
		wantSub string
	}{
		{"valid", sign(priv, jwt.MapClaims{"sub": "user-1", "iss": issuer, "exp": future}), "user-1"},
		{"wrong issuer", sign(priv, jwt.MapClaims{"sub": "user-1", "iss": "https://evil.example", "exp": future}), ""},
		{"expired", sign(priv, jwt.MapClaims{"sub": "user-1", "iss": issuer, "exp": time.Now().Add(-time.Minute).Unix()}), ""},
		{"no expiry", sign(priv, jwt.MapClaims{"sub": "user-1", "iss": issuer}), ""},
		{"no subject", sign(priv, jwt.MapClaims{"iss": issuer, "exp": future}), ""},
		{"other key", sign(otherPriv, jwt.MapClaims{"sub": "user-1", "iss": issuer, "exp": future}), ""},
		{"garbage", "not-a-jwt", ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			sub, err := v.Verify(tt.token)
			if tt.wantSub == "" {
				require.Error(t, err)
				return
			}
			require.NoError(t, err)
			require.Equal(t, tt.wantSub, sub)
		})
	}
}

func TestHS256IsRejected(t *testing.T) {
	// alg confusion: an HMAC token must never pass an EdDSA verifier.
	v := JWTVerifier{Keyfunc: func(*jwt.Token) (any, error) { return []byte("secret"), nil }, Issuer: issuer}
	s, err := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub": "user-1", "iss": issuer, "exp": time.Now().Add(time.Minute).Unix(),
	}).SignedString([]byte("secret"))
	require.NoError(t, err)
	_, err = v.Verify(s)
	require.Error(t, err)
}
