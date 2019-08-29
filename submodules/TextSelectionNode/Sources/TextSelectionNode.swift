import Foundation
import UIKit
import UIKit.UIGestureRecognizerSubclass
import AsyncDisplayKit
import Display

private func findScrollView(view: UIView?) -> UIScrollView? {
    if let view = view {
        if let view = view as? UIScrollView {
            return view
        }
        return findScrollView(view: view.superview)
    } else {
        return nil
    }
}

private func cancelScrollViewGestures(view: UIView?) {
    if let view = view {
        if let gestureRecognizers = view.gestureRecognizers {
            for recognizer in gestureRecognizers {
                if let recognizer = recognizer as? UIPanGestureRecognizer {
                    switch recognizer.state {
                    case .began, .possible:
                        recognizer.state = .ended
                    default:
                        break
                    }
                }
            }
        }
        cancelScrollViewGestures(view: view.superview)
    }
}

private func generateKnobImage(color: UIColor, inverted: Bool = false) -> UIImage? {
    let f: (CGSize, CGContext) -> Void = { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        context.setFillColor(color.cgColor)
        context.fill(CGRect(origin: CGPoint(x: (size.width - 2.0) / 2.0, y: size.width / 2.0), size: CGSize(width: 2.0, height: size.height - size.width / 2.0 - 1.0)))
        context.fillEllipse(in: CGRect(origin: CGPoint(), size: CGSize(width: size.width, height: size.width)))
        context.fillEllipse(in: CGRect(origin: CGPoint(x: (size.width - 2.0) / 2.0, y: size.width + 2.0), size: CGSize(width: 2.0, height: 2.0)))
    }
    let size = CGSize(width: 12.0, height: 12.0 + 2.0 + 2.0)
    if inverted {
        return generateImage(size, contextGenerator: f)?.stretchableImage(withLeftCapWidth: Int(size.width / 2.0), topCapHeight: Int(size.height) - (Int(size.width) + 1))
    } else {
        return generateImage(size, rotatedContext: f)?.stretchableImage(withLeftCapWidth: Int(size.width / 2.0), topCapHeight: Int(size.width) + 1)
    }
}

public final class TextSelectionTheme {
    public let selection: UIColor
    public let knob: UIColor
    
    public init(selection: UIColor, knob: UIColor) {
        self.selection = selection
        self.knob = knob
    }
}

private enum Knob {
    case left
    case right
}

