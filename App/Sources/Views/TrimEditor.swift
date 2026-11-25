// TBD — To Be Downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import SwiftUI
import AppKit

/// Choose the parts of a video to download.
///
/// The video's storyboard, the width of the card, with the chosen range
/// drawn as a thick white frame over it (the trim bar of Photos and X): two
/// handles with chevrons, and the frame itself to move the range whole.
/// Other ranges stay visible as a thin outline. Under the bar, the ranges
/// are listed as chips; clicking the selected chip shows its times as
/// fields.
///
/// It starts as one range over the whole video, which means "download the
/// file as usual" (see `ClipRange.wholeVideo`): the row under the bar then
/// only says how to use it. Pulling a handle in switches to parts, and
/// "Whole Video" switches back.
struct TrimEditor: View {
    @Binding var ranges: [ClipRange]
    @Binding var selection: Int
    let duration: Double
    let metadata: MediaMetadata?
    let format: DownloadFormat

    /// Shortest range a drag can make. A zero-length range is not a clip.
    static var minimumLength: Double { ClipRange.minimumLength }

    // MARK: Geometry (R1 + P2 mockup of 2026-11-25)

    /// Height of the storyboard strip.
    static let trackHeight: CGFloat = 36
    /// Width of a handle: the frame's side border, drawn OUTSIDE the range,
    /// so even a one-second range keeps a frame 28 pt wide. The strip is
    /// inset by this much on each side to leave room for it.
    static let handleWidth: CGFloat = 14
    /// What a handle answers to: its border plus 2 pt on each side.
    static let gripWidth: CGFloat = 18
    /// The frame overhangs the strip by this much above and below.
    static let frameOverhang: CGFloat = 2
    private let frameBorder: CGFloat = 3
    private let frameRadius: CGFloat = 8
    private let stripRadius: CGFloat = 6
    /// Everything outside the ranges, dimmed: what stays bright is what
    /// will be downloaded.
    private let dimOpacity = 0.58

    private enum Edge: Hashable { case start, end }
    private enum DragKind { case edge(Edge), move }

    /// The range being dragged, kept here until the handle is released.
    ///
    /// Writing `ranges` on every mouse event redrew the whole Download
    /// screen at the rate of the mouse (field, notices, format controls,
    /// session list), which is what made the handles lag. The bar and the
    /// chips read this instead; the binding is written once, on release.
    private struct LiveDrag {
        let index: Int
        let kind: DragKind
        /// The range as it was when the drag began.
        let origin: ClipRange
        var range: ClipRange
    }

    @State private var live: LiveDrag?
    /// The selected range's times shown as fields, under the chips.
    @State private var showsDetail = false
    /// The handle the arrow keys move, after a click or a Tab.
    @FocusState private var focusedEdge: Edge?
    /// A handle that took the keyboard from a drag: its time stays hidden
    /// after the release, until an arrow key moves it. A handle reached with
    /// Tab shows its time at once (it is its focus indicator).
    @State private var quietEdge: Edge?

    /// What range `i` looks like right now: the dragged value while a drag
    /// is on, else the committed one.
    private func shown(_ i: Int) -> ClipRange {
        if let live, live.index == i { return live.range }
        return ranges[i]
    }

    /// The ranges as drawn, the dragged one included.
    private var current: [ClipRange] { ranges.indices.map(shown) }

