import SwiftUI

/// The entry point lives apart from `BrisaApp` so `Scripts/test.sh` can compile every other source file into the test runner.
@main
enum BrisaMain {
    static func main() { BrisaApp.main() }
}
