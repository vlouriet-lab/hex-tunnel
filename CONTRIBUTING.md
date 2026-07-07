# Contributing to Hex Tunnel

First off, thank you for considering contributing to Hex Tunnel! It's people like you that make open-source software such a great community to learn, inspire, and create.

## Code of Conduct

By participating in this project, you are expected to uphold our Code of Conduct. Please be respectful and constructive in your interactions with other contributors.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the existing issues as you might find out that you don't need to create one. When you are creating a bug report, please include as many details as possible:

*   **App Version:** Specify the exact version you are running.
*   **Device Info:** Android version, device model.
*   **Logs:** Include relevant logcat output (make sure to redact any personal information or keys).
*   **Steps to Reproduce:** Provide a clear, step-by-step description of how to reproduce the problem.

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, please provide:
*   A clear and descriptive title.
*   A detailed description of the proposed feature.
*   Any relevant examples or mockups.

### Submitting Pull Requests

1.  **Fork the repository** and create your branch from `main`.
2.  **Write clean, documented code**. Follow the existing Dart and Kotlin formatting standards.
3.  **Test your changes**. Ensure your code does not break existing functionality (especially legacy fallback mechanisms and routing rules).
4.  **Commit your changes** with descriptive commit messages.
5.  **Create a Pull Request**. Provide a comprehensive description of the changes you've made.

## Development Environment Setup

1.  Install the Flutter SDK (3.19+).
2.  Install Android Studio.
3.  Clone the repository and run `flutter pub get`.
4.  If you modify the core `sing-box` integration, you may need to recompile the `libsingbox.so` bindings.

## Licensing

By contributing to Hex Tunnel, you agree that your contributions will be licensed under the project's Apache License 2.0 with the Commons Clause.
