import Foundation

 let array = [{0,0,0,1}, {0,0,1,0}, {0,1,0,0}, {0,1,1,1}, {0,1,1,1}]
 array[2]

//var nativeArray: [Any] = [Data].trueArray()
//var nsArray = NSArray.trueArray()
//
//let randomIndecies = (1...1000).map { _ in Int.random(in: 1...500000) }

//measure {
//    for i in randomIndecies {
//        _ = nativeArray[i]
//    }
//}
//
//measure {
//    for i in randomIndecies {
//        _ = nsArray[i]
//    }
//}


////-----------------------------------------======================-------------------------------------------

var nativeArray: [Data] = []
var nsArray = NSArray.trueArray()

let randomIndecies = (1...1000).map { _ in Int.random(in: 1...500000) }

var sum = 0
print("1")
readLine()
nativeArray = nsArray as! [Data]
var array1 = nativeArray.compactMap { NSData(data: $0) }
print("3")
readLine()
var array2 = array1
print("4")
readLine()
array2[20] = NSData()
print("5")
readLine()

////-----------------------------------------======================-------------------------------------------
//
//
//
//
//
//
//
//
//
//
//
//
//
//
//
//readLine()
//
//print("1")
//
//var array1 = [Data].trueArray()
//
//print("2")
//readLine()
//
//var array2 = array1
//
//print("3")
//readLine()
//
//array2[290] = Data()
//
//print("4")
//readLine()

//
//
//
//
//
//
//
//
//
//
//
//
//
//
//
//
//
//
//
////-----------------------------------------======================-------------------------------------------
//
//let bigArray = [Data].trueArray()
//
//
//measure {
//    let offset = Int.random(in: 0...10000)
//    let slice = bigArray[offset...(offset+1000)]
//
//    for e in slice {
//
//    }
//}
//
//
//
//
//
//
//
//
//
//

//
//
//
//
//
//

////-----------------------------------------======================-------------------------------------------
//
//var neededData: ArraySlice<Data> = []
//
//func process(array: [Data]) {
//    neededData = array[100...300]
//}
//
//autoreleasepool {
//    process(array: .trueArray())
//}
//
//readLine()

// [1,2,3,4] capacity = 4
// append(5)
// [1,2,3,4,5,0,0,0]


// [1,2,3,4] [10,11,12,17]
