import Foundation

public enum CanvasQuizEngine: String, CaseIterable, Identifiable, Codable, Sendable {
    case classicQuizzes
    case newQuizzes
    /// Canvas Surveys are exported as QTI 1.2 (the only Canvas survey QTI path
    /// that round-trips reliably). Survey items strip resprocessing so Canvas
    /// scores no answers.
    case surveys

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .classicQuizzes: "Classic Quizzes (QTI 1.2)"
        case .newQuizzes: "New Quizzes (QTI 2.1)"
        case .surveys: "Surveys (QTI 1.2)"
        }
    }
}

public struct QTIPackage: Equatable, Sendable {
    public var files: [QTIPackageFile]

    public init(files: [QTIPackageFile]) {
        self.files = files
    }

    public func file(named path: String) -> QTIPackageFile? {
        files.first { $0.path == path }
    }
}

public struct QTIPackageFile: Equatable, Sendable {
    public var path: String
    public var contents: String

    public init(path: String, contents: String) {
        self.path = path
        self.contents = contents
    }
}

public struct CanvasQTIExporter: Sendable {
    public enum ExportError: UserFacingError, Equatable {
        case emptyQuizTitle
        case noQuestions

        public var description: String {
            switch self {
            case .emptyQuizTitle: "The quiz needs a title before it can be exported."
            case .noQuestions: "The quiz has no questions to export."
            }
        }
    }

    private let engine: CanvasQuizEngine
    private let html = HTMLUtilities()

    public init(engine: CanvasQuizEngine = .classicQuizzes) {
        self.engine = engine
    }

    /// Produces well-formed XHTML for QTI 2.1 bodies, falling back to escaped
    /// text if the fragment can't be tidied.
    private func inlineXHTML(_ value: String) -> String {
        html.xhtmlFragment(from: value) ?? xmlEscape(value)
    }

    public func makePackage(for quiz: Quiz) throws -> QTIPackage {
        guard !quiz.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExportError.emptyQuizTitle
        }
        guard !quiz.questions.isEmpty else { throw ExportError.noQuestions }

