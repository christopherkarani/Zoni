import Testing
import Foundation
@testable import Zoni

@Suite("Zoni Core Tests")
struct ZoniTests {

    @Test("Package builds successfully")
    func packageBuilds() {
        // This test verifies the package structure is correct
        #expect(true)
    }
}

// MARK: - MetadataValue Tests

@Suite("MetadataValue Tests")
struct MetadataValueTests {

    // MARK: - Literal Expressions

    @Test("String literal creates string value")
    func stringLiteral() {
        let value: MetadataValue = "hello"
        #expect(value.stringValue == "hello")
    }

    @Test("Integer literal creates int value")
    func integerLiteral() {
        let value: MetadataValue = 42
        #expect(value.intValue == 42)
    }

    @Test("Double literal creates double value")
    func doubleLiteral() {
        let value: MetadataValue = 3.14
        #expect(value.doubleValue == 3.14)
    }

    @Test("Boolean literal creates bool value")
    func booleanLiteral() {
        let valueTrue: MetadataValue = true
        let valueFalse: MetadataValue = false
        #expect(valueTrue.boolValue == true)
        #expect(valueFalse.boolValue == false)
    }

    @Test("Array literal creates array value")
    func arrayLiteral() {
        let value: MetadataValue = ["one", "two", "three"]
        #expect(value.arrayValue?.count == 3)
        #expect(value.arrayValue?[0].stringValue == "one")
        #expect(value.arrayValue?[1].stringValue == "two")
        #expect(value.arrayValue?[2].stringValue == "three")
    }

    @Test("Dictionary literal creates dictionary value")
    func dictionaryLiteral() {
        let value: MetadataValue = ["key1": "value1", "key2": 42]
        #expect(value.dictionaryValue?["key1"]?.stringValue == "value1")
        #expect(value.dictionaryValue?["key2"]?.intValue == 42)
    }

    @Test("Nil literal creates null value")
    func nilLiteral() {
        let value: MetadataValue = nil
        #expect(value.isNull == true)
    }

    // MARK: - Accessor Properties

    @Test("stringValue returns nil for non-string")
    func stringValueReturnsNilForNonString() {
        let value: MetadataValue = 42
        #expect(value.stringValue == nil)
    }

    @Test("intValue returns nil for non-int")
    func intValueReturnsNilForNonInt() {
        let value: MetadataValue = "hello"
        #expect(value.intValue == nil)
    }

    @Test("doubleValue returns nil for non-double")
    func doubleValueReturnsNilForNonDouble() {
        let value: MetadataValue = "hello"
        #expect(value.doubleValue == nil)
    }

    @Test("boolValue returns nil for non-bool")
    func boolValueReturnsNilForNonBool() {
        let value: MetadataValue = "hello"
        #expect(value.boolValue == nil)
    }

    @Test("arrayValue returns nil for non-array")
    func arrayValueReturnsNilForNonArray() {
        let value: MetadataValue = "hello"
        #expect(value.arrayValue == nil)
    }

    @Test("dictionaryValue returns nil for non-dictionary")
    func dictionaryValueReturnsNilForNonDictionary() {
        let value: MetadataValue = "hello"
        #expect(value.dictionaryValue == nil)
    }

    @Test("numericValue returns Double for int")
    func numericValueFromInt() {
        let value: MetadataValue = 42
        #expect(value.numericValue == 42.0)
    }

    @Test("numericValue returns Double for double")
    func numericValueFromDouble() {
        let value: MetadataValue = 3.14
        #expect(value.numericValue == 3.14)
    }

    @Test("numericValue returns nil for non-numeric")
    func numericValueReturnsNilForNonNumeric() {
        let value: MetadataValue = "hello"
        #expect(value.numericValue == nil)
    }

    @Test("isNull returns true only for null")
    func isNullProperty() {
        let nullValue: MetadataValue = nil
        let stringValue: MetadataValue = "hello"
        #expect(nullValue.isNull == true)
        #expect(stringValue.isNull == false)
    }

    // MARK: - Codable Round-Trip

    @Test("Codable round-trip preserves string value")
    func codableRoundTripString() throws {
        let original: MetadataValue = "test string"
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MetadataValue.self, from: data)

