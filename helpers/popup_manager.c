#define _POSIX_C_SOURCE 200809L

#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifdef __APPLE__
#include <bootstrap.h>
#include <mach/mach.h>
#include <mach/message.h>
#endif

/*
 * Global Popup Manager
 *
 * Handles automatic dismissal of all popups on events like:
 * - space_changed (Yabai space switching)
 * - display_changed (Display configuration changes)
 * - mission_control_enter (macOS Mission Control/Spaces overview)
 * - window_focused (Window focus changes)
 *
 * Usage:
 *   Set as script for items that should dismiss popups on these events
 *   Subscribe items with: sketchybar --subscribe popup_manager <events>
 *   Switch root popups with: popup_manager switch <item>
 *   Switch child popups with: popup_manager submenu <item>
 */

/* Hardcoded fallback lists */
static const char *FALLBACK_POPUP_ITEMS[] = {
  "apple_menu", "front_app", "clock", "system_info", "volume", "battery", "control_center"
};
static const size_t FALLBACK_POPUP_COUNT = sizeof(FALLBACK_POPUP_ITEMS) / sizeof(FALLBACK_POPUP_ITEMS[0]);

static const char *FALLBACK_SUBMENU_PARENTS[] = {
  "yaze.recent_roms", "emacs.recent_org"
};
static const size_t FALLBACK_SUBMENU_COUNT = sizeof(FALLBACK_SUBMENU_PARENTS) / sizeof(FALLBACK_SUBMENU_PARENTS[0]);

#define MAX_TOPOLOGY_NAMES 128
#define MAX_TOPOLOGY_RELATIONS 512
#define MAX_TOPOLOGY_NAME_LENGTH 127
#define MAX_SKETCHYBAR_PAYLOAD_ARGUMENTS \
  (MAX_TOPOLOGY_NAMES * 3 + MAX_TOPOLOGY_NAMES * 5 + 3)
#define MAX_SKETCHYBAR_TOKEN_BYTES 1024
#define MAX_SKETCHYBAR_PAYLOAD_BYTES (64 * 1024)

#ifdef __APPLE__
static const mach_msg_timeout_t MACH_SEND_TIMEOUT_MILLISECONDS = 50;
static const mach_msg_timeout_t MACH_RECEIVE_TIMEOUT_MILLISECONDS = 100;
#endif

typedef struct {
  char **items;
  size_t count;
} NameList;

typedef struct {
  char *target;
  char *ancestor;
} AncestorRelation;

typedef struct {
  AncestorRelation *items;
  size_t count;
} AncestorList;

typedef enum {
  MUTATION_DISMISS_ALL,
  MUTATION_SWITCH_ROOT,
  MUTATION_SWITCH_SUBMENU,
} PopupMutation;

typedef enum {
  MACH_DISPATCH_NOT_SENT,
  MACH_DISPATCH_CONFIRMED_SUCCESS,
  MACH_DISPATCH_SENT_UNCONFIRMED,
  MACH_DISPATCH_CONFIRMED_ERROR,
} MachDispatchResult;

typedef struct {
  uint8_t bytes[MAX_SKETCHYBAR_PAYLOAD_BYTES];
  size_t length;
  size_t arguments;
} SketchybarPayload;

#ifdef __APPLE__
struct barista_mach_message {
  mach_msg_header_t header;
  mach_msg_size_t descriptor_count;
  mach_msg_ool_descriptor_t descriptor;
};

struct barista_mach_buffer {
  struct barista_mach_message message;
  mach_msg_trailer_t trailer;
};
#endif

#ifdef BARISTA_POPUP_MANAGER_TESTING
static MachDispatchResult (*mach_dispatch_test_hook)(const SketchybarPayload *) = NULL;
static int (*cli_dispatch_test_hook)(const char *, char **, size_t, int) = NULL;
#endif

static NameList popup_items = {0};
static NameList submenu_parents = {0};
static AncestorList submenu_ancestors = {0};

static void free_list(NameList *list) {
  if (!list) return;
  for (size_t i = 0; i < list->count; i++) {
    free(list->items[i]);
  }
  free(list->items);
  list->items = NULL;
  list->count = 0;
}

