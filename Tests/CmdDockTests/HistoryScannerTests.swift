import XCTest
@testable import CmdDock

final class HistoryScannerTests: XCTestCase {

    // MARK: Secretos

    func testDetectsSecrets() {
        let secrets = [
            "mysql -u root -pmysql123 -h localhost",
            "curl --user \"admin:hunter2\" https://example.com",
            "curl -H \"Authorization: Bearer abcdefghijklmnop\" https://api.example.com",
            "export OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyz",
            "git clone https://user:pass@github.com/org/repo.git",
            "psql postgres://app:s3cret@db.local:5432/app",
            "gh auth login --with-token ghp_abcdefghijklmnopqrstuvwxyz123456",
            "aws configure set aws_access_key_id AKIAABCDEFGHIJKLMNOP",
            "deploy --token=abc123",
            "PASSWORD=foo ./run.sh",
        ]
        for s in secrets {
            XCTAssertTrue(HistoryScanner.containsSecret(s), "Debería detectar secreto en: \(s)")
        }
    }

    func testDoesNotFlagSafeCommands() {
        let safe = [
            "mysql -u root -p",
            "git status",
            "docker compose up -d",
            "gcloud compute ssh my-vm --zone=us-central1-a --tunnel-through-iap",
            "curl -s -o /dev/null -w \"%{http_code}\" https://example.com/health",
            "npm run dev",
        ]
        for s in safe {
            XCTAssertFalse(HistoryScanner.containsSecret(s), "Falso positivo en: \(s)")
        }
    }

    // MARK: Filtros

    func testSkipsTrivialAndDestructive() {
        for s in ["ls", "cd ..", "cd..", "LS", "clear", "pwd", "rm -rf node_modules", "sudo rm -r /tmp/x",
                  "gcloud run jobs delete x --quiet", "docker system prune -a", "kubectl delete pod x",
                  "git push --force"] {
            XCTAssertTrue(HistoryScanner.shouldSkip(s), "Debería descartar: \(s)")
        }
        for s in ["git status", "npm run dev", "sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder"] {
            XCTAssertFalse(HistoryScanner.shouldSkip(s), "No debería descartar: \(s)")
        }
    }

    // MARK: Normalización

    func testNormalizeJoinsContinuationLines() {
        let n = HistoryScanner.normalize("gcloud compute start-iap-tunnel vm 3389 \\\n    --zone=us-east4-c")
        XCTAssertEqual(n?.command, "gcloud compute start-iap-tunnel vm 3389 --zone=us-east4-c")
    }

    func testNormalizeExtractsCdPrefix() {
        let n = HistoryScanner.normalize("cd '/Users/me/My Project' && npm run dev")
        XCTAssertEqual(n?.command, "npm run dev")
        XCTAssertEqual(n?.directory, "/Users/me/My Project")
    }

    // MARK: Clasificación

    func testCategories() {
        XCTAssertEqual(HistoryScanner.category(of: "git pull"), "Git")
        XCTAssertEqual(HistoryScanner.category(of: "~/google-cloud-sdk/bin/gcloud compute ssh vm"), "Cloud")
        XCTAssertEqual(HistoryScanner.category(of: "sudo apachectl restart"), "Servidores web y PHP")
        XCTAssertEqual(HistoryScanner.category(of: "ollama ps"), "IA local")
        XCTAssertEqual(HistoryScanner.category(of: "docker ps"), "Docker y Kubernetes")
        XCTAssertNil(HistoryScanner.category(of: "./levantar.sh"))
    }

    func testDependsOnCwd() {
        XCTAssertTrue(HistoryScanner.dependsOnCwd("./bin/docker-up --watch"))
        XCTAssertTrue(HistoryScanner.dependsOnCwd("backend/scripts/deploy.sh prod"))
        XCTAssertTrue(HistoryScanner.dependsOnCwd("npm run dev"))
        XCTAssertTrue(HistoryScanner.dependsOnCwd("code ."))
        XCTAssertTrue(HistoryScanner.dependsOnCwd("python3 send_report.py"))
        XCTAssertFalse(HistoryScanner.dependsOnCwd("ollama ps"))
        XCTAssertFalse(HistoryScanner.dependsOnCwd("ssh root@example.com"))
    }

    func testDisplayName() {
        XCTAssertEqual(HistoryScanner.displayName("git status"), "git status")
        XCTAssertEqual(HistoryScanner.displayName("~/google-cloud-sdk/bin/gcloud compute ssh my-vm --zone=us-central1-a --tunnel-through-iap -- -N -L 8080:localhost:8080"),
                       "gcloud compute ssh my-vm 8080:localhost:8080")
        // `proyecto:region:instancia` largo → solo la instancia
        XCTAssertEqual(HistoryScanner.displayName("./cloud-sql-proxy my-gcp-project-123456:us-central1:my-database"),
                       "cloud-sql-proxy my-database")
    }

    // MARK: Parsers

    func testParseZshExtendedHistory() {
        let text = ": 1700000000:0;git status\n: 1700000001:0;echo uno \\\ndos\n: 1700000002:0;ls\n"
        let cmds = HistoryScanner.parseZsh(Data(text.utf8)).filter { !$0.isEmpty }
        XCTAssertEqual(cmds, ["git status", "echo uno \\\ndos", "ls"])
    }

    func testParseZshMetafiedUTF8() {
        // "ñ" = C3 B1; zsh guarda 0xB1 sin metafy, pero bytes >= 0x83 meta-codificados: 0x83, byte^0x20
        var bytes = Array(": 1:0;echo ".utf8)
        bytes += [0xC3, 0x83, 0xB1 ^ 0x20] // 0x83 + (0xB1 ^ 0x20)
        let cmds = HistoryScanner.parseZsh(Data(bytes))
        XCTAssertEqual(cmds.first, "echo ñ")
    }

    func testParseFish() {
        let text = "- cmd: git status\n  when: 1\n- cmd: echo a\\nb\n  when: 2\n"
        XCTAssertEqual(HistoryScanner.parseFish(Data(text.utf8)), ["git status", "echo a\nb"])
    }
}
