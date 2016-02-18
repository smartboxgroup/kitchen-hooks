require 'simplecov'
require 'simplecov-cobertura'
SimpleCov.formatters = [
  SimpleCov::Formatter::HTMLFormatter,
  SimpleCov::Formatter::CoberturaFormatter
]
SimpleCov.start