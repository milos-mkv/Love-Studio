import Foundation

// MARK: - TestLauncher
//
// Builds the temporary directory that headless `love` runs as a "game" (§5.5):
//   conf.lua  — disables window/graphics/audio (real-module tests would re-enable)
//   main.lua  — the bootstrap: capture real love.event.quit, set package.path to
//               the TestKit + project, require the facade, load test files, run,
//               emit the wire protocol, quit.
//
// The dir is created under the system temp area and removed by TestRunner after the
// run (parallel to the debugger's inject/cleanup pattern, but in an isolated temp
// dir so the user's project is never written to for tests).

enum TestLauncher {

    static func build(projectRoot: URL,
                      kitURL: URL,
                      files: [URL],
                      filter: String?,
                      debug: Bool,
                      coverage: Bool) throws -> URL {
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
                           coverage: coverage)
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
                                coverage: Bool) -> String {
        let kit = luaStr(kitURL.path)
        let proj = luaStr(projectRoot.path)
        let launcher = luaStr(launcherDir.path)
        let reportPath = luaStr(launcherDir.appendingPathComponent("luacov.report.out").path)
        let statsPath = luaStr(launcherDir.appendingPathComponent("luacov.stats.out").path)
        let filterLua = filter.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" } ?? "nil"
        let coverageLua = coverage ? "true" : "false"

        // For a debug run, connect mobdebug to the DebugServer (TCP :8172) before
        // running the (single, filtered) test. Reuses DebugServer, not runDebug (§5.4).
        let debugStart = debug ? """

          -- connect to the LÖVE Studio debug server before running the test
          local okmd, md = pcall(require, "mobdebug")
          if okmd then pcall(function() md.start("localhost", 8172) end) end
        """ : ""

        return """
        -- [LÖVE Studio] test runner bootstrap (auto-generated)
        function love.load()
          -- Capture the REAL quit/output before doubles replace love.* / std libs.
          local realQuit  = love.event.quit
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
                -- exclude our kit + the generated bootstrap/test files; only the
                -- user's game code should appear in coverage.
                exclude = { "TestKit", "luaunit", "luassert", "say", "luacov",
                            "^main$", "/main$", "%.test$", "_test$", "_spec$" },
              })
            end
          end

          local lt = require("lovetest")
          lt.configure{ emit = realWrite }
          lt.expose(_G)

          -- Load every configured test file (paths passed from Swift).
          local files = {
        \(files.map { "    " + luaStr($0.path) + "," }.joined(separator: "\n"))
          }
          for _, f in ipairs(files) do
            local ok, err = pcall(function() lt.loadFile(f) end)
            if not ok then realWrite("[[LS_OUT]]{\\"id\\":\\"<bootstrap>\\",\\"text\\":\\"load fail: " .. tostring(err) .. "\\"}\\n") end
          end

          local summary = lt.run{ filter = \(filterLua) }

          if coverageOn and covRunner then
            covRunner.shutdown()                 -- writes stats
            -- emits [[LS_COV]] (overall %) + [[LS_COVLINES]] per file (gutter data);
            -- projectRoot resolves relative game-module paths → absolute for the editor
            require("lovetest_coverage").emit(\(statsPath), \(reportPath), realWrite, \(proj))
          end

          realQuit(0)
        end

        -- love needs these defined even though we quit in load().
        function love.update() end
        function love.draw() end
        """
    }

    // MARK: helpers

    /// A Lua double-quoted string literal with backslashes/quotes escaped.
    private static func luaStr(_ s: String) -> String {
        let esc = s.replacingOccurrences(of: "\\", with: "\\\\")
                   .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(esc)\""
    }
}
