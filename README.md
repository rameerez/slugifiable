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
```ruby
class Product < ApplicationRecord
  include Slugifiable::Model # Adding this provides all the required slug-related methods to your model
end
```

Then you can, for example, get the slug for a company like this:
```ruby
Product.first.slug
=> "4e07408562b"
```

You can also define how to generate slugs:
```ruby
class Product < ApplicationRecord
  include Slugifiable::Model
  generate_slug_based_on :name
end
```

And this will generate slugs based on your `Company` instance `name`, like:
```ruby
Product.first.slug
=> "big-red-backpack"
```

More details in the "How to use" section.

## How to use

Slugs should never change, so it's recommended you save your slugs to the database.

Therefore, all models that include `Slugifiable::Model` should have a `slug` attribute that persists the slug in the database. If your model doesn't have a `slug` attribute yet, just run:
```
rails g migration addSlugTo<MODEL_NAME> slug:text
```

where `<MODEL_NAME>` is your model name in plural, and then run:
```
rails db:migrate
```

And your model should now have a `slug` attribute in the database.

When a model has a `slug` attribute, `slugifiable` automatically generates a slug for that model upon instance creation, and saves it to the DB.

`slugifiable` can also work without persisting slugs to the databse, though: you can always run `.slug`, and that will give you a valid, unique slug for your record.

### Define how slugs are generated

By default, when you include `Slugifiable::Model`, slugs will be generated as a string based off the record `id`

`slugifiable` supports both `id` and `uuid`.

The default setting is:
```ruby
generate_slug_based_on id: :string
```

Which returns slugs like: `d4735e3a265`

You can get number-based slugs with:
```ruby
generate_slug_based_on id: :number
```

Which will return slugs like: `321678`

You can also specify an attribute to base your slugs off of, if you want to create SEO-friendly slugs and expose that attribute publicly. For example:
```ruby
generate_slug_based_on :name
```

Will look for a `name` attribute in your model, and use its value to generate the slug. So if you have a product like:
```ruby
Product.first.name
=> "Big Red Backpack"
```

then the slug will be computed as:
```ruby
Product.first.slug
=> "big-red-backpack"
```

There may be collisions if two records share the same name – but slugs should be unique! To resolve this, when this happens, `slugifiable` will append a unique string at the end to make the slug unique:
```ruby
Product.first.slug
=> "big-red-backpack-d4735e3a265"
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rameerez/slugifiable. Our code of conduct is: just be nice and make your mom proud of what you do and post online.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
