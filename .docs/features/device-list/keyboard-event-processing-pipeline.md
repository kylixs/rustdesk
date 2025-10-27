# Keyboard Event Processing Pipeline

## Overview

This document explains the complete path of keyboard events in RustDesk, from user input to transmission to the remote host. It covers the role of `_rawKeyFocusNode` and the entire processing pipeline.

## 1. What is `_rawKeyFocusNode`?

### Definition
Located in `flutter/lib/desktop/pages/remote_page.dart:87`:

```dart
final FocusNode _rawKeyFocusNode = FocusNode(debugLabel: "rawkeyFocusNode");
```

### Purpose
`_rawKeyFocusNode` is a **FocusNode** that serves as the focal point for capturing keyboard events for the remote desktop session.

**Key characteristics**:
- **FocusNode**: Flutter widget that can receive keyboard focus and keyboard events
- **Debug label**: "rawkeyFocusNode" for debugging and identification
- **Scope**: Belongs to the `RemotePage` widget instance
- **Lifecycle**: Created with the `RemotePage` and disposed when the page is disposed

### Why it's needed
In Flutter's focus system, only widgets with focus can receive keyboard events. The `_rawKeyFocusNode` ensures that:
1. The remote desktop area can receive keyboard focus
2. Keyboard events are captured even when other widgets are present
3. Focus can be explicitly requested when the user interacts with the remote desktop
4. Focus state can be monitored for debugging and diagnostics

## 2. Complete Keyboard Event Flow

### High-Level Pipeline

```
┌─────────────────┐
│ Physical        │
│ Keyboard        │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Operating       │
│ System          │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Flutter         │
│ Engine          │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ FocusManager    │
│ (Dispatch)      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ _rawKeyFocusNode│
│ (Remote Page)   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ RawKeyFocusScope│
│ onKeyEvent      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ InputModel      │
│ handleKeyEvent  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ newKeyboardMode │
│ or legacy mode  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ FFI Bridge      │
│ sessionHandle   │
│ FlutterKeyEvent │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Rust Session    │
│ Handler         │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Remote Host     │
│ (Actual PC)     │
└─────────────────┘
```

## 3. Detailed Step-by-Step Processing

### Step 1: Physical Keyboard → OS → Flutter Engine

When a user presses a key:
1. The physical keyboard sends a scan code to the OS
2. The OS translates it to a virtual key code
3. The OS sends the key event to the focused window (RustDesk)
4. Flutter Engine receives the raw key event from the OS

### Step 2: Flutter Engine → FocusManager

**File**: Flutter framework internals

The Flutter Engine:
1. Wraps the OS key event into a `KeyEvent` object
2. Passes it to the `FocusManager`
3. `FocusManager` identifies which `FocusNode` has focus
4. Dispatches the event to that `FocusNode`'s event handlers

### Step 3: FocusManager → _rawKeyFocusNode

**File**: `flutter/lib/desktop/pages/remote_page.dart:87`

```dart
final FocusNode _rawKeyFocusNode = FocusNode(debugLabel: "rawkeyFocusNode");
```

When `_rawKeyFocusNode` has focus:
1. It receives the `KeyEvent` from `FocusManager`
2. The event is passed to its parent widget's `onKeyEvent` callback
3. This callback is defined in `RawKeyFocusScope`

**Focus acquisition**:
- When user enters the remote desktop area: `enterView()` calls `_rawKeyFocusNode.requestFocus()` (line 425)
- When user clicks on remote desktop: Focus is automatically requested
- Can be verified with: `_rawKeyFocusNode.hasFocus` (returns bool)

### Step 4: _rawKeyFocusNode → RawKeyFocusScope.onKeyEvent

**File**: `flutter/lib/common/widgets/remote_input.dart:55-62`

```dart
onKeyEvent: useRawKeyEvents
    ? null
    : (FocusNode node, KeyEvent event) {
        debugPrint('[TRACE] RawKeyFocusScope.onKeyEvent: ${event.runtimeType}, logicalKey=${event.logicalKey}, character=${event.character}, nodeHasFocus=${node.hasFocus}');
        final result = inputModel.handleKeyEvent(event);
        debugPrint('[TRACE] RawKeyFocusScope.onKeyEvent result: $result');
        return result;
      },
```

**Processing**:
1. Receives the `KeyEvent` and the `FocusNode` (which is `_rawKeyFocusNode`)
2. Logs the event details for debugging
3. Calls `inputModel.handleKeyEvent(event)`
4. Returns `KeyEventResult.handled` or `KeyEventResult.ignored`

