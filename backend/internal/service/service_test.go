package service

import (
	"context"
	"fmt"
	"testing"
	"time"

	"connectrpc.com/connect"
	"github.com/stretchr/testify/require"

	aloftv1 "aloft/gen/aloft/v1"
	"aloft/internal/auth"
	"aloft/internal/store"
)

// fakeStore keeps rows in maps. It mirrors the Postgres rules the service
// depends on (one crew per user, member cap, unique codes).
type fakeStore struct {
	profiles map[string]store.Profile
	crews    map[string]store.Crew // by id
	members  map[string]string     // user -> crew id
	order    []string              // join order of users
	weather  map[string]int        // user|day -> weather
	lifts    []store.Lift
	liftTo   []string
}

func newFake() *fakeStore {
	return &fakeStore{
		profiles: map[string]store.Profile{},
		crews:    map[string]store.Crew{},
		members:  map[string]string{},
		weather:  map[string]int{},
	}
}

func (f *fakeStore) GetOrCreateProfile(_ context.Context, id string) (store.Profile, error) {
	p, ok := f.profiles[id]
	if !ok {
		p = store.Profile{UserID: id, BedtimeMinutes: 1350, WakeMinutes: 390}
		f.profiles[id] = p
	}
	return p, nil
}

func (f *fakeStore) UpdateProfile(_ context.Context, p store.Profile) (store.Profile, error) {
	f.profiles[p.UserID] = p
	return p, nil
}

func (f *fakeStore) CrewForUser(_ context.Context, id string) (store.Crew, error) {
	cid, ok := f.members[id]
	if !ok {
		return store.Crew{}, store.ErrNotFound
	}
	return f.crews[cid], nil
}

func (f *fakeStore) CreateCrew(_ context.Context, id, code string) (store.Crew, error) {
	for _, c := range f.crews {
		if c.Code == code {
			return store.Crew{}, store.ErrCodeCollision
		}
	}
	if _, ok := f.members[id]; ok {
		return store.Crew{}, store.ErrAlreadyInCrew
	}
	c := store.Crew{ID: fmt.Sprintf("crew-%d", len(f.crews)+1), Code: code}
	f.crews[c.ID] = c
	f.members[id] = c.ID
	f.order = append(f.order, id)
	return c, nil
}

func (f *fakeStore) JoinCrew(_ context.Context, id, code string, max int) (store.Crew, error) {
	var crew store.Crew
	for _, c := range f.crews {
		if c.Code == code {
			crew = c
		}
	}
	if crew.ID == "" {
		return store.Crew{}, store.ErrNotFound
	}
	n := 0
	for _, cid := range f.members {
		if cid == crew.ID {
			n++
		}
	}
	if n >= max {
		return store.Crew{}, store.ErrCrewFull
	}
	if _, ok := f.members[id]; ok {
		return store.Crew{}, store.ErrAlreadyInCrew
	}
	f.members[id] = crew.ID
	f.order = append(f.order, id)
	return crew, nil
}

func (f *fakeStore) CrewMembers(_ context.Context, crewID string, day time.Time) ([]store.Member, error) {
	var out []store.Member
	for _, id := range f.order {
		if f.members[id] == crewID {
			out = append(out, store.Member{
				UserID:    id,
				FirstName: f.profiles[id].FirstName,
				Weather:   f.weather[id+"|"+day.Format(time.DateOnly)],
			})
		}
	}
	return out, nil
}

func (f *fakeStore) SetWeather(_ context.Context, id string, day time.Time, w int) error {
	f.weather[id+"|"+day.Format(time.DateOnly)] = w
	return nil
}

func (f *fakeStore) SameCrew(_ context.Context, a, b string) (bool, error) {
	ca, okA := f.members[a]
	cb, okB := f.members[b]
	return okA && okB && ca == cb, nil
}

func (f *fakeStore) InsertLift(_ context.Context, from, to, msg string) (store.Lift, error) {
	l := store.Lift{ID: fmt.Sprint(len(f.lifts) + 1), FromUserID: from, FromFirstName: f.profiles[from].FirstName, Message: msg, SentAt: time.Unix(1_800_000_000, 0)}
	f.lifts = append(f.lifts, l)
	f.liftTo = append(f.liftTo, to)
	return l, nil
}

func (f *fakeStore) ListLifts(_ context.Context, to string, limit int) ([]store.Lift, error) {
	var out []store.Lift
	for i := len(f.lifts) - 1; i >= 0 && len(out) < limit; i-- {
		if f.liftTo[i] == to {
			out = append(out, f.lifts[i])
		}
	}
	return out, nil
}

