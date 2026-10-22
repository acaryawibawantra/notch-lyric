# Cat mascot — resting concept v1

Generated with the built-in image generation tool. This is concept art, not a production animation or an exact frame-aligned sprite sheet. The application does not load this bitmap; `RestingCatEyes` in `AnimatedFace.swift` implements the eyes natively.

Production placement: one eye on each side of the physical camera gap, measured using the display's auxiliary top areas. On notchless displays the eyes sit together. Idle animation uses cancellable pauses with synchronized blinks and gentle pupil movements; Reduce Motion keeps a static front-facing expression. Enable it in Appearance → Cat mascot → Show resting cat eyes while inactive (the existing preference is preserved).

Eye gradient presets: Pearl (default), Sky, Mint, Lavender, Sunrise, and Rose. The palette is saved separately from the tools accent and applies live without restarting the animation. The Appearance preview is static; pupils stay black, and the gradient itself does not run a continuous animation.

Asset: `cat-resting-concept-v1.png`.

Expressions, in reading order: forward, look left, look right, closed-eye blink.

For implementation, recreate the approved silhouette and eye geometry as lightweight native shapes. Keep pupils clipped inside the eyes, animate gaze gently, vary blink timing, and respect Reduce Motion. The head should blend into the black notch; avoid continuous redraw when the mascot is hidden. Do not use the generated frame proportions as precise animation geometry.

## Generation prompt

Use case: stylized-concept.

Asset type: a single transparent PNG concept atlas for a cat mascot resting inside a tiny black macOS screen notch. This is a visual direction sheet for later native animation, NOT a screenshot or app UI.

Primary request: design one original, charming, quiet black cat face and show its four resting expressions in a perfectly aligned 2 by 2 atlas. Top left: eyes open looking straight ahead. Top right: both pupils looking to the viewer's left. Bottom left: both pupils looking to the viewer's right. Bottom right: both eyes fully shut in a soft friendly blink.

Subject and composition: four identical small front-facing cat head silhouettes with two understated triangular ears, widely spaced soft almond-shaped ivory-white eyes with dark vertical feline pupils, and two very short subtle whisker strokes on each cheek. Each cat is exactly the same size, same ear silhouette, same eye positions, centered in its equal square cell with generous transparent padding. Only pupil position or eyelids change between cells. Broad face, no body. The silhouette is near-black charcoal so it can disappear into a black notch. Eye design must be legible at 24 to 40 pixels wide. Friendly curious sleepy expression, never sinister or aggressive.

Style: premium minimal flat 2D mascot illustration, smooth antialiased clean shapes, restrained precise geometry, warm personality, simple enough to reconstruct as native animated vector shapes. No glossy 3D, no fur detail, no photographic textures, no strong glow, no gradients.

Constraints: genuinely transparent background outside each head. No black rectangles or rounded UI plates, no wallpaper, no labels, no text, no numbers, no grid lines, no watermark, no additional characters or props. All four faces must be fully visible and separated. Keep contours and proportions identical across expressions.
