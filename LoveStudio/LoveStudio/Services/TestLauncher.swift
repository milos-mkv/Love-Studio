import Foundation

// Builds the temporary directory that headless `love` runs as a "game":
//   conf.lua — disables the window/graphics/audio modules.
//   main.lua — the bootstrap: set package.path, require the facade, load the test
//              files, run (or collect), emit the wire protocol, and exit.
// The dir lives under the system temp area and is removed by TestRunner after the
// run, so the user's project is never written to.

enum TestLauncher {

    static func build(projectRoot: URL,
                      kitURL: URL,
                      files: [URL],
                      filter: String?,
                      debug: Bool,
                      coverage: Bool,
                      coverageExcludes: [String] = [],
                      collect: Bool = false) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("ls-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // For debug runs, copy mobdebug.lua into the launcher dir so the bootstrap
        // can require it (it's already on package.path via the kit/launcher dir).
        if debug, let mob = Bundle.main.url(forResource: "mobdebug", withExtension: "lua") {
            try? fm.copyItem(at: mob, to: dir.appendingPathComponent("mobdebug.lua"))
        }

        try confLua().write(to: dir.appendingPathComponent("conf.lua"), atomically: true, encoding: .utf8)
        let main = mainLua(projectRoot: projectRoot,
                           kitURL: kitURL,
                           launcherDir: dir,
                           files: files,
                           filter: filter,
                           debug: debug,
                           coverage: coverage,
                           coverageExcludes: coverageExcludes,
                           collect: collect)
        try main.write(to: dir.appendingPathComponent("main.lua"), atomically: true, encoding: .utf8)
        return dir
    }

    // MARK: conf.lua

    private static func confLua() -> String {
        """
        -- [LÖVE Studio] test runner — headless config (auto-generated)
        function love.conf(t)
          t.window = false
          t.modules.graphics = false
          t.modules.audio = false
          t.modules.window = false
          t.modules.sound = false
          t.modules.physics = false
          t.modules.joystick = false
        end
        """
    }

    // MARK: main.lua bootstrap

    private static func mainLua(projectRoot: URL,
                                kitURL: URL,
                                launcherDir: URL,
                                files: [URL],
                                filter: String?,
                                debug: Bool,
                                coverage: Bool,
                                coverageExcludes: [String],
                                collect: Bool) -> String {
        let kit = luaStr(kitURL.path)
        let proj = luaStr(projectRoot.path)
        let launcher = luaStr(launcherDir.path)
        let reportPath = luaStr(launcherDir.appendingPathComponent("luacov.report.out").path)
        let statsPath = luaStr(launcherDir.appendingPathComponent("luacov.stats.out").path)
        let filterLua = filter.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" } ?? "nil"
        let coverageLua = coverage ? "true" : "false"
        let coverageExcludeLua = coverageExcludes
            .map { "          " + luaStr($0) + "," }
            .joined(separator: "\n")

        // For a debug run, connect mobdebug to the DebugServer (:8172) before the test.
        let debugStart = debug ? """

          -- connect to the LÖVE Studio debug server before running the test
          local okmd, md = pcall(require, "mobdebug")
          if okmd then pcall(function() md.start("localhost", 8172) end) end
        """ : ""

        return """
        -- test runner bootstrap (auto-generated)
        function love.load()
          -- Capture the real exit/output before the doubles replace love.*/std libs.
          -- Exit with os.exit, not love.event.quit: quit only queues, letting LÖVE run
          -- one more frame against the now-doubled love table, which opens an error
          -- window. os.exit ends the process immediately.
          local realExit  = os.exit
          local realWrite = io.write

          package.path = \(kit) .. "/?.lua;" .. \(kit) .. "/?/init.lua;"
                      .. \(launcher) .. "/?.lua;"
                      .. \(proj) .. "/?.lua;" .. \(proj) .. "/?/init.lua;" .. package.path
        \(debugStart)

          local coverageOn = \(coverageLua)
          local covRunner
          if coverageOn then
            local ok, runner = pcall(require, "luacov.runner")
            if ok then
              covRunner = runner
              covRunner.init({
                statsfile  = \(statsPath),
                reportfile = \(reportPath),
                runreport  = false,
                -- exclude our kit + the generated bootstrap/test files, plus the
                -- user-configured coverage excludes. Only the user's game code
                -- should appear in coverage.
                exclude = {
                  "TestKit", "luaunit", "luassert", "say", "luacov", "lfs",
                  "%.test$", "_test$", "_spec$",
                  -- always exclude anything inside a dot-folder (.love-studio,
                  -- .git, .vscode, …): a "." segment at path start or after a "/".
                  "^%.", "/%.",
        \(coverageExcludeLua)
                },
              })
            end
          end

          local lt = require("lovetest")
          lt.configure{ emit = realWrite }
          lt.expose(_G)
          -- Debug runs only: load project modules with filename chunk names so
          -- breakpoints match. (It changes the chunk name LuaCov records under, so it
          -- must not run for coverage runs.)
          if \(debug ? "true" : "false") then
            lt.installFilenameChunkLoader(\(proj))
          end

          -- Load every configured test file (paths passed from Swift).
          local files = {
        \(files.map { "    " + luaStr($0.path) + "," }.joined(separator: "\n"))
          }
          for _, f in ipairs(files) do
            local ok, err = pcall(function() lt.loadFile(f) end)
            if not ok then realWrite("[[LS_OUT]]{\\"id\\":\\"<bootstrap>\\",\\"text\\":\\"load fail: " .. tostring(err) .. "\\"}\\n") end
          end

          if \(collect ? "true" : "false") then
            -- DISCOVERY pass: build the tree (emit [[LS_TREE]]) without running tests.
            lt.collect()
          else
            local summary = lt.run{ filter = \(filterLua) }

            if coverageOn and covRunner then
              covRunner.shutdown()                 -- writes stats
              -- emits [[LS_COV]] (overall %) + [[LS_COVLINES]] per file (gutter data);
              -- includeUntested=true counts whole-project .lua files at 0% (lfs shim).
              require("lovetest_coverage").emit(\(statsPath), \(reportPath), realWrite, \(proj),
                                                { includeUntested = true })
            end
          end

          realExit(0)
        end

        -- Defined so LÖVE has callbacks, but love.load exits via os.exit before the
        -- loop runs. If a frame ever does run, quit immediately rather than error.
        function love.update() os.exit(0) end
        function love.draw() end
        """
    }

    // MARK: helpers

    // A Lua double-quoted string literal with backslashes/quotes escaped.
    private static func luaStr(_ s: String) -> String {
        let esc = s.replacingOccurrences(of: "\\", with: "\\\\")
                   .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(esc)\""
    }
}
