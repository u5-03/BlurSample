import SwiftUI
import UIKit
import CoreGraphics
import DeveloperToolsSupport   // ImageResourceを利用するためのモジュール

// MARK: - Pixel データ構造体

/// 1ピクセル分の RGB 情報 (0～255) を保持。グリッド描画時の位置情報として index も保持します。
struct Pixel: Codable, Identifiable {
    var id: Int { index }
    let index: Int
    let r: Int
    let g: Int
    let b: Int

    /// SwiftUI の Color に変換（各成分は 0～1 に正規化）
    var color: Color {
        Color(red: Double(r) / 255.0,
              green: Double(g) / 255.0,
              blue: Double(b) / 255.0)
    }
}

// MARK: - ImageResource からピクセル情報を抽出する関数

/// ImageResource を指定サイズにリサイズし、各ピクセルの (r, g, b) 値を読み出します。
/// α == 0 のピクセルは (0,0,0) として扱います。
/// - Parameters:
///   - resource: 変換対象の ImageResource
///   - size: リサイズ後のサイズ（例: 100×100）
/// - Returns: 指定サイズ分（width×height）の Pixel 配列
func convertImageResourceToPixels(resource: ImageResource,
                                  size: CGSize = CGSize(width: 100, height: 100)) -> [Pixel] {
    var pixels: [Pixel] = []
    let image = UIImage(resource: resource)
    // ImageResource から CGImage を取得
    guard let cgImage = image.cgImage else { return [] }
    let width = Int(size.width)
    let height = Int(size.height)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerPixel = 4
    let bitsPerComponent = 8
    let bytesPerRow = bytesPerPixel * width
    var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

    // CGContext を作成してリサイズ後の画像を描画
    guard let context = CGContext(
        data: &pixelData,
        width: width,
        height: height,
        bitsPerComponent: bitsPerComponent,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        print("コンテキストの作成に失敗しました")
        return []
    }
    context.draw(cgImage, in: CGRect(origin: .zero, size: size))

    // 各ピクセルを読み出す（左上から右下へ順次）
    var currentIndex = 0
    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * bytesPerRow) + (x * bytesPerPixel)
            let r = pixelData[offset + 0]
            let g = pixelData[offset + 1]
            let b = pixelData[offset + 2]
            let a = pixelData[offset + 3]

            // 完全に透明なら (0, 0, 0)
            if a == 0 {
                pixels.append(Pixel(index: currentIndex, r: 0, g: 0, b: 0))
            } else {
                pixels.append(Pixel(index: currentIndex, r: Int(r), g: Int(g), b: Int(b)))
            }
            currentIndex += 1
        }
    }
    return pixels
}

// MARK: - SwiftUI によるピクセル描画

/// 単一のピクセルを表示するビュー
struct PixelView: View {
    let pixel: Pixel

    var body: some View {
        Rectangle()
            .fill(pixel.color)
            .aspectRatio(1, contentMode: .fit)
    }
}

/// ブラー効果を適用したピクセル表示。周囲のピクセルの色を weight 値で重み付けして平均化します。
struct BlurredPixelView: View {
    let pixel: Pixel
    let surroundingPixels: [Pixel]
    let weight: Double  // 周囲ピクセルの寄与度

    var body: some View {
        let blurredColor = computeBlurredColor()
        return Rectangle()
            .fill(blurredColor)
            .aspectRatio(1, contentMode: .fit)
    }

    /// 指定された weight を用いて、元ピクセルと周囲ピクセルの重み付き平均色を算出
    private func computeBlurredColor() -> Color {
        let baseRed = Double(pixel.r) / 255.0
        let baseGreen = Double(pixel.g) / 255.0
        let baseBlue = Double(pixel.b) / 255.0

        var rTotal = baseRed
        var gTotal = baseGreen
        var bTotal = baseBlue
        var totalWeight = 1.0

        for neighbor in surroundingPixels {
            let nRed = Double(neighbor.r) / 255.0
            let nGreen = Double(neighbor.g) / 255.0
            let nBlue = Double(neighbor.b) / 255.0
            rTotal += nRed * weight
            gTotal += nGreen * weight
            bTotal += nBlue * weight
            totalWeight += weight
        }
        return Color(red: rTotal / totalWeight,
                     green: gTotal / totalWeight,
                     blue: bTotal / totalWeight)
    }
}

