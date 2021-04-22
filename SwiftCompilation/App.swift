
class App {
    
    var name: String = .init("")
    
    func getName() -> String {
        let appName = "AlfaBank"
        return appName
    }
}

func add(a: Int, b: Int) -> Int {
    if a > 0 {
        let sum = a + b
        return sum
    } else {
        let sum = a - b
        return sum
    }
}
