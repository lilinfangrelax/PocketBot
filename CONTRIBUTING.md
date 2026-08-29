# Contributing to PocketBot

Thank you for your interest in contributing to PocketBot! This document provides guidelines and instructions for contributing.

## Getting Started

### Prerequisites

- Flutter 3.19+
- Android Studio or VS Code
- Git

### Development Setup

1. **Fork the repository**
   ```bash
   git fork https://github.com/yourusername/PocketBot.git
   ```

2. **Clone your fork**
   ```bash
   git clone https://github.com/yourusername/PocketBot.git
   cd PocketBot
   ```

3. **Set up upstream remote**
   ```bash
   git remote add upstream https://github.com/original-owner/PocketBot.git
   ```

4. **Create a feature branch**
   ```bash
   git checkout -b feature/amazing-new-feature
   ```

5. **Install dependencies**
   ```bash
   flutter pub get
   ```

## Development Workflow

### 1. Making Changes

- Write clean, readable code
- Follow Dart/Flutter conventions
- Add comments for complex logic
- Keep PRs focused and small

### 2. Testing

**Before committing:**
```bash
# Run unit tests
flutter test

# Run with coverage
flutter test --coverage

# Check code analysis
flutter analyze
```

**Integration tests:**
```bash
flutter test integration_test/
```

### 3. Code Style

**Format code:**
```bash
flutter format lib/ test/
```

**Run linter:**
```bash
flutter pub run custom_lint
```

### 4. Commit Messages

Follow conventional commits:

```
feat: Add new chat feature
fix: Fix connection timeout issue
docs: Update README
refactor: Simplify message parsing
test: Add unit tests for WebSocket
chore: Update dependencies
```

### 5. Pull Request Process

1. **Update your branch**
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. **Push your changes**
   ```bash
   git push origin feature/amazing-new-feature
   ```

3. **Create PR**
   - Go to GitHub
   - Click "New Pull Request"
   - Fill out the template
   - Request review

4. **Address feedback**
   - Make requested changes
   - Push updates

### 6. PR Requirements

Before a PR can be merged:

- [ ] All tests pass
- [ ] Code follows style guidelines
- [ ] New code has tests
- [ ] Documentation updated
- [ ] No breaking changes (or documented)

## Architecture

### Project Structure

```
lib/
├── config/         # Configuration classes
├── models/         # Data models
├── screens/        # UI screens
├── services/       # Business logic
├── utils/          # Helpers
└── widgets/        # Reusable UI components
```

### Key Components

- **AcpTransport / WebSocketService**: Local stdio, SSH, and optional WebSocket ACP
- **ConnectionManager**: Saved targets and connection lifecycle
- **Message Models**: Data structures for messages

### Testing Strategy

- **Unit Tests**: Model serialization, utility functions
- **Widget Tests**: UI components
- **Integration Tests**: Full user flows

## Code Review Guidelines

Reviewers will check for:

1. **Functionality**: Does it work as intended?
2. **Tests**: Are there tests? Do they pass?
3. **Style**: Does it follow the style guide?
4. **Complexity**: Is it too complex? Can it be simpler?
5. **Documentation**: Are complex parts documented?

## Questions?

If you have questions, please open an issue with the `question` label.

## Recognition

Contributors will be listed in the README and release notes.

Thank you for contributing! 🎉
