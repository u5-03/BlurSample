//
//  ContentView.swift
//  BlurSample
//
//  Created by Yugo Sugiyama on 2024/03/30.
//

import SwiftUI

struct Pixel: Codable, Identifiable {
    var id: String {
        return UUID().uuidString
    }
    let r: Int
    let g: Int
    let b: Int

    var color: Color {
        Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
    }
}

struct PixelView: View {
    let pixel: Pixel

    var body: some View {
        Rectangle()
            .fill(pixel.color)
            .aspectRatio(1, contentMode: .fit)
    }
}

struct PixelImageView: View {
    let pixels: [Pixel]
    let columns: Int
    let rows: Int

    init(pixels: [Pixel], size: Int) {
        self.pixels = pixels
        self.columns = size
        self.rows = size
    }

    

    var body: some View {
        if pixels.isEmpty {
            EmptyView()
        } else {
            GeometryReader { geometry in
                let width = geometry.size.width / CGFloat(columns)
                VStack(spacing: 0) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<columns, id: \.self) { column in
                                let pixelIndex = row * columns + column
                                PixelView(pixel: pixels[pixelIndex])
                                    .frame(width: width, height: width)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ContentView: View {
    @State private var pixels: [Pixel] = []

    var body: some View {
        PixelImageView(pixels: pixels, size: 100)
            .onAppear {
                loadPixels()
            }
    }

    func loadPixels() {
        guard let url = Bundle.main.url(forResource: "rgb", withExtension: "json") else {
            print("JSON file not found")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            pixels = try JSONDecoder().decode([Pixel].self, from: data)
        } catch {
            print("Error loading JSON data: \(error)")
        }
    }
}

#Preview {
    ContentView()
}