        #expect(decoded == original)
        #expect(decoded.stringValue == "test string")
    }

    @Test("Codable round-trip preserves int value")
    func codableRoundTripInt() throws {
        let original: MetadataValue = 42
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MetadataValue.self, from: data)

        #expect(decoded == original)
        #expect(decoded.intValue == 42)
    }

    @Test("Codable round-trip preserves double value")
    func codableRoundTripDouble() throws {
        let original: MetadataValue = 3.14159
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MetadataValue.self, from: data)

        #expect(decoded == original)
    }

    @Test("Codable round-trip preserves bool value")
    func codableRoundTripBool() throws {
        let original: MetadataValue = true
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MetadataValue.self, from: data)

        #expect(decoded == original)
        #expect(decoded.boolValue == true)
    }

    @Test("Codable round-trip preserves array value")
    func codableRoundTripArray() throws {
        let original: MetadataValue = ["one", "two", 3]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MetadataValue.self, from: data)

        #expect(decoded == original)
    }

    @Test("Codable round-trip preserves dictionary value")
    func codableRoundTripDictionary() throws {
        let original: MetadataValue = ["name": "test", "count": 42]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MetadataValue.self, from: data)

        #expect(decoded == original)
    }

    @Test("Codable round-trip preserves null value")
    func codableRoundTripNull() throws {
        let original: MetadataValue = nil
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MetadataValue.self, from: data)

        #expect(decoded == original)
        #expect(decoded.isNull == true)
    }

    // MARK: - Equality

    @Test("Same string values are equal")
    func stringEquality() {
        let value1: MetadataValue = "hello"
        let value2: MetadataValue = "hello"
        let value3: MetadataValue = "world"
        #expect(value1 == value2)
        #expect(value1 != value3)
    }

    @Test("Same int values are equal")
    func intEquality() {
        let value1: MetadataValue = 42
        let value2: MetadataValue = 42
        let value3: MetadataValue = 100
        #expect(value1 == value2)
        #expect(value1 != value3)
    }

    @Test("Different types are not equal")
    func differentTypesNotEqual() {
        let stringValue: MetadataValue = "42"
        let intValue: MetadataValue = 42
        #expect(stringValue != intValue)
    }

    // MARK: - Description

    @Test("Description returns readable string")
    func descriptionProperty() {
        let stringValue: MetadataValue = "hello"
        let intValue: MetadataValue = 42
        let nullValue: MetadataValue = nil

        #expect(stringValue.description == "\"hello\"")
        #expect(intValue.description == "42")
        #expect(nullValue.description == "null")
    }
}

// MARK: - MetadataFilter Tests

@Suite("MetadataFilter Tests")
struct MetadataFilterTests {

    @Test("Single condition filter construction")
    func singleConditionFilter() {
        let filter = MetadataFilter(.equals("status", "active"))
        #expect(filter.conditions.count == 1)
    }

    @Test("Multiple conditions filter construction")
    func multipleConditionsFilter() {
        let filter = MetadataFilter(conditions: [
            .equals("status", "active"),
            .greaterThan("count", 10.0)
        ])
        #expect(filter.conditions.count == 2)
    }

    @Test("Static equals constructor")
    func equalsStaticConstructor() {
        let filter = MetadataFilter.equals("field", "value")
        #expect(filter.conditions.count == 1)
        if case .equals(let field, let value) = filter.conditions.first {
            #expect(field == "field")
            #expect(value.stringValue == "value")
        } else {
            Issue.record("Expected equals operator")
        }
    }

    @Test("Static notEquals constructor")
    func notEqualsStaticConstructor() {
        let filter = MetadataFilter.notEquals("field", "value")
        #expect(filter.conditions.count == 1)
        if case .notEquals(let field, let value) = filter.conditions.first {
            #expect(field == "field")
            #expect(value.stringValue == "value")
        } else {
            Issue.record("Expected notEquals operator")
        }
    }

    @Test("Static greaterThan constructor")
    func greaterThanStaticConstructor() {
        let filter = MetadataFilter.greaterThan("rating", 4.5)
        #expect(filter.conditions.count == 1)
        if case .greaterThan(let field, let value) = filter.conditions.first {
            #expect(field == "rating")
            #expect(value == 4.5)
        } else {
            Issue.record("Expected greaterThan operator")
        }
    }

    @Test("Static lessThan constructor")
    func lessThanStaticConstructor() {
        let filter = MetadataFilter.lessThan("price", 100.0)
        #expect(filter.conditions.count == 1)
        if case .lessThan(let field, let value) = filter.conditions.first {
            #expect(field == "price")
            #expect(value == 100.0)
        } else {
            Issue.record("Expected lessThan operator")
        }
    }

    @Test("Static and constructor")
    func andStaticConstructor() {
        let filter = MetadataFilter.and([
            .equals("status", "published"),
            .greaterThan("rating", 4.0)
        ])
        #expect(filter.conditions.count == 1)
        if case .and(let filters) = filter.conditions.first {
            #expect(filters.count == 2)
        } else {
            Issue.record("Expected and operator")
        }
    }

    @Test("Static or constructor")
    func orStaticConstructor() {
        let filter = MetadataFilter.or([
            .equals("type", "article"),
            .equals("type", "blog")
        ])
        #expect(filter.conditions.count == 1)
        if case .or(let filters) = filter.conditions.first {
            #expect(filters.count == 2)
        } else {
            Issue.record("Expected or operator")
        }
    }

    @Test("Static not constructor")
    func notStaticConstructor() {
        let innerFilter = MetadataFilter.equals("draft", true)
        let filter = MetadataFilter.not(innerFilter)
        #expect(filter.conditions.count == 1)
        if case .not(let negatedFilter) = filter.conditions.first {
            #expect(negatedFilter == innerFilter)
        } else {
            Issue.record("Expected not operator")
        }
    }

    @Test("Static contains constructor")
    func containsStaticConstructor() {
        let filter = MetadataFilter.contains("title", "Swift")
        #expect(filter.conditions.count == 1)
        if case .contains(let field, let substring) = filter.conditions.first {
            #expect(field == "title")
            #expect(substring == "Swift")
        } else {
            Issue.record("Expected contains operator")
        }
    }

    @Test("Static startsWith constructor")
    func startsWithStaticConstructor() {
        let filter = MetadataFilter.startsWith("name", "Dr.")
        #expect(filter.conditions.count == 1)
        if case .startsWith(let field, let prefix) = filter.conditions.first {
            #expect(field == "name")
            #expect(prefix == "Dr.")
        } else {
            Issue.record("Expected startsWith operator")
        }
    }

