import Foundation
import CoreGraphics

public struct GridSelection: Codable, Equatable, Hashable, Sendable {
    public var startRow: Int
    public var startColumn: Int
    public var endRow: Int
    public var endColumn: Int

    public init(startRow: Int, startColumn: Int, endRow: Int, endColumn: Int) {
        self.startRow = min(startRow, endRow)
        self.startColumn = min(startColumn, endColumn)
        self.endRow = max(startRow, endRow)
        self.endColumn = max(startColumn, endColumn)
    }
}

public struct GridGeometry: Equatable, Sendable {
    public var rows: Int
    public var columns: Int
    public var outerMargin: Double
    public var gap: Double

    public init(rows: Int, columns: Int, outerMargin: Double, gap: Double) {
        self.rows = max(1, rows)
        self.columns = max(1, columns)
        self.outerMargin = max(0, outerMargin)
        self.gap = max(0, gap)
    }

    public func frame(for selection: GridSelection, in visibleFrame: CGRect) -> CGRect {
        let margin = CGFloat(outerMargin)
        let spacing = CGFloat(gap)
        let usable = visibleFrame.insetBy(dx: margin, dy: margin)
        let cellWidth = usable.width / CGFloat(columns)
        let cellHeight = usable.height / CGFloat(rows)
        let x = usable.minX + CGFloat(selection.startColumn) * cellWidth
        let y = usable.maxY - CGFloat(selection.endRow + 1) * cellHeight
        let width = CGFloat(selection.endColumn - selection.startColumn + 1) * cellWidth
        let height = CGFloat(selection.endRow - selection.startRow + 1) * cellHeight
        let resultWidth = max(1, width - spacing)
        let resultHeight = max(1, height - spacing)
        return CGRect(x: x + spacing / 2, y: y + spacing / 2,
                      width: resultWidth, height: resultHeight)
    }

    public func frame(for selection: GridSelection, in visibleFrame: CGRect,
                      edgeInsets: EdgeInsets, horizontalGap: Double, verticalGap: Double) -> CGRect {
        let left = CGFloat(edgeInsets.left)
        let right = CGFloat(edgeInsets.right)
        let top = CGFloat(edgeInsets.top)
        let bottom = CGFloat(edgeInsets.bottom)
        let hGap = CGFloat(max(0, horizontalGap))
        let vGap = CGFloat(max(0, verticalGap))
        let usableWidth = max(1, visibleFrame.width - left - right)
        let usableHeight = max(1, visibleFrame.height - top - bottom)
        let cellWidth = max(1, (usableWidth - hGap * CGFloat(columns - 1)) / CGFloat(columns))
        let cellHeight = max(1, (usableHeight - vGap * CGFloat(rows - 1)) / CGFloat(rows))
        let selectedColumns = selection.endColumn - selection.startColumn + 1
        let selectedRows = selection.endRow - selection.startRow + 1
        let x = visibleFrame.minX + left + CGFloat(selection.startColumn) * (cellWidth + hGap)
        let yFromTop = top + CGFloat(selection.startRow) * (cellHeight + vGap)
        let width = CGFloat(selectedColumns) * cellWidth + CGFloat(selectedColumns - 1) * hGap
        let height = CGFloat(selectedRows) * cellHeight + CGFloat(selectedRows - 1) * vGap
        return CGRect(x: x, y: visibleFrame.maxY - yFromTop - height, width: width, height: height)
    }
}

public struct EdgeInsets: Equatable, Codable, Sendable {
    public var left: Double
    public var right: Double
    public var top: Double
    public var bottom: Double

    public init(left: Double, right: Double, top: Double, bottom: Double) {
        self.left = max(0, left)
        self.right = max(0, right)
        self.top = max(0, top)
        self.bottom = max(0, bottom)
    }

    public static let zero = EdgeInsets(left: 0, right: 0, top: 0, bottom: 0)
}

public struct WindowShortcut: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var keyCode: UInt32
    public var cocoaModifiers: UInt
    public var isGlobal: Bool
    public var isEnabled: Bool
    public var rows: Int
    public var columns: Int
    public var isSubdivided: Bool
    public var selection: GridSelection

    public init(id: UUID = UUID(), name: String, keyCode: UInt32, cocoaModifiers: UInt,
                isGlobal: Bool, isEnabled: Bool, rows: Int, columns: Int,
                isSubdivided: Bool, selection: GridSelection) {
        self.id = id
        self.name = name
        self.keyCode = keyCode
        self.cocoaModifiers = cocoaModifiers
        self.isGlobal = isGlobal
        self.isEnabled = isEnabled
        self.rows = rows
        self.columns = columns
        self.isSubdivided = isSubdivided
        self.selection = selection
    }
}
