@preconcurrency import AppKit
import Observation
import SwiftUI

enum WidgetMotion {
    /// Tomato and circle trade places up to half opacity.
    static let crossfade: TimeInterval = 0.1
    /// The circle and the pill trade shape while that fade finishes.
    static let morph: TimeInterval = 0.18
    /// Once the shape is a circle, the tomato finishes fading in.
    static let finish: TimeInterval = 0.1
    /// The circle stays faint while it is still under the tomato.
    static let circleOpacity = 0.14
    static let tomatoBesideCircle = 0.9
    /// Closing the pill drops the colour well before the shape has become a circle.
    static let wrapFade: TimeInterval = 0.07
}

/// Which screen corner the widget is parked in. The pill grows away from that corner.
enum WidgetAnchor: String, Equatable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    var restsOnRight: Bool {
        switch self {
        case .topTrailing, .bottomTrailing:
            return true
        case .topLeading, .bottomLeading:
            return false
        }
    }

    var restsOnTop: Bool {
        switch self {
        case .topLeading, .topTrailing:
            return true
        case .bottomLeading, .bottomTrailing:
            return false
        }
    }

    /// The quarter of `visible` that contains `point`. Ties on a midline go up and right.
    static func containing(_ point: CGPoint, in visible: CGRect) -> WidgetAnchor {
        let onRight = point.x >= visible.midX
        let onTop = point.y >= visible.midY
        switch (onTop, onRight) {
        case (false, false):
            return .bottomLeading
        case (false, true):
            return .bottomTrailing
        case (true, false):
            return .topLeading
        case (true, true):
            return .topTrailing
        }
    }

    func origin(for size: CGSize, in visible: CGRect) -> CGPoint {
        let x = restsOnRight
            ? visible.maxX - WidgetLayout.margin - size.width
            : visible.minX + WidgetLayout.margin
        let y = restsOnTop
            ? visible.maxY - WidgetLayout.margin - size.height
            : visible.minY + WidgetLayout.margin
        return CGPoint(x: x, y: y)
    }
}

@MainActor
@Observable
final class WidgetPlacement {
    static let storageKey = "widgetAnchor"

    private(set) var anchor: WidgetAnchor
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.storageKey),
           let stored = WidgetAnchor(rawValue: raw) {
            anchor = stored
        } else {
            anchor = .bottomLeading
        }
    }

    func move(to anchor: WidgetAnchor) {
        guard anchor != self.anchor else { return }
        self.anchor = anchor
        defaults.set(anchor.rawValue, forKey: Self.storageKey)
    }
}

enum WidgetDragCursor {
    static var isActive = false
}

enum WidgetLayout {
    static let margin: CGFloat = 16
    static let tomatoSide: CGFloat = 72
    /// Shorter than the pill. Its top lines up with the pill's top, so the stretch keeps one edge.
    static let circleSide: CGFloat = 40
    static let pillWidth: CGFloat = 206
    static let pillHeight: CGFloat = 56
    /// Upper bound for the glide home. Short drops finish sooner.
    static let glideDuration: TimeInterval = 0.72

    static func size(for step: WidgetMorph.Step) -> NSSize {
        switch step {
        case .tomato:
            return NSSize(width: tomatoSide, height: tomatoSide)
        case .union:
            return NSSize(width: pillWidth, height: tomatoSide)
        case .settings:
            return NSSize(width: 168, height: 92)
        case .pill:
            return NSSize(width: pillWidth, height: pillHeight)
        case .breakPrompt:
            return NSSize(width: 248, height: pillHeight)
        }
    }

    static func frame(for step: WidgetMorph.Step, visible: NSRect, anchor: WidgetAnchor) -> NSRect {
        let size = size(for: step)
        return NSRect(origin: anchor.origin(for: size, in: visible), size: size)
    }

    /// Tomato and pill share one hover area, so the pointer stays inside while the shape changes size.
    static func hoverUnion(visible: NSRect, anchor: WidgetAnchor) -> NSRect {
        frame(for: .tomato, visible: visible, anchor: anchor)
            .union(frame(for: .pill, visible: visible, anchor: anchor))
    }

