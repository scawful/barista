# Homebrew Tap Strategy

Documentation for creating a Homebrew tap for halext-org and related tools.

## Overview

A Homebrew tap is a third-party repository that provides "formulae" (package definitions) for installing software via `brew`. Creating a tap allows users to easily install your software and its dependencies.

## Proposed Repository Structure

```
homebrew-halext/
├── Formula/
│   ├── halext-org.rb          # Main halext-org server
│   ├── halext-cli.rb           # Command-line client
│   └── sketchybar-halext.rb    # SketchyBar integration plugin
├── Casks/
│   └── halext-desktop.rb       # GUI application (if applicable)
└── README.md
```

## Creating the Tap

### 1. Create Repository

```bash
# Create GitHub repository
gh repo create homebrew-halext --public

# Clone and setup
git clone https://github.com/scawful/homebrew-halext
cd homebrew-halext
mkdir -p Formula Casks
```

### 2. Write Formula

#### halext-org.rb

```ruby
class HalextOrg < Formula
  desc "Task management and calendar system with LLM integration"
  homepage "https://github.com/scawful/halext-org"
  url "https://github.com/scawful/halext-org/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "..." # Calculate with: shasum -a 256 archive.tar.gz
  license "MIT"

  depends_on "node@20"
  depends_on "postgresql@15"
  depends_on "redis"

  def install
    system "npm", "install", *Language::Node.std_npm_install_args(libexec)
    bin.install_symlink Dir["#{libexec}/bin/*"]

    # Install config template
    (etc/"halext-org").install "config/default.json" => "config.json" unless (etc/"halext-org/config.json").exist?
  end

  service do
    run [opt_bin/"halext-org", "start"]
    keep_alive true
    working_dir var/"halext-org"
    log_path var/"log/halext-org.log"
    error_log_path var/"log/halext-org.error.log"
  end

  test do
    system "#{bin}/halext-org", "--version"
  end
end
```

#### halext-cli.rb

```ruby
class HalextCli < Formula
  desc "Command-line client for halext-org"
  homepage "https://github.com/scawful/halext-cli"
  url "https://github.com/scawful/halext-cli/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "..."
  license "MIT"

  depends_on "rust" => :build

  def install
    system "cargo", "install", *std_cargo_args
  end

  test do
    system "#{bin}/halext", "--version"
  end
end
```

#### sketchybar-halext.rb

```ruby
class SketchybarHalext < Formula
  desc "SketchyBar integration for halext-org"
  homepage "https://github.com/scawful/sketchybar-config"
  url "https://github.com/scawful/sketchybar-config/releases/download/v1.0.0/halext-integration.tar.gz"
  sha256 "..."
  license "MIT"

  depends_on "halext-org"
  depends_on "felixkratz/formulae/sketchybar"
  depends_on "lua"

  def install
    # Install Lua module
    (share/"sketchybar/modules/integrations").install "modules/integrations/halext.lua"

    # Install plugin script
    (share/"sketchybar/plugins").install "plugins/halext_menu.sh"

    # Install documentation
    doc.install "docs/HALEXT_INTEGRATION.md"
  end

  def caveats
    <<~EOS
      SketchyBar halext-org integration installed.

      To enable:
      1. Add to your sketchybarrc or main.lua:
         require("modules.integrations.halext")

      2. Configure in state.json:
         {
           "integrations": {
             "halext": {
               "enabled": true,
               "server_url": "http://localhost:3000",
               "api_key": "your-key"
             }
           }
         }

      3. Reload SketchyBar:
         brew services restart sketchybar

      Documentation: #{doc}/HALEXT_INTEGRATION.md
    EOS
  end

  test do
    assert_predicate share/"sketchybar/modules/integrations/halext.lua", :exist?
  end
end
```

### 3. Publish Tap

```bash
git add .
git commit -m "Initial formulae for halext-org ecosystem"
git push origin main
```

### 4. Usage

Users can then install with:

```bash
# Add tap
brew tap scawful/halext

# Install packages
brew install halext-org
brew install halext-cli
brew install sketchybar-halext

# Start service
brew services start halext-org
```

## Formula Best Practices

### 1. Versioning

```ruby
# Use semantic versioning
version "1.0.0"

# Update URL for each release
url "https://github.com/scawful/halext-org/archive/refs/tags/v#{version}.tar.gz"
```

### 2. Dependencies

```ruby
# Build dependencies
depends_on "rust" => :build
depends_on "node@20" => :build

# Runtime dependencies
depends_on "postgresql@15"
depends_on "redis"

# Optional dependencies
depends_on "emacs" => :optional
```

### 3. Services

