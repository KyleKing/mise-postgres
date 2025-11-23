--- Installs PostgreSQL from pre-built binaries with platform detection and SHA256 verification
--- @param ctx table Context containing tool, version, and install_path
--- @return table Empty table on success
function BackendInstall(ctx)
    local tool = ctx.tool
    local version = ctx.version
    local install_path = ctx.install_path

    -- Validate inputs
    if not tool or tool == "" then
        error("Tool name is required")
    end
    if not version or version == "" then
        error("Version is required")
    end
    if not install_path or install_path == "" then
        error("Install path is required")
    end

    -- Only handle postgres/postgresql tools
    if tool ~= "postgres" and tool ~= "postgresql" then
        error("This backend only supports 'postgres' or 'postgresql' tools")
    end

    -- Detect platform and get Rust target triple
    local platform_target = get_rust_target()
    print("Installing PostgreSQL " .. version .. " for platform: " .. platform_target)

    -- Download and verify PostgreSQL binary
    download_and_verify_postgresql(version, platform_target, install_path)

    -- Initialize PostgreSQL data directory
    initialize_pgdata(install_path)

    print("PostgreSQL " .. version .. " installed successfully at " .. install_path)
    return {}
end

--- Maps RUNTIME platform to Rust target triple used by theseus-rs/postgresql-binaries
--- @return string Rust target triple (e.g., "x86_64-apple-darwin")
function get_rust_target()
    local os_type = RUNTIME.osType -- "Darwin", "Linux", "Windows"
    local arch_type = RUNTIME.archType -- "amd64", "386", "arm64", etc.

    -- Platform mapping table
    local platform_map = {
        -- macOS
        ["Darwin-amd64"] = "x86_64-apple-darwin",
        ["Darwin-arm64"] = "aarch64-apple-darwin",

        -- Linux (glibc) - most common
        ["Linux-amd64"] = "x86_64-unknown-linux-gnu",
        ["Linux-arm64"] = "aarch64-unknown-linux-gnu",
        ["Linux-386"] = "i686-unknown-linux-gnu",

        -- Linux (musl) - can be detected via environment or preference
        -- For now, default to glibc. Future: detect libc type
        -- ["Linux-amd64-musl"] = "x86_64-unknown-linux-musl",
        -- ["Linux-arm64-musl"] = "aarch64-unknown-linux-musl",

        -- Windows
        ["Windows-amd64"] = "x86_64-pc-windows-msvc",
    }

    local key = os_type .. "-" .. arch_type
    local target = platform_map[key]

    if not target then
        error(string.format(
            "Unsupported platform: %s (OS: %s, Arch: %s)\nSupported platforms: macOS (x86_64/arm64), Linux (x86_64/arm64), Windows (x86_64)",
            key,
            os_type,
            arch_type
        ))
    end

    return target
end

--- Downloads PostgreSQL binary with SHA256 checksum verification
--- @param version string PostgreSQL version (e.g., "15.10.0")
--- @param platform string Rust target triple
--- @param install_path string Destination directory
function download_and_verify_postgresql(version, platform, install_path)
    local base_url = string.format(
        "https://github.com/theseus-rs/postgresql-binaries/releases/download/%s",
        version
    )

    local filename = string.format("postgresql-%s-%s.tar.gz", version, platform)
    local download_url = base_url .. "/" .. filename
    local checksum_url = download_url .. ".sha256"
    local temp_archive = install_path .. "/" .. filename

    print("Downloading checksum from: " .. checksum_url)

    -- Download and parse SHA256 checksum file
    local ok, checksum_content = pcall(http.get, checksum_url)
    if not ok then
        error("Failed to download checksum file: " .. tostring(checksum_content))
    end

    -- Parse checksum (format: "abc123...  filename" or just "abc123...")
    local expected_sha256 = checksum_content:match("^(%x+)")
    if not expected_sha256 then
        error("Invalid checksum format in file: " .. checksum_content)
    end

    print("Expected SHA256: " .. expected_sha256)
    print("Downloading PostgreSQL binary from: " .. download_url)

    -- Download with automatic SHA256 verification
    -- mise's http.download_file will verify the checksum automatically
    ok, err = pcall(http.download_file, download_url, temp_archive, {
        sha256 = expected_sha256,
    })

    if not ok then
        error("Failed to download PostgreSQL binary: " .. tostring(err))
    end

    print("Download complete, SHA256 verified")
    print("Extracting archive...")

    -- Extract the archive to install_path
    -- The archive contains a flat structure with bin/, lib/, share/, etc.
    ok, err = pcall(archiver.extract, temp_archive, install_path)
    if not ok then
        error("Failed to extract archive: " .. tostring(err))
    end

    -- Clean up archive file
    os.remove(temp_archive)

    print("Extraction complete")
end

--- Initializes PostgreSQL data directory (PGDATA) using initdb
--- @param install_path string PostgreSQL installation directory
function initialize_pgdata(install_path)
    local pgdata_dir = install_path .. "/data"

    -- Check if data directory already exists
    if file.exists(pgdata_dir) then
        print("PGDATA directory already exists, skipping initdb")
        return
    end

    print("Initializing PostgreSQL data directory at: " .. pgdata_dir)

    local initdb_bin = install_path .. "/bin/initdb"

    -- Check if initdb exists (it should after extraction)
    if not file.exists(initdb_bin) then
        error("initdb binary not found at: " .. initdb_bin)
    end

    -- Run initdb to initialize the database cluster
    -- Use UTF-8 encoding and C locale for maximum compatibility
    local ok, result = pcall(cmd.exec, initdb_bin, {
        "-D",
        pgdata_dir,
        "--encoding=UTF8",
        "--locale=C",
    })

    if not ok then
        error("Failed to initialize PostgreSQL data directory: " .. tostring(result))
    end

    print("Database cluster initialized successfully")
end
