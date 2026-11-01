// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import SwiftUI
import AppKit

/// Choose the parts of a video to download.
///
/// A bar the width of the card, drawn over the video's storyboard, with one
/// band per range. The selected band has two handles; dragging inside it
/// moves it whole. Under the bar, each range has its start and end typed as
/// times, its length and its estimated size. Only these parts are downloaded.
struct TrimEditor: View {
    @Binding var ranges: [ClipRange]
    @Binding var selection: Int
    let duration: Double
    let metadata: MediaMetadata?
    let format: DownloadFormat

    /// Shortest range a drag can make. A zero-length range is not a clip.
    static let minimumLength: Double = 1

    private let barHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            bar
            VStack(spacing: Theme.Space.s6) {
                ForEach(ranges.indices, id: \.self) { index in
                    RangeRow(
                        range: ranges[index],
                        // Through a guarded closure, never `$ranges[index]`:
                        // a field that commits on losing focus can fire after
                        // the download started and the list was emptied, and
                        // an index binding then reads past the end and traps.
                        update: { new in
                            if ranges.indices.contains(index) { ranges[index] = new }
                        },
                        index: index,
                        isSelected: index == selection,
                        canRemove: ranges.count > 1,
                        duration: duration,
                        estimate: metadata?.estimatedBytes(for: format, range: ranges[index]),
                        onSelect: { selection = index },
                        onRemove: { remove(at: index) })
                }
            }
            actions
        }
        .padding(Theme.Space.s12)
        .background(Theme.fillTertiary,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    // MARK: - Bar

    /// Width of a handle. Handles sit OUTSIDE their range, so a range of a
    /// few seconds on a long video stays visible between them instead of
    /// disappearing under them; the bar keeps that much room on each side.
    private let handleWidth: CGFloat = 10

    private var bar: some View {
        GeometryReader { geo in
            let track = max(1, geo.size.width - handleWidth * 2)
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    StoryboardStrip(storyboard: metadata?.storyboard, duration: duration,
                                    height: barHeight)
                        .frame(width: track, height: barHeight)

                    // Everything outside the ranges is dimmed: what stays
                    // bright is what will be downloaded.
                    Rectangle()
                        .fill(Color.black.opacity(0.5))
                        .mask(
                            ZStack(alignment: .leading) {
                                Rectangle()
                                ForEach(ranges.indices, id: \.self) { i in
                                    Rectangle()
                                        .frame(width: max(x(ranges[i].length, track), 2))
                                        .offset(x: x(ranges[i].start, track))
                                        .blendMode(.destinationOut)
                                }
                            }
                            .compositingGroup()
                        )
                        .allowsHitTesting(false)
                }
                .frame(width: track, height: barHeight)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .offset(x: handleWidth)
                // Click on the strip outside every band: move the closest
                // edge of the selected range there. Faster than dragging.
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { value in
                    jumpSelectedEdge(to: seconds(value.location.x, track))
                })

                ForEach(ranges.indices, id: \.self) { i in
                    band(i, track: track)
                }
            }
        }
        .frame(height: barHeight)
    }

    private func band(_ i: Int, track: CGFloat) -> some View {
        let range = ranges[i]
        let selected = i == selection
        let bandWidth = max(x(range.length, track), 2)
        return HStack(spacing: 0) {
            Group {
                if selected {
                    handle.gesture(edgeGesture(i, edge: .start, width: track))
                } else {
                    Color.clear
                }
            }
            .frame(width: handleWidth)

            Rectangle()
                .fill(Color.white.opacity(selected ? 0 : 0.12))
                .overlay(
                    Rectangle().strokeBorder(Color.white.opacity(selected ? 1 : 0.6),
                                             lineWidth: selected ? 2 : 1))
                .frame(width: bandWidth)
                .contentShape(Rectangle())
                .gesture(moveGesture(i, width: track))
                .onTapGesture { selection = i }

            Group {
                if selected {
                    handle.gesture(edgeGesture(i, edge: .end, width: track))
                } else {
                    Color.clear
                }
            }
            .frame(width: handleWidth)
        }
        .frame(height: barHeight)
        .offset(x: x(range.start, track))
        .help(range.label)
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.white)
            .frame(width: handleWidth, height: barHeight)
            .overlay(
                Capsule().fill(Color.black.opacity(0.35)).frame(width: 2, height: 14)
            )
            .shadow(color: .black.opacity(0.3), radius: 1.5)
            .contentShape(Rectangle().inset(by: -6))
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
    }

    // MARK: - Gestures

    private enum Edge { case start, end }

    @State private var dragOrigin: ClipRange?

    private func edgeGesture(_ i: Int, edge: Edge, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                selection = i
                let origin = dragOrigin ?? ranges[i]
                if dragOrigin == nil { dragOrigin = origin }
                let delta = seconds(value.translation.width, width)
                var r = ranges[i]
                switch edge {
                case .start:
                    r.start = min(max(0, origin.start + delta), r.end - Self.minimumLength)
                case .end:
                    r.end = max(min(duration, origin.end + delta), r.start + Self.minimumLength)
                }
                ranges[i] = r
            }
            .onEnded { _ in dragOrigin = nil }
    }

    private func moveGesture(_ i: Int, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                selection = i
                let origin = dragOrigin ?? ranges[i]
                if dragOrigin == nil { dragOrigin = origin }
                let delta = seconds(value.translation.width, width)
                let length = origin.length
                let start = min(max(0, origin.start + delta), max(0, duration - length))
                ranges[i] = ClipRange(start: start, end: start + length)
            }
            .onEnded { _ in dragOrigin = nil }
    }

    private func jumpSelectedEdge(to time: Double) {
        guard ranges.indices.contains(selection) else { return }
        var r = ranges[selection]
        if abs(time - r.start) <= abs(time - r.end) {
            r.start = min(max(0, time), r.end - Self.minimumLength)
        } else {
            r.end = max(min(duration, time), r.start + Self.minimumLength)
        }
        ranges[selection] = r
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: Theme.Space.s8) {
            Button {
                addRange()
            } label: {
                Label("Add a Range", systemImage: "plus")
            }
            .buttonStyle(.push)

            if let chapters = metadata?.chapters, !chapters.isEmpty {
                Menu {
                    ForEach(chapters, id: \.self) { chapter in
                        Button {
                            toggle(chapter)
                        } label: {
                            if ranges.contains(chapter.range) {
                                Label(chapterLabel(chapter), systemImage: "checkmark")
                            } else {
                                Text(chapterLabel(chapter))
                            }
                        }
                    }
                } label: {
                    Text("Chapters")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Menu {
                Button("From the Start Handle to the End") { toEnd() }
                Button("Last 30 Seconds") { last(30) }
                Button("Last 60 Seconds") { last(60) }
            } label: {
                Text("Quick Range")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer(minLength: 0)
        }
        .font(Theme.Text.body)
    }

    private func chapterLabel(_ chapter: MediaMetadata.Chapter) -> String {
        "\(chapter.title)  \(chapter.range.label)"
    }

    /// New range after the last one, 30 seconds long, or wherever there is
    /// room when the last one reaches the end.
    private func addRange() {
        let last = ranges.map(\.end).max() ?? 0
        let length = min(30, duration)
        let start = last + length <= duration ? last : max(0, duration - length)
        ranges.append(ClipRange(start: start, end: min(duration, start + length)))
        selection = ranges.count - 1
    }

    private func remove(at index: Int) {
        guard ranges.count > 1, ranges.indices.contains(index) else { return }
        ranges.remove(at: index)
        selection = min(selection, ranges.count - 1)
    }

    /// Ticking a chapter adds it as a range; unticking removes it. The first
    /// chapter ticked replaces the default range rather than adding to it.
    private func toggle(_ chapter: MediaMetadata.Chapter) {
        if let index = ranges.firstIndex(of: chapter.range) {
            if ranges.count > 1 { remove(at: index) }
            return
        }
        let untouched = ranges.count == 1 && ranges[0] == ClipRange(start: 0, end: duration)
        if untouched {
            ranges = [chapter.range]
            selection = 0
        } else {
            ranges.append(chapter.range)
            selection = ranges.count - 1
        }
    }

    private func toEnd() {
        guard ranges.indices.contains(selection) else { return }
        ranges[selection].end = duration
    }

    private func last(_ seconds: Double) {
        guard ranges.indices.contains(selection) else { return }
        ranges[selection] = ClipRange(start: max(0, duration - seconds), end: duration)
    }

    // MARK: - Geometry

    private func x(_ time: Double, _ width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(time / duration) * width
    }

    private func seconds(_ x: CGFloat, _ width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(x / width) * duration
    }
}

// MARK: - One range

/// Start and end of one range, typed as times, with its length and size.
private struct RangeRow: View {
    let range: ClipRange
    let update: (ClipRange) -> Void
    let index: Int
    let isSelected: Bool
    let canRemove: Bool
    let duration: Double
    let estimate: Int64?
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s8) {
            Circle()
                .fill(isSelected ? Theme.label : Theme.labelTertiary)
                .frame(width: 6, height: 6)

            TimeField(label: "Start", value: startBinding, upperBound: duration)
            Text("to").font(Theme.Text.body).foregroundStyle(Theme.labelSecondary)
            TimeField(label: "End", value: endBinding, upperBound: duration)

            Text(summary)
                .font(Theme.Text.callout)
                .monospacedDigit()
                .foregroundStyle(range.isValid ? Theme.labelSecondary : Color.red)
                .lineLimit(1)

            Spacer(minLength: 0)

            if canRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.labelSecondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove this range")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var summary: String {
        guard range.isValid else { return "Start must be before end" }
        let length = Format.clipLength(range.length)
        guard let estimate, estimate > 0 else { return length }
        return "\(length) · ≈ \(Format.bytes(estimate))"
    }

    private var startBinding: Binding<Double> {
        Binding(get: { range.start }, set: {
            var r = range
            r.start = min(max(0, $0), duration)
            update(r)
        })
    }

    private var endBinding: Binding<Double> {
        Binding(get: { range.end }, set: {
            var r = range
            r.end = min(max(0, $0), duration)
            update(r)
        })
    }
}

