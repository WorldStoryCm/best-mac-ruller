import Foundation

public enum ShortcutAction: String, Codable, CaseIterable, Identifiable {
    case controls, edit, visibility, loupe
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .controls: return "Show / hide controls"
        case .edit: return "Edit / click through"
        case .visibility: return "Show / hide lines"
        case .loupe: return "Show / hide loupe"
        }
    }
    public var hotKeyID: UInt32 {
        switch self { case .controls: return 3; case .edit: return 1; case .visibility: return 2; case .loupe: return 4 }
    }
    public var defaultShortcut: KeyBinding {
        switch self {
        case .controls: return KeyBinding(keyCode: 35, modifiers: 3, label: "P")
        case .edit: return KeyBinding(keyCode: 15, modifiers: 3, label: "R")
        case .visibility: return KeyBinding(keyCode: 4, modifiers: 3, label: "H")
        case .loupe: return KeyBinding(keyCode: 46, modifiers: 3, label: "M")
        }
    }
}

public struct KeyBinding: Codable, Equatable, Hashable {
    public var keyCode: UInt32
    // Stable, platform-independent bits: Control=1, Option=2, Command=4, Shift=8.
    public var modifiers: UInt32
    public var label: String
    public init(keyCode: UInt32, modifiers: UInt32, label: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.label = label
    }
    public var isValid: Bool { keyCode < 128 && modifiers > 0 && modifiers < 16 && modifiers & 7 != 0 && !label.isEmpty && label.count <= 8 }
    public func hasSameKeys(as other: Self) -> Bool { keyCode == other.keyCode && modifiers == other.modifiers }
    public var display: String {
        (modifiers & 1 != 0 ? "⌃" : "") + (modifiers & 2 != 0 ? "⌥" : "") +
        (modifiers & 8 != 0 ? "⇧" : "") + (modifiers & 4 != 0 ? "⌘" : "") + label
    }
}
