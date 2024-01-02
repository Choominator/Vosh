/// Parameterized attribute queries.
public enum Query: String {
    // Text attributes.
    case lineForIndex = "AXLineForIndex"
    case rangeForLine = "AXRangeForLine"
    case stringForRange = "AXStringForRange"
    case rangeForPosition = "AXRangeForPosition"
    case rangeForIndex = "AXRangeForIndex"
    case boundsForRange = "AXBoundsForRange"
    case rtfForRange = "AXRTFForRange"
    case attributedStringForRange = "AXAttributedStringForRange"
    case styleRangeForIndex = "AXStyleRangeForIndex"

    // Table cell attributes.
    case cellForColumnAndRow = "AXCellForColumnAndRow"

    // Layout attributes.
    case layoutPointForScreenPoint = "AXLayoutPointForScreenPoint"
    case layoutSizeForScreenSize = "AXLayoutSizeForScreenSize"
    case screenPointForLayoutPoint = "AXScreenPointForLayoutPoint"
    case screenSizeForLayoutSize = "AXScreenSizeForLayoutSize"
}