static int list_contains(const NameList *list, const char *name) {
  if (!list || !name) return 0;
  for (size_t i = 0; i < list->count; i++) {
    if (strcmp(list->items[i], name) == 0) return 1;
  }
  return 0;
}

static int append_name(NameList *list, const char *name) {
  if (!list || !name || name[0] == '\0' || list_contains(list, name)) return 1;
  if (list->count >= MAX_TOPOLOGY_NAMES || strlen(name) > MAX_TOPOLOGY_NAME_LENGTH) {
    return 0;
  }
  char **next = realloc(list->items, (list->count + 1) * sizeof(*next));
  if (!next) return 0;
  list->items = next;
  list->items[list->count] = strdup(name);
  if (!list->items[list->count]) return 0;
  list->count++;
  return 1;
}

static void free_ancestor_list(AncestorList *list) {
  if (!list) return;
  for (size_t i = 0; i < list->count; i++) {
    free(list->items[i].target);
    free(list->items[i].ancestor);
  }
  free(list->items);
  list->items = NULL;
  list->count = 0;
}

static int append_ancestor(AncestorList *list, const char *target, const char *ancestor) {
  if (!list || !target || !ancestor || target[0] == '\0' || ancestor[0] == '\0'
      || strcmp(target, ancestor) == 0) {
    return 0;
  }
  if (strlen(target) > MAX_TOPOLOGY_NAME_LENGTH
      || strlen(ancestor) > MAX_TOPOLOGY_NAME_LENGTH) {
    return 0;
  }
  for (size_t i = 0; i < list->count; i++) {
    if (strcmp(list->items[i].target, target) == 0
        && strcmp(list->items[i].ancestor, ancestor) == 0) {
      return 1;
    }
  }
  if (list->count >= MAX_TOPOLOGY_RELATIONS) return 0;

  AncestorRelation *next = realloc(list->items, (list->count + 1) * sizeof(*next));
  if (!next) return 0;
  list->items = next;
  AncestorRelation *relation = &list->items[list->count];
  relation->target = strdup(target);
  relation->ancestor = strdup(ancestor);
  if (!relation->target || !relation->ancestor) {
    free(relation->target);
    free(relation->ancestor);
    relation->target = NULL;
    relation->ancestor = NULL;
    return 0;
  }
  list->count++;
  return 1;
}

static int is_target_ancestor(const char *candidate, const char *target) {
  if (!candidate || !target) return 0;
  for (size_t i = 0; i < submenu_ancestors.count; i++) {
    if (strcmp(submenu_ancestors.items[i].target, target) == 0
        && strcmp(submenu_ancestors.items[i].ancestor, candidate) == 0) {
      return 1;
    }
  }
  return 0;
}

static NameList load_list(const char *path, const char *fallback[], size_t fallback_count) {
  NameList result = {0};
  FILE *fp = fopen(path, "r");
  if (fp) {
    char *line = NULL;
    size_t capacity = 0;
    while (getline(&line, &capacity, fp) != -1) {
      line[strcspn(line, "\n\r")] = '\0';
      if (line[0] != '\0' && !append_name(&result, line)) {
        fprintf(stderr, "popup_manager: unable to load registry item\n");
        free(line);
        fclose(fp);
        free_list(&result);
        return result;
      }
    }
    free(line);
    fclose(fp);
    return result;
  }

  for (size_t i = 0; i < fallback_count; i++) {
    if (!append_name(&result, fallback[i])) {
      fprintf(stderr, "popup_manager: unable to load fallback item\n");
      free_list(&result);
      break;
    }
  }
  return result;
}

