# frozen-string-literal: true

require 'helper'
require 'fluent/plugin/in_protobuf_http'

class ProtobufHttpInputTest < Test::Unit::TestCase
  setup do
    Fluent::Test.setup
  end

  test 'failure' do
    flunk
  end

  private

  def create_driver(conf)
    Fluent::Test::Driver::Input.new(Fluent::Plugin::ProtobufHttpInput).configure(conf)
  end
end
