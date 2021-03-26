import CoreGraphics
import Foundation
import PDFParse
import Base

let commonHeaderPrefix = ObjcTerm.comment("Generated by cggen")

enum Error: Swift.Error {
  case unsupportedFileExtension(String)
  case multiplePagedPdfNotSupported(file: String)
}

public typealias Generator = (URL) throws -> DrawRoute

public let generator: Generator = {
  switch $0.pathExtension {
  case "pdf":
    let pages = PDFParser.parse(pdfURL: $0 as CFURL)
    try check(
      pages.count == 1,
      Error.multiplePagedPdfNotSupported(file: $0.absoluteString)
    )
    return PDFToDrawRouteConverter.convert(page: pages[0])
  case "svg":
    let svg = try SVGParser.root(from: Data(contentsOf: $0))
    return try SVGToDrawRouteConverter.convert(document: svg)
  case let ext:
    throw Error.unsupportedFileExtension(ext)
  }
}

public func generateImages(from files: [URL], generator: Generator = generator) throws -> [Image] {
  try zip(files, files.concurrentMap(generator)).map {
    Image(
      name: $0.0.deletingPathExtension().lastPathComponent,
      route: $0.1
    )
  }
}