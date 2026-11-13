#if os(macOS)
import SwiftUI
import AppKit
import CoreText
import IRCaptureCore

// RackRoutes.swift: the Cab IR rack's other two routes as bays of their own (Phase 7a; the fifth proof, approved 11-13:
// "looks good ... Looks great, very visually appealing with great ideas"; the toggles as Lowell picked, C). In place of
// CabImportSteps and the 640 x 620 ReexportSheet (design/render/ircapture_rack_layers.py):
//
//   The DAW route (IMPORT DAW on the connect unit):
//     step-daw   1U  TEST SIGNAL, RECORD IN DAW, MAKE IRS, RESULTS
//     chart-daw  6U  DWG 2 (the computer on the interface's USB) and the card IN THE DAW
//     signal     3U  RATE kHz and LEVEL dBFS rotaries, SWEEPS, LENGTH, GAP, WARM-UP; SAVE SIGNAL, LOAD SIGNAL, RECORD HERE
//     tracks     4U  the TRACK SHEET typed by the app, a side toggle a line (MIC left, OFF centre, REF right), a hole
//                    plug on a line with no track; ADD FILES, CLEAR; files may be dropped on it. One unit every 8 tracks.
//     files, formats  as in the record route
//     go-daw     1U  FROM THE TRACKS, MAKE IRS (lit while the files are made)
//   The re-export (RE-EXPORT OLD on the files unit, RE-EXPORT on the results unit):
//     step-rex   1U  PAST CAPTURE, FILES, RE-EXPORT, RESULTS
//     files-rex  4U  the past capture's card (typed, stamped RE-EXPORT), the five file keys, PAST CAPTURE CHOOSE
//     formats    as in the record route
//     go-rex     1U  FROM THE RAW TAKE, CANCEL, RE-EXPORT (lit while the files are made)
// Both routes end in the results unit and the plotter, as the record route does. Their status lines are on the shelf's
// VFD (Shelf.cabLine); a fault in these two routes is shown in a message window (they have no pre-flight form). The
// explanations the old panels carried are in Help › Quick start, "The DAW route" and "Re-export".

extension RackKit {
    /// The DAW route's test signal: the rotaries, the thumbwheels (groups sweeps, length, gap, warm-up), the keys.
    struct Signal: Decodable {
        let wheels: Wheels
        let selectors: [Selector]
        let keys: [KeyRect]
    }
    /// The track sheet: its printed form (sheet cm, entries by their baselines), the side toggles' centres, the MIC / OFF
    /// / REF columns' x and width, a line's pitch (pt in the base picture).
    struct Tracks: Decodable {
        struct Col: Decodable { let key: String; let label: String; let x: CGFloat }
        struct Form: Decodable {
            let w: CGFloat; let h: CGFloat; let margin: CGFloat; let typedCm: CGFloat; let advance: CGFloat
            let headY: CGFloat; let rows: Int; let pitch: CGFloat
            let centres: [CGFloat]; let rules: [CGFloat]; let baselines: [CGFloat]
            let cols: [Col]; let right: CGFloat
            func col(_ k: String) -> CGFloat? { cols.first { $0.key == k }?.x }
        }
        let sheet: [CGFloat]
        let form: Form
        let keys: [KeyRect]
        let toggles: [[CGFloat]]
        let columns: [CGFloat]
        let column: CGFloat
        let pitch: CGFloat
    }
    /// A route's last unit: its keys.
    struct Go: Decodable { let keys: [KeyRect] }
}

// ------------------------------------------------------------------ the bays
/// The DAW route: play the test signal from a DAW, record the mics there, make the IRs from the exported files.
struct CabDAWBay: View {
    @EnvironmentObject var m: AppModel
    static var available: Bool { RackSignalUnit.available && RackTracksBay.available && RackGoUnit.available("daw") }
    var signalDone: Bool {
        !m.logicChannels.isEmpty || (m.signalMessage.map { $0.hasPrefix("Saved") || $0.hasPrefix("Loaded") } ?? false)
    }
    var body: some View {
        VStack(spacing: 0) {
            RackStepStrip(steps: [("Test signal", signalDone), ("Record in DAW", !m.logicChannels.isEmpty),
                                  ("Make IRs", m.result != nil), ("Results", m.result != nil)], unit: "step-daw")
                .id("baytop")
            RackChartUnit(daw: true)
            RackSignalUnit().id("signal")
            RackTracksBay().id("tracks")
            if RackFilesUnit.available { RackFilesUnit().id("files") } else { CabFilesStep() }
            if RackFormatsUnit.available { RackFormatsUnit() } else { AdvancedOutput().onPanel() }
            RackGoUnit(kind: "daw").id("machine")
        }
        .faultMessage([("The IRs were not made", $m.errorText), ("A file was not added", $m.logicMessage),
                       ("The test signal", Binding(get: { m.signalMessage.flatMap { $0.hasPrefix("Saved") || $0.hasPrefix("Loaded") ? nil : $0 } },
                                                   set: { if $0 == nil { m.signalMessage = nil } }))])
    }
}