static int load_topology(const char *path) {
  FILE *fp = fopen(path, "r");
  if (!fp) return 0;

  const char *expected_generation = getenv("BARISTA_POPUP_TOPOLOGY_TOKEN");
  int generation_required = expected_generation && expected_generation[0] != '\0';
  NameList roots = {0};
  NameList children = {0};
  AncestorList ancestors = {0};
  char *line = NULL;
  size_t capacity = 0;
  int version_seen = 0;
  int generation_seen = 0;
  int topology_entry_seen = 0;
  int valid = 1;

  ssize_t line_length = 0;
  while ((line_length = getline(&line, &capacity, fp)) != -1) {
    size_t content_length = (size_t)line_length;
    if (memchr(line, '\0', content_length)
        || memchr(line, '\r', content_length)) {
      valid = 0;
      break;
    }
    if (content_length > 0 && line[content_length - 1] == '\n') {
      content_length--;
    }
    if (memchr(line, '\n', content_length)) {
      valid = 0;
      break;
    }
    line[content_length] = '\0';
    if (line[0] == '\0') continue;

    char *save = NULL;
    char *kind = strtok_r(line, "\t", &save);
    char *first = strtok_r(NULL, "\t", &save);
    char *second = strtok_r(NULL, "\t", &save);
    char *extra = strtok_r(NULL, "\t", &save);

    if (!version_seen) {
      version_seen = kind && first && !second && strcmp(kind, "version") == 0
        && strcmp(first, "1") == 0;
      if (!version_seen) valid = 0;
    } else if (kind && first && !second && strcmp(kind, "generation") == 0) {
      valid = !generation_seen && !topology_entry_seen;
      if (valid && generation_required) {
        valid = strcmp(first, expected_generation) == 0;
      }
      if (valid) generation_seen = 1;
    } else if (kind && first && !second && strcmp(kind, "root") == 0) {
      topology_entry_seen = 1;
      valid = append_name(&roots, first);
    } else if (kind && first && !second && strcmp(kind, "child") == 0) {
      topology_entry_seen = 1;
      valid = append_name(&children, first);
    } else if (kind && first && second && !extra && strcmp(kind, "ancestor") == 0) {
      topology_entry_seen = 1;
      valid = append_ancestor(&ancestors, first, second);
    } else {
      valid = 0;
    }

    if (!valid) break;
  }

  free(line);
  fclose(fp);
  if (!valid || !version_seen || (generation_required && !generation_seen)) {
    free_list(&roots);
    free_list(&children);
    free_ancestor_list(&ancestors);
    return 0;
  }

  popup_items = roots;
  submenu_parents = children;
  submenu_ancestors = ancestors;
  return 1;
}

static void load_lists(int click_mode) {
  const char *tmpdir = getenv("TMPDIR");
  if (!tmpdir) tmpdir = "/tmp";
  char path[PATH_MAX];

  int length = snprintf(
    path,
    sizeof(path),
    "%s/sketchybar_popup_topology",
    tmpdir
  );
  if (click_mode) {
    if (length > 0 && length < (int)sizeof(path)) {
      load_topology(path);
    }
    return;
  }

  length = snprintf(path, sizeof(path), "%s/sketchybar_popup_list", tmpdir);
  if (length > 0 && length < (int)sizeof(path)) {
    popup_items = load_list(path, FALLBACK_POPUP_ITEMS, FALLBACK_POPUP_COUNT);
  }
  length = snprintf(path, sizeof(path), "%s/sketchybar_submenu_list", tmpdir);
  if (length > 0 && length < (int)sizeof(path)) {
    submenu_parents = load_list(path, FALLBACK_SUBMENU_PARENTS, FALLBACK_SUBMENU_COUNT);
  }
}

static void clear_popup_state_directory(const char *path) {
  DIR *dir = opendir(path);
  if (!dir) return;
  struct dirent *entry = NULL;
  char item_path[PATH_MAX];
  while ((entry = readdir(dir)) != NULL) {
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;
    int length = snprintf(item_path, sizeof(item_path), "%s/%s", path, entry->d_name);
    if (length > 0 && length < (int)sizeof(item_path)) {
      unlink(item_path);
    }
  }
  closedir(dir);
  rmdir(path);
}

static void unlink_tmp_entry(const char *tmpdir, const char *name) {
  char path[PATH_MAX];
  int length = snprintf(path, sizeof(path), "%s/%s", tmpdir, name);
  if (length > 0 && length < (int)sizeof(path)) {
    unlink(path);
  }
}

