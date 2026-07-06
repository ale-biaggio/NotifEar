
import Foundation

struct SonarTarget: Identifiable, Codable, Equatable, Hashable {
    var label: String
    var category: String
    var iconName: String
    var isSystemIcon: Bool
    var identifiers: [String]
    var customLabel: String?

    var id: String { label }

    // MARK: - Serialization

    static let messageKind = "sonarHandoff"

    var payload: [String: Any] {
        var dict: [String: Any] = [
            "kind": SonarTarget.messageKind,
            "label": label,
            "category": category,
            "iconName": iconName,
            "isSystemIcon": isSystemIcon,
            "identifiers": identifiers
        ]
        if let customLabel { dict["customLabel"] = customLabel }
        return dict
    }

    init?(payload: [String: Any]) {
        guard (payload["kind"] as? String) == SonarTarget.messageKind,
              let label = payload["label"] as? String else { return nil }
        self.label = label
        self.category = (payload["category"] as? String) ?? "attention"
        self.iconName = (payload["iconName"] as? String) ?? "waveform"
        self.isSystemIcon = (payload["isSystemIcon"] as? Bool) ?? true
        self.identifiers = (payload["identifiers"] as? [String]) ?? []
        self.customLabel = payload["customLabel"] as? String
    }

    init(label: String, category: String, iconName: String, isSystemIcon: Bool,
         identifiers: [String], customLabel: String?) {
        self.label = label
        self.category = category
        self.iconName = iconName
        self.isSystemIcon = isSystemIcon
        self.identifiers = identifiers
        self.customLabel = customLabel
    }
}