/// The re-export: the files made again from a past capture's raw take, with no new recording.
struct CabReexportBay: View {
    @EnvironmentObject var m: AppModel
    static var available: Bool { RackFilesRexUnit.available && RackGoUnit.available("rex") }
    var body: some View {
        VStack(spacing: 0) {
            RackStepStrip(steps: [("Past capture", m.reexportFolder != nil), ("Files", m.outputProblem == nil),
                                  ("Re-export", false), ("Results", false)], unit: "step-rex")
                .id("baytop")
            RackFilesRexUnit().id("files")
            if RackFormatsUnit.available { RackFormatsUnit() } else { AdvancedOutput().onPanel() }
            RackGoUnit(kind: "rex").id("machine")
        }
        .faultMessage([("The files were not re-exported", $m.reexportMessage)])
    }
}

extension View {
    /// A fault in the DAW route or the re-export, in a message window (these routes have no pre-flight form to type
    /// it on): the first of `faults` that is set; closing the window clears it. One alert for them all (a view takes
    /// only one).
    func faultMessage(_ faults: [(String, Binding<String?>)]) -> some View {
        let first = faults.first { $0.1.wrappedValue != nil }
        return alert(first?.0 ?? "", isPresented: Binding(get: { first != nil }, set: { if !$0 { first?.1.wrappedValue = nil } })) {
            Button("OK", role: .cancel) { first?.1.wrappedValue = nil }
        } message: {
            Text(first?.1.wrappedValue ?? "")
        }
    }
}

// ------------------------------------------------------------------ the DAW drawing (6U)
extension RackChartUnit {
    /// DWG 2 and the card IN THE DAW (as typed in ircapture_rack.daw_card), for VoiceOver.
    static let dawCard = [
        "Project at the test signal's RATE. The sweep WAV on a track at bar 1.",
        "That track only to the output to the amp. Monitors off.",
        "A track for each mic, named after it. The reference track: Ref. No plug-ins.",
        "Play it. Each preamp to about -6 dBFS. No clip.",
        "Record one full pass.",
        "Export all tracks as WAV at the project rate. Normalize off.",
    ]
}

// ------------------------------------------------------------------ the test signal (3U)
struct RackSignalUnit: View {
    @EnvironmentObject var m: AppModel
    static var available: Bool { RackKit.ready("signal")?.1.signal != nil }
    static let rates = CoreAudioHelper.captureRates
    static let levels: [Double] = [-6, -12, -18, -24]

    var body: some View {
        if let r = RackKit.ready("signal"), let s = r.1.signal {
            let kit = r.0, u = r.1
            let settings = RackSweepUnit.wheelSettings(s.wheels, m)
            let ratePos = Self.rates.firstIndex(of: m.logicRate) ?? Self.rates.count - 1
            let levelPos = Self.levels.firstIndex(of: m.level) ?? 1
            let sels = s.selectors
            let on = Set([sels.count > 0 ? RackSelectorControl.layer(0, sels[0], ratePos) : nil,
                          sels.count > 1 ? RackSelectorControl.layer(1, sels[1], levelPos) : nil].compactMap { $0 })
            RackSetupFrame(kit: kit, unit: u, on: on) {
                RackWheelFigures(kit: kit, wheels: s.wheels, figures: RackWheelButtons.figures(s.wheels, settings))
            } controls: {
                if sels.count > 1 {
                    RackSelectorControl(sel: sels[0], names: Self.rates.map { "\(rateTag($0).dropLast()) kHz" }, pos: ratePos,
                                        set: { m.logicRate = Self.rates[$0] }, label: "Test signal rate (the DAW project's rate)")
                    RackSelectorControl(sel: sels[1], names: Self.levels.map { "\(Int($0)) dBFS" }, pos: levelPos,
                                        set: { m.level = Self.levels[$0] }, label: "Sweep level")
                }
                RackWheelButtons(kit: kit, unit: u, wheels: s.wheels, settings: settings)
                ForEach(Array(s.keys.enumerated()), id: \.offset) { i, k in
                    switch k.id {
                    case "save-signal":
                        RackPressButton(kit: kit, unit: u, rect: k.rect, downLayer: "k\(i)-down", label: "Save test signal",
                                        help: "Save the sweeps as a WAV file for playback from the DAW, with these settings") { m.saveTestSignal() }
                    case "load-signal":
                        RackPressButton(kit: kit, unit: u, rect: k.rect, downLayer: "k\(i)-down", label: "Load settings from a test signal",
                                        help: "Set these controls from the .json file saved with a test signal") { m.loadSignalSettings() }
                    default:
                        RackPressButton(kit: kit, unit: u, rect: k.rect, downLayer: "k\(i)-down", label: "Record here",
                                        help: "Back to recording through the interface with the app") { m.cabImport = false }
                            .disabled(m.busy != nil)
                    }
                }
            }
        }
    }
}