    /// The box the session shape occupies inside the window.
    /// 0 is the circle centred under the tomato. 1 is the pill.
    /// The edge against the screen stays put; the shape stretches inward.
    static func shapeRect(progress: Double, containerSize: CGSize, anchor: WidgetAnchor) -> CGRect {
        let t = min(1, max(0, progress))
        let width = circleSide + (pillWidth - circleSide) * t
        let height = circleSide + (pillHeight - circleSide) * t
        let circleX = (tomatoSide - circleSide) / 2
        let circleY = (tomatoSide - circleSide) / 2
        let pillY = tomatoSide - pillHeight

        let x: CGFloat
        if anchor.restsOnRight {
            let rightInset = circleX * (1 - t)
            x = containerSize.width - rightInset - width
        } else {
            x = circleX * (1 - t)
        }

        let y: CGFloat
        if anchor.restsOnTop {
            // Mirror of the bottom anchor: the circle's lower edge stays, and the pill grows up to the screen.
            let circleBottom = circleY + circleSide
            let pillBottom = pillHeight
            let bottom = circleBottom + (pillBottom - circleBottom) * t
            y = bottom - height
        } else {
            var top = circleY + (pillY - circleY) * t
            if containerSize.height < tomatoSide - 0.5 {
                top -= tomatoSide - containerSize.height
            }
            y = top
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Crossfades the tomato with a circle, and stretches that circle into the pill while the fade finishes.
@MainActor
@Observable
final class WidgetMorph {
    enum Step: Equatable {
        case tomato
        /// Tall enough for the tomato and wide enough for the pill, so both can be on screen together.
        case union
        case pill
        case settings
        case breakPrompt
    }

    enum Fill: Equatable {
        case study(Double)
        case pause
    }

    private(set) var step: Step = .tomato
    private(set) var fill: Fill = .study(1)
    /// 0 is the circle, 1 is the pill.
    private(set) var shapeProgress: Double = 0
    private(set) var fillOpacity: Double = 0
    private(set) var tomatoOpacity: Double = 1
    private(set) var showsLabel = false

    var onFrame: ((Step, Bool) -> Void)?
    var onShadow: (() -> Void)?

    private var desired: Step = .tomato
    private var token = 0
    private var labelToken = 0

    func sync(model: PomodoroModel) {
        let target = Self.target(for: model)
        let shapeShowing = step == .pill || step == .union || fillOpacity > 0.01
        if target == .pill || shapeShowing {
            if model.phase == .breaking {
                fill = .pause
            } else if model.phase == .studying {
                fill = .study(model.ripeness)
            }
        }
        guard target != desired else { return }
        desired = target
        advance()
    }

    private static func target(for model: PomodoroModel) -> Step {
        switch model.phase {
        case .idle:
            return .tomato
        case .settings:
            return .settings
        case .studying:
            return model.countdownRevealed ? .pill : .tomato
        case .breakPrompt:
            return .breakPrompt
        case .breaking:
            return .pill
        }
    }

    private func advance() {
        cancelSchedule()
        switch desired {
        case .pill where step == .tomato || step == .union:
            goTowardPill()
        case .tomato where step == .pill || step == .union:
            goTowardTomato()
        case let next where step != next:
            arrive(at: next)
        default:
            break
        }
    }

    /// Ease a faint circle in under the tomato, then let it brighten as it opens into the pill.
    private func goTowardPill() {
        let stillJustTheTomato = shapeProgress < 0.04 && fillOpacity < 0.05 && tomatoOpacity > 0.55
        if stillJustTheTomato {
            fadeToMidpoint()
        } else {
            morphToPill()
        }
    }

    /// Shrink the pill into the circle while the two opacities meet, then bring the tomato up to full.
    private func goTowardTomato() {
        if shapeProgress > 0.04 {
            morphToCircle()
        } else {
            finishTomato()
        }
    }

    private func fadeToMidpoint() {
        snap(step: .tomato, progress: 0)
        withAnimation(.easeOut(duration: WidgetMotion.crossfade)) {
            tomatoOpacity = WidgetMotion.tomatoBesideCircle
        }
        withAnimation(.easeIn(duration: WidgetMotion.crossfade)) {
            fillOpacity = WidgetMotion.circleOpacity
        }
        followShadow()
        schedule(WidgetMotion.crossfade) { [weak self] in
            guard let self, self.desired == .pill else { return }
            self.morphToPill()
        }
    }

    private func morphToPill() {
        snap(step: .union, progress: nil)
        withAnimation(.easeIn(duration: WidgetMotion.morph)) {
            fillOpacity = 1
        }
        withAnimation(.easeInOut(duration: WidgetMotion.morph)) {
            shapeProgress = 1
            tomatoOpacity = 0
        }
        fadeLabel(true, duration: WidgetMotion.morph * 0.45, delay: WidgetMotion.morph * 0.55)
        followShadow()
        schedule(WidgetMotion.morph) { [weak self] in
            guard let self, self.desired == .pill else { return }
            self.settlePill()
        }
    }

    private func settlePill() {
        snap(step: .pill, progress: 1)
        followShadow()
    }

    private func morphToCircle() {
        fadeLabel(false, duration: 0.06)
        snap(step: .union, progress: nil)
        withAnimation(.easeOut(duration: WidgetMotion.wrapFade)) {
            fillOpacity = WidgetMotion.circleOpacity
        }
        withAnimation(.easeInOut(duration: WidgetMotion.morph)) {
            shapeProgress = 0
            tomatoOpacity = WidgetMotion.tomatoBesideCircle
        }
        followShadow()
        schedule(WidgetMotion.morph) { [weak self] in
            guard let self, self.desired == .tomato else { return }
            self.finishTomato()
        }
    }

    private func finishTomato() {
        snap(step: .tomato, progress: 0)
        withAnimation(.easeInOut(duration: WidgetMotion.finish)) {
            tomatoOpacity = 1
            fillOpacity = 0
        }
        followShadow()
    }

    private func snap(step: Step, progress: Double?) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.step = step
            if let progress {
                shapeProgress = progress
            }
        }
        onFrame?(step, false)
    }

    private func arrive(at next: Step) {
        let showTomato = next == .tomato
        let showPill = next == .pill
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            step = next
            shapeProgress = showPill ? 1 : 0
        }
        onFrame?(next, true)
        fadeLabel(showPill, duration: 0.16)
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            tomatoOpacity = showTomato ? 1 : 0
            fillOpacity = showPill ? 1 : 0
        }
    }

    private func fadeLabel(_ visible: Bool, duration: TimeInterval, delay: TimeInterval = 0) {
        labelToken += 1
        let current = labelToken
        let apply = { [weak self] in
            guard let self, self.labelToken == current else { return }
            withAnimation(.easeOut(duration: duration)) {
                self.showsLabel = visible
            }
        }
        if delay <= 0 {
            apply()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Task { @MainActor in apply() }
            }
        }
    }

    private func followShadow() {
        onShadow?()
    }

    private func schedule(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        token += 1
        let current = token
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            Task { @MainActor in
                guard let self, self.token == current else { return }
                action()
            }
        }
    }

    private func cancelSchedule() {
        token += 1
    }
}

