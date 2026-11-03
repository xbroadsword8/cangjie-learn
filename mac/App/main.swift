import Cocoa
import InputMethodKit

let connectionName = Bundle.main.infoDictionary!["InputMethodConnectionName"] as! String
let server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
_ = server
NSApplication.shared.run()
