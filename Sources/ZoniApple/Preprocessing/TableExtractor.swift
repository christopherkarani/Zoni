// ZoniApple - Apple platform extensions for Zoni
//
// TableExtractor.swift - Vision-based table extraction from images

#if canImport(Vision)
import Vision
import Foundation
import CoreGraphics

// MARK: - ExtractedTable

/// A table extracted from an image with structured row/column data.
///
/// `ExtractedTable` represents tabular data recognized from an image using
/// Apple's Vision framework. It provides:
/// - **Structured Data**: Rows and columns as a 2D string array
/// - **Position Information**: Bounding box in normalized coordinates
/// - **Confidence Score**: How confident the extraction was
/// - **Export Formats**: Built-in Markdown and CSV conversion
///
/// ## Example Usage
/// ```swift
/// let extractor = TableExtractor()
/// let tables = try await extractor.extractTables(from: image)
///
/// for table in tables {
///     print("Found table with \(table.rows.count) rows")
///     print(table.markdown)  // Pretty Markdown output
///     print(table.csv)       // CSV for spreadsheets
/// }
/// ```
///
/// ## Limitations
/// - Merged cells are not detected; they appear as separate cells
/// - Complex nested tables may not be accurately parsed
/// - Very small text may have lower recognition accuracy
/// - Tables without clear boundaries may not be detected
public struct ExtractedTable: Sendable {

    // MARK: - Properties

    /// The table data organized as rows of cells.
    ///
    /// Each inner array represents a row, with strings representing cell contents.
    /// Empty cells are represented as empty strings.
    public let rows: [[String]]

    /// The bounding box of the table in normalized image coordinates.
    ///
    /// Coordinates are normalized (0.0 to 1.0) with origin at bottom-left
    /// (Vision framework convention).
    public let boundingBox: CGRect

    /// The confidence score of the table detection (0.0 to 1.0).
    ///
    /// Higher values indicate more confident detection. A score below 0.5
    /// may indicate uncertain table boundaries.
    public let confidence: Float

    // MARK: - Initialization

    /// Creates an extracted table with the specified data.
    ///
    /// - Parameters:
    ///   - rows: The table data as rows of cell strings.
    ///   - boundingBox: The normalized bounding box of the table.
    ///   - confidence: The detection confidence score (0.0 to 1.0).
    public init(rows: [[String]], boundingBox: CGRect, confidence: Float) {
        self.rows = rows
        self.boundingBox = boundingBox
        self.confidence = confidence
    }

    // MARK: - Export Formats

    /// Converts the table to Markdown format.
    ///
    /// The first row is treated as the header row with a separator line below it.
    /// Produces output like:
    /// ```
    /// | Header 1 | Header 2 | Header 3 |
    /// | --- | --- | --- |
    /// | Data 1 | Data 2 | Data 3 |
    /// ```
    ///
    /// - Returns: A Markdown-formatted string representing the table.
    ///   Returns an empty string if the table has no rows or the first row is empty.
    public var markdown: String {
        guard let firstRow = rows.first, !firstRow.isEmpty else {
            return ""
        }

        var lines: [String] = []

        // Header row
        lines.append("| " + firstRow.joined(separator: " | ") + " |")

        // Separator row
        lines.append("| " + firstRow.map { _ in "---" }.joined(separator: " | ") + " |")

        // Data rows
        for row in rows.dropFirst() {
            lines.append("| " + row.joined(separator: " | ") + " |")
        }

        return lines.joined(separator: "\n")
    }

    /// Converts the table to CSV (Comma-Separated Values) format.
    ///
    /// Cells containing commas, quotes, or newlines are properly escaped
    /// according to RFC 4180.
    ///
    /// - Returns: A CSV-formatted string representing the table.
    public var csv: String {
        rows.map { row in
            row.map { cell in
                let escaped = cell.replacing("\"", with: "\"\"")
                return cell.contains(",") || cell.contains("\"") || cell.contains("\n")
                    ? "\"\(escaped)\""
                    : escaped
            }.joined(separator: ",")
        }.joined(separator: "\n")
    }

    // MARK: - Computed Properties

    /// The number of rows in the table.
    public var rowCount: Int { rows.count }

    /// The number of columns in the table (based on the first row).
    public var columnCount: Int { rows.first?.count ?? 0 }

    /// Whether the table is empty (has no rows or no data).
    public var isEmpty: Bool { rows.isEmpty || rows.allSatisfy { $0.isEmpty } }
}

