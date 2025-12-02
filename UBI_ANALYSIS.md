# UBI Backend Analysis for PostgreSQL

## Can UBI Work with theseus-rs/postgresql-binaries?

**Short answer:** UBI can download and extract the binaries, but **cannot provide a complete PostgreSQL installation**.

## What UBI Can Do

✅ **Download from GitHub releases**: theseus-rs/postgresql-binaries is on GitHub
✅ **Extract tarballs**: UBI supports `tar.gz` extraction
✅ **Platform detection**: Can use `matching` parameter for platform-specific assets
✅ **Multi-file extraction**: Can use `extract_all` for full directory structures

## Example UBI Configuration

```toml
[tools]
"ubi:theseus-rs/postgresql-binaries" = "15.10.0"

[tool.ubi:theseus-rs/postgresql-binaries]
exe = "bin/postgres"
matching = "x86_64-apple-darwin"  # Must specify per-platform
extract_all = true  # Extract entire directory structure

[env]
# Manual configuration required
PGDATA = "/path/to/postgres-data"
```

## Critical Limitations

### 1. No Automatic Environment Setup

UBI extracts binaries but **does not configure PostgreSQL-specific environment variables**:

❌ **PGDATA**: Not set automatically (PostgreSQL won't know where to store data)
❌ **LD_LIBRARY_PATH**: Not configured (dynamic library loading may fail)
❌ **DYLD_LIBRARY_PATH**: Not set for macOS
❌ **PATH**: Set for `exe` only, not for `psql`, `pg_dump`, etc.

**Result:** User must manually configure environment in shell profile or project scripts

### 2. No Database Initialization

UBI has no concept of PostgreSQL's required setup:

❌ **initdb not executed**: Database directory not initialized
❌ **No data directory creation**: PGDATA directory not created
❌ **No default configuration**: No postgresql.conf, pg_hba.conf

**Result:** User must manually run `initdb -D $PGDATA` after installation

### 3. Platform Detection Limitations

UBI requires manual platform specification:

⚠️ **No automatic platform detection**: Must set `matching` parameter
⚠️ **Not cross-platform**: Configuration differs per OS (macOS vs Linux)
⚠️ **Team coordination**: Each developer needs different config

**Example problem:**
```toml
# Developer A (macOS M1) needs:
matching = "aarch64-apple-darwin"

# Developer B (Linux) needs:
matching = "x86_64-unknown-linux-gnu"

# Can't share the same mise.toml!
```

### 4. Multi-Binary Tool Confusion

PostgreSQL includes multiple binaries:

⚠️ **`exe` parameter**: Only points to single binary (`postgres`)
⚠️ **Other tools**: `psql`, `pg_dump`, `pg_restore`, etc. not in PATH
⚠️ **PATH setup**: UBI only adds exe location, not bin/ directory

**Result:** Users can't easily run `psql` or other PostgreSQL utilities

## Manual Workaround Example

If using UBI, users would need:

```bash
# 1. Install with UBI
mise use ubi:theseus-rs/postgresql-binaries@15.10.0

# 2. Find installation path
INSTALL_PATH=$(mise where ubi:theseus-rs/postgresql-binaries)

# 3. Manually configure environment (in .envrc or shell profile)
export PGDATA="$PWD/postgres-data"
export PATH="$INSTALL_PATH/bin:$PATH"
export LD_LIBRARY_PATH="$INSTALL_PATH/lib:$LD_LIBRARY_PATH"
export DYLD_LIBRARY_PATH="$INSTALL_PATH/lib:$DYLD_LIBRARY_PATH"

# 4. Manually initialize database
mkdir -p "$PGDATA"
"$INSTALL_PATH/bin/initdb" -D "$PGDATA"

# 5. Now can use PostgreSQL
postgres --version
psql --version
```

**This defeats the purpose of automated version management!**

## Comparison: UBI vs Custom Backend

| Feature | UBI | Custom Backend Plugin |
|---------|-----|----------------------|
| **Binary download** | ✅ Yes | ✅ Yes |
| **SHA256 verification** | ⚠️ Limited | ✅ Yes (explicit) |
| **Platform detection** | ❌ Manual | ✅ Automatic (RUNTIME) |
| **PGDATA setup** | ❌ No | ✅ Automatic |
| **initdb execution** | ❌ No | ✅ Automatic |
| **Library paths** | ❌ No | ✅ Automatic |
| **Multi-binary PATH** | ⚠️ exe only | ✅ Full bin/ directory |
| **Team portability** | ❌ Platform-specific config | ✅ Cross-platform |
| **User experience** | ⚠️ Requires manual setup | ✅ Just works |

## Verdict

**UBI is insufficient for PostgreSQL** due to:
1. Missing PostgreSQL-specific environment setup
2. No database initialization
3. Manual platform configuration required
4. Poor multi-binary tool support

**Custom backend plugin is necessary** to provide:
- Automatic platform detection
- PGDATA and library path configuration
- Automatic initdb execution
- Complete PostgreSQL environment setup
- Cross-platform team portability

## Recommendation

**Proceed with custom mise backend plugin implementation** as originally proposed.

UBI could be used as a building block (download mechanism), but the backend plugin is needed for the PostgreSQL-specific logic around environment setup and initialization.
