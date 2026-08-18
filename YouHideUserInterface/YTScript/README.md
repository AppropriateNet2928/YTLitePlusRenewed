# YTScript

**YTScript** is a preprocessor framework for building YouTube iOS tweaks with [Theos](https://theos.dev). It lets you declare settings (toggles, sliders, menus) and conditional hook groups using simple macros in your `.xm` file. The generator automatically produces all the Objective-C/Logos code for YouTube's native settings UI.

---

## Quick Start

### 1. Import the runtime

```objc
#import <YTScript/YTScriptRuntime.h>
```

This single header gives you access to **everything** — generator directives, storage macros, conditions, and logging.

### 2. Declare your settings page

```objc
YT_PAGE(@"MyTweak");
YT_ICON(@"gear");
YT_TOGGLE(@"MyTweak", @"Enable or disable this tweak. App restart required.", YES);
YT_SLIDER(@"Opacity", 1, 10, 5, @"Set the opacity level from 1 to 10.");

YT_ON(MyTweak)

// ... your Logos hooks here ...

YT_END
```

### 3. Build

```bash
make clean
make
```

The preprocessor runs automatically before compilation and generates a `.processed.xm` file with all the settings UI code and Logos groups.

---

## File Structure

```
YTScript/
├── YTScriptRuntime.h      ← Single runtime header (import this)
├── YTScriptGenerator.py   ← Core preprocessor (generates .processed.xm)
├── YTScriptCompiler.py    ← Build automation (finds .xm files, calls generator)
└── YTScript.mk            ← Theos Makefile integration
```

---

## Generator Directives

These macros are **consumed at preprocessing time** by `YTScriptGenerator.py`. They produce Logos/Objective-C code in the `.processed.xm` output. At compile time, they expand to nothing.

---

### `YT_PAGE(@"PageName")`

**Declares a settings page.** This creates a new section in YouTube's Settings that users can tap to access your tweak's controls.

```objc
YT_PAGE(@"YouHideUserInterface");
```

- **PageName** — The name displayed in YouTube Settings.
- Must be called **before** any toggles, sliders, or menus.
- You can have **one page per tweak**.

---

### `YT_ICON(@"iconName")`

**Sets a custom SF Symbol icon** for your settings page row.

```objc
YT_ICON(@"eye.slash");
```

- **iconName** — Any valid [SF Symbols](https://developer.apple.com/sf-symbols/) name.
- Must be placed **after** `YT_PAGE`.
- If omitted, the default icon is `eye.slash`.

---

### `YT_TOGGLE(@"Key")` / `YT_TOGGLE(@"Key", DEFAULT)` / `YT_TOGGLE(@"Key", @"Description", DEFAULT)`

**Adds a toggle switch** to the settings page.

**Formats:**

```objc
// Basic — defaults to YES, no description
YT_TOGGLE(@"HideAds");

// With default value — no description
YT_TOGGLE(@"HideAds", NO);

// With description and default value
YT_TOGGLE(@"HideAds", @"Remove all advertisements. App restart required.", YES);

// With description only — defaults to YES
YT_TOGGLE(@"HideAds", @"Remove all advertisements. App restart required.");
```

**Arguments:**

| Argument | Required | Description |
|----------|----------|-------------|
| `@"Key"` | ✅ | The NSUserDefaults key. Also used as the toggle label. |
| `@"Description"` | ❌ | Subtitle text shown below the toggle label. |
| `YES` / `NO` | ❌ | Default value when the user hasn't changed the setting. Defaults to `YES`. |

**Two usage modes:**

#### Mode 1: Classic (with `YT_ON` / `YT_END`)

The toggle controls a **Logos `%group`** that wraps your hooks. The hooks are only initialized if the toggle is enabled.

```objc
YT_TOGGLE(@"HideAds", @"Removes all ads.", YES);

YT_ON(HideAds)

%hook SomeAdClass
- (BOOL)shouldShowAd { return NO; }
%end

YT_END
```

#### Mode 2: Block Toggle (with `YT_END_TOGGLE`)

The toggle generates its **own independent `%group` and `%ctor`**, separate from the classic `YT_ON`/`YT_END` flow. Use this when a toggle has its own set of hooks that should be independently toggleable.

```objc
YT_TOGGLE(@"RemoveWatermark", @"Removes the YouTube watermark.", YES);
%hook YTWatermarkView
- (void)setHidden:(BOOL)hidden { %orig(YES); }
%end
YT_END_TOGGLE
```

---

### `YT_END_TOGGLE`

**Closes a block toggle** opened by `YT_TOGGLE`. See Mode 2 above.

- Must have a matching `YT_TOGGLE(...)` before it.
- Generates a `%ctor` that conditionally calls `%init` based on the toggle's current value.

---

### `YT_SLIDER(@"Key", min, max, default)` / `YT_SLIDER(@"Key", min, max, default, @"Description")`

**Adds a slider control** to the settings page. When tapped, shows an alert with a UISlider.

```objc
// Without description
YT_SLIDER(@"Opacity", 1, 10, 5);

// With description
YT_SLIDER(@"Visibility", 1, 10, 1, @"Set the eye button visibility. 1 = barely visible, 10 = fully visible.");
```

**Arguments:**

| Argument | Required | Description |
|----------|----------|-------------|
| `@"Key"` | ✅ | The NSUserDefaults key. Also used as the slider label. |
| `min` | ✅ | Minimum slider value (integer). |
| `max` | ✅ | Maximum slider value (integer). |
| `default` | ✅ | Default value when the user hasn't changed it. |
| `@"Description"` | ❌ | Subtitle text shown below the slider label. |

**Reading the value at runtime:**

```objc
id val = [[NSUserDefaults standardUserDefaults] objectForKey:@"Visibility"];
float currentVal = val ? [val floatValue] : 1.0; // fallback to default
```

Or using the YTScript macro:

```objc
float currentVal = YT_GET_FLOAT(@"Visibility");
```

---

### `YT_MENU(@"Key", (@[@"Opt1", @"Opt2"]), @"Default")` / `YT_MENU(@"Key", (@[@"Opt1", @"Opt2"]), @"Default", @"Description")`

**Adds a menu picker** to the settings page. When tapped, shows a list of options with checkmarks.

```objc
// Without description
YT_MENU(@"Theme", (@[@"Dark", @"Light", @"OLED"]), @"Dark");

// With description
YT_MENU(@"Theme", (@[@"Dark", @"Light", @"OLED"]), @"Dark", @"Choose the app theme. Restart required.");
```

**Arguments:**

| Argument | Required | Description |
|----------|----------|-------------|
| `@"Key"` | ✅ | The NSUserDefaults key. Also used as the menu label. |
| `(@[@"..."])` | ✅ | Array of option strings wrapped in parentheses. |
| `@"Default"` | ✅ | The default selected option string. |
| `@"Description"` | ❌ | Subtitle text shown below the menu label. |

**Reading the value at runtime:**

```objc
NSString *theme = YT_GET_STRING(@"Theme") ?: @"Dark";
```

---

### `YT_SECTION(@"SectionName")` *(placeholder — not yet implemented in generator)*

**Declares a section header** within the settings page. Reserved for future use.

```objc
YT_SECTION(@"Appearance");
```

---

### `YT_BUTTON(@"ButtonName")` *(placeholder — not yet implemented in generator)*

**Declares a tappable button** in the settings page. Reserved for future use.

```objc
YT_BUTTON(@"Reset Settings");
```

---

### `YT_ON(GroupName)` / `YT_END`

**Classic Logos group control.** Wraps hooks in a `%group` that is conditionally initialized based on a toggle's value.

```objc
YT_TOGGLE(@"MyFeature", YES);

YT_ON(MyFeature)

%hook SomeClass
- (void)someMethod { %orig; }
%end

YT_END
```

- `YT_ON(GroupName)` generates `%group GroupName`
- `YT_END` generates `%end` and a `%ctor` that calls `%init(GroupName)` only if the toggle key is enabled.
- The `GroupName` must match the key of a previously declared `YT_TOGGLE`.

---

## Runtime Storage Macros

These macros provide **direct inline access** to `NSUserDefaults`. No wrapper classes needed. Use them anywhere in your tweak code.

---

### Boolean

```objc
// Read
BOOL isEnabled = YT_GET_BOOL(@"MyToggle");

// Write
YT_SET_BOOL(@"MyToggle", YES);
```

### Float

```objc
// Read
float opacity = YT_GET_FLOAT(@"Opacity");

// Write
YT_SET_FLOAT(@"Opacity", 0.5);
```

### String

```objc
// Read
NSString *theme = YT_GET_STRING(@"Theme");

// Write
YT_SET_STRING(@"Theme", @"Dark");
```

### Object (generic)

```objc
// Read
id value = YT_GET_OBJECT(@"SomeKey");

// Write
YT_SET_OBJECT(@"SomeKey", @{@"key": @"value"});
```

### Synchronize

```objc
// Force save to disk
YT_SYNC;
```

> **Note:** `synchronize` is rarely needed on modern iOS, but is included for compatibility.

---

## Condition Macros

Shorthand macros for checking toggle states and conditional logic.

---

### `YT_ENABLED(key)` / `YT_DISABLED(key)`

Check if a toggle is on or off:

```objc
if (YT_ENABLED(@"DarkMode")) {
    // apply dark mode
}

if (YT_DISABLED(@"Ads")) {
    // ads are turned off
}
```

---

### `YT_RETURN_IF_DISABLED(key)`

Early return from a method if the toggle is off:

```objc
- (void)viewDidLoad {
    YT_RETURN_IF_DISABLED(@"MyFeature");
    %orig;
    // ... custom code only runs if MyFeature is enabled
}
```

---

### `YT_RETURN_VALUE_IF_DISABLED(key, value)`

Early return **with a value** if the toggle is off:

```objc
- (BOOL)shouldShowAd {
    YT_RETURN_VALUE_IF_DISABLED(@"BlockAds", NO);
    return %orig;
}
```

---

### `YT_IF(key)` / `YT_ELSE` / `YT_COND_END`

Block-scoped conditional execution:

```objc
YT_IF(@"DarkMode")
    self.view.backgroundColor = [UIColor blackColor];
YT_ELSE
    self.view.backgroundColor = [UIColor whiteColor];
YT_COND_END;
```

---

### `YT_RUN_IF(key, block)`

Execute a block only if the toggle is enabled:

```objc
YT_RUN_IF(@"Analytics", ^{
    [self sendAnalyticsEvent];
});
```

---

## Debug & Logging

### `YT_LOG(message)` / `YT_DEBUG_LOG(message)`

Log messages prefixed with `[YTScript]`:

```objc
YT_LOG(@"Tweak loaded successfully");
YT_LOG([NSString stringWithFormat:@"Opacity: %f", opacity]);
```

Output in Console:
```
[YTScript] Tweak loaded successfully
[YTScript] Opacity: 0.500000
```

---

## Version

```objc
NSLog(@"YTScript version: %@", YTSCRIPT_VERSION);
// Output: YTScript version: 2.0
```

---

## Complete Example

```objc
#import <UIKit/UIKit.h>
#import <YTScript/YTScriptRuntime.h>

// === Settings Declaration ===
YT_PAGE(@"MyTweak");
YT_ICON(@"sparkles");
YT_TOGGLE(@"MyTweak", @"Master switch for all features. Restart required.", YES);
YT_TOGGLE(@"HideAds", @"Remove all advertisements.", YES);
YT_SLIDER(@"UIScale", 1, 10, 5, @"Scale the UI elements. 1 = small, 10 = large.");
YT_MENU(@"Theme", (@[@"Default", @"Dark", @"OLED"]), @"Default", @"Choose the app appearance.");

// === Classic Toggle Group ===
YT_ON(MyTweak)

%hook YTSomeClass
- (void)viewDidLoad {
    %orig;
    YT_LOG(@"MyTweak hook active");
}
%end

YT_END

// === Block Toggle (independent) ===
YT_TOGGLE(@"HideAds", @"Remove all advertisements.", YES);
%hook YTAdClass
- (BOOL)shouldShowAd {
    return NO;
}
%end
YT_END_TOGGLE
```
