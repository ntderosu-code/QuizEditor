import Foundation

public enum CanvasQuizEngine: String, CaseIterable, Identifiable, Codable, Sendable {
    case classicQuizzes
    case newQuizzes

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .classicQuizzes: "Classic Quizzes (QTI 1.2)"
        case .newQuizzes: "New Quizzes (QTI 2.1)"
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
    public enum ExportError: Error, Equatable {
        case emptyQuizTitle
        case noQuestions
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
        case .classicQuizzes:
            return QTIPackage(files: classicPackageFiles(for: quiz))
        case .newQuizzes:
            return QTIPackage(files: newQuizzesPackageFiles(for: quiz))
        }
    }

    private func classicPackageFiles(for quiz: Quiz) -> [QTIPackageFile] {
        var files = [
            QTIPackageFile(path: "imsmanifest.xml", contents: classicManifestXML(for: quiz)),
            QTIPackageFile(path: "assessment.xml", contents: classicAssessmentXML(for: quiz))
        ]

        for (index, question) in quiz.questions.enumerated() {
            files.append(QTIPackageFile(path: "items/question-\(index + 1).xml", contents: classicItemXML(for: question, index: index + 1)))
        }

        return files
    }

    private func newQuizzesPackageFiles(for quiz: Quiz) -> [QTIPackageFile] {
        var files = [
            QTIPackageFile(path: "imsmanifest.xml", contents: newQuizzesManifestXML(for: quiz)),
            QTIPackageFile(path: "assessment.xml", contents: newQuizzesAssessmentXML(for: quiz))
        ]

        for (index, question) in quiz.questions.enumerated() {
            files.append(QTIPackageFile(path: "items/question-\(index + 1).xml", contents: qti21ItemXML(for: question, index: index + 1)))
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

    private func classicItemXML(for question: QuizQuestion, index: Int) -> String {
        let presentation = classicPresentationXML(for: question)
        let responseProcessing = classicResponseProcessingXML(for: question)
        let feedback = classicFeedbackXML(question.feedback)

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <questestinterop>
            <item ident="question_\(index)" title="Question \(index)">
                <itemmetadata>
                    <qtimetadata>
                        <qtimetadatafield>
                            <fieldlabel>question_type</fieldlabel>
                            <fieldentry>\(question.type.canvasQuestionType)</fieldentry>
                        </qtimetadatafield>
                        <qtimetadatafield>
                            <fieldlabel>points_possible</fieldlabel>
                            <fieldentry>\(formatPoints(question.points))</fieldentry>
                        </qtimetadatafield>
                    </qtimetadata>
                </itemmetadata>
        \(presentation)
        \(responseProcessing)
        \(feedback)
            </item>
        </questestinterop>
        """
    }

    private func qti21ItemXML(for question: QuizQuestion, index: Int) -> String {
        let responseDeclaration = qti21ResponseDeclaration(for: question)
        let body = qti21ItemBody(for: question)
        let feedback = qti21FeedbackXML(question.feedback)

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <assessmentItem xmlns="http://www.imsglobal.org/xsd/imsqti_v2p1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" identifier="question_\(index)" title="Question \(index)" adaptive="false" timeDependent="false">
        \(responseDeclaration)
            <outcomeDeclaration identifier="SCORE" cardinality="single" baseType="float">
                <defaultValue><value>0</value></defaultValue>
            </outcomeDeclaration>
        \(body)
            <responseProcessing template="http://www.imsglobal.org/question/qti_v2p1/rptemplates/match_correct"/>
        \(feedback)
        </assessmentItem>
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
        case .essay:
            return "    <responseDeclaration identifier=\"RESPONSE\" cardinality=\"single\" baseType=\"string\"/>"
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
        case .matching:
            return qti21MatchingBody(for: question)
        case .multipleAnswer:
            return qti21ChoiceBody(for: question, maxChoices: question.answers.count)
        case .multipleChoice, .trueFalse:
            return qti21ChoiceBody(for: question, maxChoices: 1)
        }
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
        default:
            return classicAnswerResponseProcessing(question)
        }
    }

    private func classicAnswerResponseProcessing(_ question: QuizQuestion) -> String {
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
}

func xmlEscape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}