    @Test("Static endsWith constructor")
    func endsWithStaticConstructor() {
        let filter = MetadataFilter.endsWith("filename", ".swift")
        #expect(filter.conditions.count == 1)
        if case .endsWith(let field, let suffix) = filter.conditions.first {
            #expect(field == "filename")
            #expect(suffix == ".swift")
        } else {
            Issue.record("Expected endsWith operator")
        }
    }

    @Test("Static in constructor")
    func inStaticConstructor() {
        let filter = MetadataFilter.in("category", ["tech", "science", "health"])
        #expect(filter.conditions.count == 1)
        if case .in(let field, let values) = filter.conditions.first {
            #expect(field == "category")
            #expect(values.count == 3)
        } else {
            Issue.record("Expected in operator")
        }
    }

    @Test("Static exists constructor")
    func existsStaticConstructor() {
        let filter = MetadataFilter.exists("thumbnail")
        #expect(filter.conditions.count == 1)
        if case .exists(let field) = filter.conditions.first {
            #expect(field == "thumbnail")
        } else {
            Issue.record("Expected exists operator")
        }
    }

    @Test("Filter equality")
    func filterEquality() {
        let filter1 = MetadataFilter.equals("status", "active")
        let filter2 = MetadataFilter.equals("status", "active")
        let filter3 = MetadataFilter.equals("status", "inactive")
        #expect(filter1 == filter2)
        #expect(filter1 != filter3)
    }
}

// MARK: - Embedding Tests

@Suite("Embedding Tests")
struct EmbeddingTests {

    // MARK: - Cosine Similarity

    @Test("Cosine similarity of identical vectors is 1.0")
    func cosineSimilarityIdentical() {
        let e1 = Embedding(vector: [1.0, 0.0, 0.0])
        let e2 = Embedding(vector: [1.0, 0.0, 0.0])
        let similarity = e1.cosineSimilarity(to: e2)
        #expect(abs(similarity - 1.0) < 0.0001)
    }

    @Test("Cosine similarity of orthogonal vectors is 0.0")
    func cosineSimilarityOrthogonal() {
        let e1 = Embedding(vector: [1.0, 0.0, 0.0])
        let e2 = Embedding(vector: [0.0, 1.0, 0.0])
        let similarity = e1.cosineSimilarity(to: e2)
        #expect(abs(similarity - 0.0) < 0.0001)
    }

    @Test("Cosine similarity of opposite vectors is -1.0")
    func cosineSimilarityOpposite() {
        let e1 = Embedding(vector: [1.0, 0.0, 0.0])
        let e2 = Embedding(vector: [-1.0, 0.0, 0.0])
        let similarity = e1.cosineSimilarity(to: e2)
        #expect(abs(similarity - (-1.0)) < 0.0001)
    }

    @Test("Cosine similarity handles non-unit vectors")
    func cosineSimilarityNonUnit() {
        let e1 = Embedding(vector: [3.0, 0.0, 0.0])
        let e2 = Embedding(vector: [5.0, 0.0, 0.0])
        let similarity = e1.cosineSimilarity(to: e2)
        // Same direction, should be 1.0 regardless of magnitude
        #expect(abs(similarity - 1.0) < 0.0001)
    }

    // MARK: - Euclidean Distance

    @Test("Euclidean distance of identical vectors is 0.0")
    func euclideanDistanceIdentical() {
        let e1 = Embedding(vector: [1.0, 2.0, 3.0])
        let e2 = Embedding(vector: [1.0, 2.0, 3.0])
        let distance = e1.euclideanDistance(to: e2)
        #expect(abs(distance - 0.0) < 0.0001)
    }

    @Test("Euclidean distance calculation")
    func euclideanDistanceCalculation() {
        let e1 = Embedding(vector: [0.0, 0.0, 0.0])
        let e2 = Embedding(vector: [3.0, 4.0, 0.0])
        let distance = e1.euclideanDistance(to: e2)
        // sqrt(9 + 16) = sqrt(25) = 5.0
        #expect(abs(distance - 5.0) < 0.0001)
    }

    @Test("Euclidean distance is symmetric")
    func euclideanDistanceSymmetric() {
        let e1 = Embedding(vector: [1.0, 2.0, 3.0])
        let e2 = Embedding(vector: [4.0, 5.0, 6.0])
        let distance1 = e1.euclideanDistance(to: e2)
        let distance2 = e2.euclideanDistance(to: e1)
        #expect(abs(distance1 - distance2) < 0.0001)
    }

    // MARK: - Dot Product

    @Test("Dot product calculation")
    func dotProductCalculation() {
        let e1 = Embedding(vector: [1.0, 2.0, 3.0])
        let e2 = Embedding(vector: [4.0, 5.0, 6.0])
        let dot = e1.dotProduct(with: e2)
        // 1*4 + 2*5 + 3*6 = 4 + 10 + 18 = 32
        #expect(abs(dot - 32.0) < 0.0001)
    }

    @Test("Dot product of orthogonal vectors is 0.0")
    func dotProductOrthogonal() {
        let e1 = Embedding(vector: [1.0, 0.0, 0.0])
        let e2 = Embedding(vector: [0.0, 1.0, 0.0])
        let dot = e1.dotProduct(with: e2)
        #expect(abs(dot - 0.0) < 0.0001)
    }

