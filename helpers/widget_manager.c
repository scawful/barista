// Widget Manager - High-performance C-based widget updates with SketchyBar API
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <sys/mount.h>
#include <mach/mach.h>
#include <mach/processor_info.h>
#include <mach/mach_host.h>
#include <mach/vm_map.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/ps/IOPowerSources.h>
#include <pthread.h>

// Widget types
typedef enum {
    WIDGET_CLOCK,
    WIDGET_BATTERY,
    WIDGET_CPU,
    WIDGET_MEMORY,
    WIDGET_DISK,
    WIDGET_NETWORK,
    WIDGET_VOLUME,
    WIDGET_CUSTOM
} WidgetType;

// Widget update intervals (in seconds)
typedef struct {
    WidgetType type;
    int interval;
    time_t last_update;
    char name[64];
    char (*update_func)();
} Widget;

// System info cache
typedef struct {
    double cpu_usage;
    double memory_usage;
    double disk_usage;
    int battery_percentage;
    int battery_charging;
    int volume_level;
    int volume_muted;
    char network_status[32];
    time_t last_cpu_update;
    time_t last_mem_update;
    time_t last_disk_update;
} SystemCache;

static SystemCache cache = {0};
static pthread_mutex_t cache_lock = PTHREAD_MUTEX_INITIALIZER;

// CPU usage calculation
double get_cpu_usage() {
    static host_cpu_load_info_data_t prev_info = {0};
    host_cpu_load_info_data_t info;
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;

    if (host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO,
                        (host_info_t)&info, &count) != KERN_SUCCESS) {
        return 0.0;
    }

    natural_t user = info.cpu_ticks[CPU_STATE_USER] - prev_info.cpu_ticks[CPU_STATE_USER];
    natural_t system = info.cpu_ticks[CPU_STATE_SYSTEM] - prev_info.cpu_ticks[CPU_STATE_SYSTEM];
    natural_t idle = info.cpu_ticks[CPU_STATE_IDLE] - prev_info.cpu_ticks[CPU_STATE_IDLE];
    natural_t nice = info.cpu_ticks[CPU_STATE_NICE] - prev_info.cpu_ticks[CPU_STATE_NICE];

    natural_t total = user + system + idle + nice;
    double usage = (total > 0) ? ((double)(user + system + nice) / total * 100.0) : 0.0;

    prev_info = info;
    return usage;
}

// Memory usage calculation
double get_memory_usage() {
    vm_size_t page_size;
    mach_port_t mach_port = mach_host_self();
    vm_statistics64_data_t vm_stat;
    mach_msg_type_number_t host_size = sizeof(vm_stat) / sizeof(natural_t);

    host_page_size(mach_port, &page_size);
    if (host_statistics64(mach_port, HOST_VM_INFO,
                          (host_info64_t)&vm_stat, &host_size) != KERN_SUCCESS) {
        return 0.0;
    }

    uint64_t total_pages = vm_stat.free_count + vm_stat.active_count +
                           vm_stat.inactive_count + vm_stat.wire_count;
    uint64_t used_pages = vm_stat.active_count + vm_stat.wire_count;

    return (total_pages > 0) ? ((double)used_pages / total_pages * 100.0) : 0.0;
}

// Disk usage calculation
double get_disk_usage() {
    struct statfs stats;
    if (statfs("/", &stats) != 0) {
        return 0.0;
    }

    uint64_t total = stats.f_blocks * stats.f_bsize;
    uint64_t free = stats.f_bavail * stats.f_bsize;
    uint64_t used = total - free;

    return (total > 0) ? ((double)used / total * 100.0) : 0.0;
}

// Define IOKit constants if not available
#ifndef kIOPSTypeKey
#define kIOPSTypeKey "Type"
#endif
#ifndef kIOPSInternalBatteryType
#define kIOPSInternalBatteryType "InternalBattery"
#endif
#ifndef kIOPSCurrentCapacityKey
#define kIOPSCurrentCapacityKey "Current Capacity"
#endif
#ifndef kIOPSPowerSourceStateKey
#define kIOPSPowerSourceStateKey "Power Source State"
#endif
#ifndef kIOPSACPowerValue
#define kIOPSACPowerValue "AC Power"
#endif