func as(id string) context.Context { return auth.WithUserID(context.Background(), id) }

func code(t *testing.T, err error) connect.Code {
	t.Helper()
	require.Error(t, err)
	return connect.CodeOf(err)
}

func TestGetMeCreatesProfile(t *testing.T) {
	svc := New(newFake())
	res, err := svc.GetMe(as("u1"), connect.NewRequest(&aloftv1.GetMeRequest{}))
	require.NoError(t, err)
	require.Equal(t, "u1", res.Msg.Profile.UserId)
	require.False(t, res.Msg.Profile.Onboarded)
}

func TestUpdateProfileValidation(t *testing.T) {
	now := time.Date(2026, 11, 2, 0, 0, 0, 0, time.UTC)
	ok := store.Profile{FirstName: "Ryan", BirthYear: 1991, HeightCM: 180, WeightKG: 78, BedtimeMinutes: 1350, WakeMinutes: 390, Onboarded: true}
	tests := []struct {
		name   string
		mutate func(*store.Profile)
		valid  bool
	}{
		{"complete", func(*store.Profile) {}, true},
		{"empty basics are allowed", func(p *store.Profile) { p.BirthYear, p.HeightCM, p.WeightKG = 0, 0, 0 }, true},
		{"onboarded needs a name", func(p *store.Profile) { p.FirstName = "" }, false},
		{"too young", func(p *store.Profile) { p.BirthYear = 2020 }, false},
		{"height out of range", func(p *store.Profile) { p.HeightCM = 400 }, false},
		{"weight out of range", func(p *store.Profile) { p.WeightKG = 10 }, false},
		{"bedtime past midnight", func(p *store.Profile) { p.BedtimeMinutes = 1440 }, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p := ok
			tt.mutate(&p)
			err := validateProfile(p, now)
			if tt.valid {
				require.NoError(t, err)
			} else {
				require.Equal(t, connect.CodeInvalidArgument, code(t, err))
			}
		})
	}
}

func TestCrewLifecycle(t *testing.T) {
	f := newFake()
	svc := New(f)
	ctx := context.Background()
	_, _ = f.UpdateProfile(ctx, store.Profile{UserID: "ryan", FirstName: "Ryan"})
	_, _ = f.UpdateProfile(ctx, store.Profile{UserID: "maya", FirstName: "Maya"})

	created, err := svc.CreateCrew(as("ryan"), connect.NewRequest(&aloftv1.CreateCrewRequest{}))
	require.NoError(t, err)
	crewCode := created.Msg.Crew.Code
	require.Len(t, crewCode, 6)

	again, err := svc.CreateCrew(as("ryan"), connect.NewRequest(&aloftv1.CreateCrewRequest{}))
	require.NoError(t, err)
	require.Equal(t, crewCode, again.Msg.Crew.Code, "creating twice returns the existing crew")

	typed := " " + crewCode[:3] + "-" + crewCode[3:] + " "
	joined, err := svc.JoinCrew(as("maya"), connect.NewRequest(&aloftv1.JoinCrewRequest{Code: typed}))
	require.NoError(t, err)
	require.Len(t, joined.Msg.Crew.Members, 2)

	_, err = svc.JoinCrew(as("maya"), connect.NewRequest(&aloftv1.JoinCrewRequest{Code: crewCode}))
	require.Equal(t, connect.CodeAlreadyExists, code(t, err))

	_, err = svc.JoinCrew(as("theo"), connect.NewRequest(&aloftv1.JoinCrewRequest{Code: "ZZZZZZ"}))
	require.Equal(t, connect.CodeNotFound, code(t, err))

	_, err = svc.SetWeather(as("maya"), connect.NewRequest(&aloftv1.SetWeatherRequest{Day: "2026-11-02", Weather: aloftv1.Weather_WEATHER_CLEAR}))
	require.NoError(t, err)

	got, err := svc.GetCrew(as("ryan"), connect.NewRequest(&aloftv1.GetCrewRequest{Day: "2026-11-02"}))
	require.NoError(t, err)
	require.Equal(t, aloftv1.Weather_WEATHER_UNSPECIFIED, got.Msg.Crew.Members[0].Weather)
	require.Equal(t, "Maya", got.Msg.Crew.Members[1].FirstName)
	require.Equal(t, aloftv1.Weather_WEATHER_CLEAR, got.Msg.Crew.Members[1].Weather)

	other, err := svc.GetCrew(as("ryan"), connect.NewRequest(&aloftv1.GetCrewRequest{Day: "2026-11-03"}))
	require.NoError(t, err)
	require.Equal(t, aloftv1.Weather_WEATHER_UNSPECIFIED, other.Msg.Crew.Members[1].Weather, "weather is per day")
}