/// グリッド上にピクセルを描画するビュー
/// - Note: columns/rows は変換サイズと一致している必要があります。
struct PixelImageView: View {
    let pixels: [Pixel]
    let columns: Int
    let rows: Int
    let isBlurred: Bool
    let blurDistance: Int  // 周囲ピクセルのサンプリング範囲
    let weight: Double = 0.03  // 重み係数（固定）

    var body: some View {
        GeometryReader { geometry in
            let pixelSize = geometry.size.width / CGFloat(columns)
            let gridItems = Array(repeating: GridItem(.fixed(pixelSize), spacing: 0), count: columns)

            LazyVGrid(columns: gridItems, spacing: 0) {
                ForEach(pixels) { pixel in
                    if isBlurred {
                        BlurredPixelView(pixel: pixel,
                                         surroundingPixels: getSurroundingPixels(for: pixel),
                                         weight: weight)
                            .frame(width: pixelSize, height: pixelSize)
                    } else {
                        PixelView(pixel: pixel)
                            .frame(width: pixelSize, height: pixelSize)
                    }
                }
            }
        }
    }

    /// 指定ピクセルの周囲 (blurDistance 範囲内) のピクセルを返す。
    private func getSurroundingPixels(for pixel: Pixel) -> [Pixel] {
        var neighbors: [Pixel] = []
        // ピクセルの列番号・行番号は、渡された columns を利用して計算
        let col = pixel.index % columns
        let row = pixel.index / columns

        for dy in -blurDistance...blurDistance {
            for dx in -blurDistance...blurDistance {
                if dx == 0 && dy == 0 { continue }
                let newCol = col + dx
                let newRow = row + dy
                if newCol >= 0, newCol < columns, newRow >= 0, newRow < rows {
                    let neighborIndex = newRow * columns + newCol
                    if neighborIndex < pixels.count {
                        neighbors.append(pixels[neighborIndex])
                    }
                }
            }
        }
        return neighbors
    }
}

// MARK: - ContentView

/// アプリのメインビュー。ImageResource を利用してピクセル配列を生成し、
/// ピクセルグリッド表示と共に、変換サイズ・サンプリング範囲の調整UIを提供します。
struct ContentView: View {
    @State private var pixels: [Pixel] = []
    @State private var isBlurred: Bool = true
    @State private var conversionSize: Int = 100  // ピクセル変換サイズ（例: 50, 100, 150, 200）
    @State private var blurDistance: Int = 5        // ブラー効果でサンプリングする範囲

    // ImageResource はここでは拡張ケースとして用意（例: .sugiy として利用）
    // 実際は Bundle 内のリソース等をご利用ください。
    private let resource: ImageResource = .sugiy

    var body: some View {
        StrokeAnimationShapeView()
//        VStack {
//            // 調整用のコントロール群
//            VStack {
//                // 変換サイズのPicker
//                HStack {
//                    Text("Image Size:")
//                    Picker("", selection: $conversionSize) {
//                        Text("50").tag(50)
//                        Text("100").tag(100)
//                        Text("150").tag(150)
//                        Text("200").tag(200)
//                    }
//                    .pickerStyle(.segmented)
//                }
//                .padding(.horizontal)
//
//                // ブラーのサンプリング範囲のSlider
//                HStack {
//                    Text("Blur Range: \(blurDistance)")
//                    Slider(value: Binding(get: {
//                        Double(blurDistance)
//                    }, set: { newValue in
//                        blurDistance = Int(newValue)
//                    }), in: 0...30, step: 1)
//                    
//                }
//                .padding(.horizontal)
//            }
//            .padding(.top)
//
//            // ピクセルグリッド表示
//            PixelImageView(pixels: pixels,
//                           columns: conversionSize,
//                           rows: conversionSize,
//                           isBlurred: isBlurred,
//                           blurDistance: blurDistance)
//                .padding()
//
//            // Blur ON/OFF ボタン
//            Button(action: { isBlurred.toggle() },
//                   label: {
//                       Text(isBlurred ? "Blur を解除" : "Blur を適用")
//                   })
//                   .padding()
//
//            Spacer()
//        }
//        .onAppear { loadImageResourceAndConvert() }
//        // 変換サイズ変更時に再変換する
//        .onChange(of: conversionSize) { _ in loadImageResourceAndConvert() }
    }

    /// Bundle 内の画像ファイルから ImageResource を生成し、ピクセル配列を作成する
    private func loadImageResourceAndConvert() {
        let newSize = CGSize(width: conversionSize, height: conversionSize)
        let convertedPixels = convertImageResourceToPixels(resource: resource, size: newSize)
        self.pixels = convertedPixels
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}