// MARK: - ExtractedTable + Equatable

extension ExtractedTable: Equatable {
    public static func == (lhs: ExtractedTable, rhs: ExtractedTable) -> Bool {
        lhs.rows == rhs.rows &&
        lhs.boundingBox == rhs.boundingBox &&
        lhs.confidence == rhs.confidence
    }
}

// MARK: - ExtractedTable + Hashable

extension ExtractedTable: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(rows)
        hasher.combine(boundingBox.origin.x)
        hasher.combine(boundingBox.origin.y)
        hasher.combine(boundingBox.size.width)
        hasher.combine(boundingBox.size.height)
        hasher.combine(confidence)
    }
}

// MARK: - TableExtractor

/// Extracts tabular data from images using Apple's Vision framework.
///
/// `TableExtractor` uses a multi-step process to identify and extract tables:
/// 1. **Rectangle Detection**: Finds rectangular regions that may contain tables
/// 2. **Text Recognition**: Extracts text with position information from each region
/// 3. **Row Grouping**: Groups text observations by vertical position
/// 4. **Column Sorting**: Sorts text within each row by horizontal position
///
/// ## Example Usage
/// ```swift
/// let extractor = TableExtractor()
///
/// // Extract tables from a CGImage
/// let tables = try await extractor.extractTables(from: image)
///
/// for table in tables {
///     print("Table with \(table.rowCount) rows and \(table.columnCount) columns")
///     print("Confidence: \(table.confidence)")
///     print(table.markdown)
/// }
/// ```
///
/// ## Algorithm Details
///
/// ### Rectangle Detection
/// Uses `VNDetectRectanglesRequest` to find table boundaries. Parameters are
/// tuned for typical table aspect ratios (0.1 to 10.0) and minimum sizes.
///
/// ### Text Recognition
/// Uses `VNRecognizeTextRequest` in `.accurate` mode for best quality.
/// Each text observation includes position data for row/column grouping.
///
/// ### Row Grouping
/// Text observations are grouped into rows based on vertical position.
/// A threshold of 2% of image height determines row boundaries.
///
/// ## Performance Considerations
/// - Processing time scales with image complexity and text density
/// - Larger images take longer but produce better recognition accuracy
/// - Consider downscaling very large images (>4000px) for faster processing
/// - First extraction may be slower due to Vision model loading
///
/// ## Limitations
/// - **Merged Cells**: Tables with merged cells may not be accurately parsed
/// - **Borderless Tables**: Tables without clear visual boundaries may be missed
/// - **Complex Layouts**: Nested tables or irregular layouts are not supported
/// - **Image Quality**: Low resolution or blurry images reduce accuracy
/// - **Handwritten Text**: Best results with printed/typed text
///
/// ## Thread Safety
/// This actor is safe to use from any concurrency context.
@available(macOS 13.0, iOS 16.0, *)
public actor TableExtractor {

    // MARK: - Configuration

    /// Configuration options for table extraction.
    public struct Configuration: Sendable {

        /// The row grouping threshold as a fraction of image height.
        ///
        /// Text observations within this vertical distance are considered
        /// to be in the same row. Default is 0.02 (2% of image height).
        public var rowThreshold: CGFloat

        /// The minimum aspect ratio for detected rectangles.
        ///
        /// Tables narrower than this ratio are ignored. Default is 0.1.
        public var minimumAspectRatio: Float

        /// The maximum aspect ratio for detected rectangles.
        ///
        /// Tables wider than this ratio are ignored. Default is 10.0.
        public var maximumAspectRatio: Float

        /// The minimum size for detected rectangles as a fraction of image size.
        ///
        /// Smaller rectangles are ignored. Default is 0.1 (10% of image).
        public var minimumSize: Float

        /// The maximum number of tables to detect.
        ///
        /// Default is 10. Set to 0 for unlimited.
        public var maximumTables: Int

        /// The text recognition level.
        ///
        /// Use `.accurate` for best quality, `.fast` for speed.
        public var recognitionLevel: VNRequestTextRecognitionLevel

        /// Creates a configuration with default values.
        public init(
            rowThreshold: CGFloat = 0.02,
            minimumAspectRatio: Float = 0.1,
            maximumAspectRatio: Float = 10.0,
            minimumSize: Float = 0.1,
            maximumTables: Int = 10,
            recognitionLevel: VNRequestTextRecognitionLevel = .accurate
        ) {
            self.rowThreshold = rowThreshold
            self.minimumAspectRatio = minimumAspectRatio
            self.maximumAspectRatio = maximumAspectRatio
            self.minimumSize = minimumSize
            self.maximumTables = maximumTables
            self.recognitionLevel = recognitionLevel
        }

        /// Default configuration suitable for most use cases.
        public static let `default` = Configuration()

        /// Configuration optimized for faster processing.
        public static let fast = Configuration(
            rowThreshold: 0.03,
            minimumAspectRatio: 0.2,
            maximumAspectRatio: 5.0,
            minimumSize: 0.15,
            maximumTables: 5,
            recognitionLevel: .fast
        )

        /// Configuration optimized for accuracy.
        public static let accurate = Configuration(
            rowThreshold: 0.015,
            minimumAspectRatio: 0.05,
            maximumAspectRatio: 20.0,
            minimumSize: 0.05,
            maximumTables: 20,
            recognitionLevel: .accurate
        )
    }

    // MARK: - Properties

    /// The configuration used for table extraction.
    private let configuration: Configuration

    // MARK: - Initialization

    /// Creates a table extractor with the specified configuration.
    ///
    /// - Parameter configuration: The extraction configuration. Defaults to `.default`.
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    // MARK: - Public Methods

    /// Extracts tables from an image.
    ///
    /// This method performs multi-step table extraction:
    /// 1. Detects rectangular regions that may contain tables
    /// 2. For each region, extracts text with position information
    /// 3. Groups text into rows based on vertical position
    /// 4. Sorts text within rows by horizontal position
    ///
    /// If no rectangular regions are found, the method attempts to extract
    /// a table from the entire image (useful for screenshots or single-table images).
    ///
    /// - Parameter image: The image to extract tables from.
    /// - Returns: An array of extracted tables, sorted by position (top to bottom).
    /// - Throws: Vision framework errors if image processing fails.
    ///
    /// ## Example
    /// ```swift
    /// let extractor = TableExtractor()
    /// let tables = try await extractor.extractTables(from: myImage)
    ///
    /// if let firstTable = tables.first {
    ///     print(firstTable.markdown)
    /// }
    /// ```
    public func extractTables(from image: CGImage) async throws -> [ExtractedTable] {
        // Detect table regions
        let regions = try await detectTableRegions(in: image)

        // If no regions found, try extracting from the full image
        if regions.isEmpty {
            let observations = try await recognizeText(in: image)
            guard !observations.isEmpty else {
                return []
            }

            let rows = groupIntoRows(observations)
            guard !rows.isEmpty else {
                return []
            }

            return [ExtractedTable(
                rows: rows,
                boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1),
                confidence: 0.5
            )]
        }

        // Extract table from each region
        var tables: [ExtractedTable] = []

        for region in regions {
            guard let croppedImage = cropImage(image, to: region) else {
                continue
            }

            let observations = try await recognizeText(in: croppedImage)
            guard !observations.isEmpty else {
                continue
            }

            let rows = groupIntoRows(observations)
            guard !rows.isEmpty else {
                continue
            }

            let table = ExtractedTable(
                rows: rows,
                boundingBox: region.boundingBox,
                confidence: region.confidence
            )

            tables.append(table)
        }

        // Sort tables by vertical position (top to bottom in image coordinates)
        return tables.sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
    }

    /// Extracts text observations from an image region.
    ///
    /// This is useful for custom processing pipelines where you want
    /// direct access to text positions.
    ///
    /// - Parameter image: The image to process.
    /// - Returns: An array of tuples containing recognized text and bounding boxes.
    /// - Throws: Vision framework errors if text recognition fails.
    public func extractTextObservations(
        from image: CGImage
    ) async throws -> [(text: String, bounds: CGRect)] {
        try await recognizeText(in: image)
    }

    // MARK: - Private Methods

    /// Detects rectangular regions that may contain tables.
    ///
    /// Uses `VNDetectRectanglesRequest` with parameters tuned for table detection.
    ///
    /// - Parameter image: The image to search for rectangles.
    /// - Returns: An array of rectangle observations.
    /// - Throws: Vision framework errors if detection fails.
    private func detectTableRegions(in image: CGImage) async throws -> [VNRectangleObservation] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                // SAFETY: VNRectangleObservation is not marked Sendable by Apple, but the
                // objects returned from Vision request results are effectively immutable after
                // creation. The Vision framework creates these as read-only value snapshots
                // within the completion handler, making them safe to transfer across actor
                // isolation boundaries despite the missing Sendable conformance.
                nonisolated(unsafe) let observations = request.results as? [VNRectangleObservation] ?? []
                continuation.resume(returning: observations)
            }

            request.minimumAspectRatio = configuration.minimumAspectRatio
            request.maximumAspectRatio = configuration.maximumAspectRatio
            request.minimumSize = configuration.minimumSize
            request.maximumObservations = configuration.maximumTables

            let handler = VNImageRequestHandler(cgImage: image, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Recognizes text in an image with position information.
    ///
    /// Uses `VNRecognizeTextRequest` to extract text and bounding boxes.
    ///
    /// - Parameter image: The image to recognize text from.
    /// - Returns: An array of tuples containing text and normalized bounding boxes.
    /// - Throws: Vision framework errors if recognition fails.
    private func recognizeText(
        in image: CGImage
    ) async throws -> [(text: String, bounds: CGRect)] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let results = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { observation -> (String, CGRect)? in
                        guard let text = observation.topCandidates(1).first?.string else {
                            return nil
                        }
                        return (text, observation.boundingBox)
                    }

                continuation.resume(returning: results)
            }

            request.recognitionLevel = configuration.recognitionLevel

            let handler = VNImageRequestHandler(cgImage: image, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Groups text observations into rows based on vertical position.
    ///
    /// Text observations with similar Y coordinates (within the row threshold)
    /// are grouped together and sorted by X coordinate.
    ///
    /// - Parameter observations: The text observations to group.
    /// - Returns: A 2D array where each inner array represents a row of cell text.
    private func groupIntoRows(_ observations: [(String, CGRect)]) -> [[String]] {
        guard !observations.isEmpty else { return [] }

        // Sort by Y (top to bottom in image coordinates), then X (left to right)
        // Vision uses bottom-left origin, so higher Y values are at the top
        let sorted = observations.sorted { a, b in
            let yDiff = abs(a.1.midY - b.1.midY)
            if yDiff < configuration.rowThreshold {
                // Same row - sort by X
                return a.1.minX < b.1.minX
            }
            // Different rows - sort by Y (descending for top-to-bottom)
            return a.1.midY > b.1.midY
        }

        var rows: [[String]] = []
        var currentRow: [String] = []
        var lastY: CGFloat = sorted[0].1.midY

        for (text, rect) in sorted {
            if abs(rect.midY - lastY) > configuration.rowThreshold {
                // New row
                if !currentRow.isEmpty {
                    rows.append(currentRow)
                }
                currentRow = [text]
            } else {
                currentRow.append(text)
            }
            lastY = rect.midY
        }

        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }

    /// Crops an image to a rectangle observation region.
    ///
    /// Converts normalized Vision coordinates to pixel coordinates and crops.
    ///
    /// - Parameters:
    ///   - image: The source image.
    ///   - region: The rectangle observation defining the crop region.
    /// - Returns: The cropped image, or `nil` if cropping fails.
    private func cropImage(_ image: CGImage, to region: VNRectangleObservation) -> CGImage? {
        let bounds = region.boundingBox

        // Convert normalized coordinates to pixel coordinates
        // Vision uses bottom-left origin; CoreGraphics uses top-left
        let x = Int(bounds.minX * CGFloat(image.width))
        let y = Int((1 - bounds.maxY) * CGFloat(image.height))
        let width = Int(bounds.width * CGFloat(image.width))
        let height = Int(bounds.height * CGFloat(image.height))

        // Validate crop region
        guard width > 0, height > 0 else {
            return nil
        }

        let cropRect = CGRect(x: x, y: y, width: width, height: height)
        return image.cropping(to: cropRect)
    }
}

// MARK: - TableExtractor + CustomStringConvertible

@available(macOS 13.0, iOS 16.0, *)
extension TableExtractor: CustomStringConvertible {
    public nonisolated var description: String {
        "TableExtractor(recognitionLevel: \(configuration.recognitionLevel == .accurate ? "accurate" : "fast"))"
    }
}

// MARK: - ExtractedTable + CustomStringConvertible

extension ExtractedTable: CustomStringConvertible {
    public var description: String {
        let formattedConfidence = String(format: "%.2f", confidence)
        return "ExtractedTable(rows: \(rowCount), columns: \(columnCount), confidence: \(formattedConfidence))"
    }
}
#endif
