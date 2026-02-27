# Middleware Feature and File Filtering

This document explains the feature-based filtering system for middleware components in RDK image assembler builds.

## Overview

The filtering system provides two levels of control for middleware components based on `DISTRO_FEATURES`:

1. **Package-Level Filtering**: Prevents entire IPK packages from being installed
2. **File-Level Filtering**: Removes specific files from installed packages during rootfs creation

## Architecture

```
DISTRO_FEATURES (product.inc)
         |
         v
┌────────────────────────────────────────────────────┐
│ rdk-assembler-post-rootfs-hooks.bbclass            │
│                                                     │
│  ┌──────────────────────────────────────┐          │
│  │ Package Filtering (Parse Time)       │          │
│  │ - Reads: middleware-feature-mapping  │          │
│  │ - Sets: MIDDLEWARE_PACKAGES_TO_EXCLUDE          │
│  └──────────────────────────────────────┘          │
│                                                     │
│  ┌──────────────────────────────────────┐          │
│  │ File Filtering (Parse Time)          │          │
│  │ - Reads: middleware-file-filter.conf │          │
│  │ - Sets: MIDDLEWARE_FILES_TO_REMOVE   │          │
│  └──────────────────────────────────────┘          │
│                                                     │
│  ┌──────────────────────────────────────┐          │
│  │ File Removal (do_rootfs time)        │          │
│  │ - Function: remove_feature_filtered_files()     │
│  │ - Removes files from IMAGE_ROOTFS    │          │
│  └──────────────────────────────────────┘          │
└────────────────────────────────────────────────────┘
         |
         v
IMAGE (rdk-fullstack-image.bb)
```

## Package-Level Filtering

### How It Works

1. **Configuration** ([conf/middleware-feature-mapping.conf](conf/middleware-feature-mapping.conf))
   ```bitbake
   # Feature name: nuance
   MIDDLEWARE_FEATURE_nuance = "enable_nuance"
   MIDDLEWARE_FEATURE_nuance_PACKAGES = " \
       nuanceeve \
   "
   
   MIDDLEWARE_AVAILABLE_FEATURES = "nuance"
   ```

2. **Processing** (Anonymous Python function in bbclass)
   - Runs during image recipe parsing
   - Checks if `enable_nuance` is in `DISTRO_FEATURES`
   - If missing, adds `nuanceeve` to `MIDDLEWARE_PACKAGES_TO_EXCLUDE`

3. **Application** (rdk-fullstack-image.bb)
   ```bitbake
   BAD_RECOMMENDATIONS += "${MIDDLEWARE_PACKAGES_TO_EXCLUDE}"
   ```
   - `BAD_RECOMMENDATIONS` prevents installation of packages listed as `RRECOMMENDS`
   - Packages are never downloaded or installed

### Requirements

- Target package must be listed as `RRECOMMENDS` (not `RDEPENDS`) in packagegroup
- Example in `packagegroup-middleware-layer.bb`:
  ```bitbake
  RRECOMMENDS:${PN} += "nuanceeve"  # Can be excluded
  # NOT: RDEPENDS:${PN} += "nuanceeve"  # Cannot be excluded
  ```

### When to Use Package Filtering

- Exclude entire middleware components/services
- Component is packaged as standalone IPK
- No other packages depend on it (runtime)
- Want to save image space and avoid installation entirely

## File-Level Filtering

### How It Works

1. **Configuration** ([conf/middleware-file-filter.conf](conf/middleware-file-filter.conf))
   ```bitbake
   # Feature name: motiondetector
   MIDDLEWARE_FILE_FILTER_motiondetector = "motion_detector"
   MIDDLEWARE_FILE_FILTER_motiondetector_FILES = " \
       /usr/lib/wpeframework/plugins/libWPEFrameworkMotionDetection.so* \
       /etc/WPEFramework/plugins/MotionDetection.json \
       /usr/share/WPEFramework/MotionDetection/* \
   "
   
   MIDDLEWARE_FILE_FILTER_FEATURES = "motiondetector"
   ```

2. **Processing** (Anonymous Python function + shell function)
   - **Parse time**: Builds list of file patterns to remove
   - **Rootfs time**: `remove_feature_filtered_files()` shell function executes
   - Removes files from `${IMAGE_ROOTFS}` based on patterns

3. **Execution** (During `do_rootfs` task)
   ```bash
   ROOTFS_POSTPROCESS_COMMAND += "remove_feature_filtered_files; "
   ```

