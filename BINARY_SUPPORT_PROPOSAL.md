# PostgreSQL Binary Support Proposal for mise

## Executive Summary

This proposal outlines a path to add pre-built binary support to PostgreSQL installations via mise, addressing the need for:
1. **Directory-based version management** (via mise `.tool-versions`)
2. **Fast binary installations** (no compilation, no build dependencies)
3. **Precise version control** (e.g., PostgreSQL 15.10, not just 15.x)

**Recommendation:** Implement a custom mise backend plugin that downloads PostgreSQL binaries from [theseus-rs/postgresql-binaries](https://github.com/theseus-rs/postgresql-binaries) with platform detection, SHA256 verification, and PostgreSQL-specific environment setup.

---

## Background & Problem Statement

### Current Situation

mise-postgres (and asdf-postgres) exclusively build PostgreSQL from source:
- ⏱️ **Slow**: 5-15 minutes per installation
- 🔧 **Complex dependencies**: Requires gcc, make, openssl-dev, readline-dev, etc.
- 💻 **Platform-specific issues**: Homebrew path detection, ICU version patches, UUID-OSSP fixes
- 🚫 **Explicitly unsupported**: [asdf-postgres issue #62](https://github.com/smashedtoatoms/asdf-postgres/issues/62) states binary support is intentionally excluded

### User Requirements

1. **Per-directory version management**: Already provided by mise
2. **Binary installations**: Fast installs across colleague computers
3. **Minor version precision**: Must support specific versions (e.g., 15.10 not 15.15)
4. **Common platform coverage**: macOS (Intel/M1/M2), Linux (x86_64/arm64)

### Why Not Existing Solutions?

| Solution | Issue |
|----------|-------|
| **Homebrew** | No minor version control (only `postgresql@15`, not `@15.10`) |
| **EDB Binaries** | Manual downloads, not integrated with mise, latest versions only |
| **Extend asdf-postgres** | Maintainer unlikely to accept (see issue #62) |
| **Extend mise-postgres** | Adds complexity to source-focused plugin |

---

## Research Findings

### Binary Source: theseus-rs/postgresql-binaries

**Repository:** https://github.com/theseus-rs/postgresql-binaries

**Key characteristics:**
- ✅ **Comprehensive platform coverage**: 25+ Rust target triples
- ✅ **Active maintenance**: 277 releases (latest: PostgreSQL 18.1.0, Nov 2025)
- ✅ **Full version range**: PostgreSQL 13.23, 14.20, 15.15, 16.11, 17.7, 18.1
- ✅ **SHA256 checksums**: Security verification for all downloads
- ✅ **GitHub releases**: Compatible with mise backends (UBI, GitHub, custom)

**Supported platforms:**
- macOS: `x86_64-apple-darwin`, `aarch64-apple-darwin` (M1/M2)
- Linux (glibc): `x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu`
- Linux (musl): `x86_64-unknown-linux-musl`, `aarch64-unknown-linux-musl`
- Windows: `x86_64-pc-windows-msvc`
- Additional: ARM32, PowerPC, S390x, MIPS64, and more

**Example release structure:**
```
postgresql-15.10.0-x86_64-apple-darwin.tar.gz
postgresql-15.10.0-x86_64-apple-darwin.tar.gz.sha256
postgresql-15.10.0-aarch64-apple-darwin.tar.gz
postgresql-15.10.0-aarch64-apple-darwin.tar.gz.sha256
...
```

### mise Backend Options Analysis

We evaluated five implementation approaches:

#### Option A: UBI Backend (Quickest)
**Implementation:** Use mise's built-in Universal Binary Installer
```toml
[tools]
"ubi:theseus-rs/postgresql-binaries" = "15.10.0"
```

**Pros:** Zero code, works immediately
**Cons:** No PGDATA setup, no initdb, manual platform configuration

**Verdict:** ⚠️ Insufficient - PostgreSQL needs environment configuration

---

#### Option B: Aqua Registry Contribution (Long-term)
**Implementation:** Add PostgreSQL to [aqua-registry](https://github.com/aquaproj/aqua-registry)

**Research result:** PostgreSQL is NOT currently in aqua-registry (checked Dec 2024)

**Pros:** Community-maintained, security features, checksum verification
**Cons:** 2-4 week PR review, still no PGDATA/initdb setup

**Verdict:** ⚠️ Good future contribution, but insufficient alone

---

#### Option C: Custom Backend Plugin ⭐ **RECOMMENDED**
**Implementation:** Create `mise-postgres-binary` backend plugin using Lua

**Pros:**
- ✅ Full control over installation (download, extract, initdb)
- ✅ PostgreSQL-specific environment setup (PGDATA, LD_LIBRARY_PATH)
- ✅ Platform detection via `RUNTIME` object
- ✅ SHA256 verification via mise's built-in `http.download_file()`
- ✅ Supports multiple tools (`postgres`, `psql`, `pg_dump`)
- ✅ Template with CI/static analysis available
- ✅ ~200 lines of Lua code

**Cons:**
- ⚠️ Code to maintain (mitigated by simplicity)
- ⚠️ Lua learning curve (mitigated by template/examples)

**Verdict:** ✅ **Best option** - meets all requirements

---

#### Option D: Fork mise-postgres
**Pros:** Preserves existing infrastructure
**Cons:** Fork maintenance burden, diverges from upstream

**Verdict:** ❌ Only if contributions to upstream are required

---

#### Option E: Hybrid (UBI + mise-postgres)
**Pros:** Leverages existing tools
**Cons:** Complex version management, confusing UX

**Verdict:** ❌ Over-engineered

---

## Recommended Implementation: Custom Backend Plugin

### Architecture

**Plugin name:** `mise-postgres-binary` (or contribute as `postgresql` to mise registry)

**File structure:**
```
mise-postgres-binary/
├── .github/
│   └── workflows/ci.yml          # Cross-platform CI
├── hooks/
│   ├── backend_list_versions.lua # Fetch versions from GitHub API
│   ├── backend_install.lua       # Download, verify, extract, initdb
│   └── backend_exec_env.lua      # Set PGDATA, PATH, LD_LIBRARY_PATH
├── .luacheckrc                   # Lua linter config
├── hk.pkl                        # Pre-commit hooks
├── mise.toml                     # Dev tools (luacheck, stylua)
├── metadata.lua                  # Plugin metadata
└── README.md
```

### Key Implementation Details

#### 1. Platform Detection (`backend_install.lua`)

mise provides `RUNTIME` global object:
```lua
function get_rust_target()
    local os = RUNTIME.osType    -- "Darwin", "Linux", "Windows"
    local arch = RUNTIME.archType -- "amd64", "arm64", "386"

    local mapping = {
        ["Darwin-arm64"] = "aarch64-apple-darwin",
        ["Darwin-amd64"] = "x86_64-apple-darwin",
        ["Linux-amd64"] = "x86_64-unknown-linux-gnu",
        ["Linux-arm64"] = "aarch64-unknown-linux-gnu",
        ["Windows-amd64"] = "x86_64-pc-windows-msvc",
    }

    local key = os .. "-" .. arch
    return mapping[key] or error("Unsupported platform: " .. key)
end
```

**Scalability:** Add new platforms by extending the mapping table.

#### 2. SHA256 Verification

mise's `http` module supports automatic verification:
```lua
function download_postgresql(version, platform, dest_dir)
    local base_url = string.format(
        "https://github.com/theseus-rs/postgresql-binaries/releases/download/%s",
        version
    )

    local filename = string.format("postgresql-%s-%s.tar.gz", version, platform)

    -- Download checksum file
    local checksum_url = base_url .. "/" .. filename .. ".sha256"
    local checksum_content = http.get(checksum_url)
    local expected_sha256 = checksum_content:match("^(%x+)")

    -- Download with automatic SHA256 verification
    local download_url = base_url .. "/" .. filename
    http.download_file(download_url, dest_dir .. "/" .. filename, {
        sha256 = expected_sha256
    })

    -- Extract archive
    archiver.extract(dest_dir .. "/" .. filename, dest_dir)
end
```

**Feature parity with aqua:** ✅ Same SHA256 verification approach

#### 3. PostgreSQL-Specific Setup

**Environment variables (`backend_exec_env.lua`):**
```lua
function BackendExecEnv(ctx)
    local install_path = ctx.install_path

    return {
        env_vars = {
            { key = "PGDATA", value = install_path .. "/data" },
            { key = "PATH", value = install_path .. "/bin" },
            { key = "LD_LIBRARY_PATH", value = install_path .. "/lib" },
            { key = "DYLD_LIBRARY_PATH", value = install_path .. "/lib" }, -- macOS
        }
    }
end
```

**Database initialization (`backend_install.lua`):**
```lua
-- After extracting binaries, initialize PGDATA
local pgdata_dir = install_path .. "/data"
if not file.exists(pgdata_dir) then
    cmd.exec(install_path .. "/bin/initdb", {
        "-D", pgdata_dir,
        "--encoding=UTF8",
        "--locale=C"
    })
end
```

#### 4. Version Discovery

Fetch available versions from GitHub Releases API:
```lua
function BackendListVersions(ctx)
    local api_url = "https://api.github.com/repos/theseus-rs/postgresql-binaries/releases"
    local response = http.get(api_url)
    local releases = json.decode(response)

    local versions = {}
    for _, release in ipairs(releases) do
        table.insert(versions, release.tag_name)
    end

    return { versions = versions }
end
```

### Built-in Lua Capabilities

mise provides comprehensive Lua modules that cover all requirements:

| Requirement | mise Module | Functions |
|-------------|-------------|-----------|
| **Platform detection** | `RUNTIME` global | `RUNTIME.osType`, `RUNTIME.archType` |
| **HTTP downloads** | `http` module | `http.get()`, `http.download_file()` |
| **SHA256 verification** | `http` module | `http.download_file({sha256 = "..."})` |
| **Archive extraction** | `archiver` module | `archiver.extract()` |
| **JSON parsing** | `json` module | `json.encode()`, `json.decode()` |
| **File operations** | `file` module | `file.exists()`, `file.join_path()` |
| **Command execution** | `cmd` module | `cmd.exec()` |
| **Windows support** | `RUNTIME` global | `RUNTIME.osType == "Windows"` |

**Conclusion:** ✅ No external framework needed - mise provides everything required

### Quality Assurance

The [mise-backend-plugin-template](https://github.com/jdx/mise-backend-plugin-template) includes production-grade tooling:

**Static analysis:**
- **luacheck**: Lua linter configured for mise globals
- **stylua**: Lua code formatter
- **actionlint**: GitHub Actions workflow validator
- **hk**: Pre-commit hook orchestrator

**CI/CD:**
- Cross-platform testing (Ubuntu + macOS)
- Automated linting on every PR
- Auto-formatting via pre-commit hooks

**Configuration files:**
- `.luacheckrc`: Defines `PLUGIN`, `RUNTIME`, `http`, `json`, `file`, `cmd` globals
- `hk.pkl`: Pre-commit workflow (luacheck + stylua + actionlint)
- `.github/workflows/ci.yml`: GitHub Actions pipeline

---

## Implementation Estimate

**Code complexity:**
- `metadata.lua`: ~20 lines (plugin metadata)
- `backend_list_versions.lua`: ~30 lines (GitHub API query)
- `backend_install.lua`: ~100 lines (download, verify, extract, initdb)
- `backend_exec_env.lua`: ~50 lines (environment variables)
- Utility functions: ~30 lines (platform mapping, SHA parsing)

**Total:** ~230 lines of Lua code

**Time estimate:** 6-8 hours for implementation + testing

**Maintenance:** Low - simple logic, comprehensive tests, static analysis

---

## Usage Example

Once implemented, users would install PostgreSQL like this:

```bash
# Install the backend plugin (one-time)
mise plugin install postgres-binary https://github.com/mise-plugins/mise-postgres-binary

# Use in project
cd my-project
mise use postgres-binary:postgres@15.10

# PostgreSQL is now available with proper environment
postgres --version
# PostgreSQL 15.10

# PGDATA is automatically configured
echo $PGDATA
# /home/user/.local/share/mise/installs/postgres-binary--postgres/15.10/data

# Start PostgreSQL server
pg_ctl start -D $PGDATA
```

---

## Future Enhancements

1. **Contribute to aqua-registry** (after validation)
   - Extract configuration logic from backend plugin
   - Submit PR to aqua-registry
   - Benefit entire mise/aqua community

2. **Support multiple binary sources**
   - theseus-rs (default)
   - EDB PostgreSQL Binaries
   - Custom enterprise builds

3. **PostgreSQL extension management**
   - Support for PostGIS, TimescaleDB, etc.
   - Automatic extension compilation against binaries

4. **Source build fallback** (optional)
   - Detect when no binary available for platform
   - Fall back to source compilation
   - Requires integration with mise-postgres

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| **theseus-rs discontinuation** | High | Monitor project health; easy to switch sources |
| **Platform not supported** | Medium | Document supported platforms; consider source fallback |
| **SHA256 verification failure** | Low | Retry download; log clear error message |
| **Lua API changes** | Low | mise maintains backward compatibility; pin mise version |

---

## Decision Recommendation

**Proceed with Option C: Custom Backend Plugin**

**Justification:**
1. ✅ Meets all three user requirements (directory management, binary install, version control)
2. ✅ PostgreSQL-specific needs addressed (PGDATA, initdb, environment)
3. ✅ Built-in Lua capabilities provide feature parity with aqua (SHA256, platform detection)
4. ✅ High-quality template available with static analysis and CI
5. ✅ Reasonable implementation effort (~8 hours)
6. ✅ Low maintenance burden (~230 lines of simple Lua)
7. ✅ Future-proof (can contribute to aqua-registry later)

**Next steps:**
1. Create repository from [mise-backend-plugin-template](https://github.com/jdx/mise-backend-plugin-template)
2. Implement three hooks (list_versions, install, exec_env)
3. Test on macOS (Intel + M1/M2) and Linux (x86_64 + arm64)
4. Publish to mise-plugins organization
5. (Optional) Extract configuration and contribute to aqua-registry

---

## Appendix: Research Sources

- [asdf-postgres issue #62: Binary support discussion](https://github.com/smashedtoatoms/asdf-postgres/issues/62)
- [theseus-rs/postgresql-binaries](https://github.com/theseus-rs/postgresql-binaries)
- [mise Backend Plugin Development](https://mise.jdx.dev/backend-plugin-development.html)
- [mise Backend Plugin Template](https://github.com/jdx/mise-backend-plugin-template)
- [mise Lua Modules Documentation](https://mise.jdx.dev/plugin-lua-modules.html)
- [mise Discussion #5620: Custom Backends](https://github.com/jdx/mise/discussions/5620)
- [mise Discussion #5604: GitHub/GitLab/HTTP Backends](https://github.com/jdx/mise/discussions/5604)
- [aqua-registry](https://github.com/aquaproj/aqua-registry)
- [luacheck - Lua Static Analyzer](https://github.com/mpeterv/luacheck)
- [Vfox Backend Documentation](https://mise.jdx.dev/dev-tools/backends/vfox.html)

---

## Appendix: Options Comparison Matrix

| Criteria | UBI | Aqua Registry | Custom Backend | Fork mise-postgres | Hybrid |
|----------|-----|---------------|----------------|-------------------|--------|
| **Setup Time** | 5 min | 2-4 weeks | 1-2 days | 1 day | 2-3 days |
| **Code to Write** | 0 | ~50 lines YAML | ~230 lines Lua | ~300 lines bash | ~150 lines |
| **Maintenance** | None | Community | Low | Medium | High |
| **PGDATA Setup** | ❌ Manual | ❌ No | ✅ Yes | ✅ Yes | ⚠️ Complex |
| **initdb Support** | ❌ No | ❌ No | ✅ Yes | ✅ Yes | ⚠️ Complex |
| **SHA256 Verify** | ⚠️ Basic | ✅ Yes | ✅ Yes | ✅ Possible | ✅ Yes |
| **Platform Detection** | ⚠️ Manual | ✅ Auto | ✅ Auto | ✅ Auto | ✅ Auto |
| **Windows Support** | ⚠️ Limited | ✅ Yes | ✅ Yes | ❌ No | ⚠️ Partial |
| **Version Control** | ✅ Full | ✅ Full | ✅ Full | ✅ Full | ⚠️ Dual |
| **Community Benefit** | ❌ No | ✅✅ High | ✅ Medium | ❌ No | ❌ No |
| **Recommendation** | ⭐⭐ Quick Start | ⭐⭐⭐⭐ Long-term | ⭐⭐⭐⭐⭐ **Best** | ⭐ If needed | ⭐ Avoid |

---

**Document Version:** 1.0
**Date:** 2025-11-23
**Author:** Research analysis for mise-postgres binary support