// Battery status
void get_battery_status(int* percentage, int* charging) {
    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    CFArrayRef sources = IOPSCopyPowerSourcesList(info);

    if (!sources) {
        if (info) CFRelease(info);
        *percentage = 100;
        *charging = 0;
        return;
    }

    for (int i = 0; i < CFArrayGetCount(sources); i++) {
        CFDictionaryRef source = IOPSGetPowerSourceDescription(info,
                                    CFArrayGetValueAtIndex(sources, i));
        if (!source) continue;

        CFStringRef type = CFDictionaryGetValue(source, CFSTR("Type"));
        if (type && CFStringCompare(type, CFSTR("InternalBattery"), 0) == 0) {
            CFNumberRef capacity = CFDictionaryGetValue(source,
                                     CFSTR("Current Capacity"));
            if (capacity) {
                CFNumberGetValue(capacity, kCFNumberIntType, percentage);
            }

            CFStringRef state = CFDictionaryGetValue(source, CFSTR("Power Source State"));
            *charging = (state && CFStringCompare(state,
                         CFSTR("AC Power"), 0) == 0) ? 1 : 0;
            break;
        }
    }

    CFRelease(sources);
    CFRelease(info);
}

// Update clock widget
void update_clock(const char* widget_name) {
    time_t t = time(NULL);
    struct tm* tm = localtime(&t);
    char time_str[32];
    strftime(time_str, sizeof(time_str), "%H:%M", tm);

    char cmd[256];
    snprintf(cmd, sizeof(cmd), "sketchybar --set %s label='%s'", widget_name, time_str);
    system(cmd);
}

// Update battery widget
void update_battery(const char* widget_name) {
    int percentage, charging;
    get_battery_status(&percentage, &charging);

    const char* icon = "";
    if (charging) {
        icon = "";
    } else if (percentage > 80) {
        icon = "";
    } else if (percentage > 60) {
        icon = "";
    } else if (percentage > 40) {
        icon = "";
    } else if (percentage > 20) {
        icon = "";
    } else {
        icon = "";
    }

    char cmd[256];
    snprintf(cmd, sizeof(cmd),
             "sketchybar --set %s icon='%s' label='%d%%'",
             widget_name, icon, percentage);
    system(cmd);
}

// Update CPU widget
void update_cpu(const char* widget_name) {
    pthread_mutex_lock(&cache_lock);

    time_t now = time(NULL);
    if (now - cache.last_cpu_update >= 1) {
        cache.cpu_usage = get_cpu_usage();
        cache.last_cpu_update = now;
    }

    char cmd[256];
    snprintf(cmd, sizeof(cmd),
             "sketchybar --set %s label='CPU: %.1f%%'",
             widget_name, cache.cpu_usage);
    system(cmd);

    pthread_mutex_unlock(&cache_lock);
}

// Update memory widget
void update_memory(const char* widget_name) {
    pthread_mutex_lock(&cache_lock);

    time_t now = time(NULL);
    if (now - cache.last_mem_update >= 2) {
        cache.memory_usage = get_memory_usage();
        cache.last_mem_update = now;
    }

    char cmd[256];
    snprintf(cmd, sizeof(cmd),
             "sketchybar --set %s label='MEM: %.1f%%'",
             widget_name, cache.memory_usage);
    system(cmd);

    pthread_mutex_unlock(&cache_lock);
}

// Update system info widget (combined)
void update_system_info(const char* widget_name) {
    pthread_mutex_lock(&cache_lock);

    time_t now = time(NULL);
    if (now - cache.last_cpu_update >= 1) {
        cache.cpu_usage = get_cpu_usage();
        cache.last_cpu_update = now;
    }
    if (now - cache.last_mem_update >= 2) {
        cache.memory_usage = get_memory_usage();
        cache.last_mem_update = now;
    }
    if (now - cache.last_disk_update >= 10) {
        cache.disk_usage = get_disk_usage();
        cache.last_disk_update = now;
    }

    char label[128];
    snprintf(label, sizeof(label),
             "󰻠 %.1f%% 󰘚 %.1f%% 󰋊 %.1f%%",
             cache.cpu_usage, cache.memory_usage, cache.disk_usage);

    char cmd[512];
    snprintf(cmd, sizeof(cmd),
             "sketchybar --set %s label='%s'", widget_name, label);
    system(cmd);

    pthread_mutex_unlock(&cache_lock);
}

