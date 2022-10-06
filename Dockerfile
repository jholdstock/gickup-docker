###############
# Builder Stage
###############

# Basic Go environment with git, SSL CA certs, and upx.
# The image below is golang:1.19.1-alpine3.16 (linux/amd64)
# It's pulled by the digest (immutable id) to avoid supply-chain attacks.
# Maintainer Note:
#    To update to a new digest, you must first manually pull the new image:
#    `docker pull golang:<new version>`
#    Docker will print the digest of the new image after the pull has finished.
FROM golang@sha256:d475cef843a02575ebdcb1416d98cd76bab90a5ae8bc2cd15f357fc08b6a329f AS builder
RUN apk add --no-cache git ca-certificates upx tzdata

# New unprivileged user for use in production image below to improve security.
ENV USER=gickup
ENV UID=10000
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home="/home/${USER}" \
    --shell "/sbin/nologin" \
    --no-create-home \
    --uid "${UID}" \
    "${USER}"

# Build gickup
WORKDIR /go/src/github.com/jholdstock/gickup
RUN git clone https://github.com/jholdstock/gickup . && \
    CGO_ENABLED=0 GOOS=linux \
    go build -trimpath -o app -tags safe,netgo,timetzdata \
      -ldflags="-s -w" \
      .

# Compress bin
RUN upx -9 /go/src/github.com/jholdstock/gickup/app

##################
# Production image
##################

# Minimal scratch-based environment.
FROM scratch

# Copy user and group from the builder
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /etc/group /etc/group
# Copy valid SSL certs from the builder for fetching github/gitlab/...
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
# Copy zoneinfo for getting the right cron timezone
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
# Copy the main executable from the builder
COPY --from=builder /go/src/github.com/jholdstock/gickup/app /gickup/app

# Use the unprivileged user.
USER gickup

VOLUME [ "/host-dir" ]

ENTRYPOINT [ "/gickup/app", "/host-dir/gickup/conf.yml" ]

