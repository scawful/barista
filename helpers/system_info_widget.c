// High-performance system info widget in C
// Replaces plugins/system_info.sh for better performance

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>
#include <mach/mach.h>
#include <mach/mach_host.h>
#include <sys/types.h>
#include <sys/mount.h>

#define CMD_SIZE 512
#define LABEL_SIZE 256

typedef struct {
    int cpu_percent;
    float load_avg;
    unsigned long long mem_used_gb;
    unsigned long long mem_total_gb;
    char disk_info[128];
    char net_ip[64];
    char net_name[64];
    int net_online;
} SystemInfo;

static void read_cmd(const char *cmd, char *out, size_t len) {
    if (!out || len == 0) return;
    out[0] = '\0';
    FILE *fp = popen(cmd, "r");
    if (!fp) return;
    if (fgets(out, len, fp)) {
        out[strcspn(out, "\n")] = 0;
    } else {
        out[0] = '\0';
    }
    pclose(fp);
}

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
    int64_t memsize = 0;
    size_t len = sizeof(memsize);
    vm_size_t page_size = 0;
    mach_port_t mach_port = mach_host_self();
    vm_statistics64_data_t vm_stat;
    mach_msg_type_number_t host_size = HOST_VM_INFO64_COUNT;
    unsigned long long used_bytes = 0;

    info->mem_used_gb = 0;
    info->mem_total_gb = 0;

    if (sysctlbyname("hw.memsize", &memsize, &len, NULL, 0) == 0 && memsize > 0) {
        info->mem_total_gb = (unsigned long long)(memsize / (1024ULL * 1024ULL * 1024ULL));
    }

    if (host_page_size(mach_port, &page_size) != KERN_SUCCESS) {
        return;
    }

    if (host_statistics64(mach_port, HOST_VM_INFO64, (host_info64_t)&vm_stat, &host_size) != KERN_SUCCESS) {
        return;
    }

    used_bytes = ((unsigned long long)vm_stat.active_count +
                  (unsigned long long)vm_stat.wire_count +
                  (unsigned long long)vm_stat.compressor_page_count) * (unsigned long long)page_size;
    info->mem_used_gb = used_bytes / (1024ULL * 1024ULL * 1024ULL);
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

// Get network info (with timeout protection)
void get_network_info(SystemInfo *info) {
    char wifi_iface[32] = "";
    char active_iface[32] = "";
    read_cmd(
        "perl -e 'alarm 1; exec @ARGV' \"networksetup -listallhardwareports 2>/dev/null | "
        "awk '/^Hardware Port: (Wi-Fi|AirPort)$/{found=1} found && /^Device: /{print $2; exit}'\"",
        wifi_iface, sizeof(wifi_iface));
    read_cmd(
        "perl -e 'alarm 1; exec @ARGV' \"route -n get default 2>/dev/null | awk '/interface: /{print $2; exit}'\"",
        active_iface, sizeof(active_iface));

    const char *iface = "en0";
    if (wifi_iface[0] != '\0') {
        iface = wifi_iface;
    } else if (active_iface[0] != '\0') {
        iface = active_iface;
    }

    char cmd[CMD_SIZE];
    snprintf(cmd, sizeof(cmd),
             "perl -e 'alarm 1; exec @ARGV' \"ipconfig getifaddr %s 2>/dev/null\"",
             iface);
    read_cmd(cmd, info->net_ip, sizeof(info->net_ip));
    if (info->net_ip[0] == '\0' && active_iface[0] != '\0' && strcmp(active_iface, iface) != 0) {
        snprintf(cmd, sizeof(cmd),
                 "perl -e 'alarm 1; exec @ARGV' \"ipconfig getifaddr %s 2>/dev/null\"",
                 active_iface);
        read_cmd(cmd, info->net_ip, sizeof(info->net_ip));
    }

    read_cmd(
        "perl -e 'alarm 1; exec @ARGV' "
        "\"/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I "
        "| awk -F': ' '/ SSID/ {print $2; exit}'\"",
        info->net_name, sizeof(info->net_name));
    if (info->net_name[0] == '\0' && wifi_iface[0] != '\0') {
        snprintf(cmd, sizeof(cmd),
                 "perl -e 'alarm 1; exec @ARGV' "
                 "\"networksetup -getairportnetwork %s 2>/dev/null | "
                 "awk -F': ' '/Current Wi-Fi Network:/{print $2; exit}'\"",
                 wifi_iface);
        read_cmd(cmd, info->net_name, sizeof(info->net_name));
    }
    if (strcmp(info->net_name, "You are not associated with an AirPort network.") == 0) {
        info->net_name[0] = '\0';
    }

    info->net_online = (info->net_ip[0] != '\0' || info->net_name[0] != '\0');
}

int main(void) {
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
    const char *cpu_color = "0xFFa6e3a1"; // Green

    if (info.cpu_percent > 80) {
        cpu_color = "0xFFf38ba8"; // Red
    } else if (info.cpu_percent > 50) {
        cpu_color = "0xFFfab387"; // Peach
    }

    // Build main widget label
    char main_label[LABEL_SIZE];
    snprintf(main_label, sizeof(main_label), "%d%% %llu/%lluG",
             info.cpu_percent,
             info.mem_used_gb,
             info.mem_total_gb);

    // Network label
    char net_label[LABEL_SIZE];
    if (info.net_online) {
        if (info.net_name[0] != '\0' && info.net_ip[0] != '\0') {
            snprintf(net_label, sizeof(net_label), "Wi-Fi: %s (%s)", info.net_name, info.net_ip);
        } else if (info.net_name[0] != '\0') {
            snprintf(net_label, sizeof(net_label), "Wi-Fi: %s", info.net_name);
        } else {
            snprintf(net_label, sizeof(net_label), "Network: %s", info.net_ip);
        }
    } else {
        snprintf(net_label, sizeof(net_label), "Wi-Fi: Disconnected");
    }

    /* Routine helper updates should only touch the main bar label.
     * Popup rows are refreshed on demand by plugins/system_info.sh popup_refresh. */
    char cmd[CMD_SIZE];
    snprintf(cmd, sizeof(cmd),
             "sketchybar"
             " --set system_info label=\"%s\" icon.color=\"%s\" label.font.style=\"Semibold\"",
             main_label, cpu_color);
    system(cmd);

    return 0;
}
