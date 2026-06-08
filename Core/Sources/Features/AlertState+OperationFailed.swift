import ComposableArchitecture

extension AlertState {
    /// Generic "something went wrong" alert with a single dismiss button, shared
    /// by features that surface a failed database write. The button carries no
    /// action, so this is valid for any alert `Action` type.
    static func operationFailed(_ message: String) -> Self {
        AlertState {
            TextState("Something Went Wrong")
        } actions: {
            ButtonState(role: .cancel) { TextState("OK") }
        } message: {
            TextState(message)
        }
    }
}