    @Test("Dot product is commutative")
    func dotProductCommutative() {
        let e1 = Embedding(vector: [1.0, 2.0, 3.0])
        let e2 = Embedding(vector: [4.0, 5.0, 6.0])
        let dot1 = e1.dotProduct(with: e2)
        let dot2 = e2.dotProduct(with: e1)
        #expect(abs(dot1 - dot2) < 0.0001)
    }

    // MARK: - Magnitude

    @Test("Magnitude of unit vector is 1.0")
    func magnitudeUnitVector() {
        let e = Embedding(vector: [1.0, 0.0, 0.0])
        let mag = e.magnitude()
        #expect(abs(mag - 1.0) < 0.0001)
    }

    @Test("Magnitude calculation")
    func magnitudeCalculation() {
        let e = Embedding(vector: [3.0, 4.0, 0.0])
        let mag = e.magnitude()
        // sqrt(9 + 16) = sqrt(25) = 5.0
        #expect(abs(mag - 5.0) < 0.0001)
    }

    @Test("Magnitude of zero vector is 0.0")
    func magnitudeZeroVector() {
        let e = Embedding(vector: [0.0, 0.0, 0.0])
        let mag = e.magnitude()
        #expect(abs(mag - 0.0) < 0.0001)
    }

    // MARK: - Normalized

    @Test("Normalized vector has magnitude 1.0")
    func normalizedMagnitude() {
        let e = Embedding(vector: [3.0, 4.0, 0.0])
        let normalized = e.normalized()
        let mag = normalized.magnitude()
        #expect(abs(mag - 1.0) < 0.0001)
    }

    @Test("Normalized preserves direction")
    func normalizedPreservesDirection() {
        let e = Embedding(vector: [3.0, 4.0, 0.0])
        let normalized = e.normalized()
        // Normalized should be [0.6, 0.8, 0.0]
        #expect(abs(normalized.vector[0] - 0.6) < 0.0001)
        #expect(abs(normalized.vector[1] - 0.8) < 0.0001)
        #expect(abs(normalized.vector[2] - 0.0) < 0.0001)
    }

    @Test("Normalized zero vector returns original")
    func normalizedZeroVector() {
        let e = Embedding(vector: [0.0, 0.0, 0.0])
        let normalized = e.normalized()
        #expect(normalized == e)
    }

    @Test("Normalized preserves model info")
    func normalizedPreservesModel() {
        let e = Embedding(vector: [3.0, 4.0], model: "test-model")
        let normalized = e.normalized()
        #expect(normalized.model == "test-model")
    }

    // MARK: - Edge Cases

    @Test("Empty vectors return 0.0 for cosine similarity")
    func emptyVectorsCosineSimilarity() {
        let e1 = Embedding(vector: [])
        let e2 = Embedding(vector: [])
        let similarity = e1.cosineSimilarity(to: e2)
        #expect(similarity == 0.0)
    }

    @Test("Empty vectors return 0.0 for euclidean distance")
    func emptyVectorsEuclideanDistance() {
        let e1 = Embedding(vector: [])
        let e2 = Embedding(vector: [])
        let distance = e1.euclideanDistance(to: e2)
        #expect(distance == 0.0)
    }

    @Test("Empty vectors return 0.0 for magnitude")
    func emptyVectorsMagnitude() {
        let e = Embedding(vector: [])
        let mag = e.magnitude()
        #expect(mag == 0.0)
    }

    @Test("Dimension mismatch returns 0.0 for cosine similarity")
    func dimensionMismatchCosineSimilarity() {
        let e1 = Embedding(vector: [1.0, 2.0, 3.0])
        let e2 = Embedding(vector: [1.0, 2.0])
        let similarity = e1.cosineSimilarity(to: e2)
        #expect(similarity == 0.0)
    }

    @Test("Dimension mismatch returns 0.0 for euclidean distance")
    func dimensionMismatchEuclideanDistance() {
        let e1 = Embedding(vector: [1.0, 2.0, 3.0])
        let e2 = Embedding(vector: [1.0, 2.0])
        let distance = e1.euclideanDistance(to: e2)
        #expect(distance == 0.0)
    }

    @Test("Dimension mismatch returns 0.0 for dot product")
    func dimensionMismatchDotProduct() {
        let e1 = Embedding(vector: [1.0, 2.0, 3.0])
        let e2 = Embedding(vector: [1.0, 2.0])
        let dot = e1.dotProduct(with: e2)
        #expect(dot == 0.0)
    }

    // MARK: - Properties

    @Test("Dimensions property returns vector count")
    func dimensionsProperty() {
        let e = Embedding(vector: [1.0, 2.0, 3.0, 4.0, 5.0])
        #expect(e.dimensions == 5)
    }

    @Test("Model property is stored correctly")
    func modelProperty() {
        let e = Embedding(vector: [1.0, 2.0], model: "text-embedding-3-small")
        #expect(e.model == "text-embedding-3-small")
    }

    @Test("Model defaults to nil")
    func modelDefaultsToNil() {
        let e = Embedding(vector: [1.0, 2.0])
        #expect(e.model == nil)
    }

    // MARK: - Equality and Hashable

    @Test("Identical embeddings are equal")
    func embeddingEquality() {
        let e1 = Embedding(vector: [1.0, 2.0, 3.0], model: "test")
        let e2 = Embedding(vector: [1.0, 2.0, 3.0], model: "test")
        #expect(e1 == e2)
    }

