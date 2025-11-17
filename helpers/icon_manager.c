// Icon Manager - Centralized C-based icon management with SketchyBar API
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

#define MAX_ICONS 500
#define MAX_CATEGORIES 30
#define MAX_NAME_LEN 64
#define MAX_GLYPH_LEN 16
#define CACHE_FILE "/tmp/sketchybar_icon_cache.bin"

// Icon structure
typedef struct {
    char name[MAX_NAME_LEN];
    char glyph[MAX_GLYPH_LEN];
    char category[MAX_NAME_LEN];
    uint32_t hash;
} Icon;

// Category structure
typedef struct {
    char name[MAX_NAME_LEN];
    int icon_count;
    int icon_indices[100];
} Category;

// Icon library structure
typedef struct {
    Icon icons[MAX_ICONS];
    Category categories[MAX_CATEGORIES];
    int icon_count;
    int category_count;
    time_t cache_time;
} IconLibrary;

static IconLibrary* library = NULL;

// Built-in icon definitions (Nerd Font glyphs)
static const Icon builtin_icons[] = {
    // System icons
    {"apple", "", "system", 0},
    {"apple_alt", "", "system", 0},
    {"settings", "", "system", 0},
    {"battery", "", "system", 0},
    {"battery_charging", "", "system", 0},
    {"wifi", "󰖩", "system", 0},
    {"wifi_off", "󰖪", "system", 0},
    {"bluetooth", "󰂯", "system", 0},
    {"volume", "", "system", 0},
    {"volume_mute", "󰝟", "system", 0},
    {"brightness", "󰃞", "system", 0},
    {"clock", "", "system", 0},
    {"calendar", "", "system", 0},
    {"notification", "󰂚", "system", 0},
    {"lock", "󰷛", "system", 0},
    {"power", "", "system", 0},

    // Hardware monitoring
    {"cpu", "󰻠", "hardware", 0},
    {"cpu_chip", "󰍛", "hardware", 0},
    {"memory", "󰘚", "hardware", 0},
    {"disk", "󰋊", "hardware", 0},
    {"network", "󰖩", "hardware", 0},
    {"temperature", "󰔄", "hardware", 0},

    // Development
    {"terminal", "", "development", 0},
    {"code", "", "development", 0},
    {"git", "", "development", 0},
    {"github", "", "development", 0},
    {"docker", "", "development", 0},
    {"vscode", "󰨞", "development", 0},
    {"vim", "", "development", 0},
    {"emacs", "", "development", 0},

    // Window management
    {"tile", "󰆾", "window", 0},
    {"stack", "󰓩", "window", 0},
    {"float", "󰒄", "window", 0},
    {"fullscreen", "󰊓", "window", 0},
    {"split_h", "󰤼", "window", 0},
    {"split_v", "󰤻", "window", 0},

    // Apps
    {"finder", "󰀶", "apps", 0},
    {"safari", "󰀹", "apps", 0},
    {"chrome", "", "apps", 0},
    {"firefox", "", "apps", 0},
    {"messages", "󰍦", "apps", 0},
    {"mail", "󰇮", "apps", 0},
    {"music", "", "apps", 0},
    {"photos", "", "apps", 0},

    // Files
    {"folder", "", "files", 0},
    {"folder_open", "", "files", 0},
    {"file", "", "files", 0},
    {"file_code", "", "files", 0},
    {"file_text", "󰈙", "files", 0},
    {"file_image", "", "files", 0},
    {"file_video", "", "files", 0},
    {"file_audio", "", "files", 0},
    {"file_pdf", "", "files", 0},
    {"file_zip", "", "files", 0},

    // Gaming
    {"gamepad", "󰍳", "gaming", 0},
    {"controller", "󰖺", "gaming", 0},
    {"quest", "", "gaming", 0},
    {"triforce", "󰊠", "gaming", 0},
    {"sword", "󰚥", "gaming", 0},
    {"shield", "󰡁", "gaming", 0},

    // Status
    {"success", "", "status", 0},
    {"error", "", "status", 0},
    {"warning", "", "status", 0},
    {"info", "", "status", 0},
    {"loading", "󰔟", "status", 0},
    {"refresh", "󰑐", "status", 0}
};

// Hash function for fast lookups
uint32_t hash_string(const char* str) {
    uint32_t hash = 5381;
    int c;
    while ((c = *str++))
        hash = ((hash << 5) + hash) + c;
    return hash;
}

// Initialize icon library
void init_library() {
    if (library) return;

    library = (IconLibrary*)calloc(1, sizeof(IconLibrary));

    // Load built-in icons
    int num_builtins = sizeof(builtin_icons) / sizeof(Icon);
    for (int i = 0; i < num_builtins && i < MAX_ICONS; i++) {
        library->icons[i] = builtin_icons[i];
        library->icons[i].hash = hash_string(builtin_icons[i].name);

        // Update category
        int cat_idx = -1;
        for (int j = 0; j < library->category_count; j++) {
            if (strcmp(library->categories[j].name, builtin_icons[i].category) == 0) {
                cat_idx = j;
                break;
            }
        }
        if (cat_idx == -1 && library->category_count < MAX_CATEGORIES) {
            cat_idx = library->category_count++;
            strcpy(library->categories[cat_idx].name, builtin_icons[i].category);
            library->categories[cat_idx].icon_count = 0;
        }
        if (cat_idx >= 0) {
            int idx = library->categories[cat_idx].icon_count++;
            library->categories[cat_idx].icon_indices[idx] = i;
        }
    }
    library->icon_count = num_builtins;
}

