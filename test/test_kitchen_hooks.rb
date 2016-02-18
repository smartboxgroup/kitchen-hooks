require 'minitest/autorun'

require_relative 'test_helper'
require_relative '../lib/kitchen_hooks'

Thread.abort_on_exception = true


class TestKitchenHooks < MiniTest::Test
  def setup
  end

  def teardown
  end

  def test_fails
    assert false
  end
end