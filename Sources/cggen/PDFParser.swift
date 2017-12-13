// Copyright (c) 2017 Yandex LLC. All rights reserved.
// Author: Alfred Zien <zienag@yandex-team.ru>

import Base
import Foundation

struct Resources {
  let shadings: [String:PDFShading]
  let gStates: [String:PDFExtGState]
  init?(obj: PDFObject) {
    guard case let .dictionary(dict) = obj
      else { return nil }
    let shadingDict = dict["Shading"]?.dictionaryVal() ?? [:]
    let gStatesDict = dict["ExtGState"]?.dictionaryVal() ?? [:]
    shadings = shadingDict.mapValues { PDFShading.init(obj: $0)! }
    gStates = gStatesDict.mapValues { PDFExtGState.init(obj: $0)! }
  }
}

extension CGPDFDocument {
  var pages: [CGPDFPage] {
    return (1...numberOfPages).map { page(at: $0)! }
  }
}


private extension CGPDFScannerRef {
  func popNumber() -> CGPDFReal? {
    var val : CGPDFReal = 0;
    return CGPDFScannerPopNumber(self, &val) ? val : nil
  }
  private func popTwoNumbers() -> (CGFloat, CGFloat)? {
    guard let a1 = popNumber() else {
      return nil
    }
    guard let a2 = popNumber() else {
      fatalError()
    }
    return (a1, a2)
  }
  func popPoint() -> CGPoint? {
    guard let pair = popTwoNumbers() else { return nil }
    return CGPoint(x: pair.1, y: pair.0)
  }
  func popSize() -> CGSize? {
    guard let pair = popTwoNumbers() else { return nil }
    return CGSize(width: pair.1, height: pair.0)
  }
  func popRect() -> CGRect? {
    guard let size = popSize() else { return nil }
    guard let origin = popPoint() else { fatalError() }
    return CGRect(origin: origin, size: size)
  }
  func popColor() -> RGBColor? {
    guard let blue = popNumber() else { return nil }
    guard let green = popNumber(), let red = popNumber() else { fatalError() }
    return RGBColor(red: red, green: green, blue: blue)
  }
  func popName() -> String? {
    var pointer: UnsafePointer<Int8>? = nil
    CGPDFScannerPopName(self, &pointer)
    guard let cString = pointer else { return nil }
    return String(cString: cString)
  }
  func popAffineTransform() -> CGAffineTransform? {
    guard let f = popNumber() else { return nil }
    guard let e = popNumber(),
      let d = popNumber(),
      let c = popNumber(),
      let b = popNumber(),
      let a = popNumber() else { fatalError() }
    return CGAffineTransform(a: a, b: b, c: c, d: d, tx: e, ty: f)
  }
  func popObject() -> PDFObject? {
    var objP: CGPDFObjectRef? = nil
    CGPDFScannerPopObject(self, &objP)
    guard let obj = objP else { return nil }
    return PDFObject(pdfObj: obj)
  }
}

enum PDFParser {
  private class ParsingContext {
    var route: DrawRoute
    let resources: Resources

    var strokeAlpha: CGFloat = 1
    var fillAlpha: CGFloat = 1

    var strokeRGBColor: RGBColor?
    var fillRGBColor: RGBColor?

    var strokeColor: RGBAColor {
      guard let strokeRGBColor = strokeRGBColor else {
        fatalError("Stroke color should been set")
      }
      return RGBAColor.rgb(strokeRGBColor, alpha: strokeAlpha)
    }

    var fillColor: RGBAColor {
      guard let fillRGBColor = fillRGBColor else {
        fatalError("Fill color should been set")
      }
      return RGBAColor.rgb(fillRGBColor, alpha: fillAlpha)
    }

    init(route: DrawRoute, resources: Resources) {
      self.route = route
      self.resources = resources
    }
  }

  static func parse(pdfURL: CFURL) -> [DrawRoute] {
    guard let pdfDoc = CGPDFDocument(pdfURL) else {
      fatalError("Could not open pdf file at: \(pdfURL)");
    }
    let operatorTable = makeOperatorTable()

    return pdfDoc.pages.map { (page) in
      let stream = CGPDFContentStreamCreateWithPage(page)

      let pageDictionary = PDFObject.processDict(page.dictionary!)
      let resources = Resources(obj: pageDictionary["Resources"]!)!

      let gradients = resources.shadings.mapValues { $0.makeGradient() }
      let route = DrawRoute(boundingRect: page.getBoxRect(.mediaBox),
                            gradients: gradients)
      var context = ParsingContext(route: route, resources: resources)

      let scanner = CGPDFScannerCreate(stream, operatorTable, &context)
      CGPDFScannerScan(scanner)

      CGPDFScannerRelease(scanner)
      CGPDFContentStreamRelease(stream)
      return context.route
    }
  }

