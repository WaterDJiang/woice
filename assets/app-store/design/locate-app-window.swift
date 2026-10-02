#!/usr/bin/swift

import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("用法：locate-app-window.swift <应用显示名>\n".utf8))
    exit(64)
}

let ownerName = arguments[1]
guard
    let rawWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0)
        as? [[CFString: Any]]
else {
    fatalError("无法读取窗口列表")
}

let candidates: [(id: CGWindowID, bounds: CGRect)] = rawWindows.compactMap { info in
    guard
        info[kCGWindowOwnerName] as? String == ownerName,
        (info[kCGWindowLayer] as? NSNumber)?.intValue == 0,
        let number = info[kCGWindowNumber] as? NSNumber,
        let rawBounds = info[kCGWindowBounds]
    else {
        return nil
    }
    let boundsDictionary = rawBounds as! CFDictionary
    guard
        let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
        bounds.width >= 640,
        bounds.height >= 480
    else {
        return nil
    }
    return (CGWindowID(number.uint32Value), bounds)
}

guard let target = candidates.max(by: { lhs, rhs in
    lhs.bounds.width * lhs.bounds.height < rhs.bounds.width * rhs.bounds.height
}) else {
    fatalError("找不到 \(ownerName) 的可见主窗口")
}

print(target.id)