    /// Parts chosen, rather than the whole video. Follows the drag, so the
    /// chips appear as soon as a handle leaves its end.
    private var isPart: Bool { !ClipRange.coversWholeVideo(current, duration: duration) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s10) {
            bar
                .padding(.horizontal, Self.handleWidth)
                .padding(.top, Self.frameOverhang)
            if isPart {
                chipsRow
                if showsDetail, ranges.indices.contains(selection) {
                    detail
                }
            } else {
                hintRow
            }
        }
    }

    // MARK: - Bar

    private var bar: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            ZStack(alignment: .topLeading) {
                strip(width)
                ForEach(ranges.indices, id: \.self) { i in
                    if i != selection { otherBand(i, width: width) }
                }
                if ranges.indices.contains(selection) {
                    selectedFrame(width)
                }
            }
            .coordinateSpace(name: Self.trackSpace)
        }
        .frame(height: Self.trackHeight)
    }

    private func strip(_ width: CGFloat) -> some View {
        let height = Self.trackHeight
        return ZStack(alignment: .topLeading) {
            StoryboardStrip(storyboard: metadata?.storyboard, duration: duration,
                            height: height)
                // Same storyboard, same size: nothing to redraw while a
                // handle moves over it.
                .equatable()
                .frame(width: width, height: height)

            Rectangle()
                .fill(Color.black.opacity(dimOpacity))
                .mask(
                    ZStack(alignment: .leading) {
                        Rectangle()
                        ForEach(ranges.indices, id: \.self) { i in
                            Rectangle()
                                .frame(width: max(x(shown(i).length, width), 1))
                                .offset(x: x(shown(i).start, width))
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
                )
                .allowsHitTesting(false)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: stripRadius, style: .continuous))
        // Click on the strip outside every range: move the closest edge of
        // the selected range there. Faster than dragging.
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { value in
            jumpSelectedEdge(to: seconds(value.location.x, width))
        })
    }

    /// A range that is not selected: a thin outline, to click or drag.
    private func otherBand(_ i: Int, width: CGFloat) -> some View {
        let range = shown(i)
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5))
            .frame(width: max(x(range.length, width), 3), height: Self.trackHeight)
            .contentShape(Rectangle())
            .gesture(moveGesture(i, width: width))
            .onTapGesture { selection = i }
            .offset(x: x(range.start, width))
            .help(range.label)
    }

    /// The selected range: white frame, handles, and the times while a
    /// handle is held or has the keyboard.
    @ViewBuilder
    private func selectedFrame(_ width: CGFloat) -> some View {
        let range = shown(selection)
        let start = x(range.start, width), end = x(range.end, width)
        let side = Self.handleWidth, overhang = Self.frameOverhang
        let frameHeight = Self.trackHeight + overhang * 2

        // Inside the frame: drag to move the range whole.
        Color.clear
            .frame(width: max(end - start, 0), height: Self.trackHeight)
            .contentShape(Rectangle())
            .gesture(moveGesture(selection, width: width))
            .offset(x: start)
            .help(range.label)

        RangeFrame(border: frameBorder, side: side, radius: frameRadius)
            .fill(Theme.ink, style: FillStyle(eoFill: true))
            .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
            .overlay(alignment: .leading) { chevron("chevron.left").frame(width: side) }
            .overlay(alignment: .trailing) { chevron("chevron.right").frame(width: side) }
            .frame(width: end - start + side * 2, height: frameHeight)
            .offset(x: start - side, y: -overhang)
            .allowsHitTesting(false)

        grip(.start, range: range, width: width)
            .frame(width: Self.gripWidth, height: frameHeight)
            .offset(x: start - side - (Self.gripWidth - side) / 2, y: -overhang)
        grip(.end, range: range, width: width)
            .frame(width: Self.gripWidth, height: frameHeight)
            .offset(x: end - (Self.gripWidth - side) / 2, y: -overhang)

        if showsBubble(.start) { bubble(.start, range: range, width: width) }
        if showsBubble(.end) { bubble(.end, range: range, width: width) }
    }

    private func chevron(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(Theme.inkOn)
    }

    /// One handle: drag, arrow keys (one second), VoiceOver (adjustable).
    private func grip(_ edge: Edge, range: ClipRange, width: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(edgeGesture(selection, edge: edge, width: width))
            .onHover { inside in
                // `set` rather than push/pop: a handle removed while hovered
                // would never pop, leaving the resize cursor everywhere.
                if inside { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
            }
            .focusable()
            .focused($focusedEdge, equals: edge)
            .onChange(of: focusedEdge) { _ in
                // Tab from a quiet handle to the other one: show it.
                if focusedEdge != quietEdge { quietEdge = nil }
            }
            .modifier(NoFocusRing())
            .onMoveCommand { direction in
                switch direction {
                case .left: nudge(edge, by: -1)
                case .right: nudge(edge, by: 1)
                default: break
                }
            }
            .accessibilityElement()
            .accessibilityLabel(edge == .start ? "Start" : "End")
            .accessibilityValue(ClipRange.clock(edge == .start ? range.start : range.end))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: nudge(edge, by: 1)
                case .decrement: nudge(edge, by: -1)
                @unknown default: break
                }
            }
    }

    private func showsBubble(_ edge: Edge) -> Bool {
        switch live?.kind {
        case .edge(let held)?: return held == edge
        case .move?: return true
        case nil: return focusedEdge == edge && quietEdge != edge
        }
    }

    private static let bubbleFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    private static let bubbleHeight: CGFloat = 17

    /// The time of a handle, on the dimmed side next to it; inside the frame
    /// when the card has no room left on that side.
    private func bubble(_ edge: Edge, range: ClipRange, width: CGFloat) -> some View {
        let text = ClipRange.clock(edge == .start ? range.start : range.end)
        let textWidth = (text as NSString).size(withAttributes: [.font: Self.bubbleFont]).width
        let bubbleWidth = textWidth.rounded(.up) + 12
        let reach = Self.gripWidth - (Self.gripWidth - Self.handleWidth) / 2
        var left: CGFloat
        switch edge {
        case .start:
            left = x(range.start, width) - reach - bubbleWidth
            if left < -Self.handleWidth { left = x(range.start, width) + 4 }
        case .end:
            left = x(range.end, width) + reach
            if left + bubbleWidth > width + Self.handleWidth {
                left = x(range.end, width) - 4 - bubbleWidth
            }
        }
        return Text(text)
            .font(Font(Self.bubbleFont))
            .foregroundStyle(Theme.inkOn)
            .frame(width: bubbleWidth, height: Self.bubbleHeight)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .offset(x: left, y: (Self.trackHeight - Self.bubbleHeight) / 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: - Under the bar

    /// Whole video: how to use the bar, and the chapters.
    private var hintRow: some View {
        HStack(spacing: Theme.Space.s8) {
            Text("Drag the ends to download only a part · \(ClipRange(start: 0, end: duration).label)")
                .font(Theme.Text.callout)
                .monospacedDigit()
                .foregroundStyle(Theme.labelSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            chaptersMenu
        }
    }

    /// Parts: one chip per range, then a way back to the whole video.
    private var chipsRow: some View {
        HStack(alignment: .top, spacing: Theme.Space.s8) {
            ChipFlow(spacing: Theme.Space.s6) {
                ForEach(ranges.indices, id: \.self) { i in chip(i) }
                addChip
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Theme.Space.s8) {
                chaptersMenu
                Button("Whole Video", action: useWholeVideo)
                    .buttonStyle(.push)
                    .help("Download the whole video")
            }
            .fixedSize()
        }
        .font(Theme.Text.body)
    }

    private func chip(_ i: Int) -> some View {
        let range = shown(i)
        let on = i == selection
        return HStack(spacing: Theme.Space.s8) {
            Text(range.label).monospacedDigit()
            Text(Format.clipLength(range.length))
                .font(.system(size: 11))
                .monospacedDigit()
                .opacity(0.6)
            if ranges.count > 1 {
                Button { remove(at: i) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .opacity(0.7)
                        .frame(width: 12, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove this range")
            }
        }
        .font(Theme.Text.body)
        .foregroundStyle(on ? Theme.inkOn : Theme.label)
        .padding(.leading, Theme.Space.s10)
        .padding(.trailing, Theme.Space.s8)
        .frame(height: 24)
        .background(on ? Theme.ink : Theme.fillSecondary, in: Capsule())
        .contentShape(Capsule())
        .onTapGesture {
            if on { showsDetail.toggle() } else { selection = i }
        }
        .help(on ? (showsDetail ? "Hide the times" : "Type the times") : "Select this range")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var addChip: some View {
        Button(action: addRange) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.label)
                .frame(width: 28, height: 24)
                .background(Theme.fillSecondary, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Add a Range")
        .accessibilityLabel("Add a Range")
    }

    @ViewBuilder
    private var chaptersMenu: some View {
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
    }

    /// The selected range typed as times, with its length and size.
    private var detail: some View {
        let range = shown(selection)
        let estimate = metadata?.estimatedBytes(for: format, range: range)
        return HStack(spacing: Theme.Space.s8) {
            TimeField(label: "Start", value: timeBinding(\.start), upperBound: duration)
            Text("to").font(Theme.Text.body).foregroundStyle(Theme.labelSecondary)
            TimeField(label: "End", value: timeBinding(\.end), upperBound: duration)

            Text(summary(range, estimate: estimate))
                .font(Theme.Text.callout)
                .monospacedDigit()
                .foregroundStyle(range.isValid ? Theme.labelSecondary : Color.red)
                .lineLimit(1)

            Spacer(minLength: 0)

            Menu {
                Button("From the Start Handle to the End") { toEnd() }
                Button("Last 30 Seconds") { last(30) }
                Button("Last 60 Seconds") { last(60) }
            } label: {
                Text("Quick Range")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .font(Theme.Text.body)
    }

    private func summary(_ range: ClipRange, estimate: Int64?) -> String {
        guard range.isValid else { return "Start must be before end" }
        let length = Format.clipLength(range.length)
        guard let estimate, estimate > 0 else { return length }
        return "\(length) · ≈ \(Format.bytes(estimate))"
    }

    /// A time field of the selected range. Through a guarded closure, never
    /// `$ranges[selection]`: a field that commits on losing focus can fire
    /// after the download started and the list was emptied, and an index
    /// binding then reads past the end and traps.
    private func timeBinding(_ key: WritableKeyPath<ClipRange, Double>) -> Binding<Double> {
        let index = selection
        return Binding(
            get: { ranges.indices.contains(index) ? shown(index)[keyPath: key] : 0 },
            set: { value in
                guard ranges.indices.contains(index) else { return }
                ranges[index][keyPath: key] = min(max(0, value), duration)
            })
    }

    // MARK: - Gestures

    /// Drags are measured in the bar's space, which stays put. In the
    /// handle's own space (the default), the handle moving under the pointer
    /// was subtracted from the drag: it followed at half the pointer's speed.
    private static let trackSpace = "TrimEditor.track"

    private func edgeGesture(_ i: Int, edge: Edge, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.trackSpace))
            .onChanged { value in
                guard let origin = beginDrag(i, kind: .edge(edge)) else { return }
                let delta = seconds(value.translation.width, width)
                var r = origin
                switch edge {
                case .start:
                    r.start = min(max(0, origin.start + delta), r.end - Self.minimumLength)
                case .end:
                    r.end = max(min(duration, origin.end + delta), r.start + Self.minimumLength)
                }
                follow(r)
            }
            .onEnded { _ in endDrag() }
    }

    private func moveGesture(_ i: Int, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.trackSpace))
            .onChanged { value in
                guard let origin = beginDrag(i, kind: .move) else { return }
                let delta = seconds(value.translation.width, width)
                let length = origin.length
                let start = min(max(0, origin.start + delta), max(0, duration - length))
                follow(ClipRange(start: start, end: start + length))
            }
            .onEnded { _ in endDrag() }
    }

    /// Range `i` as it was when its drag began, starting the drag on the
    /// first event. `nil` if the range is gone.
    private func beginDrag(_ i: Int, kind: DragKind) -> ClipRange? {
        if let live, live.index == i { return live.origin }
        guard ranges.indices.contains(i) else { return nil }
        if selection != i { selection = i }
        if case .edge(let edge) = kind { focusedEdge = edge }
        live = LiveDrag(index: i, kind: kind, origin: ranges[i], range: ranges[i])
        return ranges[i]
    }

    /// One mouse event: only the local copy moves. Without animation: the
    /// handle follows the pointer, and SwiftUI's velocity tracking of every
    /// moved frame cost about a third of each update.
    private func follow(_ range: ClipRange) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { live?.range = range }
    }

    /// Release: the range is written to the binding, once.
    private func endDrag() {
        guard let done = live else { return }
        live = nil
        if case .edge(let edge) = done.kind { quietEdge = edge }
        if ranges.indices.contains(done.index), ranges[done.index] != done.range {
            ranges[done.index] = done.range
        }
    }

    /// Arrow key or VoiceOver: one second, on whole seconds.
    private func nudge(_ edge: Edge, by step: Double) {
        guard live == nil, ranges.indices.contains(selection) else { return }
        quietEdge = nil
        var r = ranges[selection]
        switch edge {
        case .start:
            r.start = min(max(0, (r.start + step).rounded()), r.end - Self.minimumLength)
        case .end:
            r.end = max(min(duration, (r.end + step).rounded()), r.start + Self.minimumLength)
        }
        if r != ranges[selection] { ranges[selection] = r }
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

    private func useWholeVideo() {
        ranges = ClipRange.wholeVideo(duration)
        selection = 0
        showsDetail = false
        focusedEdge = nil
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
    /// chapter ticked replaces the whole video rather than adding to it.
    private func toggle(_ chapter: MediaMetadata.Chapter) {
        if let index = ranges.firstIndex(of: chapter.range) {
            if ranges.count > 1 { remove(at: index) } else { useWholeVideo() }
            return
        }
        if ClipRange.coversWholeVideo(ranges, duration: duration) {
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

// MARK: - Frame

/// The trim frame: a rounded rectangle with a thin border at the top and
/// bottom and a wide one on each side for the handles. Filled even-odd, so
/// the inside stays see-through.
private struct RangeFrame: Shape {
    let border: CGFloat
    let side: CGFloat
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: radius, height: radius),
                            style: .continuous)
        let inner = rect.insetBy(dx: side, dy: border)
        if inner.width > 0, inner.height > 0 {
            path.addRect(inner)
        }
        return path
    }
}

/// Hides the system focus ring on a handle: the handle shows its time
/// instead when it has the keyboard. Kept on macOS 13, which has no way to
/// turn the ring off.
private struct NoFocusRing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.focusEffectDisabled()
        } else {
            content
        }
    }
}

// MARK: - Chips

/// Chips side by side, wrapping to a new line when the row is full.
private struct ChipFlow: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(subviews, width: proposal.width ?? .infinity)
        let height = lines.last.map { $0.y + $0.height } ?? 0
        let widest = lines.map(\.width).max() ?? 0
        return CGSize(width: proposal.width.map { $0.isFinite ? $0 : widest } ?? widest,
                      height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        for line in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in line.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + line.y
                                                  + (line.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Line { var items: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = [Line()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            var line = lines[lines.count - 1]
            let needed = line.items.isEmpty ? size.width : line.width + spacing + size.width
            if needed > width, !line.items.isEmpty {
                let y = line.y + line.height + spacing
                lines.append(Line(items: [index], y: y, width: size.width, height: size.height))
                continue
            }
            line.items.append(index)
            line.width = needed
            line.height = max(line.height, size.height)
            lines[lines.count - 1] = line
        }
        return lines
    }
}

// MARK: - Typed times

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
        // The field shows whole seconds, so untouched text is compared as
        // text: parsing it back would round 63.4 s down to 63 s.
        if text != ClipRange.clock(value), let parsed = ClipRange.parseTime(text),
           parsed != value {
            value = parsed
        }
        text = ClipRange.clock(value)
    }
}

