# Library grid controls

Replace the library's small/large presets with Grid and List views. Grid size uses a slider and minus/plus buttons in 20-pixel increments, from 120 to 320 pixels, defaulting to 160 pixels. Calculate columns from the available content width after padding, and remember the size on this device. Shelf contents share the same size preference.

Show the favorite button when a mouse hovers over a book or the book is already favorited. Keep the control available when no mouse is connected. Continue hiding favorites during selection and active acquisitions.

Implementation:
1. Add behavior tests for adjustable density, persistence, and mouse hover/favorite interactions.
2. Add the grid-size model, persist it through the existing preferences, replace preset view options, and update responsive layout calculations.
3. Add the view sheet with a live size slider and increment controls; apply the favorite visibility rule.
4. Run focused provider/widget/OPDS layout tests and analysis, then check the running web library at desktop and narrow sizes.

Acceptance: smaller default covers on wide screens; incremental changes update the grid; size survives restart and switching to List; no narrow-layout overflow; nonfavorite hearts disappear after pointer exit while favorite hearts remain visible.
