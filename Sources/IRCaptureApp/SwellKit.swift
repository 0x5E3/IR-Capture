// SwellKit.swift: the desktop bench's rendered workshop look, for IR Capture (SwiftUI, macOS 13).
// From desktop-bench, branch irkit (127th desktop chat, 2026-11-03). A starter, NOT compiled where it was written (no
// Swift toolchain there): expect small fixes on the first build. Read HANDOFF-desktop-to-ircapture.md first.
//
// The kit's files go in the app bundle at Contents/Resources/SwellKit/{pictures,fonts,layout.json}
// (scripts/make_app.sh: `cp -R Resources/SwellKit "$APP/Contents/Resources/"`). While developing with `swift run`,
// set SWELLKIT_DIR to the kit folder. Pictures are WebP: NSImage/ImageIO decode WebP from macOS 11, and IR Capture's
// floor is macOS 13 (Package.swift .macOS(.v13), LSMinimumSystemVersion 13.0), so no PNG copies are needed.
//
// What's here:
//   SwellKit.registerFonts()        call once at launch (IRCaptureApp.init): Barlow, Barlow Semi Condensed, B612 Mono, Nixie One
//   Font.swellLegend / swellBody / swellMono / swellNixie
//   Swell.<colour>                  the colours the bench actually uses (its CSS)
//   SwellPictures.shared.image(...) an NSImage with its 1x and @2x reps, sized in points; .sprite(...) crops a sheet cell
//   Panel9Slice                     a rendered piece laid round any size (Image.resizable(capInsets:resizingMode:))
//   KeyButtonStyle                  the shelf's illuminated pushbutton: off / lit / down / lit-and-down
//   GlassWindow                     smoked glass in a black cast bezel, amber digits on it
//   Lamp                            the shelf's jewel pilot (off / amber / red) or a coloured jewel
//   ShelfKey                        a key from a rendered legend sheet (frame-keys / audio-keys / ircapture-keys)
#if os(macOS)
import SwiftUI
import AppKit
import CoreText
import ImageIO

// ------------------------------------------------------------------ where the kit lives, and its fonts
enum SwellKit {
    static let folder: URL = {
        if let d = ProcessInfo.processInfo.environment["SWELLKIT_DIR"] { return URL(fileURLWithPath: d) }
        return (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("SwellKit")
    }()
    static var pictures: URL { folder.appendingPathComponent("pictures") }

    /// Registers the kit's TTFs for this process only (nothing is installed on the Mac). Call once, before any view.
    static func registerFonts() {
        let dir = folder.appendingPathComponent("fonts")
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            NSLog("SwellKit: no fonts folder at %@", dir.path); return
        }
        for u in urls where u.pathExtension.lowercased() == "ttf" {
            var err: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(u as CFURL, .process, &err) {
                let e = err?.takeRetainedValue()
                NSLog("SwellKit: font %@ not registered: %@", u.lastPathComponent, e.map { String(describing: $0) } ?? "?")
            }
        }
    }
}

// PostScript names of the kit's fonts (fonts/*.ttf; subsets: Latin, digits, ° µ Ω − › … and the like. Anything
// else falls back to the system font by itself).
extension Font {
    /// Engraved legends: Barlow Semi Condensed, capitals, tracked (use .textCase(.uppercase) and .tracking(size * 0.14)).
    static func swellLegend(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "BarlowSemiCondensed-Bold" : "BarlowSemiCondensed-SemiBold", size: size)
    }
    /// Running text (notes, checklists): Barlow.
    static func swellBody(_ size: CGFloat, semibold: Bool = false) -> Font {
        .custom(semibold ? "Barlow-SemiBold" : "Barlow-Regular", size: size)
    }
    /// Figures in tables and windows: B612 Mono.
    static func swellMono(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "B612Mono-Bold" : "B612Mono-Regular", size: size)
    }
    /// Only inside a rendered nixie tube's window.
    static func swellNixie(_ size: CGFloat) -> Font { .custom("NixieOne-Regular", size: size) }
}

// ------------------------------------------------------------------ the colours (taken from the bench's CSS)
extension Color {
    init(swellHex h: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255,
                  blue: Double(h & 0xFF) / 255, opacity: opacity)
    }
}