    @Test("Different vectors are not equal")
    func embeddingInequalityVector() {
        let e1 = Embedding(vector: [1.0, 2.0, 3.0])
        let e2 = Embedding(vector: [1.0, 2.0, 4.0])
        #expect(e1 != e2)
    }

    @Test("Different models are not equal")
    func embeddingInequalityModel() {
        let e1 = Embedding(vector: [1.0, 2.0], model: "model-a")
        let e2 = Embedding(vector: [1.0, 2.0], model: "model-b")
        #expect(e1 != e2)
    }
}

// MARK: - Document Tests

@Suite("Document Tests")
struct DocumentTests {

    @Test("Document creation with default values")
    func documentDefaultValues() {
        let doc = Document(content: "Test content")
        #expect(doc.content == "Test content")
        #expect(!doc.id.isEmpty)
        #expect(doc.metadata.source == nil)
        #expect(doc.metadata.title == nil)
    }

    @Test("Document creation with custom ID")
    func documentCustomId() {
        let doc = Document(id: "custom-id-123", content: "Test content")
        #expect(doc.id == "custom-id-123")
    }

    @Test("Document creation with custom metadata")
    func documentCustomMetadata() {
        let metadata = DocumentMetadata(
            source: "wikipedia",
            title: "Swift Programming",
            author: "Apple Inc.",
            url: URL(string: "https://swift.org"),
            mimeType: "text/plain",
            custom: ["category": "technology", "rating": 5]
        )
        let doc = Document(content: "Swift is awesome", metadata: metadata)

        #expect(doc.metadata.source == "wikipedia")
        #expect(doc.metadata.title == "Swift Programming")
        #expect(doc.metadata.author == "Apple Inc.")
        #expect(doc.metadata.url?.absoluteString == "https://swift.org")
        #expect(doc.metadata.mimeType == "text/plain")
        #expect(doc.metadata.custom["category"]?.stringValue == "technology")
        #expect(doc.metadata.custom["rating"]?.intValue == 5)
    }

    @Test("Document wordCount calculation")
    func documentWordCount() {
        let doc = Document(content: "This is a test document with seven words")
        #expect(doc.wordCount == 8)
    }

    @Test("Document wordCount handles multiple whitespace")
    func documentWordCountMultipleWhitespace() {
        let doc = Document(content: "Word1   Word2\n\nWord3\tWord4")
        #expect(doc.wordCount == 4)
    }

    @Test("Document wordCount for empty content")
    func documentWordCountEmpty() {
        let doc = Document(content: "")
        #expect(doc.wordCount == 0)
    }

    @Test("Document characterCount calculation")
    func documentCharacterCount() {
        let doc = Document(content: "Hello, World!")
        #expect(doc.characterCount == 13)
    }

    @Test("Document characterCount for empty content")
    func documentCharacterCountEmpty() {
        let doc = Document(content: "")
        #expect(doc.characterCount == 0)
    }

    @Test("DocumentMetadata subscript access")
    func documentMetadataSubscript() {
        var metadata = DocumentMetadata()
        metadata["customKey"] = "customValue"
        #expect(metadata["customKey"]?.stringValue == "customValue")
    }

    @Test("Document Identifiable conformance")
    func documentIdentifiable() {
        let doc = Document(id: "test-id", content: "Content")
        #expect(doc.id == "test-id")
    }

    @Test("Document equality")
    func documentEquality() {
        let date = Date()
        let doc1 = Document(id: "same-id", content: "Same content", createdAt: date)
        let doc2 = Document(id: "same-id", content: "Same content", createdAt: date)
        #expect(doc1 == doc2)
    }
}

// MARK: - Chunk Tests

@Suite("Chunk Tests")
struct ChunkTests {

    @Test("Chunk creation with basic parameters")
    func chunkCreation() {
        let metadata = ChunkMetadata(documentId: "doc-1", index: 0)
        let chunk = Chunk(content: "This is chunk content", metadata: metadata)

        #expect(chunk.content == "This is chunk content")
        #expect(chunk.metadata.documentId == "doc-1")
        #expect(chunk.metadata.index == 0)
        #expect(chunk.embedding == nil)
    }

    @Test("Chunk creation with custom ID")
    func chunkCustomId() {
        let metadata = ChunkMetadata(documentId: "doc-1", index: 0)
        let chunk = Chunk(id: "chunk-abc", content: "Content", metadata: metadata)
        #expect(chunk.id == "chunk-abc")
    }

    @Test("Chunk creation with full metadata")
    func chunkFullMetadata() {
        let metadata = ChunkMetadata(
            documentId: "doc-123",
            index: 5,
            startOffset: 100,
            endOffset: 200,
            source: "/path/to/file.txt",
            custom: ["section": "Introduction"]
        )
        let chunk = Chunk(content: "Chunk text", metadata: metadata)

        #expect(chunk.metadata.documentId == "doc-123")
        #expect(chunk.metadata.index == 5)
        #expect(chunk.metadata.startOffset == 100)
        #expect(chunk.metadata.endOffset == 200)
        #expect(chunk.metadata.source == "/path/to/file.txt")
        #expect(chunk.metadata.custom["section"]?.stringValue == "Introduction")
    }

