---@meta

-- version: 11.5
---
---[Open in Browser](https://love2d.org/wiki/love)
---
-- NOTE: LÖVE callbacks are declared as optional @field types (not concrete
-- `function love.x() end` definitions) so a game assigning its own
-- `function love.draw()` is the single definition, not a duplicate. This is a local
-- modification to the vendored love2d LuaCATS defs; re-apply if re-vendored.
---@class love
---@field conf? fun(t: table)
---@field directorydropped? fun(path: string)
---@field displayrotated? fun(index: number, orientation: love.DisplayOrientation)
---@field draw? fun()
---@field errorhandler? fun(msg: string): function
---@field filedropped? fun(file: love.DroppedFile)
---@field focus? fun(focus: boolean)
---@field gamepadaxis? fun(joystick: love.Joystick, axis: love.GamepadAxis, value: number)
---@field gamepadpressed? fun(joystick: love.Joystick, button: love.GamepadButton)
---@field gamepadreleased? fun(joystick: love.Joystick, button: love.GamepadButton)
---@field joystickadded? fun(joystick: love.Joystick)
---@field joystickaxis? fun(joystick: love.Joystick, axis: number, value: number)
---@field joystickhat? fun(joystick: love.Joystick, hat: number, direction: love.JoystickHat)
---@field joystickpressed? fun(joystick: love.Joystick, button: number)
---@field joystickreleased? fun(joystick: love.Joystick, button: number)
---@field joystickremoved? fun(joystick: love.Joystick)
---@field keypressed? fun(key: love.KeyConstant, scancode: love.Scancode, isrepeat: boolean)
---@field keyreleased? fun(key: love.KeyConstant, scancode: love.Scancode)
---@field load? fun(arg: table, unfilteredArg: table)
---@field lowmemory? fun()
---@field mousefocus? fun(focus: boolean)
---@field mousemoved? fun(x: number, y: number, dx: number, dy: number, istouch: boolean)
---@field mousepressed? fun(x: number, y: number, button: number, istouch: boolean, presses: number)
---@field mousereleased? fun(x: number, y: number, button: number, istouch: boolean, presses: number)
---@field quit? fun(): boolean
---@field resize? fun(w: number, h: number)
---@field run? fun(): fun()
---@field textedited? fun(text: string, start: number, length: number)
---@field textinput? fun(text: string)
---@field threaderror? fun(thread: love.Thread, errorstr: string)
---@field touchmoved? fun(id: lightuserdata, x: number, y: number, dx: number, dy: number, pressure: number)
---@field touchpressed? fun(id: lightuserdata, x: number, y: number, dx: number, dy: number, pressure: number)
---@field touchreleased? fun(id: lightuserdata, x: number, y: number, dx: number, dy: number, pressure: number)
---@field update? fun(dt: number)
---@field visible? fun(visible: boolean)
---@field wheelmoved? fun(x: number, y: number)
love = {}

---
---Gets the current running version of LÖVE.
---
---
---[Open in Browser](https://love2d.org/wiki/love.getVersion)
---
---@return number major # The major version of LÖVE, i.e. 0 for version 0.9.1.
---@return number minor # The minor version of LÖVE, i.e. 9 for version 0.9.1.
---@return number revision # The revision version of LÖVE, i.e. 1 for version 0.9.1.
---@return string codename # The codename of the current version, i.e. 'Baby Inspector' for version 0.9.1.
function love.getVersion() end

---
---Gets whether LÖVE displays warnings when using deprecated functionality. It is disabled by default in fused mode, and enabled by default otherwise.
---
---When deprecation output is enabled, the first use of a formally deprecated LÖVE API will show a message at the bottom of the screen for a short time, and print the message to the console.
---
---
---[Open in Browser](https://love2d.org/wiki/love.hasDeprecationOutput)
---
---@return boolean enabled # Whether deprecation output is enabled.
function love.hasDeprecationOutput() end

---
---Gets whether the given version is compatible with the current running version of LÖVE.
---
---
---[Open in Browser](https://love2d.org/wiki/love.isVersionCompatible)
---
---@overload fun(major: number, minor: number, revision: number):boolean
---@param version string # The version to check (for example '11.3' or '0.10.2').
---@return boolean compatible # Whether the given version is compatible with the current running version of LÖVE.
function love.isVersionCompatible(version) end

---
---Sets whether LÖVE displays warnings when using deprecated functionality. It is disabled by default in fused mode, and enabled by default otherwise.
---
---When deprecation output is enabled, the first use of a formally deprecated LÖVE API will show a message at the bottom of the screen for a short time, and print the message to the console.
---
---
---[Open in Browser](https://love2d.org/wiki/love.setDeprecationOutput)
---
---@param enable boolean # Whether to enable or disable deprecation output.
function love.setDeprecationOutput(enable) end

---
---The superclass of all data.
---
---
---[Open in Browser](https://love2d.org/wiki/love)
---
---@class love.Data: love.Object
local Data = {}

---
---Creates a new copy of the Data object.
---
---
---[Open in Browser](https://love2d.org/wiki/Data:clone)
---
---@return love.Data clone # The new copy.
function Data:clone() end

---
---Gets an FFI pointer to the Data.
---
---This function should be preferred instead of Data:getPointer because the latter uses light userdata which can't store more all possible memory addresses on some new ARM64 architectures, when LuaJIT is used.
---
---
---[Open in Browser](https://love2d.org/wiki/Data:getFFIPointer)
---
---@return ffi.cdata* pointer # A raw void* pointer to the Data, or nil if FFI is unavailable.
function Data:getFFIPointer() end

---
---Gets a pointer to the Data. Can be used with libraries such as LuaJIT's FFI.
---
---
---[Open in Browser](https://love2d.org/wiki/Data:getPointer)
---
---@return lightuserdata pointer # A raw pointer to the Data.
function Data:getPointer() end

---
---Gets the Data's size in bytes.
---
---
---[Open in Browser](https://love2d.org/wiki/Data:getSize)
---
---@return number size # The size of the Data in bytes.
function Data:getSize() end

---
---Gets the full Data as a string.
---
---
---[Open in Browser](https://love2d.org/wiki/Data:getString)
---
---@return string data # The raw data.
function Data:getString() end

---
---The superclass of all LÖVE types.
---
---
---[Open in Browser](https://love2d.org/wiki/love)
---
---@class love.Object
local Object = {}

---
---Destroys the object's Lua reference. The object will be completely deleted if it's not referenced by any other LÖVE object or thread.
---
---This method can be used to immediately clean up resources without waiting for Lua's garbage collector.
---
---
---[Open in Browser](https://love2d.org/wiki/Object:release)
---
---@return boolean success # True if the object was released by this call, false if it had been previously released.
function Object:release() end

---
---Gets the type of the object as a string.
---
---
---[Open in Browser](https://love2d.org/wiki/Object:type)
---
---@return string type # The type as a string.
function Object:type() end

---
---Checks whether an object is of a certain type. If the object has the type with the specified name in its hierarchy, this function will return true.
---
---
---[Open in Browser](https://love2d.org/wiki/Object:typeOf)
---
---@param name string # The name of the type to check for.
---@return boolean b # True if the object is of the specified type, false otherwise.
function Object:typeOf(name) end

return love