// ------------------------------------------------------------------ the track sheet (4U)
struct RackTracksBay: View {
    @EnvironmentObject var m: AppModel
    @State private var dropping = false
    static var available: Bool { RackKit.ready("tracks")?.1.tracks != nil }

    var body: some View {
        if let r = RackKit.ready("tracks"), let t = r.1.tracks {
            let n = max(1, t.form.rows)
            let units = max(1, (m.logicChannels.count + n - 1) / n)
            VStack(spacing: 0) {
                ForEach(0..<units, id: \.self) { b in
                    RackTracksUnit(kit: r.0, unit: r.1, tracks: t, bank: b)
                }
            }
            // files dropped anywhere on the units are added (the old drop plate)
            .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
                for p in providers {
                    _ = p.loadObject(ofClass: URL.self) { url, _ in
                        if let url { DispatchQueue.main.async { m.addLogicFiles([url]) } }
                    }
                }
                return true
            }
            .overlay {
                // while files are held over it, the units' edge warms: a drop is taken here
                RoundedRectangle(cornerRadius: 3).strokeBorder(Swell.amber.opacity(dropping ? 0.7 : 0), lineWidth: 2)
                    .allowsHitTesting(false)
            }
            .disabled(m.busy != nil)
        }
    }
}

/// One track sheet: tracks bank * 8 + 1 to bank * 8 + 8. A click on a line's MIC, OFF or REF throws its toggle there;
/// a click on a mic's name types there; a line's menu (right-click) removes its file.
struct RackTracksUnit: View {
    @EnvironmentObject var m: AppModel
    let kit: RackKit
    let unit: RackKit.Unit
    let tracks: RackKit.Tracks
    let bank: Int
    @State private var editing: UUID?
    @FocusState private var focus: UUID?

    var rows: [LogicChannel] {
        let n = tracks.form.rows, all = m.logicChannels
        let a = min(bank * n, all.count), b = min(a + n, all.count)
        return Array(all[a..<b])
    }

    var body: some View {
        let rs = rows
        RackSetupFrame(kit: kit, unit: unit, on: lit(rs)) {
            TrackSheetInk(form: tracks.form, sheet: tracks.sheet, first: bank * tracks.form.rows + 1, rows: rs, hide: editing)
        } controls: {
            ForEach(Array(rs.enumerated()), id: \.element.id) { i, c in line(i, c) }
            ForEach(Array(tracks.keys.enumerated()), id: \.offset) { i, k in
                if k.id == "r-add-files" {
                    RackPressButton(kit: kit, unit: unit, rect: k.rect, downLayer: "k\(i)-down", label: "Add files",
                                    help: "Add the WAV files exported from the DAW (or drop them on the track sheet). A file named after the sweep is set to OFF.") { m.chooseLogicFiles() }
                } else {
                    RackPressButton(kit: kit, unit: unit, rect: k.rect, downLayer: "k\(i)-down", label: "Clear the files",
                                    help: "Take every file off the track sheet") { m.logicChannels = []; m.logicMessage = nil }
                        .disabled(m.logicChannels.isEmpty)
                }
            }
        }
        .onChange(of: focus) { f in if f == nil { editing = nil } }
    }

