#!/usr/bin/env python3

import re
import sys


class YTScriptGenerator:

    def __init__(self):
        self.group_stack = []
        self.pages = {}  # { page_name: [items] }
        self.page_icons = {}  # { page_name: icon_name }
        self.current_page = None
        self.toggle_defaults = {}  # { key: default_value }

    def deterministic_hash(self, string):
        h = 0
        for char in string:
            h = (h * 31 + ord(char)) & 0xFFFFFFFF
        return h

    def sanitize_group_name(self, name):
        clean = re.sub(r'[^A-Za-z0-9_]', '', name)
        if not clean or clean[0].isdigit():
            clean = "YTSGroup_" + str(abs(self.deterministic_hash(name)))
        return clean

    def generate_settings_code(self):
        code = []
        code.append("\n// ========================================== \n")
        code.append("// YTScript Generated Settings Hook Code\n")
        code.append("// ========================================== \n\n")
        
        # Forward declarations
        code.append("""
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <YouTubeHeader/YTIIcon.h>

@interface YTSettingsGroupData : NSObject
@property (nonatomic, readonly, assign) NSUInteger type;
- (NSArray *)orderedCategories;
@end

@interface YTSettingsSectionItemManager : NSObject
- (id)parentResponder;
@end

@interface YTSettingsSectionItem : NSObject
+ (instancetype)itemWithTitle:(NSString *)title accessibilityIdentifier:(NSString *)accessibilityIdentifier detailTextBlock:(NSString *(^)(void))detailTextBlock selectBlock:(BOOL (^)(id, NSUInteger))selectBlock;
+ (instancetype)itemWithTitle:(NSString *)title titleDescription:(NSString *)titleDescription accessibilityIdentifier:(NSString *)accessibilityIdentifier detailTextBlock:(NSString *(^)(void))detailTextBlock selectBlock:(BOOL (^)(id, NSUInteger))selectBlock;
+ (instancetype)switchItemWithTitle:(NSString *)title titleDescription:(NSString *)titleDescription accessibilityIdentifier:(NSString *)accessibilityIdentifier switchOn:(BOOL)switchOn switchBlock:(BOOL (^)(id, BOOL))switchBlock settingItemId:(int)settingItemId;
+ (instancetype)checkmarkItemWithTitle:(NSString *)title selectBlock:(BOOL (^)(id, NSUInteger))selectBlock;
@end

@interface YTSettingsViewController : UIViewController
- (NSMutableDictionary *)settingsSectionControllers;
- (void)setSectionItems:(NSMutableArray *)sectionItems forCategory:(NSInteger)category title:(NSString *)title titleDescription:(NSString *)titleDescription headerHidden:(BOOL)headerHidden;
- (void)setSectionItems:(NSMutableArray *)sectionItems forCategory:(NSInteger)category title:(NSString *)title icon:(id)icon titleDescription:(NSString *)titleDescription headerHidden:(BOOL)headerHidden;
- (void)pushViewController:(UIViewController *)viewController;
- (void)reloadData;
@end

@interface YTSettingsPickerViewController : UIViewController
- (instancetype)initWithNavTitle:(NSString *)navTitle pickerSectionTitle:(NSString *)pickerSectionTitle rows:(NSArray *)rows selectedItemIndex:(NSUInteger)selectedItemIndex parentResponder:(id)parentResponder;
@end
""")

        # Generate category IDs
        page_ids = {}
        for page_name in self.pages:
            cat_id = (self.deterministic_hash(page_name) % 50000) + 40000
            page_ids[page_name] = cat_id
            
        # Hook YTSettingsGroupData
        code.append("\n%hook YTSettingsGroupData\n")
        code.append("- (NSArray *)orderedCategories {\n")
        code.append("    NSArray *categories = %orig;\n")
        code.append("    NSMutableArray *mutableCategories = categories ? [categories mutableCopy] : [NSMutableArray array];\n")
        code.append("    BOOL hasTweaks = class_getClassMethod(objc_getClass(\"YTSettingsGroupData\"), @selector(tweaks)) != nil;\n")
        
        custom_ids_str = ", ".join([f"@({cat_id})" for cat_id in page_ids.values()])
        code.append(f"    NSArray *customCatIds = @[{custom_ids_str}];\n")
        
        code.append("    if (hasTweaks) {\n")
        code.append("        if (self.type == 'psyt') {\n")
        code.append("            for (NSNumber *catId in customCatIds) {\n")
        code.append("                if (![mutableCategories containsObject:catId]) {\n")
        code.append("                    [mutableCategories addObject:catId];\n")
        code.append("                }\n")
        code.append("            }\n")
        code.append("        }\n")
        code.append("    } else {\n")
        code.append("        if (self.type == 1) {\n")
        code.append("            for (NSNumber *catId in customCatIds) {\n")
        code.append("                if (![mutableCategories containsObject:catId]) {\n")
        code.append("                    [mutableCategories insertObject:catId atIndex:0];\n")
        code.append("                }\n")
        code.append("            }\n")
        code.append("        }\n")
        code.append("    }\n")
        code.append("    return [mutableCategories copy];\n")
        code.append("}\n")
        code.append("%end\n\n")

        # Hook YTAppSettingsPresentationData
        code.append("\n%hook YTAppSettingsPresentationData\n")
        code.append("+ (NSArray *)settingsCategoryOrder {\n")
        code.append("    NSArray *order = %orig;\n")
        code.append("    NSMutableArray *mutableOrder = [order mutableCopy];\n")
        code.append("    NSUInteger insertIndex = [order indexOfObject:@(1)];\n")
        
        for page_name, cat_id in page_ids.items():
            code.append(f"    if (insertIndex != NSNotFound) {{\n")
            code.append(f"        [mutableOrder insertObject:@({cat_id}) atIndex:insertIndex + 1];\n")
            code.append(f"    }} else {{\n")
            code.append(f"        [mutableOrder addObject:@({cat_id})];\n")
            code.append(f"    }}\n")
            
        code.append("    return [mutableOrder copy];\n")
        code.append("}\n")
        code.append("%end\n\n")
        
        # Hook YTSettingsSectionItemManager
        code.append("%hook YTSettingsSectionItemManager\n")
        code.append("- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry {\n")
        
        for page_name, cat_id in page_ids.items():
            items = self.pages[page_name]
            icon_name = self.page_icons.get(page_name, "eye.slash")
            code.append(f"    if (category == {cat_id}) {{\n")
            code.append("        YTSettingsViewController *settingsViewController = [self valueForKey:@\"_settingsViewControllerDelegate\"];\n")
            code.append("        NSMutableArray *sectionItems = [NSMutableArray array];\n")
            code.append("        Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);\n")
            
            for item in items:
                t = item["type"]
                key = item["key"]
                
                if t == "toggle":
                    default_val = "YES" if item["default"] == "YES" else "NO"
                    desc_code = f'@"{item["desc"]}"' if item.get("desc") else "nil"
                    code.append(f"""
        [sectionItems addObject:[YTSettingsSectionItemClass switchItemWithTitle:@"{key}"
            titleDescription:{desc_code}
            accessibilityIdentifier:nil
            switchOn:[[NSUserDefaults standardUserDefaults] objectForKey:@"{key}"] ? [[NSUserDefaults standardUserDefaults] boolForKey:@"{key}"] : {default_val}
            switchBlock:^BOOL(id cell, BOOL enabled) {{
                [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"{key}"];
                [[NSUserDefaults standardUserDefaults] synchronize];
                return YES;
            }}
            settingItemId:0]];
""")
                elif t == "slider":
                    min_val = item["min"]
                    max_val = item["max"]
                    default_val = item["default"]
                    desc_code = f'@"{item["desc"]}"' if item.get("desc") else "nil"
                    code.append(f"""
        [sectionItems addObject:[YTSettingsSectionItemClass itemWithTitle:@"{key}"
            titleDescription:{desc_code}
            accessibilityIdentifier:nil
            detailTextBlock:^NSString *() {{
                id val = [[NSUserDefaults standardUserDefaults] objectForKey:@"{key}"];
                float currentVal = val ? [val floatValue] : {default_val};
                return [NSString stringWithFormat:@"%.0f", currentVal];
            }}
            selectBlock:^BOOL(id cell, NSUInteger arg) {{
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"{key}"
                                                                                message:@"\\n\\n\\n"
                                                                         preferredStyle:UIAlertControllerStyleAlert];
                
                UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(24, 60, 222, 40)];
                slider.minimumValue = {min_val};
                slider.maximumValue = {max_val};
                id val = [[NSUserDefaults standardUserDefaults] objectForKey:@"{key}"];
                slider.value = val ? [val floatValue] : {default_val};
                
                [alert.view addSubview:slider];
                
                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"Save"
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^(UIAlertAction *action) {{
                                                                     [[NSUserDefaults standardUserDefaults] setFloat:slider.value forKey:@"{key}"];
                                                                     [[NSUserDefaults standardUserDefaults] synchronize];
                                                                 }}];
                [alert addAction:okAction];
                
                UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel"
                                                                       style:UIAlertActionStyleCancel
                                                                     handler:nil];
                [alert addAction:cancelAction];
                
                YTSettingsViewController *settingsVC = [self valueForKey:@"_settingsViewControllerDelegate"];
                [settingsVC presentViewController:alert animated:YES completion:nil];
                return YES;
            }}]];
""")
                elif t == "menu":
                    options = item["options"]
                    default_val = item["default"]
                    options_objc = ", ".join([f'@"{opt}"' for opt in options])
                    desc_code = f'@"{item["desc"]}"' if item.get("desc") else "nil"
                    code.append(f"""
        [sectionItems addObject:[YTSettingsSectionItemClass itemWithTitle:@"{key}"
            titleDescription:{desc_code}
            accessibilityIdentifier:nil
            detailTextBlock:^NSString *() {{
                NSString *val = [[NSUserDefaults standardUserDefaults] stringForKey:@"{key}"];
                return val ?: @"{default_val}";
            }}
            selectBlock:^BOOL(id cell, NSUInteger arg) {{
                NSMutableArray *rows = [NSMutableArray array];
                NSArray *options = @[{options_objc}];
                NSString *currentValue = [[NSUserDefaults standardUserDefaults] stringForKey:@"{key}"] ?: @"{default_val}";
                NSUInteger selectedIndex = [options indexOfObject:currentValue];
                
                for (NSString *option in options) {{
                    YTSettingsSectionItem *optionItem = [%c(YTSettingsSectionItem) checkmarkItemWithTitle:option selectBlock:^BOOL(id c, NSUInteger index) {{
                        [[NSUserDefaults standardUserDefaults] setObject:option forKey:@"{key}"];
                        [[NSUserDefaults standardUserDefaults] synchronize];
                        return YES;
                    }}];
                    [rows addObject:optionItem];
                }}
                
                YTSettingsViewController *settingsVC = [self valueForKey:@"_settingsViewControllerDelegate"];
                YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"{key}"
                                                                                                  pickerSectionTitle:nil
                                                                                                                rows:rows
                                                                                                   selectedItemIndex:selectedIndex
                                                                                                     parentResponder:[self parentResponder]];
                [settingsVC pushViewController:picker];
                return YES;
            }}]];
""")
            
            code.append(f"""
        YTIIcon *customIcon = nil;
        if (NSClassFromString(@"YTIIcon")) {{
            customIcon = [%c(YTIIcon) new];
            if (customIcon) {{
                customIcon.iconType = (YTIcon)44;
                objc_setAssociatedObject(customIcon, "YHUICustomIcon", @"{icon_name}", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }}
        }}
        BOOL isNew = [settingsViewController respondsToSelector:@selector(setSectionItems:forCategory:title:icon:titleDescription:headerHidden:)];
        if (isNew) {{
            [settingsViewController setSectionItems:sectionItems forCategory:{cat_id} title:@"{page_name}" icon:customIcon titleDescription:nil headerHidden:NO];
        }} else {{
            [settingsViewController setSectionItems:sectionItems forCategory:{cat_id} title:@"{page_name}" titleDescription:nil headerHidden:NO];
        }}
        return;
    }}
""")

        code.append("    %orig;\n")
        code.append("}\n")
        code.append("%end\n\n")

        # Hook YTIIcon to dynamically load custom icon image
        code.append("%hook YTIIcon\n")
        code.append("- (UIImage *)iconImageWithColor:(UIColor *)color {\n")
        code.append("    NSString *tag = objc_getAssociatedObject(self, \"YHUICustomIcon\");\n")
        code.append("    if (tag) {\n")
        code.append("        if (@available(iOS 13.0, *)) {\n")
        code.append("            UIImage *img = [UIImage systemImageNamed:tag];\n")
        code.append("            if (!img) img = [UIImage systemImageNamed:@\"eye.slash\"];\n")
        code.append("            if (color) img = [img imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];\n")
        code.append("            return img;\n")
        code.append("        }\n")
        code.append("    }\n")
        code.append("    return %orig;\n")
        code.append("}\n")
        
        code.append("- (UIImage *)iconImageWithSelected:(BOOL)selected {\n")
        code.append("    NSString *tag = objc_getAssociatedObject(self, \"YHUICustomIcon\");\n")
        code.append("    if (tag) {\n")
        code.append("        if (@available(iOS 13.0, *)) {\n")
        code.append("            NSString *fillTag = [NSString stringWithFormat:@\"%@.fill\", tag];\n")
        code.append("            UIImage *img = selected ? [UIImage systemImageNamed:fillTag] : [UIImage systemImageNamed:tag];\n")
        code.append("            if (!img) img = [UIImage systemImageNamed:tag];\n")
        code.append("            if (!img) img = [UIImage systemImageNamed:@\"eye.slash\"];\n")
        code.append("            return img;\n")
        code.append("        }\n")
        code.append("    }\n")
        code.append("    return %orig;\n")
        code.append("}\n")
        code.append("%end\n")

        code.append("\n%ctor {\n")
        code.append("    %init;\n")
        code.append("}\n")
        
        return "".join(code)

    def process(self, lines):
        cleaned_lines = []
        
        # Count YT_END_TOGGLE count to identify block toggles
        end_toggle_count = sum(1 for l in lines if l.strip() == "YT_END_TOGGLE")
        
        def clean_str(s):
            s = s.strip()
            if s.startswith('@"'): s = s[2:]
            elif s.startswith('"'): s = s[1:]
            if s.endswith('"'): s = s[:-1]
            return s.strip()

        # Pass 1: Parse macros and extract settings items
        for line in lines:
            stripped = line.strip()
            
            # YT_PAGE(@"PageName")
            page_match = re.match(r'YT_PAGE\s*\(\s*@?"(.*?)"\s*\)\s*;?', stripped)
            if page_match:
                page_name = page_match.group(1)
                self.current_page = page_name
                if page_name not in self.pages:
                    self.pages[page_name] = []
                cleaned_lines.append("\n")
                continue

            # YT_ICON(@"iconName") or YT_ICON("iconName")
            icon_match = re.match(r'YT_ICON\s*\(\s*@?"(.*?)"\s*\)\s*;?', stripped)
            if icon_match:
                icon_name = icon_match.group(1)
                if self.current_page:
                    self.page_icons[self.current_page] = icon_name
                cleaned_lines.append("\n")
                continue
                
            # YT_TOGGLE(...)
            if stripped.startswith("YT_TOGGLE"):
                m = re.match(r'YT_TOGGLE\s*\((.*?)\)\s*;?$', stripped)
                if m:
                    args_str = m.group(1).strip()
                    # Split args by comma respecting quotes
                    args = [a.strip() for a in re.split(r',\s*(?=(?:[^"]*"[^"]*")*[^"]*$)', args_str) if a.strip()]
                    
                    key = ""
                    desc = ""
                    default_val = "YES"
                    
                    if len(args) >= 1:
                        key = clean_str(args[0])
                    if len(args) >= 2:
                        second = args[1].strip()
                        if second in ["YES", "NO"]:
                            default_val = second
                        else:
                            desc = clean_str(second)
                    if len(args) >= 3:
                        third = args[2].strip()
                        if third in ["YES", "NO"]:
                            default_val = third

                    if key:
                        self.toggle_defaults[key] = default_val
                        if self.current_page:
                            self.pages[self.current_page].append({
                                "type": "toggle",
                                "key": key,
                                "desc": desc,
                                "default": default_val
                            })
                    
                    # If this is part of a block toggle (YT_END_TOGGLE exists in file), keep line for Pass 2
                    if end_toggle_count > 0:
                        cleaned_lines.append(line)
                    else:
                        cleaned_lines.append("\n")
                    continue
                
            # YT_SLIDER(...)
            if stripped.startswith("YT_SLIDER"):
                m = re.match(r'YT_SLIDER\s*\((.*?)\)\s*;?$', stripped)
                if m:
                    args_str = m.group(1).strip()
                    args = [a.strip() for a in re.split(r',\s*(?=(?:[^"]*"[^"]*")*[^"]*$)', args_str) if a.strip()]
                    
                    key = ""
                    min_val = "0"
                    max_val = "10"
                    default_val = "5"
                    desc = ""
                    
                    if len(args) >= 1:
                        key = clean_str(args[0])
                    if len(args) >= 2:
                        min_val = args[1].strip()
                    if len(args) >= 3:
                        max_val = args[2].strip()
                    if len(args) >= 4:
                        default_val = args[3].strip()
                    if len(args) >= 5:
                        desc = clean_str(args[4])
                        
                    if key:
                        if self.current_page:
                            self.pages[self.current_page].append({
                                "type": "slider",
                                "key": key,
                                "min": min_val,
                                "max": max_val,
                                "default": default_val,
                                "desc": desc
                            })
                    cleaned_lines.append("\n")
                    continue
                
            # YT_MENU(...)
            if stripped.startswith("YT_MENU"):
                m = re.match(r'YT_MENU\s*\((.*?)\)\s*;?$', stripped)
                if m:
                    args_str = m.group(1).strip()
                    args = [a.strip() for a in re.split(r',\s*(?=(?:[^"]*"[^"]*")*[^"]*$)', args_str) if a.strip()]
                    
                    key = ""
                    options_str = ""
                    default_val = ""
                    desc = ""
                    
                    if len(args) >= 1:
                        key = clean_str(args[0])
                    if len(args) >= 2:
                        options_str = args[1].strip()
                        if options_str.startswith("("):
                            options_str = options_str[1:]
                        if options_str.endswith(")"):
                            options_str = options_str[:-1]
                        options_str = options_str.strip()
                    if len(args) >= 3:
                        default_val = clean_str(args[2])
                    if len(args) >= 4:
                        desc = clean_str(args[3])
                        
                    options = re.findall(r'@"(.*?)"', options_str)
                    if not options:
                        options = re.findall(r'"(.*?)"', options_str)
                        
                    if key and options:
                        if self.current_page:
                            self.pages[self.current_page].append({
                                "type": "menu",
                                "key": key,
                                "options": options,
                                "default": default_val,
                                "desc": desc
                            })
                    cleaned_lines.append("\n")
                    continue
                
            cleaned_lines.append(line)

        # Pass 2: Process Logos groups & block toggles
        output = []
        i = 0
        while i < len(cleaned_lines):
            line = cleaned_lines[i]
            stripped = line.strip()
            
            # YT_TOGGLE(...) block start
            if stripped.startswith("YT_TOGGLE"):
                m = re.match(r'YT_TOGGLE\s*\((.*?)\)', stripped)
                if m:
                    args_str = m.group(1).strip()
                    args = [a.strip() for a in re.split(r',\s*(?=(?:[^"]*"[^"]*")*[^"]*$)', args_str) if a.strip()]
                    if args:
                        key = clean_str(args[0])
                        group_name = self.sanitize_group_name(key)
                        self.group_stack.append((group_name, key))
                        output.append(f"%group {group_name}\n")
                        i += 1
                        continue

            # YT_END_TOGGLE block end
            if stripped == "YT_END_TOGGLE":
                if not self.group_stack:
                    raise RuntimeError("YTScript Error: Found YT_END_TOGGLE without a matching YT_TOGGLE().")
                group_name, key = self.group_stack.pop()
                default_val = self.toggle_defaults.get(key, "YES")
                output.append("%end\n\n")
                output.append(
f"""%ctor {{
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:@"{key}"];
    BOOL enabled = val ? [val boolValue] : {default_val};
    if (enabled) {{
        %init({group_name});
    }}
}}

"""
)
                i += 1
                continue

            # YT_ON(GroupName) classic
            match = re.match(r'YT_ON\s*\(\s*([A-Za-z0-9_]+)\s*\)', stripped)
            if match:
                group = match.group(1)
                self.group_stack.append((group, group))
                output.append("%group " + group + "\n")
                i += 1
                continue
                
            # YT_END classic
            if stripped == "YT_END":
                if not self.group_stack:
                    raise RuntimeError("YTScript Error: Found YT_END without a matching YT_ON().")
                output.append("%end\n\n")
                group_name, key = self.group_stack.pop()
                default_val = self.toggle_defaults.get(key, "YES")
                output.append(
f"""%ctor {{
    id val = [[NSUserDefaults standardUserDefaults] objectForKey:@"{key}"];
    BOOL enabled = val ? [val boolValue] : {default_val};
    if (enabled) {{
        %init({group_name});
    }}
}}

"""
)
                i += 1
                continue
                
            output.append(line)
            i += 1
            
        if self.group_stack:
            unclosed = ", ".join([pair[1] for pair in self.group_stack])
            raise RuntimeError("YTScript Error: Missing YT_END or YT_END_TOGGLE for: " + unclosed)
            
        if self.pages:
            output.append(self.generate_settings_code())
            
        return output


def main():

    if len(sys.argv) != 3:

        print(
            "Usage: YTScriptGenerator.py input.xm output.xm"
        )

        return

    input_file = sys.argv[1]
    output_file = sys.argv[2]

    with open(
        input_file,
        "r",
        encoding="utf-8"
    ) as f:

        data = f.readlines()

    generator = YTScriptGenerator()

    result = generator.process(data)

    with open(
        output_file,
        "w",
        encoding="utf-8"
    ) as f:

        f.writelines(result)

    print(
        "[YTScript] Generated:",
        output_file
    )


if __name__ == "__main__":
    main()
