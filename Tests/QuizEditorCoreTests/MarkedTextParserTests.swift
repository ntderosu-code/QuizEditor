import XCTest
@testable import QuizEditorCore

final class MarkedTextParserTests: XCTestCase {
    func testParsesMultipleChoiceWithStarredCorrectAnswerAndFeedback() throws {
        let source = """
        Title: Photosynthesis Check

        Type: Multiple Choice
        Question: Which pigment captures light energy?
        * Chlorophyll
        - Glucose
        - Oxygen
        Feedback: Chlorophyll absorbs light during photosynthesis.
        """

        let quiz = try MarkedTextParser().parse(source)

        XCTAssertEqual(quiz.title, "Photosynthesis Check")
        XCTAssertEqual(quiz.questions.count, 1)
        XCTAssertEqual(quiz.questions[0].type, .multipleChoice)
        XCTAssertEqual(quiz.questions[0].prompt, "Which pigment captures light energy?")
        XCTAssertEqual(quiz.questions[0].answers.map(\.text), ["Chlorophyll", "Glucose", "Oxygen"])
        XCTAssertEqual(quiz.questions[0].answers.map(\.isCorrect), [true, false, false])
        XCTAssertEqual(quiz.questions[0].feedback, "Chlorophyll absorbs light during photosynthesis.")
    }

    func testParsesMultipleAnswerTrueFalseEssayAndMatchingBlocks() throws {
        let source = """
        Title: Mixed Quiz

        Type: Multiple Answer
        Question: Select prime numbers.
        * 2
        * 3
        - 4

        Type: True/False
        Question: The Earth orbits the Sun.
        * True
        - False

        Type: Essay
        Question: Explain why revision improves quiz quality.

        Type: Matching
        Question: Match each term.
        - HTML => Structure
        - CSS => Presentation
        """

        let quiz = try MarkedTextParser().parse(source)

        XCTAssertEqual(quiz.questions.map(\.type), [.multipleAnswer, .trueFalse, .essay, .matching])
        XCTAssertEqual(quiz.questions[0].answers.filter(\.isCorrect).map(\.text), ["2", "3"])
        XCTAssertEqual(quiz.questions[1].answers.filter(\.isCorrect).map(\.text), ["True"])
        XCTAssertTrue(quiz.questions[2].answers.isEmpty)
        XCTAssertEqual(quiz.questions[3].matches.map(\.prompt), ["HTML", "CSS"])
        XCTAssertEqual(quiz.questions[3].matches.map(\.match), ["Structure", "Presentation"])
    }

    func testParsesCustomCorrectMarkerAtEndOfEnumeratedChoices() throws {
        let source = """
        Title: Symbol Quiz

        Type: Multiple Choice
        Question: Which option is correct?
        A. First option
        B. Second option ##
        C. Third option
        """

        let parser = MarkedTextParser(correctAnswerMarker: CorrectAnswerMarker(symbol: "##", location: .endOfLine))
        let quiz = try parser.parse(source)

        XCTAssertEqual(quiz.questions[0].answers.map(\.text), ["First option", "Second option", "Third option"])
        XCTAssertEqual(quiz.questions[0].answers.map(\.isCorrect), [false, true, false])
    }

    func testParsesCustomCorrectMarkerAfterEnumeratedChoice() throws {
        let source = """
        Title: Enumerated Quiz

        Type: Multiple Answer
        Question: Select accurate statements.
        1) + Correct first statement
        2) Incorrect statement
        3) + Correct third statement
        """

        let parser = MarkedTextParser(correctAnswerMarker: CorrectAnswerMarker(symbol: "+", location: .afterEnumeration))
        let quiz = try parser.parse(source)

        XCTAssertEqual(quiz.questions[0].answers.map(\.text), ["Correct first statement", "Incorrect statement", "Correct third statement"])
        XCTAssertEqual(quiz.questions[0].answers.map(\.isCorrect), [true, false, true])
    }

