import Foundation
import PaneCore

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let geometry = GridGeometry(rows: 6, columns: 6, outerMargin: 10, gap: 10)
let full = GridSelection(startRow: 0, startColumn: 0, endRow: 5, endColumn: 5)
require(geometry.frame(for: full, in: CGRect(x: 0, y: 0, width: 1200, height: 900)) ==
        CGRect(x: 15, y: 15, width: 1170, height: 870), "full-grid geometry")

let noSpacing = GridGeometry(rows: 6, columns: 6, outerMargin: 0, gap: 0)
let topLeft = GridSelection(startRow: 0, startColumn: 0, endRow: 2, endColumn: 2)
require(noSpacing.frame(for: topLeft, in: CGRect(x: 0, y: 0, width: 1200, height: 900)) ==
        CGRect(x: 0, y: 450, width: 600, height: 450), "top-left geometry")

require(GridSelection(startRow: 4, startColumn: 5, endRow: 1, endColumn: 2) ==
        GridSelection(startRow: 1, startColumn: 2, endRow: 4, endColumn: 5),
        "reverse drag normalization")

let margins = GridGeometry(rows: 1, columns: 2, outerMargin: 0, gap: 0)
let left = margins.frame(for: GridSelection(startRow: 0, startColumn: 0, endRow: 0, endColumn: 0),
                         in: CGRect(x: 0, y: 0, width: 1000, height: 800),
                         edgeInsets: EdgeInsets(left: 5, right: 5, top: 5, bottom: 5),
                         horizontalGap: 16, verticalGap: 16)
let right = margins.frame(for: GridSelection(startRow: 0, startColumn: 1, endRow: 0, endColumn: 1),
                          in: CGRect(x: 0, y: 0, width: 1000, height: 800),
                          edgeInsets: EdgeInsets(left: 5, right: 5, top: 5, bottom: 5),
                          horizontalGap: 16, verticalGap: 16)
require(left.minX == 5 && right.maxX == 995 && right.minX - left.maxX == 16,
        "edge and inter-window margin geometry")

print("GridLayoutCheck: 4 checks passed")
