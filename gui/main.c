#include "../helpers/event_providers/sketchybar.h"

int main(int argc, char **argv) {

  if (ImGui::ColorEdit3("Bar Color", bar_color)) {
    char cmd[256];
    snprintf(cmd, sizeof(cmd),
             "--bar color=0x%02X%02X%02XFF",
             (int)(bar_color[0]*255),
             (int)(bar_color[1]*255),
             (int)(bar_color[2]*255));
    sketchybar(cmd);
  }

  return EXIT_SUCCESS;
}