/// A time typed as `3:40`, `1:02:00`, `220` or `3m40s`, with a stepper of one
/// second for adjusting with the arrows. A value that cannot be read is put
/// back as it was when the field is left.
private struct TimeField: View {
    let label: String
    @Binding var value: Double
    let upperBound: Double

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 2) {
            TextField(label, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(Theme.Text.body.monospacedDigit())
                .frame(width: upperBound >= 3600 ? 70 : 54)
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { isFocused in
                    if !isFocused { commit() }
                }
                .help("\(label) time, for example 3:40")
            Stepper("", value: Binding(
                get: { value },
                set: { value = min(max(0, $0.rounded()), upperBound) }),
                    in: 0...max(upperBound, 0), step: 1)
                .labelsHidden()
                .controlSize(.small)
        }
        .onAppear { text = ClipRange.clock(value) }
        // Always follow the range, focused or not: a drag, a stepper or a
        // removed row above changes it, and the field must never show a
        // time the range no longer has. Typing does not change the value
        // until it is committed, so nothing is overwritten mid-edit.
        .onChange(of: value) { newValue in
            text = ClipRange.clock(newValue)
        }
    }

    private func commit() {
        // Only a real change is written back: leaving a field untouched must
        // not rewrite the range (it can happen while the editor goes away).
        if let parsed = ClipRange.parseTime(text), parsed != value {
            value = parsed
        }
        text = ClipRange.clock(value)
    }
}

