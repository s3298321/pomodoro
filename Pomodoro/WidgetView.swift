@preconcurrency import AppKit
import SwiftUI

struct WidgetView: View {
    var model: PomodoroModel
    var morph: WidgetMorph
    var placement: WidgetPlacement

    var body: some View {
        ZStack(alignment: placement.anchor.restsOnRight ? .topTrailing : .topLeading) {
            if showsSessionShape {
                AnchoredSessionShape(
                    progress: morph.shapeProgress,
                    containerSize: sessionContainerSize,
                    anchor: placement.anchor,
                    fillOpacity: morph.fillOpacity,
                    showsLabel: morph.showsLabel,
                    isBreak: sessionIsBreak,
                    ripeness: sessionRipeness,
                    model: model
                )
            }

            if showsTomato {
                tomatoFace
                    .frame(width: WidgetLayout.tomatoSide, height: WidgetLayout.tomatoSide)
                    .opacity(morph.tomatoOpacity)
                    .allowsHitTesting(morph.tomatoOpacity > 0.4)
            }

            if morph.step == .settings {
                SettingsCard(model: model)
                    .transition(.opacity)
            } else if morph.step == .breakPrompt {
                BreakPrompt(model: model)
                    .transition(.opacity)
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(Rectangle())
    }

    /// The window is already this size when the shape animates, so the circle can grow toward the free side.
    private var sessionContainerSize: CGSize {
        switch morph.step {
        case .tomato:
            return CGSize(width: WidgetLayout.tomatoSide, height: WidgetLayout.tomatoSide)
        case .pill:
            return CGSize(width: WidgetLayout.pillWidth, height: WidgetLayout.pillHeight)
        case .union, .settings, .breakPrompt:
            return CGSize(width: WidgetLayout.pillWidth, height: WidgetLayout.tomatoSide)
        }
    }

    private var showsSessionShape: Bool {
        morph.step == .tomato || morph.step == .union || morph.step == .pill
    }

    private var showsTomato: Bool {
        morph.step == .tomato || morph.step == .union
    }

    @ViewBuilder
    private var tomatoFace: some View {
        let ripeness = model.phase == .studying ? model.ripeness : 1
        if model.phase == .idle {
            TomatoButton(model: model, ripeness: ripeness)
                .animation(.linear(duration: 0.45), value: ripeness)
        } else {
            TomatoArt(size: 68, ripeness: ripeness)
                .animation(.linear(duration: 0.45), value: ripeness)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Study in progress")
        }
    }

    private var cornerRadius: CGFloat {
        morph.step == .settings ? 18 : 0
    }

    /// While a study session is still on screen, follow the live ripeness. After it ends, keep the colour the pill had.
    private var sessionRipeness: Double {
        if model.phase == .studying {
            return model.ripeness
        }
        if case .study(let ripeness) = morph.fill {
            return ripeness
        }
        return 1
    }

    private var sessionIsBreak: Bool {
        if model.phase == .breaking { return true }
        if model.phase == .studying { return false }
        return morph.fill == .pause
    }

    @ViewBuilder
    private var surface: some View {
        switch morph.step {
        case .settings:
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        case .breakPrompt:
            Capsule(style: .circular)
                .fill(
                    LinearGradient(
                        colors: [
                            PomodoroPalette.flesh(1, highlight: true),
                            PomodoroPalette.flesh(1, highlight: false)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        case .tomato, .union, .pill:
            Color.clear
        }
    }

}

/// Draws the session capsule from an interpolated progress so the circle stays under the tomato
/// instead of collapsing toward the middle of the pill.
private struct AnchoredSessionShape: View, Animatable {
    var progress: Double
    var containerSize: CGSize
    var anchor: WidgetAnchor
    var fillOpacity: Double
    var showsLabel: Bool
    var isBreak: Bool
    var ripeness: Double
    var model: PomodoroModel

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let rect = WidgetLayout.shapeRect(progress: progress, containerSize: containerSize, anchor: anchor)
        fill
            .frame(width: rect.width, height: rect.height)
            .clipShape(Capsule(style: .circular))
            .overlay {
                CountdownPill(model: model)
                    .opacity(showsLabel ? 1 : 0)
                    .allowsHitTesting(showsLabel)
            }
            .position(x: rect.midX, y: rect.midY)
            .opacity(fillOpacity)
            .allowsHitTesting(showsLabel)
    }

    @ViewBuilder
    private var fill: some View {
        if isBreak {
            LinearGradient(
                colors: [PomodoroPalette.pauseTop, PomodoroPalette.pauseBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            LinearGradient(
                colors: [
                    PomodoroPalette.flesh(ripeness, highlight: true),
                    PomodoroPalette.flesh(ripeness, highlight: false)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct TomatoButton: View {
    var model: PomodoroModel
    var ripeness: Double
    @State private var hovering = false

    var body: some View {
        Button(action: model.leftClick) {
            TomatoArt(size: 68, ripeness: ripeness)
                .scaleEffect(hovering ? 1.04 : 1)
                .animation(.easeOut(duration: 0.16), value: hovering)
        }
        .buttonStyle(PressButtonStyle())
        .onContinuousHover { phase in
            guard !WidgetDragCursor.isActive else { return }
            switch phase {
            case .active:
                if !hovering { hovering = true }
                NSCursor.pointingHand.set()
            case .ended:
                if hovering { hovering = false }
                NSCursor.arrow.set()
            }
        }
        .accessibilityLabel("Start study session")
        .accessibilityHint("Right click to change study and pause durations")
        .accessibilityIdentifier("pomodoro.tomato")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension View {
    /// AppKit buttons keep the arrow unless the hand is set again on each move inside the control.
    func pointingCursor() -> some View {
        onContinuousHover { phase in
            guard !WidgetDragCursor.isActive else { return }
            switch phase {
            case .active:
                NSCursor.pointingHand.set()
            case .ended:
                NSCursor.arrow.set()
            }
        }
    }
}

private struct PressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

enum PomodoroQuit {
    static func perform() {
        NSApp.terminate(nil)
        DispatchQueue.main.async {
            exit(EXIT_SUCCESS)
        }
    }
}

struct TomatoArt: View, Animatable {
    var size: CGFloat = 68
    var ripeness: Double = 1

    /// Animating ripeness itself walks the fruit through the ripening colours instead of cross-fading.
    var animatableData: Double {
        get { ripeness }
        set { ripeness = newValue }
    }

    var body: some View {
        Canvas { context, canvasSize in
            let geometry = TomatoGeometry(side: min(canvasSize.width, canvasSize.height))
            draw(geometry, in: &context)
        }
        .frame(width: size, height: size)
    }

    private func draw(_ geometry: TomatoGeometry, in context: inout GraphicsContext) {
        let unit = geometry.unit
        let fruit = geometry.fruit

        context.fill(
            fruit,
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: PomodoroPalette.flesh(ripeness, tone: .highlight), location: 0),
                    .init(color: PomodoroPalette.flesh(ripeness, tone: .core), location: 0.50),
                    .init(color: PomodoroPalette.flesh(ripeness, tone: .deep), location: 1)
                ]),
                center: geometry.point(34, 38),
                startRadius: 4 * unit,
                endRadius: 68 * unit
            )
        )

        context.drawLayer { layer in
            layer.clip(to: fruit)
            layer.fill(
                fruit,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: PomodoroPalette.flesh(ripeness, tone: .rim).opacity(0.45), location: 0),
                        .init(color: .clear, location: 0.36)
                    ]),
                    startPoint: geometry.point(16, 24),
                    endPoint: geometry.point(52, 58)
                )
            )
            let pit = CGRect(x: 40 * unit, y: 22.6 * unit, width: 20 * unit, height: 5.2 * unit)
            layer.addFilter(.blur(radius: 1.6 * unit))
            layer.fill(Path(ellipseIn: pit), with: .color(.black.opacity(0.08)))
        }

        context.drawLayer { layer in
            layer.clip(to: fruit)
            layer.opacity = 0.13
            layer.addFilter(.blur(radius: unit))
            layer.translateBy(x: 0, y: 1.4 * unit)
            layer.fill(geometry.leaf, with: .color(.black))
        }

        context.fill(
            geometry.stem,
            with: .linearGradient(
                Gradient(colors: [PomodoroPalette.stemLight, PomodoroPalette.stemDark]),
                startPoint: geometry.point(56, 6.8),
                endPoint: geometry.point(50, 27.2)
            )
        )
        context.fill(
            geometry.leaf,
            with: .linearGradient(
                Gradient(colors: [PomodoroPalette.leafMid, PomodoroPalette.leafShadow]),
                startPoint: geometry.point(16, 21),
                endPoint: geometry.point(49, 29)
            )
        )
        context.fill(
            geometry.leafUpper,
            with: .linearGradient(
                Gradient(colors: [PomodoroPalette.leafSun, PomodoroPalette.leafMid]),
                startPoint: geometry.point(20, 12),
                endPoint: geometry.point(49, 26)
            )
        )
    }
}

/// The tomato drawn on a 100 x 100 grid, so every part shares one set of proportions.
private struct TomatoGeometry {
    let unit: CGFloat

    init(side: CGFloat) {
        unit = side / 100
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * unit, y: y * unit)
    }

    /// Wider than tall. The crown only dips 1.4 units, so the top stays almost round.
    var fruit: Path {
        var path = Path()
        path.move(to: point(50, 24.8))
        path.addCurve(to: point(68, 23.4), control1: point(55.4, 24.8), control2: point(61.6, 23.4))
        path.addCurve(to: point(93, 57.4), control1: point(82, 23.4), control2: point(93, 38.5))
        path.addCurve(to: point(50, 93), control1: point(93, 77.5), control2: point(74.6, 93))
        path.addCurve(to: point(7, 57.4), control1: point(25.4, 93), control2: point(7, 77.5))
        path.addCurve(to: point(32, 23.4), control1: point(7, 38.5), control2: point(18, 23.4))
        path.addCurve(to: point(50, 24.8), control1: point(38.4, 23.4), control2: point(44.6, 24.8))
        path.closeSubpath()
        return path
    }

    /// A slender stem, curving up and a little to the right.
    var stem: Path {
        var path = Path()
        path.move(to: point(48.4, 27.2))
        path.addCurve(to: point(54.5, 7.6), control1: point(48.8, 19.4), control2: point(51.4, 12))
        path.addQuadCurve(to: point(57.6, 9), control: point(56.4, 7))
        path.addCurve(to: point(51.6, 27.2), control1: point(54.8, 13.4), control2: point(52, 19.8))
        path.closeSubpath()
        return path
    }

    /// One sculpted leaf arching over the left shoulder.
    var leaf: Path {
        var path = Path()
        path.move(to: point(49.6, 26.2))
        path.addCurve(to: point(18.5, 22.8), control1: point(43.2, 12.8), control2: point(28.5, 12.8))
        path.addCurve(to: point(49.6, 27.2), control1: point(26.8, 28.2), control2: point(39.2, 29.2))
        path.closeSubpath()
        return path
    }

    /// The sunlit half of the leaf, split along its midrib.
    var leafUpper: Path {
        var path = Path()
        path.move(to: point(49.6, 26.2))
        path.addCurve(to: point(18.5, 22.8), control1: point(43.2, 12.8), control2: point(28.5, 12.8))
        path.addCurve(to: point(49.6, 26.6), control1: point(28.8, 20.4), control2: point(40.2, 22.8))
        path.closeSubpath()
        return path
    }
}

private struct SettingsCard: View {
    @Bindable var model: PomodoroModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DurationRow(
                title: "Study",
                range: PomodoroModel.studyRange,
                value: $model.studyMinutes
            )
            .accessibilityIdentifier("pomodoro.studyMinutes")

            DurationRow(
                title: "Pause",
                range: PomodoroModel.breakRange,
                value: $model.breakMinutes
            )
            .accessibilityIdentifier("pomodoro.pauseMinutes")

            HStack {
                Spacer(minLength: 0)
                Button("Quit") {
                    PomodoroQuit.perform()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .pointingCursor()
                .accessibilityIdentifier("pomodoro.quit")
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onExitCommand {
            model.dismissSettings()
        }
    }
}

private struct DurationRow: View {
    var title: String
    var range: ClosedRange<Int>
    @Binding var value: Int
    @State private var draft: String
    @FocusState private var focused: Bool

    init(title: String, range: ClosedRange<Int>, value: Binding<Int>) {
        self.title = title
        self.range = range
        self._value = value
        self._draft = State(initialValue: String(value.wrappedValue))
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 44, alignment: .leading)
            TextField(title, text: $draft)
                .focused($focused)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 48)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
                .onChange(of: draft) { _, newValue in
                    accept(newValue)
                }
            Text("min")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 13))
        .controlSize(.small)
        .onChange(of: value) { _, newValue in
            guard !focused else { return }
            let shown = String(newValue)
            if draft != shown {
                draft = shown
            }
        }
        .onDisappear(perform: commit)
    }

    /// Digits only. A whole number inside the allowed range is stored immediately; anything else waits until editing ends.
    private func accept(_ newValue: String) {
        let digits = String(newValue.filter(\.isNumber).prefix(3))
        if digits != newValue {
            draft = digits
            return
        }
        guard let parsed = Int(digits), range.contains(parsed), parsed != value else { return }
        value = parsed
    }

    private func commit() {
        if let parsed = Int(draft) {
            value = parsed
        }
        let shown = String(value)
        if draft != shown {
            draft = shown
        }
    }
}

private struct CountdownPill: View {
    var model: PomodoroModel