private final class TextSelectionGetureRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private var longTapTimer: Timer?
    private var movingKnob: (Knob, CGPoint, CGPoint)?
    private var currentLocation: CGPoint?
    
    var beginSelection: ((CGPoint) -> Void)?
    var knobAtPoint: ((CGPoint) -> (Knob, CGPoint)?)?
    var moveKnob: ((Knob, CGPoint) -> Void)?
    var finishedMovingKnob: (() -> Void)?
    var clearSelection: (() -> Void)?
    
    override init(target: Any?, action: Selector?) {
        super.init(target: nil, action: nil)
        
        self.delegate = self
    }
    
    override public func reset() {
        super.reset()
        
        self.longTapTimer?.invalidate()
        self.longTapTimer = nil
        
        self.movingKnob = nil
        self.currentLocation = nil
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        
        let currentLocation = touches.first?.location(in: self.view)
        self.currentLocation = currentLocation
        
        if let currentLocation = currentLocation {
            if let (knob, knobPosition) = self.knobAtPoint?(currentLocation) {
                self.movingKnob = (knob, knobPosition, currentLocation)
                cancelScrollViewGestures(view: self.view?.superview)
                self.state = .began
            } else if self.longTapTimer == nil {
                final class TimerTarget: NSObject {
                    let f: () -> Void
                    
                    init(_ f: @escaping () -> Void) {
                        self.f = f
                    }
                    
                    @objc func event() {
                        self.f()
                    }
                }
                let longTapTimer = Timer(timeInterval: 0.3, target: TimerTarget({ [weak self] in
                    self?.longTapEvent()
                }), selector: #selector(TimerTarget.event), userInfo: nil, repeats: false)
                self.longTapTimer = longTapTimer
                RunLoop.main.add(longTapTimer, forMode: .common)
            }
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        
        let currentLocation = touches.first?.location(in: self.view)
        self.currentLocation = currentLocation
        
        if let (knob, initialKnobPosition, initialGesturePosition) = self.movingKnob, let currentLocation = currentLocation {
            
            self.moveKnob?(knob, CGPoint(x: initialKnobPosition.x + currentLocation.x - initialGesturePosition.x, y: initialKnobPosition.y + currentLocation.y - initialGesturePosition.y))
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        
        if let longTapTimer = self.longTapTimer {
            self.longTapTimer = nil
            longTapTimer.invalidate()
            self.clearSelection?()
        } else {
            if let _ = self.currentLocation, let _ = self.movingKnob {
                self.finishedMovingKnob?()
            }
        }
        self.state = .ended
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        
        self.state = .cancelled
    }
    
    private func longTapEvent() {
        if let currentLocation = self.currentLocation {
            self.beginSelection?(currentLocation)
            self.state = .ended
        }
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return true
    }
    
    @available(iOS 9.0, *)
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool {
        return true
    }
}

public final class TextSelectionNodeView: UIView {
    
}

public enum TextSelectionAction {
    case copy
    case share
    case lookup
}

public final class TextSelectionNode: ASDisplayNode {
    private let theme: TextSelectionTheme
    private let textNode: TextNode
    private let updateIsActive: (Bool) -> Void
    private let present: (ViewController, Any?) -> Void
    private weak var rootNode: ASDisplayNode?
    private let performAction: (String, TextSelectionAction) -> Void
    private var highlightOverlay: LinkHighlightingNode?
    private let leftKnob: ASImageNode
    private let rightKnob: ASImageNode
    
    private var currentRange: (Int, Int)?
    private var currentRects: [CGRect]?
    
    public let highlightAreaNode: ASDisplayNode
    
    public init(theme: TextSelectionTheme, textNode: TextNode, updateIsActive: @escaping (Bool) -> Void, present: @escaping (ViewController, Any?) -> Void, rootNode: ASDisplayNode, performAction: @escaping (String, TextSelectionAction) -> Void) {
        self.theme = theme
        self.textNode = textNode
        self.updateIsActive = updateIsActive
        self.present = present
        self.rootNode = rootNode
        self.performAction = performAction
        self.leftKnob = ASImageNode()
        self.leftKnob.isUserInteractionEnabled = false
        self.leftKnob.image = generateKnobImage(color: theme.knob)
        self.leftKnob.displaysAsynchronously = false
        self.leftKnob.displayWithoutProcessing = true
        self.leftKnob.alpha = 0.0
        self.rightKnob = ASImageNode()
        self.rightKnob.isUserInteractionEnabled = false
        self.rightKnob.image = generateKnobImage(color: theme.knob, inverted: true)
        self.rightKnob.displaysAsynchronously = false
        self.rightKnob.displayWithoutProcessing = true
        self.rightKnob.alpha = 0.0
        
        self.highlightAreaNode = ASDisplayNode()
        
        super.init()
        
        self.setViewBlock({
            return TextSelectionNodeView()
        })
        
        self.addSubnode(self.leftKnob)
        self.addSubnode(self.rightKnob)
    }
    
    override public func didLoad() {
        super.didLoad()
       
        let recognizer = TextSelectionGetureRecognizer(target: nil, action: nil)
        recognizer.knobAtPoint = { [weak self] point in
            guard let strongSelf = self else {
                return nil
            }
            if !strongSelf.leftKnob.alpha.isZero, strongSelf.leftKnob.frame.insetBy(dx: -4.0, dy: -8.0).contains(point) {
                return (.left, strongSelf.leftKnob.frame.offsetBy(dx: 0.0, dy: strongSelf.leftKnob.frame.width / 2.0).center)
            }
            if !strongSelf.rightKnob.alpha.isZero, strongSelf.rightKnob.frame.insetBy(dx: -4.0, dy: -8.0).contains(point) {
                return (.right, strongSelf.rightKnob.frame.offsetBy(dx: 0.0, dy: -strongSelf.rightKnob.frame.width / 2.0).center)
            }
            return nil
        }
        recognizer.moveKnob = { [weak self] knob, point in
            guard let strongSelf = self, let cachedLayout = strongSelf.textNode.cachedLayout, let _ = cachedLayout.attributedString, let currentRange = strongSelf.currentRange else {
                return
            }
            
            let mappedPoint = strongSelf.view.convert(point, to: strongSelf.textNode.view)
            if let stringIndex = strongSelf.textNode.attributesAtPoint(mappedPoint, orNearest: true)?.0 {
                //let string = attributedString.string as NSString
                var updatedMin = currentRange.0
                var updatedMax = currentRange.1
                switch knob {
                case .left:
                    updatedMin = stringIndex
                case .right:
                    updatedMax = stringIndex
                }
                let updatedRange = NSRange(location: min(updatedMin, updatedMax), length: max(updatedMin, updatedMax) - min(updatedMin, updatedMax))
                if strongSelf.currentRange?.0 != updatedMin || strongSelf.currentRange?.1 != updatedMax {
                    strongSelf.currentRange = (updatedMin, updatedMax)
                    strongSelf.updateSelection(range: updatedRange, animateIn: false)
                }
                
                if let scrollView = findScrollView(view: strongSelf.view) {
                    let scrollPoint = strongSelf.view.convert(point, to: scrollView)
                    scrollView.scrollRectToVisible(CGRect(origin: CGPoint(x: scrollPoint.x, y: scrollPoint.y - 30.0), size: CGSize(width: 1.0, height: 60.0)), animated: false)
                }
            }
        }
        recognizer.finishedMovingKnob = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.displayMenu()
        }
        recognizer.beginSelection = { [weak self] point in
            guard let strongSelf = self, let cachedLayout = strongSelf.textNode.cachedLayout, let attributedString = cachedLayout.attributedString else {
                return
            }
            
            strongSelf.dismissSelection()
            
            let mappedPoint = strongSelf.view.convert(point, to: strongSelf.textNode.view)
            var resultRange: NSRange?
            if let stringIndex = strongSelf.textNode.attributesAtPoint(mappedPoint, orNearest: false)?.0 {
                let string = attributedString.string as NSString
                
                let inputRange = CFRangeMake(0, string.length)
                let flag = UInt(kCFStringTokenizerUnitWord)
                let locale = CFLocaleCopyCurrent()
                let tokenizer = CFStringTokenizerCreate( kCFAllocatorDefault, string as CFString, inputRange, flag, locale)
                var tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
                
                while !tokenType.isEmpty {
                    let currentTokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
                    if currentTokenRange.location <= stringIndex && currentTokenRange.location + currentTokenRange.length > stringIndex  {
                        resultRange = NSRange(location: currentTokenRange.location, length: currentTokenRange.length)
                        break
                    }
                    tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
                }
                if resultRange == nil {
                    resultRange = NSRange(location: stringIndex, length: 1)
                }
            }
            
            strongSelf.currentRange = resultRange.flatMap {
                ($0.lowerBound, $0.upperBound)
            }
            strongSelf.updateSelection(range: resultRange, animateIn: true)
            strongSelf.displayMenu()
            strongSelf.updateIsActive(true)
        }
        recognizer.clearSelection = { [weak self] in
            self?.dismissSelection()
            self?.updateIsActive(false)
        }
        self.view.addGestureRecognizer(recognizer)
    }
    
    private func updateSelection(range: NSRange?, animateIn: Bool) {
        var rects: [CGRect]?
        
        if let range = range {
            rects = self.textNode.rangeRects(in: range)
        }
        
        self.currentRects = rects
        
        if let rects = rects, !rects.isEmpty {
            let highlightOverlay: LinkHighlightingNode
            if let current = self.highlightOverlay {
                highlightOverlay = current
            } else {
                highlightOverlay = LinkHighlightingNode(color: self.theme.selection)
                highlightOverlay.isUserInteractionEnabled = false
                highlightOverlay.innerRadius = 0.0
                highlightOverlay.outerRadius = 0.0
                highlightOverlay.inset = 1.0
                self.highlightOverlay = highlightOverlay
                self.highlightAreaNode.addSubnode(highlightOverlay)
            }
            highlightOverlay.frame = self.bounds
            highlightOverlay.updateRects(rects)
            if let image = self.leftKnob.image {
                self.leftKnob.frame = CGRect(origin: CGPoint(x: floor(rects[0].minX - 1.0 - image.size.width / 2.0), y: rects[0].minY - 1.0 - image.size.width), size: CGSize(width: image.size.width, height: image.size.width + rects[0].height + 2.0))
                self.rightKnob.frame = CGRect(origin: CGPoint(x: floor(rects[rects.count - 1].maxX + 1.0 - image.size.width / 2.0), y: rects[rects.count - 1].maxY + 1.0 - (rects[0].height + 2.0)), size: CGSize(width: image.size.width, height: image.size.width + rects[0].height + 2.0))
            }
            if self.leftKnob.alpha.isZero {
                highlightOverlay.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3, timingFunction: CAMediaTimingFunctionName.easeOut.rawValue)
                self.leftKnob.alpha = 1.0
                self.leftKnob.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.14, delay: 0.19)
                self.rightKnob.alpha = 1.0
                self.rightKnob.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.14, delay: 0.19)
                self.leftKnob.layer.animateSpring(from: 0.5 as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: 0.2, delay: 0.25, initialVelocity: 0.0, damping: 80.0)
                self.rightKnob.layer.animateSpring(from: 0.5 as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: 0.2, delay: 0.25, initialVelocity: 0.0, damping: 80.0)
                
                if animateIn {
                    var result = CGRect()
                    for rect in rects {
                        if result.isEmpty {
                            result = rect
                        } else {
                            result = result.union(rect)
                        }
                    }
                    highlightOverlay.layer.animateScale(from: 2.0, to: 1.0, duration: 0.26)
                    let fromResult = CGRect(origin: CGPoint(x: result.minX - result.width / 2.0, y: result.minY - result.height / 2.0), size: CGSize(width: result.width * 2.0, height: result.height * 2.0))
                    highlightOverlay.layer.animatePosition(from: CGPoint(x: (-fromResult.midX + highlightOverlay.bounds.midX) / 1.0, y: (-fromResult.midY + highlightOverlay.bounds.midY) / 1.0), to: CGPoint(), duration: 0.26, additive: true)
                }
            }
        } else if let highlightOverlay = self.highlightOverlay {
            self.highlightOverlay = nil
            highlightOverlay.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.18, removeOnCompletion: false, completion: { [weak highlightOverlay] _ in
                highlightOverlay?.removeFromSupernode()
            })
            self.leftKnob.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.18)
            self.leftKnob.alpha = 0.0
            self.leftKnob.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.18)
            self.rightKnob.alpha = 0.0
            self.rightKnob.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.18)
        }
    }
    
    private func dismissSelection() {
        self.currentRange = nil
        self.updateSelection(range: nil, animateIn: false)
    }
    
    private func displayMenu() {
        guard let currentRects = self.currentRects, !currentRects.isEmpty, let currentRange = self.currentRange, let cachedLayout = self.textNode.cachedLayout, let attributedString = cachedLayout.attributedString else {
            return
        }
        let range = NSRange(location: min(currentRange.0, currentRange.1), length: max(currentRange.0, currentRange.1) - min(currentRange.0, currentRange.1))
        var completeRect = currentRects[0]
        for i in 0 ..< currentRects.count {
            completeRect = completeRect.union(currentRects[i])
        }
        completeRect = completeRect.insetBy(dx: 0.0, dy: -12.0)
        
        let text = (attributedString.string as NSString).substring(with: range)
        
        var actions: [ContextMenuAction] = []
        actions.append(ContextMenuAction(content: .text(title: "Copy", accessibilityLabel: "Copy"), action: { [weak self] in
            self?.performAction(text, .copy)
            self?.dismissSelection()
        }))
        actions.append(ContextMenuAction(content: .text(title: "Look Up", accessibilityLabel: "Look Up"), action: { [weak self] in
            self?.performAction(text, .lookup)
            self?.dismissSelection()
        }))
        actions.append(ContextMenuAction(content: .text(title: "Share...", accessibilityLabel: "Share"), action: { [weak self] in
            self?.performAction(text, .share)
            self?.dismissSelection()
        }))
        self.present(ContextMenuController(actions: actions, catchTapsOutside: false, hasHapticFeedback: false), ContextMenuControllerPresentationArguments(sourceNodeAndRect: { [weak self] in
            guard let strongSelf = self, let rootNode = strongSelf.rootNode else {
                return nil
            }
            return (strongSelf, completeRect, rootNode, rootNode.bounds)
        }, bounce: false))
    }
}
