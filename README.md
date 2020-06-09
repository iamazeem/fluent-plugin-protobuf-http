# fluent-plugin-protobuf-http

[Fluentd](https://fluentd.org/) HTTP input plugin for Protocol Buffers.

## Installation

### RubyGems

```
$ gem install fluent-plugin-protobuf-http
```

### Bundler

Add following line to your Gemfile:
```ruby
gem "fluent-plugin-protobuf-http"
```

And then execute:
```
$ bundle
```

## Configuration

* **bind** (string) (optional): The address to listen to.
  * Default value: `0.0.0.0`.
* **port** (integer) (optional): The port to listen to.
  * Default value: `8080`.
* **proto_dir** (string) (required): The directory path that contains the .proto files.
* **in_mode** (enum) (optional): The mode of incoming (supported) events.
  * Available values: binary, json
  * Default value: `binary`.
* **out_mode** (enum) (optional): The mode of outgoing (emitted) events.
  * Available values: binary, json
  * Default value: `binary`.
* **tag** (string) (required): The tag for the event.

### Example

```
<source>
  @type       protobuf_http
  @id         protobuf_http_input

  bind        0.0.0.0
  port        8080
  tag         debug.test

  proto_dir   ~/fluent/protos
  in_mode     binary
  out_mode    json
</source>
```

## Copyright

* Copyright(c) 2020 [Azeem Sajid](https://www.linkedin.com/in/az33msajid/)
* License
  * Apache License, Version 2.0
