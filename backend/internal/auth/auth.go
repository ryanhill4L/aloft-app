// Package auth verifies Neon Auth (Managed Better Auth) JWTs and carries the
// caller's user id through the request context.
package auth

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"connectrpc.com/connect"
	"github.com/golang-jwt/jwt/v5"
)

// Verifier checks a bearer token and returns the user id (the `sub` claim).
type Verifier interface {
	Verify(token string) (string, error)
}

// JWTVerifier validates EdDSA tokens against a key set. Neon signs with
// Ed25519 and issues from the auth URL's origin.
type JWTVerifier struct {
	Keyfunc jwt.Keyfunc
	Issuer  string
}

func (v JWTVerifier) Verify(token string) (string, error) {
	parsed, err := jwt.Parse(token, v.Keyfunc,
		jwt.WithIssuer(v.Issuer),
		jwt.WithValidMethods([]string{"EdDSA"}),
		jwt.WithExpirationRequired(),
	)
	if err != nil {
		return "", err
	}
	sub, err := parsed.Claims.GetSubject()
	if err != nil || sub == "" {
		return "", errors.New("token has no subject")
	}
	return sub, nil
}

type userKey struct{}

// UserID returns the authenticated caller. Every handler behind the
// interceptor can rely on it being set.
func UserID(ctx context.Context) string {
	id, _ := ctx.Value(userKey{}).(string)
	return id
}

func WithUserID(ctx context.Context, id string) context.Context {
	return context.WithValue(ctx, userKey{}, id)
}

// NewInterceptor requires `Authorization: Bearer <jwt>` on every procedure.
func NewInterceptor(v Verifier) connect.UnaryInterceptorFunc {
	return func(next connect.UnaryFunc) connect.UnaryFunc {
		return func(ctx context.Context, req connect.AnyRequest) (connect.AnyResponse, error) {
			header := req.Header().Get("Authorization")
			token, ok := strings.CutPrefix(header, "Bearer ")
			if !ok || token == "" {
				return nil, connect.NewError(connect.CodeUnauthenticated, errors.New("missing bearer token"))
			}
			sub, err := v.Verify(token)
			if err != nil {
				return nil, connect.NewError(connect.CodeUnauthenticated, fmt.Errorf("invalid token: %w", err))
			}
			return next(WithUserID(ctx, sub), req)
		}
	}
}
