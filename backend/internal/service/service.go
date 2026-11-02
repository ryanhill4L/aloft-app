// Package service implements aloft.v1.AloftService on top of the Store.
package service

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"log/slog"
	"math/big"
	"strings"
	"time"
	"unicode/utf8"

	"connectrpc.com/connect"

	aloftv1 "aloft/gen/aloft/v1"
	"aloft/gen/aloft/v1/aloftv1connect"
	"aloft/internal/auth"
	"aloft/internal/store"
)

const (
	MaxCrewMembers = 12
	maxLiftRunes   = 280
	defaultLifts   = 20
	maxLifts       = 100
	// No 0/O or 1/I/L: codes are read aloud and typed by hand.
	codeAlphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
	codeLength   = 6
)

type Service struct {
	store store.Store
}

var _ aloftv1connect.AloftServiceHandler = (*Service)(nil)

func New(s store.Store) *Service { return &Service{store: s} }

func (s *Service) GetMe(ctx context.Context, _ *connect.Request[aloftv1.GetMeRequest]) (*connect.Response[aloftv1.GetMeResponse], error) {
	p, err := s.store.GetOrCreateProfile(ctx, auth.UserID(ctx))
	if err != nil {
		return nil, internal(err)
	}
	return connect.NewResponse(&aloftv1.GetMeResponse{Profile: toProto(p)}), nil
}

func (s *Service) UpdateProfile(ctx context.Context, req *connect.Request[aloftv1.UpdateProfileRequest]) (*connect.Response[aloftv1.UpdateProfileResponse], error) {
	in := req.Msg.GetProfile()
	if in == nil {
		return nil, invalid("profile is required")
	}
	p := store.Profile{
		UserID:         auth.UserID(ctx),
		FirstName:      strings.TrimSpace(in.GetFirstName()),
		BirthYear:      int(in.GetBirthYear()),
		HeightCM:       int(in.GetHeightCm()),
		WeightKG:       int(in.GetWeightKg()),
		BedtimeMinutes: int(in.GetBedtimeMinutes()),
		WakeMinutes:    int(in.GetWakeMinutes()),
		Onboarded:      in.GetOnboarded(),
	}
	if err := validateProfile(p, time.Now()); err != nil {
		return nil, err
	}
	out, err := s.store.UpdateProfile(ctx, p)
	if err != nil {
		return nil, internal(err)
	}
	return connect.NewResponse(&aloftv1.UpdateProfileResponse{Profile: toProto(out)}), nil
}

func validateProfile(p store.Profile, now time.Time) error {
	switch {
	case utf8.RuneCountInString(p.FirstName) > 40:
		return invalid("first name is too long")
	case p.Onboarded && p.FirstName == "":
		return invalid("first name is required to finish onboarding")
	case p.BirthYear != 0 && (p.BirthYear < 1900 || p.BirthYear > now.Year()-13):
		return invalid("birth year is out of range")
	case p.HeightCM != 0 && (p.HeightCM < 90 || p.HeightCM > 250):
		return invalid("height is out of range")
	case p.WeightKG != 0 && (p.WeightKG < 25 || p.WeightKG > 300):
		return invalid("weight is out of range")
	case p.BedtimeMinutes < 0 || p.BedtimeMinutes > 1439 || p.WakeMinutes < 0 || p.WakeMinutes > 1439:
		return invalid("times must be minutes after midnight")
	}
	return nil
}

func (s *Service) CreateCrew(ctx context.Context, _ *connect.Request[aloftv1.CreateCrewRequest]) (*connect.Response[aloftv1.CreateCrewResponse], error) {
	uid := auth.UserID(ctx)
	if _, err := s.store.GetOrCreateProfile(ctx, uid); err != nil {
		return nil, internal(err)
	}
	crew, err := s.store.CrewForUser(ctx, uid)
	if errors.Is(err, store.ErrNotFound) {
		crew, err = s.createWithFreshCode(ctx, uid)
	}
	if err != nil {
		return nil, internal(err)
	}
	pc, err := s.crewProto(ctx, crew, time.Time{})
	if err != nil {
		return nil, internal(err)
	}
	return connect.NewResponse(&aloftv1.CreateCrewResponse{Crew: pc}), nil
}

