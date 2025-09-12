#!/usr/bin/env python3
"""
QuickSnap Grid Snap Debug Script
This script helps debug Grid Snap functionality
"""

import bpy

def check_grid_snap_settings():
    """Check current Grid Snap settings"""
    addon = bpy.context.preferences.addons.get('quicksnap-1_0_1')
    if addon:
        prefs = addon.preferences
        print("=== Grid Snap Settings ===")
        print(f"Enable Grid Snap: {prefs.enable_grid_snap}")
        print(f"Grid Snap is available in preferences: {prefs.enable_grid_snap}")
        return prefs.enable_grid_snap
    else:
        print("QuickSnap addon not found!")
        return False

def enable_grid_snap():
    """Enable Grid Snap in preferences"""
    addon = bpy.context.preferences.addons.get('quicksnap-1_0_1')
    if addon:
        addon.preferences.enable_grid_snap = True
        print("✅ Grid Snap has been enabled in preferences!")
        print("Now you can use the 4 key during QuickSnap to toggle grid snapping.")
        return True
    else:
        print("❌ QuickSnap addon not found!")
        return False

if __name__ == "__main__":
    print("QuickSnap Grid Snap Debug Tool")
    print("=" * 40)

    is_enabled = check_grid_snap_settings()

    if not is_enabled:
        print("\n🔧 Grid Snap is currently DISABLED in preferences.")
        print("To enable it, you can:")
        print("1. Go to Edit > Preferences > Add-ons")
        print("2. Search for 'QuickSnap'")
        print("3. In the QuickSnap preferences, check 'Enable Grid Snap'")
        print("4. Or run this script with: enable_grid_snap()")

        # Auto-enable for convenience
        if input("\nWould you like to enable Grid Snap now? (y/n): ").lower() == 'y':
            enable_grid_snap()
    else:
        print("\n✅ Grid Snap is ENABLED!")
        print("You can now:")
        print("1. Start QuickSnap with Ctrl+Shift+V")
        print("2. Press 4 or NUMPAD_4 to toggle grid snapping on/off")
        print("3. The grid plane will be automatically detected based on camera view")
        print("4. Visual feedback will show colored grid lines (Red=X, Green=Y, Blue=Z)")