enum Swell {
    static let amber = Color(swellHex: 0xF2C46D)        // digits on glass (index.html --amber)
    static let windowInk = Color(swellHex: 0xF1C983)    // the shelf windows' lettering (frame.css --ink-win)
    static let nixie = Color(swellHex: 0xFF9A4A)        // nixie glow (--nixie)
    static let warn = Color(swellHex: 0xFF8A6A)         // a warning in words (--warn)
    static let keyLegend = Color(swellHex: 0x1D150B)    // a key's legend, unlit (rkit.css --rk-ink)
    static let keyLegendLit = Color(swellHex: 0x2A1506) // lit
    static let panelLegend = Color(swellHex: 0xE6E1D4)  // engraved light on the bronze / crinkle panels (--rk-legend)
    static let panelLabel = Color(swellHex: 0xD9D2C2)   // a control's label on a panel
    static let crinkleLegend = Color(swellHex: 0xD8D0BD) // the rack's cream lettering (audiopage.css)
    static let crinkleSub = Color(swellHex: 0x9D968A)
    static let tagInk = Color(swellHex: 0x2A2117)       // manila tag text (frame.css .fnote)
    static let tagPaper = Color(swellHex: 0xD9C69A)
    static let tagError = Color(swellHex: 0x7A1C10)
    static let wall = Color(swellHex: 0x1C1D1E)         // pegboard paint
    static let stage = Color(swellHex: 0x120F0C)        // the stage cloth
    static let glass = Color(swellHex: 0x050505)        // under the smoked glass
    static let focus = Color(swellHex: 0xFFB547)        // keyboard focus ring
}

// ------------------------------------------------------------------ pictures
/// Loads kit pictures as NSImages sized in points, with the @2x file as a second representation when there is one,
/// so AppKit picks the sharper one on a Retina screen. `pxPerPoint` is the 1x file's pixels a point (layout.json's
/// px_per_pt: 1.6 for frame-*, 2.4 for rkit-*, 4.8 for faceplate, 2.46 for audio-panel; for a rack unit pick one).
final class SwellPictures {
    static let shared = SwellPictures()
    private var cache: [String: NSImage] = [:]

    func cgImage(_ file: String) -> CGImage? {
        let url = SwellKit.pictures.appendingPathComponent(file)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// `name` without extension: "frame-win-circ" loads frame-win-circ.webp and, if present, frame-win-circ@2x.webp.
    func image(_ name: String, pxPerPoint: CGFloat) -> NSImage? {
        let key = "\(name)|\(pxPerPoint)"
        if let i = cache[key] { return i }
        guard let c1 = cgImage(name + ".webp") else { NSLog("SwellKit: missing %@.webp", name); return nil }
        let size = NSSize(width: CGFloat(c1.width) / pxPerPoint, height: CGFloat(c1.height) / pxPerPoint)
        let img = NSImage(size: size)
        let r1 = NSBitmapImageRep(cgImage: c1); r1.size = size; img.addRepresentation(r1)
        if let c2 = cgImage(name + "@2x.webp") {
            let r2 = NSBitmapImageRep(cgImage: c2); r2.size = size; img.addRepresentation(r2)
        }
        cache[key] = img
        return img
    }

    /// One cell of a sprite sheet: `rect` in the file's pixels (layout.json's rects_px / rects_px_2x, origin top left),
    /// shown at `pxPerPoint` of that file (3.2 for a frame-*@2x sheet).
    func sprite(_ file: String, rect: CGRect, pxPerPoint: CGFloat) -> NSImage? {
        let key = "\(file)|\(rect.origin.x),\(rect.origin.y),\(rect.width),\(rect.height)|\(pxPerPoint)"
        if let i = cache[key] { return i }
        guard let sheet = cgImage(file), let cell = sheet.cropping(to: rect) else { return nil }
        let size = NSSize(width: rect.width / pxPerPoint, height: rect.height / pxPerPoint)
        let img = NSImage(size: size)
        let r = NSBitmapImageRep(cgImage: cell); r.size = size; img.addRepresentation(r)
        cache[key] = img
        return img
    }
}

/// The cap insets and scales of the pieces SwellKit's views use (from layout.json; points).
enum SwellNine {
    struct Piece { let name: String; let pxPerPoint: CGFloat; let insets: EdgeInsets; let mode: Image.ResizingMode; let outset: CGFloat }
    // rkit (toolkit.py): 13 / 12 / 41 px slices at 2.4 px a point; the picture's margin (its shadow) lies outside the box
    static func key(_ state: String) -> Piece {
        Piece(name: "rkit-key-\(state)", pxPerPoint: 2.4, insets: EdgeInsets(top: 5.42, leading: 5.42, bottom: 5.42, trailing: 5.42),
              mode: .stretch, outset: 1.2)
    }
    static let window = Piece(name: "rkit-win", pxPerPoint: 2.4, insets: EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5),
                              mode: .stretch, outset: 1.2)
    // Drawn at 1.5 times the kit's density (screws two thirds the size): at the kit's own scale the corner screws
    // dominate IR Capture's smaller panels. Insets scale with it (17.08 pt at 2.4 px a pt).
    static let panel = Piece(name: "rkit-panel", pxPerPoint: 3.6, insets: EdgeInsets(top: 11.39, leading: 11.39, bottom: 11.39, trailing: 11.39),
                             mode: .tile, outset: 1.3)
    static let faceplate = Piece(name: "faceplate", pxPerPoint: 4.8, insets: EdgeInsets(top: 40, leading: 40, bottom: 40, trailing: 40),
                                 mode: .tile, outset: 0)
    // Twice the kit's density, for the same reason (26 pt insets at 2.46 px a pt).
    static let crinkle = Piece(name: "audio-panel", pxPerPoint: 128.0 / 26.0, insets: EdgeInsets(top: 13, leading: 13, bottom: 13, trailing: 13),
                               mode: .stretch, outset: 0)
    // frame (frame_camera.py): ref px = points, 1.6 px a point at 1x
    static let shelfBox = Piece(name: "frame-box-keys", pxPerPoint: 1.6, insets: EdgeInsets(top: 10, leading: 26, bottom: 8, trailing: 76),
                                mode: .tile, outset: 0)
    static let card = Piece(name: "frame-card", pxPerPoint: 1.6, insets: EdgeInsets(top: 34, leading: 30, bottom: 34, trailing: 30),
                            mode: .tile, outset: 0)
    static let cabinet = Piece(name: "frame-cabinet", pxPerPoint: 1.6, insets: EdgeInsets(top: 10, leading: 37, bottom: 22, trailing: 25),
                               mode: .tile, outset: 0)
    static let selectorGlass = Piece(name: "frame-win-circ", pxPerPoint: 1.6, insets: EdgeInsets(top: 0, leading: 31, bottom: 0, trailing: 31),
                                     mode: .tile, outset: 0)
}