// MARK: - Storyboard strip

/// Thumbnails of the video side by side, cut from YouTube's storyboard
/// sheets. A plain bar when the video has none.
///
/// Equatable, so that a handle moving over it redraws nothing. The tiles
/// are drawn by `StoryboardTiles`, which observes the sheets itself: when
/// this view observed them, only the first sheet to arrive was ever drawn,
/// the next ones being stopped by the equality check.
struct StoryboardStrip: View, Equatable {
    let storyboard: Storyboard?
    let duration: Double
    let height: CGFloat

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.storyboard == b.storyboard && a.duration == b.duration && a.height == b.height
    }

    @StateObject private var sheets = StoryboardSheets()

    var body: some View {
        StoryboardTiles(sheets: sheets, storyboard: storyboard, duration: duration,
                        height: height)
            .background(Theme.fillSecondary)
            .task(id: storyboard?.sheets.first) {
                if let storyboard { await sheets.load(storyboard) }
            }
    }
}

/// One tile about every 30 pt, cut to the middle of its frame: the R1
/// mockup's density, where the storyboard's own 16:9 tiles showed only six
/// moments across the bar.
private struct StoryboardTiles: View {
    @ObservedObject var sheets: StoryboardSheets
    let storyboard: Storyboard?
    let duration: Double
    let height: CGFloat

