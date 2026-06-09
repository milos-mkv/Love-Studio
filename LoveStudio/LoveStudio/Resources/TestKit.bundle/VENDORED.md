# Vendored libraries — pinned versions

These pure-Lua libraries are vendored into this `TestKit/` and bundled into the
app. They are pinned to tagged releases for reproducibility (do **not** bump to
`master` casually — re-run the TestKit regression after any update).

| Library  | Version        | Source repo                          | Module entry            |
|----------|----------------|--------------------------------------|-------------------------|
| LuaUnit  | `LUAUNIT_V3_5` | github.com/bluebird75/luaunit        | `luaunit.lua`           |
| luassert | `v1.9.0`       | github.com/lunarmodules/luassert     | `luassert.lua` + `luassert/` |
| say      | `v1.4.1`       | github.com/lunarmodules/say          | `say/init.lua`          |
| luacov   | `v0.17.0`      | github.com/lunarmodules/luacov       | `luacov.lua` + `luacov/` |

Layout: each library sits in its own module namespace so `require("luaunit")`,
`require("luassert")`, `require("say")`, `require("luacov.runner")` resolve from a
single `package.path` root (`TestKit/?.lua;TestKit/?/init.lua`).

Hand-written (not vendored): `love_stubs.lua`, `std_doubles.lua`, `lovetest.lua`.

Verified loading + full regression under headless `love` (LOVE 11.5, LuaJIT/5.1).