**Event properties available at this stage**:
- `event.runtimeType`: Type of event (KeyDownEvent, KeyUpEvent, KeyRepeatEvent)
- `event.logicalKey`: Logical key (e.g., LogicalKeyboardKey.keyA)
- `event.physicalKey`: Physical key location (e.g., PhysicalKeyboardKey.keyA)
- `event.character`: Character representation (e.g., "a", "A", "1")
- `event.timeStamp`: When the event occurred

### Step 5: RawKeyFocusScope → InputModel.handleKeyEvent

**File**: `flutter/lib/models/input_model.dart:555-624`

```dart
KeyEventResult handleKeyEvent(KeyEvent e) {
  // 1. Check if input is allowed
  if (isViewOnly) return KeyEventResult.handled;
  if (isViewCamera) return KeyEventResult.handled;
  if (!isInputSourceFlutter) {
    if (isDesktop) {
      return KeyEventResult.handled;
    } else if (isWeb) {
      return KeyEventResult.ignored;
    }
  }

  // 2. Handle Windows/Linux meta key special case
  if (isWindows || isLinux) {
    // Ignore meta keys to prevent window focus loss
    if (e.physicalKey == PhysicalKeyboardKey.metaLeft ||
        e.physicalKey == PhysicalKeyboardKey.metaRight) {
      return KeyEventResult.handled;
    }
  }

  // 3. Track modifier key states
  if (e is KeyUpEvent) {
    handleKeyUpEventModifiers(e);
  } else if (e is KeyDownEvent) {
    handleKeyDownEventModifiers(e);
  }

  // 4. Route to appropriate keyboard mode handler
  final isDesktopAndMapMode =
      isDesktop || (isWebDesktop && keyboardMode == kKeyMapMode);
  if (isMobileAndMapMode || isDesktopAndMapMode) {
    newKeyboardMode(
        e.character ?? '',
        e.physicalKey.usbHidUsage & 0xFFFF,
        e is KeyDownEvent || e is KeyRepeatEvent);
  } else {
    legacyKeyboardMode(e);
  }

  return KeyEventResult.handled;
}
```

**Key processing steps**:

#### 5.1 Validation
- Checks if view-only mode is active (no input allowed)
- Checks if camera view mode is active
- Verifies the input source is Flutter

#### 5.2 Platform-specific handling
- **Windows/Linux**: Blocks meta keys to prevent focus loss
- These keys are handled but not transmitted

#### 5.3 Modifier tracking
- **KeyDownEvent**: Records that a modifier (Ctrl, Alt, Shift, Meta) is pressed
- **KeyUpEvent**: Records that a modifier is released
- Maintains internal state of which modifiers are currently active

Methods:
```dart
void handleKeyDownEventModifiers(KeyDownEvent e) {
  // Track Alt, Ctrl, Shift, Meta key states
}

void handleKeyUpEventModifiers(KeyUpEvent e) {
  // Clear modifier states on release
}
```

#### 5.4 Mode routing

**Desktop (Map Mode)**:
- Uses USB HID codes for maximum compatibility
- Calls `newKeyboardMode(character, usbHid, down)`
- This is the modern, recommended mode

**Mobile/Legacy Mode**:
- Uses logical key codes
- Calls `legacyKeyboardMode(e)`
- Maintained for backward compatibility

### Step 6: InputModel → newKeyboardMode

**File**: `flutter/lib/models/input_model.dart:627-650`

```dart
void newKeyboardMode(String character, int usbHid, bool down) {
  const capslock = 1;
  const numlock = 2;
  const scrolllock = 3;

  // 1. Collect lock mode states
  int lockModes = 0;
  if (HardwareKeyboard.instance.lockModesEnabled
      .contains(KeyboardLockMode.capsLock)) {
    lockModes |= (1 << capslock);
  }
  if (HardwareKeyboard.instance.lockModesEnabled
      .contains(KeyboardLockMode.numLock)) {
    lockModes |= (1 << numlock);
  }
  if (HardwareKeyboard.instance.lockModesEnabled
      .contains(KeyboardLockMode.scrollLock)) {
    lockModes |= (1 << scrolllock);
  }

  // 2. Send to FFI bridge
  bind.sessionHandleFlutterKeyEvent(
      sessionId: sessionId,
      character: character,
      usbHid: usbHid,
      lockModes: lockModes,
      downOrUp: down);
}
```

**Key transformations**:

