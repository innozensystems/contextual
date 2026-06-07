import SwiftUI

struct OnboardingView: View {
    @State private var currentPage = 0
    @State private var showHome = false

    var body: some View {
        if showHome {
            HomeView()
        } else {
            TabView(selection: $currentPage) {
                OnboardingPage(
                    icon: "brain.head.profile",
                    title: "Never forget an errand again",
                    description: "Contextual reminds you of tasks when you're near the right place — so you never have to remember.",
                    color: .accentColor
                )
                .tag(0)

                OnboardingPage(
                    icon: "location.circle.fill",
                    title: "Smart location reminders",
                    description: "We use your location to remind you at the right place. Your data stays on your device.",
                    color: .green
                )
                .tag(1)

                OnboardingPage(
                    icon: "bell.badge.fill",
                    title: "Only the right notifications",
                    description: "We'll only notify you when you're near something you need to do. No spam, ever.",
                    color: .orange
                )
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .overlay(alignment: .bottom) {
                if currentPage == 2 {
                    Button("Get Started") {
                        requestPermissions()
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .clipShape(Capsule())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private func requestPermissions() {
        GeofenceService.shared.requestAuthorization()
        NotificationService.shared.requestAuthorization()
        showHome = true
    }
}

struct OnboardingPage: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 80))
                .foregroundStyle(color)

            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }
}
