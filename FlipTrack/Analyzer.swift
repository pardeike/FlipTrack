import UIKit

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

class Analyzer {
    static let url = URL(string: "https://api.openai.com/v1/chat/completions")!
    static func extractScore(_ image: UIImage) async -> [Int] {
        let imageData = renderedJPEGData(from: image, compressionQuality: 0.5)!
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
    
    static func renderedJPEGData(from image: UIImage, compressionQuality: CGFloat) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        let renderedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return renderedImage.jpegData(compressionQuality: compressionQuality)
    }
}