/// A rendered piece laid round whatever size its parent gives it.
struct Panel9Slice: View {
    let piece: SwellNine.Piece
    var body: some View {
        if let img = SwellPictures.shared.image(piece.name, pxPerPoint: piece.pxPerPoint) {
            Image(nsImage: img)
                .resizable(capInsets: piece.insets, resizingMode: piece.mode)
                .padding(-piece.outset)          // the render's shadow margin falls outside the box, as border-image-outset
                .accessibilityHidden(true)
        } else {
            Color.clear
        }
    }
}

extension View {
    /// Puts the view on a rendered panel (bronze hammertone by default), with room for the screws in the corners.
    func swellPanel(_ piece: SwellNine.Piece = SwellNine.panel, padding: CGFloat = 12.5) -> some View {
        self.padding(padding).background(Panel9Slice(piece: piece))
    }
}

// ------------------------------------------------------------------ the illuminated key
/// The shelf's pushbutton: ivory resin cap in a black cast bezel, the lamp behind it lit when `lit` (a selected step,
/// a mode that's on, a running check). Pressed, the cap sits down in its bezel. The legend is the button's own label.
///   Button("Capture") { ... }.buttonStyle(KeyButtonStyle(lit: m.busy != nil))
struct KeyButtonStyle: ButtonStyle {
    var lit = false
    var size: CGFloat = 12
    /// A large key (Capture, Record): more cap round the legend.
    var big = false
    func makeBody(configuration: Configuration) -> some View {
        KeyFace(configuration: configuration, lit: lit, size: big ? max(size, 15) : size, big: big)
    }
    private struct KeyFace: View {
        let configuration: ButtonStyleConfiguration
        let lit: Bool
        let size: CGFloat
        let big: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hover = false
        var body: some View {
            let down = configuration.isPressed && isEnabled
            let state = lit ? (down ? "litdown" : "lit") : (down ? "down" : "off")
            configuration.label
                .font(.swellLegend(size))
                .textCase(.uppercase)
                .tracking(size * 0.05)
                .foregroundColor(lit ? Swell.keyLegendLit : Swell.keyLegend)
                .shadow(color: lit ? Color(swellHex: 0xFFD296, opacity: 0.6) : Color(swellHex: 0xFFF4DC, opacity: 0.35), radius: 0, x: 0, y: lit ? 0 : 1)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, big ? 24 : 12)
                .padding(.vertical, big ? 11 : 6)
                .frame(minWidth: big ? 120 : 44, minHeight: big ? 40 : 26)
                .offset(y: down ? 1 : 0)
                .background(Panel9Slice(piece: SwellNine.key(state)))
                .brightness(hover && isEnabled && !down ? 0.04 : 0)
                .opacity(isEnabled ? 1 : 0.5)
                .saturation(isEnabled ? 1 : 0.6)
                .contentShape(Rectangle())
                .onHover { hover = $0 }
                .accessibilityAddTraits(lit ? .isSelected : [])
        }
    }
}

