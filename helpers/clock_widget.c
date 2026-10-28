// High-performance clock widget in C
// Replaces plugins/clock.sh for better performance

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define BUFFER_SIZE 128

static const char *clock_format(void) {
    const char *style = getenv("BARISTA_CLOCK_STYLE");
    if (style && strcmp(style, "time") == 0) {
        return "%I:%M %p";
    }
    if (style && strcmp(style, "compact") == 0) {
        return "%a %I:%M %p";
    }
    return "%a %m/%d %I:%M %p";
}

void get_formatted_time(char *buffer, size_t size) {
    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);
    if (!tm_info) {
        snprintf(buffer, size, "--:--");
        return;
    }
    if (strftime(buffer, size, clock_format(), tm_info) == 0) {
        snprintf(buffer, size, "--:--");
    }
}

int main(int argc, char *argv[]) {
    char time_str[BUFFER_SIZE];
    char command[BUFFER_SIZE * 2];
    const char *sender = getenv("SENDER");
    const char *name = getenv("NAME");

    (void)argc;
    (void)argv;

    if (!name) {
        name = "clock";
    }

    // Handle mouse.exited.global event
    if (sender && strcmp(sender, "mouse.exited.global") == 0) {
        snprintf(command, sizeof(command),
                 "sketchybar --set %s popup.drawing=off", name);
        system(command);
        return 0;
    }

    // Get formatted time
    get_formatted_time(time_str, sizeof(time_str));

    // Update sketchybar
    snprintf(command, sizeof(command),
             "sketchybar --set %s label=\"%s\"", name, time_str);
    system(command);

    return 0;
}