static void clear_hover_state_files(void) {
  const char *tmpdir = getenv("TMPDIR");
  if (!tmpdir) tmpdir = "/tmp";

  unlink_tmp_entry(tmpdir, "sketchybar_submenu_active");
  unlink_tmp_entry(tmpdir, "sketchybar_parent_popup_lock");
}

static void clear_state_files(void) {
  const char *tmpdir = getenv("TMPDIR");
  if (!tmpdir) tmpdir = "/tmp";

  char popup_dir[PATH_MAX];
  int length = snprintf(
    popup_dir,
    sizeof(popup_dir),
    "%s/sketchybar_popup_state",
    tmpdir
  );
  if (length > 0 && length < (int)sizeof(popup_dir)) {
    clear_popup_state_directory(popup_dir);
  }
  clear_hover_state_files();
}

static int append_set(char **argv, size_t *index, const char *name, const char **properties,
                      size_t property_count) {
  if (!argv || !index || !name || name[0] == '\0') return 0;
  argv[(*index)++] = "--set";
  argv[(*index)++] = (char *)name;
  for (size_t i = 0; i < property_count; i++) {
    argv[(*index)++] = (char *)properties[i];
  }
  return 1;
}

static int environment_truthy(const char *value) {
  if (!value || value[0] == '\0') return 0;
  return strcmp(value, "1") == 0
    || strcasecmp(value, "true") == 0
    || strcasecmp(value, "yes") == 0
    || strcasecmp(value, "on") == 0;
}

#if defined(__APPLE__) || defined(BARISTA_POPUP_MANAGER_TESTING)
static int supported_bar_name(void) {
  const char *bar_name = getenv("BAR_NAME");
  return !bar_name || bar_name[0] == '\0' || strlen(bar_name) <= 128;
}

static int canonical_sketchybar_binary(const char *path, int explicitly_configured) {
  if (!path || path[0] == '\0') return 0;
  if (strcmp(path, "sketchybar") == 0) return !explicitly_configured;
  static const char *known_paths[] = {
    "/opt/homebrew/opt/sketchybar/bin/sketchybar",
    "/opt/homebrew/bin/sketchybar",
    "/usr/local/opt/sketchybar/bin/sketchybar",
    "/usr/local/bin/sketchybar",
  };
  for (size_t i = 0; i < sizeof(known_paths) / sizeof(known_paths[0]); i++) {
    if (strcmp(path, known_paths[i]) == 0) return 1;
  }
  return 0;
}
#endif

static int mach_transport_eligible(const char *sketchybar, int explicitly_configured) {
  if (environment_truthy(getenv("BARISTA_POPUP_MACH_DISABLE"))) return 0;
#if !defined(__APPLE__) && !defined(BARISTA_POPUP_MANAGER_TESTING)
  (void)sketchybar;
  (void)explicitly_configured;
  return 0;
#else
  return supported_bar_name()
    && canonical_sketchybar_binary(sketchybar, explicitly_configured);
#endif
}

static int build_sketchybar_payload(SketchybarPayload *payload,
                                    char **argv,
                                    size_t argc) {
  if (!payload || !argv || argc <= 1) return 0;
  memset(payload, 0, sizeof(*payload));

  for (size_t i = 1; i < argc; i++) {
    if (!argv[i]) return 0;
    size_t token_length = strnlen(argv[i], MAX_SKETCHYBAR_TOKEN_BYTES + 1);
    if (token_length > MAX_SKETCHYBAR_TOKEN_BYTES
        || payload->arguments >= MAX_SKETCHYBAR_PAYLOAD_ARGUMENTS
        || payload->length + token_length + 2 > sizeof(payload->bytes)) {
      return 0;
    }
    memcpy(payload->bytes + payload->length, argv[i], token_length);
    payload->length += token_length;
    payload->bytes[payload->length++] = 0;
    payload->arguments++;
  }
  payload->bytes[payload->length++] = 0;
  return payload->length >= 2
    && payload->bytes[payload->length - 1] == 0
    && payload->bytes[payload->length - 2] == 0;
}

