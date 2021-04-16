//
//  StepsView.swift
//  RunningOrder
//
//  Created by Lucas Barbero on 25/08/2020.
//  Copyright © 2020 Worldline. All rights reserved.
//

import SwiftUI

struct ConfigurationView: View {
    @Binding var storyInformation: StoryInformation
//    @Binding var links: [LinkEntity]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text("Configuration")
                    .font(.title2)
                    .padding(.leading, 10)

                InlineEditableList(title: "Environments", values: $storyInformation.configuration.environments)

                InlineEditableList(title: "Mock", values: $storyInformation.configuration.mocks)

                InlineEditableList(title: "Feature flip", values: $storyInformation.configuration.features)

                InlineEditableList(title: "Indicators", values: $storyInformation.configuration.indicators)

                InlineEditableList(title: "Identifier", values: $storyInformation.configuration.identifiers)

                Text("Links")
                    .font(.title2)
                    .padding(.top, 20)
                    .padding(.leading, 10)

                InlineEditableLinkList(title: "Add a link", values: $storyInformation.configuration.links)

                Spacer()
            }
            .padding(.horizontal, 10)
        }
    }
}

struct StepsView_Previews: PreviewProvider {
    static var previews: some View {
        ConfigurationView(storyInformation: .constant(StoryInformation(storyId: "")))
    }
}