    func testParsesPoorlyFormattedPasteWithOptionalAndMixedCorrectIndicators() throws {
        let source = """
        1. Question 1 No right answer
        a. Choice 1
        b. Choice 2

        2. Question 2 With a right answer
        a. Choice 1
        b. Choice 2
        c. Choice 3*

        Another question, this time unnumbered
        a. Choice 1
        *b. Choice 2
        """

        let quiz = try MarkedTextParser().parse(source)

        XCTAssertEqual(quiz.title, "Imported Quiz")
        XCTAssertEqual(quiz.questions.map(\.prompt), [
            "Question 1 No right answer",
            "Question 2 With a right answer",
            "Another question, this time unnumbered"
        ])
        XCTAssertEqual(quiz.questions[0].answers.map(\.text), ["Choice 1", "Choice 2"])
        XCTAssertEqual(quiz.questions[0].answers.map(\.isCorrect), [false, false])
        XCTAssertEqual(quiz.questions[1].answers.map(\.text), ["Choice 1", "Choice 2", "Choice 3"])
        XCTAssertEqual(quiz.questions[1].answers.map(\.isCorrect), [false, false, true])
        XCTAssertEqual(quiz.questions[2].answers.map(\.text), ["Choice 1", "Choice 2"])
        XCTAssertEqual(quiz.questions[2].answers.map(\.isCorrect), [false, true])
    }

    func testParsesChoicesSeparatedByBlankLinesAndRepeatedQuestionNumbers() throws {
        let source = """
        1. A client tells you they drink every weekend but "never feel drunk like their friends do." Based on Module 2 content, which of the following best explains this phenomenon and its clinical implication?
        A) They have low base tolerance, suggesting minimal risk for developing AUD

        B) They have high base tolerance, which may lead to consuming greater amounts — exposing organs to higher alcohol concentrations despite feeling fewer effects

        *C) They have developed acquired tolerance, meaning their brain has permanently adapted and they are protected from overdose

        D) This pattern only becomes clinically relevant if the client is also driving while drinking

        1. Under DSM-5 criteria, a person who (1) repeatedly tries and fails to cut back on cannabis use, (2) spends significant time obtaining and recovering from use, and (3) continues using despite worsening anxiety would receive which diagnosis?
        A) Severe cannabis use disorder

        B) Moderate cannabis use disorder

        C) Mild cannabis use disorder

        *D) Cannabis-induced anxiety disorder — not a SUD

        1. Which of the following represents the most significant challenge to the original disease model of addiction, as discussed in the module?
        *A) The model overemphasizes social and environmental factors at the expense of biological ones

        B) Longitudinal studies show highly variable patterns of alcohol misuse and recovery, including natural recovery without formal treatment, contradicting the model's progressive, uniform disease premise

        C) The model was developed using a large, nationally representative sample, limiting its generalizability

        D) The model requires abstinence as a treatment goal, which most clinicians now reject entirely
        """

        let quiz = try MarkedTextParser().parse(source)

        XCTAssertEqual(quiz.questions.count, 3)
        XCTAssertEqual(quiz.questions.map { $0.answers.count }, [4, 4, 4])
        XCTAssertEqual(quiz.questions[0].answers.map(\.isCorrect), [false, false, true, false])
        XCTAssertEqual(quiz.questions[1].answers.map(\.isCorrect), [false, false, false, true])
        XCTAssertEqual(quiz.questions[2].answers.map(\.isCorrect), [true, false, false, false])
        XCTAssertTrue(quiz.questions[0].prompt.hasPrefix("A client tells you"))
        XCTAssertTrue(quiz.questions[1].prompt.hasPrefix("Under DSM-5 criteria"))
        XCTAssertTrue(quiz.questions[2].prompt.hasPrefix("Which of the following represents"))
    }

    func testRejectsQuestionWithoutPrompt() {
        let source = """
        Title: Broken Quiz

        Type: Multiple Choice
        * Correct
        - Wrong
        """

        XCTAssertThrowsError(try MarkedTextParser().parse(source)) { error in
            XCTAssertEqual(error as? MarkedTextParser.ParseError, .missingPrompt(questionNumber: 1))
        }
    }
}
