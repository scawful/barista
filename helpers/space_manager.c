// High-performance space manager for SketchyBar
// Handles space operations with minimal latency

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MAX_CMD 512

// Execute yabai command and trigger sketchybar update
static void yabai_exec(const char *cmd) {
    char full_cmd[MAX_CMD];
    snprintf(full_cmd, sizeof(full_cmd), "yabai -m %s 2>/dev/null", cmd);
    system(full_cmd);
}

// Trigger sketchybar refresh
static void trigger_refresh() {
    system("sketchybar --trigger space_change 2>/dev/null &");
}

// Create new space
static void space_create() {
    yabai_exec("space --create");
    trigger_refresh();
}

// Destroy space
static void space_destroy(int space_idx) {
    char cmd[MAX_CMD];
    snprintf(cmd, sizeof(cmd), "space %d --destroy", space_idx);
    yabai_exec(cmd);
    trigger_refresh();
}

// Move space (reorder)
static void space_move(int from_idx, int to_idx) {
    char cmd[MAX_CMD];
    snprintf(cmd, sizeof(cmd), "space %d --move %d", from_idx, to_idx);
    yabai_exec(cmd);
    trigger_refresh();
}

// Focus space
static void space_focus(int space_idx) {
    char cmd[MAX_CMD];
    snprintf(cmd, sizeof(cmd), "space %d --focus", space_idx);
    yabai_exec(cmd);
    trigger_refresh();
}

// Swap spaces (for drag-and-drop)
static void space_swap(int space1, int space2) {
    // Temporarily move to avoid conflicts
    int temp_idx = 999;
    space_move(space1, temp_idx);
    space_move(space2, space1);
    space_move(temp_idx, space2);
    trigger_refresh();
}

void print_usage(const char *prog) {
    fprintf(stderr, "Usage: %s <command> [args]\n", prog);
    fprintf(stderr, "Commands:\n");
    fprintf(stderr, "  create              - Create new space\n");
    fprintf(stderr, "  destroy <index>     - Destroy space at index\n");
    fprintf(stderr, "  move <from> <to>    - Move space from index to index\n");
    fprintf(stderr, "  focus <index>       - Focus space at index\n");
    fprintf(stderr, "  swap <idx1> <idx2>  - Swap two spaces\n");
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }

    const char *cmd = argv[1];

    if (strcmp(cmd, "create") == 0) {
        space_create();
    }
    else if (strcmp(cmd, "destroy") == 0) {
        if (argc < 3) {
            fprintf(stderr, "Error: destroy requires space index\n");
            return 1;
        }
        int idx = atoi(argv[2]);
        space_destroy(idx);
    }
    else if (strcmp(cmd, "move") == 0) {
        if (argc < 4) {
            fprintf(stderr, "Error: move requires from and to indices\n");
            return 1;
        }
        int from = atoi(argv[2]);
        int to = atoi(argv[3]);
        space_move(from, to);
    }
    else if (strcmp(cmd, "focus") == 0) {
        if (argc < 3) {
            fprintf(stderr, "Error: focus requires space index\n");
            return 1;
        }
        int idx = atoi(argv[2]);
        space_focus(idx);
    }
    else if (strcmp(cmd, "swap") == 0) {
        if (argc < 4) {
            fprintf(stderr, "Error: swap requires two space indices\n");
            return 1;
        }
        int idx1 = atoi(argv[2]);
        int idx2 = atoi(argv[3]);
        space_swap(idx1, idx2);
    }
    else {
        fprintf(stderr, "Unknown command: %s\n", cmd);
        print_usage(argv[0]);
        return 1;
    }

    return 0;
}
