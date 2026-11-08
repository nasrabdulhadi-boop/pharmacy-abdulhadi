# Seven-language interface — QA, 2026-11-08

Added Russian, Turkish, Romanian, French and German alongside Arabic and English. Romanian is the interpretation of the user's «الرومانسية».

The shared language selector and administration appearance selector use the same persisted preference. All five catalogs contain 1,968 source messages each, loaded on demand. Document language, direction, application title and display date locales update together. Numbers retain the existing Latin digits, separators and currency calculation rules. User-entered names, search terms and business records are not translated.

Catalogs are static: no runtime translation API or browser dependency was added. Translation drafts were generated offline using the MIT-licensed Meta M2M100-418M model, CTranslate2 int8 conversion VoragoStudios/gct-m2m100-418m-ct2 revision 09bd1aceee8a638b4e102bded4dfb8dbf20af4bd, CTranslate2 4.6.0 and SentencePiece 0.2.1. Build-only reproducibility scripts and reviewed overrides are under scripts/i18n. Each language has 105 source messages with manually supplied core terminology overrides. Longer text remains machine-translated and requires specialist linguistic review before commercial release; catalog coverage does not certify translation quality.

Preserved interpolation placeholders and technical identifiers. Reverse translation returns all matching source labels to preserve employee restrictions when languages render Edit and Change identically. Server authorization and SDK call arguments remain unchanged.

Validation: 163 automated tests passed; one live support-session test skipped. The workspace SSR contract passed 63 cases. Staging build succeeded. Browser checks against an isolated fixture with mocked Auth/RPC verified all five languages in navigation, LTR direction, translated POS, unchanged Arabic search draft during switching, and restored language after page reload. Fixture checks do not replace a real employee-session end-to-end test. No database, Auth user, Edge Function or production changes were performed.

Large main application bundle warning remains pre-existing; additional language catalogs are separate lazy chunks. Pending commercial work includes linguistic review across all workflows and review of contextual source labels such as permission versus expiry.