    @Test("Chunk withEmbedding creates new chunk with embedding")
    func chunkWithEmbedding() {
        let metadata = ChunkMetadata(documentId: "doc-1", index: 0)
        let chunk = Chunk(id: "chunk-1", content: "Original content", metadata: metadata)
        let embedding = Embedding(vector: [0.1, 0.2, 0.3], model: "test-model")

        let embeddedChunk = chunk.withEmbedding(embedding)

        #expect(embeddedChunk.id == chunk.id)
        #expect(embeddedChunk.content == chunk.content)
        #expect(embeddedChunk.metadata == chunk.metadata)
        #expect(embeddedChunk.embedding == embedding)
        // Original chunk should be unchanged
        #expect(chunk.embedding == nil)
    }

    @Test("Chunk wordCount calculation")
    func chunkWordCount() {
        let metadata = ChunkMetadata(documentId: "doc-1", index: 0)
        let chunk = Chunk(content: "One two three four five", metadata: metadata)
        #expect(chunk.wordCount == 5)
    }

    @Test("Chunk characterCount calculation")
    func chunkCharacterCount() {
        let metadata = ChunkMetadata(documentId: "doc-1", index: 0)
        let chunk = Chunk(content: "Hello", metadata: metadata)
        #expect(chunk.characterCount == 5)
    }

    @Test("Chunk Identifiable conformance")
    func chunkIdentifiable() {
        let metadata = ChunkMetadata(documentId: "doc-1", index: 0)
        let chunk = Chunk(id: "my-chunk-id", content: "Content", metadata: metadata)
        #expect(chunk.id == "my-chunk-id")
    }

    @Test("Chunk equality")
    func chunkEquality() {
        let metadata = ChunkMetadata(documentId: "doc-1", index: 0)
        let chunk1 = Chunk(id: "same-id", content: "Same content", metadata: metadata)
        let chunk2 = Chunk(id: "same-id", content: "Same content", metadata: metadata)
        #expect(chunk1 == chunk2)
    }

    @Test("ChunkMetadata default values")
    func chunkMetadataDefaults() {
        let metadata = ChunkMetadata(documentId: "doc-1", index: 0)
        #expect(metadata.startOffset == 0)
        #expect(metadata.endOffset == 0)
        #expect(metadata.source == nil)
        #expect(metadata.custom.isEmpty)
    }
}

// MARK: - RetrievalResult Tests

@Suite("RetrievalResult Tests")
struct RetrievalResultTests {

    @Test("RetrievalResult creation")
    func retrievalResultCreation() {
        let metadata = ChunkMetadata(documentId: "doc-1", index: 0)
        let chunk = Chunk(id: "chunk-1", content: "Retrieved content", metadata: metadata)
        let result = RetrievalResult(chunk: chunk, score: 0.95)

        #expect(result.chunk == chunk)
        #expect(result.score == 0.95)
        #expect(result.metadata.isEmpty)
    }

    @Test("RetrievalResult creation with metadata")
    func retrievalResultWithMetadata() {
        let chunkMeta = ChunkMetadata(documentId: "doc-1", index: 0)
        let chunk = Chunk(content: "Content", metadata: chunkMeta)
        let result = RetrievalResult(
            chunk: chunk,
            score: 0.85,
            metadata: ["method": "cosine", "reranked": true]
        )

        #expect(result.metadata["method"]?.stringValue == "cosine")
        #expect(result.metadata["reranked"]?.boolValue == true)
    }

    @Test("RetrievalResult id derived from chunk")
    func retrievalResultId() {
        let chunkMeta = ChunkMetadata(documentId: "doc-1", index: 0)
        let chunk = Chunk(id: "chunk-abc", content: "Content", metadata: chunkMeta)
        let result = RetrievalResult(chunk: chunk, score: 0.9)

        #expect(result.id == "chunk-abc")
    }

    @Test("RetrievalResult Comparable - less than")
    func retrievalResultLessThan() {
        let chunkMeta = ChunkMetadata(documentId: "doc-1", index: 0)
        let chunk1 = Chunk(content: "Low score", metadata: chunkMeta)
        let chunk2 = Chunk(content: "High score", metadata: chunkMeta)

        let result1 = RetrievalResult(chunk: chunk1, score: 0.5)
        let result2 = RetrievalResult(chunk: chunk2, score: 0.9)

        #expect(result1 < result2)
        #expect(!(result2 < result1))
    }

    @Test("RetrievalResult sorting by score ascending")
    func retrievalResultSortingAscending() {
        let chunkMeta = ChunkMetadata(documentId: "doc-1", index: 0)
        let results = [
            RetrievalResult(chunk: Chunk(content: "Medium", metadata: chunkMeta), score: 0.7),
            RetrievalResult(chunk: Chunk(content: "High", metadata: chunkMeta), score: 0.95),
            RetrievalResult(chunk: Chunk(content: "Low", metadata: chunkMeta), score: 0.3)
        ]

        let sorted = results.sorted()
        #expect(sorted[0].score == 0.3)
        #expect(sorted[1].score == 0.7)
        #expect(sorted[2].score == 0.95)
    }

    @Test("RetrievalResult sorting by score descending")
    func retrievalResultSortingDescending() {
        let chunkMeta = ChunkMetadata(documentId: "doc-1", index: 0)
        let results = [
            RetrievalResult(chunk: Chunk(content: "Medium", metadata: chunkMeta), score: 0.7),
            RetrievalResult(chunk: Chunk(content: "High", metadata: chunkMeta), score: 0.95),
            RetrievalResult(chunk: Chunk(content: "Low", metadata: chunkMeta), score: 0.3)
        ]

        let sorted = results.sorted(by: >)
        #expect(sorted[0].score == 0.95)
        #expect(sorted[1].score == 0.7)
        #expect(sorted[2].score == 0.3)
    }

