# Release image. Migrations are embedded in the binary and run at start.
FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o /out/aloft-api .

FROM alpine:3.22
RUN apk add --no-cache ca-certificates tzdata
COPY --from=build /out/aloft-api /usr/local/bin/aloft-api
ENV ADDRESS=:9090
EXPOSE 9090
USER nobody
ENTRYPOINT ["/usr/local/bin/aloft-api"]
