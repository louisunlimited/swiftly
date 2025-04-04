import Foundation
@testable import Swiftly
@testable import SwiftlyCore
import XCTest

final class UpdateTests: SwiftlyTests {
    /// Verify updating the most up-to-date toolchain has no effect.
    func testUpdateLatest() async throws {
        try await self.withTestHome {
            try await self.withMockedToolchain {
                try await self.installMockedToolchain(selector: .latest)

                let beforeUpdateConfig = try Config.load()

                var update = try self.parseCommand(Update.self, ["update", "latest", "--no-verify", "--post-install-file=\(Swiftly.currentPlatform.getTempFilePath().path)"])
                try await update.run()

                XCTAssertEqual(try Config.load(), beforeUpdateConfig)
                try await validateInstalledToolchains(
                    beforeUpdateConfig.installedToolchains,
                    description: "Updating latest toolchain should have no effect"
                )
            }
        }
    }

    /// Verify that attempting to update when no toolchains are installed has no effect.
    func testUpdateLatestWithNoToolchains() async throws {
        try await self.withTestHome {
            try await self.withMockedToolchain {
                var update = try self.parseCommand(Update.self, ["update", "latest", "--no-verify", "--post-install-file=\(Swiftly.currentPlatform.getTempFilePath().path)"])
                try await update.run()

                try await validateInstalledToolchains(
                    [],
                    description: "Updating should not install any toolchains"
                )
            }
        }
    }

    /// Verify that updating the latest installed toolchain updates it to the latest available toolchain.
    func testUpdateLatestToLatest() async throws {
        try await self.withTestHome {
            try await self.withMockedToolchain {
                try await self.installMockedToolchain(selector: .stable(major: 5, minor: 9, patch: 0))
                var update = try self.parseCommand(Update.self, ["update", "-y", "latest", "--no-verify", "--post-install-file=\(Swiftly.currentPlatform.getTempFilePath().path)"])
                try await update.run()

                let config = try Config.load()
                let inUse = config.inUse!.asStableRelease!

                XCTAssertGreaterThan(inUse, .init(major: 5, minor: 9, patch: 0))
                try await validateInstalledToolchains(
                    [config.inUse!],
                    description: "Updating toolchain should properly install new toolchain and uninstall old"
                )
            }
        }
    }

    /// Verify that the latest installed toolchain for a given major version can be updated to the latest
    /// released minor version.
    func testUpdateToLatestMinor() async throws {
        try await self.withTestHome {
            try await self.withMockedToolchain {
                try await self.installMockedToolchain(selector: .stable(major: 5, minor: 9, patch: 0))
                var update = try self.parseCommand(Update.self, ["update", "-y", "5", "--no-verify", "--post-install-file=\(Swiftly.currentPlatform.getTempFilePath().path)"])
                try await update.run()

                let config = try Config.load()
                let inUse = config.inUse!.asStableRelease!

                XCTAssertEqual(inUse.major, 5)
                XCTAssertGreaterThan(inUse.minor, 0)

                try await validateInstalledToolchains(
                    [config.inUse!],
                    description: "Updating toolchain should properly install new toolchain and uninstall old"
                )
            }
        }
    }

    /// Verify that a toolchain can be updated to the latest patch version of that toolchain's minor version.
    func testUpdateToLatestPatch() async throws {
        let snapshotsAvailable = try await self.snapshotsAvailable()
        try XCTSkipIf(!snapshotsAvailable)

        try await self.withTestHome {
            try await self.withMockedToolchain {
                try await self.installMockedToolchain(selector: "5.9.0")

                var update = try self.parseCommand(Update.self, ["update", "-y", "5.9.0", "--no-verify", "--post-install-file=\(Swiftly.currentPlatform.getTempFilePath().path)"])
                try await update.run()

                let config = try Config.load()
                let inUse = config.inUse!.asStableRelease!

                XCTAssertEqual(inUse.major, 5)
                XCTAssertEqual(inUse.minor, 9)
                XCTAssertGreaterThan(inUse.patch, 0)

                try await validateInstalledToolchains(
                    [config.inUse!],
                    description: "Updating toolchain should properly install new toolchain and uninstall old"
                )
            }
        }
    }

    /// Verifies that updating the currently global default toolchain can be updated, and that after update the new toolchain
    /// will be the global default instead.
    func testUpdateGlobalDefault() async throws {
        try await self.withTestHome {
            try await self.withMockedToolchain {
                try await self.installMockedToolchain(selector: "6.0.0")

                var update = try self.parseCommand(Update.self, ["update", "-y", "--no-verify", "--post-install-file=\(Swiftly.currentPlatform.getTempFilePath().path)"])
                try await update.run()

                let config = try Config.load()
                let inUse = config.inUse!.asStableRelease!
                XCTAssertGreaterThan(inUse, .init(major: 6, minor: 0, patch: 0))
                XCTAssertEqual(inUse.major, 6)
                XCTAssertEqual(inUse.minor, 0)
                XCTAssertGreaterThan(inUse.patch, 0)

                try await self.validateInstalledToolchains(
                    [config.inUse!],
                    description: "update should update the in use toolchain to latest patch"
                )

                try await self.validateInUse(expected: config.inUse!)
            }
        }
    }

