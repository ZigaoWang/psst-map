import SwiftUI

extension View {
    /// Opens a place full screen, zooming out of the view marked with `placeZoomSource` on iOS 18 and later.
    /// Swipe down to close. Earlier versions get a regular sheet.
    func placePresentation(_ place: Binding<Place?>, namespace: Namespace.ID, showsMapButton: Bool = true) -> some View {
        modifier(PlacePresentationModifier(place: place, namespace: namespace, showsMapButton: showsMapButton))
    }

    /// Marks the view a place zooms out of when it opens.
    @ViewBuilder
    func placeZoomSource(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}

private struct PlacePresentationModifier: ViewModifier {
    @Binding var place: Place?
    let namespace: Namespace.ID
    let showsMapButton: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.fullScreenCover(item: $place) { place in
                SpotDetailView(place: place, showsMapButton: showsMapButton)
                    .navigationTransition(.zoom(sourceID: place.id, in: namespace))
            }
        } else {
            content.sheet(item: $place) { place in
                SpotDetailView(place: place, showsMapButton: showsMapButton)
                    .presentationDragIndicator(.visible)
            }
        }
    }
}
