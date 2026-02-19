## [0.2.1] - 2026-02-19

### Fixed
- **Race condition in slug generation**: When two processes create records with the same base slug simultaneously, the second process now retries with a new random suffix instead of crashing with `RecordNotUnique`

### Added
- `around_create :retry_create_on_slug_unique_violation` for NOT NULL slug columns (pre-INSERT collision handling)
- `with_slug_retry` helper with PostgreSQL-safe savepoints (`requires_new: true`)
- `slug_column_not_null?` optimization to skip savepoint overhead for nullable slug columns
- `slug_unique_violation?` detection supporting SQLite, PostgreSQL, and MySQL error formats
- `compute_slug_for_retry` protected method as override point for custom retry behavior

### Changed
- `set_slug` now retries with savepoints on `RecordNotUnique` for slug collisions (after_create path)
- Retry exhaustion raises `RecordNotUnique` instead of falling back to timestamp suffix (fail-fast behavior)
- `update_slug_if_nil` explicitly uses non-bang `save` to avoid exceptions on read operations

### Known Limitations
- **`before_create` callbacks re-execute on retry**: If a retry is needed, `before_create` callbacks run again. Design callbacks to be idempotent or use guards.
- **`RecordInvalid` not retried**: Only DB-level `RecordNotUnique` triggers retry. Validation-level uniqueness errors do not retry (this is the race window the fix addresses).
- **Custom index names**: If your slug unique index has a non-standard name that doesn't contain "slug" or "_on_slug", violations will bubble up instead of retrying.

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
