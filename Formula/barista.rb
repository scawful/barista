# Homebrew Formula for Barista
# This file should be placed in: homebrew-barista/Formula/barista.rb
#
# To use:
#   1. Create GitHub repo: homebrew-barista
#   2. Copy this file to: homebrew-barista/Formula/barista.rb
#   3. Update version and sha256 for each release
#   4. Users install with: brew tap scawful/barista && brew install barista

class Barista < Formula
  desc "Brewing the perfect macOS status bar experience"
  homepage "https://github.com/scawful/barista"
  url "https://github.com/scawful/barista/archive/v2.0.0.tar.gz"
  # Calculate SHA256 with: shasum -a 256 <archive.tar.gz>
  sha256 "PLACEHOLDER_SHA256"
  license "MIT"
  version "2.0.0"

  depends_on "cmake" => :build
  depends_on "felixkratz/formulae/sketchybar" => :recommended
  depends_on "lua" => :recommended
  depends_on "jq" => :recommended
  depends_on "koekeishiya/formulae/yabai" => :optional
  depends_on "koekeishiya/formulae/skhd" => :optional

  def install
    # Build C components and GUI
    system "cmake", "-B", "build", "-S", ".", "-DCMAKE_BUILD_TYPE=Release"
    system "cmake", "--build", "build", "-j", Hardware::CPU.cores

    # Install configuration files
    config_dir = Pathname.new(ENV["HOME"])/".config/sketchybar"
    config_dir.mkpath

    # Copy configuration files (preserve existing if present)
    unless (config_dir/"main.lua").exist?
      cp_r Dir["*.lua"], config_dir
      cp_r "modules", config_dir
      cp_r "profiles", config_dir
      cp_r "themes", config_dir
      cp_r "plugins", config_dir
      cp_r "data", config_dir
      cp_r "launch_agents", config_dir
      cp_r "helpers", config_dir
    end

    # Install binaries
    bin.install Dir["build/bin/*"]
    
    # Install helpers
    (config_dir/"helpers").install Dir["helpers/*.sh"]
    (config_dir/"bin").install Dir["build/bin/*"]

    # Install documentation
    doc.install Dir["docs"]
  end

  def post_install
    # Create sketchybarrc if it doesn't exist
    config_dir = Pathname.new(ENV["HOME"])/".config/sketchybar"
    sketchybarrc = config_dir/"sketchybarrc"
    
    unless sketchybarrc.exist?
      sketchybarrc.write <<~EOF
        #!/usr/bin/env lua
        -- SketchyBar Configuration Entry Point
        local HOME = os.getenv("HOME")
        local CONFIG_DIR = HOME .. "/.config/sketchybar"
        dofile(CONFIG_DIR .. "/main.lua")
      EOF
      sketchybarrc.chmod 0755
    end

    # Create initial state.json if it doesn't exist
    state_file = config_dir/"state.json"
    unless state_file.exist?
      state_file.write <<~JSON
        {
          "profile": "minimal",
          "widgets": {
            "clock": true,
            "battery": true,
            "network": true,
            "system_info": true,
            "volume": true,
            "yabai_status": true
          },
          "appearance": {
            "bar_height": 32,
            "corner_radius": 9,
            "bar_color": "0xC021162F",
            "blur_radius": 30,
            "widget_scale": 1.0
          },
          "integrations": {
            "yaze": {"enabled": false},
            "emacs": {"enabled": false},
            "halext": {"enabled": false}
          }
        }
      JSON
    end

    # Run post-update script
    if (config_dir/"helpers/post_update.sh").exist?
      system "#{config_dir}/helpers/post_update.sh"
    end
  end

  def caveats
    <<~EOS
      Barista has been installed to ~/.config/sketchybar

      Next steps:
      1. Grant Accessibility permissions:
         ~/.config/sketchybar/helpers/setup_permissions.sh
      
      2. Configure system permissions for yabai/skhd (if using):
         - System Settings > Privacy & Security > Accessibility
         - Add: SketchyBar, Yabai, skhd
         - For Yabai: Also grant Screen Recording permission
      
      3. Choose a profile: edit ~/.config/sketchybar/state.json
         Set "profile" to: "minimal", "personal", "work", or custom
      
      4. Start services:
         brew services start sketchybar
         # Optional:
         brew services start yabai
         brew services start skhd
      
      5. Install launch agent (optional, for unified management):
         ~/.config/sketchybar/bin/install-launch-agent

      Documentation: #{doc}
      
      For updates: brew upgrade barista
    EOS
  end

  test do
    # Test that binaries were installed
    assert_predicate bin/"config_menu_v2", :exist?
    assert_predicate bin/"icon_manager", :exist?
  end
end