    /// Verifies that updating the currently in-use toolchain can be updated, and that after update the new toolchain
    /// will be in-use with the swift version file updated.
    func testUpdateInUse() async throws {
        try await self.withTestHome {
            try await self.withMockedToolchain {
                try await self.installMockedToolchain(selector: "6.0.0")

                let versionFile = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".swift-version")
                try "6.0.0".write(to: versionFile, atomically: true, encoding: .utf8)

                var update = try self.parseCommand(Update.self, ["update", "-y", "--no-verify", "--post-install-file=\(Swiftly.currentPlatform.getTempFilePath().path)"])
                try await update.run()

                let versionFileContents = try String(contentsOf: versionFile, encoding: .utf8)
                let inUse = try ToolchainVersion(parsing: versionFileContents)
                XCTAssertGreaterThan(inUse, .init(major: 6, minor: 0, patch: 0))

                // Since the global default was set to 6.0.0, and that toolchain is no longer installed
                // the update should have unset it to prevent the config from going into a bad state.
                let config = try Config.load()
                XCTAssertTrue(config.inUse == nil)

                // The new toolchain should be installed
                XCTAssertTrue(config.installedToolchains.contains(inUse))
            }
        }
    }

    /// Verifies that snapshots, both from the main branch and from development branches, can be updated.
    func testUpdateSnapshot() async throws {
        let snapshotsAvailable = try await self.snapshotsAvailable()
        try XCTSkipIf(!snapshotsAvailable)

        let branches: [ToolchainVersion.Snapshot.Branch] = [
            .main,
            .release(major: 6, minor: 0),
        ]

        for branch in branches {
            try await self.withTestHome {
                try await self.withMockedToolchain {
                    let date = "2024-06-18"
                    try await self.installMockedToolchain(selector: .snapshot(branch: branch, date: date))

                    var update = try self.parseCommand(
                        Update.self, ["update", "-y", "\(branch.name)-snapshot", "--no-verify", "--post-install-file=\(Swiftly.currentPlatform.getTempFilePath().path)"]
                    )
                    try await update.run()

                    let config = try Config.load()
                    let inUse = config.inUse!.asSnapshot!
                    XCTAssertGreaterThan(inUse, .init(branch: branch, date: date))
                    XCTAssertEqual(inUse.branch, branch)
                    XCTAssertGreaterThan(inUse.date, date)

                    try await self.validateInstalledToolchains(
                        [config.inUse!],
                        description: "update should work with snapshots"
                    )
                }
            }
        }
    }

    /// Verify that the latest of all the matching release toolchains is updated.
    func testUpdateSelectsLatestMatchingStableRelease() async throws {
        try await self.withTestHome {
            try await self.withMockedToolchain {
                try await self.installMockedToolchain(selector: "6.0.1")
                try await self.installMockedToolchain(selector: "6.0.0")

                var update = try self.parseCommand(Update.self, ["update", "-y", "6.0", "--no-verify", "--post-install-file=\(Swiftly.currentPlatform.getTempFilePath().path)"])
                try await update.run()

                let config = try Config.load()
                let inUse = config.inUse!.asStableRelease!
                XCTAssertEqual(inUse.major, 6)
                XCTAssertEqual(inUse.minor, 0)
                XCTAssertGreaterThan(inUse.patch, 1)

                try await self.validateInstalledToolchains(
                    [config.inUse!, .init(major: 6, minor: 0, patch: 0)],
                    description: "update with ambiguous selector should update the latest matching toolchain"
                )
            }
        }
    }

    /// Verify that the latest of all the matching snapshot toolchains is updated.
    func testUpdateSelectsLatestMatchingSnapshotRelease() async throws {
        let snapshotsAvailable = try await self.snapshotsAvailable()
        try XCTSkipIf(!snapshotsAvailable)

        let branches: [ToolchainVersion.Snapshot.Branch] = [
            .main,
            .release(major: 6, minor: 0),
        ]

        for branch in branches {
            try await self.withTestHome {
                try await self.withMockedToolchain {
                    try await self.installMockedToolchain(selector: .snapshot(branch: branch, date: "2024-06-19"))
                    try await self.installMockedToolchain(selector: .snapshot(branch: branch, date: "2024-06-18"))

                    var update = try self.parseCommand(
                        Update.self, ["update", "-y", "\(branch.name)-snapshot", "--no-verify", "--post-install-file=\(Swiftly.currentPlatform.getTempFilePath().path)"]
                    )
                    try await update.run()

                    let config = try Config.load()
                    let inUse = config.inUse!.asSnapshot!

                    XCTAssertEqual(inUse.branch, branch)
                    XCTAssertGreaterThan(inUse.date, "2024-06-18")

                    try await self.validateInstalledToolchains(
                        [config.inUse!, .init(snapshotBranch: branch, date: "2024-06-18")],
                        description: "update with ambiguous selector should update the latest matching toolchain"
                    )
                }
            }
        }
    }
}
