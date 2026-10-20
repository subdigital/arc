import Foundation

/// A project's icon is an emoji or an SF Symbol name. Icons imported from Linear arrive as Linear's own names
/// ("SouthAmerica", "Boombox"); those are translated to symbols here.
public enum ProjectIcons {
    private static let linearNames: [String: String] = [
        "Subscribe": "bell", "SouthAmerica": "globe.americas", "NorthAmerica": "globe.americas", "Europe": "globe.europe.africa",
        "Asia": "globe.asia.australia", "Sound": "waveform", "Boombox": "hifispeaker", "Bitcoin": "bitcoinsign.circle",
        "Rocket": "paperplane", "Bug": "ladybug", "Code": "chevron.left.forwardslash.chevron.right", "Database": "cylinder",
        "Phone": "iphone", "Mobile": "iphone", "Server": "server.rack", "Star": "star", "Heart": "heart", "Home": "house",
        "Build": "hammer", "Tools": "wrench.and.screwdriver", "Lightbulb": "lightbulb", "Idea": "lightbulb", "Chart": "chart.bar",
        "Calendar": "calendar", "Mail": "envelope", "Chat": "bubble.left", "Music": "music.note", "Camera": "camera",
        "Cart": "cart", "Money": "dollarsign.circle", "Shield": "shield", "Lock": "lock", "Cloud": "cloud", "Globe": "globe",
        "Bolt": "bolt", "Flag": "flag", "Gift": "gift", "Key": "key", "Map": "map", "Pencil": "pencil", "Trophy": "trophy",
    ]

    /// The icon as it should be stored: Linear names become SF Symbols, everything else is kept as is.
    public static func normalized(_ icon: String) -> String {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        return linearNames[trimmed] ?? trimmed
    }

    /// A curated set for the picker.
    public static let symbols: [String] = [
        "folder", "star", "heart", "bolt", "flag", "bookmark", "tag", "pin", "bell", "gift",
        "house", "building.2", "globe", "globe.americas", "map", "location", "airplane", "car", "bicycle", "leaf",
        "paperplane", "hammer", "wrench.and.screwdriver", "gearshape", "cpu", "server.rack", "cylinder", "terminal",
        "chevron.left.forwardslash.chevron.right", "ladybug", "lightbulb", "puzzlepiece", "cube", "shippingbox", "cart", "creditcard",
        "chart.bar", "chart.pie", "dollarsign.circle", "bitcoinsign.circle", "calendar", "clock", "envelope", "bubble.left",
        "person.2", "graduationcap", "book", "doc.text", "newspaper", "photo", "camera", "film",
        "music.note", "waveform", "hifispeaker", "guitars", "mic", "headphones", "gamecontroller", "paintbrush",
        "iphone", "laptopcomputer", "applewatch", "tv", "wifi", "lock", "shield", "key",
    ]
}
