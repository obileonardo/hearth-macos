# Floating navigation

The bottom navigation bar floats over scrolling content. There is no full-width blackout or blur strip. Scroll to bring the final controls completely above the bar. Fixed climate controls and the demo exit remain above it.

In **Settings → Navigation**, adjust **Glass opacity** from clearer to more opaque. The default is 55%. The setting changes the bar's surface; icons and labels retain full opacity. The value is remembered between launches.

**Reduce Transparency** or **Increase Contrast** in macOS keeps the bar solid and temporarily disables the slider. Your chosen value is retained for when those settings are turned off. **Reduce Motion** removes the lens stretch; ordinary motion is restrained and pending settling animations are cancelled when another tab is chosen.

The scrolled page heading becomes a separate floating capsule after the original heading has left the viewport. In Security it retains the camera count and update summary. Back buttons remain actionable, and the original and pinned heading are not announced simultaneously.

The **Assets** section contains homes, energy, vehicles, gadgets and speakers. This is a display-name update: saved routes, hidden-section choices, device links and Home Assistant's own Devices terminology remain compatible.

## Menu-bar updates

An open panel retains its presentation position while the menu-bar status rotates. Hearth reserves a bounded slot for the currently enabled status lines while the panel is open, centers the capsule artwork inside it and releases that space when the panel closes. Display changes and explicit repositioning can reanchor it; the panel still stays within the usable screen.

macOS owns the positions of neighboring menu items. Very long incoming text may truncate in the bounded slot; its full text remains available to VoiceOver and in the tooltip. This does not claim control over the system menu-bar layout.

## Documentation images

The navigation guide shows the real Settings navigation section in isolation, using an offline demo context. The slider, section switches and dock material are drawn statically for offscreen rendering; the running app uses native interactive controls and adaptive glass. No household configuration is included.