@MainActor
protocol WidgetDragDelegate: AnyObject {
    func widgetDragBegan(at screenPoint: NSPoint)
    func widgetDragMoved(to screenPoint: NSPoint)
    func widgetDragEnded(at screenPoint: NSPoint)
}

final class FloatingPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: WidgetLayout.size(for: .tomato)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.contentView = contentView
        contentView.autoresizingMask = [.width, .height]
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        title = "Pomodoro"
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class ClearHostingView<Content: View>: NSHostingView<Content>, NSGestureRecognizerDelegate {
    weak var dragDelegate: WidgetDragDelegate?
    private var pan: NSPanGestureRecognizer?
    private var cursorAtPress = NSPoint.zero
    private var pressScreen = NSPoint.zero
    private var pressLocal = NSPoint.zero

    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        installPanIfNeeded()
    }

    /// Delay the click until the pointer actually moves, so the tomato can be dragged without losing its tap.
    private func installPanIfNeeded() {
        guard pan == nil else { return }
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.delaysPrimaryMouseButtonEvents = true
        addGestureRecognizer(pan)
        self.pan = pan
    }

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        !isTextInput(event)
    }

    @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
        let local = gesture.location(in: self)
        switch gesture.state {
        case .began:
            let translation = gesture.translation(in: self)
            pressLocal = NSPoint(x: local.x - translation.x, y: local.y - translation.y)
            pressScreen = screenPoint(pressLocal)
            cursorAtPress = NSEvent.mouseLocation
            let origin = pressScreen
            let mouse = dragPoint(local: local)
            MainActor.assumeIsolated {
                self.dragDelegate?.widgetDragBegan(at: origin)
                self.dragDelegate?.widgetDragMoved(to: mouse)
            }
        case .changed:
            let mouse = dragPoint(local: local)
            MainActor.assumeIsolated {
                self.dragDelegate?.widgetDragMoved(to: mouse)
            }
        case .ended, .cancelled:
            let mouse = dragPoint(local: local)
            MainActor.assumeIsolated {
                self.dragDelegate?.widgetDragMoved(to: mouse)
                self.dragDelegate?.widgetDragEnded(at: mouse)
            }
        default:
            break
        }
    }

    private func dragPoint(local: NSPoint) -> NSPoint {
        let cursor = NSEvent.mouseLocation
        if hypot(cursor.x - cursorAtPress.x, cursor.y - cursorAtPress.y) >= 1 {
            return cursor
        }
        // The hosting view's y axis points down, and screen coordinates point up.
        let dy = local.y - pressLocal.y
        return NSPoint(
            x: pressScreen.x + local.x - pressLocal.x,
            y: pressScreen.y + (isFlipped ? -dy : dy)
        )
    }

    private func screenPoint(_ local: NSPoint) -> NSPoint {
        let inWindow = convert(local, to: nil)
        return window?.convertPoint(toScreen: inWindow) ?? inWindow
    }

    private func isTextInput(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        var view: NSView? = super.hitTest(point)
        while let current = view, current !== self {
            if current is NSTextView || current is NSTextField { return true }
            let name = NSStringFromClass(type(of: current))
            if name.contains("TextField") || name.contains("TextView") || name.contains("FieldEditor") {
                return true
            }
            view = current.superview
        }
        return false
    }
}

