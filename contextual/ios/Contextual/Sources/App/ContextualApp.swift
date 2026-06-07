import SwiftUI

@main
struct ContextualApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var supabase = SupabaseService.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if supabase.isAuthenticated {
                if hasCompletedOnboarding {
                    HomeView()
                } else {
                    OnboardingView()
                }
            } else {
                AuthView()
            }
        }
        .task {
            await supabase.initializeSession()
        }
    }
}

struct AuthView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundStyle(.accent)

            Text("Contextual")
                .font(.largeTitle.bold())

            Text("Never forget an errand again")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(action: authenticate) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(isSignUp ? "Create Account" : "Sign In")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .clipShape(Capsule())
            .disabled(email.isEmpty || password.isEmpty || isLoading)

            Button(isSignUp ? "Already have an account?" : "Need an account?") {
                isSignUp.toggle()
                errorMessage = nil
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private func authenticate() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                if isSignUp {
                    try await SupabaseService.shared.signUp(email: email, password: password)
                } else {
                    try await SupabaseService.shared.signIn(email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationService.shared
        return true
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        // Handle deep links from partner invites
        if let url = userActivity.webpageURL {
            handleDeepLink(url)
        }
        return true
    }

    private func handleDeepLink(_ url: URL) {
        // Parse invite token and navigate to list
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value else {
            return
        }
        // In production: call SupabaseService.shared.acceptInvite(token: token)
        #if DEBUG
        print("Deep link token: \(token)")
        #endif
    }
}
