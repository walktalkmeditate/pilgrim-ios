import Foundation
import CoreGraphics
import SwiftUI

public enum Constants {

    public enum UI {

        public enum Padding {
            public static let xs: CGFloat = 4
            public static let small: CGFloat = 8
            public static let normal: CGFloat = 16
            public static let big: CGFloat = 24
            public static let breathingRoom: CGFloat = 64
        }

        public enum CornerRadius {
            public static let small: CGFloat = 8
            public static let normal: CGFloat = 12
            public static let big: CGFloat = 20
        }

        public enum Motion {
            public static let gentle: Double = 0.6
            public static let breath: Double = 1.2
            public static let appear: Double = 0.4
        }

        public enum Opacity {
            public static let subtle: Double = 0.06
            public static let light: Double = 0.12
            public static let medium: Double = 0.3
        }
    }

    public enum Typography {
        public static let displayLarge: Font = .system(.largeTitle, design: .serif).weight(.light)
        public static let displayMedium: Font = .system(.title, design: .serif).weight(.light)
        public static let heading: Font = .system(.headline, design: .serif)
        public static let timer: Font = .system(size: 48, design: .serif).weight(.thin)
        public static let statValue: Font = .system(.title3, design: .serif)
        public static let statLabel: Font = .system(.caption, design: .rounded)
        public static let body: Font = .system(.body, design: .serif)
        public static let button: Font = .system(.headline, design: .default).weight(.medium)
        public static let caption: Font = .system(.caption)
    }
}
