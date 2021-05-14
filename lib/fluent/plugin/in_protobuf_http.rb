# frozen-string-literal: true

#
# Copyright 2020 Azeem Sajid
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'fluent/plugin/input'
require 'fluent/config/error'
require 'fluent/plugin_helper/http_server'
require 'webrick/httputils'
require 'json'
require 'English'

module Fluent
  module Plugin
    # Implementation of HTTP input plugin for Protobuf
    class ProtobufHttpInput < Fluent::Plugin::Input
      Fluent::Plugin.register_input('protobuf_http', self)

      helpers :http_server, :event_emitter

      desc 'The address to listen to.'
      config_param :bind, :string, default: '0.0.0.0'
      desc 'The port to listen to.'
      config_param :port, :integer, default: 8080

      desc 'The directory path that contains the .proto files.'
      config_param :proto_dir, :string

      desc 'The mode of incoming (supported) events.'
      config_param :in_mode, :enum, list: %i[binary json], default: :binary
      desc 'The mode of outgoing (emitted) events.'
      config_param :out_mode, :enum, list: %i[binary json], default: :binary

      desc 'The tag for the event.'
      config_param :tag, :string

      config_section :transport, required: false, multi: false, init: true, param_name: :transport_config do
        config_argument :protocol, :enum, list: %i[tcp tls], default: :tcp
      end

      def initialize
        super

        @protos = []            # list of *.proto files
        @compiled_protos = []   # list of compiled protos i.e. *_pb.rb files
        @msgclass_lookup = {}   # Lookup Hash: { msgtype => msgclass }
      end

      def compile_protos
        log.debug("Checking proto_dir [#{@proto_dir}]...")

        path = File.expand_path(@proto_dir)
        raise Fluent::ConfigError, "protos_dir does not exist! [#{path}]" unless Dir.exist?(path)

        @protos = Dir["#{path}/*.proto"]
        raise Fluent::ConfigError, "Empty proto_dir! [#{path}]" unless @protos.any?

        log.info("Compiling .proto files [#{@protos.length}]...")

        `protoc --ruby_out=#{path} --proto_path=#{path} #{path}/*.proto`
        raise Fluent::ConfigError, 'Could not compile! See error(s) above.' unless $CHILD_STATUS.success?

        log.info("Compiled successfully:\n- #{@protos.join("\n- ")}")

        @protos.each do |proto|
          @compiled_protos.push(get_compiled_proto(proto))
        end

        log.info("Compiled .proto files:\n- #{@compiled_protos.join("\n- ")}")
      end

      def get_compiled_proto(proto)
        proto_suffix = '.proto'
        compiled_proto_suffix = '_pb.rb'

        compiled_proto = proto.chomp(proto_suffix) + compiled_proto_suffix
        raise Fluent::ConfigError, "Compiled proto not found! [#{compiled_proto}]" unless File.file?(compiled_proto)

        compiled_proto
      end

      def populate_msgclass_lookup
        @compiled_protos.each do |compiled_proto|
          msg_types = get_msg_types(compiled_proto)
          next unless msg_types.any?

          begin
            require compiled_proto
          rescue LoadError => e
            raise Fluent::ConfigError, "Possible 'import' issue! Use a single self-contianed .proto file! #{e}"
          end

          msg_types.each do |msg_type|
            @msgclass_lookup[msg_type] = get_msg_class(msg_type)
          end
        end

        raise Fluent::ConfigError, "No message types found! Check proto_dir [#{@proto_dir}]!" if @msgclass_lookup.empty?

        log.info("Registered messages [#{@msgclass_lookup.keys.length}]:\n- #{@msgclass_lookup.keys.join("\n- ")}")
      end

      def get_msg_types(compiled_proto)
        log.debug("Extracting message types [#{compiled_proto}]...")
        msg_types = []
        File.foreach(compiled_proto) do |line|
          if line.lstrip.start_with?('add_message')
            msg_type = line[/"([^"]*)"/, 1] # regex: <add_message> 'msg_type' <do>
            msg_types.push(msg_type) unless msg_type.nil?
          end
        end

        if msg_types.any?
          log.info("Total [#{msg_types.length}] message types in [#{compiled_proto}]:\n- #{msg_types.join("\n- ")}")
        else
          log.warn("No message types found! [#{compiled_proto}]")
        end

        msg_types
      end

      def get_msg_class(msg_type)
        msg = Google::Protobuf::DescriptorPool.generated_pool.lookup(msg_type)
        raise Fluent::ConfigError, "Message type ['#{msg_type}'] not registered!'" if msg.nil?

        msg.msgclass
      end

      def start
        super

        compile_protos
        populate_msgclass_lookup

        # TLS check
        proto = :tcp
        tls_opts = nil
        if @transport_config && @transport_config.protocol == :tls
          proto = :tls
          tls_opts = @transport_config.to_h
        end

        log.info("Starting protobuf #{proto == :tcp ? 'HTTP' : 'HTTPS'} server [#{@bind}:#{@port}]...")
        log.debug("TLS configuration:\n#{tls_opts}") if tls_opts

        http_server_create_http_server(:protobuf_server, addr: @bind, port: @port, logger: log, proto: proto, tls_opts: tls_opts) do |server|
          server.post("/#{tag}") do |req|
            peeraddr = "#{req.peeraddr[2]}:#{req.peeraddr[1]}" # ip:port
            serialized_msg = req.body

            log.info("[R] {#{@in_mode}} [#{peeraddr}, size: #{serialized_msg.length} bytes]")
            log.debug("Dumping serialized message [#{serialized_msg.length} bytes]:\n#{serialized_msg}")

            content_type = req.header['content-type'][0]

            unless valid_content_type?(content_type)
              status = "Invalid 'Content-Type' header! [#{content_type}]"
              log.warn("[X] Message rejected! [#{peeraddr}] #{status}")
              next [400, { 'Content-Type' => 'application/json', 'Connection' => 'close' }, { 'status' => status }.to_json]
            end

            log.debug("[>] Content-Type: #{content_type}")

            msgtype, batch = get_query_params(req.query_string)
            unless @msgclass_lookup.key?(msgtype)
              status = "Invalid 'msgtype' in 'query_string'! [#{msgtype}]"
              log.warn("[X] Message rejected! [#{peeraddr}] #{status}")
              next [400, { 'Content-Type' => 'application/json', 'Connection' => 'close' }, { 'status' => status }.to_json]
            end

            log.debug("[>] Query parameters: [msgtype: #{content_type}, batch: #{batch}]")

            deserialized_msg = deserialize_msg(msgtype, serialized_msg)

            if deserialized_msg.nil?
              status = "Incompatible message! [msgtype: #{msgtype}, size: #{serialized_msg.length} bytes]"
              log.warn("[X] Message rejected! [#{peeraddr}] #{status}")
              next [400, { 'Content-Type' => 'application/json', 'Connection' => 'close' }, { 'status' => status }.to_json]
            end

            is_batch = !batch.nil? && batch == 'true'
            log.debug("[>] Message validated! [msgtype: #{content_type}, is_batch: #{is_batch}]")

            # Log single message

            unless is_batch
              log.info("[S] {#{@in_mode}} [#{peeraddr}, msgtype: #{msgtype}, size: #{serialized_msg.length} bytes]")

              time = Fluent::Engine.now
              event_msg = serialize_msg(msgtype, deserialized_msg)
              record = { 'message' => event_msg }
              router.emit(@tag, time, record)

              log.info("[S] {#{@out_mode}} [#{peeraddr}, msgtype: #{msgtype}, size: #{event_msg.length} bytes]")
              next [200, { 'Content-Type' => 'text/plain' }, nil]
            end

            # Log batch messages

            log.info("[B] {#{@in_mode}} [#{peeraddr}, msgtype: #{msgtype}, size: #{serialized_msg.length} bytes]")

            if deserialized_msg.type.nil? || deserialized_msg.batch.nil? || deserialized_msg.batch.empty?
              status = "Invalid 'batch' message! [msgtype: #{msgtype}, size: #{serialized_msg.length} bytes]"
              log.warn("[X] Message rejected! [#{peeraddr}] #{status}")
              next [400, { 'Content-Type' => 'application/json', 'Connection' => 'close' }, { 'status' => status }.to_json]
            end

            batch_type = deserialized_msg.type
            batch_msgs = deserialized_msg.batch
            batch_size = batch_msgs.length

            log.info("[B] Emitting message stream/batch [batch_size: #{batch_size} messages]...")

            stream = MultiEventStream.new
            batch_msgs.each do |batch_msg|
              time = Fluent::Engine.now
              record = { 'message' => serialize_msg(batch_type, batch_msg) }
              stream.add(time, record)
            end

            router.emit_stream(@tag, stream)

            status = "Batch received! [batch_type: #{batch_type}, batch_size: #{batch_size} messages]"
            log.info("[B] {#{@out_mode}} [#{peeraddr}, msgtype: #{msgtype}] #{status}")
            [200, { 'Content-Type' => 'application/json', 'Connection' => 'close' }, { 'status' => status }.to_json]
          end
        end
      end

      def valid_content_type?(content_type)
        hdr_binary = 'application/octet-stream'
        hdr_json = 'application/json'

        case @in_mode
        when :binary
          content_type == hdr_binary
        when :json
          content_type == hdr_json
        when :binary_and_json
          content_type == hdr_binary || content_type == hdr_json
        end
      end

      def get_query_params(query_string)
        if query_string.nil?
          log.warn("Empty query string! 'msgtype' is required!")
          return nil
        end

        query = WEBrick::HTTPUtils.parse_query(query_string)
        msgtype = query['msgtype']
        log.warn("'msgtype' not found in 'query_string' [#{query_string}]") if msgtype.nil?

        batch = query['batch']
        log.warn("'batch' not found in 'query_string' [#{query_string}]") if batch.nil?

        [msgtype, batch]
      end

      def deserialize_msg(msgtype, serialized_msg)
        msgclass = @msgclass_lookup[msgtype]
        log.debug("Deserializing {#{@in_mode}} message of type [#{msgclass}]...")
        begin
          case @in_mode
          when :binary
            msgclass.decode(serialized_msg)
          when :json
            msgclass.decode_json(serialized_msg)
          end
        rescue Google::Protobuf::ParseError => e
          log.error("Incompatible message! [msgtype: #{msgtype}, size: #{serialized_msg.length} bytes] #{e}")
          nil
        rescue StandardError => e
          log.error("Deserializaton failed! Error: #{e}")
          nil
        end
      end

      def serialize_msg(msgtype, deserialized_msg)
        msgclass = @msgclass_lookup[msgtype]
        log.debug("Serializing [#{@in_mode} > #{@out_mode}]...")
        begin
          case @out_mode
          when :binary
            msgclass.encode(deserialized_msg)
          when :json
            msgclass.encode_json(deserialized_msg)
          end
        rescue StandardError => e
          log.error("Serialization failed! [msgtype: #{msgtype}, msg: #{deserialized_msg}] Error: #{e}")
          nil
        end
      end

      def shutdown
        @compiled_protos.each do |compiled_proto|
          File.delete(compiled_proto)
        end

        super
      end
    end
  end
end
