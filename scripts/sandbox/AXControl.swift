import ApplicationServices
let pid = Int32(CommandLine.arguments[1])!
let target = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(target, 0.5)
print("trusted=\(AXIsProcessTrusted())")
for attribute in [kAXFocusedWindowAttribute, kAXFocusedUIElementAttribute] {
    var element: CFTypeRef?
    print("\(attribute)=\(AXUIElementCopyAttributeValue(target, attribute as CFString, &element).rawValue)")
}
