# License Analysis for Barista

## Executive Summary

This document analyzes the licenses of the core dependencies (SketchyBar, yabai, skhd) and provides recommendations for the barista project.

## Dependency Licenses

### SketchyBar - GPL-3.0-only
- **License**: GNU General Public License version 3
- **Type**: Strong copyleft license
- **Key Requirements**:
  - Must preserve copyright notices
  - Must provide source code when distributing
  - Derivative works must also be GPL-3.0
  - Cannot be sublicensed
- **Commercial Use**: ✅ **Allowed** - Can be used commercially
- **License Text**: https://github.com/FelixKratz/SketchyBar/blob/master/LICENSE.md

### skhd - MIT License
- **License**: MIT License
- **Type**: Permissive license
- **Key Requirements**:
  - Must include copyright notice and license text
- **Commercial Use**: ✅ **Allowed** - Very permissive
- **Modifications**: Can be relicensed
- **Repository**: https://github.com/koekeishiya/skhd

### yabai - MIT License
- **License**: MIT License
- **Type**: Permissive license
- **Key Requirements**:
  - Must include copyright notice and license text
- **Commercial Use**: ✅ **Allowed** - Very permissive
- **Modifications**: Can be relicensed
- **Repository**: https://github.com/koekeishiya/yabai

## Impact on Barista

### Relationship to Dependencies
Barista is a **configuration tool** for SketchyBar, not a derivative work:
- Barista provides Lua configuration scripts
- Barista calls SketchyBar as an external program
- Barista does not link against SketchyBar code
- Barista does not modify SketchyBar source code
- Barista does not bundle or redistribute SketchyBar binaries

### GPL-3.0 Implications
Since barista is:
1. A **separate work** that configures SketchyBar
2. **Not linking** to SketchyBar libraries
3. **Not modifying** SketchyBar source
4. **Not distributing** SketchyBar binaries

The GPL-3.0 license of SketchyBar **does not require** barista to be GPL-licensed.

**Legal Precedent**: Configuration files, scripts, and orchestration tools that interact with GPL software through standard interfaces (like command-line APIs) are generally considered separate works, not derivatives.

## Recommended License for Barista

### Primary Recommendation: MIT License

**Reasons**:
1. ✅ **Compatible** with all dependencies
2. ✅ **Simple** and widely understood
3. ✅ **Permissive** - allows maximum reuse
4. ✅ **Commercial-friendly** - can be used in commercial products
5. ✅ **Matches** yabai and skhd ecosystem licenses
6. ✅ **Low barrier** for contributions

**MIT License allows**:
- ✅ Commercial use
- ✅ Modification
- ✅ Distribution
- ✅ Private use
- ✅ Sublicensing

**MIT License requires**:
- ⚠️ Include copyright notice
- ⚠️ Include license text

### Alternative: Apache 2.0
If you want stronger patent protection, Apache 2.0 is another excellent choice:
- Includes explicit patent grant
- More corporate-friendly
- Still very permissive
- Slightly more complex than MIT

## Commercial Use Scenarios

### ✅ What You CAN Do

1. **Use barista commercially**
   - In your own company
   - For client projects
   - In commercial products

2. **Sell barista configurations**
   - Charge for custom configurations
   - Offer premium themes/profiles
   - Provide support services

3. **Bundle with commercial products**
   - Include in commercial software
   - Ship as part of a paid product
   - Use in proprietary systems

4. **Create derivatives**
   - Fork and modify
   - Build commercial tools on top
   - Create proprietary extensions

### ⚠️ What You MUST Do

1. **Include barista license** in distributions
2. **Include copyright notices** for:
   - barista (your code)
   - Note dependencies on SketchyBar, yabai, skhd
3. **Provide instructions** for users to install dependencies:
   ```bash
   # Users must separately install:
   brew install felixkratz/formulae/sketchybar
   brew install koekeishiya/formulae/yabai
   brew install koekeishiya/formulae/skhd
   ```

### ❌ What You CANNOT Do

1. **Redistribute SketchyBar binaries** without GPL compliance
   - Don't bundle SketchyBar executables
   - Don't modify and redistribute SketchyBar without GPL
2. **Remove copyright notices** from any component
3. **Claim you wrote** the dependency tools

## Integration with halext-org Ecosystem

If you're creating a Homebrew tap for halext-org:

```ruby
class Barista < Formula
  desc "Modular SketchyBar configuration with native control panel"
  homepage "https://github.com/scawful/barista"
  url "https://github.com/scawful/barista/archive/v1.0.0.tar.gz"
  license "MIT"

  depends_on "sketchybar"  # Users install separately
  depends_on "yabai"       # Users install separately
  depends_on "skhd"        # Users install separately

  # Installation logic...
end
```

This approach:
- ✅ Clearly states dependencies
- ✅ Doesn't redistribute GPL binaries
- ✅ Lets users install dependencies separately
- ✅ Maintains GPL compliance
- ✅ Allows MIT licensing for barista

## Recommended License Text

Add this to your `LICENSE` file:

```
MIT License

Copyright (c) 2025 [Your Name/Organization]

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Attribution in README

Add a section to your README.md:

```markdown
## Dependencies

Barista requires the following tools to be installed separately:

- [SketchyBar](https://github.com/FelixKratz/SketchyBar) (GPL-3.0) - macOS status bar
- [yabai](https://github.com/koekeishiya/yabai) (MIT) - Tiling window manager
- [skhd](https://github.com/koekeishiya/skhd) (MIT) - Hotkey daemon

## Legal

Barista is a configuration tool for SketchyBar and does not contain or modify
any SketchyBar source code. Users must install SketchyBar separately and comply
with its GPL-3.0 license.
```

## Summary

✅ **You CAN use barista commercially** with an MIT license because:
1. Barista is a configuration tool, not a derivative of SketchyBar
2. It doesn't link to or modify GPL code
3. It requires users to install dependencies separately
4. Configuration scripts are separate works

✅ **Recommended Actions**:
1. License barista under MIT
2. Document dependency licenses in README
3. Don't bundle SketchyBar binaries
4. Include clear attribution
5. Provide installation instructions for dependencies

📋 **Best Practice**: Always consult with a lawyer for specific commercial use cases, but this analysis provides a solid foundation for understanding your licensing options.
