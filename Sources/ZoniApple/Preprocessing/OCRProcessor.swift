// ZoniApple - Apple platform extensions for Zoni
//
// OCRProcessor.swift - Vision framework OCR processor for text extraction

#if canImport(Vision)
import Vision
import Foundation
import CoreGraphics
import ImageIO

// MARK: - VisionOCRProcessor

/// An OCR processor using Apple's Vision framework for text extraction.
///
/// `VisionOCRProcessor` leverages Apple's on-device Vision framework to extract
/// text from images and PDF documents. This provides:
/// - **Privacy**: All processing happens on-device with no network requests
/// - **Accuracy**: State-of-the-art text recognition using neural networks
/// - **Multi-language support**: Supports numerous languages for text recognition
/// - **Offline support**: Works without internet connectivity
///
/// ## Supported Languages
/// Vision framework supports text recognition in many languages including:
/// - English (en-US)
/// - Spanish (es-ES)
/// - French (fr-FR)
/// - German (de-DE)
/// - Italian (it-IT)
/// - Portuguese (pt-BR)
/// - Chinese (zh-Hans, zh-Hant)
/// - Japanese (ja-JP)
/// - Korean (ko-KR)
/// - And many more
///
/// To get the full list of supported languages, use:
/// ```swift
/// let supportedLanguages = try VNRecognizeTextRequest.supportedRecognitionLanguages(
///     for: .accurate,
///     revision: VNRecognizeTextRequestRevision3
/// )
/// ```
///
/// ## Recognition Levels
/// Vision provides two recognition levels:
/// - **Accurate**: Higher accuracy, slower processing. Best for archival documents.
/// - **Fast**: Lower accuracy, faster processing. Best for real-time applications.
///
/// ## Example Usage
/// ```swift
/// // Create an OCR processor with default settings
/// let processor = VisionOCRProcessor()
///
/// // Extract text from an image
/// let imageURL = URL(filePath: "/path/to/image.png")
/// let text = try await processor.extractText(from: imageURL)
/// print(text)
///
/// // Extract text from a PDF
/// let pdfURL = URL(filePath: "/path/to/document.pdf")
/// let pageTexts = try await processor.extractTextFromPDF(at: pdfURL)
/// for (index, pageText) in pageTexts.enumerated() {
///     print("Page \(index + 1): \(pageText)")
/// }
/// ```
///
/// ## Multi-Language Recognition
/// ```swift
/// // Configure for multiple languages
/// let processor = VisionOCRProcessor(
///     languages: ["en-US", "es-ES", "fr-FR"],
///     recognitionLevel: .accurate,
///     usesLanguageCorrection: true
/// )
///
/// let text = try await processor.extractText(from: imageURL)
/// ```
///
/// ## Performance Considerations
/// - **Accurate mode**: Provides the best results but takes longer to process.
///   Use for documents where accuracy is critical.
/// - **Fast mode**: Suitable for real-time applications or when processing
///   many images quickly is more important than perfect accuracy.
/// - **Language correction**: Improves accuracy for natural language text but
///   may not be ideal for technical content like code or serial numbers.
/// - **PDF processing**: Each page is rendered to an image before OCR, which
///   can be memory-intensive for large documents. Consider processing pages
///   individually for very large PDFs.
///
/// ## Thread Safety
/// This actor is safe to use from any concurrency context.
@available(macOS 10.15, iOS 13.0, tvOS 13.0, *)
public actor VisionOCRProcessor {

    // MARK: - Properties

    /// The languages to use for text recognition.
    ///
    /// Specify languages in BCP-47 format (e.g., "en-US", "fr-FR").
    /// The order matters: languages listed first are given priority.
    private let languages: [String]

    /// The recognition level to use.
    ///
    /// - `accurate`: Higher accuracy, slower processing
    /// - `fast`: Lower accuracy, faster processing
    private let recognitionLevel: VNRequestTextRecognitionLevel

    /// Whether to use language correction during recognition.
    ///
    /// When enabled, the recognizer applies language-specific corrections
    /// to improve accuracy for natural language text. Disable for technical
    /// content like code, serial numbers, or structured data.
    private let usesLanguageCorrection: Bool

    // MARK: - Initialization

    /// Creates a new Vision OCR processor with the specified configuration.
    ///
    /// - Parameters:
    ///   - languages: The languages to use for recognition in BCP-47 format.
    ///     Defaults to `["en-US"]`. Languages are prioritized in order.
    ///   - recognitionLevel: The accuracy level to use. Defaults to `.accurate`.
    ///   - usesLanguageCorrection: Whether to apply language correction.
    ///     Defaults to `true`.
    public init(
        languages: [String] = ["en-US"],
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
        usesLanguageCorrection: Bool = true
    ) {
        self.languages = languages
        self.recognitionLevel = recognitionLevel
        self.usesLanguageCorrection = usesLanguageCorrection
    }

    // MARK: - Public Methods

    /// Extracts text from an image at the specified URL.
    ///
    /// Loads the image from the URL and performs OCR to extract text content.
    ///
    /// - Parameter imageURL: The URL of the image file to process.
    ///   Supports common image formats including PNG, JPEG, TIFF, and HEIC.
    /// - Returns: The extracted text with lines joined by newlines.
    /// - Throws: `ZoniError.loadingFailed` if the image cannot be loaded,
    ///   or a Vision framework error if OCR fails.
    ///
    /// ## Example
    /// ```swift
    /// let processor = VisionOCRProcessor()
    /// let url = URL(filePath: "/path/to/receipt.jpg")
    /// let text = try await processor.extractText(from: url)
    /// print(text)
    /// ```
    public func extractText(from imageURL: URL) async throws -> String {
        guard let cgImage = loadCGImage(from: imageURL) else {
            throw ZoniError.loadingFailed(
                url: imageURL,
                reason: "Unable to load image from URL. Ensure the file exists and is a valid image format."
            )
        }

        return try await extractText(from: cgImage)
    }

    /// Extracts text from a CGImage.
    ///
    /// Performs OCR on the provided image to extract text content.
    ///
    /// - Parameter image: The CGImage to process.
    /// - Returns: The extracted text with lines joined by newlines.
    /// - Throws: A Vision framework error if OCR fails.
    ///
    /// ## Example
    /// ```swift
    /// let processor = VisionOCRProcessor()
    /// // Assuming you have a CGImage from elsewhere
    /// let text = try await processor.extractText(from: cgImage)
    /// print(text)
    /// ```
    public func extractText(from image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                continuation.resume(returning: text)
            }

            // Configure the request
            request.recognitionLevel = recognitionLevel
            request.usesLanguageCorrection = usesLanguageCorrection
            request.recognitionLanguages = languages

            // Create handler and perform request
            let handler = VNImageRequestHandler(cgImage: image, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Extracts text from each page of a PDF document.
    ///
    /// Opens the PDF, renders each page to an image, and performs OCR
    /// on each page individually.
    ///
    /// - Parameter url: The URL of the PDF file to process.
    /// - Returns: An array of strings, one per page, containing the extracted text.
    ///   Empty pages return empty strings in the array.
    /// - Throws: `ZoniError.loadingFailed` if the PDF cannot be opened or
    ///   a page cannot be rendered, or a Vision framework error if OCR fails.
    ///
    /// ## Example
    /// ```swift
    /// let processor = VisionOCRProcessor()
    /// let pdfURL = URL(filePath: "/path/to/document.pdf")
    /// let pageTexts = try await processor.extractTextFromPDF(at: pdfURL)
    ///
    /// for (index, text) in pageTexts.enumerated() {
    ///     print("--- Page \(index + 1) ---")
    ///     print(text)
    /// }
    /// ```
    ///
    /// ## Memory Considerations
    /// For large PDFs, each page is rendered at 2x scale for optimal OCR accuracy.
    /// This can consume significant memory. Consider processing pages in batches
    /// for very large documents.
    public func extractTextFromPDF(at url: URL) async throws -> [String] {
        guard let pdfDocument = CGPDFDocument(url as CFURL) else {
            throw ZoniError.loadingFailed(
                url: url,
                reason: "Unable to open PDF document. Ensure the file exists and is a valid PDF."
            )
        }

        let pageCount = pdfDocument.numberOfPages
        var pageTexts: [String] = []
        pageTexts.reserveCapacity(pageCount)

        // PDF pages are 1-indexed
        for pageIndex in 1...pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else {
                // If a page cannot be retrieved, add empty string and continue
                pageTexts.append("")
                continue
            }

            guard let pageImage = renderPDFPage(page) else {
                throw ZoniError.loadingFailed(
                    url: url,
                    reason: "Unable to render PDF page \(pageIndex) to image."
                )
            }

            let pageText = try await extractText(from: pageImage)
            pageTexts.append(pageText)
        }

        return pageTexts
    }

    // MARK: - Static Methods

    /// Returns the list of supported recognition languages for the specified level.
    ///
    /// - Parameter level: The recognition level to query. Defaults to `.accurate`.
    /// - Returns: An array of BCP-47 language codes supported for text recognition.
    ///
    /// ## Example
    /// ```swift
    /// let languages = VisionOCRProcessor.supportedLanguages()
    /// print("Supported languages: \(languages)")
    /// ```
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, *)
    public static func supportedLanguages(
        for level: VNRequestTextRecognitionLevel = .accurate
    ) -> [String] {
        do {
            return try VNRecognizeTextRequest.supportedRecognitionLanguages(
                for: level,
                revision: VNRecognizeTextRequestRevision3
            )
        } catch {
            return []
        }
    }

    // MARK: - Private Methods

    /// Loads a CGImage from a file URL.
    ///
    /// Uses ImageIO for efficient image loading from various formats.
    ///
    /// - Parameter url: The URL of the image file.
    /// - Returns: The loaded CGImage, or `nil` if loading fails.
    private func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return image
    }

    /// Renders a PDF page to a CGImage.
    ///
    /// Renders the page at 2x scale for optimal OCR accuracy while
    /// balancing memory usage.
    ///
    /// - Parameters:
    ///   - page: The PDF page to render.
    ///   - scale: The scale factor for rendering. Defaults to 2.0 for
    ///     optimal OCR accuracy.
    /// - Returns: The rendered CGImage, or `nil` if rendering fails.
    private func renderPDFPage(_ page: CGPDFPage, scale: CGFloat = 2.0) -> CGImage? {
        let pageRect = page.getBoxRect(.mediaBox)
        let width = Int(pageRect.width * scale)
        let height = Int(pageRect.height * scale)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // Fill with white background for better OCR results
        context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Scale and draw the PDF page
        context.scaleBy(x: scale, y: scale)
        context.drawPDFPage(page)

        return context.makeImage()
    }
}

// MARK: - CustomStringConvertible

@available(macOS 10.15, iOS 13.0, tvOS 13.0, *)
extension VisionOCRProcessor: CustomStringConvertible {

    /// A textual description of the processor.
    public nonisolated var description: String {
        "VisionOCRProcessor"
    }
}

#endif
