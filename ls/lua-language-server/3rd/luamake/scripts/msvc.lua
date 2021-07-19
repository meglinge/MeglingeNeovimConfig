require 'bee'
local sp = require 'bee.subprocess'
local fs = require 'bee.filesystem'

local function Is64BitWindows()
    -- https://docs.microsoft.com/en-us/archive/blogs/david.wang/howto-detect-process-bitness
    return os.getenv "PROCESSOR_ARCHITECTURE" == "AMD64" or os.getenv "PROCESSOR_ARCHITEW6432" == "AMD64"
end

local ProgramFiles = Is64BitWindows() and 'ProgramFiles(x86)' or 'ProgramFiles'
local vswhere = fs.path(os.getenv(ProgramFiles)) / 'Microsoft Visual Studio' / 'Installer' / 'vswhere.exe'
local need = { LIB = true, LIBPATH = true, PATH = true, INCLUDE = true }

local function createfile(filename, content)
    local f = assert(io.open(filename:string(), 'w'))
    if content then
        f:write(content)
    end
    f:close()
end

local function strtrim(str)
    return str:gsub("^%s*(.-)%s*$", "%1")
end

local InstallDir
local function installpath()
    if InstallDir then
        return InstallDir
    end
    local process = assert(sp.spawn {
        vswhere,
        '-latest',
        '-utf8',
        '-products', '*',
        '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
        '-property', 'installationPath',
        stdout = true,
    })
    local result = strtrim(process.stdout:read 'a')
    process.stdout:close()
    local code = process:wait()
    if code ~= 0 then
        os.exit(code, true)
    end
    assert(result ~= "", "can't find msvc.")
    InstallDir = fs.path(result)
    return InstallDir
end

local function parse_env(str)
    local pos = str:find('=')
    if not pos then
        return
    end
    return strtrim(str:sub(1, pos - 1)), strtrim(str:sub(pos + 1))
end

local function vsdevcmd(arch, f)
    local vsvars32 = installpath() / 'Common7' / 'Tools' / 'VsDevCmd.bat'
    local args = { vsvars32:string() }
    if arch then
        args[#args+1] = ('-arch=%s'):format(arch)
    end
    local process = assert(sp.spawn {
        'cmd', '/k', args, '&', 'set',
        stderr = true,
        stdout = true,
        searchPath = true,
    })
    for line in process.stdout:lines() do
        local name, value = parse_env(line)
        if name and value then
            f(name, value)
        end
    end
    local err = process.stderr:read "a"
    process.stdout:close()
    process.stderr:close()
    local code = process:wait()
    if code ~= 0 then
        io.stderr:write("Call `VsDevCmd.bat` error:\n")
        io.stderr:write(err)
        os.exit(code, true)
    end
end

local function environment(arch)
    local env = {}
    vsdevcmd(arch, function (name, value)
        name = name:upper()
        if need[name] then
            env[name] = value
        end
    end)
    return env
end

local function prefix(env)
    local testdir = MAKEDIR / 'luamake-temp'
    fs.create_directories(testdir)
    createfile(testdir / 'test.h')
    createfile(testdir / 'test.c', '#include "test.h"')
    local process = assert(sp.spawn {
        'cmd', '/c',
        'cl', '/showIncludes', '/nologo', '-c', 'test.c',
        searchPath = true,
        env = env,
        cwd = testdir,
        stdout = true,
        stderr = true,
    })
    local prefix
    for line in process.stdout:lines() do
        local m = line:match('[^:]+:[^:]+:')
        if m then
            prefix = m
            break
        end
    end
    process.stdout:close()
    process.stderr:close()
    process:wait()
    fs.remove_all(testdir)
    assert(prefix, "can't find msvc.")
    return prefix
end

local function vcrtpath(arch)
    local RedistVersion = (function ()
        local verfile = installpath() / 'VC' / 'Auxiliary' / 'Build' / 'Microsoft.VCRedistVersion.default.txt'
        local f = assert(io.open(verfile:string(), 'r'))
        local r = f:read 'a'
        f:close()
        return strtrim(r)
    end)()
    local ToolVersion = (function ()
        local verfile = installpath() / 'VC' / 'Auxiliary' / 'Build' / 'Microsoft.VCToolsVersion.default.txt'
        local f = assert(io.open(verfile:string(), 'r'))
        local r = f:read 'a'
        f:close()
        return strtrim(r)
    end)()
    local ToolsetVersion = (function ()
        local verfile = installpath() / 'VC' / 'Tools' / 'MSVC' / ToolVersion / 'include' / 'yvals_core.h'
        local f = assert(io.open(verfile:string(), 'r'))
        local r = f:read 'a'
        f:close()
        return r:match '#define%s+_MSVC_STL_VERSION%s+(%d+)'
    end)()
    return installpath() / 'VC' / 'Redist' / 'MSVC' / RedistVersion / arch / ('Microsoft.VC'..ToolsetVersion..'.CRT')
end

local function ucrtpath(arch)
    local UniversalCRTSdkDir
    vsdevcmd(arch, function (name, value)
        if name == "UniversalCRTSdkDir" then
            UniversalCRTSdkDir = value
        end
    end)
    if not UniversalCRTSdkDir then
        return
    end
    local path = fs.path(UniversalCRTSdkDir) / 'Redist'
    local res, ver
    local function accept(p)
        local ucrt = p / 'ucrt' / 'DLLs' / arch
        if fs.exists(ucrt) then
            local version = 0
            if p ~= path then
                version = p:filename():string():gsub('10%.0%.([0-9]+)%.0', '%1')
                version = tonumber(version)
            end
            if not ver or ver < version then
                res, ver = ucrt, version
            end
        end
    end
    accept(path)
    for p in path:list_directory() do
        accept(p)
    end
    if res then
        return res
    end
end

local function copy_vcrt(arch, target)
    fs.create_directories(target)
    for dll in vcrtpath(arch):list_directory() do
        if dll:filename() ~= fs.path "vccorlib140.dll" then
            fs.copy_file(dll, target / dll:filename(), true)
        end
    end
end

local function copy_ucrt(arch, target)
    fs.create_directories(target)
    for dll in ucrtpath(arch):list_directory() do
        fs.copy_file(dll, target / dll:filename(), true)
    end
end

return {
    installpath = installpath,
    environment = environment,
    prefix = prefix,
    vcrtpath = vcrtpath,
    ucrtpath = ucrtpath,
    copy_vcrt = copy_vcrt,
    copy_ucrt = copy_ucrt,
}
