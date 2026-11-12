#if os(macOS)
import SwiftUI
import IRCaptureCore

// RackShelf.swift: the shelf from below at the rack bay's scale (Phase 7a, 11-12; the approved proof
// docs/design/proofs/shelf-from-below-14ptcm-proof-2026-11-11.png).
//
// The shelf above the rack, seen from 9 degrees below (it is above the eye): the shop-wood plank's front edge and dark
// underside, and three boxes standing on it, at 14 pt a cm as everything in the bay (design/render/
// ircapture_rack_layers.py shelf-plank, shelf-boxes; posted into irc-rack.json "shelf"):
//   plank   a long strip, laid across the window (copies end to end past its 240 cm)
//   jobs    bronze: CAB IR and AMP NAM, the job showing lit (k<i>-lit, -down, -litdown)
//   status  bronze: the power lamp (lamp-amber, lamp-red: filaments) and the VFD, its dots lit by the app
//   help    oxblood: HELP (k0-down)
// Each box picture is placed so the plank's front top edge in it (plankRow) falls on the strip's (frontTop): the two
// were rendered from the same camera, so the box stands on the plank. Without these pictures, the old shelf.

struct RackShelf: View {
    struct Parts {
        let kit: RackKit
        let plank: RackKit.Shelf.Plank
        let jobs: RackKit.Shelf.Box
        let status: RackKit.Shelf.Box
        let help: RackKit.Shelf.Box
    }
    /// The boxes' faces' top under the window's top (pt): clear of the traffic lights.
    static let faceTop: CGFloat = 30
    static let pad: CGFloat = 26
    /// Wall between the plank's underside and the rack's top (the plank's shadow falls there).
    static let gapBelow: CGFloat = 14

    static let parts: Parts? = {
        guard let k = RackKit.shared, let s = k.shelf, let p = s.plank, let b = s.boxes,
              let j = b["jobs"], let st = b["status"], let h = b["help"], st.vfd != nil,
              j.keys.count == 2, h.keys.count == 1 else { return nil }
        let files = [p.picture] + j.pictures + st.pictures + h.pictures
        guard files.allSatisfy({ SwellPictures.shared.cgImage($0 + ".webp") != nil }) else { return nil }
        return Parts(kit: k, plank: p, jobs: j, status: st, help: h)
    }()

    let parts: Parts
    let job: Job
    let jobsLocked: Bool
    let lamp: Lamp.Glow
    let vfdText: String
    let vfdHelp: String
    let statusLabel: String
    let setJob: (Job) -> Void
    let openHelp: () -> Void

    var plankTop: CGFloat { RackShelf.faceTop + (parts.jobs.plankRow - parts.jobs.face[1]) - parts.plank.frontTop }
    var height: CGFloat { plankTop + parts.plank.underBack + RackShelf.gapBelow }

    var body: some View {
        let kit = parts.kit
        ZStack(alignment: .topLeading) {
            FrameStrip(name: parts.plank.picture, height: parts.plank.size[1], pxPerPoint: kit.pxPerPoint)
                .offset(y: plankTop)
            HStack(alignment: .top, spacing: 0) {
                ShelfBoxPicture(kit: kit, box: parts.jobs) {
                    ForEach(Array(parts.jobs.keys.enumerated()), id: \.offset) { i, k in
                        let j: Job = k.id == "amp-nam" ? .nam : .cab
                        RackMachineKey(kit: kit, unit: parts.jobs.unit, index: i, rect: k.rect,
                                       label: j == .nam ? "Amp NAM" : "Cab IR", lit: job == j) { setJob(j) }
                            .disabled(jobsLocked)
                    }
                }
                Spacer(minLength: 12)
                ShelfBoxPicture(kit: kit, box: parts.status,
                                on: lamp == .amber ? ["lamp-amber"] : lamp == .red ? ["lamp-red"] : []) {
                    if let v = parts.status.vfd, v.cells.count == 4 {
                        VFDStatusLine(text: vfdText, on: VFDGeometry(
                            cells: CGRect(x: v.cells[0], y: v.cells[1], width: v.cells[2], height: v.cells[3]),
                            mtx: v.mtx, n: v.n, size: CGSize(width: parts.status.size[0], height: parts.status.size[1])))
                            .help(vfdHelp)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Status: \(statusLabel)")
                Spacer(minLength: 12)
                ShelfBoxPicture(kit: kit, box: parts.help) {
                    if let k = parts.help.keys.first {
                        RackMachineKey(kit: kit, unit: parts.help.unit, index: 0, rect: k.rect, label: "Help") { openHelp() }
                    }
                }
            }
            .padding(.horizontal, RackShelf.pad)
            .offset(y: RackShelf.faceTop)
        }
        .frame(height: height, alignment: .top)
    }
}

/// A shelf box: its picture laid so its front face fills the layout frame (the shadow and margins overhang), its
/// switched layers (lamps: filaments), and `content` drawn in the picture's points (the keys, the VFD's dots).
struct ShelfBoxPicture<Content: View>: View {
    let kit: RackKit
    let box: RackKit.Shelf.Box
    var on: Set<String> = []
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let f = box.face
        ZStack(alignment: .topLeading) {
            if let base = SwellPictures.shared.image(box.picture, pxPerPoint: kit.pxPerPoint) {
                Image(nsImage: base).resizable().interpolation(.high).frame(width: box.size[0], height: box.size[1])
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            ForEach(box.layers.keys.sorted().filter { !$0.hasPrefix("k") }, id: \.self) { k in
                if let l = box.layers[k], let img = SwellPictures.shared.image(l.picture, pxPerPoint: kit.pxPerPoint) {
                    let lit = on.contains(k)
                    Image(nsImage: img).resizable().interpolation(.high)
                        .frame(width: l.rect[2], height: l.rect[3])
                        .offset(x: l.rect[0], y: l.rect[1])
                        .opacity(lit ? 1 : 0)
                        .animation(reduceMotion ? nil : SwellMotion.filament(lit), value: lit)
                        .accessibilityHidden(true)
                }
            }
            content
        }
        .frame(width: box.size[0], height: box.size[1], alignment: .topLeading)
        .offset(x: -f[0], y: -f[1])
        .frame(width: f[2], height: f[3], alignment: .topLeading)
    }
}
#endif
