-- Luacheck configuration for mise backend plugin
std = "lua51" -- mise uses Lua 5.1

-- Globals provided by mise/vfox
globals = {
    "PLUGIN", -- Plugin metadata
    "RUNTIME", -- Platform information (osType, archType)
}

-- Read-only globals (modules provided by mise)
read_globals = {
    "cmd", -- Command execution
    "http", -- HTTP requests and downloads
    "json", -- JSON encoding/decoding
    "file", -- File operations
    "html", -- HTML parsing
    "archiver", -- Archive extraction
}

-- Ignore specific warnings
ignore = {
    "631", -- Line too long
    "212", -- Unused argument (hook functions have required signatures)
    "611", -- Whitespace
    "612", -- Trailing whitespace
    "621", -- Inconsistent indentation
}

-- Hook functions may have unused parameters defined by the API
unused_args = false