func (s *Service) createWithFreshCode(ctx context.Context, uid string) (store.Crew, error) {
	for range 5 {
		code, err := newCode()
		if err != nil {
			return store.Crew{}, err
		}
		crew, err := s.store.CreateCrew(ctx, uid, code)
		if !errors.Is(err, store.ErrCodeCollision) {
			return crew, err
		}
	}
	return store.Crew{}, errors.New("could not find a free crew code")
}

func (s *Service) JoinCrew(ctx context.Context, req *connect.Request[aloftv1.JoinCrewRequest]) (*connect.Response[aloftv1.JoinCrewResponse], error) {
	uid := auth.UserID(ctx)
	code := NormalizeCode(req.Msg.GetCode())
	if len(code) != codeLength {
		return nil, invalid("a crew code is six characters")
	}
	if _, err := s.store.GetOrCreateProfile(ctx, uid); err != nil {
		return nil, internal(err)
	}
	crew, err := s.store.JoinCrew(ctx, uid, code, MaxCrewMembers)
	switch {
	case errors.Is(err, store.ErrNotFound):
		return nil, connect.NewError(connect.CodeNotFound, errors.New("no crew has that code"))
	case errors.Is(err, store.ErrCrewFull):
		return nil, connect.NewError(connect.CodeFailedPrecondition, fmt.Errorf("a crew holds %d people", MaxCrewMembers))
	case errors.Is(err, store.ErrAlreadyInCrew):
		return nil, connect.NewError(connect.CodeAlreadyExists, errors.New("you are already in a crew"))
	case err != nil:
		return nil, internal(err)
	}
	pc, err := s.crewProto(ctx, crew, time.Time{})
	if err != nil {
		return nil, internal(err)
	}
	return connect.NewResponse(&aloftv1.JoinCrewResponse{Crew: pc}), nil
}

func (s *Service) GetCrew(ctx context.Context, req *connect.Request[aloftv1.GetCrewRequest]) (*connect.Response[aloftv1.GetCrewResponse], error) {
	day, err := parseDay(req.Msg.GetDay())
	if err != nil {
		return nil, err
	}
	crew, err := s.store.CrewForUser(ctx, auth.UserID(ctx))
	if errors.Is(err, store.ErrNotFound) {
		return connect.NewResponse(&aloftv1.GetCrewResponse{}), nil
	}
	if err != nil {
		return nil, internal(err)
	}
	pc, err := s.crewProto(ctx, crew, day)
	if err != nil {
		return nil, internal(err)
	}
	return connect.NewResponse(&aloftv1.GetCrewResponse{Crew: pc}), nil
}

func (s *Service) SetWeather(ctx context.Context, req *connect.Request[aloftv1.SetWeatherRequest]) (*connect.Response[aloftv1.SetWeatherResponse], error) {
	day, err := parseDay(req.Msg.GetDay())
	if err != nil {
		return nil, err
	}
	w := req.Msg.GetWeather()
	if w == aloftv1.Weather_WEATHER_UNSPECIFIED || aloftv1.Weather_name[int32(w)] == "" {
		return nil, invalid("weather is required")
	}
	uid := auth.UserID(ctx)
	if _, err := s.store.GetOrCreateProfile(ctx, uid); err != nil {
		return nil, internal(err)
	}
	if err := s.store.SetWeather(ctx, uid, day, int(w)); err != nil {
		return nil, internal(err)
	}
	return connect.NewResponse(&aloftv1.SetWeatherResponse{}), nil
}