        switch engine {
        case .classicQuizzes, .surveys:
            // Surveys reuse the QTI 1.2 layout; per-item resprocessing is stripped
            // inside `classicItemXML(for:index:ungraded:)`.
            let ungraded = (engine == .surveys) || (quiz.kind == .survey)
            return QTIPackage(files: classicPackageFiles(for: quiz, ungraded: ungraded))
        case .newQuizzes:
            return QTIPackage(files: newQuizzesPackageFiles(for: quiz, ungraded: quiz.kind == .survey))
        }
    }

    private func classicPackageFiles(for quiz: Quiz, ungraded: Bool = false) -> [QTIPackageFile] {
        var files = [
            QTIPackageFile(path: "imsmanifest.xml", contents: classicManifestXML(for: quiz)),
            QTIPackageFile(path: "assessment.xml", contents: classicAssessmentXML(for: quiz))
        ]

        for (index, question) in quiz.questions.enumerated() {
            files.append(QTIPackageFile(path: "items/question-\(index + 1).xml", contents: classicItemXML(for: question, index: index + 1, ungraded: ungraded)))
        }

        return files
    }

    private func newQuizzesPackageFiles(for quiz: Quiz, ungraded: Bool = false) -> [QTIPackageFile] {
        var files = [
            QTIPackageFile(path: "imsmanifest.xml", contents: newQuizzesManifestXML(for: quiz)),
            QTIPackageFile(path: "assessment.xml", contents: newQuizzesAssessmentXML(for: quiz))
        ]

        for (index, question) in quiz.questions.enumerated() {
            files.append(QTIPackageFile(path: "items/question-\(index + 1).xml", contents: qti21ItemXML(for: question, index: index + 1, ungraded: ungraded)))
        }

        return files
    }

    private func classicManifestXML(for quiz: Quiz) -> String {
        let itemResources = quiz.questions.indices.map { index in
            let number = index + 1
            return """
                <resource identifier="question_\(number)_resource" type="imsqti_item_xmlv1p2" href="items/question-\(number).xml">
                    <file href="items/question-\(number).xml"/>
                </resource>
            """
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <manifest identifier="quiz_manifest" xmlns="http://www.imsglobal.org/xsd/imsccv1p1/imscp_v1p1" xmlns:imsmd="http://www.imsglobal.org/xsd/imsmd_v1p2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <metadata>
                <schema>IMS Content</schema>
                <schemaversion>1.1.3</schemaversion>
            </metadata>
            <organizations/>
            <resources>
                <resource identifier="assessment_resource" type="imsqti_xmlv1p2" href="assessment.xml">
                    <file href="assessment.xml"/>
                </resource>
        \(itemResources)
            </resources>
        </manifest>
        """
    }

    private func newQuizzesManifestXML(for quiz: Quiz) -> String {
        let itemResources = quiz.questions.indices.map { index in
            let number = index + 1
            return """
                <resource identifier="question_\(number)_resource" type="imsqti_item_xmlv2p1" href="items/question-\(number).xml">
                    <file href="items/question-\(number).xml"/>
                </resource>
            """
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <manifest identifier="new_quizzes_manifest" xmlns="http://www.imsglobal.org/xsd/imscp_v1p1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <metadata>
                <schema>IMS Common Cartridge</schema>
                <schemaversion>1.3.0</schemaversion>
            </metadata>
            <organizations/>
            <resources>
                <resource identifier="assessment_resource" type="imsqti_test_xmlv2p1" href="assessment.xml">
                    <file href="assessment.xml"/>
                </resource>
        \(itemResources)
            </resources>
        </manifest>
        """
    }

    private func classicAssessmentXML(for quiz: Quiz) -> String {
        let itemReferences = quiz.questions.indices.map { index in
            "            <itemref linkrefid=\"question_\(index + 1)\" href=\"items/question-\(index + 1).xml\"/>"
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <questestinterop>
            <assessment ident="assessment_1" title="\(xmlEscape(quiz.title))">
                <qtimetadata>
                    <qtimetadatafield>
                        <fieldlabel>cc_maxattempts</fieldlabel>
                        <fieldentry>1</fieldentry>
                    </qtimetadatafield>
                </qtimetadata>
                <section ident="root_section">
        \(itemReferences)
                </section>
            </assessment>
        </questestinterop>
        """
    }

    private func newQuizzesAssessmentXML(for quiz: Quiz) -> String {
        let itemReferences = quiz.questions.indices.map { index in
            let number = index + 1
            return """
                    <assessmentItemRef identifier="question_\(number)_ref" href="items/question-\(number).xml" required="true" fixed="false"/>
            """
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <assessmentTest xmlns="http://www.imsglobal.org/xsd/imsqti_v2p1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" identifier="assessment_1" title="\(xmlEscape(quiz.title))">
            <testPart identifier="part_1" navigationMode="linear" submissionMode="individual">
                <assessmentSection identifier="section_1" title="\(xmlEscape(quiz.title))" visible="true">
        \(itemReferences)
                </assessmentSection>
            </testPart>
        </assessmentTest>
        """
    }

    private func classicItemXML(for question: QuizQuestion, index: Int, ungraded: Bool = false) -> String {
        let presentation = classicPresentationXML(for: question)
        let responseProcessing = ungraded ? "" : classicResponseProcessingXML(for: question)
        let feedback = classicFeedbackXML(question.feedback)
        let pointsField = ungraded ? "" : """
                        <qtimetadatafield>
                            <fieldlabel>points_possible</fieldlabel>
                            <fieldentry>\(formatPoints(question.points))</fieldentry>
                        </qtimetadatafield>
        """

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <questestinterop>
            <item ident="question_\(index)" title="Question \(index)">
                <itemmetadata>
                    <qtimetadata>
                        <qtimetadatafield>
                            <fieldlabel>question_type</fieldlabel>
                            <fieldentry>\(question.type.canvasQuestionType)</fieldentry>
                        </qtimetadatafield>\(pointsField)\(metadataFields(for: question))
                    </qtimetadata>
                </itemmetadata>
        \(presentation)
        \(responseProcessing)
        \(feedback)
            </item>
        </questestinterop>
        """
    }

    private func qti21ItemXML(for question: QuizQuestion, index: Int, ungraded: Bool = false) -> String {
        let responseDeclaration = qti21ResponseDeclaration(for: question)
        let body = qti21ItemBody(for: question)
        let feedback = qti21FeedbackXML(question.feedback)
        let processing: String
        if ungraded {
            processing = "    <responseProcessing/>"
        } else if question.type == .numeric {
            processing = qti21NumericResponseProcessing(for: question)
        } else if question.type == .formula {
            processing = qti21FormulaResponseProcessing(for: question)
        } else {
            processing = "    <responseProcessing template=\"http://www.imsglobal.org/question/qti_v2p1/rptemplates/match_correct\"/>"
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <assessmentItem xmlns="http://www.imsglobal.org/xsd/imsqti_v2p1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" identifier="question_\(index)" title="Question \(index)" adaptive="false" timeDependent="false">
        \(responseDeclaration)
            <outcomeDeclaration identifier="SCORE" cardinality="single" baseType="float">
                <defaultValue><value>0</value></defaultValue>
            </outcomeDeclaration>
        \(body)
        \(processing)
        \(feedback)
        </assessmentItem>
        """
    }

    /// QTI 2.1 response processing for a numeric item: scores 1 when the response
    /// falls in the accepted interval (value±margin or range), or equals the value
    /// for precision/exact. No condition is emitted for an unconfigured question.
    private func qti21NumericResponseProcessing(for question: QuizQuestion) -> String {
        guard let numeric = question.numeric else {
            return "    <responseProcessing/>"
        }
        let test: String
        if let interval = numeric.acceptedInterval, interval.low != interval.high {
            test = """
                            <and>
                                <gte><variable identifier="RESPONSE"/><baseValue baseType="float">\(formatNumber(interval.low))</baseValue></gte>
                                <lte><variable identifier="RESPONSE"/><baseValue baseType="float">\(formatNumber(interval.high))</baseValue></lte>
                            </and>
            """
        } else if let value = numeric.value ?? numeric.acceptedInterval?.low {
            test = """
                            <equal toleranceMode="exact"><variable identifier="RESPONSE"/><baseValue baseType="float">\(formatNumber(value))</baseValue></equal>
            """
        } else {
            return "    <responseProcessing/>"
        }

        return """
            <responseProcessing>
                <responseCondition>
                    <responseIf>
        \(test)
                        <setOutcomeValue identifier="SCORE"><baseValue baseType="float">1</baseValue></setOutcomeValue>
                    </responseIf>
                </responseCondition>
            </responseProcessing>
        """
    }

    private func classicPresentationXML(for question: QuizQuestion) -> String {
        switch question.type {
        case .essay:
            return classicPromptOnlyPresentation(question)
        case .fillInBlank, .shortAnswer:
            return """
                <presentation>
                    <material><mattext texttype="text/html">\(xmlEscape(question.prompt))</mattext></material>
                    <response_str ident="response1" rcardinality="Single">
                        <render_fib fibtype="String" prompt="Box" rows="1" columns="40"/>
                    </response_str>
                </presentation>
            """
        case .matching:
            return classicMatchingPresentation(question)
        case .multipleAnswer:
            return classicChoicePresentation(question, cardinality: "Multiple")
        case .multipleChoice, .trueFalse:
            return classicChoicePresentation(question, cardinality: "Single")
        case .numeric:
            return """
                <presentation>
                    <material><mattext texttype="text/html">\(xmlEscape(question.prompt))</mattext></material>
                    <response_str ident="response1" rcardinality="Single">
                        <render_fib fibtype="Decimal" prompt="Box" rows="1" columns="20"/>
                    </response_str>
                </presentation>
            """
        case .formula:
            // Body looks like a numeric question; the formula spec is carried in
            // the item's qtimetadata so Canvas can evaluate it server-side.
            return """
                <presentation>
                    <material><mattext texttype="text/html">\(xmlEscape(question.prompt))</mattext></material>
                    <response_str ident="response1" rcardinality="Single">
                        <render_fib fibtype="Decimal" prompt="Box" rows="1" columns="20"/>
                    </response_str>
                </presentation>
            """
        case .fileUpload:
            return classicFileUploadPresentation(question)
        }
    }

    private func classicPromptOnlyPresentation(_ question: QuizQuestion) -> String {
        """
            <presentation>
                <material><mattext texttype="text/html">\(xmlEscape(question.prompt))</mattext></material>
                <response_str ident="response1" rcardinality="Single">
                    <render_fib fibtype="String" prompt="Box" rows="8" columns="80"/>
                </response_str>
            </presentation>
        """
    }

    /// File upload in QTI 1.2: a `<response_str type="file">` with the allowed
    /// MIME types as a single space-separated value. Canvas reads this and
    /// shows an upload widget.
    private func classicFileUploadPresentation(_ question: QuizQuestion) -> String {
        let mimeTypes = question.allowedFileTypes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return """
            <presentation>
                <material><mattext texttype="text/html">\(xmlEscape(question.prompt))</mattext></material>
                <response_str ident="response1" rcardinality="Single" type="file">
                    <render_fib fibtype="File" prompt="Upload" rows="1" columns="40" mimetype="\(xmlEscape(mimeTypes))"/>
                </response_str>
            </presentation>
        """
    }

    private func classicChoicePresentation(_ question: QuizQuestion, cardinality: String) -> String {
        let labels = question.answers.enumerated().map { index, answer in
            """
                        <response_label ident="answer_\(index + 1)">
                            <material><mattext texttype="text/html">\(xmlEscape(answer.text))</mattext></material>
                        </response_label>
            """
        }.joined(separator: "\n")

        return """
            <presentation>
                <material><mattext texttype="text/html">\(xmlEscape(question.prompt))</mattext></material>
                <response_lid ident="response1" rcardinality="\(cardinality)">
                    <render_choice>
        \(labels)
                    </render_choice>
                </response_lid>
            </presentation>
        """
    }

    private func classicMatchingPresentation(_ question: QuizQuestion) -> String {
        let rows = question.matches.enumerated().map { index, pair in
            """
                    <response_lid ident="match_\(index + 1)" rcardinality="Single">
                        <material><mattext texttype="text/html">\(xmlEscape(pair.prompt))</mattext></material>
                        <render_choice>
                            <response_label ident="match_answer_\(index + 1)">
                                <material><mattext texttype="text/html">\(xmlEscape(pair.match))</mattext></material>
                            </response_label>
                        </render_choice>
                    </response_lid>
            """
        }.joined(separator: "\n")

        return """
            <presentation>
                <material><mattext texttype="text/html">\(xmlEscape(question.prompt))</mattext></material>
        \(rows)
            </presentation>
        """
    }

    private func qti21ResponseDeclaration(for question: QuizQuestion) -> String {
        switch question.type {
        case .numeric:
            let representative = question.numeric?.value
                ?? question.numeric?.acceptedInterval.map { ($0.low + $0.high) / 2 }
            let correct = representative.map { "<correctResponse><value>\(formatNumber($0))</value></correctResponse>" } ?? ""
            return "    <responseDeclaration identifier=\"RESPONSE\" cardinality=\"single\" baseType=\"float\">\(correct)</responseDeclaration>"
        case .formula:
            let representative = question.formula?.computedValue
            let correct = representative.map { "<correctResponse><value>\(formatNumber($0))</value></correctResponse>" } ?? ""
            return "    <responseDeclaration identifier=\"RESPONSE\" cardinality=\"single\" baseType=\"float\">\(correct)</responseDeclaration>"
        case .fileUpload:
            return "    <responseDeclaration identifier=\"RESPONSE\" cardinality=\"single\" baseType=\"file\"/>"
        case .essay:
            return "    <responseDeclaration identifier=\"RESPONSE\" cardinality=\"single\" baseType=\"string\"/>"
        case .fillInBlank, .shortAnswer:
            // Graded against what the student types. correctResponse carries the
            // first accepted answer (cardinality is single); the mapping is what
            // credits the alternative spellings.
            let accepted = acceptedAnswers(for: question)
            guard let first = accepted.first else {
                return "    <responseDeclaration identifier=\"RESPONSE\" cardinality=\"single\" baseType=\"string\"/>"
            }
            let entries = accepted.map {
                "            <mapEntry mapKey=\"\(xmlEscape($0))\" mappedValue=\"1\" caseSensitive=\"false\"/>"
            }.joined(separator: "\n")
            return """
                <responseDeclaration identifier="RESPONSE" cardinality="single" baseType="string">
                    <correctResponse><value>\(xmlEscape(first))</value></correctResponse>
                    <mapping defaultValue="0">
            \(entries)
                    </mapping>
                </responseDeclaration>
            """
        case .matching:
            let values = question.matches.indices.map { "            <value>source_\($0 + 1) target_\($0 + 1)</value>" }.joined(separator: "\n")
            return """
                <responseDeclaration identifier="RESPONSE" cardinality="multiple" baseType="directedPair">
                    <correctResponse>
            \(values)
                    </correctResponse>
                </responseDeclaration>
            """
        default:
            let cardinality = question.type == .multipleAnswer ? "multiple" : "single"
            let values = question.answers.enumerated().filter { $0.element.isCorrect }.map { index, _ in
                "            <value>answer_\(index + 1)</value>"
            }.joined(separator: "\n")
            return """
                <responseDeclaration identifier="RESPONSE" cardinality="\(cardinality)" baseType="identifier">
                    <correctResponse>
            \(values)
                    </correctResponse>
                </responseDeclaration>
            """
        }
    }

    private func qti21ItemBody(for question: QuizQuestion) -> String {
        switch question.type {
        case .essay:
            return """
                <itemBody>
                    <div>\(inlineXHTML(question.prompt))</div>
                    <extendedTextInteraction responseIdentifier="RESPONSE" expectedLines="8"/>
                </itemBody>
            """
        case .fillInBlank, .shortAnswer:
            return """
                <itemBody>
                    <div>\(inlineXHTML(question.prompt))</div>
                    <textEntryInteraction responseIdentifier="RESPONSE" expectedLength="40"/>
                </itemBody>
            """
        case .numeric:
            return """
                <itemBody>
                    <div>\(inlineXHTML(question.prompt))</div>
                    <textEntryInteraction responseIdentifier="RESPONSE" expectedLength="20"/>
                </itemBody>
            """
        case .formula:
            return """
                <itemBody>
                    <div>\(inlineXHTML(question.prompt))</div>
                    <textEntryInteraction responseIdentifier="RESPONSE" expectedLength="20"/>
                </itemBody>
            """
        case .fileUpload:
            return qti21FileUploadBody(for: question)
        case .matching:
            return qti21MatchingBody(for: question)
        case .multipleAnswer:
            return qti21ChoiceBody(for: question, maxChoices: question.answers.count)
        case .multipleChoice, .trueFalse:
            return qti21ChoiceBody(for: question, maxChoices: 1)
        }
    }

    private func qti21FileUploadBody(for question: QuizQuestion) -> String {
        let mimes = question.allowedFileTypes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let mimeAttribute = mimes.isEmpty ? "" : " expectedMimeTypes=\"\(xmlEscape(mimes.joined(separator: ",")))\""
        return """
            <itemBody>
                <div>\(inlineXHTML(question.prompt))</div>
                <uploadInteraction responseIdentifier="RESPONSE"\(mimeAttribute)/>
            </itemBody>
        """
    }

    private func qti21ChoiceBody(for question: QuizQuestion, maxChoices: Int) -> String {
        let choices = question.answers.enumerated().map { index, answer in
            """
                    <simpleChoice identifier="answer_\(index + 1)">\(inlineXHTML(answer.text))</simpleChoice>
            """
        }.joined(separator: "\n")

        return """
            <itemBody>
                <choiceInteraction responseIdentifier="RESPONSE" shuffle="false" maxChoices="\(maxChoices)">
                    <prompt>\(inlineXHTML(question.prompt))</prompt>
        \(choices)
                </choiceInteraction>
            </itemBody>
        """
    }

    private func qti21MatchingBody(for question: QuizQuestion) -> String {
        let sources = question.matches.enumerated().map { index, pair in
            "            <simpleAssociableChoice identifier=\"source_\(index + 1)\" matchMax=\"1\">\(inlineXHTML(pair.prompt))</simpleAssociableChoice>"
        }.joined(separator: "\n")
        let targets = question.matches.enumerated().map { index, pair in
            "            <simpleAssociableChoice identifier=\"target_\(index + 1)\" matchMax=\"1\">\(inlineXHTML(pair.match))</simpleAssociableChoice>"
        }.joined(separator: "\n")

        return """
            <itemBody>
                <div>\(inlineXHTML(question.prompt))</div>
                <matchInteraction responseIdentifier="RESPONSE" shuffle="false" maxAssociations="\(question.matches.count)">
        \(sources)
        \(targets)
                </matchInteraction>
            </itemBody>
        """
    }

    private func classicResponseProcessingXML(for question: QuizQuestion) -> String {
        switch question.type {
        case .essay:
            return """
                <resprocessing>
                    <outcomes><decvar maxvalue="100" minvalue="0" varname="SCORE" vartype="Decimal"/></outcomes>
                </resprocessing>
            """
        case .matching:
            return classicMatchingResponseProcessing(question)
        case .numeric:
            return classicNumericResponseProcessing(question)
        case .formula:
            return classicFormulaResponseProcessing(question)
        case .fileUpload:
            // File uploads are scored manually; the resprocessing is a stub.
            return """
                <resprocessing>
                    <outcomes><decvar maxvalue="100" minvalue="0" varname="SCORE" vartype="Decimal"/></outcomes>
                </resprocessing>
            """
        default:
            return classicAnswerResponseProcessing(question)
        }
    }

    /// Numeric grading as QTI 1.2 response conditions Canvas understands: a single
    /// exact value uses `varequal`; a value±margin or a range uses an inclusive
    /// `vargte`/`varlte` pair. An unconfigured question emits no scoring condition.
    /// A typed answer is compared to the accepted text, not to a choice
    /// identifier, and every answer row counts: these types have no notion of a
    /// wrong row to leave unchecked.
    private func classicTextEntryResponseProcessing(_ question: QuizQuestion) -> String {
        let conditions = acceptedAnswers(for: question).map { answer in
            """
                    <respcondition title="correct" continue="No">
                        <conditionvar><varequal respident="response1">\(xmlEscape(answer))</varequal></conditionvar>
                        <setvar action="Set" varname="SCORE">100</setvar>
                    </respcondition>
            """
        }.joined(separator: "\n")

        return """
            <resprocessing>
                <outcomes><decvar maxvalue="100" minvalue="0" varname="SCORE" vartype="Decimal"/></outcomes>
        \(conditions)
            </resprocessing>
        """
    }

    /// Every non-empty answer row, in author order. `isCorrect` is meaningless
    /// for a typed answer, and filtering on it silently dropped alternative
    /// spellings from the key.
    private func acceptedAnswers(for question: QuizQuestion) -> [String] {
        question.answers
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Formula items in QTI 1.2: Canvas evaluates the expression server-side and
    /// compares the typed answer against `value ± tolerance`. The expression and
    /// variables are carried in qtimetadata (added by `metadataFields`), and the
    /// answer key here is a varequal on the computed value with a tolerance band.
    private func classicFormulaResponseProcessing(_ question: QuizQuestion) -> String {
        var condition = ""
        if let formula = question.formula, let value = formula.computedValue {
            let tol = abs(formula.tolerance)
            if tol == 0 {
                condition = """
                        <respcondition title="correct" continue="No">
                            <conditionvar><varequal respident="response1">\(formatNumber(value))</varequal></conditionvar>
                            <setvar action="Set" varname="SCORE">100</setvar>
                        </respcondition>
                """
            } else {
                condition = """
                        <respcondition title="correct" continue="No">
                            <conditionvar><and>
                                <vargte respident="response1">\(formatNumber(value - tol))</vargte>
                                <varlte respident="response1">\(formatNumber(value + tol))</varlte>
                            </and></conditionvar>
                            <setvar action="Set" varname="SCORE">100</setvar>
                        </respcondition>
                """
            }
        }

        return """
            <resprocessing>
                <outcomes><decvar maxvalue="100" minvalue="0" varname="SCORE" vartype="Decimal"/></outcomes>
        \(condition)
            </resprocessing>
        """
    }

    /// QTI 2.1 formula items: identical to numeric but the precomputed value
    /// comes from `formula.computedValue`. The formula and variables are passed
    /// through `responseProcessing` only when we can emit a representative value
    /// — Canvas will re-evaluate on the server.
    private func qti21FormulaResponseProcessing(for question: QuizQuestion) -> String {
        guard let value = question.formula?.computedValue else {
            return "    <responseProcessing/>"
        }
        let tol = abs(question.formula?.tolerance ?? 0)
        let test: String
        if tol == 0 {
            test = """
                            <equal toleranceMode="exact"><variable identifier="RESPONSE"/><baseValue baseType="float">\(formatNumber(value))</baseValue></equal>
            """
        } else {
            test = """
                            <and>
                                <gte><variable identifier="RESPONSE"/><baseValue baseType="float">\(formatNumber(value - tol))</baseValue></gte>
                                <lte><variable identifier="RESPONSE"/><baseValue baseType="float">\(formatNumber(value + tol))</baseValue></lte>
                            </and>
            """
        }

        return """
            <responseProcessing>
                <responseCondition>
                    <responseIf>
        \(test)
                        <setOutcomeValue identifier="SCORE"><baseValue baseType="float">1</baseValue></setOutcomeValue>
                    </responseIf>
                </responseCondition>
            </responseProcessing>
        """
    }

    private func classicNumericResponseProcessing(_ question: QuizQuestion) -> String {
        var condition = ""
        if let numeric = question.numeric {
            if let interval = numeric.acceptedInterval {
                if interval.low == interval.high {
                    condition = """
                            <respcondition title="correct" continue="No">
                                <conditionvar><varequal respident="response1">\(formatNumber(interval.low))</varequal></conditionvar>
                                <setvar action="Set" varname="SCORE">100</setvar>
                            </respcondition>
                    """
                } else {
                    condition = """
                            <respcondition title="correct" continue="No">
                                <conditionvar><and>
                                    <vargte respident="response1">\(formatNumber(interval.low))</vargte>
                                    <varlte respident="response1">\(formatNumber(interval.high))</varlte>
                                </and></conditionvar>
                                <setvar action="Set" varname="SCORE">100</setvar>
                            </respcondition>
                    """
                }
            } else if numeric.mode == .precision, let value = numeric.value {
                // QTI 1.2 can't express significant-digit precision, so it degrades
                // to an exact match on the value.
                condition = """
                        <respcondition title="correct" continue="No">
                            <conditionvar><varequal respident="response1">\(formatNumber(value))</varequal></conditionvar>
                            <setvar action="Set" varname="SCORE">100</setvar>
                        </respcondition>
                """
            }
        }

        return """
            <resprocessing>
                <outcomes><decvar maxvalue="100" minvalue="0" varname="SCORE" vartype="Decimal"/></outcomes>
        \(condition)
            </resprocessing>
        """
    }

    private func classicAnswerResponseProcessing(_ question: QuizQuestion) -> String {
        if question.type == .fillInBlank || question.type == .shortAnswer {
            return classicTextEntryResponseProcessing(question)
        }
        let correctConditions = question.answers.enumerated().filter { $0.element.isCorrect }.map { index, _ in
            """
                    <respcondition title="correct" continue="Yes">
                        <conditionvar><varequal respident="response1">answer_\(index + 1)</varequal></conditionvar>
                        <setvar action="Set" varname="SCORE">100</setvar>
                    </respcondition>
            """
        }.joined(separator: "\n")

        return """
            <resprocessing>
                <outcomes><decvar maxvalue="100" minvalue="0" varname="SCORE" vartype="Decimal"/></outcomes>
        \(correctConditions)
            </resprocessing>
        """
    }

    private func classicMatchingResponseProcessing(_ question: QuizQuestion) -> String {
        let pointsPerMatch = 100 / max(question.matches.count, 1)
        let conditions = question.matches.indices.map { index in
            """
                    <respcondition title="correct" continue="Yes">
                        <conditionvar><varequal respident="match_\(index + 1)">match_answer_\(index + 1)</varequal></conditionvar>
                        <setvar action="Add" varname="SCORE">\(pointsPerMatch)</setvar>
                    </respcondition>
            """
        }.joined(separator: "\n")

        return """
            <resprocessing>
                <outcomes><decvar maxvalue="100" minvalue="0" varname="SCORE" vartype="Decimal"/></outcomes>
        \(conditions)
            </resprocessing>
        """
    }

    private func classicFeedbackXML(_ feedback: String) -> String {
        guard !feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return """
            <itemfeedback ident="general_fb">
                <flow_mat><material><mattext texttype="text/html">\(xmlEscape(feedback))</mattext></material></flow_mat>
            </itemfeedback>
        """
    }

    private func qti21FeedbackXML(_ feedback: String) -> String {
        guard !feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return """
            <modalFeedback outcomeIdentifier="SCORE" identifier="general_feedback" showHide="show">\(inlineXHTML(feedback))</modalFeedback>
        """
    }

    private func formatPoints(_ points: Double) -> String {
        points.rounded() == points ? String(Int(points)) : String(points)
    }

    /// Formats a numeric answer/bound, dropping a trailing ".0" for whole numbers.
    private func formatNumber(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    /// Optional Canvas-tolerated metadata fields for tags, difficulty, and the
    /// formula spec. Canvas ignores fields it doesn't recognize, so this is safe
    /// to always emit when the question carries the metadata. Formula items
    /// additionally need the expression and variable values so Canvas can
    /// re-evaluate the answer server-side.
    ///
    /// Stimulus linking is author metadata and is **not** exported: the
    /// `stimulus`/`stimulus_body` fields would carry passage text that Canvas's
    /// `calculations`/survey APIs don't have a place for in a one-item-per-file
    /// QTI package. The linking is preserved on the model and reappears on
    /// import via the `stimulus` qtimetadata field (which Canvas ignores) so
    /// round-trips through the editor don't lose the link.
    private func metadataFields(for question: QuizQuestion) -> String {
        var fields: [String] = []
        if let difficulty = question.difficulty {
            fields.append("""

                        <qtimetadatafield>
                            <fieldlabel>difficulty</fieldlabel>
                            <fieldentry>\(xmlEscape(difficulty.rawValue))</fieldentry>
                        </qtimetadatafield>
            """)
        }
        if !question.tags.isEmpty {
            fields.append("""

                        <qtimetadatafield>
                            <fieldlabel>tags</fieldlabel>
                            <fieldentry>\(xmlEscape(question.tags.joined(separator: ", ")))</fieldentry>
                        </qtimetadatafield>
            """)
        }
        if let formula = question.formula {
            let variablesXML = formula.variables
                .map { "<variable name=\"\(xmlEscape($0.name))\">\(formatNumber($0.value))</variable>" }
                .joined()
            fields.append("""

                        <qtimetadatafield>
                            <fieldlabel>formula_question</fieldlabel>
                            <fieldentry><formula>\(xmlEscape(formula.expression))<variables>\(variablesXML)</variables></formula></fieldentry>
                        </qtimetadatafield>
            """)
        }
        return fields.joined()
    }
}

func xmlEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}
