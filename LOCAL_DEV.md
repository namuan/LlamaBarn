# Local Development Guide

## Prerequisites

- macOS 14.0+ (Sonoma or later)
- Xcode 16.0+
- Git
- CMake 3.28+

## Initial Setup

1. Clone the repository:
```sh
git clone https://github.com/ggml-org/LlamaBarn.git
cd LlamaBarn
```

2. Initialize and update submodules:
```sh
git submodule update --init --recursive
```

## Building

### Build llama.cpp dependencies
The application uses prebuilt llama.cpp libraries for development. To build them from source:

```sh
cd llama-cpp
mkdir build && cd build
cmake .. -DLLAMA_BUILD_SERVER=ON -DLLAMA_METAL=ON -DCMAKE_BUILD_TYPE=Release
cmake --build . -j $(sysctl -n hw.ncpu)
```

Copy the built libraries and server binary back to the `llama-cpp/` directory:
```sh
cp bin/llama-server ../
cp lib/*.dylib ../
```

### Build the macOS App

#### From Command Line
First configure signing for command line builds:
```sh
# List available development teams
xcodebuild -showsdks -list
```

#### Unsigned local build (no certificate required)
You can build without a signing certificate for local development only:
```sh
xcodebuild -project LlamaBarn.xcodeproj \
  -scheme LlamaBarn \
  -configuration Debug \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build
```

#### Signed release build
```sh
xcodebuild -project LlamaBarn.xcodeproj \
  -scheme LlamaBarn \
  -configuration Release \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  CODE_SIGN_STYLE=Automatic \
  build
```

The built app will be at:
```
~/Library/Developer/Xcode/DerivedData/LlamaBarn-*/Build/Products/Release/LlamaBarn.app
```

Run directly from command line:
```sh
# For unsigned debug build
open ~/Library/Developer/Xcode/DerivedData/LlamaBarn-*/Build/Products/Debug/LlamaBarn.app

# For signed release build
open ~/Library/Developer/Xcode/DerivedData/LlamaBarn-*/Build/Products/Release/LlamaBarn.app
```

#### In Xcode
Open the project in Xcode:
```sh
open LlamaBarn.xcodeproj
```

Then:
1. Select the `LlamaBarn` scheme
2. Select your development team (Signing & Capabilities tab)
3. Build with `Cmd+B` or run directly with `Cmd+R`

## Running Locally

The application runs as a menu bar app. When running locally:
- Configuration and models are stored in `~/.llamabarn/`
- The server starts automatically on `http://localhost:2276`
- You can access the built-in web UI at `http://localhost:2276`

### Verify the server is running
```sh
curl http://localhost:2276/v1/models
```

## Development Notes

- The project uses pure SwiftUI for all UI components
- llama.cpp server runs as a separate process managed by the app
- All networking is done with Foundation URLSession
- No external dependencies are required for the app itself

## Troubleshooting

### Build errors
1. Ensure submodules are fully updated: `git submodule update --init --recursive`
2. Clean build folder:
   - Xcode: `Cmd+Shift+K`
   - Command line: `xcodebuild clean`
3. Delete derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`
4. For command line signing errors: verify your DEVELOPMENT_TEAM id is correct

### Server won't start
1. Check `Console.app` for logs from `LlamaBarn`
2. Verify permissions: `Settings > Privacy & Security > Full Disk Access`
3. Ensure port 2276 is not in use: `lsof -i :2276`

## Debug Builds

For debugging llama.cpp integration, run the server manually:
```sh
./llama-cpp/llama-server --port 2276
```

Run the application separately in Xcode with the debug configuration.