@MainActor
final class PanelController: WidgetDragDelegate {
    let model: PomodoroModel
    private let morph = WidgetMorph()
    private let placement = WidgetPlacement()
    private let panel: FloatingPanel
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var isVisible = false
    private var lastRightClick = Date.distantPast
    private var hoverWatch: Timer?
    /// After the short countdown flash, ignore the pointer until it leaves, so polling does not immediately reopen the pill.
    private var holdTomatoUntilExit = false
    private var revealWasShowing = false
    private var isDragging = false
    private var isGliding = false
    private var glideToken = 0
    private var glideTimer: Timer?
    private var pushedDragCursor = false
    /// Pointer position minus the window origin, so the same point stays under the cursor.
    private var grabOffset = CGPoint.zero
    private var lastDragPoint = CGPoint.zero

    init(model: PomodoroModel) {
        self.model = model
        let hosting = ClearHostingView(rootView: WidgetView(model: model, morph: morph, placement: placement))
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel = FloatingPanel(contentView: hosting)
        hosting.dragDelegate = self
        morph.onFrame = { [weak self] step, animated in
            self?.applyFrame(for: step, animated: animated)
        }
        morph.onShadow = { [weak self] in
            self?.pulseShadow()
        }
    }

    func show() {
        installMonitorsIfNeeded()
        isVisible = true
        morph.sync(model: model)
        trackModel()
        updateHoverWatch()
        applyFrame(for: morph.step, animated: false)
        panel.orderFrontRegardless()
        panel.invalidateShadow()
    }

