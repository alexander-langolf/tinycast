import Foundation

/// A built-in theme, mapped by `ForkVSCodeTheme` from its official file; sources are in docs.
struct ForkColorThemePreset: Identifiable, Sendable {
    let id: String
    let name: String
    let slots: [ForkColorTheme.Slot: ForkThemeValue.Color]
    /// Normal then bright: black, red, green, yellow, blue, magenta, cyan, white.
    let ansi: [ForkThemeValue.Color]

    private init(_ id: String, _ name: String, slots: [UInt32], ansi: [UInt32]) {
        self.id = id
        self.name = name
        self.slots = Dictionary(
            uniqueKeysWithValues: zip(ForkColorTheme.Slot.allCases, slots.map(ForkThemeValue.Color.hex)))
        self.ansi = ansi.map(ForkThemeValue.Color.hex)
    }

    static let all: [ForkColorThemePreset] = [
        // Marketplace GitHub.github-vscode-theme 6.3.5, themes/dark-default.json
        .init(
            "github-dark", "GitHub Dark",
            slots: [
                0x0D1117, 0x010409, 0xE6EDF3, 0x7D8590, 0x2F81F7, 0x30363D, 0x3FB950, 0xD29922, 0xFF7B72,
                0x010409
            ],
            ansi: [
                0x484F58, 0xFF7B72, 0x3FB950, 0xD29922, 0x58A6FF, 0xBC8CFF, 0x39C5CF, 0xB1BAC4,
                0x6E7681, 0xFFA198, 0x56D364, 0xE3B341, 0x79C0FF, 0xD2A8FF, 0x56D4DD, 0xFFFFFF
            ]),
        // Marketplace GitHub.github-vscode-theme 6.3.5, themes/light-default.json
        .init(
            "github-light", "GitHub Light",
            slots: [
                0xFFFFFF, 0xF6F8FA, 0x1F2328, 0x656D76, 0x0969DA, 0xD0D7DE, 0x116329, 0x4D2D00, 0xCF222E,
                0xF6F8FA
            ],
            ansi: [
                0x24292F, 0xCF222E, 0x116329, 0x4D2D00, 0x0969DA, 0x8250DF, 0x1B7C83, 0x6E7781,
                0x57606A, 0xA40E26, 0x1A7F37, 0x633C01, 0x218BFF, 0xA475F9, 0x3192AA, 0x8C959F
            ]),
        // https://raw.githubusercontent.com/ayu-theme/vscode-ayu/master/ayu-dark.json
        .init(
            "ayu-dark", "Ayu Dark",
            slots: [
                0x10141C, 0x0D1017, 0xBFBDB6, 0x5A6378, 0xE6B450, 0x1B1F29, 0x70BF56, 0xE6B450, 0xD95757,
                0x0D1017
            ],
            ansi: [
                0x1B1F29, 0xF06B73, 0x70BF56, 0xFDB04C, 0x4FBFFF, 0xD0A1FF, 0x93E2C8, 0xC7C7C7,
                0x686868, 0xF07178, 0xAAD94C, 0xFFB454, 0x59C2FF, 0xD2A6FF, 0x95E6CB, 0xFFFFFF
            ]),
        // https://raw.githubusercontent.com/ayu-theme/vscode-ayu/master/ayu-mirage.json
        .init(
            "ayu-mirage", "Ayu Mirage",
            slots: [
                0x242936, 0x1F2430, 0xCCCAC2, 0x707A8C, 0xFFCC66, 0x171B24, 0x87D96C, 0xFFCC66, 0xFF6666,
                0x1F2430
            ],
            ansi: [
                0x171B24, 0xF28273, 0x87D96C, 0xFCCA60, 0x6ACDFF, 0xDDBBFF, 0x93E2C8, 0xC7C7C7,
                0x686868, 0xF28779, 0xD5FF80, 0xFFCD66, 0x73D0FF, 0xDFBFFF, 0x95E6CB, 0xFFFFFF
            ]),
        // https://raw.githubusercontent.com/ayu-theme/vscode-ayu/master/ayu-light.json
        .init(
            "ayu-light", "Ayu Light",
            slots: [
                0xFCFCFC, 0xF8F9FA, 0x5C6166, 0x828E9F, 0xF29718, 0xEAEDEF, 0x6CBF43, 0xF29718, 0xE65050,
                0xF8F9FA
            ],
            ansi: [
                0x000000, 0xF06B6C, 0x6CBF43, 0xE7A100, 0x21A1E2, 0xA176CB, 0x4ABC96, 0xC7C7C7,
                0x686868, 0xF07171, 0x86B300, 0xEBA400, 0x22A4E6, 0xA37ACC, 0x4CBF99, 0xD1D1D1
            ]),
        // Marketplace Equinusocio.vsc-material-theme 34.7.16, Material-Theme-Default.json
        .init(
            "material", "Material",
            slots: [
                0x263238, 0x263238, 0xEEFFFF, 0x465A64, 0x80CBC4, 0x263238, 0xC3E88D, 0xFFCB6B, 0xF07178,
                0x263238
            ],
            ansi: [
                0x000000, 0xF07178, 0xC3E88D, 0xFFCB6B, 0x82AAFF, 0xC792EA, 0x89DDFF, 0xFFFFFF,
                0x546E7A, 0xF07178, 0xC3E88D, 0xFFCB6B, 0x82AAFF, 0xC792EA, 0x89DDFF, 0xFFFFFF
            ]),
        // Cursor 3.22.7 app bundle: extensions/theme-cursor/themes/cursor-dark-color-theme.json
        .init(
            "cursor-dark", "Cursor Dark",
            slots: [
                0x181818, 0x141414, 0xF0F0F0, 0x666666, 0x81A1C1, 0x282828, 0x3FA266, 0xF1B467, 0xE34671,
                0x141414
            ],
            ansi: [
                0x242424, 0xFC6B83, 0x3FA266, 0xD2943E, 0x81A1C1, 0xB48EAD, 0x88C0D0, 0xF0F0F0,
                0x989898, 0xFC6B83, 0x70B489, 0xF1B467, 0x87A6C4, 0xB48EAD, 0x88C0D0, 0xFFFFFF
            ]),
        // Marketplace monokai.theme-monokai-pro-vscode 2.0.16, themes/Monokai Pro.json
        .init(
            "monokai-pro", "Monokai Pro",
            slots: [
                0x2D2A2E, 0x221F22, 0xFCFCFA, 0x939293, 0xFFD866, 0x19181A, 0xA9DC76, 0xFC9867, 0xFF6188,
                0x403E41
            ],
            ansi: [
                0x403E41, 0xFF6188, 0xA9DC76, 0xFFD866, 0xFC9867, 0xAB9DF2, 0x78DCE8, 0xFCFCFA,
                0x727072, 0xFF6188, 0xA9DC76, 0xFFD866, 0xFC9867, 0xAB9DF2, 0x78DCE8, 0xFCFCFA
            ])
    ]
}
