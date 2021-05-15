# frozen-string-literal: true

require 'helper'
require 'fluent/plugin/in_protobuf_http'
require 'net/http'

# Implementation of Test Class
class ProtobufHttpInputTest < Test::Unit::TestCase
  setup do
    Fluent::Test.setup
    @log_bin = File.open('./test/data/log.bin', 'rb') { |f| f.read }
    @log_json = File.open('./test/data/log.json', 'r') { |f| f.read }
    @log_bin_batch = File.open('./test/data/logbatch5.bin', 'rb') { |f| f.read }
  end

  def create_driver(conf)
    Fluent::Test::Driver::Input.new(Fluent::Plugin::ProtobufHttpInput).configure(conf)
  end

  sub_test_case 'configure' do
    test 'test default configuration' do
      conf = %(
        proto_dir ./test/data/protos
        tag       test
      )
      driver = create_driver(conf)
      plugin = driver.instance
      assert_equal plugin.class, Fluent::Plugin::ProtobufHttpInput
      assert_equal plugin.bind, '0.0.0.0'
      assert_equal plugin.port, 8080
      assert_equal plugin.in_mode, :binary
      assert_equal plugin.out_mode, :binary
    end
  end

  sub_test_case 'route#emit' do
    conf = %(
      proto_dir   ./test/data/protos
      tag         test
      in_mode     binary
      out_mode    json
    )

    test 'test invalid msgtype in query string i.e. empty or mismatch' do
      driver = create_driver(conf)
      res_codes = []
      driver.run do
        path = '/test'
        res = post(path, @log_bin)
        res_codes << res.code
      end
      assert_equal 1, res_codes.size
      assert_equal '400', res_codes[0]
    end

    test 'test incoming type mismatch [in_mode != Content-Type]' do
      conf = %(
        proto_dir   ./test/data/protos
        tag         test
        in_mode     binary
        out_mode    json
      )
      driver = create_driver(conf)
      res_codes = []
      driver.run do
        path = '/test?msgtype=service.logging.Log'
        res = post(path, @log_bin, :json)
        res_codes << res.code
      end
      assert_equal 1, res_codes.size
      assert_equal '400', res_codes[0]
    end

    test 'test single message (Binary to JSON)' do
      driver = create_driver(conf)
      res_codes = []
      driver.run do
        path = '/test?msgtype=service.logging.Log'
        res = post(path, @log_bin)
        res_codes << res.code
      end
      assert_equal 1, res_codes.size
      assert_equal '200', res_codes[0]
    end

    test 'test single message (JSON to Binary)' do
      conf = %(
        proto_dir   ./test/data/protos
        tag         test
        in_mode     json
        out_mode    binary
      )
      driver = create_driver(conf)
      res_codes = []
      driver.run do
        path = '/test?msgtype=service.logging.Log'
        res = post(path, @log_json, :json)
        res_codes << res.code
      end
      assert_equal 1, res_codes.size
      assert_equal '200', res_codes[0]
    end

    test 'test batch messages (Binary to JSON)' do
      conf = %(
        proto_dir   ./test/data/protos
        tag         test
        in_mode     binary
        out_mode    json
      )
      driver = create_driver(conf)
      res_codes = []
      driver.run do
        path = '/test?msgtype=service.logging.Batch&batch=true'
        res = post(path, @log_bin_batch)
        res_codes << res.code
      end
      assert_equal 1, res_codes.size
      assert_equal '200', res_codes[0]
    end

    test 'test incompatible message' do
      conf = %(
        proto_dir   ./test/data/protos
        tag         test
        in_mode     binary
        out_mode    json
      )
      driver = create_driver(conf)
      res_codes = []
      driver.run do
        path = '/test?msgtype=service.logging.Log'
        res = post(path, @log_bin_batch)
        res_codes << res.code
      end
      assert_equal 1, res_codes.size
      assert_equal '400', res_codes[0]
    end
  end

  private

  def post(path, body, type = :binary)
    http = Net::HTTP.new('127.0.0.1', 8080)
    content_type = 'application/octet-stream'
    content_type = 'application/json' if type == :json
    header = { 'Content-Type' => content_type }
    req = Net::HTTP::Post.new(path, header)
    req.body = body
    http.request(req)
  end
end
