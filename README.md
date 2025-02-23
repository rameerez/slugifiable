# 🐌 `slugifiable` - Rails gem to generate SEO-friendly slugs

[![Gem Version](https://badge.fury.io/rb/slugifiable.svg)](https://badge.fury.io/rb/slugifiable)

Automatically generates unique slugs for your Rails' model records, so you can expose SEO-friendly URLs.

Example:
```
https://myapp.com/products/big-red-backpack-321678
```

Where `big-red-backpack-321678` is the slug.

`slugifiable` can generate:
- Slugs like `"big-red-backpack"` or `"big-red-backpack-321678"`: unique, string-based slugs based on any attribute, such as `product.name`
- Slugs like `"d4735e3a265"`: unique **hex string slugs**
- Slugs like `321678`: unique **number-only slugs**

## Why

When building Rails apps, we usually need to expose _something_ in the URL to identify a record, like:
```
https://myapp.com/products/123
```

But exposing IDs (like `123`) is not usually good practice. It's not SEO-friendly, it can give away how many records you have in the database, it could also be an attack vector, and it just feels off.

It would be much better to have a random-like string or number instead, while still remaining unique and identifiable:
```
https://myapp.com/products/d4735e3a265
```

Or better yet, use other instance attribute (like `product.name`) to build the slug:
```
https://myapp.com/products/big-red-backpack
```

`slugifiable` takes care of building all these kinds of slugs for you.

## Installation

Add this line to your application's Gemfile:
```ruby
gem 'slugifiable'
```

Then run `bundle install`.

After installing the gem, add `include Slugifiable::Model` to any ActiveRecord model, like this:
```ruby
class Product < ApplicationRecord
  include Slugifiable::Model # Adding this provides all the required slug-related methods to your model
end
```

That's it!

Then you can, for example, get the slug for a product like this:
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

And this will generate slugs based on your `Product` instance `name`, like:
```ruby
Product.first.slug
=> "big-red-backpack"
```

If your model has a `slug` attribute in the database, `slugifiable` will automatically generate a slug for that model upon instance creation, and save it to the DB.

> [!IMPORTANT]
> Your `slug` attribute **SHOULD NOT** have `null: false` in the migration / database. If it does, `slugifiable` will not be able to save the slug to the database, and will raise an error like `ERROR:  null value in column "slug" of relation "posts" violates not-null constraint (PG::NotNullViolation)`
> This is because records are created without a slug, and the slug is generated later.

If you're generating slugs based off the model `id`, you can also set a desired length:
```ruby
class Product < ApplicationRecord
  include Slugifiable::Model
  generate_slug_based_on :id, length: 6
end
```

Which would return something like:
```ruby
Product.first.slug
=> "6b86b2"
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

By default, when you include `Slugifiable::Model`, slugs will be generated as a random-looking string based off the record `id` (SHA hash)

`slugifiable` supports both `id` and `uuid`.

The default setting is:
```ruby
generate_slug_based_on id: :hex_string
```

Which returns slugs like: `d4735e3a265`

If you don't like hex strings, you can get number-only slugs with:
```ruby
generate_slug_based_on id: :number
```

Which will return slugs like: `321678` – nonconsecutive, nonincremental, not a total count.

When you're generating obfuscated slugs (based on `id`), you can specify a desired slug length:
```ruby
generate_slug_based_on id: :number, length: 3
```

The length should be a positive number between 1 and 64.

If instead of obfuscated slugs you want human-readable slugs, you can specify an attribute to base your slugs off of. For example:
```ruby
generate_slug_based_on :name
```

Will look for a `name` attribute in your instance, and use its value to generate the slug. So if you have a product like:
```ruby
Product.first.name
=> "Big Red Backpack"
```

then the slug will be computed as:
```ruby
Product.first.slug
=> "big-red-backpack"
```

You can also use instance methods to generate more complex slugs. This is useful when you need to combine multiple attributes:
```ruby
class Event < ApplicationRecord
  include Slugifiable::Model
  belongs_to :location
  
  generate_slug_based_on :title_with_location

  # The method can return any string - slugifiable will handle the parameterization
  def title_with_location
    if location.present?
      "#{title} #{location.city} #{location.region}"  # Returns raw string, slugifiable parameterizes it
    else
      title
    end
  end
end
```

This will generate slugs like:
```ruby
Event.first.slug
=> "my-awesome-event-new-york-new-york"  # Automatically parameterized
```

There may be collisions if two records share the same name – but slugs should be unique! To resolve this, when this happens, `slugifiable` will append a unique string at the end to make the slug unique:
```ruby
Product.first.slug
=> "big-red-backpack-321678"
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rameerez/slugifiable. Our code of conduct is: just be nice and make your mom proud of what you do and post online.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