// ------------------------------------------------------------------ the value window
/// Smoked glass in a black cast bezel, the figures amber on it: a capture name, a level, the save folder.
///   GlassWindow { Text(String(format: "%.1f dBFS", peak)) }
struct GlassWindow<Content: View>: View {
    var size: CGFloat = 14
    @ViewBuilder var content: Content
    var body: some View {
        content
            .font(.swellLegend(size))
            .foregroundColor(Swell.amber)
            .shadow(color: Swell.amber.opacity(0.35), radius: 1.5)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                ZStack {
                    Swell.glass
                    if let g = SwellPictures.shared.image("rkit-glass", pxPerPoint: 2.4) {
                        Image(nsImage: g).resizable()
                    }
                }
                .padding(3))
            .overlay(Panel9Slice(piece: SwellNine.window).allowsHitTesting(false))   // its middle is transparent
    }
}

// ------------------------------------------------------------------ lamps
/// The shelf's jewel pilot (frame-lamp@2x: off, amber, red; cells 186 px at 3.2 px a point = 58 pt with its shadow;
/// the jewel itself is about 18 pt across). Dark while all is well, amber while busy, red on an error, as on the bench.
struct Lamp: View {
    enum Glow: Int { case off = 0, amber = 1, red = 2 }
    var state: Glow
    /// The cell's size in points, shadow included (58 at the shelf's own scale).
    var size: CGFloat = 58
    var body: some View {
        if let img = SwellPictures.shared.sprite("frame-lamp@2x.webp", rect: CGRect(x: 186 * state.rawValue, y: 0, width: 186, height: 186), pxPerPoint: 3.2) {
            Image(nsImage: img).resizable().interpolation(.high).frame(width: size, height: size)
                .shadow(color: state == .amber ? Color(red: 1, green: 0.59, blue: 0.2, opacity: 0.55)
                              : state == .red ? Color(red: 1, green: 0.27, blue: 0.16, opacity: 0.55) : .clear, radius: 5)
                .accessibilityLabel(state == .off ? "Ready" : state == .amber ? "Working" : "Error")
        }
    }
}

/// A coloured jewel lamp (rlamp-jewel<colour>-<on|off>.webp, 120 px and @2x 240 px); draw it at the size you need.
struct JewelLamp: View {
    var colour = "amber"          // amber, red, green, clear, blue
    var on: Bool
    var diameter: CGFloat = 24
    var body: some View {
        // The picture is the jewel in its chrome ring with a shadow margin round it: the jewel's own size is
        // `diameter`, so the picture is drawn 1.7 times larger and overhangs its frame.
        if let img = SwellPictures.shared.image("rlamp-jewel\(colour)-\(on ? "on" : "off")", pxPerPoint: 120 / (diameter * 1.7)) {
            Image(nsImage: img).frame(width: diameter, height: diameter).accessibilityHidden(true)
        }
    }
}

// ------------------------------------------------------------------ a key with a rendered legend
/// One key from a legend sheet: frame-keys@2x.webp (the bench's own names), audio-keys.webp, or ircapture-keys.webp
/// once rendered (design/render/jobs-imac-irkit.json). Cells and rows from layout.json; rows are off, lit, down, litdown.
/// The page's own Button keeps the action and the accessibility label; this only dresses it.
struct ShelfKey: View {
    let sheet: String            // e.g. "audio-keys.webp"
    let names: [String]          // layout.json's names, in order
    let cell: CGSize             // cell_px (or cell_px_2x for a frame @2x sheet)
    let pxPerPoint: CGFloat      // 1 / ref_px_per_px (audio-keys: about 2.4; frame-keys@2x: 3.2)
    let legend: String
    var lit = false
    var action: () -> Void
    @GestureState private var down = false
    var body: some View {
        let col = CGFloat(names.firstIndex(of: legend) ?? 0)
        let row: CGFloat = lit ? (down ? 3 : 1) : (down ? 2 : 0)
        let rect = CGRect(x: col * cell.width, y: row * cell.height, width: cell.width, height: cell.height)
        Button(action: action) {
            if let img = SwellPictures.shared.sprite(sheet, rect: rect, pxPerPoint: pxPerPoint) { Image(nsImage: img) }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(DragGesture(minimumDistance: 0).updating($down) { _, s, _ in s = true })
        .accessibilityLabel(legend.capitalized)
        .accessibilityAddTraits(lit ? .isSelected : [])
    }
}
#endif
