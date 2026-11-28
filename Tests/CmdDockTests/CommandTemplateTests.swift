import XCTest
@testable import CmdDock

final class CommandTemplateTests: XCTestCase {

    func testParsesVariablesInOrderWithoutDuplicates() {
        let vars = CommandTemplate.variables(in: "ssh -L {{port:8080}}:localhost:{{port}} {{user:root}}@{{host}}")
        XCTAssertEqual(vars.map(\.name), ["port", "user", "host"])
        XCTAssertEqual(vars.map(\.defaultValue), ["8080", "root", nil])
    }

    func testLaterDefaultFillsMissingOne() {
        let vars = CommandTemplate.variables(in: "echo {{x}} {{x:hola}}")
        XCTAssertEqual(vars, [CommandTemplate.Variable(name: "x", defaultValue: "hola")])
    }

    func testIgnoresTextThatIsNotAVariable() {
        XCTAssertTrue(CommandTemplate.variables(in: "echo {{ }} {{1abc}} ${HOME} {single}").isEmpty)
        XCTAssertTrue(CommandTemplate.variables(in: "git status").isEmpty)
    }

    func testAllowsSpacesAndDotsInSyntax() {
        let vars = CommandTemplate.variables(in: "kubectl -n {{ k8s.namespace : default }} get pods")
        XCTAssertEqual(vars.first?.name, "k8s.namespace")
        XCTAssertEqual(vars.first?.defaultValue, "default")
    }

    func testRenderUsesValuesThenDefaults() {
        let tpl = "ssh -L {{port:8080}}:localhost:{{port}} {{user:root}}@{{host}}"
        XCTAssertEqual(CommandTemplate.render(tpl, values: ["host": "example.com"]),
                       "ssh -L 8080:localhost:8080 root@example.com")
        XCTAssertEqual(CommandTemplate.render(tpl, values: ["host": "h", "port": "9000", "user": ""]),
                       "ssh -L 9000:localhost:9000 root@h")
    }

    func testRenderKeepsTextWithoutVariables() {
        XCTAssertEqual(CommandTemplate.render("echo 'ñandú' {not}", values: [:]), "echo 'ñandú' {not}")
    }

    func testInitialValuesPreferLastUsed() {
        var cmd = Command(name: "t", command: "deploy {{env:dev}} {{tag}}")
        XCTAssertEqual(CommandTemplate.initialValues(for: cmd), ["env": "dev", "tag": ""])
        cmd.lastValues = ["env": "prod"]
        XCTAssertEqual(CommandTemplate.initialValues(for: cmd), ["env": "prod", "tag": ""])
    }
}
