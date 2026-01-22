# Testing Guide

This document describes how to test mise-postgres-binary locally and in Docker.

## Prerequisites

- [mise](https://mise.jdx.dev/) installed
- Docker (for container tests)

## Local Testing

### Quick Test

```bash
cd mise-postgres-binary

# Install development tools
mise install

# Link the plugin locally
mise plugin link --force postgres-binary "$PWD"

# Verify available versions
mise ls-remote postgres-binary:postgres | head -10

# Install PostgreSQL
mise install postgres-binary:postgres@15.15.0

# Verify installation
mise exec postgres-binary:postgres@15.15.0 -- postgres --version
mise exec postgres-binary:postgres@15.15.0 -- psql --version
```

### Full Local Test

This test verifies the complete workflow including database operations:

```bash
cd mise-postgres-binary

# Link plugin
mise plugin link --force postgres-binary "$PWD"

# Install PostgreSQL
mise install postgres-binary:postgres@16.11.0

# Activate the environment
eval "$(mise activate bash)"  # or zsh/fish
mise use postgres-binary:postgres@16.11.0

# Verify environment variables
echo "PGDATA: $PGDATA"
echo "PGHOME: $PGHOME"

# Check database initialization
ls -la "$PGDATA"
cat "$PGDATA/PG_VERSION"

# Start PostgreSQL
pg_ctl start -D "$PGDATA" -l /tmp/postgres.log -w

# Run queries
psql -c "SELECT version();" postgres
psql -c "CREATE TABLE test (id SERIAL PRIMARY KEY, data TEXT);" postgres
psql -c "INSERT INTO test (data) VALUES ('hello');" postgres
psql -c "SELECT * FROM test;" postgres

# Stop PostgreSQL
pg_ctl stop -D "$PGDATA" -m fast
```

### Testing Multiple Versions

```bash
# Install multiple versions
mise install postgres-binary:postgres@15.15.0
mise install postgres-binary:postgres@16.11.0
mise install postgres-binary:postgres@17.7.0

# Switch between versions
mise use postgres-binary:postgres@15.15.0
postgres --version  # PostgreSQL 15.x

mise use postgres-binary:postgres@16.11.0
postgres --version  # PostgreSQL 16.x
```

### Testing with mise.toml

Create a `mise.toml` in a test project:

```toml
[tools]
"postgres-binary:postgres" = "16.11.0"
```

Then:

```bash
cd test-project
mise install
eval "$(mise activate bash)"
postgres --version
```

## Docker Testing

Docker tests verify the plugin works on different Linux distributions.

### Run All Docker Tests

```bash
cd mise-postgres-binary
./test/run-docker-tests.sh
```

### Run Specific Distribution

```bash
# Debian (glibc)
./test/run-docker-tests.sh debian

# Alpine (musl)
./test/run-docker-tests.sh alpine
```

### Run Specific Container

```bash
# Using docker compose directly
docker compose -f test/docker-compose.yml build debian-pg15
docker compose -f test/docker-compose.yml run --rm debian-pg15

# Or build and run manually
docker build -f test/Dockerfile.debian --build-arg POSTGRES_VERSION=16.11.0 -t pg-test .
docker run --rm pg-test
```

### Test ARM64 (Requires ARM Host or QEMU)

```bash
# Enable ARM64 emulation (if on x86)
docker run --privileged --rm tonistiigi/binfmt --install arm64

# Run ARM64 tests
./test/run-docker-tests.sh arm64
```

## CI Testing

The GitHub Actions workflow tests:

| Platform | OS Versions | PostgreSQL Versions |
|----------|-------------|---------------------|
| Ubuntu | 22.04, latest | 15.x, 16.x, 17.x |
| macOS | 13, latest | 15.x, 16.x, 17.x |
| Docker (Debian) | bookworm | 15.x |
| Docker (Alpine) | 3.20 | 15.x |
| Windows | latest | 15.x (experimental) |

### Run CI Locally

```bash
# Lint only
mise run lint

# Full test (link plugin + list versions)
mise run test

# Full CI pipeline
mise run ci
```

## Troubleshooting

### Plugin Not Found

```bash
# Remove and re-link
mise plugin uninstall postgres-binary
mise plugin link --force postgres-binary "$PWD"
```

### Version Not Installing

```bash
# Check available versions
mise ls-remote postgres-binary:postgres

# Enable debug output
MISE_DEBUG=1 mise install postgres-binary:postgres@15.15.0
```

### Docker Build Fails

```bash
# Clean up and rebuild
docker compose -f test/docker-compose.yml down --rmi all
docker compose -f test/docker-compose.yml build --no-cache
```

### PostgreSQL Won't Start

```bash
# Check logs
cat /tmp/postgres.log

# Check if port 5432 is in use
lsof -i :5432

# Use a different port
pg_ctl start -D "$PGDATA" -o "-p 5433" -l /tmp/postgres.log
```

## Verification Checklist

Before submitting changes, verify:

- [ ] `mise run lint` passes
- [ ] Local installation works: `mise install postgres-binary:postgres@15.15.0`
- [ ] Binary verification: `postgres --version`, `psql --version`
- [ ] Environment setup: `$PGDATA` exists and is initialized
- [ ] Database operations: can start, query, and stop PostgreSQL
- [ ] Docker tests pass: `./test/run-docker-tests.sh`
