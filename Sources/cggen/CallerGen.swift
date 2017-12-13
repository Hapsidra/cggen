// Copyright (c) 2017 Yandex LLC. All rights reserved.
// Author: Alfred Zien <zienag@yandex-team.ru>

import Foundation

struct ObjcCallerGen: CoreGraphicsGenerator {
  let headerImportPath: String
  let scale: CGFloat
  let prefix: String
  let outputPath: String
  func filePreamble() -> String {
    return
      """
      // Generated by cggen

      #import <CoreGraphics/CoreGraphics.h>
      #import <Foundation/Foundation.h>

      #import "\(headerImportPath)"

      typedef void (*DrawingFunction)(CGContextRef);
      static const CGFloat kScale = \(scale);

      static int WriteImageToFile(DrawingFunction f,
                                  CGSize s,
                                  NSString* outputFilePath) {
        CGSize contextSize =
        CGSizeApplyAffineTransform(s, CGAffineTransformMakeScale(kScale, kScale));
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx =
          CGBitmapContextCreate(NULL, contextSize.width, contextSize.width, 8, 0,
                                colorSpace, kCGImageAlphaPremultipliedLast);
        CGContextSetAllowsAntialiasing(ctx, NO);
        CGContextScaleCTM(ctx, kScale, kScale);
        f(ctx);
        CGImageRef img = CGBitmapContextCreateImage(ctx);
        NSURL* url = [NSURL fileURLWithPath:outputFilePath];
        CGImageDestinationRef destination = CGImageDestinationCreateWithURL(
          (__bridge CFURLRef)url, kUTTypePNG, 1, nil);
        CGImageDestinationAddImage(destination, img, nil);
        BOOL t = CGImageDestinationFinalize(destination);

        CGColorSpaceRelease(colorSpace);
        CGContextRelease(ctx);
        CGImageRelease(img);
        CFRelease(destination);
        return t ? 0 : 1;
      }

      int main(int argc, const char* argv[]) {
        int retCode = 0;

      """
  }

  func funcStart(imageName: ImageName, imageSize _: CGSize) -> [String] {
    let camel = imageName.camelCase
    let function = ObjCGen.functionName(imageName: camel, prefix: prefix)
    return [
      "  retCode |= WriteImageToFile(\(function),",
      "      k\(camel)ImageSize,",
      "      @\"\(outputPath)/\(imageName.snakeCase).png\");",
    ]
  }

  func command(step _: DrawStep, gradients _: [String: Gradient]) -> [String] {
    return []
  }

  func funcEnd(imageName _: ImageName, imageSize _: CGSize) -> [String] {
    return []
  }

  func fileEnding() -> String {
    return "  return retCode;\n}"
  }
}
