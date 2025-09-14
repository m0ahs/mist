# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

Mel is an iOS application featuring a conversational AI interface with the "Alyn" personality. The app is built with SwiftUI and targets iOS 18.5+, providing both text and image-based AI interactions through OpenRouter's API.

## Development Commands

### Building and Running
```bash
# Build the project (from project root)
xcodebuild -project Mel.xcodeproj -scheme Mel -destination "platform=iOS Simulator,name=iPhone 15" build

# Run in Xcode
open Mel.xcodeproj

# Clean build folder
xcodebuild -project Mel.xcodeproj -scheme Mel clean
```

### Testing
```bash
# Run unit tests (if available)
xcodebuild test -project Mel.xcodeproj -scheme Mel -destination "platform=iOS Simulator,name=iPhone 15"

# Test specific target
xcodebuild test -project Mel.xcodeproj -scheme Mel -destination "platform=iOS Simulator,name=iPhone 15" -only-testing:MelTests
```

### Code Quality
```bash
# Swift formatting (if swiftformat is installed)
swiftformat Mel/

# Swift linting (if swiftlint is installed)
swiftlint Mel/
```

## Architecture

### Core Components

**AIManager** (`AIManager.swift`)
- Central AI service coordinator using the `@MainActor` pattern for UI updates
- Manages conversation state and history (last 6 turns)
- Handles both text and image inputs through OpenRouter API
- Implements the "Alyn" personality with extensive system prompting
- States: `.idle`, `.thinking`, `.responding`, `.error(String)`

**ContentView** (`ContentView.swift`) 
- Main chat interface with advanced SwiftUI implementation
- Features smooth scrolling with custom scroll offset tracking
- Implements haptic feedback and camera/photo picker integration
- Uses `.ultraThinMaterial` blur effects for modern iOS design
- Custom animation system with smooth interpolation functions

**OpenRouterService** (`OpenRouterService.swift`)
- HTTP client for OpenRouter API integration
- Handles multimodal requests (text + base64 encoded images)
- Uses structured message format with role-based conversation history
- Configured for "openai/gpt-oss-20b:free" model by default

**LocalLLMService** (`LocalLLMService.swift`)
- Placeholder for Core ML model integration (not implemented)
- Designed to load "MistLM.mlmodelc" model bundle

### UI Architecture

- **Message System**: Bidirectional chat with timestamp formatting
- **Input Handling**: Multi-line text field with attachment support  
- **Media Integration**: Camera capture and photo library access
- **Responsive Design**: Adaptive layouts for iPhone and iPad (portrait/landscape)
- **Accessibility**: Proper focus management and keyboard handling

### Key Design Patterns

- **MVVM**: ContentView as View, AIManager as ViewModel/Model
- **Actor Model**: `@MainActor` for UI thread safety
- **Reactive UI**: `@Published` properties with SwiftUI bindings
- **Async/Await**: Modern concurrency for AI API calls
- **Coordinator Pattern**: Custom camera picker implementation

## Configuration

### API Configuration
The app uses a hardcoded OpenRouter API key in `AIManager.swift`. For production:
```swift
// Replace hardcoded key in AIManager.swift line 33-34
private let openRouter = OpenRouterService(
    apiKey: "your-api-key-here"
)
```

### Build Settings
- **iOS Deployment Target**: 18.5
- **Bundle ID**: com.josephmbai.mel  
- **Team ID**: R5RLJQL933
- **Swift Version**: 5.0
- **Device Family**: iPhone + iPad (1,2)

### Capabilities Required
- Camera access (for photo capture)
- Photo library access (for image selection)
- Network access (for AI API calls)

## Development Notes

### Adding New AI Services
Implement the pattern established by `OpenRouterService.swift`:
1. Create structured request/response models
2. Handle async HTTP requests with proper error handling
3. Support multimodal inputs (text + images)
4. Integrate with `AIManager` following the existing state management pattern

### UI Customization
The app uses a sophisticated blur/material design system:
- Header overlay with dynamic opacity based on scroll position
- Custom animation curves (`smoothstep` function)
- Haptic feedback integration
- Dark/light mode considerations

### State Management
All AI operations flow through `AIManager`:
- Conversation history maintained in memory
- User name extraction from messages
- State transitions for loading indicators
- Error handling with user-friendly messages

### Performance Considerations
- Conversation history limited to last 6 turns
- Image compression (0.9 quality JPEG)
- Efficient SwiftUI view updates with `@Published`
- Scroll position tracking for UI effects