#ifdef __APPLE__
static mach_port_t sketchybar_port(void) {
  const char *bar_name = getenv("BAR_NAME");
  if (!bar_name || bar_name[0] == '\0') {
    bar_name = "sketchybar";
  }
  char service_name[160];
  int written = snprintf(service_name, sizeof(service_name), "git.felix.%s", bar_name);
  if (written < 0 || (size_t)written >= sizeof(service_name)) return MACH_PORT_NULL;

  mach_port_t bootstrap_port = MACH_PORT_NULL;
  if (task_get_special_port(mach_task_self(), TASK_BOOTSTRAP_PORT, &bootstrap_port)
      != KERN_SUCCESS) {
    return MACH_PORT_NULL;
  }
  mach_port_t port = MACH_PORT_NULL;
  kern_return_t result = bootstrap_look_up(bootstrap_port, service_name, &port);
  mach_port_deallocate(mach_task_self(), bootstrap_port);
  return result == KERN_SUCCESS ? port : MACH_PORT_NULL;
}

static int response_status(const void *bytes, size_t size) {
  if (!bytes || size == 0 || size > MAX_SKETCHYBAR_PAYLOAD_BYTES) return -1;
  const char *response = bytes;
  if (memchr(response, '\0', size) == NULL) return -1;
  return strstr(response, "[!]") == NULL ? 1 : 0;
}
#endif

static MachDispatchResult dispatch_mach_payload(const SketchybarPayload *payload) {
#ifdef BARISTA_POPUP_MANAGER_TESTING
  if (mach_dispatch_test_hook) return mach_dispatch_test_hook(payload);
#endif
#ifdef __APPLE__
  if (!payload || payload->length < 2
      || payload->length > MAX_SKETCHYBAR_PAYLOAD_BYTES
      || payload->arguments == 0
      || payload->arguments > MAX_SKETCHYBAR_PAYLOAD_ARGUMENTS
      || payload->bytes[payload->length - 1] != 0
      || payload->bytes[payload->length - 2] != 0) {
    return MACH_DISPATCH_NOT_SENT;
  }

  for (int attempt = 0; attempt < 2; attempt++) {
    mach_port_t port = sketchybar_port();
    if (port == MACH_PORT_NULL) continue;

    mach_port_t response_port = MACH_PORT_NULL;
    mach_port_name_t task = mach_task_self();
    if (mach_port_allocate(task, MACH_PORT_RIGHT_RECEIVE, &response_port) != KERN_SUCCESS) {
      mach_port_deallocate(task, port);
      continue;
    }
    if (mach_port_insert_right(task,
                               response_port,
                               response_port,
                               MACH_MSG_TYPE_MAKE_SEND) != KERN_SUCCESS) {
      mach_port_mod_refs(task, response_port, MACH_PORT_RIGHT_RECEIVE, -1);
      mach_port_deallocate(task, port);
      continue;
    }

    struct barista_mach_message message = {0};
    message.header.msgh_remote_port = port;
    message.header.msgh_local_port = response_port;
    message.header.msgh_id = response_port;
    message.header.msgh_bits = MACH_MSGH_BITS_SET(
      MACH_MSG_TYPE_COPY_SEND,
      MACH_MSG_TYPE_MAKE_SEND,
      0,
      MACH_MSGH_BITS_COMPLEX);
    message.header.msgh_size = sizeof(message);
    message.descriptor_count = 1;
    message.descriptor.address = (void *)payload->bytes;
    message.descriptor.size = (mach_msg_size_t)payload->length;
    message.descriptor.copy = MACH_MSG_VIRTUAL_COPY;
    message.descriptor.deallocate = false;
    message.descriptor.type = MACH_MSG_OOL_DESCRIPTOR;

    mach_msg_return_t result = mach_msg(&message.header,
                                        MACH_SEND_MSG | MACH_SEND_TIMEOUT,
                                        sizeof(message),
                                        0,
                                        MACH_PORT_NULL,
                                        MACH_SEND_TIMEOUT_MILLISECONDS,
                                        MACH_PORT_NULL);
    mach_port_deallocate(task, port);
    if (result != MACH_MSG_SUCCESS) {
      mach_port_mod_refs(task, response_port, MACH_PORT_RIGHT_RECEIVE, -1);
      mach_port_deallocate(task, response_port);
      continue;
    }

    struct barista_mach_buffer buffer = {0};
    result = mach_msg(&buffer.message.header,
                      MACH_RCV_MSG | MACH_RCV_TIMEOUT,
                      0,
                      sizeof(buffer),
                      response_port,
                      MACH_RECEIVE_TIMEOUT_MILLISECONDS,
                      MACH_PORT_NULL);

    MachDispatchResult dispatch_result = MACH_DISPATCH_SENT_UNCONFIRMED;
    if (result == MACH_MSG_SUCCESS) {
      mach_msg_ool_descriptor_t descriptor = buffer.message.descriptor;
      if (buffer.message.descriptor_count == 1
          && descriptor.type == MACH_MSG_OOL_DESCRIPTOR
          && descriptor.address != NULL
          && descriptor.size > 0
          && descriptor.size <= MAX_SKETCHYBAR_PAYLOAD_BYTES) {
        int status = response_status(descriptor.address, descriptor.size);
        if (status > 0) dispatch_result = MACH_DISPATCH_CONFIRMED_SUCCESS;
        else if (status == 0) dispatch_result = MACH_DISPATCH_CONFIRMED_ERROR;
      }
      mach_msg_destroy(&buffer.message.header);
    }
    mach_port_mod_refs(task, response_port, MACH_PORT_RIGHT_RECEIVE, -1);
    mach_port_deallocate(task, response_port);

    /* The target mutation ends in popup.drawing=toggle. Once the kernel accepts
     * the message, retrying or exec fallback could toggle the target twice. */
    return dispatch_result;
  }
#else
  (void)payload;
#endif
  return MACH_DISPATCH_NOT_SENT;
}

