// Copyright (c) 2017 Yandex LLC. All rights reserved.
// Author: Alfred Zien <zienag@yandex-team.ru>

import Foundation
import ArgParse


extension ArgParser {
  func string(at key: String) -> String? {
    return found(key) ? getString(key) : nil
  }
}

struct Args {
  let objcHeader: String?
  let objcPrefix: String?
  let objcImpl: String?
  let objcHeaderImportPath: String?
  let files: [String]
}

func ParseArgs() -> Args {
  let parser = ArgParser(helptext: "Tool for generationg CoreGraphics code from vector images in pdf format",
                         version: "0.1")
  let objcHeaderKey = "objc-header"
  let objcPrefixKey = "objc-prefix"
  let objcImplKey = "objc-impl"
  let objcHeaderImportPathKey = "objc-header-import-path"
  parser.newString(objcHeaderKey)
  parser.newString(objcImplKey)
  parser.newString(objcHeaderImportPathKey)
  parser.newString(objcPrefixKey)
  parser.parse()
  return Args(objcHeader: parser.string(at: objcHeaderKey),
              objcPrefix: parser.string(at: objcPrefixKey) ?? "",
              objcImpl: parser.string(at: objcImplKey),
              objcHeaderImportPath: parser.string(at: objcHeaderImportPathKey),
              files: parser.getArgs())
}

func main(args: Args) {
  let routes = args.files
    .map { URL(fileURLWithPath: $0) }
    .map { ($0.deletingPathExtension().lastPathComponent, parse(pdfURL: $0 as CFURL)) }
    .flatMap { (nameAndRoutes) in
      nameAndRoutes.1.enumerated().flatMap({ (offset, route) -> (String, DrawRoute) in
        let finalName = nameAndRoutes.0 + (offset == 0 ? "" : "_\(offset)")
        return (finalName.snakeToCamelCase(), route)
      })
  }

  let objcPrefix = args.objcPrefix ?? ""

  if let objcHeaderPath = args.objcHeader {
    let headerGenerator = ObjcHeaderCGGenerator(prefix: objcPrefix)
    let fileStr = headerGenerator.generateFile(namesAndRoutes: routes)
    try! fileStr.write(toFile: objcHeaderPath, atomically: true, encoding: .utf8)
  }

  if let objcImplPath = args.objcImpl {
    let headerImportPath = args.objcHeaderImportPath
    let implGenerator = ObjcCGGenerator(prefix: objcPrefix,
                                        headerImportPath: headerImportPath)
    let fileStr = implGenerator.generateFile(namesAndRoutes: routes)
    try! fileStr.write(toFile: objcImplPath, atomically: true, encoding: .utf8)
  }
}

main(args: ParseArgs())