func (s *Service) SendLift(ctx context.Context, req *connect.Request[aloftv1.SendLiftRequest]) (*connect.Response[aloftv1.SendLiftResponse], error) {
	from := auth.UserID(ctx)
	to := req.Msg.GetToUserId()
	msg := strings.TrimSpace(req.Msg.GetMessage())
	switch {
	case to == "" || to == from:
		return nil, invalid("send a Lift to someone in your crew")
	case msg == "":
		return nil, invalid("a Lift needs a few words")
	case utf8.RuneCountInString(msg) > maxLiftRunes:
		return nil, invalid("a Lift is at most 280 characters")
	}
	same, err := s.store.SameCrew(ctx, from, to)
	if err != nil {
		return nil, internal(err)
	}
	if !same {
		return nil, connect.NewError(connect.CodePermissionDenied, errors.New("you can only lift your own crew"))
	}
	lift, err := s.store.InsertLift(ctx, from, to, msg)
	if err != nil {
		return nil, internal(err)
	}
	return connect.NewResponse(&aloftv1.SendLiftResponse{Lift: liftProto(lift)}), nil
}

func (s *Service) ListLifts(ctx context.Context, req *connect.Request[aloftv1.ListLiftsRequest]) (*connect.Response[aloftv1.ListLiftsResponse], error) {
	limit := int(req.Msg.GetLimit())
	if limit <= 0 {
		limit = defaultLifts
	}
	limit = min(limit, maxLifts)
	lifts, err := s.store.ListLifts(ctx, auth.UserID(ctx), limit)
	if err != nil {
		return nil, internal(err)
	}
	out := make([]*aloftv1.Lift, 0, len(lifts))
	for _, l := range lifts {
		out = append(out, liftProto(l))
	}
	return connect.NewResponse(&aloftv1.ListLiftsResponse{Lifts: out}), nil
}

func (s *Service) crewProto(ctx context.Context, crew store.Crew, day time.Time) (*aloftv1.Crew, error) {
	if day.IsZero() {
		day = time.Now().UTC()
	}
	members, err := s.store.CrewMembers(ctx, crew.ID, day)
	if err != nil {
		return nil, err
	}
	pc := &aloftv1.Crew{Id: crew.ID, Code: crew.Code}
	for _, m := range members {
		pc.Members = append(pc.Members, &aloftv1.CrewMember{
			UserId:    m.UserID,
			FirstName: m.FirstName,
			Weather:   aloftv1.Weather(m.Weather),
		})
	}
	return pc, nil
}

// NormalizeCode accepts what people type: lower case, spaces, and dashes.
func NormalizeCode(raw string) string {
	var b strings.Builder
	for _, r := range strings.ToUpper(raw) {
		if r != ' ' && r != '-' {
			b.WriteRune(r)
		}
	}
	return b.String()
}

func newCode() (string, error) {
	b := make([]byte, codeLength)
	for i := range b {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(codeAlphabet))))
		if err != nil {
			return "", err
		}
		b[i] = codeAlphabet[n.Int64()]
	}
	return string(b), nil
}

func parseDay(raw string) (time.Time, error) {
	day, err := time.Parse(time.DateOnly, raw)
	if err != nil {
		return time.Time{}, invalid("day must be YYYY-MM-DD")
	}
	return day, nil
}

func toProto(p store.Profile) *aloftv1.Profile {
	return &aloftv1.Profile{
		UserId:         p.UserID,
		FirstName:      p.FirstName,
		BirthYear:      int32(p.BirthYear),
		HeightCm:       int32(p.HeightCM),
		WeightKg:       int32(p.WeightKG),
		BedtimeMinutes: int32(p.BedtimeMinutes),
		WakeMinutes:    int32(p.WakeMinutes),
		Onboarded:      p.Onboarded,
	}
}

func liftProto(l store.Lift) *aloftv1.Lift {
	return &aloftv1.Lift{
		Id:            l.ID,
		FromUserId:    l.FromUserID,
		FromFirstName: l.FromFirstName,
		Message:       l.Message,
		SentAtUnix:    l.SentAt.Unix(),
	}
}

func invalid(msg string) error { return connect.NewError(connect.CodeInvalidArgument, errors.New(msg)) }

// internal logs the cause and hides store details from the client.
func internal(err error) error {
	slog.Error("internal error", "err", err)
	return connect.NewError(connect.CodeInternal, errors.New("something went wrong"))
}