  static private func callback(info: UnsafeMutableRawPointer?,
                               step: DrawStep) {
    callback(context: info!.load(as: ParsingContext.self), step: step)
  }

  static private func callback(context: ParsingContext, step: DrawStep) {
    let n = context.route.push(step: step)
    cggen.log("\(n): \(step)")
  }

  static private func getContext(_ info: UnsafeMutableRawPointer?) -> ParsingContext {
    return info!.load(as: ParsingContext.self)
  }

  static private func makeOperatorTable() -> CGPDFOperatorTableRef {
    let operatorTableRef = CGPDFOperatorTableCreate()!
    CGPDFOperatorTableSetCallback(operatorTableRef, "b") { (scanner, info) in
      fatalError("not implemented")
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "B") { (scanner, info) in
      fatalError("not implemented")
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "b*") { (scanner, info) in
      fatalError("not implemented")
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "B*") { (scanner, info) in
      fatalError("not implemented")
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "BDC") { (scanner, info) in
      fatalError("not implemented")
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "BT") { (scanner, info) in
      fatalError("not implemented")
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "BX") { (scanner, info) in
      fatalError("not implemented")
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "c") { (scanner, info) in
      let c3 = scanner.popPoint()!
      let c2 = scanner.popPoint()!
      let c1 = scanner.popPoint()!
      PDFParser.callback(info: info, step: .curve(c1, c2, c3))
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "cm") { (scanner, info) in
      PDFParser.callback(info: info, step: .concatCTM(scanner.popAffineTransform()!))
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "CS") { (scanner, info) in
      PDFParser.callback(info: info, step: .strokeColorSpace)
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "cs") { (scanner, info) in
      // TBD: Extract proper color space
      PDFParser.callback(info: info, step: .fillColorSpace)
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "d") { (scanner, info) in
      fatalError("not implemented")
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "gs") { (scanner, info) in
      let context = info!.load(as: ParsingContext.self)
      let gsName = scanner.popName()!
      let extGState = context.resources.gStates[gsName]!
      extGState.commands.forEach({ (cmd) in
        switch cmd {
        case let .fillAlpha(a):
          context.fillAlpha = a
        case let .strokeAlpha(a):
          context.strokeAlpha = a
        }
      })
      cggen.log("push gstate: \(extGState)")
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "q") { (scanner, info) in
      PDFParser.callback(info: info, step: .saveGState)
    }
    CGPDFOperatorTableSetCallback(operatorTableRef, "Q") { (scanner, info) in
      PDFParser.callback(info: info, step: .restoreGState)
    }
    CGPDFOperatorTableSetCallback(operatorTableRef, "l") { (scanner, info) in
      PDFParser.callback(info: info, step: .line(scanner.popPoint()!))
    }
    CGPDFOperatorTableSetCallback(operatorTableRef, "h") { (scanner, info) in
      PDFParser.callback(info: info, step: .closePath)
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "n") { (scanner, info) in
      PDFParser.callback(info: info, step: .endPath)
    }
    CGPDFOperatorTableSetCallback(operatorTableRef, "i") { (scanner, info) in
      PDFParser.callback(info: info, step: .flatness(scanner.popNumber()!))
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "m") { (scanner, info) in
      PDFParser.callback(info: info, step: .moveTo(scanner.popPoint()!))
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "re") { (scanner, info) in
      PDFParser.callback(info: info, step: .appendRectangle(scanner.popRect()!))
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "rg") { (scanner, info) in
      PDFParser.getContext(info).fillRGBColor = scanner.popColor()!
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "RG") { (scanner, info) in
      PDFParser.getContext(info).strokeRGBColor = scanner.popColor()!
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "ri") { (scanner, info) in
      PDFParser.callback(info: info, step: .colorRenderingIntent)
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "s") { (scanner, info) in
      fatalError("not implemented")
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "S") { (scanner, info) in
      let context = PDFParser.getContext(info)
      PDFParser.callback(context: context,
                         step: .stroke(context.strokeColor))
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "sc") { (scanner, info) in
      PDFParser.getContext(info).fillRGBColor = scanner.popColor()!
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "SC") { (scanner, info) in
      PDFParser.getContext(info).strokeRGBColor = scanner.popColor()!
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "sh") { (scanner, info) in
      PDFParser.callback(info: info, step: .paintWithGradient(scanner.popName()!))
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "f") { (scanner, info) in
      let context = PDFParser.getContext(info)
      PDFParser.callback(context: context,
                         step: .fill(context.fillColor, .winding))
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "w") { (scanner, info) in
      PDFParser.callback(info: info, step: .lineWidth(scanner.popNumber()!))
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "W") { (scanner, info) in
      PDFParser.callback(info: info, step: .clip(.winding))
    }

    CGPDFOperatorTableSetCallback(operatorTableRef, "W*") { (scanner, info) in
      PDFParser.callback(info: info, step: .clip(.evenOdd))
    }
    return operatorTableRef
  }
}