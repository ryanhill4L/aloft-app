package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"connectrpc.com/connect"
	"github.com/MicahParks/keyfunc/v3"
	"github.com/joho/godotenv"
	"github.com/pressly/goose/v3"
	"golang.org/x/net/http2"
	"golang.org/x/net/http2/h2c"

	"aloft/gen/aloft/v1/aloftv1connect"
	"aloft/internal/auth"
	"aloft/internal/config"
	"aloft/internal/service"
	"aloft/internal/store"
	"aloft/migrations"
)

func main() {
	if err := run(); err != nil {
		slog.Error("aloft api stopped", "err", err)
		os.Exit(1)
	}
}

func run() error {
	_ = godotenv.Load()
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	db, err := store.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer db.Close()

	goose.SetBaseFS(migrations.FS)
	if err := goose.SetDialect("postgres"); err != nil {
		return err
	}
	if err := goose.UpContext(ctx, db, "."); err != nil {
		return err
	}

	jwks, err := keyfunc.NewDefaultCtx(ctx, []string{cfg.JWKSURL()})
	if err != nil {
		return err
	}
	verifier := auth.JWTVerifier{Keyfunc: jwks.Keyfunc, Issuer: cfg.Issuer()}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) })
	path, handler := aloftv1connect.NewAloftServiceHandler(
		service.New(store.NewPostgres(db)),
		connect.WithInterceptors(auth.NewInterceptor(verifier)),
	)
	mux.Handle(path, handler)

	srv := &http.Server{
		Addr:              cfg.Address,
		Handler:           h2c.NewHandler(mux, &http2.Server{}),
		ReadHeaderTimeout: 10 * time.Second,
	}
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		srv.Shutdown(shutdown)
	}()
	slog.Info("aloft api listening", "addr", cfg.Address)
	if err := srv.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}
