# ExecTrace

Trace Ruby code, returning methods that were run, how many times they were
called, how long they took to run, and the methods they called.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'exec_trace'
```

## Usage

```ruby
require "pp"
require "exec_trace"

result = exec_trace do
  u = User.new
  u.save!
end

pp result
```

`exec_trace` returns an array of arrays. Each top-level array is a top-level call in the
`exec_trace` block. Frame consist 4 fields: file name + line number,
calls, time in microseconds, and an array of frames that it called.

e.g.

```
[
  ["/Users/me/exec_trace/test/exec_trace_test.rb:23", 1, 52, [
    ["/Users/me/exec_trace/test/exec_trace_test.rb:24", 5, 2518388, []]
  ]]
]
```

## Middleware

`exec_trace` include a Rack middleware that can be used to visualize trace
results on the page. The middleware should be included before everything you'd
like to trace.

```ruby
# config.ru
require 'exec_trace/middleware'

use ExecTrace::Middleware
```

To run the middleware, add `exec_trace` to the url's query parameters. e.g.
http://localhost:3000/dashboard?exec_trace

The middleware takes an optional `allowed_cb` keyword argument that can be used
to gate access to the middleware.

```ruby
# config.ru
require 'exec_trace/middleware'

use ExecTrace::Middleware, allowed_cb: ->(env) { env["current_user"].admin? }
```

## Developing

* To compile the C extension: `bundle exec rake compile`
* To run the tests `bundle exec rake test`

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
