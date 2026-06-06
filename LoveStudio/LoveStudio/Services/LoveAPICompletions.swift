import Foundation

enum LoveAPICompletions {

    static func completions(for rawPrefix: String) -> [String] {
        let prefix = rawPrefix.lowercased()
        if prefix == "love" || prefix == "love." { return moduleNames.sorted() }
        for (module, fns) in api {
            let moduleKey    = "love.\(module)"
            let moduleKeyDot = "\(moduleKey)."
            if prefix == moduleKey || prefix == moduleKeyDot {
                return fns.map { "\(moduleKey).\($0)" }.sorted()
            }
            if prefix.hasPrefix(moduleKeyDot) {
                let partial = String(prefix.dropFirst(moduleKeyDot.count))
                return fns.filter { $0.hasPrefix(partial) }.map { "\(moduleKey).\($0)" }.sorted()
            }
        }
        if prefix.hasPrefix("love.") {
            let partial = String(prefix.dropFirst("love.".count))
            return api.keys.filter { $0.hasPrefix(partial) }.map { "love.\($0)" }.sorted()
        }
        return []
    }

    private static let moduleNames: [String] = api.keys.map { "love.\($0)" }

    private static let api: [String: [String]] = [
        "graphics": [
            "arc","circle","clear","draw","drawInstanced","drawLayer","ellipse",
            "flushBatch","getBackgroundColor","getBlendMode","getCanvas","getColor",
            "getDefaultFilter","getDimensions","getFont","getHeight","getLineJoin",
            "getLineStyle","getLineWidth","getPixelDimensions","getPixelHeight",
            "getPixelWidth","getPointSize","getRendererInfo","getScissor","getShader",
            "getStats","getStencilTest","getWidth","intersectScissor",
            "inverseTransformPoint","isActive","isWireframe","line","newArrayImage",
            "newCanvas","newCubeImage","newFont","newImage","newImageFont","newMesh",
            "newParticleSystem","newQuad","newShader","newSpriteBatch","newText",
            "newVideo","newVolumeImage","origin","points","polygon","pop","present",
            "print","printf","push","rectangle","replaceTransform","reset","rotate",
            "scale","scissor","setBackgroundColor","setBlendMode","setCanvas",
            "setColor","setColorMask","setDefaultFilter","setDepthMode","setFont",
            "setFrontFaceWinding","setLineJoin","setLineStyle","setLineWidth",
            "setMeshCullMode","setNewFont","setPointSize","setScissor","setShader",
            "setStencilTest","setWireframe","shear","stencil","transformPoint","translate"
        ],
        "audio": [
            "getActiveSourceCount","getDistanceModel","getDopplerScale","getEffect",
            "getMaxSourceCount","getOrientation","getPosition","getRecordingDevices",
            "getSourceCount","getVelocity","getVolume","isEffectsSupported",
            "newQueueableSource","newSource","pause","play","resume","rewind",
            "setDistanceModel","setDopplerScale","setEffect","setMixWithSystem",
            "setOrientation","setPosition","setVelocity","setVolume","stop"
        ],
        "keyboard": [
            "getKeyFromScancode","getScancodeFromKey","hasKeyRepeat","hasTextInput",
            "isDown","isScancodeDown","setKeyRepeat","setTextInput"
        ],
        "mouse": [
            "getCursor","getPosition","getRelativeMode","getSystemCursor","getX","getY",
            "isDown","isGrabbed","isVisible","newCursor","setCursor","setGrabbed",
            "setPosition","setRelativeMode","setVisible","setX","setY"
        ],
        "math": [
            "colorFromBytes","colorToBytes","compress","decompress","gammaToLinear",
            "getRandomSeed","getRandomState","isConvex","linearToGamma",
            "newBezierCurve","newRandomGenerator","newTransform","noise","random",
            "randomNormal","setRandomSeed","setRandomState","triangulate"
        ],
        "physics": [
            "getDistance","getMeter","newBody","newChainShape","newCircleShape",
            "newDistanceJoint","newEdgeShape","newFixture","newFrictionJoint",
            "newGearJoint","newMotorJoint","newMouseJoint","newPolygonShape",
            "newPrismaticJoint","newPulleyJoint","newRectangleShape",
            "newRevoluteJoint","newRopeJoint","newWeldJoint","newWheelJoint",
            "newWorld","setMeter"
        ],
        "filesystem": [
            "append","areSymlinksEnabled","createDirectory","enumDirectory","exists",
            "getAppdataDirectory","getCRequirePath","getDirectoryItems","getIdentity",
            "getInfo","getLastModified","getRealDirectory","getRequirePath",
            "getSaveDirectory","getSize","getSource","getSourceBaseDirectory",
            "getUserDirectory","getWorkingDirectory","isFused","isSymlink","lines",
            "load","mount","newFile","newFileData","read","remove","setCRequirePath",
            "setIdentity","setRequirePath","setSymlinksEnabled","unmount","write"
        ],
        "window": [
            "close","fromPixels","getDPIScale","getDesktopDimensions","getDisplayCount",
            "getDisplayName","getDisplayOrientation","getFullscreen","getFullscreenModes",
            "getIcon","getMode","getPosition","getSafeArea","getTitle","getVSync",
            "hasFocus","hasMouseFocus","isDisplaySleepEnabled","isMaximized",
            "isMinimized","isOpen","isVisible","maximize","minimize",
            "requestAttention","restore","setDisplaySleepEnabled","setFullscreen",
            "setIcon","setMode","setPosition","setTitle","setVSync",
            "showMessageBox","toPixels","updateMode"
        ],
        "timer":      ["getAverageDelta","getDelta","getFPS","getTime","sleep","step"],
        "event":      ["clear","poll","pump","push","quit","wait"],
        "system":     ["getClipboardText","getOS","getPowerInfo","getProcessorCount","hasBackgroundMusic","openURL","setClipboardText","vibrate"],
        "touch":      ["getPosition","getPressure","getTouches"],
        "joystick":   ["getJoystickCount","getJoysticks"],
        "video":      ["newVideoStream"],
        "data":       ["compress","decode","decompress","encode","hash","newByteData","newDataView","pack","packSize","unpack"],
        "image":      ["isCompressed","newCompressedData","newImageData"],
        "sound":      ["newSoundData"],
        "font":       ["newBMFontRasterizer","newFreeTypeRasterizer","newGlyphData","newRasterizer","newTrueTypeRasterizer"],
        "thread":     ["getChannel","newChannel","newThread"]
    ]
}
