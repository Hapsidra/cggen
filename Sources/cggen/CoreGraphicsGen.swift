// Copyright (c) 2017 Yandex LLC. All rights reserved.
// Author: Alfred Zien <zienag@yandex-team.ru>

import Base
import Foundation

struct ImageName {
  let snakeCase: String
  let camelCase: String
  init(snakeCase: String) {
    self.snakeCase = snakeCase
    camelCase = snakeCase.snakeToCamelCase()
  }
}

protocol CoreGraphicsGenerator {
  func filePreamble() -> String
  func funcStart(imageName: ImageName, imageSize: CGSize) -> [String]
  func command(step: DrawStep, gradients: [String: Gradient]) -> [String]
  func funcEnd(imageName: ImageName, imageSize: CGSize) -> [String]
  func fileEnding() -> String
}

extension CoreGraphicsGenerator {
  private func generateImageFunction(imgName: ImageName, route: DrawRoute) -> [String] {
    let size = route.boundingRect.size
    let preambleLines = funcStart(imageName: imgName, imageSize: size)
    let commandsLines = route.getSteps().flatMap {
      command(step: $0,
              gradients: route.gradients)
    }
    let conclusionLines = funcEnd(imageName: imgName, imageSize: size)
    return preambleLines + commandsLines + conclusionLines
  }

  private func generateImageFunction(nameAndRoute: (ImageName, DrawRoute)) -> String {
    return generateImageFunction(imgName: nameAndRoute.0, route: nameAndRoute.1).joined(separator: "\n")
  }

  func generateFile(namesAndRoutes: [(ImageName, DrawRoute)]) -> String {
    return filePreamble()
      + namesAndRoutes.map({ generateImageFunction(nameAndRoute: $0) }).joined(separator: "\n\n")
      + "\n"
      + fileEnding()
      + "\n"
  }
}

struct ObjcCGGenerator: CoreGraphicsGenerator {
  let prefix: String
  let headerImportPath: String?
  private let rgbColorSpaceVarName = "rgbColorSpace"
  private func cmd(_ name: String, _ args: String? = nil) -> String {
    let argStr: String
    if let args = args {
      argStr = ", \(args)"
    } else {
      argStr = ""
    }
    return "  CGContext\(name)(context\(argStr));"
  }

  private func cmd(_ name: String, points: [CGPoint]) -> String {
    return cmd(name, points.map { "(CGFloat)\($0.x), (CGFloat)\($0.y)" }.joined(separator: ", "))
  }

  private func cmd(_ name: String, rect: CGRect) -> String {
    let w = cmd(name, "CGRectMake((CGFloat)\(rect.x), (CGFloat)\(rect.y), (CGFloat)\(rect.size.width), (CGFloat)\(rect.size.height))")
    return w
  }

  private func cmd(_ name: String, float: CGFloat) -> String {
    return cmd(name, "(CGFloat)\(float)")
  }

  private static var uniqColorID = 0
  private static func asquireUniqID() -> Int {
    let uid = uniqColorID
    uniqColorID += 1
    return uid
  }

  private func with(colors: [RGBAColor], block: ([String]) -> [String]) -> [String] {
    let colorNamesAndLines = colors.map { define(color: $0) }
    let colorNames = colorNamesAndLines.map { $0.0 }
    let colorDefLines = colorNamesAndLines.map { $0.1 }
    let releaseLines = colorNames.map { release(colorVarName: $0) }
    return colorDefLines + block(colorNames) + releaseLines
  }

  private func define(color: RGBAColor) -> (String, String) {
    let colorVarName = "color\(ObjcCGGenerator.asquireUniqID())"
    let createColor = "  CGColorRef \(colorVarName) = CGColorCreate(\(rgbColorSpaceVarName), (CGFloat []){(CGFloat)\(color.red), (CGFloat)\(color.green), (CGFloat)\(color.blue), (CGFloat)\(color.alpha)});"
    return (colorVarName, createColor)
  }

  private func release(colorVarName: String) -> String {
    return "  CGColorRelease(\(colorVarName));"
  }

  private func cmd(_ name: String, color: RGBAColor) -> [String] {
    let (colorVarName, createColor) = define(color: color)
    let cmdStr = cmd(name, "\(colorVarName)")
    let releaseLine = release(colorVarName: colorVarName)
    return [createColor, cmdStr, releaseLine]
  }

  func filePreamble() -> String {
    let importLine: String
    if let headerImportPath = headerImportPath {
      importLine = "#import \"\(headerImportPath)\""
    } else {
      importLine = "#import <CoreGraphics/CoreGraphics.h>"
    }
    let foundation_import = "#import <Foundation/Foundation.h>"
    return [
      "// Generated by cggen",
      "",
      importLine,
      "",
      foundation_import,
      "\n",
    ].joined(separator: "\n")
  }

