//
//  YTScriptRuntime.h
//  YTScript Runtime v2.0
//
//  Single-header runtime for YTScript tweaks.
//  No .m files required — everything is inline.
//
//  Usage: #import <YTScript/YTScriptRuntime.h>
//

#ifndef YTSCRIPTRUNTIME_H
#define YTSCRIPTRUNTIME_H

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>


// =====================================================================
//  SECTION 1: Generator Directives
// =====================================================================
//
//  These macros are detected and processed by YTScriptGenerator.py.
//  They are consumed at preprocessing time and produce Logos code
//  in the .processed.xm output. At compile time they expand to nothing.
//

// -- Page & Icon --
#define YT_PAGE(name)
#define YT_ICON(...)

// -- Settings Controls --
#define YT_TOGGLE(...)
#define YT_END_TOGGLE
#define YT_SLIDER(...)
#define YT_MENU(...)
#define YT_SECTION(name)
#define YT_BUTTON(name)

// -- Logos Group Control (Classic) --
#define YT_ON(group)
#define YT_END


// =====================================================================
//  SECTION 2: NSUserDefaults Storage (Inline)
// =====================================================================
//
//  Direct access to NSUserDefaults without wrapper classes.
//  Use these to read/write tweak settings at runtime.
//

// -- Boolean --
#define YT_GET_BOOL(key) \
    [[NSUserDefaults standardUserDefaults] boolForKey:(key)]

#define YT_SET_BOOL(key, value) \
    [[NSUserDefaults standardUserDefaults] setBool:(value) forKey:(key)]

// -- Float --
#define YT_GET_FLOAT(key) \
    [[NSUserDefaults standardUserDefaults] floatForKey:(key)]

#define YT_SET_FLOAT(key, value) \
    [[NSUserDefaults standardUserDefaults] setFloat:(value) forKey:(key)]

// -- String --
#define YT_GET_STRING(key) \
    [[NSUserDefaults standardUserDefaults] stringForKey:(key)]

#define YT_SET_STRING(key, value) \
    [[NSUserDefaults standardUserDefaults] setObject:(value) forKey:(key)]

// -- Object (generic) --
#define YT_GET_OBJECT(key) \
    [[NSUserDefaults standardUserDefaults] objectForKey:(key)]

#define YT_SET_OBJECT(key, value) \
    [[NSUserDefaults standardUserDefaults] setObject:(value) forKey:(key)]

// -- Synchronize --
#define YT_SYNC \
    [[NSUserDefaults standardUserDefaults] synchronize]


// =====================================================================
//  SECTION 3: Conditions
// =====================================================================
//
//  Shorthand macros for checking toggle state and early returns.
//

// -- Check state --
#define YT_ENABLED(key)    YT_GET_BOOL(key)
#define YT_DISABLED(key)   (!YT_GET_BOOL(key))

// -- Early return --
#define YT_RETURN_IF_DISABLED(key) \
    if (YT_DISABLED(key)) { return; }

#define YT_RETURN_VALUE_IF_DISABLED(key, val) \
    if (YT_DISABLED(key)) { return (val); }

// -- Conditional block --
#define YT_IF(key) \
    do { if (YT_ENABLED(key)) {

#define YT_ELSE \
    } else {

#define YT_COND_END \
    } } while(0)

// -- Execute block if enabled --
#define YT_RUN_IF(key, block) \
    do { if (YT_ENABLED(key)) { block(); } } while(0)


// =====================================================================
//  SECTION 4: Debug & Logging
// =====================================================================

#define YT_LOG(msg) \
    NSLog(@"[YTScript] %@", (msg))

#define YT_DEBUG_LOG(msg) \
    NSLog(@"[YTScript] %@", (msg))


// =====================================================================
//  SECTION 5: Version
// =====================================================================

#define YTSCRIPT_VERSION @"2.0"


#endif