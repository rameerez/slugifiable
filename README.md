# 🐌 `slugifiable` - Rails gem to generate SEO-friendly slugs

[![Gem Version](https://badge.fury.io/rb/slugifiable.svg)](https://badge.fury.io/rb/slugifiable)

Automatically generates unique slugs for your records, so you can expose them in SEO-friendly URLs.

Example:
```
https://myapp.com/products/big-red-backpack-d4735e3a265
```

Where `big-red-backpack-d4735e3a265` is the slug.

`slugifiable` can generate:
- Unique string-based slugs based on any attribute, such as `product.name` (like `"big-red-backpack"` or `"big-red-backpack-d4735e3a265"`)
- Unique and random string-based slugs based off an ID (like `"d4735e3a265"`)
- Unique and random number-based slugs based off an ID (like `321678`).

## Why

When building URLs, especially when building SEO-friendly URLs, we usually need to expose something that identifies a record, like:
```
https://myapp.com/products/123
```

The problem is exposing internal IDs is not usually good practice. It can give away how many records you have in the database, could be an attack vector, and it just feels off.

It would be much better to have a random string or number instead, while still remaining unique and identifiable:
```
https://myapp.com/products/321678

# or

https://myapp.com/products/d4735e3a265
```

Or better yet, use other attribute (like `product.name`), which makes a human-readable and SEO-friendly URL, like:
```
https://myapp.com/products/big-red-backpack
```

`slugifiable` takes care of building these slugs automatically for you.

## Installation

Add this line to your application's Gemfile:
```ruby
gem 'slugifiable'
```

Then run `bundle install`.

After installing the gem, add `include Slugifiable::Model` to any model you want to provide with slugs, like this:
```
class Company < ApplicationRecord
  has_many :employees

  include Slugifiable::Model # Adding this provides all the required slug-related methods to your model
end
```

Then you can, for example, get the slug for a company like this:
```
Company.first.slug
=> "4e07408562b"
```

## How to use

TODO: write this section

- based off id, also supports uuid
- slug collision resolver
  - customizable before and after?
  - requires us to both transform it into a slug and resolve collisions. This way, if you have two companies named "Technology Services", each one will get a different slug:
```
https://myapp.com/companies/technology-services

# and

https://myapp.com/companies/technology-services-6b86b273ff3
```
- number-based (customizable length?)
- string-based (customizable length?)
- readable-attribute (customizable length?)
- works with and without a `slug` attribute (but better to store it)
- warning: always generate your slugs based off attrs that are not going to change (like id), not attrs that might change (like name or email) -- slugs should be unique and immutable

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rameerez/slugifiable. Our code of conduct is: just be nice and make your mom proud of what you do and post online.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
