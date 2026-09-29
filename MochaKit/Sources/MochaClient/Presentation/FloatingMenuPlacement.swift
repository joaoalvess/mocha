import CoreGraphics

public enum FloatingMenuPlacement {
    public static func maxHeight(minTop: CGFloat, maxBottom: CGFloat) -> CGFloat {
        max(maxBottom - minTop, 0)
    }

    public static func top(height: CGFloat, preferredBottom: CGFloat, minTop: CGFloat, maxBottom: CGFloat) -> CGFloat {
        let fitted = min(height, maxHeight(minTop: minTop, maxBottom: maxBottom))
        return max(preferredBottom - fitted, minTop)
    }
}
