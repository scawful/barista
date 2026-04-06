#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <limits.h>

/*
 * Popup Hover Handler (Brutalist Edition)
 * Optimized for zero-slop execution and minimal binary size.
 */

static inline const char* get(const char* k, const char* d) {
    const char* v = getenv(k);
    return (v && *v) ? v : d;
}

int main(void) {
    const char *name = getenv("NAME");
    if (!name) return 0;

    const char *tmp = get("TMPDIR", "/tmp");
    char path[PATH_MAX];
    snprintf(path, sizeof(path), "%s/sketchybar_popup_state", tmp);
    mkdir(path, 0700);

    const char *parent = getenv("SUBMENU_PARENT");
    if (parent && *parent) {
        char p_path[PATH_MAX];
        snprintf(p_path, sizeof(p_path), "%s/active_parent", path);
        FILE *fp = fopen(p_path, "w");
        if (fp) { fputs(parent, fp); fclose(fp); }
    }

    const char *sender = get("SENDER", "mouse.entered");
    const char *enter_curve = getenv("POPUP_HOVER_ANIMATION_CURVE");
    const char *enter_dur = getenv("POPUP_HOVER_ANIMATION_DURATION");
    const char *exit_curve = getenv("POPUP_HOVER_EXIT_CURVE");
    const char *exit_dur = getenv("POPUP_HOVER_EXIT_DURATION");
    int enter_anim = (enter_curve && *enter_curve && enter_dur && *enter_dur);
    int exit_anim = (exit_curve && *exit_curve && exit_dur && *exit_dur);

    char cmd[1024];
    if (!strcmp(sender, "mouse.entered")) {
        const char *color = get("POPUP_HOVER_COLOR", "0x40f5c2e7");
        const char *brd = get("POPUP_HOVER_BORDER_COLOR", "0x60cdd6f4");
        const char *width = getenv("POPUP_HOVER_BORDER_WIDTH");
        
        if (width && *width) {
            snprintf(cmd, sizeof(cmd), 
                "sketchybar%s%s%s%s --set %s background.drawing=on background.color=%s background.border_width=%s background.border_color=%s",
                enter_anim ? " --animate " : "", enter_anim ? enter_curve : "", enter_anim ? " " : "", enter_anim ? enter_dur : "",
                name, color, width, brd);
        } else {
            snprintf(cmd, sizeof(cmd), 
                "sketchybar%s%s%s%s --set %s background.drawing=on background.color=%s",
                enter_anim ? " --animate " : "", enter_anim ? enter_curve : "", enter_anim ? " " : "", enter_anim ? enter_dur : "",
                name, color);
        }
    } else {
        snprintf(cmd, sizeof(cmd), 
            "sketchybar%s%s%s%s --set %s background.drawing=off background.border_width=0",
            exit_anim ? " --animate " : "", exit_anim ? exit_curve : "", exit_anim ? " " : "", exit_anim ? exit_dur : "",
            name);
    }
    /* PERF: Use execlp instead of system() to avoid double-fork.
     * Since popup_hover is a one-shot binary (SketchyBar spawns it per event),
     * we can exec directly — the process is replaced, saving one fork cycle. */
    execlp("sh", "sh", "-c", cmd, (char *)NULL);
    /* execlp only returns on failure */
    perror("execlp");
    return 1;
}