### File Pattern Support

- **Exact paths**: `/etc/WPEFramework/plugins/MotionDetection.json`
- **Wildcards**: `/usr/lib/wpeframework/plugins/libWPEFrameworkMotionDetection.so*`
  - Uses `find` with `-path` for pattern matching
- **Directories**: `/usr/share/WPEFramework/MotionDetection/*`
  - Removes all files in directory

### When to Use File Filtering

- IPK contains both required and optional files
- Cannot exclude entire package (has dependencies)
- Want to remove specific plugins/configs from multi-component package
- Package is already installed but contains feature-specific files

## Configuration Files

### middleware-feature-mapping.conf

Location: `meta-rdk-images/conf/middleware-feature-mapping.conf`

**Format:**
```bitbake
# Define the DISTRO_FEATURE required for this feature
MIDDLEWARE_FEATURE_<feature_name> = "distro_feature_name"

# List packages that should be excluded if feature is disabled
MIDDLEWARE_FEATURE_<feature_name>_PACKAGES = " \
    package1 \
    package2 \
"

# Register the feature (space-separated list)
MIDDLEWARE_AVAILABLE_FEATURES = " \
    <feature_name> \
"
```

**Example - Adding Netflix filtering:**
```bitbake
MIDDLEWARE_FEATURE_netflix = "enable_netflix"
MIDDLEWARE_FEATURE_netflix_PACKAGES = " \
    netflix-plugin \
    netflix-libs \
"

MIDDLEWARE_AVAILABLE_FEATURES = " \
    nuance \
    netflix \
"
```

### middleware-file-filter.conf

Location: `meta-rdk-images/conf/middleware-file-filter.conf`

**Format:**
```bitbake
# Define the DISTRO_FEATURE required for this file group
MIDDLEWARE_FILE_FILTER_<feature_name> = "distro_feature_name"

# List file patterns to remove if feature is disabled
MIDDLEWARE_FILE_FILTER_<feature_name>_FILES = " \
    /path/to/file1 \
    /path/to/wildcard* \
    /path/to/dir/* \
"

# Register the file filter (space-separated list)
MIDDLEWARE_FILE_FILTER_FEATURES = " \
    <feature_name> \
"
```

**Example - Adding HDR filtering:**
```bitbake
MIDDLEWARE_FILE_FILTER_hdr = "enable_hdr"
MIDDLEWARE_FILE_FILTER_hdr_FILES = " \
    /usr/lib/wpeframework/plugins/libWPEFrameworkHDR.so* \
    /etc/WPEFramework/plugins/HDR.json \
"

MIDDLEWARE_FILE_FILTER_FEATURES = " \
    motiondetector \
    hdr \
"
```

## Adding New Filters

### Step 1: Identify What to Filter

**For Package-Level:**
- Identify the IPK package name
- Verify it's listed as `RRECOMMENDS` in packagegroup
- Choose a meaningful `DISTRO_FEATURE` name

**For File-Level:**
- Find files in rootfs that should be conditional
- Determine file patterns (exact paths or wildcards)
- Choose a meaningful `DISTRO_FEATURE` name

### Step 2: Update Configuration

**For Package-Level Filtering:**

Edit `meta-rdk-images/conf/middleware-feature-mapping.conf`:
```bitbake
# Add feature definition
MIDDLEWARE_FEATURE_myfeature = "enable_myfeature"
MIDDLEWARE_FEATURE_myfeature_PACKAGES = " \
    my-package-name \
"

# Update the feature list
MIDDLEWARE_AVAILABLE_FEATURES = " \
    nuance \
    myfeature \
"
```

**For File-Level Filtering:**

Edit `meta-rdk-images/conf/middleware-file-filter.conf`:
```bitbake
# Add file filter definition
MIDDLEWARE_FILE_FILTER_myfeature = "enable_myfeature"
MIDDLEWARE_FILE_FILTER_myfeature_FILES = " \
    /path/to/files/* \
"

# Update the filter list
MIDDLEWARE_FILE_FILTER_FEATURES = " \
    motiondetector \
    myfeature \
"
```

### Step 3: Configure Product

Edit your product configuration (e.g., `product.inc`):

**To ENABLE the feature (keep packages/files):**
```bitbake
DISTRO_FEATURES += "enable_myfeature"
```

**To DISABLE the feature (remove packages/files):**
```bitbake
# Simply omit the DISTRO_FEATURE - filtering happens automatically
```

