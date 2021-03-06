import Foundation

func measure(_ block: () -> Void) {
    let iterations = 100
    let startDate = Date()

    for _ in 1...iterations {
        block()
    }

    print(abs(startDate.timeIntervalSinceNow) * 1000000 / Double(iterations))
}
