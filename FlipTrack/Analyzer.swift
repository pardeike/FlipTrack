import UIKit

class Analyzer {
    
    struct ImageResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                struct ImageRequest: Encodable {
                    let model = "gpt-4o-mini"
                    let messages: [String]
                }
                let content: String
            }
            let message: Message
        }
        let choices: [Choice]
    }
    
    static let url = URL(string: "https://api.openai.com/v1/chat/completions")!
    static func extractScore(_ image: UIImage, _ maxSize: Int, _ quality: CGFloat) async -> [Int] {
        guard let imageData = renderedJPEGData(from: image, maxSize: maxSize, quality: quality) else { return [] }
        let base64 = imageData.base64EncodedString()
        let body = """
        {
            "model": "gpt-4o",
            "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": "You are an expert at analyzing images of 80s pinball machines. Extract the left and right pinball scores from the image and state the pair of numbers in the form #####/##### without any extra text."
                    },
                    {
                        "type": "image_url",
                        "image_url": {"url": "data:image/jpeg;base64,\(base64)"}
                    }
                ]
            }
            ],
            "max_tokens": 100
        }
        """
        var request = URLRequest(url: url)
        guard let apiKey = UserDefaults.standard.string(forKey: "openai-api-key") else { return [] }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "POST"
        request.httpBody = body.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8)
        guard let res = try? await URLSession.shared.data(for: request) else { return [] }
        guard let httpResponse = res.1 as? HTTPURLResponse else { return [] }
        guard httpResponse.statusCode == 200 else { return [] }
        guard let response = try? JSONDecoder().decode(ImageResponse.self, from: res.0) else { return [] }
        guard var text = response.choices.first?.message.content else { return [] }
        text = text.replacingOccurrences(of: ",", with: "")
        return text.split(separator: "/").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
    }
    
    static func renderedJPEGData(from image: UIImage, maxSize: Int, quality: CGFloat) -> Data? {
        let (w, h) = (image.size.width, image.size.height)
        let f = CGFloat(maxSize) / max(w, h)
        let size = CGSize(width: w * f, height: h * f)
        #if ENHANCE
        guard let inputCIImage = CIImage(image: image) else { return nil }
        
        guard let colorControlsFilter = CIFilter(name: "CIColorControls") else { return nil }
        colorControlsFilter.setValue(inputCIImage, forKey: kCIInputImageKey)
        colorControlsFilter.setValue(1.5, forKey: kCIInputContrastKey)    // Increase contrast
        colorControlsFilter.setValue(2.0, forKey: kCIInputSaturationKey)  // Boost saturation
        colorControlsFilter.setValue(0.0, forKey: kCIInputBrightnessKey)  // Adjust brightness
        guard let colorAdjustedImage = colorControlsFilter.outputImage else { return nil }

        guard let hueAdjustFilter = CIFilter(name: "CIHueAdjust") else { return nil }
        hueAdjustFilter.setValue(colorAdjustedImage, forKey: kCIInputImageKey)
        hueAdjustFilter.setValue(0.1, forKey: kCIInputAngleKey)
        guard let hueAdjustedImage = hueAdjustFilter.outputImage else { return nil }
        
        let ciContext = CIContext(options: nil)
        guard let cgImage = ciContext.createCGImage(hueAdjustedImage, from: hueAdjustedImage.extent) else { return nil }
        let processedImage = UIImage(cgImage: cgImage)
        
        let renderer = UIGraphicsImageRenderer(size: size)
        let renderedImage = renderer.image { _ in
            processedImage.draw(in: CGRect(origin: .zero, size: size))
        }
        #else
        let renderedImage = image
        #endif 
        return renderedImage.jpegData(compressionQuality: quality)
    }

}