    /// Each line's toggle thrown as its track's use; a hole plug where the line has no track.
    func lit(_ rs: [LogicChannel]) -> Set<String> {
        var on = Set<String>()
        for i in 0..<tracks.form.rows {
            guard i < rs.count else { on.insert("p\(i)"); continue }
            switch rs[i].role {
            case .mic: on.insert("t\(i)-mic")
            case .ref: on.insert("t\(i)-ref")
            case .off: break
            }
        }
        return on
    }

    @ViewBuilder func line(_ i: Int, _ c: LogicChannel) -> some View {
        let F = tracks.form, sr = tracks.sheet, k = sr[2] / F.w
        let order: [Role] = [.mic, .off, .ref]
        let lineH = tracks.pitch
        if i < tracks.toggles.count {
            let tc = tracks.toggles[i]
            // the toggle: three columns under MIC, OFF, REF
            HStack(spacing: 0) {
                ForEach(order, id: \.self) { r in
                    Button { m.setLogicRole(r, for: c.id) } label: { Color.clear.frame(width: tracks.column, height: lineH) }
                        .buttonStyle(.plain).contentShape(Rectangle())
                        .help("Track \(bank * F.rows + i + 1): \(r == .off ? "Off (not used)" : r.label)")
                }
            }
            .offset(x: (tracks.columns.first ?? tc[0]) - tracks.column / 2, y: tc[1] - lineH / 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Track \(bank * F.rows + i + 1), \(c.label)")
            .accessibilityValue(c.role.label)
            .accessibilityAdjustableAction { d in
                let j = order.firstIndex(of: c.role) ?? 1
                switch d {
                case .increment: if j > 0 { m.setLogicRole(order[j - 1], for: c.id) }
                case .decrement: if j < 2 { m.setLogicRole(order[j + 1], for: c.id) }
                @unknown default: break
                }
            }
        }
        // the line on the sheet: its file's details as a tooltip, the menu to remove it; the mic's name to type
        if i < F.centres.count, let xn = F.col("name"), let xk = F.col("khz") {
            let top = sr[1] + (F.centres[i] - F.pitch / 2) * k
            let nameX0 = sr[0] + (xn - 0.1) * k, nameW = (xk - xn - 0.2) * k
            Color.clear.contentShape(Rectangle())
                .frame(width: (xn - F.margin - 0.15) * k, height: F.pitch * k)
                .offset(x: sr[0] + F.margin * k, y: top)
                .help("\(c.label): \(c.meta)")
                .contextMenu { Button("Remove \(c.url.lastPathComponent)") { m.removeLogicFile(c.url) } }
                .accessibilityHidden(true)
            if c.role == .mic {
                if editing == c.id {
                    TextField("", text: nameBinding(c.id))
                        .textFieldStyle(.plain)
                        .font(.custom("CourierPrime-Regular", size: F.typedCm * k))
                        .foregroundColor(Color(.sRGB, red: 34 / 255, green: 32 / 255, blue: 44 / 255))
                        .focused($focus, equals: c.id)
                        .onSubmit { focus = nil }
                        .frame(width: nameW, alignment: .leading)
                        .offset(x: nameX0 + 0.1 * k - 1, y: sr[1] + (F.baselines[i] - 0.78 * F.typedCm) * k - 2)
                        .accessibilityLabel("Mic name, track \(bank * F.rows + i + 1)")
                } else {
                    Button { editing = c.id; DispatchQueue.main.async { focus = c.id } } label: {
                        Color.clear.frame(width: nameW, height: F.pitch * k)
                    }
                    .buttonStyle(.plain).contentShape(Rectangle())
                    .help("The mic's name, used in the file names. Click to type. Right-click for common names.")
                    .contextMenu { ForEach(commonMicNames, id: \.self) { n in Button(n) { nameBinding(c.id).wrappedValue = n } } }
                    .offset(x: nameX0, y: top)
                    .accessibilityLabel("Mic name, track \(bank * F.rows + i + 1)")
                    .accessibilityValue(c.name)
                    .accessibilityHint("Types on the track sheet")
                }
            }
        }
    }

    func nameBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { m.logicChannels.first { $0.id == id }?.name ?? "" },
                set: { v in if let j = m.logicChannels.firstIndex(where: { $0.id == id }) { m.logicChannels[j].name = v } })
    }
}

