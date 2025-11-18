// High-performance system info widget in C
// Replaces plugins/system_info.sh for better performance

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>
#include <mach/mach.h>
#include <sys/types.h>
#include <sys/mount.h>

#define CMD_SIZE 512
#define LABEL_SIZE 256

typedef struct {
    int cpu_percent;
    float load_avg;
    unsigned long long mem_used_gb;
    char disk_info[128];
    char net_ip[64];
    char net_name[64];
    int net_online;
} SystemInfo;

// Get CPU usage (simplified - get load average as proxy)
void get_cpu_info(SystemInfo *info) {
    double loadavg[3];
    if (getloadavg(loadavg, 3) != -1) {
        info->load_avg = (float)loadavg[0];
        // Estimate CPU % from load average (rough approximation)
        info->cpu_percent = (int)(loadavg[0] * 25.0);
        if (info->cpu_percent > 100) info->cpu_percent = 100;
    } else {
        info->load_avg = 0.0;
        info->cpu_percent = 0;
    }
}

// Get memory info
void get_memory_info(SystemInfo *info) {
    int64_t memsize;
    size_t len = sizeof(memsize);

    if (sysctlbyname("hw.memsize", &memsize, &len, NULL, 0) == 0) {
        info->mem_used_gb = memsize / (1024ULL * 1024ULL * 1024ULL);
    } else {
        info->mem_used_gb = 0;
    }
}

// Get disk info
void get_disk_info(SystemInfo *info) {
    struct statfs buf;
    if (statfs("/", &buf) == 0) {
        unsigned long long total = (unsigned long long)buf.f_blocks * buf.f_bsize;
        unsigned long long avail = (unsigned long long)buf.f_bavail * buf.f_bsize;
        unsigned long long used = total - avail;

        int used_gb = used / (1024ULL * 1024ULL * 1024ULL);
        int total_gb = total / (1024ULL * 1024ULL * 1024ULL);
        int percent = (int)((used * 100) / total);

        snprintf(info->disk_info, sizeof(info->disk_info),
                 "%dGB / %dGB (%d%%)", used_gb, total_gb, percent);
    } else {
        strcpy(info->disk_info, "n/a");
    }
}

// Get network info (simplified - just check if online)
void get_network_info(SystemInfo *info) {
    FILE *fp = popen("ifconfig en0 2>/dev/null | grep 'inet ' | awk '{print $2}'", "r");
    if (fp) {
        if (fgets(info->net_ip, sizeof(info->net_ip), fp)) {
            // Remove newline
            info->net_ip[strcspn(info->net_ip, "\n")] = 0;
            info->net_online = (strlen(info->net_ip) > 0);
        } else {
            info->net_online = 0;
            strcpy(info->net_ip, "offline");
        }
        pclose(fp);
    } else {
        info->net_online = 0;
        strcpy(info->net_ip, "offline");
    }

    if (info->net_online) {
        FILE *ssid_fp = popen("networksetup -getairportnetwork en0 2>/dev/null", "r");
        if (ssid_fp) {
            if (fgets(info->net_name, sizeof(info->net_name), ssid_fp)) {
                char *colon = strchr(info->net_name, ':');
                if (colon && *(colon + 1)) {
                    colon += 1;
                    while (*colon == ' ') colon++;
                    memmove(info->net_name, colon, strlen(colon) + 1);
                }
                info->net_name[strcspn(info->net_name, "\n")] = 0;
            }
            pclose(ssid_fp);
        }
        if (info->net_name[0] == '\0') {
            strcpy(info->net_name, "Wi-Fi");
        }
    } else {
        info->net_name[0] = '\0';
    }
}

int main(int argc, char *argv[]) {
    const char *sender = getenv("SENDER");

    // Handle mouse.exited.global
    if (sender && strcmp(sender, "mouse.exited.global") == 0) {
        system("sketchybar --set system_info popup.drawing=off");
        return 0;
    }

    SystemInfo info;
    memset(&info, 0, sizeof(info));

    // Gather all system info
    get_cpu_info(&info);
    get_memory_info(&info);
    get_disk_info(&info);
    get_network_info(&info);

    // Determine CPU icon and color based on load
    const char *cpu_icon = "󰍛";
    const char *cpu_color = "0xFFa6e3a1"; // Green

    if (info.cpu_percent > 80) {
        cpu_icon = "󰈸";
        cpu_color = "0xFFf38ba8"; // Red
    } else if (info.cpu_percent > 50) {
        cpu_icon = "󰔄";
        cpu_color = "0xFFfab387"; // Peach
    }

    // Build main widget label
    char main_label[LABEL_SIZE];
    snprintf(main_label, sizeof(main_label), "%s %d%%", cpu_icon, info.cpu_percent);

    // Update main widget
    char cmd[CMD_SIZE];
    snprintf(cmd, sizeof(cmd),
             "sketchybar --set system_info "
             "label=\"%s\" "
             "icon.color=\"%s\" "
             "label.font.style=\"Semibold\"",
             main_label, cpu_color);
    system(cmd);

    // Update popup items
    snprintf(cmd, sizeof(cmd),
             "sketchybar --set system_info.cpu "
             "label=\"CPU %d%%    Load %.2f\"",
             info.cpu_percent, info.load_avg);
    system(cmd);

    snprintf(cmd, sizeof(cmd),
             "sketchybar --set system_info.mem "
             "label=\"Memory %lluG\"",
             info.mem_used_gb);
    system(cmd);

    snprintf(cmd, sizeof(cmd),
             "sketchybar --set system_info.disk "
             "label=\"Disk %s\"",
             info.disk_info);
    system(cmd);

    // Network
    if (info.net_online) {
        const char *ssid = info.net_name[0] ? info.net_name : "Wi-Fi";
        snprintf(cmd, sizeof(cmd),
                 "sketchybar --set system_info.net "
                 "label=\"%s (%s)\" "
                 "icon.color=\"0xFFa6e3a1\"",
                 ssid,
                 info.net_ip);
    } else {
        snprintf(cmd, sizeof(cmd),
                 "sketchybar --set system_info.net "
                 "label=\"Wi-Fi Offline\" "
                 "icon.color=\"0xFFf38ba8\"");
    }
    system(cmd);

    return 0;
}