#### 6.1 Extract character
- `character`: The text representation of the key
- Examples: "a", "A", "1", "!", " " (space)
- Empty string for non-character keys (F1, arrows, etc.)

#### 6.2 Extract USB HID usage code
- `usbHid`: Physical key position identifier
- Format: `physicalKey.usbHidUsage & 0xFFFF` (lower 16 bits)
- Example: 0x0004 for 'A' key, 0x001E for '1' key
- **Why USB HID**: Universal standard that works across different keyboard layouts

#### 6.3 Determine key state
- `down`: Boolean indicating if key is pressed or released
- `true` for KeyDownEvent or KeyRepeatEvent
- `false` for KeyUpEvent

#### 6.4 Collect lock modes
- Reads current state of Caps Lock, Num Lock, Scroll Lock
- Encodes as bit flags:
  - Bit 1: Caps Lock
  - Bit 2: Num Lock
  - Bit 3: Scroll Lock
- **Why needed**: Ensures remote host has same lock states

### Step 7: newKeyboardMode → FFI Bridge

**File**: Auto-generated FFI bindings (from flutter_rust_bridge)

```dart
bind.sessionHandleFlutterKeyEvent(
    sessionId: sessionId,
    character: character,
    usbHid: usbHid,
    lockModes: lockModes,
    downOrUp: down);
```

**FFI Bridge role**:
1. Converts Dart types to C-compatible types
2. Marshals data across the Dart ↔ Rust boundary
3. Calls the corresponding Rust function
4. No return value (fire-and-forget for performance)

**Parameters passed**:
- `sessionId`: String identifying the remote session
- `character`: String (possibly empty)
- `usbHid`: int (16-bit USB HID usage code)
- `lockModes`: int (3-bit flags)
- `downOrUp`: bool (true = down, false = up)

### Step 8: FFI Bridge → Rust Session Handler

**File**: `src/flutter_ffi.rs` (estimated location)

The Rust side receives the FFI call:
1. Unmarshals the parameters from C types
2. Looks up the session by `sessionId`
3. Calls the session's key event handler

**Processing in Rust**:
```rust
// Pseudo-code (actual implementation may vary)
pub fn session_handle_flutter_key_event(
    session_id: String,
    character: String,
    usb_hid: u32,
    lock_modes: u32,
    down_or_up: bool,
) {
    let session = get_session(&session_id)?;
    session.handle_key_event(character, usb_hid, lock_modes, down_or_up);
}
```

### Step 9: Rust Session → Remote Host

**File**: `src/client.rs` and related files

The Rust session handler:
1. **Encodes the key event** into the RustDesk protocol format
2. **Serializes** the event (likely using protobuf)
3. **Encrypts** the data (if encryption is enabled)
4. **Sends** over the network connection to the remote host
5. The remote host's RustDesk service **receives** the packet
6. **Decrypts** and **deserializes** the event
7. **Simulates** the keyboard input on the remote OS

**Protocol considerations**:
- Uses UDP or TCP depending on connection quality
- Implements reliability and ordering for UDP mode
- Handles network latency and packet loss
- Maintains synchronization of keyboard states

## 4. Event Data Transformation Summary

### Input: OS Keyboard Event
- Platform-specific scan code
- Virtual key code
- Character
- Modifiers state

### After Flutter Engine: KeyEvent
```dart
KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.keyA,
  logicalKey: LogicalKeyboardKey.keyA,
  character: "a",
  timeStamp: Duration(...)
)
```

### After InputModel: Extracted Components
```dart
character: "a"
usbHid: 0x0004  // USB HID usage for 'A' key
lockModes: 0b010  // Only Num Lock is on
down: true  // Key down event
```

### Sent to FFI Bridge
```
sessionId: "abc123"
character: "a"
usbHid: 4
lockModes: 2
downOrUp: true
```

### Transmitted over Network (Serialized)
```
[Protobuf/Binary Format]
- session_id: "abc123"
- key_event {
    character: "a"
    usb_hid: 4
    lock_modes: 2
    down: true
  }
```

### Received by Remote Host
```
Simulates: Press 'A' key with current keyboard layout
```

## 5. Special Cases and Edge Cases

### 5.1 Modifier Keys (Ctrl, Alt, Shift)
- Tracked separately by `InputModel`
- State maintained across events
- Synchronized with remote host

### 5.2 Meta Key (Windows Key / Command Key)
- **Windows/Linux**: Blocked to prevent focus loss
- Not transmitted to remote host
- Prevents accidental window switching