    static let tileWidth: CGFloat = 30

    var body: some View {
        GeometryReader { geo in
            let count = max(1, Int((geo.size.width / Self.tileWidth).rounded()))
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { i in
                    tile(at: duration * (Double(i) + 0.5) / Double(count))
                        .frame(width: geo.size.width / CGFloat(count), height: height)
                        .clipped()
                }
            }
        }
    }

    @ViewBuilder
    private func tile(at seconds: Double) -> some View {
        if let storyboard, let spot = storyboard.tile(at: seconds),
           let cropped = sheets.tile(spot, width: storyboard.tileWidth,
                                     height: storyboard.tileHeight) {
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
    /// Tiles already cut, by sheet and position: cut once, not on every pass.
    private var tiles: [TileKey: CGImage] = [:]

    private struct TileKey: Hashable { let sheet: Int, x: Int, y: Int }

    func tile(_ spot: (sheet: Int, x: Int, y: Int), width: Int, height: Int) -> CGImage? {
        let key = TileKey(sheet: spot.sheet, x: spot.x, y: spot.y)
        if let cached = tiles[key] { return cached }
        guard let image = images[spot.sheet],
              let cropped = image.cropping(to: CGRect(x: spot.x, y: spot.y,
                                                      width: width, height: height))
        else { return nil }
        tiles[key] = cropped
        return cropped
    }

    func load(_ storyboard: Storyboard) async {
        guard loadedFor != storyboard.sheets.first else { return }
        loadedFor = storyboard.sheets.first
        images = [:]
        tiles = [:]
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
