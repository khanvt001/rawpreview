import Testing
@testable import rawpreview

@Suite struct LuaTableParserTests {
    private func table(_ text: String) throws -> LuaTable {
        try #require(try LuaTableParser.parse(text).table)
    }

    @Test func readsTheAssignmentThatStartsAnLrtemplate() throws {
        let root = try table(#"s = { title = "Warm", version = 0 }"#)
        #expect(root["title"]?.string == "Warm")
        #expect(root["version"]?.number == 0)
    }

    @Test func readsABareTable() throws {
        #expect(try table("{ amount = 1.5 }")["amount"]?.number == 1.5)
    }

    @Test func readsPositionalAndNamedEntriesTogether() throws {
        let root = try table(#"{ 1, 2; name = "x", ["quoted key"] = true, [7] = "seven", }"#)
        #expect(root.array.compactMap(\.number) == [1, 2])
        #expect(root["name"]?.string == "x")
        if case .bool(true)? = root["quoted key"] {} else { Issue.record("expected true") }
        #expect(root["7.0"]?.string == "seven")
    }

    @Test func readsNestedTables() throws {
        let root = try table("{ value = { settings = { Exposure2012 = -0.25 } } }")
        #expect(root["value"]?.table?["settings"]?.table?["Exposure2012"]?.number == -0.25)
    }

    @Test func readsNumbersInScientificNotation() throws {
        #expect(try table("{ a = 1e-3, b = +2 }")["a"]?.number == 0.001)
    }

    @Test func skipsComments() throws {
        let root = try table("""
            -- header
            { a = 1, -- trailing
              b = 2 }
            """)
        #expect(root["b"]?.number == 2)
    }

    @Test func unescapesStrings() throws {
        let root = try table(#"{ a = "line\nbreak", b = 'it\'s', c = "\65\066" }"#)
        #expect(root["a"]?.string == "line\nbreak")
        #expect(root["b"]?.string == "it's")
        #expect(root["c"]?.string == "AB")
    }

    @Test func keepsMultibyteTextIntact() throws {
        #expect(try table(#"{ a = "Ảnh" }"#)["a"]?.string == "Ảnh")
    }

    @Test func readsLongStrings() throws {
        let root = try table("{ a = [[one]], b = [==[two ]] still two]==] }")
        #expect(root["a"]?.string == "one")
        #expect(root["b"]?.string == "two ]] still two")
    }

    @Test(arguments: [
        "",
        "{ a = 1",
        "{ a = }",
        "{ a = 1 b = 2 }",
        #"{ a = "unterminated }"#,
        "{ a = [[unterminated }",
        "{ a = 1.2.3 }",
        "{ a = os.execute }",
    ])
    func rejectsMalformedInput(_ text: String) {
        #expect(throws: LuaTableParser.ParseError.self) { try LuaTableParser.parse(text) }
    }
}
