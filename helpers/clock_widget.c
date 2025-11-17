// High-performance clock widget in C
// Replaces plugins/clock.sh for better performance

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define BUFFER_SIZE 128

// Format: "Day MM/DD HH:MM AM/PM"
void get_formatted_time(char *buffer, size_t size) {
    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);

    // Day names
    const char *days[] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};

    // Get 12-hour format
    int hour = tm_info->tm_hour;
    const char *am_pm = hour >= 12 ? "PM" : "AM";
    if (hour > 12) hour -= 12;
    if (hour == 0) hour = 12;

    snprintf(buffer, size, "%s %02d/%02d %02d:%02d %s",
             days[tm_info->tm_wday],
             tm_info->tm_mon + 1,
             tm_info->tm_mday,
             hour,
             tm_info->tm_min,
             am_pm);
}

int main(int argc, char *argv[]) {
    char time_str[BUFFER_SIZE];
    char command[BUFFER_SIZE * 2];
    const char *sender = getenv("SENDER");
    const char *name = getenv("NAME");

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