  func command(step: DrawStep, gradients: [String: Gradient]) -> [String] {
    switch step {
    case .saveGState:
      return [cmd("SaveGState")]
    case .restoreGState:
      return [cmd("RestoreGState")]
    case let .moveTo(p):
      return [cmd("MoveToPoint", points: [p])]
    case let .curve(c1, c2, end):
      return [cmd("AddCurveToPoint", points: [c1, c2, end])]
    case let .line(p):
      return [cmd("AddLineToPoint", points: [p])]
    case .closePath:
      return [cmd("ClosePath")]
    case let .clip(rule):
      switch rule {
      case .winding:
        return [cmd("Clip")]
      case .evenOdd:
        return [cmd("EOClip")]
      }
    case .endPath:
      return []
    case let .flatness(flatness):
      return [cmd("SetFlatness", float: flatness)]
    case .fillColorSpace:
      return []
    case let .appendRectangle(rect):
      return [cmd("AddRect", rect: rect)]
    case let .fill(color, rule):
      let colorCmd = cmd("SetFillColorWithColor", color: color)
      let fillCmd: String
      switch rule {
      case .winding:
        fillCmd = cmd("FillPath")
      case .evenOdd:
        fillCmd = cmd("EOFillPath")
      }
      return colorCmd + [fillCmd]
    case .strokeColorSpace:
      return []
    case let .concatCTM(transform):
      return [cmd("ConcatCTM", "CGAffineTransformMake(\(transform.a), \(transform.b), \(transform.c), \(transform.d), \(transform.tx), \(transform.ty))")]
    case let .lineWidth(w):
      return [cmd("SetLineWidth", float: w)]
    case let .stroke(color):
      return cmd("SetStrokeColorWithColor", color: color) + [cmd("StrokePath")]
    case .colorRenderingIntent:
      return []
    case .parametersFromGraphicsState:
      return []
    case let .paintWithGradient(gradientKey):
      let gradient = gradients[gradientKey]!
      let colors = gradient.locationAndColors.map { $0.1 }
      let locations = gradient.locationAndColors.map { $0.0 }
      let lines = with(colors: colors) { (colorNames) -> [String] in
        let colorString = colorNames.map { "(__bridge id)\($0)" }.joined(separator: ", ")
        let colorsArrayVarName = "colors\(ObjcCGGenerator.asquireUniqID())"
        let colorArray = "  CFArrayRef \(colorsArrayVarName) = CFBridgingRetain(@[ \(colorString) ]);"
        let locationList = locations.map { "(CGFloat)\($0)" }.joined(separator: ", ")
        let locationArray = "(CGFloat []){\(locationList)}"
        let gradientName = "gradient\(ObjcCGGenerator.asquireUniqID())"
        let gradientDef = "  CGGradientRef \(gradientName) = CGGradientCreateWithColors(\(rgbColorSpaceVarName), \(colorsArrayVarName), \(locationArray));"
        let colorArrayRelease = "  CFRelease(\(colorsArrayVarName));"

        var optionsStrings: [String] = []
        if gradient.options.contains(.drawsBeforeStartLocation) {
          optionsStrings.append("kCGGradientDrawsBeforeStartLocation")
        }
        if gradient.options.contains(.drawsAfterEndLocation) {
          optionsStrings.append("kCGGradientDrawsAfterEndLocation")
        }
        if optionsStrings.isEmpty {
          optionsStrings.append("0")
        }
        let optionsVarName = "gradientOptions\(ObjcCGGenerator.asquireUniqID())"
        let optionsLine = "  CGGradientDrawingOptions \(optionsVarName) = (CGGradientDrawingOptions)(\(optionsStrings.joined(separator: " | ")));"
        let startPoint = "CGPointMake((CGFloat)\(gradient.startPoint.x), (CGFloat)\(gradient.startPoint.y))"
        let endPoint = "CGPointMake((CGFloat)\(gradient.endPoint.x), (CGFloat)\(gradient.endPoint.y))"
        let drawGradientLine = "  CGContextDrawLinearGradient(context, \(gradientName), \(startPoint), \(endPoint), \(optionsVarName));"
        let releaseGradient = "  CGGradientRelease(\(gradientName));"
        return [colorArray, gradientDef, colorArrayRelease, optionsLine, drawGradientLine, releaseGradient]
      }
      return lines
    }
  }

  func funcStart(imageName: ImageName, imageSize _: CGSize) -> [String] {
    return [
      ObjCGen.functionDef(imageName: imageName.camelCase, prefix: prefix),
      "  CGColorSpaceRef \(rgbColorSpaceVarName) = CGColorSpaceCreateDeviceRGB();",
    ]
  }

  func funcEnd(imageName _: ImageName, imageSize _: CGSize) -> [String] {
    return ["  CGColorSpaceRelease(\(rgbColorSpaceVarName));", "}"]
  }

  func fileEnding() -> String {
    return ""
  }
}

struct ObjcHeaderCGGenerator: CoreGraphicsGenerator {
  let prefix: String
  func filePreamble() -> String {
    return [
      "// Generated by cggen",
      "",
      "#import <CoreGraphics/CoreGraphics.h>",
      "\n",
    ].joined(separator: "\n")
  }

  func command(step _: DrawStep, gradients _: [String: Gradient]) -> [String] {
    return []
  }

  func funcStart(imageName: ImageName, imageSize: CGSize) -> [String] {
    let camel = imageName.camelCase
    return [
      "static const CGSize k\(prefix)\(camel)ImageSize = (CGSize){.width = \(imageSize.width), .height = \(imageSize.height)};",
      ObjCGen.functionDecl(imageName: camel, prefix: prefix),
    ]
  }

  func funcEnd(imageName _: ImageName, imageSize _: CGSize) -> [String] {
    return []
  }

  func fileEnding() -> String {
    return ""
  }
}
