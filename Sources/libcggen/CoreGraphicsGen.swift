import Foundation

import Base

public protocol CoreGraphicsGenerator {
  func filePreamble() -> String
  func generateImageFunction(image: Image) -> String
  func fileEnding() -> String
}

extension CoreGraphicsGenerator {
  public func generateFile(images: [Image]) -> String {
    let functions = images.map(generateImageFunction).joined(separator: "\n\n")
    return
      """
      \(commonHeaderPrefix.renderText())

      \(filePreamble())
      \(functions)

      \(fileEnding())

      """
  }
}
