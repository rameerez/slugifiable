## [0.2.0] - 2026-01-16

- Added a full Minitest test suite
- Fixed `respond_to?(:slug)` returning false for models using method_missing by implementing `respond_to_missing?`
- Fixed collision resolution generating identical suffixes by switching from id-based deterministic suffixes to SecureRandom-based random suffixes
- Fixed length parameter edge cases (zero, negative, very large values) by adding length validation and clamping via `normalize_length` method
- Fixed timestamp fallback to include random suffix for additional uniqueness guarantee
- Added length validation constants (`MAX_HEX_STRING_LENGTH`, `MAX_NUMBER_LENGTH`) to prevent invalid length values

## [0.1.1] - 2024-03-21

- Slugs can be now generated based off methods that return a string, not just based off attributes
- Enhanced collision resolution strategy so that it doesn't get stuck in infinite loops
- Added comprehensive test suite

## [0.1.0] - 2024-10-30

- Initial release
