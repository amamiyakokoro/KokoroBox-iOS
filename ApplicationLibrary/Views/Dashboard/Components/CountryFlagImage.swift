import SwiftUI

struct CountryFlagImage: View {
    let countryCode: String
    var size: CGFloat = 24

    private var assetName: String {
        "CircleFlags/\(countryCode.lowercased())"
    }

    var body: some View {
        Image(assetName, bundle: .main)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}