### Step 4: Test

**Package filtering test:**
```bash
# Check what will be excluded
bitbake-getvar -r rdk-fullstack-image MIDDLEWARE_PACKAGES_TO_EXCLUDE

# Build and verify package is not in image
bitbake rdk-fullstack-image
ls tmp-debug/work/*/rdk-fullstack-image/*/rootfs/ | grep my-package
```

**File filtering test:**
```bash
# Check what files will be removed
bitbake-getvar -r rdk-fullstack-image MIDDLEWARE_FILES_TO_REMOVE

# Build and verify files are removed
bitbake rdk-fullstack-image
find tmp-debug/work/*/rdk-fullstack-image/*/rootfs/ -name "myfile*"
```

## Examples

### Example 1: Disable Nuance Voice

**Goal**: Remove nuanceeve package when voice control not needed

**Configuration**: Already configured in middleware-feature-mapping.conf

**To disable:**
```bitbake
# In product.inc - remove or comment out:
# DISTRO_FEATURES += "enable_nuance"
```

**Result**: 
- `nuanceeve` package not installed
- BAD_RECOMMENDATIONS prevents download and installation

### Example 2: Remove Motion Detector

**Goal**: Remove motion detection plugin files when not needed

**Configuration**: Already configured in middleware-file-filter.conf

**To disable:**
```bitbake
# In product.inc - omit:
# DISTRO_FEATURES += "motion_detector"
```

**Result**: 
- Files removed during rootfs post-processing:
  - `/usr/lib/wpeframework/plugins/libWPEFrameworkMotionDetection.so*`
  - `/etc/WPEFramework/plugins/MotionDetection.json`
  - `/usr/share/WPEFramework/MotionDetection/*`
- Empty directories cleaned up

### Example 3: Add YouTube Filtering

**Scenario**: YouTube plugin should only be installed on devices with `enable_youtube` flag

**Step 1**: Update middleware-feature-mapping.conf
```bitbake
MIDDLEWARE_FEATURE_youtube = "enable_youtube"
MIDDLEWARE_FEATURE_youtube_PACKAGES = " \
    youtube-tv \
"

MIDDLEWARE_AVAILABLE_FEATURES = " \
    nuance \
    youtube \
"
```

**Step 2**: Update packagegroup (if needed)
```bitbake
# In packagegroup-middleware-layer.bb
RRECOMMENDS:${PN} += "youtube-tv"
```

**Step 3**: Enable in product
```bitbake
# In product.inc for devices that need YouTube
DISTRO_FEATURES += "enable_youtube"
```

## Debugging

### Check Variable Values

```bash
# See what packages will be excluded
bitbake-getvar -r rdk-fullstack-image MIDDLEWARE_PACKAGES_TO_EXCLUDE

# See what files will be removed
bitbake-getvar -r rdk-fullstack-image MIDDLEWARE_FILES_TO_REMOVE

# Check current DISTRO_FEATURES
bitbake-getvar -r rdk-fullstack-image DISTRO_FEATURES
```

### Build Logs

Look for filtering messages in build output:

**Package filtering:**
```
NOTE: === Middleware Feature Filtering ===
NOTE: Available features to filter: nuance
NOTE: ✓ Feature "nuance" ENABLED (DISTRO_FEATURE "enable_nuance" present)
NOTE: === No packages to exclude ===
```

**File filtering:**
```
NOTE: === Middleware File Filtering ===
NOTE: Available file filter features: motiondetector
NOTE: ✗ File filter "motiondetector" REMOVING files (DISTRO_FEATURE "motion_detector" missing)
NOTE: === Files marked for removal: 3 patterns ===
```

**Rootfs processing:**
```
NOTE: === Starting feature-based file removal ===
NOTE: Files to remove: /usr/lib/wpeframework/plugins/libWPEFrameworkMotionDetection.so*
NOTE:   Removed files matching: /usr/lib/wpeframework/plugins/libWPEFrameworkMotionDetection.so*
NOTE: === Feature-filtered file removal complete ===
```

### Common Issues

**Package still installed after filtering:**
- **Check validation warnings** - the build will warn you if filtering failed
- Most common: Package is `RDEPENDS` (must be `RRECOMMENDS`)
- Verify `BAD_RECOMMENDATIONS` is set in image recipe
- Another package may have hard dependency
- **Solution**: Check the warning message for specific instructions

