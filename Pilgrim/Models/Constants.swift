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

    public enum Seasonal {
        static let springPeakDay: Int = 105
        static let summerPeakDay: Int = 196
        static let autumnPeakDay: Int = 288
        static let winterPeakDay: Int = 15

        static let spread: CGFloat = 91

        static let springHue: CGFloat = 0.02
        static let summerHue: CGFloat = 0.01
        static let autumnHue: CGFloat = 0.03
        static let winterHue: CGFloat = -0.02

        static let springSaturation: CGFloat = 0.10
        static let summerSaturation: CGFloat = 0.15
        static let autumnSaturation: CGFloat = 0.05
        static let winterSaturation: CGFloat = -0.15

        static let springBrightness: CGFloat = 0.05
        static let summerBrightness: CGFloat = 0.03
        static let autumnBrightness: CGFloat = -0.03
        static let winterBrightness: CGFloat = -0.05
    }

    public enum Typography {
        public static let displayLarge: Font = .custom("CormorantGaramond-Light", size: 34)
        public static let displayMedium: Font = .custom("CormorantGaramond-Light", size: 28)
        public static let heading: Font = .custom("CormorantGaramond-SemiBold", size: 17)
        public static let timer: Font = .custom("Lato-Regular", size: 48)
        public static let statValue: Font = .custom("Lato-Regular", size: 20)
        public static let statLabel: Font = .custom("Lato-Regular", size: 12)
        public static let body: Font = .custom("CormorantGaramond-Regular", size: 17)
        public static let button: Font = .custom("Lato-Bold", size: 17)
        public static let caption: Font = .custom("Lato-Regular", size: 12)
        public static let annotation: Font = .custom("CormorantGaramond-Regular", size: 11)
        public static let micro: Font = .custom("Lato-Regular", size: 9)
        public static let microBold: Font = .custom("Lato-Bold", size: 9)
    }
}
