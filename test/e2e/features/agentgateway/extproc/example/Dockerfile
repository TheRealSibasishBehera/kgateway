FROM --platform=$BUILDPLATFORM  golang:alpine AS builder

RUN apk --no-cache add make
WORKDIR /app
COPY go.mod .
COPY go.sum .   
RUN ls
RUN cat go.mod
RUN go mod download
COPY . .

ARG TARGETOS TARGETARCH
RUN GOOS=$TARGETOS GOARCH=$TARGETARCH make server

FROM alpine
COPY --from=builder ./app/_output/server /server

EXPOSE 18080
CMD ["./server"]
