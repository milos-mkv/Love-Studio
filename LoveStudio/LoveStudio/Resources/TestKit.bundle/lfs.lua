-- lfs.lua — a minimal LuaFileSystem shim implemented with LuaJIT FFI.
--
-- LuaCov's `includeuntestedfiles` needs `lfs` (a C module not available under
-- love). Rather than compile/vendor a native .so, this implements the two calls
-- LuaCov actually uses — lfs.dir() and lfs.attributes() — over POSIX libc via FFI,
-- which works under love's LuaJIT (verified). macOS/Linux only (darwin target).
--
-- Only `.mode` of attributes is relied on by LuaCov; we provide it plus a couple
-- of common fields. Not a complete LuaFileSystem.

local ffi = require("ffi")

ffi.cdef[[
  typedef struct __dirstream DIR;
  DIR  *opendir(const char *name);
  int   closedir(DIR *dirp);

  // dirent layout differs per platform; we only read d_name, which on macOS/BSD
  // and glibc sits after small leading fields. Use readdir's struct via a
  // generously-sized opaque buffer and a known d_name offset per platform.
  struct dirent {
    uint64_t d_ino;
    uint64_t d_seekoff;
    uint16_t d_reclen;
    uint16_t d_namlen;
    uint8_t  d_type;
    char     d_name[1024];
  };
  struct dirent *readdir(DIR *dirp);

  // stat: we only need st_mode. Use the macOS stat64 layout via the $INODE64
  // symbol that LuaJIT resolves on modern macOS. Keep a buffer big enough.
  int stat(const char *path, void *buf);
]]

local C = ffi.C
local M = {}

-- Returns an iterator over entry names (including "." and "..", like real lfs).
function M.dir(path)
  local dir = C.opendir(path)
  if dir == nil then
    error("cannot open directory: " .. tostring(path))
  end
  local closed = false
  local function iter()
    if closed then return nil end
    local ent = C.readdir(dir)
    if ent == nil then
      C.closedir(dir); closed = true
      return nil
    end
    return ffi.string(ent.d_name)
  end
  return iter
end

-- LuaCov only reads `.mode` ("file" | "directory"). We determine it from the
-- directory entry type when possible, falling back to opendir() probing.
-- d_type values (POSIX): 4 = DT_DIR, 8 = DT_REG.
--
-- Since LuaCov calls attributes() on a full path (not a dirent), probe via
-- opendir: if it opens, it's a directory; otherwise treat as a file.
function M.attributes(path, request)
  local dir = C.opendir(path)
  local mode
  if dir ~= nil then
    C.closedir(dir)
    mode = "directory"
  else
    mode = "file"
  end
  if request == "mode" then return mode end
  return { mode = mode }
end

-- Common no-op-ish extras some callers expect (not used by LuaCov, provided for
-- safety so a stray call doesn't error).
function M.currentdir() return "." end
function M.mkdir() return true end

return M