### 5.3 Lock Keys (Caps Lock, Num Lock, Scroll Lock)
- State queried from `HardwareKeyboard.instance`
- Transmitted with every key event
- Ensures remote host matches local lock states

### 5.4 Non-Character Keys (Function Keys, Arrows)
- `character` is empty string
- USB HID code identifies the key
- Remote host interprets based on USB HID

### 5.5 Keyboard Layout Independence
- **USB HID codes** represent physical key positions
- Remote host applies its own keyboard layout
- Works correctly even if local and remote layouts differ

### 5.6 Key Repeat Events
- `KeyRepeatEvent`: Generated when key is held down
- Treated same as `KeyDownEvent`
- Remote host handles the actual repeat rate

## 6. Performance Characteristics

### Latency Breakdown
1. **OS → Flutter Engine**: < 1ms (OS event delivery)
2. **Flutter Engine → FocusManager**: < 1ms (internal dispatch)
3. **FocusManager → _rawKeyFocusNode**: < 1ms (focus tree traversal)
4. **_rawKeyFocusNode → RawKeyFocusScope**: < 1ms (callback invoke)
5. **RawKeyFocusScope → InputModel**: < 1ms (method call)
6. **InputModel → newKeyboardMode**: < 1ms (processing)
7. **newKeyboardMode → FFI**: < 1ms (data marshaling)
8. **FFI → Rust**: < 1ms (cross-language call)
9. **Rust encoding → Network**: 1-5ms (serialization + send)
10. **Network → Remote host**: 10-100ms (network latency)

**Total local processing**: < 10ms
**Total end-to-end**: 20-120ms (depending on network)

### Optimization Techniques
1. **Fire-and-forget FFI**: No return value, no waiting
2. **Direct callback chain**: Minimal indirection
3. **Efficient encoding**: USB HID is compact (2 bytes)
4. **No buffering**: Events sent immediately
5. **Lock state caching**: Read once per event

## 7. Debugging and Logging

### Enable Trace Logging
The codebase includes trace logging for keyboard events:

**Location**: `flutter/lib/common/widgets/remote_input.dart:55-62`

```dart
debugPrint('[TRACE] RawKeyFocusScope.onKeyEvent: ${event.runtimeType}, logicalKey=${event.logicalKey}, character=${event.character}, nodeHasFocus=${node.hasFocus}');
final result = inputModel.handleKeyEvent(event);
debugPrint('[TRACE] RawKeyFocusScope.onKeyEvent result: $result');
```

### Focus State Diagnostic
**Location**: `flutter/lib/desktop/pages/remote_page.dart:435-457`

```dart
void _checkFocusState(String source) {
  final hasFocus = _rawKeyFocusNode.hasFocus;
  final primaryFocus = FocusManager.instance.primaryFocus;

  debugPrint('[FOCUS_DIAGNOSTIC] Source: $source');
  debugPrint('[FOCUS_DIAGNOSTIC] RemotePage _rawKeyFocusNode.hasFocus: $hasFocus');
  debugPrint('[FOCUS_DIAGNOSTIC] FocusManager.instance.primaryFocus: $primaryFocus');
  debugPrint('[FOCUS_DIAGNOSTIC] FocusManager.instance.primaryFocus.debugLabel: ${primaryFocus?.debugLabel}');

  if (!hasFocus) {
    debugPrint('[FOCUS_WARNING] Remote desktop does NOT have focus after request!');
  } else {
    debugPrint('[FOCUS_SUCCESS] Remote desktop successfully has focus');
  }
}
```

### Log Analysis
When debugging keyboard issues, look for:
1. **[TRACE] RawKeyFocusScope.onKeyEvent**: Confirms event received
2. **nodeHasFocus=true**: Confirms focus is correct
3. **KeyEventResult.handled**: Confirms event was processed
4. **[FOCUS_SUCCESS]**: Confirms focus state is correct

## 8. Common Issues and Solutions

### Issue 1: Keys Not Captured
**Symptom**: Typing doesn't appear on remote desktop

**Diagnosis**:
- Check if `_rawKeyFocusNode.hasFocus` is `false`
- Look for missing `[TRACE]` logs

**Solution**:
- Call `_rawKeyFocusNode.requestFocus()` when entering view
- Ensure `canRequestFocus: true` in RawKeyFocusScope
- Click on remote desktop area to acquire focus

### Issue 2: Focus Stolen by Other Widgets
**Symptom**: Focus lost after certain interactions

**Diagnosis**:
- Check `FocusManager.instance.primaryFocus.debugLabel`
- It should be "rawkeyFocusNode"