    @Test("RetrievalResult equality")
    func retrievalResultEquality() {
        let chunkMeta = ChunkMetadata(documentId: "doc-1", index: 0)
        let chunk = Chunk(id: "chunk-1", content: "Content", metadata: chunkMeta)
        let result1 = RetrievalResult(chunk: chunk, score: 0.9)
        let result2 = RetrievalResult(chunk: chunk, score: 0.9)

        #expect(result1 == result2)
    }

    @Test("RetrievalResult inequality by score")
    func retrievalResultInequalityByScore() {
        let chunkMeta = ChunkMetadata(documentId: "doc-1", index: 0)
        let chunk = Chunk(id: "chunk-1", content: "Content", metadata: chunkMeta)
        let result1 = RetrievalResult(chunk: chunk, score: 0.9)
        let result2 = RetrievalResult(chunk: chunk, score: 0.8)

        #expect(result1 != result2)
    }
}

// MARK: - RAGConfiguration Tests

@Suite("RAGConfiguration Tests")
struct RAGConfigurationTests {

    @Test("Default configuration has expected values")
    func defaultConfiguration() {
        let config = RAGConfiguration.default

        #expect(config.defaultChunkSize == 512)
        #expect(config.defaultChunkOverlap == 50)
        #expect(config.embeddingBatchSize == 100)
        #expect(config.cacheEmbeddings == true)
        #expect(config.defaultRetrievalLimit == 5)
        #expect(config.similarityThreshold == nil)
        #expect(config.defaultSystemPrompt == "You are a helpful assistant. Answer questions based on the provided context.")
        #expect(config.maxContextTokens == 4000)
        #expect(config.responseMaxTokens == nil)
        #expect(config.enableLogging == true)
        #expect(config.logLevel == .info)
    }

    @Test("Custom configuration with all parameters")
    func customConfiguration() {
        let config = RAGConfiguration(
            defaultChunkSize: 1024,
            defaultChunkOverlap: 100,
            embeddingBatchSize: 50,
            cacheEmbeddings: false,
            defaultRetrievalLimit: 10,
            similarityThreshold: 0.7,
            defaultSystemPrompt: "Custom prompt",
            maxContextTokens: 8000,
            responseMaxTokens: 500,
            enableLogging: false,
            logLevel: .debug
        )

        #expect(config.defaultChunkSize == 1024)
        #expect(config.defaultChunkOverlap == 100)
        #expect(config.embeddingBatchSize == 50)
        #expect(config.cacheEmbeddings == false)
        #expect(config.defaultRetrievalLimit == 10)
        #expect(config.similarityThreshold == 0.7)
        #expect(config.defaultSystemPrompt == "Custom prompt")
        #expect(config.maxContextTokens == 8000)
        #expect(config.responseMaxTokens == 500)
        #expect(config.enableLogging == false)
        #expect(config.logLevel == .debug)
    }

    @Test("Configuration with partial customization")
    func partialCustomConfiguration() {
        let config = RAGConfiguration(
            defaultChunkSize: 256,
            defaultRetrievalLimit: 3
        )

        // Custom values
        #expect(config.defaultChunkSize == 256)
        #expect(config.defaultRetrievalLimit == 3)

        // Default values
        #expect(config.defaultChunkOverlap == 50)
        #expect(config.embeddingBatchSize == 100)
        #expect(config.cacheEmbeddings == true)
    }

    @Test("LogLevel comparison")
    func logLevelComparison() {
        #expect(RAGConfiguration.LogLevel.none < RAGConfiguration.LogLevel.error)
        #expect(RAGConfiguration.LogLevel.error < RAGConfiguration.LogLevel.warning)
        #expect(RAGConfiguration.LogLevel.warning < RAGConfiguration.LogLevel.info)
        #expect(RAGConfiguration.LogLevel.info < RAGConfiguration.LogLevel.debug)
    }

    @Test("LogLevel equality")
    func logLevelEquality() {
        #expect(RAGConfiguration.LogLevel.info == RAGConfiguration.LogLevel.info)
        #expect(RAGConfiguration.LogLevel.error != RAGConfiguration.LogLevel.warning)
    }

    @Test("Configuration is mutable")
    func configurationMutability() {
        var config = RAGConfiguration()
        config.defaultChunkSize = 2048
        config.enableLogging = false
        config.logLevel = .error

        #expect(config.defaultChunkSize == 2048)
        #expect(config.enableLogging == false)
        #expect(config.logLevel == .error)
    }
}

// MARK: - ZoniError Tests

@Suite("ZoniError Tests")
struct ZoniErrorTests {