    private func trackModel() {
        withObservationTracking {
            _ = model.phase
            _ = model.countdownRevealed
            _ = model.ripeness
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.morph.sync(model: self.model)
                self.updateHoverWatch()
                self.trackModel()
            }
        }
    }

    private func applyFrame(for step: WidgetMorph.Step, animated: Bool) {
        if isDragging {
            resizeWhileDragging(to: WidgetLayout.size(for: step))
            return
        }
        // Stay on the screen the panel already occupies. NSScreen.main follows the key
        // window, which would fling the widget onto another display mid-morph.
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = WidgetLayout.frame(for: step, visible: screen.visibleFrame, anchor: placement.anchor)
        move(to: frame, animated: animated && isVisible, duration: 0.32, glide: false)

        if step == .settings {
            panel.makeKey()
        }
    }

    func widgetDragBegan(at screenPoint: NSPoint) {
        cancelGlide()
        isDragging = true
        lastDragPoint = screenPoint
        grabOffset = CGPoint(x: screenPoint.x - panel.frame.origin.x, y: screenPoint.y - panel.frame.origin.y)
        if !pushedDragCursor {
            WidgetDragCursor.isActive = true
            NSCursor.closedHand.push()
            pushedDragCursor = true
        }
    }

    func widgetDragMoved(to screenPoint: NSPoint) {
        guard isDragging else { return }
        lastDragPoint = screenPoint
        let origin = NSPoint(x: screenPoint.x - grabOffset.x, y: screenPoint.y - grabOffset.y)
        panel.setFrameOrigin(origin)
        NSCursor.closedHand.set()
    }

    func widgetDragEnded(at screenPoint: NSPoint) {
        if isDragging {
            widgetDragMoved(to: screenPoint)
        }
        guard isDragging else { return }
        isDragging = false
        if pushedDragCursor {
            WidgetDragCursor.isActive = false
            NSCursor.pop()
            pushedDragCursor = false
        }

        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        guard let screen = screen(containing: center) ?? nearestScreen(to: center) else { return }
        let anchor = WidgetAnchor.containing(center, in: screen.frame)
        placement.move(to: anchor)
        let frame = WidgetLayout.frame(for: morph.step, visible: screen.visibleFrame, anchor: anchor)
        let travel = hypot(frame.midX - panel.frame.midX, frame.midY - panel.frame.midY)
        let duration = min(WidgetLayout.glideDuration, max(0.34, travel / 1600))
        move(to: frame, animated: true, duration: duration, glide: true)
    }

    /// Keep the grabbed point under the cursor when a morph changes the window size mid-drag.
    private func resizeWhileDragging(to size: NSSize) {
        let mouse = lastDragPoint
        if grabOffset.x > size.width { grabOffset.x = size.width / 2 }
        if grabOffset.y > size.height { grabOffset.y = size.height / 2 }
        let origin = NSPoint(x: mouse.x - grabOffset.x, y: mouse.y - grabOffset.y)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.invalidateShadow()
    }

    private func move(to frame: NSRect, animated: Bool, duration: TimeInterval, glide: Bool) {
        cancelGlide()
        if !animated || frame.equalTo(panel.frame) {
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
            return
        }
        if glide {
            startGlide(to: frame, duration: duration)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
            self.panel.animator().setFrame(frame, display: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.panel.invalidateShadow()
        }
    }

    /// Steps the frame ourselves so a new drag can grab the widget where it actually is.
    private func startGlide(to frame: NSRect, duration: TimeInterval) {
        isGliding = true
        let token = glideToken
        let start = panel.frame
        let began = Date()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.glideToken == token else {
                    timer.invalidate()
                    return
                }
                let raw = min(1, Date().timeIntervalSince(began) / duration)
                let eased = CGFloat(1 - pow(1 - raw, 3))
                self.panel.setFrame(
                    NSRect(
                        x: start.minX + (frame.minX - start.minX) * eased,
                        y: start.minY + (frame.minY - start.minY) * eased,
                        width: start.width + (frame.width - start.width) * eased,
                        height: start.height + (frame.height - start.height) * eased
                    ),
                    display: true
                )
                if raw >= 1 {
                    timer.invalidate()
                    if self.glideTimer === timer {
                        self.glideTimer = nil
                    }
                    self.isGliding = false
                    self.panel.invalidateShadow()
                }
            }
        }
        glideTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelGlide() {
        glideToken += 1
        glideTimer?.invalidate()
        glideTimer = nil
        isGliding = false
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func nearestScreen(to point: NSPoint) -> NSScreen? {
        NSScreen.screens.min { lhs, rhs in
            Self.distance(from: point, to: lhs.frame) < Self.distance(from: point, to: rhs.frame)
        }
    }

    private static func distance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    private func updateHoverWatch() {
        let studying = model.phase == .studying
        if studying, hoverWatch == nil {
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.sampleHover()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            hoverWatch = timer
            sampleHover()
        } else if !studying, let hoverWatch {
            hoverWatch.invalidate()
            self.hoverWatch = nil
            holdTomatoUntilExit = false
            revealWasShowing = false
        }
    }

    /// Hover uses a fixed rectangle instead of the live window, which changes size under the pointer and retriggers the morph.
    private func sampleHover() {
        guard model.phase == .studying else { return }
        // The window is away from its corner while it is being carried or is still gliding home.
        guard !isDragging, !isGliding else { return }
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let mouse = NSEvent.mouseLocation
        let anchor = placement.anchor
        let tomato = WidgetLayout.frame(for: .tomato, visible: visible, anchor: anchor).insetBy(dx: -4, dy: -4)
        let union = WidgetLayout.hoverUnion(visible: visible, anchor: anchor).insetBy(dx: -8, dy: -8)
        let insideTomato = tomato.contains(mouse)
        let insideUnion = union.contains(mouse)

        if model.countdownRevealed {
            revealWasShowing = true
        } else if revealWasShowing {
            revealWasShowing = false
            if insideTomato || insideUnion {
                holdTomatoUntilExit = true
            }
        }

        if holdTomatoUntilExit {
            if !insideTomato && !insideUnion {
                holdTomatoUntilExit = false
            } else {
                return
            }
        }

        let shapeIsOpen = model.countdownRevealed || morph.step == .pill || morph.step == .union
        let inside = shapeIsOpen ? insideUnion : insideTomato
        if model.countdownRevealed != inside {
            model.setTimerHovered(inside)
        }
    }

    private func pulseShadow() {
        panel.invalidateShadow()
        for delay in [0.05, 0.1, 0.16] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.panel.invalidateShadow()
            }
        }
    }

    private func installMonitorsIfNeeded() {
        guard monitors.isEmpty else { return }

        let local = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .rightMouseUp]) { [weak self] event in
            let type = event.type
            let windowNumber = event.windowNumber
            let consume = MainActor.assumeIsolated { () -> Bool in
                guard let self, windowNumber != 0, windowNumber == self.panel.windowNumber else { return false }
                if type == .rightMouseDown {
                    let now = Date()
                    if now.timeIntervalSince(self.lastRightClick) > 0.25 {
                        self.lastRightClick = now
                        self.model.rightClick()
                    }
                }
                return true
            }
            return consume ? nil : event
        }
        monitors.append(local as Any)

        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let location = event.locationInWindow
            let windowNumber = event.windowNumber
            Task { @MainActor in
                guard let self else { return }
                if windowNumber == self.panel.windowNumber { return }
                self.dismissSettingsIfClickIsOutside(location)
            }
        }
        if let global {
            monitors.append(global)
        }

        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.applyFrame(for: self?.morph.step ?? .tomato, animated: false)
                }
            }
        )

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(
                workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.model.tick(at: Date())
                    }
                }
            )
        }
    }

    private func dismissSettingsIfClickIsOutside(_ location: NSPoint) {
        guard model.phase == .settings else { return }
        if !panel.frame.contains(location) {
            model.dismissSettings()
        }
    }
}
