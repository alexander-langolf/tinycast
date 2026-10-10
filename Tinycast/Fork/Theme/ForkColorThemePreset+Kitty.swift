import Foundation

/// Themes from kitty-themes, mapped onto the ten slots, and each one's inverted twin.
///
/// An inverted twin keeps the theme's own pair: its foreground becomes the background and its
/// background the text. Every other colour keeps its hue and chroma and moves in lightness until it
/// stands out from the new background as much as it did before (UI colours 3–4.5:1, terminal
/// colours 3–6:1, greys exactly). `Scripts/fork-theme-invert.py` regenerates this file.
extension ForkColorThemePreset {
    static let kitty: [ForkColorThemePreset] = [
        // kitty-themes c9be61857a09, themes/yorumi-kraken.conf
        .init(
            "yorumi-kraken", "Yorumi Kraken", group: .kitty,
            slots: [
                0x0E0D17, 0x1D202B, 0xC0BCE6, 0x797693, 0xAD8FD6, 0x343742, 0xA9D07C, 0xE1C084, 0xF47571,
                0x0E0D17
            ],
            ansi: [
                0x0E121F, 0x913B3B, 0x697F4D, 0x9D672F, 0x42608A, 0x614686, 0x478584, 0xA7A9B5,
                0x343742, 0xF47571, 0xA9D07C, 0xE1C084, 0x798DDC, 0xAD8FD6, 0x85E0CB, 0xC0BCE6
            ]),
        // kitty-themes c9be61857a09, themes/yorumi-abyss.conf
        .init(
            "yorumi-abyss", "Yorumi Abyss", group: .kitty,
            slots: [
                0x060914, 0x121520, 0xBDBFCB, 0x747682, 0x798DDC, 0x1D202B, 0x8CB167, 0xC39D55, 0xF47571,
                0x060914
            ],
            ansi: [
                0x060914, 0xC65E53, 0x8CB167, 0xC39D55, 0x597BC0, 0xBB5D7D, 0x67BBB9, 0xBDBFCB,
                0x343742, 0xF47571, 0xA9D07C, 0xE1C084, 0x798DDC, 0xE184AF, 0x85E0CB, 0xD7E1B7
            ]),
        // kitty-themes c9be61857a09, themes/WildCherry.conf
        .init(
            "wild-cherry", "Wild Cherry", group: .kitty,
            slots: [
                0x1F1626, 0x2A2433, 0xD9FAFF, 0x8F9FA8, 0xDD00FF, 0x3D3A49, 0x2AB250, 0xFFD06E, 0xD94085,
                0x1F1626
            ],
            ansi: [
                0x000506, 0xD94085, 0x2AB250, 0xFFD06E, 0x873BDB, 0xECECEC, 0xC1B8B6, 0xFFF8DD,
                0x009CC9, 0xDA6BAB, 0xF4DBA5, 0xEAC066, 0x2F8BB9, 0xAE636B, 0xFF919D, 0xE4838D
            ]),
        // kitty-themes c9be61857a09, themes/vague.conf
        .init(
            "vague", "Vague", group: .kitty,
            slots: [
                0x141415, 0x252530, 0xCDCDCD, 0x838383, 0xBB9DBD, 0x323232, 0x7FA563, 0xF3BE7C, 0xD8647E,
                0x141415
            ],
            ansi: [
                0x252530, 0xD8647E, 0x7FA563, 0xF3BE7C, 0x6E94B2, 0xBB9DBD, 0xAEAED1, 0xCDCDCD,
                0x606079, 0xE08398, 0x99B782, 0xF5CB96, 0x8BA9C1, 0xC9B1CA, 0xBEBEDA, 0xD7D7D7
            ]),
        // kitty-themes c9be61857a09, themes/Terafox.conf
        .init(
            "terafox", "Terafox", group: .kitty,
            slots: [
                0x152528, 0x293E40, 0xE6EAEA, 0x929B9C, 0x5A93AA, 0x2D4F56, 0x7AA4A1, 0xFDA47F, 0xE85C51,
                0x152528
            ],
            ansi: [
                0x2F3239, 0xE85C51, 0x7AA4A1, 0xFDA47F, 0x5A93AA, 0xAD5C7C, 0xA1CDD8, 0xEBEBEB,
                0x4E5157, 0xEB746B, 0x8EB2AF, 0xFDB292, 0x73A3B7, 0xB97490, 0xAFD4DE, 0xEEEEEE
            ]),
        // kitty-themes c9be61857a09, themes/tender.conf
        .init(
            "tender", "Tender", group: .kitty,
            slots: [
                0x282828, 0x303030, 0xEEEEEE, 0x9F9F9F, 0x73CEF4, 0x4C4C4C, 0xC9D05C, 0xFFC24B, 0xF43753,
                0x282828
            ],
            ansi: [
                0x282828, 0xF43753, 0xC9D05C, 0xFFC24B, 0xB3DEEF, 0xD3B987, 0x73CEF4, 0xEEEEEE,
                0x4C4C4C, 0xF43753, 0xC9D05C, 0xFFC24B, 0xB3DEEF, 0xD3B987, 0x73CEF4, 0xFEFFFF
            ]),
        // kitty-themes c9be61857a09, themes/shadotheme.conf
        // success, warning synthesised: the palette has no such hue
        .init(
            "shadotheme", "shadotheme", group: .kitty,
            slots: [
                0x191724, 0x140A1D, 0xE3C7FC, 0x9281A6, 0xBD93F9, 0x393347, 0x4FB257, 0xCD8A02, 0xFF4971,
                0x191724
            ],
            ansi: [
                0x140A1D, 0xB52A5B, 0xFF4971, 0x8897F4, 0xBD93F9, 0xE9729D, 0xF18FB0, 0xF1C4E0,
                0xA8899C, 0xB52A5B, 0xFF4971, 0x8897F4, 0xBD93F9, 0xE9729D, 0xF18FB0, 0xF1C4E0
            ]),
        // kitty-themes c9be61857a09, themes/Serendipity_Midnight.conf
        // success, warning synthesised: the palette has no such hue
        .init(
            "serendipity-midnight", "Serendipity Midnight", group: .kitty,
            slots: [
                0x151726, 0x232534, 0xDEE0EF, 0x8E909F, 0x94B8FF, 0x353746, 0x7FBF81, 0xD5A258, 0xEE8679,
                0x151726
            ],
            ansi: [
                0x232534, 0xEE8679, 0x5BA2D0, 0xA78BFA, 0x94B8FF, 0x9CCFD8, 0xF8D2C9, 0xDEE0EF,
                0x8D8F9E, 0xEE8679, 0x5BA2D0, 0xA78BFA, 0x94B8FF, 0x9CCFD8, 0xF8D2C9, 0xDEE0EF
            ]),
        // kitty-themes c9be61857a09, themes/SeaShells.conf
        // success synthesised: the palette has no such hue
        .init(
            "sea-shells", "Sea Shells", group: .kitty,
            slots: [
                0x08131A, 0x151D21, 0xDEB88D, 0x88765F, 0xFBA02F, 0x17384C, 0x85B886, 0xFBA02F, 0xD05023,
                0x08131A
            ],
            ansi: [
                0x17384C, 0xD05023, 0x027B9B, 0xFBA02F, 0x1D4850, 0x68D3F0, 0x50A3B5, 0xDEB88D,
                0x424B52, 0xD38677, 0x618C98, 0xFDD29E, 0x1ABCDD, 0xBBE3EE, 0x86ABB3, 0xFEE3CD
            ]),
        // kitty-themes c9be61857a09, themes/rose-pine.conf
        .init(
            "rose-pine", "Rosé Pine", group: .kitty,
            slots: [
                0x191724, 0x26233A, 0xE0DEF4, 0x908EA1, 0xC4A7E7, 0x403D52, 0x9CCFD8, 0xF6C177, 0xEB6F92,
                0x191724
            ],
            ansi: [
                0x26233A, 0xEB6F92, 0x31748F, 0xF6C177, 0x9CCFD8, 0xC4A7E7, 0xEBBCBA, 0xE0DEF4,
                0x6E6A86, 0xEB6F92, 0x31748F, 0xF6C177, 0x9CCFD8, 0xC4A7E7, 0xEBBCBA, 0xE0DEF4
            ]),
        // kitty-themes c9be61857a09, themes/BlulocoLight.conf
        .init(
            "bluloco-light", "Bluloco Light", group: .kitty,
            slots: [
                0xF9F9F9, 0xECECEC, 0x373A41, 0x85868B, 0x275FE4, 0xD3D3D3, 0x23974A, 0xDF631C, 0xD52753,
                0xF9F9F9
            ],
            ansi: [
                0x373A41, 0xD52753, 0x23974A, 0xDF631C, 0x275FE4, 0x823FF1, 0x27618D, 0xBABBC2,
                0x676A77, 0xFF6480, 0x3CBC66, 0xC5A332, 0x0099E1, 0xCE33C0, 0x6D93BB, 0xD3D3D3
            ])
    ]

