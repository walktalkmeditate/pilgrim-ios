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
        public static let displayLarge: Font = .custom("CormorantGaramond-Light", size: 34)
        public static let displayMedium: Font = .custom("CormorantGaramond-Light", size: 28)
        public static let heading: Font = .custom("CormorantGaramond-SemiBold", size: 17)
        public static let timer: Font = .custom("CormorantGaramond-Light", size: 48)
        public static let statValue: Font = .custom("CormorantGaramond-Regular", size: 20)
        public static let statLabel: Font = .custom("Lato-Regular", size: 12)
        public static let body: Font = .custom("CormorantGaramond-Regular", size: 17)
        public static let button: Font = .custom("Lato-Bold", size: 17)
        public static let caption: Font = .custom("Lato-Regular", size: 12)
    }
}