/// The track sheet's ink: the track numbers printed (the form's oxblood), each track typed: its file, the mic's name,
/// its rate, bits and length. Multiplied over the printed form.
struct TrackSheetInk: View {
    let form: RackKit.Tracks.Form
    let sheet: [CGFloat]
    let first: Int
    let rows: [LogicChannel]
    let hide: UUID?
    var body: some View {
        Canvas { ctx, _ in ctx.withCGContext { cg in draw(cg) } }
            .frame(width: sheet[2], height: sheet[3])
            .offset(x: sheet[0], y: sheet[1])
            .blendMode(.multiply)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
    private var k: CGFloat { sheet[2] / form.w }
    func draw(_ cg: CGContext) {
        let F = form, pt = F.typedCm * k, adv = F.advance * pt
        let font = CTFontCreateWithName("CourierPrime-Regular" as CFString, pt, nil)
        let num = CTFontCreateWithName("BarlowSemiCondensed-Bold" as CFString, 0.56 * k, nil)
        let ox = CGColor(srgbRed: 104 / 255, green: 30 / 255, blue: 24 / 255, alpha: 1)
        cg.textMatrix = .identity
        let advCm = F.advance * F.typedCm
        func chars(_ a: String, _ b: String) -> Int {
            guard let x0 = F.col(a) else { return 1 }
            let x1 = F.col(b) ?? F.right
            return max(1, Int((x1 - x0 - 0.3) / advCm))
        }
        for i in 0..<min(F.rows, F.centres.count) {
            // the track number, printed (as the form's headings)
            let attr = NSAttributedString(string: "\(first + i)", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): num,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): ox])
            let lineRef = CTLineCreateWithAttributedString(attr)
            cg.saveGState()
            cg.translateBy(x: ((F.col("trk") ?? F.margin) + 0.35) * k, y: (F.centres[i] + 0.2) * k)
            cg.scaleBy(x: 1, y: -1)
            cg.textPosition = .zero
            CTLineDraw(lineRef, cg)
            cg.restoreGState()
            cg.textMatrix = .identity
            guard i < rows.count else { continue }
            let c = rows[i], b = F.baselines[i] * k
            let secs = String(format: "%.1f", Double(c.frames) / Double(max(1, c.fs)))
            let fields: [(String, String, String?)] = [
                ("file", TakeSheetInk.fit(c.label, chars("file", "name")), nil),
                ("name", c.role == .mic && c.id != hide ? TakeSheetInk.fit(c.name, chars("name", "khz")) : "", nil),
                ("khz", String(rateTag(c.fs).dropLast()), nil), ("bits", "\(c.bits)", nil), ("seconds", secs, nil)]
            var rng = InkRandom(s: TakeSheet.hash(c.url.path + "|\(c.channel)|" + c.name))
            for (key, text, _) in fields where !text.isEmpty {
                guard let x = F.col(key) else { continue }
                PaperInk.type(cg, font, text, x: (x + 0.1) * k, baseline: b, adv: adv, k: k, rng: &rng)
            }
        }
    }
}

// ------------------------------------------------------------------ the route's last key (1U)
struct RackGoUnit: View {
    @EnvironmentObject var m: AppModel
    let kind: String                       // "daw" or "rex"
    static func available(_ kind: String) -> Bool { RackKit.ready("go-" + kind)?.1.go != nil }

    var body: some View {
        if let r = RackKit.ready("go-" + kind), let g = r.1.go {
            let kit = r.0, u = r.1
            let making = m.busy != nil
            let on = Set(g.keys.indices.compactMap { i -> String? in
                ["r-make-irs", "reexport"].contains(g.keys[i].id) && making ? "k\(i)-lit" : nil
            })
            RackSetupFrame(kit: kit, unit: u, on: on) {
                EmptyView()
            } controls: {
                ForEach(Array(g.keys.enumerated()), id: \.offset) { i, k in
                    let lit = on.contains("k\(i)-lit")
                    switch k.id {
                    case "r-make-irs":
                        RackPressButton(kit: kit, unit: u, rect: k.rect, downLayer: "k\(i)-\(lit ? "litdown" : "down")", label: "Make IRs",
                                        help: m.logicProblem ?? "Make the IRs from the tracks, with the files and options above") { m.processLogic() }
                            .disabled(making || m.logicProblem != nil)
                    case "reexport":
                        RackPressButton(kit: kit, unit: u, rect: k.rect, downLayer: "k\(i)-\(lit ? "litdown" : "down")", label: "Re-export",
                                        help: m.outputProblem ?? "Make the files again from the raw take with the settings above. The old files go to the Trash.") {
                            if let f = m.reexportFolder { m.reexport(f) }
                        }
                        .disabled(making || m.outputProblem != nil || m.reexportFolder == nil)
                        .keyboardShortcut(.defaultAction)
                    default:
                        RackPressButton(kit: kit, unit: u, rect: k.rect, downLayer: "k\(i)-down", label: "Cancel",
                                        help: "Leave the re-export. Nothing is changed.") { m.reexportFolder = nil }
                            .disabled(making)
                            .keyboardShortcut(.cancelAction)
                    }
                }
            }
        }
    }
}