    static let kittyInverted: [ForkColorThemePreset] = [
        // Yorumi Kraken inverted by Scripts/fork-theme-invert.py
        .init(
            "yorumi-kraken-inverted", "Yorumi Kraken Inverted", group: .inverted,
            slots: [
                0xC0BCE6, 0xB5B1DA, 0x0E0D17, 0x4F4C67, 0x75589A, 0xA09CC1, 0x3A5808, 0x674A06, 0x991F26,
                0xC0BCE6
            ],
            ansi: [
                0xB7BDD0, 0xA74F4D, 0x435827, 0x7D4A09, 0x4C6B96, 0x785D9F, 0x145757, 0x252630,
                0x9296A3, 0x991F26, 0x3A5808, 0x674A06, 0x3B4A92, 0x5F4282, 0x055A4C, 0x100927
            ]),
        // Yorumi Abyss inverted by Scripts/fork-theme-invert.py
        .init(
            "yorumi-abyss-inverted", "Yorumi Abyss Inverted", group: .inverted,
            slots: [
                0xBDBFCB, 0xB2B4C0, 0x060914, 0x4C4E59, 0x4F60AB, 0x9C9EAA, 0x385807, 0x674A03, 0x981E25,
                0xBDBFCB
            ],
            ansi: [
                0xB9C0D1, 0x892620, 0x294402, 0x4F3905, 0x2B4989, 0x842B4E, 0x064443, 0x080911,
                0x8F93A0, 0x981E25, 0x3A5707, 0x674A05, 0x3B4992, 0x84305B, 0x04594C, 0x030400
            ]),
        // Wild Cherry inverted by Scripts/fork-theme-invert.py
        .init(
            "wild-cherry-inverted", "Wild Cherry Inverted", group: .inverted,
            slots: [
                0xD9FAFF, 0xCEEEF3, 0x1F1626, 0x4C5B63, 0xDF2CFF, 0xB8D1D8, 0x008231, 0x8F6A0A, 0xD1387E,
                0xD9FAFF
            ],
            ansi: [
                0xD5E6E8, 0xD1387E, 0x076C29, 0x76580C, 0xA96CFB, 0x5D5D5D, 0x635B59, 0x1B1602,
                0x0C6B8A, 0xB44889, 0x846D3A, 0x8E6B10, 0x1278A5, 0xAE636B, 0xB54F5D, 0x913946
            ]),
        // Vague inverted by Scripts/fork-theme-invert.py
        .init(
            "vague-inverted", "Vague Inverted", group: .inverted,
            slots: [
                0xCDCDCD, 0xC2C2C2, 0x141415, 0x535353, 0x816583, 0xACACAC, 0x3E6120, 0x7A4E03, 0x9D2E4D,
                0xCDCDCD
            ],
            ansi: [
                0xB9B9C8, 0x902143, 0x2D4E09, 0x623E01, 0x284C66, 0x563D58, 0x434360, 0x141414,
                0x70708A, 0x903B52, 0x455F2E, 0x75511C, 0x3F5B70, 0x665167, 0x56566E, 0x050505
            ]),
        // Terafox inverted by Scripts/fork-theme-invert.py
        .init(
            "terafox-inverted", "Terafox Inverted", group: .inverted,
            slots: [
                0xE6EAEA, 0xDBDEDE, 0x152528, 0x555D5E, 0x5089A0, 0xC0C7C7, 0x48716E, 0xA4532F, 0xC13730,
                0xE6EAEA
            ],
            ansi: [
                0xCFD3DC, 0xBF352F, 0x38605E, 0x8E3F1B, 0x356E84, 0xB46282, 0x335D66, 0x212121,
                0xA4A7AE, 0xB5433E, 0x4E706D, 0x9B583A, 0x417082, 0x975571, 0x4D6F78, 0x1F1F1F
            ]),
        // Tender inverted by Scripts/fork-theme-invert.py
        .init(
            "tender-inverted", "Tender Inverted", group: .inverted,
            slots: [
                0xEEEEEE, 0xE2E2E2, 0x282828, 0x5E5E5E, 0x2E8EB2, 0xCACACA, 0x6D710A, 0x8E6506, 0xE52447,
                0xEEEEEE
            ],
            ansi: [
                0xEEEEEE, 0xE52447, 0x5A5D0B, 0x755408, 0x375F6E, 0x6D5626, 0x05617E, 0x282828,
                0xB8B8B8, 0xE52447, 0x6D710A, 0x8E6506, 0x4A7281, 0x816939, 0x127596, 0x1B1C1C
            ]),
        // shadotheme inverted by Scripts/fork-theme-invert.py
        .init(
            "shadotheme-inverted", "shadotheme Inverted", group: .inverted,
            slots: [
                0xE2C8F8, 0xD6BDEC, 0x191724, 0x5E4E70, 0x875DBE, 0xBDA8D2, 0x0E6A1E, 0x7B530B, 0xB60542,
                0xE2C8F8
            ],
            ansi: [
                0xD1C4E0, 0xCD436F, 0x9F0639, 0x393F94, 0x5D328F, 0x8A184C, 0x7F284C, 0x2E0E24,
                0x604455, 0xCD436F, 0xB60542, 0x4953A9, 0x7045A4, 0xA0305F, 0x953C5E, 0x2E0E24
            ]),
        // Serendipity Midnight inverted by Scripts/fork-theme-invert.py
        .init(
            "serendipity-midnight-inverted", "Serendipity Midnight Inverted", group: .inverted,
            slots: [
                0xDEE0EF, 0xD3D5E3, 0x151726, 0x545563, 0x5A7BBD, 0xBABCCB, 0x337137, 0x885B07, 0xA6463C,
                0xDEE0EF
            ],
            ansi: [
                0xCCD0E4, 0x90322A, 0x09577E, 0x5D3DA4, 0x32508E, 0x275861, 0x694A43, 0x161722,
                0x545664, 0xA6463C, 0x1F6A95, 0x6F51BA, 0x4463A3, 0x3B6B74, 0x7D5D55, 0x161722
            ]),
        // Sea Shells inverted by Scripts/fork-theme-invert.py
        .init(
            "sea-shells-inverted", "Sea Shells Inverted", group: .inverted,
            slots: [
                0xDDB88E, 0xD2AD84, 0x08131A, 0x5C4B35, 0x905706, 0xB79A7A, 0x28582B, 0x724301, 0x912F08,
                0xDDB88E
            ],
            ansi: [
                0x7B9EB6, 0x912F08, 0x096079, 0x583303, 0x446F77, 0x05424F, 0x05424D, 0x1D0F00,
                0x78828A, 0x7E392D, 0x2A545F, 0x6B4711, 0x065666, 0x2F535D, 0x31535A, 0x090200
            ]),
        // Rosé Pine inverted by Scripts/fork-theme-invert.py
        .init(
            "rose-pine-inverted", "Rosé Pine Inverted", group: .inverted,
            slots: [
                0xE0DEF4, 0xD5D3E8, 0x191724, 0x565465, 0x8B6FAB, 0xBCBACF, 0x3A6B73, 0x885B07, 0xAE385F,
                0xE0DEF4
            ],
            ansi: [
                0xD0CEEC, 0x98214C, 0x3D7F9A, 0x6F4A07, 0x275860, 0x60457E, 0x6E4746, 0x191726,
                0x777390, 0xAE385F, 0x3D7F9A, 0x885B07, 0x3A6B73, 0x735892, 0x825958, 0x191726
            ]),
        // Bluloco Light inverted by Scripts/fork-theme-invert.py
        .init(
            "bluloco-light-inverted", "Bluloco Light Inverted", group: .inverted,
            slots: [
                0x373A41, 0x31343A, 0xF9F9F9, 0xA1A3A7, 0x4B82FB, 0x5A5C62, 0x34A456, 0xE36621, 0xFC7A8B,
                0x373A41
            ],
            ansi: [
                0xF7F9FF, 0xFD8090, 0x34A456, 0xE36621, 0x88AFFC, 0xB59FFD, 0x87C2F3, 0x5F6066,
                0xAAADBB, 0xE44B6A, 0x0E9748, 0x9D8015, 0x118ACA, 0xF55DE5, 0x6287AF, 0x505050
            ])
    ]
}