    @Test("unsupportedFileType has error description")
    func unsupportedFileTypeDescription() {
        let error = ZoniError.unsupportedFileType("xyz")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("xyz") == true)
    }

    @Test("loadingFailed has error description")
    func loadingFailedDescription() {
        let url = URL(fileURLWithPath: "/path/to/file.txt")
        let error = ZoniError.loadingFailed(url: url, reason: "File not found")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("file.txt") == true)
    }

    @Test("invalidData has error description")
    func invalidDataDescription() {
        let error = ZoniError.invalidData(reason: "Malformed JSON")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("Malformed JSON") == true)
    }

    @Test("chunkingFailed has error description")
    func chunkingFailedDescription() {
        let error = ZoniError.chunkingFailed(reason: "Content too short")
        #expect(error.errorDescription != nil)
    }

    @Test("emptyDocument has error description")
    func emptyDocumentDescription() {
        let error = ZoniError.emptyDocument
        #expect(error.errorDescription != nil)
    }

    @Test("embeddingFailed has error description")
    func embeddingFailedDescription() {
        let error = ZoniError.embeddingFailed(reason: "API error")
        #expect(error.errorDescription != nil)
    }

    @Test("embeddingDimensionMismatch has error description")
    func embeddingDimensionMismatchDescription() {
        let error = ZoniError.embeddingDimensionMismatch(expected: 1536, got: 768)
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("1536") == true)
        #expect(error.errorDescription?.contains("768") == true)
    }

    @Test("embeddingProviderUnavailable has error description")
    func embeddingProviderUnavailableDescription() {
        let error = ZoniError.embeddingProviderUnavailable(name: "OpenAI")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("OpenAI") == true)
    }

    @Test("rateLimited has error description")
    func rateLimitedDescription() {
        let error = ZoniError.rateLimited(retryAfter: .seconds(60))
        #expect(error.errorDescription != nil)
    }

    @Test("rateLimited without duration has error description")
    func rateLimitedWithoutDurationDescription() {
        let error = ZoniError.rateLimited(retryAfter: nil)
        #expect(error.errorDescription != nil)
    }

    @Test("vectorStoreUnavailable has error description")
    func vectorStoreUnavailableDescription() {
        let error = ZoniError.vectorStoreUnavailable(name: "Pinecone")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("Pinecone") == true)
    }

    @Test("vectorStoreConnectionFailed has error description")
    func vectorStoreConnectionFailedDescription() {
        let error = ZoniError.vectorStoreConnectionFailed(reason: "Connection timeout")
        #expect(error.errorDescription != nil)
    }

    @Test("indexNotFound has error description")
    func indexNotFoundDescription() {
        let error = ZoniError.indexNotFound(name: "documents")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("documents") == true)
    }

    @Test("insertionFailed has error description")
    func insertionFailedDescription() {
        let error = ZoniError.insertionFailed(reason: "Quota exceeded")
        #expect(error.errorDescription != nil)
    }

    @Test("searchFailed has error description")
    func searchFailedDescription() {
        let error = ZoniError.searchFailed(reason: "Invalid query")
        #expect(error.errorDescription != nil)
    }

    @Test("retrievalFailed has error description")
    func retrievalFailedDescription() {
        let error = ZoniError.retrievalFailed(reason: "No matching documents")
        #expect(error.errorDescription != nil)
    }

    @Test("noResultsFound has error description")
    func noResultsFoundDescription() {
        let error = ZoniError.noResultsFound
        #expect(error.errorDescription != nil)
    }

    @Test("generationFailed has error description")
    func generationFailedDescription() {
        let error = ZoniError.generationFailed(reason: "Model overloaded")
        #expect(error.errorDescription != nil)
    }

    @Test("llmProviderUnavailable has error description")
    func llmProviderUnavailableDescription() {
        let error = ZoniError.llmProviderUnavailable(name: "Claude")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("Claude") == true)
    }

    @Test("contextTooLong has error description")
    func contextTooLongDescription() {
        let error = ZoniError.contextTooLong(tokens: 10000, limit: 8192)
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("10000") == true)
        #expect(error.errorDescription?.contains("8192") == true)
    }

    @Test("invalidConfiguration has error description")
    func invalidConfigurationDescription() {
        let error = ZoniError.invalidConfiguration(reason: "Chunk size must be positive")
        #expect(error.errorDescription != nil)
    }

    @Test("missingRequiredComponent has error description")
    func missingRequiredComponentDescription() {
        let error = ZoniError.missingRequiredComponent("EmbeddingProvider")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("EmbeddingProvider") == true)
    }

    // MARK: - Recovery Suggestions

    @Test("All errors have recovery suggestions")
    func allErrorsHaveRecoverySuggestions() {
        let errors: [ZoniError] = [
            .unsupportedFileType("xyz"),
            .loadingFailed(url: URL(fileURLWithPath: "/test"), reason: "test"),
            .invalidData(reason: "test"),
            .chunkingFailed(reason: "test"),
            .emptyDocument,
            .embeddingFailed(reason: "test"),
            .embeddingDimensionMismatch(expected: 100, got: 50),
            .embeddingProviderUnavailable(name: "test"),
            .rateLimited(retryAfter: .seconds(10)),
            .vectorStoreUnavailable(name: "test"),
            .vectorStoreConnectionFailed(reason: "test"),
            .indexNotFound(name: "test"),
            .insertionFailed(reason: "test"),
            .searchFailed(reason: "test"),
            .retrievalFailed(reason: "test"),
            .noResultsFound,
            .generationFailed(reason: "test"),
            .llmProviderUnavailable(name: "test"),
            .contextTooLong(tokens: 100, limit: 50),
            .invalidConfiguration(reason: "test"),
            .missingRequiredComponent("test")
        ]

        for error in errors {
            #expect(error.recoverySuggestion != nil, "Error \(error) should have recovery suggestion")
        }
    }
}
