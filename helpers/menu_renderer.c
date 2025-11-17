// Menu Renderer - High-performance C-based menu rendering with SketchyBar API
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <time.h>

#define MAX_MENU_ITEMS 100
#define MAX_DEPTH 5
#define MAX_NAME_LEN 128
#define MAX_CMD_LEN 512

typedef enum {
    MENU_ITEM,
    MENU_HEADER,
    MENU_SEPARATOR,
    MENU_SUBMENU
} MenuItemType;

typedef struct MenuItem {
    char name[MAX_NAME_LEN];
    char label[MAX_NAME_LEN];
    char icon[16];
    char action[MAX_CMD_LEN];
    char shortcut[32];
    MenuItemType type;
    int submenu_count;
    struct MenuItem* submenu_items;
} MenuItem;

typedef struct {
    MenuItem items[MAX_MENU_ITEMS];
    int count;
    char popup_name[MAX_NAME_LEN];
} Menu;

// Load menu from JSON file
Menu* load_menu_json(const char* filename) {
    char path[512];
    snprintf(path, sizeof(path), "%s/.config/sketchybar/data/%s.json",
             getenv("HOME"), filename);

    FILE* f = fopen(path, "r");
    if (!f) return NULL;

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    char* buffer = malloc(size + 1);
    fread(buffer, 1, size, f);
    buffer[size] = '\0';
    fclose(f);

    Menu* menu = (Menu*)calloc(1, sizeof(Menu));

    // Simple JSON parsing
    char* ptr = buffer;
    while (*ptr && menu->count < MAX_MENU_ITEMS) {
        // Find next menu item
        char* item_start = strstr(ptr, "{");
        if (!item_start) break;

        char* item_end = strchr(item_start, '}');
        if (!item_end) break;

        MenuItem* item = &menu->items[menu->count];

        // Parse type
        char* type_ptr = strstr(item_start, "\"type\"");
        if (type_ptr && type_ptr < item_end) {
            char* val = strchr(type_ptr, ':');
            if (val) {
                if (strstr(val, "header")) item->type = MENU_HEADER;
                else if (strstr(val, "separator")) item->type = MENU_SEPARATOR;
                else if (strstr(val, "submenu")) item->type = MENU_SUBMENU;
                else item->type = MENU_ITEM;
            }
        }

        // Parse name
        char* name_ptr = strstr(item_start, "\"name\"");
        if (name_ptr && name_ptr < item_end) {
            char* quote1 = strchr(name_ptr + 6, '\"');
            if (quote1) {
                char* quote2 = strchr(quote1 + 1, '\"');
                if (quote2) {
                    int len = quote2 - quote1 - 1;
                    if (len > 0 && len < MAX_NAME_LEN) {
                        strncpy(item->name, quote1 + 1, len);
                        item->name[len] = '\0';
                    }
                }
            }
        }

        // Parse label
        char* label_ptr = strstr(item_start, "\"label\"");
        if (label_ptr && label_ptr < item_end) {
            char* quote1 = strchr(label_ptr + 7, '\"');
            if (quote1) {
                char* quote2 = strchr(quote1 + 1, '\"');
                if (quote2) {
                    int len = quote2 - quote1 - 1;
                    if (len > 0 && len < MAX_NAME_LEN) {
                        strncpy(item->label, quote1 + 1, len);
                        item->label[len] = '\0';
                    }
                }
            }
        }

        // Parse icon
        char* icon_ptr = strstr(item_start, "\"icon\"");
        if (icon_ptr && icon_ptr < item_end) {
            char* quote1 = strchr(icon_ptr + 6, '\"');
            if (quote1) {
                char* quote2 = strchr(quote1 + 1, '\"');
                if (quote2) {
                    int len = quote2 - quote1 - 1;
                    if (len > 0 && len < 16) {
                        strncpy(item->icon, quote1 + 1, len);
                        item->icon[len] = '\0';
                    }
                }
            }
        }

        // Parse action
        char* action_ptr = strstr(item_start, "\"action\"");
        if (action_ptr && action_ptr < item_end) {
            char* quote1 = strchr(action_ptr + 8, '\"');
            if (quote1) {
                char* quote2 = strchr(quote1 + 1, '\"');
                if (quote2) {
                    int len = quote2 - quote1 - 1;
                    if (len > 0 && len < MAX_CMD_LEN) {
                        strncpy(item->action, quote1 + 1, len);
                        item->action[len] = '\0';
                    }
                }
            }
        }

        // Parse shortcut
        char* shortcut_ptr = strstr(item_start, "\"shortcut\"");
        if (shortcut_ptr && shortcut_ptr < item_end) {
            char* quote1 = strchr(shortcut_ptr + 10, '\"');
            if (quote1) {
                char* quote2 = strchr(quote1 + 1, '\"');
                if (quote2) {
                    int len = quote2 - quote1 - 1;
                    if (len > 0 && len < 32) {
                        strncpy(item->shortcut, quote1 + 1, len);
                        item->shortcut[len] = '\0';
                    }
                }
            }
        }

        menu->count++;
        ptr = item_end + 1;
    }

    free(buffer);
    return menu;
}