// ------------------------------------------------------------------ the past capture's card (4U)
struct RackFilesRexUnit: View {
    @EnvironmentObject var m: AppModel
    static var available: Bool { RackKit.ready("files-rex")?.1.files?.stamp != nil }

    var body: some View {
        if let r = RackKit.ready("files-rex"), let f = r.1.files, let st = f.stamp {
            let kit = r.0, u = r.1
            let folder = m.reexportFolder
            let notes = folder.map(PastCapture.notes) ?? ""
            let on = Set(f.keys.indices.compactMap { i -> String? in
                guard let t = RackFilesUnit.targetOf[f.keys[i].id] else { return nil }
                return m.targets.contains(t) ? "k\(i)-lit" : nil
            })
            RackSetupFrame(kit: kit, unit: u, on: on) {
                CaptureCardInk(form: f.form, sheet: f.sheet, name: folder?.lastPathComponent ?? "", notes: notes,
                               folder: folder.map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") } ?? "", hide: nil)
                if folder != nil { stamp(f, st) }
            } controls: {
                let s = f.sheet
                Color.clear.contentShape(Rectangle()).frame(width: s[2], height: s[3]).offset(x: s[0], y: s[1])
                    .help(folder.map { "\($0.path)\n\(notes)" } ?? "")
                    .accessibilityElement().accessibilityLabel("Past capture")
                    .accessibilityValue(folder.map { "\($0.lastPathComponent). \(notes)" } ?? "None chosen")
                ForEach(Array(f.keys.enumerated()), id: \.offset) { i, k in
                    if let t = RackFilesUnit.targetOf[k.id] {
                        let lit = m.targets.contains(t)
                        RackPressButton(kit: kit, unit: u, rect: k.rect, downLayer: "k\(i)-\(lit ? "litdown" : "down")",
                                        label: RackFilesUnit.spokenOf[k.id] ?? k.id,
                                        help: (ExportTarget.destinations + ExportTarget.extras).first { $0.id == t }?.detail ?? "") {
                            if lit { m.targets.remove(t) } else { m.targets.insert(t) }
                        }
                        .accessibilityAddTraits(lit ? .isSelected : [])
                    } else {
                        RackPressButton(kit: kit, unit: u, rect: k.rect, downLayer: "k\(i)-down", label: "Choose a past capture",
                                        help: "Choose another capture folder (it holds a Raw take folder)") { m.chooseReexportFolder() }
                    }
                }
            }
            .disabled(m.busy != nil)
        }
    }

    /// RE-EXPORT stamped on the card in red: its top right corner where the form says, turned as the proof's.
    @ViewBuilder func stamp(_ f: RackKit.Files, _ st: RackKit.Files.Stamp) -> some View {
        if let img = SwellPictures.shared.image(st.picture, pxPerPoint: st.pxPerPoint) {
            let s = f.sheet, k = s[2] / f.form.w
            let cx = s[0] + st.right * k - st.size[0] / 2, cy = s[1] + st.top * k + st.size[1] / 2
            Image(nsImage: img).resizable().interpolation(.high)
                .frame(width: st.size[0], height: st.size[1])
                .rotationEffect(.degrees(-st.turn))
                .offset(x: cx - st.size[0] / 2, y: cy - st.size[1] / 2)
                .blendMode(.multiply)
                .allowsHitTesting(false)
        }
    }
}

/// A past capture's notes, from its raw take's take.json (read once a folder).
enum PastCapture {
    private static var cache: [String: String] = [:]
    static func notes(_ folder: URL) -> String {
        if let n = cache[folder.path] { return n }
        let u = RawTake.folder(folder).appendingPathComponent("take.json")
        let n = ((try? JSONSerialization.jsonObject(with: Data(contentsOf: u))) as? [String: Any])?["notes"] as? String ?? ""
        cache[folder.path] = n
        return n
    }
}
#endif
