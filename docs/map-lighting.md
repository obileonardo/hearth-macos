# Map lighting

The map keeps its native SceneKit renderer, materials, camera controls and directional shadows. Full map windows additionally use a Metal ray-tracing contact-lighting pass on GPUs that report ray-tracing support. Eight short hemisphere rays intersect the actual visible opaque device triangles. The result is a soft transparent floor shadow that grounds the models without making text or illustration rectangles cast shadows.

This is hybrid ray-traced contact lighting, not a fully path-traced scene or a claim of multi-bounce reflections. Unsupported GPUs and failed or oversized passes retain SceneKit lighting. The compact menu preview remains lightweight.

## Performance and interaction

The pass runs on a utility queue and is cached until placements, floor visibility, appearance or map style change. Camera orbit does not rebuild it. New requests coalesce obsolete queued work; generation checks reject stale results. Old planes are removed when the map/floor changes. Closing the window invalidates pending results.

Each tile is 128 by 128 pixels. A pass is bounded to 64 tiles and 120,000 triangles; larger scenes retain the existing renderer. Mesh ranges, index sizes, finite vertices and tile parameters are checked before GPU work. Labels, transparent surfaces and non-shadow-casting illustration planes are excluded. Contact planes live outside the house and pin hit-test roots, preserving drag, selection and cursor behavior.

Map cards retain native drag/cancel and inspect behavior. Keyboard and assistive users can explicitly choose **Place on current floor** (Option Return), which suggests a spaced point near that floor's center without moving existing devices. Named accessibility actions and focus rings are available.

## Evidence

The kernel executed on an Apple M4 during an isolated geometry check: the occluded center had nonzero alpha and the edge was transparent. Fixture regressions also check world transforms, visibility, transparent geometry, malformed ranges and invalid input. These checks do not establish identical output or performance on every supported Mac. See the release verification record for the exact candidate and results.

The implementation follows Apple's [Metal ray-tracing model](https://developer.apple.com/documentation/metal/ray-tracing-with-acceleration-structures) and preserves the native renderer as the fallback.