// Render menu item to SketchyBar
void render_menu_item(MenuItem* item, const char* popup_name, int index) {
    char cmd[2048];
    char item_name[256];

    snprintf(item_name, sizeof(item_name), "%s.item%d", popup_name, index);

    switch (item->type) {
        case MENU_HEADER:
            snprintf(cmd, sizeof(cmd),
                    "sketchybar --add item %s popup.%s "
                    "--set %s icon='' label='%s' "
                    "label.font='SF Pro:Bold:11.0' "
                    "label.color=0xFF999999 "
                    "background.drawing=off "
                    "icon.drawing=off",
                    item_name, popup_name,
                    item_name, item->label);
            break;

        case MENU_SEPARATOR:
            snprintf(cmd, sizeof(cmd),
                    "sketchybar --add item %s popup.%s "
                    "--set %s icon='' label='───────────────' "
                    "label.font='SF Pro:Regular:10.0' "
                    "label.color=0xFF666666 "
                    "background.drawing=off "
                    "icon.drawing=off",
                    item_name, popup_name,
                    item_name);
            break;

        case MENU_SUBMENU:
            snprintf(cmd, sizeof(cmd),
                    "sketchybar --add item %s popup.%s "
                    "--set %s icon='%s' label='%s  󰅂' "
                    "icon.padding_left=4 icon.padding_right=6 "
                    "label.padding_left=6 label.padding_right=6 "
                    "background.corner_radius=4 background.height=20 "
                    "background.drawing=off "
                    "script='%s/.config/sketchybar/bin/submenu_hover'",
                    item_name, popup_name,
                    item_name, item->icon, item->label,
                    getenv("HOME"));
            break;

        case MENU_ITEM:
        default: {
            char label_with_shortcut[256];
            if (strlen(item->shortcut) > 0) {
                snprintf(label_with_shortcut, sizeof(label_with_shortcut),
                        "%-16s %s", item->label, item->shortcut);
            } else {
                strcpy(label_with_shortcut, item->label);
            }

            // Wrap action with menu_action helper
            char wrapped_action[MAX_CMD_LEN];
            if (strlen(item->action) > 0) {
                snprintf(wrapped_action, sizeof(wrapped_action),
                        "MENU_ACTION_CMD='%s' %s/.config/sketchybar/bin/menu_action '%s' '%s'",
                        item->action, getenv("HOME"), item_name, popup_name);
            } else {
                wrapped_action[0] = '\0';
            }

            snprintf(cmd, sizeof(cmd),
                    "sketchybar --add item %s popup.%s "
                    "--set %s icon='%s' label='%s' "
                    "icon.padding_left=4 icon.padding_right=6 "
                    "label.padding_left=6 label.padding_right=6 "
                    "background.corner_radius=4 background.height=20 "
                    "background.drawing=off "
                    "click_script='%s' "
                    "script='%s/.config/sketchybar/bin/popup_hover'",
                    item_name, popup_name,
                    item_name, item->icon, label_with_shortcut,
                    wrapped_action,
                    getenv("HOME"));
            break;
        }
    }

    system(cmd);
}

// Render submenu
void render_submenu(MenuItem* parent, const char* parent_popup) {
    if (!parent->submenu_items || parent->submenu_count == 0) return;

    char submenu_name[256];
    snprintf(submenu_name, sizeof(submenu_name), "%s.%s", parent_popup, parent->name);

    // Create submenu bracket
    char cmd[512];
    snprintf(cmd, sizeof(cmd),
            "sketchybar --add bracket %s_bracket %s.* "
            "--set %s_bracket background.drawing=on "
            "background.color=0xE021162F "
            "background.corner_radius=8",
            submenu_name, submenu_name, submenu_name);
    system(cmd);

    // Render submenu items
    for (int i = 0; i < parent->submenu_count; i++) {
        render_menu_item(&parent->submenu_items[i], submenu_name, i);
    }
}

