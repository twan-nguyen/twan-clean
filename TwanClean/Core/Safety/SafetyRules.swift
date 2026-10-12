import Foundation

/// The path lists behind `PathPolicy`: which trees each removal purpose may
/// touch and which locations are never removable. Paths are canonical
/// (symlinks resolved, `/private` spelled out) so they compare against the
/// output of `realpath(3)`.
struct SafetyRules: Sendable {
    /// Canonical home directory, without a trailing slash.
    let home: String

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        home = Self.canonicalPath(homeDirectory.path) ?? homeDirectory.standardizedFileURL.path
    }

    // MARK: - Never removable

    /// Folders that must never be removed themselves, though some of their
    /// contents may be.
    var protectedRoots: [String] {
        [
            "/", "/System", "/Applications", "/Library", "/Users", "/Volumes",
            "/private", "/private/var", "/private/tmp", "/private/etc",
            "/usr", "/bin", "/sbin", "/opt", "/cores",
            home,
            "\(home)/Library", "\(home)/Applications", "\(home)/Desktop", "\(home)/Documents",
            "\(home)/Downloads", "\(home)/Movies", "\(home)/Music", "\(home)/Pictures",
            "\(home)/Public", "\(home)/.Trash",
        ]
    }

    /// Trees whose contents are never removable, whatever the purpose.
    var forbiddenTrees: [String] {
        [
            "/System", "/usr", "/bin", "/sbin", "/private/etc", "/Library/Apple",
            "/Library/Keychains", "/Library/SystemExtensions",
            "\(home)/Library/Keychains",
            "\(home)/Library/Mobile Documents",
            "\(home)/Library/CloudStorage",
            "\(home)/Library/Messages",
            "\(home)/Library/Mail",
            "\(home)/Library/Safari",
            "\(home)/Library/Calendars",
            "\(home)/Library/Accounts",
            "\(home)/Library/Application Support/AddressBook",
            "\(home)/Library/Application Support/com.apple.TCC",
        ] + highRiskHomeItems.map { "\(home)/\($0)" }
    }

    /// Credentials, shell setup and tool configuration in the home folder.
    /// Removing any of them can lock the user out of a service or break their
    /// tools, so they are never removable even when an app name matches.
    static let highRiskHomeItemNames: [String] = [
        ".ssh", ".aws", ".gnupg", ".gpg", ".kube", ".docker", ".config", ".claude",
        ".git", ".gitconfig", ".git-credentials", ".netrc", ".npmrc", ".yarnrc",
        ".pnpmrc", ".pip", ".pypirc", ".rbenv", ".pyenv", ".nvm", ".cargo", ".rustup",
        ".gem", ".local", ".password-store", ".mozilla", ".wine", ".vscode", ".vim",
        ".viminfo", ".zshrc", ".zprofile", ".zshenv", ".zlogin", ".zsh_history",
        ".bashrc", ".bash_profile", ".bash_history", ".profile", ".python_history",
        ".node_repl_history", ".lesshst",
    ]

    var highRiskHomeItems: [String] { Self.highRiskHomeItemNames }

    // MARK: - Allowed per purpose

    /// Trees whose contents a purpose may remove. An item must sit strictly
    /// inside one of them: the tree root itself is never removable.
    func allowedTrees(for purpose: RemovalPurpose) -> [String] {
        switch purpose {
        case .regenerableCache:
            [
                "\(home)/Library/Caches",
                "\(home)/Library/Logs",
                "\(home)/Library/HTTPStorages",
                "\(home)/Library/WebKit",
                "\(home)/Library/Saved Application State",
                "\(home)/Library/Developer/Xcode/DerivedData",
                "\(home)/Library/Developer/Xcode/Archives",
                "\(home)/Library/Developer/CoreSimulator/Caches",
                "\(home)/Library/Mail Downloads",
                "\(home)/Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
                "\(home)/Library/Containers/com.docker.docker/Data/log",
                "\(home)/Library/Containers/com.docker.docker/Data/tmp",
                "\(home)/Library/pnpm/store",
                "\(home)/.npm",
                "\(home)/.cache",
                "\(home)/.ollama/logs",
                "\(home)/.lmstudio/server-logs",
                "/Library/Caches",
                "/Library/Logs",
                "/private/var/log",
                "/private/var/tmp",
                "/private/tmp",
            ]
        case .trashContents:
            ["\(home)/.Trash"]
        case .userFile:
            [home]
        case .appBundle:
            ["/Applications", "\(home)/Applications"]
        case .appLeftover:
            [
                "\(home)/Library",
                "/Library/Application Support",
                "/Library/Caches",
                "/Library/Logs",
                "/Library/Preferences",
                "/Library/LaunchAgents",
                "/Library/LaunchDaemons",
                "/Library/PrivilegedHelperTools",
                "/private/var/db/receipts",
            ]
        case .orphan:
            [
                "\(home)/Library/Caches",
                "\(home)/Library/Logs",
                "\(home)/Library/Saved Application State",
                "\(home)/Library/HTTPStorages",
                "\(home)/Library/WebKit",
                "\(home)/Library/Application Support/CrashReporter",
                "/Library/Caches",
                "/Library/Logs",
            ]
        }
    }

    /// Trees a purpose may not touch even though an allowed tree contains them.
    func excludedTrees(for purpose: RemovalPurpose) -> [String] {
        switch purpose {
        case .userFile:
            // A user's files never include their Library, and the Trash has its
            // own purpose.
            ["\(home)/Library", "\(home)/.Trash"]
        default:
            []
        }
    }

    // MARK: - Helpers

    /// `realpath(3)`, which unlike `URL.resolvingSymlinksInPath()` keeps the
    /// `/private` prefix of `/tmp`, `/var` and `/etc`.
    static func canonicalPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
