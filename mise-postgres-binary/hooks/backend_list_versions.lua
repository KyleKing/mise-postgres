--- Lists available PostgreSQL versions from theseus-rs/postgresql-binaries GitHub releases
--- @param ctx table Context containing tool information
--- @return table Table with versions array
function BackendListVersions(ctx)
    local tool = ctx.tool

    -- Only handle postgres/postgresql tools
    if tool ~= "postgres" and tool ~= "postgresql" then
        return { versions = {} }
    end

    -- Fetch releases from GitHub API
    local api_url = "https://api.github.com/repos/theseus-rs/postgresql-binaries/releases"
    local ok, response = pcall(http.get, api_url)

    if not ok then
        error("Failed to fetch versions from GitHub API: " .. tostring(response))
    end

    local releases = json.decode(response)
    local versions = {}

    for _, release in ipairs(releases) do
        -- GitHub releases use tag names for versions
        -- theseus-rs uses versions like "15.10.0", "16.11.0", etc.
        local version = release.tag_name
        if version then
            table.insert(versions, version)
        end
    end

    if #versions == 0 then
        error("No versions found in theseus-rs/postgresql-binaries releases")
    end

    return { versions = versions }
end
