# Create the demo desktop app in Xcode

Goal: an empty macOS SwiftUI app in `logic_for_play_demo/`, ready to receive the demo of the logic described in `LOGIC_FOR_PLAY.md`.

## Steps

1. Open Xcode and choose **File > New > Project…**
2. Pick the **macOS** tab, then **App**, then **Next**.
3. Fill in the options:

   | Field | Value |
   | --- | --- |
   | Product Name | `logic_for_play_demo` |
   | Team | your personal team (or None) |
   | Organization Identifier | anything, e.g. `com.stopsopa` |
   | Interface | SwiftUI |
   | Language | Swift |
   | Testing System | None |
   | Storage | None |

4. Click **Next**. In the save dialog select the repo root:
   `/Users/szdz/Workspace/STOPSOPA__play-app/STOPSOPA__play-app`
   Do not create the `logic_for_play_demo` folder yourself. Xcode creates it.
5. **Uncheck "Create Git repository on my Mac"**, because the folder is already inside this repo. Click **Create**.
6. Only if the demo should play real audio files: select the project in the navigator, then the target, then **Signing & Capabilities**. Under **App Sandbox > File Access** set **User Selected File** to **Read Only**. For a local-only demo you can instead remove the App Sandbox capability.
7. Press **Cmd+R**. An empty "Hello, world!" window should build and open.

## Expected result

```
logic_for_play_demo/
  logic_for_play_demo.xcodeproj
  logic_for_play_demo/
    logic_for_play_demoApp.swift
    ContentView.swift
    Assets.xcassets
```

If you see `logic_for_play_demo/logic_for_play_demo/logic_for_play_demo.xcodeproj` (one level too deep), the folder was created by hand in step 4. Delete it and repeat from step 1.
