//
//  HeaderView.swift
//  diplomski
//
//  Created by Karlo Šibalić on 22.04.2026..
//

import SwiftUI

struct HeaderView: View {
    @Environment(\.theme) var theme
    
    var body: some View {
        HStack {
            Spacer()
            Text("RUSHGUARD")
                .font(theme.typography.labelMedium)
                .foregroundColor(theme.colors.primaryContainer)
                .tracking(2)
            Spacer()
        }
    }
}
#Preview {
    HeaderView()
}
