// State Manager - High-performance C-based state management with SketchyBar API
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <pthread.h>
#include <time.h>
#include <signal.h>

#define STATE_FILE_PATH "/tmp/sketchybar_state.mmap"
#define CONFIG_PATH_FMT "%s/.config/sketchybar/state.json"
#define MAX_WIDGETS 20
#define MAX_SPACES 16
#define MAX_STRING_LEN 256
#define MAX_ICON_LEN 16

// Widget configuration
typedef struct {
    char name[64];
    int enabled;
    char icon[MAX_ICON_LEN];
    uint32_t color;
    float scale;
    int update_interval;
} WidgetConfig;

// Space configuration
typedef struct {
    char icon[MAX_ICON_LEN];
    char mode[16]; // bsp, stack, float
    int active;
} SpaceConfig;

// Appearance settings
typedef struct {
    int bar_height;
    int corner_radius;
    uint32_t bar_color;
    int blur_radius;
    float widget_scale;
    char font_family[64];
    char font_style[32];
    float font_size;
} Appearance;

// Integration settings
typedef struct {
    int yaze_enabled;
    int emacs_enabled;
    int halext_enabled;
    char yaze_recent_roms[5][MAX_STRING_LEN];
    char emacs_workspace[64];
} Integrations;

// Shared state structure (memory-mapped)
typedef struct {
    pthread_mutex_t lock;
    time_t last_update;

    // Widgets
    WidgetConfig widgets[MAX_WIDGETS];
    int widget_count;

    // Spaces
    SpaceConfig spaces[MAX_SPACES];

    // Appearance
    Appearance appearance;

    // Integrations
    Integrations integrations;

    // Performance counters
    uint64_t icon_lookups;
    uint64_t state_updates;
    uint64_t cache_hits;

    // Change tracking
    uint32_t version;
    int dirty;
} SharedState;

static SharedState* state = NULL;
static int state_fd = -1;

// Initialize shared memory state
int init_state() {
    // Try to open existing shared state
    state_fd = shm_open("/sketchybar_state", O_RDWR, 0666);

    if (state_fd == -1) {
        // Create new shared state
        state_fd = shm_open("/sketchybar_state", O_CREAT | O_RDWR, 0666);
        if (state_fd == -1) {
            perror("shm_open");
            return -1;
        }

        // Set size
        if (ftruncate(state_fd, sizeof(SharedState)) == -1) {
            perror("ftruncate");
            return -1;
        }
    }

    // Map to memory
    state = (SharedState*)mmap(NULL, sizeof(SharedState),
                               PROT_READ | PROT_WRITE, MAP_SHARED, state_fd, 0);
    if (state == MAP_FAILED) {
        perror("mmap");
        return -1;
    }

    // Initialize mutex if needed
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_setpshared(&attr, PTHREAD_PROCESS_SHARED);
    pthread_mutex_init(&state->lock, &attr);

    return 0;
}

// Load state from JSON file
void load_json_state() {
    char path[512];
    snprintf(path, sizeof(path), CONFIG_PATH_FMT, getenv("HOME"));

    FILE* f = fopen(path, "r");
    if (!f) {
        // Set defaults
        state->appearance.bar_height = 28;
        state->appearance.corner_radius = 0;
        state->appearance.bar_color = 0xC021162F;
        state->appearance.blur_radius = 30;
        state->appearance.widget_scale = 1.0;
        strcpy(state->appearance.font_family, "SF Pro");
        strcpy(state->appearance.font_style, "Semibold");
        state->appearance.font_size = 12.0;

        // Default widgets
        state->widget_count = 5;
        strcpy(state->widgets[0].name, "system_info");
        state->widgets[0].enabled = 1;
        strcpy(state->widgets[1].name, "network");
        state->widgets[1].enabled = 1;
        strcpy(state->widgets[2].name, "clock");
        state->widgets[2].enabled = 1;
        strcpy(state->widgets[3].name, "volume");
        state->widgets[3].enabled = 1;
        strcpy(state->widgets[4].name, "battery");
        state->widgets[4].enabled = 1;

        return;
    }

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    char* buffer = malloc(size + 1);
    fread(buffer, 1, size, f);
    buffer[size] = '\0';
    fclose(f);

    // Parse JSON (simplified parsing)
    // Parse appearance
    char* app_start = strstr(buffer, "\"appearance\"");
    if (app_start) {
        char* height = strstr(app_start, "\"bar_height\"");
        if (height) {
            sscanf(height + 12, ": %d", &state->appearance.bar_height);
        }
        char* radius = strstr(app_start, "\"corner_radius\"");
        if (radius) {
            sscanf(radius + 15, ": %d", &state->appearance.corner_radius);
        }
        char* scale = strstr(app_start, "\"widget_scale\"");
        if (scale) {
            sscanf(scale + 14, ": %f", &state->appearance.widget_scale);
        }
    }

    // Parse widgets
    char* widgets_start = strstr(buffer, "\"widgets\"");
    if (widgets_start) {
        state->widget_count = 0;
        char* ptr = widgets_start;
        while ((ptr = strchr(ptr, '\"')) && state->widget_count < MAX_WIDGETS) {
            ptr++;
            char* end = strchr(ptr, '\"');
            if (!end) break;

            char name[64] = {0};
            strncpy(name, ptr, end - ptr);

            // Skip to value
            char* colon = strchr(end, ':');
            if (!colon) break;

            int enabled = 0;
            if (strstr(colon, "true")) enabled = 1;

            strcpy(state->widgets[state->widget_count].name, name);
            state->widgets[state->widget_count].enabled = enabled;
            state->widget_count++;

            ptr = colon + 1;
        }
    }

    free(buffer);
}