// Load custom icons from JSON state file
void load_custom_icons() {
    char state_path[512];
    snprintf(state_path, sizeof(state_path), "%s/.config/sketchybar/state.json", getenv("HOME"));

    FILE* f = fopen(state_path, "r");
    if (!f) return;

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    char* buffer = malloc(size + 1);
    fread(buffer, 1, size, f);
    buffer[size] = '\0';
    fclose(f);

    // Simple JSON parsing for icons section
    char* icons_start = strstr(buffer, "\"icons\"");
    if (icons_start) {
        char* brace = strchr(icons_start, '{');
        if (brace) {
            char* end = strchr(brace, '}');
            if (end) {
                char* ptr = brace + 1;
                while (ptr < end) {
                    // Parse "name": "glyph" pairs
                    char* quote1 = strchr(ptr, '\"');
                    if (!quote1 || quote1 >= end) break;
                    char* quote2 = strchr(quote1 + 1, '\"');
                    if (!quote2 || quote2 >= end) break;

                    char name[MAX_NAME_LEN] = {0};
                    strncpy(name, quote1 + 1, quote2 - quote1 - 1);

                    char* colon = strchr(quote2, ':');
                    if (!colon || colon >= end) break;

                    char* quote3 = strchr(colon, '\"');
                    if (!quote3 || quote3 >= end) break;
                    char* quote4 = strchr(quote3 + 1, '\"');
                    if (!quote4 || quote4 >= end) break;

                    char glyph[MAX_GLYPH_LEN] = {0};
                    strncpy(glyph, quote3 + 1, quote4 - quote3 - 1);

                    // Add or update icon
                    if (library->icon_count < MAX_ICONS) {
                        strcpy(library->icons[library->icon_count].name, name);
                        strcpy(library->icons[library->icon_count].glyph, glyph);
                        strcpy(library->icons[library->icon_count].category, "custom");
                        library->icons[library->icon_count].hash = hash_string(name);
                        library->icon_count++;
                    }

                    ptr = quote4 + 1;
                }
            }
        }
    }

    free(buffer);
}

// Get icon by name
const char* get_icon(const char* name, const char* fallback) {
    if (!library) {
        init_library();
        load_custom_icons();
    }

    uint32_t hash = hash_string(name);

    // Fast lookup by hash
    for (int i = 0; i < library->icon_count; i++) {
        if (library->icons[i].hash == hash &&
            strcmp(library->icons[i].name, name) == 0) {
            return library->icons[i].glyph;
        }
    }

    return fallback ? fallback : "";
}

// Update SketchyBar item with icon
void update_item_icon(const char* item_name, const char* icon_name, const char* fallback) {
    const char* glyph = get_icon(icon_name, fallback);

    char cmd[512];
    snprintf(cmd, sizeof(cmd), "sketchybar --set %s icon='%s'", item_name, glyph);
    system(cmd);
}

// List icons by category
void list_category_icons(const char* category) {
    if (!library) {
        init_library();
        load_custom_icons();
    }

    for (int i = 0; i < library->category_count; i++) {
        if (strcmp(library->categories[i].name, category) == 0) {
            printf("[\n");
            for (int j = 0; j < library->categories[i].icon_count; j++) {
                int idx = library->categories[i].icon_indices[j];
                printf("  {\"name\":\"%s\",\"glyph\":\"%s\"},\n",
                       library->icons[idx].name,
                       library->icons[idx].glyph);
            }
            printf("]\n");
            return;
        }
    }
}

// Search icons
void search_icons(const char* query) {
    if (!library) {
        init_library();
        load_custom_icons();
    }

    printf("[\n");
    for (int i = 0; i < library->icon_count; i++) {
        if (strstr(library->icons[i].name, query) ||
            strstr(library->icons[i].category, query)) {
            printf("  {\"name\":\"%s\",\"glyph\":\"%s\",\"category\":\"%s\"},\n",
                   library->icons[i].name,
                   library->icons[i].glyph,
                   library->icons[i].category);
        }
    }
    printf("]\n");
}

// Main function for CLI usage
int main(int argc, char* argv[]) {
    if (argc < 2) {
        printf("Usage: %s <command> [args]\n", argv[0]);
        printf("Commands:\n");
        printf("  get <name> [fallback]       - Get icon glyph\n");
        printf("  set <item> <icon> [fallback] - Update SketchyBar item\n");
        printf("  list <category>             - List category icons\n");
        printf("  search <query>              - Search icons\n");
        printf("  categories                  - List all categories\n");
        return 1;
    }

    if (strcmp(argv[1], "get") == 0 && argc >= 3) {
        const char* fallback = argc >= 4 ? argv[3] : "";
        printf("%s\n", get_icon(argv[2], fallback));
    }
    else if (strcmp(argv[1], "set") == 0 && argc >= 4) {
        const char* fallback = argc >= 5 ? argv[4] : "";
        update_item_icon(argv[2], argv[3], fallback);
    }
    else if (strcmp(argv[1], "list") == 0 && argc >= 3) {
        list_category_icons(argv[2]);
    }
    else if (strcmp(argv[1], "search") == 0 && argc >= 3) {
        search_icons(argv[2]);
    }
    else if (strcmp(argv[1], "categories") == 0) {
        if (!library) {
            init_library();
            load_custom_icons();
        }
        printf("[\n");
        for (int i = 0; i < library->category_count; i++) {
            printf("  \"%s\",\n", library->categories[i].name);
        }
        printf("]\n");
    }

    return 0;
}