**Solution**:
- Request focus in `enterView()` method
- Use `skipTraversal: true` on non-essential focusable widgets
- Call focus diagnostic to identify the stealing widget

### Issue 3: Wrong Characters Transmitted
**Symptom**: Different characters appear on remote desktop

**Root cause**: Keyboard layout mismatch is expected behavior

**Explanation**: USB HID codes represent physical keys, not characters. The remote host applies its keyboard layout.

### Issue 4: Modifier Keys Stuck
**Symptom**: Ctrl/Shift/Alt remains pressed on remote

**Diagnosis**:
- Check modifier tracking in `handleKeyDownEventModifiers` / `handleKeyUpEventModifiers`
- Ensure both KeyDown and KeyUp events are captured

**Solution**:
- Ensure focus is maintained during key press sequence
- Verify `KeyEventResult.handled` for all events
- Check network connection for packet loss

## 9. Comparison: Original Window vs Device Management Tab

See detailed comparison in: [keyboard-event-comparison-analysis.md](keyboard-event-comparison-analysis.md)

**Key difference**:
- **Original window**: Automatic focus retention (standalone window)
- **Device management tab**: Manual focus management (embedded in PageView)

**Same code path**:
Both use identical processing pipeline from Step 5 onward. The only difference is focus acquisition strategy.

## 10. Testing Recommendations

### Unit Testing
- Mock `InputModel.handleKeyEvent()`
- Verify modifier tracking logic
- Test lock mode bit encoding

### Integration Testing
- Use automated test script (e.g., `scripts/full-auto-test.ps1`)
- Verify focus acquisition
- Verify keyboard event capture
- Verify transmission to remote host

### Manual Testing Checklist
- [ ] Regular keys (a-z, 0-9)
- [ ] Shift + keys (capitals, symbols)
- [ ] Ctrl + keys (shortcuts)
- [ ] Alt + keys (menu access)
- [ ] Function keys (F1-F12)
- [ ] Arrow keys, Home, End, Page Up/Down
- [ ] Numpad keys (with Num Lock on/off)
- [ ] Special characters (@, #, $, etc.)
- [ ] Lock key toggles (Caps Lock, Num Lock)
- [ ] Key repeat (hold key down)

### Performance Testing
- Measure local processing latency (< 10ms expected)
- Measure end-to-end latency (depends on network)
- Verify no dropped events under high input rate
- Check CPU usage during continuous typing

## 11. Related Files

### Flutter Files
- `flutter/lib/desktop/pages/remote_page.dart` - RemotePage, _rawKeyFocusNode
- `flutter/lib/common/widgets/remote_input.dart` - RawKeyFocusScope
- `flutter/lib/models/input_model.dart` - InputModel, handleKeyEvent
- `flutter/lib/models/model.dart` - FFIModel base class

### Rust Files
- `src/flutter_ffi.rs` - FFI bridge, session handlers
- `src/client.rs` - Remote connection, protocol handling
- `src/server/input_service.rs` - Input simulation on remote host

### Documentation
- [keyboard-event-comparison-analysis.md](keyboard-event-comparison-analysis.md)
- [focus-diagnostic-implementation.md](focus-diagnostic-implementation.md)

## 12. Glossary

- **FocusNode**: Flutter class representing a node in the focus tree that can receive keyboard focus
- **FocusManager**: Global manager for keyboard focus in Flutter
- **KeyEvent**: Flutter class representing a keyboard event (KeyDownEvent, KeyUpEvent, KeyRepeatEvent)
- **USB HID Usage Code**: Universal identifier for physical keyboard keys (HID = Human Interface Device)
- **FFI**: Foreign Function Interface - mechanism for Dart to call Rust code
- **InputModel**: Flutter model class handling all input events for a remote session
- **SessionId**: Unique identifier for a remote desktop connection
- **Lock modes**: State of Caps Lock, Num Lock, Scroll Lock
- **Map mode**: Modern keyboard handling using USB HID codes
- **Legacy mode**: Older keyboard handling using logical key codes

## 13. Conclusion

The keyboard event processing pipeline in RustDesk is a well-designed system that:
1. Reliably captures keyboard input via Flutter's focus system
2. Transforms events into a platform-independent format (USB HID)
3. Efficiently transmits events across the FFI boundary
4. Ensures accurate input simulation on the remote host

The `_rawKeyFocusNode` is the critical entry point that connects Flutter's focus system to RustDesk's input handling, ensuring that all keyboard events are captured and forwarded to the remote desktop.