// Save state to JSON file
void save_json_state() {
    pthread_mutex_lock(&state->lock);

    char path[512];
    snprintf(path, sizeof(path), CONFIG_PATH_FMT, getenv("HOME"));

    FILE* f = fopen(path, "w");
    if (!f) {
        pthread_mutex_unlock(&state->lock);
        return;
    }

    fprintf(f, "{\n");

    // Write widgets
    fprintf(f, "  \"widgets\": {\n");
    for (int i = 0; i < state->widget_count; i++) {
        fprintf(f, "    \"%s\": %s%s\n",
                state->widgets[i].name,
                state->widgets[i].enabled ? "true" : "false",
                i < state->widget_count - 1 ? "," : "");
    }
    fprintf(f, "  },\n");

    // Write appearance
    fprintf(f, "  \"appearance\": {\n");
    fprintf(f, "    \"bar_height\": %d,\n", state->appearance.bar_height);
    fprintf(f, "    \"corner_radius\": %d,\n", state->appearance.corner_radius);
    fprintf(f, "    \"bar_color\": \"0x%08X\",\n", state->appearance.bar_color);
    fprintf(f, "    \"blur_radius\": %d,\n", state->appearance.blur_radius);
    fprintf(f, "    \"widget_scale\": %.2f,\n", state->appearance.widget_scale);
    fprintf(f, "    \"font_family\": \"%s\",\n", state->appearance.font_family);
    fprintf(f, "    \"font_style\": \"%s\",\n", state->appearance.font_style);
    fprintf(f, "    \"font_size\": %.1f\n", state->appearance.font_size);
    fprintf(f, "  },\n");

    // Write space icons
    fprintf(f, "  \"space_icons\": {\n");
    int first = 1;
    for (int i = 0; i < MAX_SPACES; i++) {
        if (strlen(state->spaces[i].icon) > 0) {
            if (!first) fprintf(f, ",\n");
            fprintf(f, "    \"%d\": \"%s\"", i + 1, state->spaces[i].icon);
            first = 0;
        }
    }
    fprintf(f, "\n  },\n");

    // Write space modes
    fprintf(f, "  \"space_modes\": {\n");
    first = 1;
    for (int i = 0; i < MAX_SPACES; i++) {
        if (strlen(state->spaces[i].mode) > 0 && strcmp(state->spaces[i].mode, "float") != 0) {
            if (!first) fprintf(f, ",\n");
            fprintf(f, "    \"%d\": \"%s\"", i + 1, state->spaces[i].mode);
            first = 0;
        }
    }
    fprintf(f, "\n  },\n");

    // Write integrations
    fprintf(f, "  \"integrations\": {\n");
    fprintf(f, "    \"yaze\": { \"enabled\": %s },\n",
            state->integrations.yaze_enabled ? "true" : "false");
    fprintf(f, "    \"emacs\": { \"enabled\": %s }\n",
            state->integrations.emacs_enabled ? "true" : "false");
    fprintf(f, "  }\n");

    fprintf(f, "}\n");
    fclose(f);

    state->dirty = 0;
    state->version++;
    pthread_mutex_unlock(&state->lock);
}

// Get widget configuration
WidgetConfig* get_widget(const char* name) {
    pthread_mutex_lock(&state->lock);
    for (int i = 0; i < state->widget_count; i++) {
        if (strcmp(state->widgets[i].name, name) == 0) {
            pthread_mutex_unlock(&state->lock);
            return &state->widgets[i];
        }
    }
    pthread_mutex_unlock(&state->lock);
    return NULL;
}