func TestCrewCap(t *testing.T) {
	svc := New(newFake())
	created, err := svc.CreateCrew(as("u0"), connect.NewRequest(&aloftv1.CreateCrewRequest{}))
	require.NoError(t, err)
	for i := 1; i < MaxCrewMembers; i++ {
		_, err := svc.JoinCrew(as(fmt.Sprint("u", i)), connect.NewRequest(&aloftv1.JoinCrewRequest{Code: created.Msg.Crew.Code}))
		require.NoError(t, err)
	}
	_, err = svc.JoinCrew(as("late"), connect.NewRequest(&aloftv1.JoinCrewRequest{Code: created.Msg.Crew.Code}))
	require.Equal(t, connect.CodeFailedPrecondition, code(t, err))
}

func TestGetCrewWithoutCrew(t *testing.T) {
	svc := New(newFake())
	res, err := svc.GetCrew(as("solo"), connect.NewRequest(&aloftv1.GetCrewRequest{Day: "2026-11-02"}))
	require.NoError(t, err)
	require.Nil(t, res.Msg.Crew)

	_, err = svc.GetCrew(as("solo"), connect.NewRequest(&aloftv1.GetCrewRequest{Day: "Nov 2"}))
	require.Equal(t, connect.CodeInvalidArgument, code(t, err))
}

func TestSetWeatherRejectsUnknownValues(t *testing.T) {
	svc := New(newFake())
	for _, w := range []aloftv1.Weather{aloftv1.Weather_WEATHER_UNSPECIFIED, aloftv1.Weather(9)} {
		_, err := svc.SetWeather(as("u"), connect.NewRequest(&aloftv1.SetWeatherRequest{Day: "2026-11-02", Weather: w}))
		require.Equal(t, connect.CodeInvalidArgument, code(t, err))
	}
}

func TestLifts(t *testing.T) {
	f := newFake()
	svc := New(f)
	ctx := context.Background()
	_, _ = f.UpdateProfile(ctx, store.Profile{UserID: "maya", FirstName: "Maya"})
	created, _ := svc.CreateCrew(as("maya"), connect.NewRequest(&aloftv1.CreateCrewRequest{}))
	_, err := svc.JoinCrew(as("ryan"), connect.NewRequest(&aloftv1.JoinCrewRequest{Code: created.Msg.Crew.Code}))
	require.NoError(t, err)

	sent, err := svc.SendLift(as("maya"), connect.NewRequest(&aloftv1.SendLiftRequest{ToUserId: "ryan", Message: "  You showed up on an overcast day. That counts.  "}))
	require.NoError(t, err)
	require.Equal(t, "You showed up on an overcast day. That counts.", sent.Msg.Lift.Message)
	require.Equal(t, "Maya", sent.Msg.Lift.FromFirstName)

	list, err := svc.ListLifts(as("ryan"), connect.NewRequest(&aloftv1.ListLiftsRequest{}))
	require.NoError(t, err)
	require.Len(t, list.Msg.Lifts, 1)

	tests := []struct {
		name string
		from string
		req  *aloftv1.SendLiftRequest
		want connect.Code
	}{
		{"to self", "ryan", &aloftv1.SendLiftRequest{ToUserId: "ryan", Message: "hi"}, connect.CodeInvalidArgument},
		{"empty", "ryan", &aloftv1.SendLiftRequest{ToUserId: "maya", Message: "   "}, connect.CodeInvalidArgument},
		{"too long", "ryan", &aloftv1.SendLiftRequest{ToUserId: "maya", Message: string(make([]rune, 281))}, connect.CodeInvalidArgument},
		{"outside crew", "stranger", &aloftv1.SendLiftRequest{ToUserId: "ryan", Message: "hi"}, connect.CodePermissionDenied},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := svc.SendLift(as(tt.from), connect.NewRequest(tt.req))
			require.Equal(t, tt.want, code(t, err))
		})
	}
}

func TestNormalizeCode(t *testing.T) {
	require.Equal(t, "ABC234", NormalizeCode(" abc-234 "))
	for range 50 {
		c, err := newCode()
		require.NoError(t, err)
		require.Len(t, c, codeLength)
		require.NotContains(t, c, "0")
		require.NotContains(t, c, "O")
	}
}
