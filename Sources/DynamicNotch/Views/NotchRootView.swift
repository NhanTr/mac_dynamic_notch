import NotchCore
import SwiftUI
import UniformTypeIdentifiers

/// Root SwiftUI view hosted in a `NotchPanel`.
///
/// The panel never resizes; the black notch shape morphs smoothly across
/// `.closed`, `.compact`, `.peek`, and `.open` states.
struct NotchRootView: View {
    let viewModel: NotchViewModel

    private static let openAnimation = Animation.spring(response: 0.40, dampingFraction: 0.80)
    private static let closeAnimation = Animation.spring(response: 0.34, dampingFraction: 0.92)

    private var layout: NotchLayout { viewModel.layout }
    private var state: NotchState { viewModel.state }

    var body: some View {
        let size = layout.shapeSize(for: state)
        let topRadius = layout.topRadius(for: state)
        let bottomRadius = layout.bottomRadius(for: state)
        let shape = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)

        ZStack(alignment: .top) {
            shape
                .fill(.black)
                .frame(width: size.width, height: size.height)
                .shadow(
                    color: .black.opacity(state == .open || state == .peek ? 0.52 : 0),
                    radius: state == .open ? 14 : 8,
                    y: state == .open ? 6 : 3
                )

            Group {
                switch state {
                case .closed:
                    EmptyView()

                case .compact:
                    if let item = viewModel.nowPlayingService.currentItem {
                        NotchCompactView(
                            item: item,
                            notchWidth: layout.geometry.size.width,
                            wingWidth: layout.style.compactWingWidth,
                            topRadius: topRadius
                        )
                        .frame(width: size.width, height: size.height)
                        .transition(.opacity)
                    }

                case .peek:
                    if let hud = viewModel.activeHUD {
                        NotchPeekHUDView(event: hud)
                            .padding(.top, layout.geometry.size.height)
                            .padding(.horizontal, topRadius + 6)
                            .frame(width: size.width, height: size.height, alignment: .top)
                            .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
                    }

                case .open:
                    NotchExpandedView(viewModel: viewModel)
                        .padding(.top, layout.geometry.size.height)
                        .padding(.horizontal, topRadius + 14)
                        .padding(.bottom, 12)
                        .frame(width: size.width, height: size.height, alignment: .top)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top))
                                    .animation(Self.openAnimation.delay(0.04)),
                                removal: .opacity.animation(.easeOut(duration: 0.12))
                            )
                        )
                }
            }
            .clipShape(shape)
        }
        .frame(width: layout.panelSize.width, height: layout.panelSize.height, alignment: .top)
        .animation(state == .open ? Self.openAnimation : Self.closeAnimation, value: state)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            viewModel.selectedTab = .shelf
            viewModel.open()
            return viewModel.shelfService.handleDrop(providers: providers)
        }
        .preferredColorScheme(.dark)
    }
}