// Render entire menu
void render_menu(Menu* menu, const char* popup_name) {
    if (!menu) return;

    strcpy(menu->popup_name, popup_name);

    // Clear existing popup items
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "sketchybar --remove '/popup.%s\\..*/'", popup_name);
    system(cmd);

    // Render all menu items
    for (int i = 0; i < menu->count; i++) {
        render_menu_item(&menu->items[i], popup_name, i);

        // Render submenus if any
        if (menu->items[i].type == MENU_SUBMENU) {
            render_submenu(&menu->items[i], popup_name);
        }
    }
}

// Batch render multiple menus
void batch_render_menus(const char* menu_names[], int count) {
    char batch_cmd[8192] = "sketchybar";

    for (int m = 0; m < count; m++) {
        Menu* menu = load_menu_json(menu_names[m]);
        if (!menu) continue;

        char popup_name[128];
        snprintf(popup_name, sizeof(popup_name), "%s_popup", menu_names[m]);

        for (int i = 0; i < menu->count && strlen(batch_cmd) < 7000; i++) {
            MenuItem* item = &menu->items[i];
            char item_name[256];
            snprintf(item_name, sizeof(item_name), "%s.item%d", popup_name, i);

            char item_cmd[512];
            snprintf(item_cmd, sizeof(item_cmd),
                    " --add item %s popup.%s --set %s icon='%s' label='%s'",
                    item_name, popup_name, item_name, item->icon, item->label);

            strcat(batch_cmd, item_cmd);
        }

        free(menu);
    }

    system(batch_cmd);
}

// Cache rendered menus
void cache_menu(Menu* menu) {
    if (!menu) return;

    char cache_path[512];
    snprintf(cache_path, sizeof(cache_path),
            "/tmp/sketchybar_menu_%s.cache", menu->popup_name);

    FILE* f = fopen(cache_path, "wb");
    if (f) {
        fwrite(menu, sizeof(Menu), 1, f);
        fclose(f);
    }
}

// Load cached menu
Menu* load_cached_menu(const char* popup_name) {
    char cache_path[512];
    snprintf(cache_path, sizeof(cache_path),
            "/tmp/sketchybar_menu_%s.cache", popup_name);

    struct stat st;
    if (stat(cache_path, &st) != 0) return NULL;

    // Check if cache is older than 5 minutes
    time_t now = time(NULL);
    if (now - st.st_mtime > 300) return NULL;

    FILE* f = fopen(cache_path, "rb");
    if (!f) return NULL;

    Menu* menu = (Menu*)malloc(sizeof(Menu));
    fread(menu, sizeof(Menu), 1, f);
    fclose(f);

    return menu;
}

// Main function
int main(int argc, char* argv[]) {
    if (argc < 2) {
        printf("Usage: %s <command> [args]\n", argv[0]);
        printf("Commands:\n");
        printf("  render <menu_file> <popup_name>  - Render menu from JSON\n");
        printf("  batch <menu1> <menu2> ...        - Batch render menus\n");
        printf("  cache <menu_file>                - Cache menu\n");
        printf("  clear <popup_name>               - Clear popup items\n");
        return 1;
    }

    if (strcmp(argv[1], "render") == 0 && argc >= 4) {
        Menu* menu = load_cached_menu(argv[3]);
        if (!menu) {
            menu = load_menu_json(argv[2]);
            if (menu) {
                cache_menu(menu);
            }
        }
        if (menu) {
            render_menu(menu, argv[3]);
            free(menu);
        }
    }
    else if (strcmp(argv[1], "batch") == 0 && argc >= 3) {
        batch_render_menus((const char**)&argv[2], argc - 2);
    }
    else if (strcmp(argv[1], "cache") == 0 && argc >= 3) {
        Menu* menu = load_menu_json(argv[2]);
        if (menu) {
            cache_menu(menu);
            free(menu);
            printf("Menu cached\n");
        }
    }
    else if (strcmp(argv[1], "clear") == 0 && argc >= 3) {
        char cmd[256];
        snprintf(cmd, sizeof(cmd), "sketchybar --remove '/popup.%s\\..*/'", argv[2]);
        system(cmd);
    }

    return 0;
}