static int run_sketchybar_cli(const char *sketchybar,
                              char **argv,
                              size_t argc,
                              int replace_process) {
#ifdef BARISTA_POPUP_MANAGER_TESTING
  if (cli_dispatch_test_hook) {
    return cli_dispatch_test_hook(sketchybar, argv, argc, replace_process);
  }
#else
  (void)argc;
#endif

  if (replace_process) {
    execvp(sketchybar, argv);
    fprintf(stderr, "popup_manager: exec failed: %s\n", strerror(errno));
    return 127;
  }

  pid_t pid = fork();
  if (pid < 0) {
    fprintf(stderr, "popup_manager: fork failed: %s\n", strerror(errno));
    return 1;
  }
  if (pid == 0) {
    execvp(sketchybar, argv);
    _exit(127);
  }

  int status = 0;
  while (waitpid(pid, &status, 0) < 0) {
    if (errno == EINTR) continue;
    fprintf(stderr, "popup_manager: waitpid failed: %s\n", strerror(errno));
    return 1;
  }
  return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}

static int run_sketchybar(PopupMutation mutation, const char *target, int replace_process) {
  static const char *popup_off[] = {"popup.drawing=off"};
  static const char *submenu_off[] = {
    "popup.drawing=off",
    "background.drawing=off",
    "background.color=0x00000000",
  };
  static const char *popup_toggle[] = {"popup.drawing=toggle"};

  size_t max_args = 2 + popup_items.count * 3 + submenu_parents.count * 5;
  if (target && target[0] != '\0') max_args += 3;
  char **argv = calloc(max_args, sizeof(*argv));
  if (!argv) {
    fprintf(stderr, "popup_manager: unable to allocate SketchyBar arguments\n");
    return 1;
  }

  const char *sketchybar = getenv("BARISTA_SKETCHYBAR_BIN");
  int explicitly_configured = sketchybar && sketchybar[0] != '\0';
  if (!explicitly_configured) sketchybar = "sketchybar";
  size_t argc = 0;
  argv[argc++] = (char *)sketchybar;

  if (mutation != MUTATION_SWITCH_SUBMENU) {
    for (size_t i = 0; i < popup_items.count; i++) {
      if (mutation == MUTATION_SWITCH_ROOT && target
          && strcmp(popup_items.items[i], target) == 0) {
        continue;
      }
      append_set(argv, &argc, popup_items.items[i], popup_off, 1);
    }
  }

  for (size_t i = 0; i < submenu_parents.count; i++) {
    if (mutation == MUTATION_SWITCH_SUBMENU && target
        && (strcmp(submenu_parents.items[i], target) == 0
            || is_target_ancestor(submenu_parents.items[i], target))) {
      continue;
    }
    append_set(argv, &argc, submenu_parents.items[i], submenu_off, 3);
  }

  if (mutation != MUTATION_DISMISS_ALL && target && target[0] != '\0') {
    append_set(argv, &argc, target, popup_toggle, 1);
  }
  argv[argc] = NULL;

  if (argc == 1) {
    free(argv);
    return 0;
  }

  if (mach_transport_eligible(sketchybar, explicitly_configured)) {
    SketchybarPayload payload = {0};
    if (build_sketchybar_payload(&payload, argv, argc)) {
      MachDispatchResult result = dispatch_mach_payload(&payload);
      if (result != MACH_DISPATCH_NOT_SENT) {
        free(argv);
        return result == MACH_DISPATCH_CONFIRMED_ERROR ? 1 : 0;
      }
    }
  }

  int status = run_sketchybar_cli(sketchybar, argv, argc, replace_process);
  free(argv);
  return status;
}

