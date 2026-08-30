import Foundation
import NumlexCore

/// r41: folder tab strip threshold — the pure scroll-vs-fixed decision.
/// Up to the visible cap (General + 5 custom = 6 total rows) the strip
/// is a plain pinned stack with NO ScrollView; beyond it a bounded
/// ScrollView appears. These cases pin the boundary deterministically.
public let r41Cases: [EngineCase] = [
    EngineCase("r41-tab-strip-short-no-scroll") {
        // General alone, General + one custom, and everything up to the
        // cap (5 custom = exactly 6 total rows) must NOT scroll.
        for custom in [0, 1, 2, 3, 4, 5] {
            try expect(!SheetOrganization.tabStripScrolls(customFolderCount: custom),
                       "custom=\(custom) (total \(custom + 1) rows) renders fixed")
        }
    },
    EngineCase("r41-tab-strip-cap-boundary") {
        try expectEqual(SheetOrganization.tabVisibleCap, 6,
                        "the visible cap is 6 total rows (General counts as one)")
        try expect(!SheetOrganization.tabStripScrolls(customFolderCount: 5),
                   "5 custom = exactly the cap: still fixed")
        try expect(SheetOrganization.tabStripScrolls(customFolderCount: 6),
                   "6 custom = cap + 1 row: scrolls")
    },
    EngineCase("r41-tab-strip-long-scrolls") {
        for custom in [7, 20, 100] {
            try expect(SheetOrganization.tabStripScrolls(customFolderCount: custom),
                       "custom=\(custom) scrolls")
        }
    },
    EngineCase("r41-tab-strip-negative-safe") {
        try expect(!SheetOrganization.tabStripScrolls(customFolderCount: -1),
                   "negative count is rejected safely (no scroll, no crash)")
        try expect(!SheetOrganization.tabStripScrolls(customFolderCount: -1000),
                   "large negative count is rejected safely")
    },
]