    var body: some View {
        HStack(spacing: 10) {
            Text(model.phase == .breaking ? "Break" : "Focus")
                .font(.system(size: 12, weight: .semibold))
            Text(model.remainingText)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .monospacedDigit()
                .accessibilityLabel(model.phase == .breaking ? "Break remaining" : "Focus remaining")
                .accessibilityValue(model.remainingText)
            Button(action: model.stop) {
                Text("Stop")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.22), in: Capsule())
            }
            .buttonStyle(.plain)
            .pointingCursor()
            .accessibilityIdentifier("pomodoro.stop")
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("pomodoro.countdown")
    }
}

private struct BreakPrompt: View {
    var model: PomodoroModel

    var body: some View {
        HStack(spacing: 8) {
            Text("Take a break?")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            choice("Yes", identifier: "pomodoro.breakYes", shortcut: .defaultAction, action: model.acceptBreak)
            choice("No", identifier: "pomodoro.breakNo", shortcut: .cancelAction, action: model.declineBreak)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("pomodoro.breakPrompt")
    }

    private func choice(
        _ title: String,
        identifier: String,
        shortcut: KeyboardShortcut,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.22), in: Capsule())
        }
        .buttonStyle(.plain)
        .pointingCursor()
        .keyboardShortcut(shortcut)
        .accessibilityIdentifier(identifier)
    }
}