static int dismiss_all_popups(void) {
  int status = run_sketchybar(MUTATION_DISMISS_ALL, NULL, 0);
  clear_state_files();
  return status;
}

static int should_dismiss_on_event(const char *sender) {
  if (!sender || sender[0] == '\0') {
    return 0;
  }

  // Dismiss on space changes
  if (strcmp(sender, "space_change") == 0 ||
      strcmp(sender, "space_changed") == 0 ||
      strcmp(sender, "display_changed") == 0 ||
      strcmp(sender, "display_added") == 0 ||
      strcmp(sender, "display_removed") == 0) {
    return 1;
  }

  // Dismiss on mission control
  if (strcmp(sender, "mission_control_enter") == 0 ||
      strcmp(sender, "mission_control_exit") == 0) {
    return 1;
  }

  // Dismiss on system sleep/wake
  if (strcmp(sender, "system_woke") == 0) {
    return 1;
  }

  // Front-app churn can fire while clicking SketchyBar itself. Keep app-switch
  // dismissal opt-in so popup clicks do not open and immediately close.
  if (strcmp(sender, "front_app_switched") == 0) {
    const char *dismiss_on_app_switch = getenv("DISMISS_ON_APP_SWITCH");
    if (dismiss_on_app_switch && strcmp(dismiss_on_app_switch, "1") == 0) {
      return 1;
    }
  }

  return 0;
}

static void print_usage(const char *program) {
  fprintf(stderr, "Usage: %s [protocol|switch|submenu <item>]\n", program);
}

int main(int argc, char **argv) {
  int status = 0;

  if (argc == 2 && strcmp(argv[1], "protocol") == 0) {
    puts("barista-popup-switch-v1");
    return 0;
  }

  if (argc > 1) {
    if (argc != 3 || !argv[2] || argv[2][0] == '\0') {
      print_usage(argv[0]);
      return 2;
    }

    PopupMutation mutation;
    if (strcmp(argv[1], "switch") == 0) {
      mutation = MUTATION_SWITCH_ROOT;
    } else if (strcmp(argv[1], "submenu") == 0) {
      mutation = MUTATION_SWITCH_SUBMENU;
    } else {
      print_usage(argv[0]);
      return 2;
    }

    load_lists(1);
    clear_hover_state_files();
    status = run_sketchybar(mutation, argv[2], 1);
    free_list(&popup_items);
    free_list(&submenu_parents);
    free_ancestor_list(&submenu_ancestors);
    return status;
  }

  load_lists(0);
  const char *sender = getenv("SENDER");

  if (should_dismiss_on_event(sender)) {
    status = dismiss_all_popups();
  }

  free_list(&popup_items);
  free_list(&submenu_parents);
  free_ancestor_list(&submenu_ancestors);
  return status;
}
