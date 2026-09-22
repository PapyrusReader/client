# Catalog details content implementation plan

Use the existing library visual identity and keep remote publications separate from local books.

1. Extract shared section-title and metadata-row widgets from the library details presentation. Preserve its layout and ownership controls.
2. Retain structured publication dates, rights, subjects and page counts where the existing OPDS formats provide them. Do not treat Atom entry timestamps as book publication dates.
3. Add a Gutenberg-only description adapter. Separate recognized summary, edition notes, information and subjects; retain unknown paragraphs and conflicting/repeated values in expandable More details. Other catalogs retain their descriptions verbatim.
4. Render catalog Description/Information in the library's desktop 60/40 layout, stacking on narrow widths. Omit empty optional sections; show read-only subject chips and preserve description paragraphs.
5. Test parsing, conservative fallback, metadata preservation, responsive rendering and disclosure actions. Run OPDS and affected library/widget tests, analysis and representative screenshots.