enum PomodoroPalette {
    static let stemLight = Color(red: 0.25, green: 0.66, blue: 0.32)
    static let stemDark = Color(red: 0.08, green: 0.34, blue: 0.17)
    static let leafSun = Color(red: 0.36, green: 0.77, blue: 0.36)
    static let leafMid = Color(red: 0.17, green: 0.56, blue: 0.26)
    static let leafShadow = Color(red: 0.09, green: 0.37, blue: 0.18)
    static let pauseTop = Color(red: 0.50, green: 0.50, blue: 0.52)
    static let pauseBottom = Color(red: 0.32, green: 0.32, blue: 0.34)

    enum FleshTone {
        case rim, highlight, core, deep
    }

    /// The lit and shaded stops the countdown pill borrows from the tomato.
    static func flesh(_ ripeness: Double, highlight: Bool) -> Color {
        flesh(ripeness, tone: highlight ? .highlight : .core)
    }

    static func flesh(_ ripeness: Double, tone: FleshTone) -> Color {
        // Green ripens through orange, the way a tomato does; a straight green-to-red blend goes brown.
        let stops: [(Double, Double, Double)]
        switch tone {
        case .rim:
            stops = [(0.74, 0.89, 0.44), (1.00, 0.79, 0.38), (1.00, 0.48, 0.37)]
        case .highlight:
            stops = [(0.58, 0.79, 0.30), (0.98, 0.64, 0.22), (0.96, 0.30, 0.23)]
        case .core:
            stops = [(0.43, 0.65, 0.21), (0.91, 0.46, 0.14), (0.86, 0.18, 0.16)]
        case .deep:
            stops = [(0.27, 0.47, 0.14), (0.74, 0.31, 0.09), (0.66, 0.09, 0.11)]
        }
        let position = min(1, max(0, ripeness)) * Double(stops.count - 1)
        let index = min(stops.count - 2, Int(position))
        let t = position - Double(index)
        let from = stops[index]
        let to = stops[index + 1]
        return Color(
            red: from.0 + (to.0 - from.0) * t,
            green: from.1 + (to.1 - from.1) * t,
            blue: from.2 + (to.2 - from.2) * t
        )
    }
}