**Files not removed:**
- Check file paths are correct (leading `/`)
- Verify `DISTRO_FEATURE` is actually missing
- Check `ROOTFS_POSTPROCESS_COMMAND` includes removal function

## Implementation Details

### Class: rdk-assembler-post-rootfs-hooks.bbclass

**Location**: `meta-rdk-images/classes/rdk-assembler-post-rootfs-hooks.bbclass`

**Components**:
1. Two anonymous Python functions (run at parse time)
2. Validation function `validate_package_filtering()` (run at rootfs time)
3. Shell function `remove_feature_filtered_files()` (run at rootfs time)
4. ROOTFS_POSTPROCESS_COMMAND registration

**Inherited by**: `rdk-fullstack-image.bb`

### Execution Flow

1. **Parse Phase** (bitbake parsing)
   - Image recipe inherits `rdk-assembler-post-rootfs-hooks`
   - Configuration files loaded
   - Anonymous Python functions execute
   - Variables set: `MIDDLEWARE_PACKAGES_TO_EXCLUDE`, `MIDDLEWARE_FILES_TO_REMOVE`

2. **Package Installation** (do_rootfs task)
   - `BAD_RECOMMENDATIONS` prevents unwanted packages
   - opkg installs only required packages

3. **Rootfs Post-Processing** (do_rootfs task)
   - `ROOTFS_POSTPROCESS_COMMAND` executes
   - **`validate_package_filtering()`** runs first - validates exclusions worked
   - `remove_feature_filtered_files()` runs
   - Files removed from `${IMAGE_ROOTFS}`
   - Empty directories cleaned up

## Validation

### Automatic Package Filtering Validation

The system automatically validates that package-level filtering worked correctly by checking the opkg status file after package installation.

**What it checks:**
- Verifies packages in `MIDDLEWARE_PACKAGES_TO_EXCLUDE` are not present in rootfs
- Detects if packages were installed despite being marked for exclusion

**If validation fails, you'll see:**
```
WARNING: ================================================
WARNING: PACKAGE FILTERING FAILED!
WARNING: ================================================
WARNING: The following packages should have been excluded but are still installed:
WARNING:   - nuanceeve
WARNING: 
WARNING: This usually means the package is added as RDEPENDS instead of RRECOMMENDS.
WARNING: BAD_RECOMMENDATIONS only works for packages listed as RRECOMMENDS.
WARNING: 
WARNING: To fix this issue:
WARNING: 1. Find the packagegroup that includes this package
WARNING: 2. Change from: RDEPENDS:${PN} += "nuanceeve"
WARNING: 3. Change to:   RRECOMMENDS:${PN} += "nuanceeve"
WARNING: ================================================
```

**Common causes:**
- Package is listed as `RDEPENDS` instead of `RRECOMMENDS` in packagegroup
- Another package has a hard runtime dependency (`RDEPENDS`) on the excluded package
- Package is in `IMAGE_INSTALL` directly (bypasses filtering)

**How to fix:**
1. Search for the package in all packagegroup recipes
2. Change `RDEPENDS` to `RRECOMMENDS` for optional packages
3. If package is truly required by other packages, consider file-level filtering instead

## Best Practices

1. **Naming Conventions**
   - Feature names: lowercase, descriptive (e.g., `nuance`, `motiondetector`)
   - DISTRO_FEATURES: prefix with `enable_` (e.g., `enable_nuance`)

2. **Package vs File Filtering**
   - Prefer package-level filtering when possible (cleaner, faster)
   - Use file filtering only when package contains mixed content

3. **Testing**
   - Always test with feature both enabled and disabled
   - Verify image boots and functions correctly
   - Check image size reduction meets expectations

4. **Documentation**
   - Comment configuration entries with recipe references
   - Document why files exist in packages
   - Note dependencies between features

## Related Files

- `meta-rdk-images/classes/rdk-assembler-post-rootfs-hooks.bbclass` - Main implementation
- `meta-rdk-images/conf/middleware-feature-mapping.conf` - Package filtering config
- `meta-rdk-images/conf/middleware-file-filter.conf` - File filtering config
- `meta-rdk-images/recipes-images/rdk-fullstack-image.bb` - Image recipe
- `meta-middleware-release/recipes-middleware/packagegroup-middleware-layer.bb` - Package group

## Support

For questions or issues:
1. Check build logs for filtering messages
2. Verify configuration syntax in `.conf` files
3. Test with `bitbake-getvar` to inspect variables
4. Review this documentation for examples