// Toggle widget
void toggle_widget(const char* name) {
    pthread_mutex_lock(&state->lock);
    for (int i = 0; i < state->widget_count; i++) {
        if (strcmp(state->widgets[i].name, name) == 0) {
            state->widgets[i].enabled = !state->widgets[i].enabled;
            state->dirty = 1;

            // Update SketchyBar immediately
            char cmd[256];
            snprintf(cmd, sizeof(cmd), "sketchybar --set %s drawing=%s",
                    name, state->widgets[i].enabled ? "on" : "off");
            system(cmd);
            break;
        }
    }
    pthread_mutex_unlock(&state->lock);
}

// Update appearance
void update_appearance(const char* key, const char* value) {
    pthread_mutex_lock(&state->lock);

    if (strcmp(key, "bar_height") == 0) {
        state->appearance.bar_height = atoi(value);
    } else if (strcmp(key, "corner_radius") == 0) {
        state->appearance.corner_radius = atoi(value);
    } else if (strcmp(key, "widget_scale") == 0) {
        state->appearance.widget_scale = atof(value);
    } else if (strcmp(key, "blur_radius") == 0) {
        state->appearance.blur_radius = atoi(value);
    } else if (strcmp(key, "bar_color") == 0) {
        sscanf(value, "0x%X", &state->appearance.bar_color);
    }

    state->dirty = 1;
    pthread_mutex_unlock(&state->lock);
}

// Set space icon
void set_space_icon(int space_num, const char* icon) {
    if (space_num < 1 || space_num > MAX_SPACES) return;

    pthread_mutex_lock(&state->lock);
    strcpy(state->spaces[space_num - 1].icon, icon);
    state->dirty = 1;

    // Update SketchyBar immediately
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "sketchybar --set space.%d icon='%s'",
            space_num, icon);
    system(cmd);

    pthread_mutex_unlock(&state->lock);
}

// Set space mode
void set_space_mode(int space_num, const char* mode) {
    if (space_num < 1 || space_num > MAX_SPACES) return;

    pthread_mutex_lock(&state->lock);
    strcpy(state->spaces[space_num - 1].mode, mode);
    state->dirty = 1;
    pthread_mutex_unlock(&state->lock);
}

// Main function for CLI usage
int main(int argc, char* argv[]) {
    if (argc < 2) {
        printf("Usage: %s <command> [args]\n", argv[0]);
        printf("Commands:\n");
        printf("  init                        - Initialize state\n");
        printf("  save                        - Save state to disk\n");
        printf("  widget <name> [on|off|toggle] - Control widget\n");
        printf("  appearance <key> <value>    - Update appearance\n");
        printf("  space-icon <num> <icon>     - Set space icon\n");
        printf("  space-mode <num> <mode>     - Set space mode\n");
        printf("  stats                       - Show performance stats\n");
        return 1;
    }

    if (init_state() != 0) {
        fprintf(stderr, "Failed to initialize state\n");
        return 1;
    }

    if (strcmp(argv[1], "init") == 0) {
        load_json_state();
        printf("State initialized\n");
    }
    else if (strcmp(argv[1], "save") == 0) {
        save_json_state();
        printf("State saved\n");
    }
    else if (strcmp(argv[1], "widget") == 0 && argc >= 3) {
        if (argc == 3) {
            WidgetConfig* w = get_widget(argv[2]);
            if (w) {
                printf("%s: %s\n", w->name, w->enabled ? "on" : "off");
            }
        } else if (strcmp(argv[3], "toggle") == 0) {
            toggle_widget(argv[2]);
            printf("Toggled %s\n", argv[2]);
        }
    }
    else if (strcmp(argv[1], "appearance") == 0 && argc >= 4) {
        update_appearance(argv[2], argv[3]);
        printf("Updated %s to %s\n", argv[2], argv[3]);
    }
    else if (strcmp(argv[1], "space-icon") == 0 && argc >= 4) {
        set_space_icon(atoi(argv[2]), argv[3]);
        printf("Set space %s icon to %s\n", argv[2], argv[3]);
    }
    else if (strcmp(argv[1], "space-mode") == 0 && argc >= 4) {
        set_space_mode(atoi(argv[2]), argv[3]);
        printf("Set space %s mode to %s\n", argv[2], argv[3]);
    }
    else if (strcmp(argv[1], "stats") == 0) {
        printf("Performance Stats:\n");
        printf("  Icon lookups: %llu\n", state->icon_lookups);
        printf("  State updates: %llu\n", state->state_updates);
        printf("  Cache hits: %llu\n", state->cache_hits);
        printf("  Version: %u\n", state->version);
    }

    // Auto-save if dirty
    if (state->dirty) {
        save_json_state();
    }

    return 0;
}