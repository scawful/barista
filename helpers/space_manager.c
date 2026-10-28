// High-performance space manager for SketchyBar
// Handles space operations with minimal latency

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static const char *resolve_yabai_bin(void) {
    const char *bin = getenv("BARISTA_YABAI_BIN");
    if (bin && bin[0] != '\0') return bin;
    bin = getenv("YABAI_BIN");
    if (bin && bin[0] != '\0') return bin;
    return "yabai";
}

static const char *resolve_sketchybar_bin(void) {
    const char *bin = getenv("BARISTA_SKETCHYBAR_BIN");
    if (bin && bin[0] != '\0') return bin;
    bin = getenv("SKETCHYBAR_BIN");
    if (bin && bin[0] != '\0') return bin;
    return "sketchybar";
}

static int run_argv(char *const argv[]) {
    pid_t pid = fork();
    if (pid < 0) return 1;
    if (pid == 0) {
        execvp(argv[0], argv);
        _exit(127);
    }
    int status = 0;
    if (waitpid(pid, &status, 0) < 0) return 1;
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    return 1;
}

static void trigger_refresh(void) {
    const char *no_trigger = getenv("BARISTA_SPACE_MANAGER_NO_TRIGGER");
    if (no_trigger && strcmp(no_trigger, "1") == 0) return;

    pid_t pid = fork();
    if (pid == 0) {
        const char *sb = resolve_sketchybar_bin();
        char *const argv[] = {(char *)sb, "--trigger", "space_change", NULL};
        execvp(argv[0], argv);
        _exit(0);
    }
}

static int space_create(void) {
    const char *yabai = resolve_yabai_bin();
    char *const argv[] = {(char *)yabai, "-m", "space", "--create", NULL};
    int rc = run_argv(argv);
    if (rc == 0) trigger_refresh();
    return rc;
}

static int space_destroy(int space_idx) {
    char idx_buf[32];
    snprintf(idx_buf, sizeof(idx_buf), "%d", space_idx);
    const char *yabai = resolve_yabai_bin();
    char *const argv[] = {(char *)yabai, "-m", "space", idx_buf, "--destroy", NULL};
    int rc = run_argv(argv);
    if (rc == 0) trigger_refresh();
    return rc;
}

static int space_move(int from_idx, int to_idx) {
    char from_buf[32], to_buf[32];
    snprintf(from_buf, sizeof(from_buf), "%d", from_idx);
    snprintf(to_buf, sizeof(to_buf), "%d", to_idx);
    const char *yabai = resolve_yabai_bin();
    char *const argv[] = {(char *)yabai, "-m", "space", from_buf, "--move", to_buf, NULL};
    int rc = run_argv(argv);
    if (rc == 0) trigger_refresh();
    return rc;
}

static int space_focus(int space_idx) {
    char idx_buf[32];
    snprintf(idx_buf, sizeof(idx_buf), "%d", space_idx);
    const char *yabai = resolve_yabai_bin();
    char *const argv[] = {(char *)yabai, "-m", "space", "--focus", idx_buf, NULL};
    int rc = run_argv(argv);
    if (rc == 0) trigger_refresh();
    return rc;
}

static int space_swap(int space1, int space2) {
    char idx1_buf[32], idx2_buf[32];
    snprintf(idx1_buf, sizeof(idx1_buf), "%d", space1);
    snprintf(idx2_buf, sizeof(idx2_buf), "%d", space2);
    const char *yabai = resolve_yabai_bin();
    char *const argv[] = {(char *)yabai, "-m", "space", idx1_buf, "--swap", idx2_buf, NULL};
    int rc = run_argv(argv);
    if (rc == 0) trigger_refresh();
    return rc;
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
        return space_create();
    }
    else if (strcmp(cmd, "destroy") == 0) {
        if (argc < 3) {
            fprintf(stderr, "Error: destroy requires space index\n");
            return 1;
        }
        int idx = atoi(argv[2]);
        if (idx < 1) return 1;
        return space_destroy(idx);
    }
    else if (strcmp(cmd, "move") == 0) {
        if (argc < 4) {
            fprintf(stderr, "Error: move requires from and to indices\n");
            return 1;
        }
        int from = atoi(argv[2]);
        int to = atoi(argv[3]);
        if (from < 1 || to < 1) return 1;
        return space_move(from, to);
    }
    else if (strcmp(cmd, "focus") == 0) {
        if (argc < 3) {
            fprintf(stderr, "Error: focus requires space index\n");
            return 1;
        }
        int idx = atoi(argv[2]);
        if (idx < 1) return 1;
        return space_focus(idx);
    }
    else if (strcmp(cmd, "swap") == 0) {
        if (argc < 4) {
            fprintf(stderr, "Error: swap requires two space indices\n");
            return 1;
        }
        int idx1 = atoi(argv[2]);
        int idx2 = atoi(argv[3]);
        if (idx1 < 1 || idx2 < 1) return 1;
        return space_swap(idx1, idx2);
    }
    else {
        fprintf(stderr, "Unknown command: %s\n", cmd);
        print_usage(argv[0]);
        return 1;
    }
}