```ruby
service do
  run [opt_bin/"halext-org", "start", "--config", etc/"halext-org/config.json"]
  keep_alive true
  working_dir var/"halext-org"
  log_path var/"log/halext-org.log"
  error_log_path var/"log/halext-org.error.log"
  environment_variables PATH: std_service_path_env
end
```

### 4. Post-Install Messages

```ruby
def caveats
  <<~EOS
    Configuration file: #{etc}/halext-org/config.json

    To start service:
      brew services start halext-org

    To configure:
      1. Edit #{etc}/halext-org/config.json
      2. Restart service: brew services restart halext-org

    Documentation: #{doc}/README.md
  EOS
end
```

## Maintenance

### Updating Formulae

```bash
# Update version
vim Formula/halext-org.rb
# Change version = "1.0.0" to "1.1.0"
# Update URL
# Calculate new SHA256

# Test locally
brew uninstall halext-org
brew install --build-from-source ./Formula/halext-org.rb

# Commit and push
git commit -am "halext-org: update to 1.1.0"
git push
```

### Audit Formula

```bash
# Check formula quality
brew audit --strict Formula/halext-org.rb

# Test installation
brew install --build-from-source Formula/halext-org.rb

# Test uninstallation
brew uninstall halext-org
```

## Integration with SketchyBar Configuration

### Option 1: Formula

Good for: Compiled components, standalone tools

```ruby
class SketchybarConfig < Formula
  desc "Advanced SketchyBar configuration with integrations"
  homepage "https://github.com/scawful/sketchybar-config"
  url "https://github.com/scawful/sketchybar-config/archive/v1.0.0.tar.gz"
  sha256 "..."

  depends_on "felixkratz/formulae/sketchybar"
  depends_on "lua"

  def install
    # Install configuration
    (share/"sketchybar").install Dir["*"]

    # Build C helpers
    cd "helpers" do
      system "make", "clean", "install", "PREFIX=#{prefix}"
    end

    # Build GUI
    cd "gui" do
      system "make", "clean", "all"
      bin.install "bin/config_menu_v2"
    end
  end

  def post_install
    # Create config symlink
    config_dir = Pathname.new(ENV["HOME"])/"/.config/sketchybar"
    config_dir.mkpath

    # Copy if not exists
    unless (config_dir/"main.lua").exist?
      cp_r share/"sketchybar/.", config_dir
    end
  end

  def caveats
    <<~EOS
      Configuration installed to: ~/.config/sketchybar

      To use:
        1. Restart SketchyBar: brew services restart sketchybar
        2. Open control panel: Shift + Click Apple menu icon

      Documentation: #{share}/sketchybar/docs/
    EOS
  end
end
```

### Option 2: One-Line Installer

Keep it simple for users:

```bash
# In README.md
brew tap scawful/halext
brew install sketchybar-config
```

## CI/CD Integration

### GitHub Actions for Tap

```yaml
# .github/workflows/tests.yml
name: Test Formulae

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up Homebrew
        uses: Homebrew/actions/setup-homebrew@master

      - name: Test formulae
        run: |
          brew tap scawful/halext ${{ github.workspace }}
          brew audit --strict Formula/*.rb
          brew install --build-from-source Formula/halext-org.rb
          brew test halext-org
```

## Publishing Releases

### 1. Tag Release

```bash
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0
```

### 2. Create GitHub Release

```bash
gh release create v1.0.0 \
  --title "Version 1.0.0" \
  --notes "See CHANGELOG.md for details"
```

### 3. Update Formula

```bash
# Calculate SHA256
curl -L https://github.com/scawful/halext-org/archive/v1.0.0.tar.gz | shasum -a 256

# Update formula
vim Formula/halext-org.rb
# Update version and sha256

# Commit
git commit -am "halext-org: update to 1.0.0"
git push
```

## Resources

- [Homebrew Formula Cookbook](https://docs.brew.sh/Formula-Cookbook)
- [Homebrew Acceptable Formulae](https://docs.brew.sh/Acceptable-Formulae)
- [Homebrew Node for Formula Authors](https://docs.brew.sh/Node-for-Formula-Authors)
- [Homebrew Python for Formula Authors](https://docs.brew.sh/Python-for-Formula-Authors)

## Future Considerations

1. **Core Tap Submission**: Once stable, consider submitting to homebrew/core
2. **Cask for GUI**: If building native macOS app, use Cask instead of Formula
3. **Bottle Building**: Pre-compile binaries for faster installation
4. **Livecheck**: Auto-detect new versions

```ruby
livecheck do
  url :stable
  strategy :github_latest
end
```

## Conclusion

A Homebrew tap makes distribution simple and professional. Users can install with a single command, and updates are handled through the familiar `brew upgrade` workflow.

Start with a simple tap, test thoroughly, and expand as the project grows.
