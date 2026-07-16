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

static inline const char* sketchybar_bin(void) {
    const char* value = getenv("BARISTA_SKETCHYBAR_BIN");
    if (value && *value) return value;
    value = getenv("SKETCHYBAR_BIN");
    return (value && *value) ? value : "sketchybar";
}

static int exec_sketchybar(const char* name,
                           const char* curve,
                           const char* duration,
                           const char* const properties[],
                           size_t property_count) {
    char* argv[16];
    size_t argc = 0;
    const char* binary = sketchybar_bin();

    argv[argc++] = (char*)binary;
    if (curve && *curve && duration && *duration) {
        argv[argc++] = "--animate";
        argv[argc++] = (char*)curve;
        argv[argc++] = (char*)duration;
    }
    argv[argc++] = "--set";
    argv[argc++] = (char*)name;
    for (size_t i = 0; i < property_count && argc + 1 < sizeof(argv) / sizeof(argv[0]); i++) {
        argv[argc++] = (char*)properties[i];
    }
    argv[argc] = NULL;

    execvp(binary, argv);
    perror("execvp");
    return 1;
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

    if (!strcmp(sender, "mouse.entered")) {
        const char *color = get("POPUP_HOVER_COLOR", "0x40f5c2e7");
        const char *brd = get("POPUP_HOVER_BORDER_COLOR", "0x60cdd6f4");
        const char *width = getenv("POPUP_HOVER_BORDER_WIDTH");

        char color_prop[1024];
        char border_width_prop[1024];
        char border_color_prop[1024];
        const char* properties[4];
        size_t property_count = 0;

        snprintf(color_prop, sizeof(color_prop), "background.color=%s", color);
        properties[property_count++] = "background.drawing=on";
        properties[property_count++] = color_prop;
        if (width && *width) {
            snprintf(border_width_prop, sizeof(border_width_prop), "background.border_width=%s", width);
            snprintf(border_color_prop, sizeof(border_color_prop), "background.border_color=%s", brd);
            properties[property_count++] = border_width_prop;
            properties[property_count++] = border_color_prop;
        }

        return exec_sketchybar(
            name,
            enter_anim ? enter_curve : NULL,
            enter_anim ? enter_dur : NULL,
            properties,
            property_count
        );
    }

    const char* properties[] = {
        "background.drawing=off",
        "background.border_width=0",
    };
    return exec_sketchybar(
        name,
        exit_anim ? exit_curve : NULL,
        exit_anim ? exit_dur : NULL,
        properties,
        sizeof(properties) / sizeof(properties[0])
    );
}
