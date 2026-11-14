#if os(macOS)
import SwiftUI
import IRCaptureCore

// RackPatch.swift: the patch unit (2U, Phase 7a; the first proof's unit, approved).
//
// The interface's inputs, eight to a unit: a three-way bat toggle each, MIC thrown up, OFF level, REF thrown down, with
// the input's number and MIC / OFF / REF engraved beside it (design/render/ircapture_rack_layers.py `patch`). The base
// is inputs 1 to 8 with every toggle level; the layers throw a toggle (`t<i>-mic`, `t<i>-ref`), put a hole plug in a
// slot the interface has no input for (`p<i>`), and engrave the slot's number for the next banks of eight (`n<i>-b<k>`:
// inputs 9 to 16, 17 to 24, 25 to 32). One unit for every eight inputs; more than 32 inputs keep the old inputs grid.
//
// A click on a toggle's MIC, OFF or REF row throws it there. Only one input is the reference: throwing a second to REF
// returns the first to OFF (AppModel.setRole). The mic names are written on the meter bridge's scribble strips.

extension RackKit {
    struct Patch: Decodable {
        let n: Int                       // toggles in a unit
        let banks: Int                   // numbered banks of n (units)
        let toggles: [[CGFloat]]         // each toggle's centre in the base picture (pt)
        let rows: [String: CGFloat]      // mic, off, ref: each legend row's centre (y, pt)
        let column: CGFloat              // one toggle's column width (pt)
    }
}

struct RackPatchBay: View {
    @EnvironmentObject var m: AppModel

    static var available: Bool { RackKit.ready("patch")?.1.patch != nil }
    /// Whether the patch units can hold this many inputs.
    static func holds(_ count: Int) -> Bool {
        guard let p = RackKit.ready("patch")?.1.patch else { return false }
        return count > 0 && count <= p.n * p.banks
    }

    var body: some View {
        if let r = RackKit.ready("patch"), let p = r.1.patch, let dev = m.device, Self.holds(dev.inputChannels) {
            let count = dev.inputChannels
            VStack(spacing: 0) {
                ForEach(0..<((count + p.n - 1) / p.n), id: \.self) { b in
                    RackPatchUnit(kit: r.0, unit: r.1, patch: p, bank: b, count: count,
                                  role: { ch in m.inputs.first { $0.id == ch }?.role ?? .off },
                                  set: { role, ch in m.setRole(role, for: ch) },
                                  locked: m.audioActive)
                }
            }
            .help(m.audioActive ? "Stop the level check or recording to change the inputs" : "")
        }
    }
}

/// One patch unit: bank `bank` of the interface's `count` inputs.
struct RackPatchUnit: View {
    let kit: RackKit
    let unit: RackKit.Unit
    let patch: RackKit.Patch
    let bank: Int
    let count: Int
    let role: (Int) -> Role
    let set: (Role, Int) -> Void
    var locked = false

    var body: some View {
        let slots = Array(0..<patch.n)
        let on = lit(slots)
        // the picture is hidden from VoiceOver; the toggles are laid over it in the picture's points, outside it
        ZStack(alignment: .topLeading) {
            RackUnitPicture(kit: kit, unit: unit, on: on, filament: false)
            controls(slots).offset(x: -unit.panel[0], y: -unit.panel[1])
        }
        .frame(width: kit.panelWidth, height: CGFloat(unit.u) * kit.uPt, alignment: .topLeading)
    }

    func channel(_ i: Int) -> Int { bank * patch.n + i }

    func lit(_ slots: [Int]) -> Set<String> {
        var on = Set<String>()
        for i in slots {
            let ch = channel(i)
            if bank > 0 { on.insert("n\(i)-b\(bank)") }
            if ch >= count { on.insert("p\(i)"); continue }
            switch role(ch) {
            case .mic: on.insert("t\(i)-mic")
            case .ref: on.insert("t\(i)-ref")
            case .off: break
            }
        }
        return on
    }

    func rowName(_ r: Role) -> String { r == .mic ? "mic" : r == .ref ? "ref" : "off" }

    @ViewBuilder func controls(_ slots: [Int]) -> some View {
        let order: [Role] = [.mic, .off, .ref]
        let ys = order.compactMap { patch.rows[rowName($0)] }
        let rowH = ys.count == 3 ? abs(ys[2] - ys[0]) / 2 : 17
        ZStack(alignment: .topLeading) {
            ForEach(slots.filter { channel($0) < count && $0 < patch.toggles.count }, id: \.self) { i in
                let ch = channel(i), c = patch.toggles[i]
                VStack(spacing: 0) {
                    ForEach(order, id: \.self) { r in
                        Button { set(r, ch) } label: { Color.clear.frame(width: patch.column, height: rowH).contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .help("Input \(ch + 1): \(r.label)")
                    }
                }
                .disabled(locked)
                .offset(x: c[0] - patch.column / 2, y: (patch.rows["mic"] ?? c[1]) - rowH / 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Input \(ch + 1)")
                .accessibilityValue(role(ch).label)
                .accessibilityAdjustableAction { dir in
                    guard !locked else { return }
                    let k = order.firstIndex(of: role(ch)) ?? 1
                    switch dir {
                    case .increment: if k > 0 { set(order[k - 1], ch) }
                    case .decrement: if k < 2 { set(order[k + 1], ch) }
                    @unknown default: break
                    }
                }
            }
        }
        .frame(width: unit.size[0], height: unit.size[1], alignment: .topLeading)
    }
}
#endif
