import Foundation
import Testing
@testable import LucidBoard

struct AppRepositoryFactoryTests {

    @Test func makeLocalAPIWhenBackendKindIsLocal() {
        let repo = AppRepositoryFactory.make(
            backendKind: "local",
            localAPIBaseURL: "http://127.0.0.1:8000",
            tokenStore: InMemoryTokenStore()
        )
        #expect(repo is LocalAPIRepository)
    }

    @Test func makeSupabaseByDefault() {
        let repo = AppRepositoryFactory.make(
            backendKind: "supabase",
            localAPIBaseURL: "http://127.0.0.1:8000",
            tokenStore: InMemoryTokenStore()
        )
        #expect(repo is SupabaseRepository)
    }
}
