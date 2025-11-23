## Overview

This PR presents a comprehensive proposal for adding pre-built binary support to PostgreSQL installations via mise, addressing the need for fast installations without compilation.

## Problem Statement

Currently, mise-postgres (and asdf-postgres) exclusively build PostgreSQL from source:
- ⏱️ Slow installations (5-15 minutes)
- 🔧 Complex build dependencies required
- 🚫 Binary support explicitly unsupported in asdf-postgres ([issue #62](https://github.com/smashedtoatoms/asdf-postgres/issues/62))

## Research Summary

This proposal evaluates **5 implementation approaches**:
1. **UBI Backend** - Quick but lacks PostgreSQL-specific setup
2. **Aqua Registry** - Good long-term option (PostgreSQL not currently in registry)
3. **Custom Backend Plugin** ⭐ **RECOMMENDED**
4. **Fork mise-postgres** - Only if upstream contributions needed
5. **Hybrid Approach** - Over-engineered

## Key Findings

### Binary Source: theseus-rs/postgresql-binaries
- ✅ 25+ platform targets (macOS Intel/M1/M2, Linux x86_64/arm64, Windows, etc.)
- ✅ 277 releases with active maintenance
- ✅ SHA256 checksums for all downloads
- ✅ All current PostgreSQL versions (13.23, 14.20, 15.15, 16.11, 17.7, 18.1)

### mise Lua Capabilities
mise provides **built-in modules** that cover all requirements:
- ✅ Platform detection: `RUNTIME.osType`, `RUNTIME.archType`
- ✅ SHA256 verification: `http.download_file({sha256 = "..."})`
- ✅ Archive extraction: `archiver.extract()`
- ✅ Windows support: Cross-platform Lua execution

**No external framework needed** - mise has everything required!

## Recommended Solution

**Implement a custom mise backend plugin** (~230 lines of Lua):

```lua
-- Platform detection example
function get_rust_target()
    local mapping = {
        ["Darwin-arm64"] = "aarch64-apple-darwin",
        ["Darwin-amd64"] = "x86_64-apple-darwin",
        ["Linux-amd64"] = "x86_64-unknown-linux-gnu",
        ...
    }
    return mapping[RUNTIME.osType .. "-" .. RUNTIME.archType]
end
```

**Handles PostgreSQL-specific needs:**
- PGDATA environment setup
- Automatic `initdb` execution
- `LD_LIBRARY_PATH` / `DYLD_LIBRARY_PATH` configuration
- Multiple tools (`postgres`, `psql`, `pg_dump`)

## Benefits

- 🚀 **Fast installations**: Pre-built binaries, no compilation
- 🎯 **Precise version control**: Support specific versions (e.g., 15.10)
- 🔒 **Secure**: SHA256 checksum verification
- 🛠️ **PostgreSQL-aware**: Proper PGDATA and environment setup
- 🧪 **Production-ready**: Template includes luacheck, stylua, CI/CD
- 📦 **Low maintenance**: ~230 lines of simple Lua code

## Implementation Estimate

- **Complexity**: ~230 lines of Lua
- **Time**: 6-8 hours
- **Maintenance**: Low (simple logic, comprehensive tests)

## Future Enhancements

1. Contribute PostgreSQL to aqua-registry (after validation)
2. Support multiple binary sources (EDB, custom builds)
3. PostgreSQL extension management (PostGIS, TimescaleDB)
4. Optional source build fallback

## Full Documentation

See [BINARY_SUPPORT_PROPOSAL.md](./BINARY_SUPPORT_PROPOSAL.md) for:
- Complete research findings
- Detailed options comparison matrix
- Platform detection implementation
- SHA256 verification approach
- Risk analysis and mitigations
- All research sources

## Next Steps

If this proposal is accepted, I can:
1. Create repository from [mise-backend-plugin-template](https://github.com/jdx/mise-backend-plugin-template)
2. Implement the three hooks (list_versions, install, exec_env)
3. Test on macOS and Linux
4. Publish to mise-plugins organization

---

**Decision Matrix:**

| Option | Setup | Code | Maintenance | PGDATA | initdb | Recommendation |
|--------|-------|------|-------------|--------|--------|----------------|
| UBI | 5 min | 0 | None | ❌ | ❌ | ⭐⭐ Quick start |
| Aqua | 2-4 wks | 50 lines | Community | ❌ | ❌ | ⭐⭐⭐⭐ Long-term |
| **Custom Backend** | **1-2 days** | **230 lines** | **Low** | **✅** | **✅** | **⭐⭐⭐⭐⭐ Best** |
| Fork | 1 day | 300 lines | Medium | ✅ | ✅ | ⭐ If needed |
| Hybrid | 2-3 days | 150 lines | High | ⚠️ | ⚠️ | ⭐ Avoid |

---

**Recommendation: Proceed with Custom Backend Plugin**

This approach meets all requirements, leverages mise's built-in capabilities, and provides a clean foundation for future enhancements.
