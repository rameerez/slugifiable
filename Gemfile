# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in slugifiable.gemspec
gemspec

gem "rake", "~> 13.0"

group :development, :test do
  gem "appraisal"
  gem "minitest", "~> 6.0"
  gem "minitest-mock"
  # Optional: install manually for PostgreSQL integration tests (requires libpq)
  # gem "pg"
  gem "rack-test"
  gem "simplecov", require: false
  gem "sqlite3", ">= 2.1"
end