// MARK: - Storyboard strip

/// Thumbnails of the video side by side, cut from YouTube's storyboard
/// sheets. A plain bar when the video has none.
struct StoryboardStrip: View {
    let storyboard: Storyboard?
    let duration: Double
    let height: CGFloat

    @StateObject private var sheets = StoryboardSheets()

    var body: some View {
        GeometryReader { geo in
            let tileWidth = tileWidth
            let count = max(1, Int((geo.size.width / tileWidth).rounded(.up)))
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { i in
                    tile(at: duration * (Double(i) + 0.5) / Double(count))
                        .frame(width: geo.size.width / CGFloat(count), height: height)
                        .clipped()
                }
            }
        }
        .background(Theme.fillSecondary)
        .task(id: storyboard?.sheets.first) {
            if let storyboard { await sheets.load(storyboard) }
        }
    }

    private var tileWidth: CGFloat {
        guard let storyboard, storyboard.tileHeight > 0 else { return height * 16 / 9 }
        return height * CGFloat(storyboard.tileWidth) / CGFloat(storyboard.tileHeight)
    }

    @ViewBuilder
    private func tile(at seconds: Double) -> some View {
        if let storyboard, let spot = storyboard.tile(at: seconds),
           let image = sheets.images[spot.sheet],
           let cropped = image.cropping(to: CGRect(
                x: spot.x, y: spot.y,
                width: storyboard.tileWidth, height: storyboard.tileHeight)) {
            Image(decorative: cropped, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Color.clear
        }
    }
}

/// Downloaded storyboard sheets, by index. A few small JPEGs per video,
/// fetched once while the trim bar is on screen.
@MainActor
final class StoryboardSheets: ObservableObject {
    @Published private(set) var images: [Int: CGImage] = [:]
    private var loadedFor: String?

    func load(_ storyboard: Storyboard) async {
        guard loadedFor != storyboard.sheets.first else { return }
        loadedFor = storyboard.sheets.first
        images = [:]
        await withTaskGroup(of: (Int, CGImage?).self) { group in
            for (index, address) in storyboard.sheets.enumerated() {
                guard let url = URL(string: address), url.host?.hasSuffix("ytimg.com") == true
                else { continue }
                group.addTask {
                    guard let (data, _) = try? await URLSession.shared.data(from: url),
                          let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                    else { return (index, nil) }
                    return (index, image)
                }
            }
            for await (index, image) in group {
                if let image { images[index] = image }
            }
        }
    }
}
