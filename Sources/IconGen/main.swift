import AppKit
import IconArt

// Emits Resources/DropNotch.icns from IconArt. Run explicitly:
//     swift run IconGen
// make-app.sh consumes the committed .icns and never runs this, so packaging
// does not depend on the generator working.

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
let output = root.appendingPathComponent("Resources/DropNotch.icns")

/// (base point size, scale) — the ten variants iconutil expects.
let variants: [(Int, Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
    (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("IconGen: \(message)\n".data(using: .utf8)!)
    exit(1)
}

try? FileManager.default.removeItem(at: iconset)
do {
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
} catch {
    fail("could not create \(iconset.path): \(error.localizedDescription)")
}

for (base, scale) in variants {
    let pixels = base * scale
    guard let image = IconRenderer.render(pixelSize: pixels) else {
        fail("render failed at \(pixels)px")
    }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: base, height: base)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fail("PNG encode failed at \(pixels)px")
    }
    let suffix = scale == 1 ? "" : "@2x"
    let name = "icon_\(base)x\(base)\(suffix).png"
    do {
        try png.write(to: iconset.appendingPathComponent(name))
    } catch {
        fail("could not write \(name): \(error.localizedDescription)")
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
do {
    try iconutil.run()
} catch {
    fail("could not launch iconutil: \(error.localizedDescription)")
}
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fail("iconutil exited \(iconutil.terminationStatus)")
}
print("Wrote \(output.path)")
