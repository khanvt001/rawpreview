//
//  RatingStarsView.swift
//  rawpreview
//

import SwiftUI

/// Read-only row of filled / empty stars.
struct RatingStarsView: View {
    let rating: Rating
    var size: CGFloat = 9

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...Rating.maxStars, id: \.self) { star in
                Image(systemName: star <= rating.rawValue ? "star.fill" : "star")
                    .opacity(star <= rating.rawValue ? 1 : 0.4)
            }
        }
        .font(.system(size: size, weight: .semibold))
        .foregroundStyle(.yellow)
        .accessibilityElement()
        .accessibilityLabel("\(rating.rawValue) of \(Rating.maxStars) stars")
    }
}

#Preview {
    RatingStarsView(rating: Rating(3), size: 14)
        .padding()
        .background(.black)
}
