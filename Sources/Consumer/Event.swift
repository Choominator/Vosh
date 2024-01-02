/// Wrapper around an event produced by the legacy consumer accessibility API.
public struct Event {
    /// Type of event.
    public let notification: Notification
    /// Application that triggered the event.
    public let application: Element
    /// Element generating this event.
    public let subject: Element
    /// Event payload.
    public let payload: [String: Any]?

    /// Event notifications.
    public enum Notification: String, CaseIterable {
        // Keyboard focus events.
        case windowDidGetFocus = "AXFocusedWindowChanged"
        case elementDidGetFocus = "AXFocusedUIElementChanged"

        // Application events.
        case applicationDidBecomeActive = "AXApplicationActivated"
        case applicationDidBecomeInactive = "AXApplicationDeactivated"
        case applicationDidHide = "AXApplicationHidden"
        case applicationDidShow = "AXApplicationShown"

        // Top-level element events.
        case windowDidAppear = "AXWindowCreated"
        case windowDidMove = "AXWindowMoved"
        case windowDidResize = "AXWindowResized"
        case windowDidMinimize = "AXWindowMiniaturized"
        case windowDidRestore = "AXWindowDeminiaturized"
        case drawerDidSpawn = "AXDrawerCreated"
        case sheetDidSpawn = "AXSheetCreated"
        case helpTagDidSpawn = "AXHelpTagCreated"

        // Menu events.
        case menuDidOpen = "AXMenuOpened"
        case menuDidClose = "AXMenuClosed"
        case menuDidSelectItem = "AXMenuItemSelected"

        // Table and outline events.
        case rowCountDidUpdate = "AXRowCountChanged"
        case rowDidExpand = "AXRowExpanded"
        case rowDidCollapse = "AXRowCollapsed"
        case cellSelectionDidUpdate = "AXSelectedCellsChanged"
        case rowSelectionDidUpdate = "AXSelectedRowsChanged"
        case columnSelectionDidUpdate = "AXSelectedColumnsChanged"

        // Generic element and hierarchy events.
        case elementDidAppear = "AXCreated"
        case elementDidDisappear = "AXUIElementDestroyed"
        case elementBusyStatusDidUpdate = "AXElementBusyChanged"
        case elementDidResize = "AXResized"
        case elementDidMove = "AXMoved"
        case selectedChildrenDidMove = "AXSelectedChildrenMoved"
        case childrenSelectionDidUpdate = "AXSelectedChildrenChanged"
        case textSelectionDidUpdate = "AXSelectedTextChanged"
        case titleDidUpdate = "AXTitleChanged"
        case valueDidUpdate = "AXValueChanged"

        // Layout events.
        case unitsDidUpdate = "AXUnitsChanged"
        case layoutDidChange = "AXLayoutChanged"

        // Announcement events.
        case applicationDidAnnounce = "AXAnnouncementRequested"
    }
}