// Batch update multiple widgets
void batch_update(const char* widgets[], int count) {
    char cmd[2048] = "sketchybar";

    for (int i = 0; i < count; i++) {
        if (strcmp(widgets[i], "clock") == 0) {
            time_t t = time(NULL);
            struct tm* tm = localtime(&t);
            char time_str[32];
            strftime(time_str, sizeof(time_str), "%H:%M", tm);
            char buf[256];
            snprintf(buf, sizeof(buf), " --set clock label='%s'", time_str);
            strcat(cmd, buf);
        }
        else if (strcmp(widgets[i], "battery") == 0) {
            int percentage, charging;
            get_battery_status(&percentage, &charging);
            char buf[256];
            snprintf(buf, sizeof(buf), " --set battery label='%d%%'", percentage);
            strcat(cmd, buf);
        }
        else if (strcmp(widgets[i], "system_info") == 0) {
            pthread_mutex_lock(&cache_lock);
            cache.cpu_usage = get_cpu_usage();
            cache.memory_usage = get_memory_usage();
            char buf[512];
            snprintf(buf, sizeof(buf),
                    " --set system_info label='󰻠 %.1f%% 󰘚 %.1f%%'",
                    cache.cpu_usage, cache.memory_usage);
            strcat(cmd, buf);
            pthread_mutex_unlock(&cache_lock);
        }
    }

    system(cmd);
}

// Widget daemon mode - continuously update widgets
void daemon_mode() {
    Widget widgets[] = {
        {WIDGET_CLOCK, 1, 0, "clock", NULL},
        {WIDGET_BATTERY, 10, 0, "battery", NULL},
        {WIDGET_CPU, 2, 0, "system_info", NULL},
    };
    int widget_count = sizeof(widgets) / sizeof(Widget);

    printf("Widget manager daemon started\n");

    while (1) {
        time_t now = time(NULL);

        for (int i = 0; i < widget_count; i++) {
            if (now - widgets[i].last_update >= widgets[i].interval) {
                switch (widgets[i].type) {
                    case WIDGET_CLOCK:
                        update_clock(widgets[i].name);
                        break;
                    case WIDGET_BATTERY:
                        update_battery(widgets[i].name);
                        break;
                    case WIDGET_CPU:
                        update_system_info(widgets[i].name);
                        break;
                    default:
                        break;
                }
                widgets[i].last_update = now;
            }
        }

        usleep(100000); // 100ms
    }
}

// Main function
int main(int argc, char* argv[]) {
    if (argc < 2) {
        printf("Usage: %s <command> [args]\n", argv[0]);
        printf("Commands:\n");
        printf("  update <widget>    - Update specific widget\n");
        printf("  batch <w1> <w2>... - Batch update widgets\n");
        printf("  daemon             - Run as daemon\n");
        printf("  stats              - Show system stats\n");
        printf("\nWidgets: clock, battery, cpu, memory, system_info\n");
        return 1;
    }

    if (strcmp(argv[1], "update") == 0 && argc >= 3) {
        if (strcmp(argv[2], "clock") == 0) {
            update_clock("clock");
        } else if (strcmp(argv[2], "battery") == 0) {
            update_battery("battery");
        } else if (strcmp(argv[2], "cpu") == 0) {
            update_cpu("cpu");
        } else if (strcmp(argv[2], "memory") == 0) {
            update_memory("memory");
        } else if (strcmp(argv[2], "system_info") == 0) {
            update_system_info("system_info");
        }
    }
    else if (strcmp(argv[1], "batch") == 0 && argc >= 3) {
        batch_update((const char**)&argv[2], argc - 2);
    }
    else if (strcmp(argv[1], "daemon") == 0) {
        daemon_mode();
    }
    else if (strcmp(argv[1], "stats") == 0) {
        printf("System Stats:\n");
        printf("  CPU Usage: %.1f%%\n", get_cpu_usage());
        printf("  Memory Usage: %.1f%%\n", get_memory_usage());
        printf("  Disk Usage: %.1f%%\n", get_disk_usage());

        int percentage, charging;
        get_battery_status(&percentage, &charging);
        printf("  Battery: %d%% %s\n", percentage, charging ? "(charging)" : "");
    }

    return 0;
}