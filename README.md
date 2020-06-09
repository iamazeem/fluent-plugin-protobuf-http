# fluent-plugin-protobuf-http

[Fluentd](https://fluentd.org/) HTTP input plugin for Protocol Buffers.

## Features

* **ProtoBuf Schemas**: Automatic compilation of `.proto` files located in `proto_dir`
* **Incoming Message Format**: Support for binary or JSON format (`Content-Type`: `application/octet-stream` or `application/json`)
* **Outgoing Message Format**: Support for binary or JSON format
* **Message Types**: Single or Batch

## Schemas (`.proto` files)

The logging of events is assumed to be the prime use-case for this plugin.  
So, use self-contained `.proto` file(s) that don't import other custom `.proto` file(s).  
The `package` and `message` names must be distinct and are treated as case-sensitive.

Consider this `log.proto` schema:
```
syntax = "proto3";

package service.logging;

import "google/protobuf/timestamp.proto";

message Log {
  message Context {
    google.protobuf.Timestamp timestamp = 1;
    string host_or_ip = 2;
    string service_name = 3;
    string user = 4;
  }

  enum Level {
    DEBUG = 0;
    INFO = 1;
    WARN = 2;
    ERROR = 3;
    FATAL = 4;
  }

  Context context = 1;
  Level level = 2;
  string message = 3;
}
```

The fully-qualified message type for `Log` will be `service.logging.Log`.  
This message type is used as the value of `msgtype` query parameter in the URL.  
See URL section below for more on `msgtype`.

### Single Message

The above schema will be used as-is for the single message.

### Batch Message

For a batch, the schema must be like this:
```
message Batch {
  string type = 1;
  repeated Log batch = 2;
}
```

IMPORTANT:
The `Batch` message type is part of `log.proto`, it's not a separate file!  
You can choose any name for a batch message type.

The complete `log.proto` will be:
```
syntax = "proto3";

package service.logging;

import "google/protobuf/timestamp.proto";

message Log {
  message Context {
    google.protobuf.Timestamp timestamp = 1;
    string host_or_ip = 2;
    string service_name = 3;
    string user = 4;
  }

  enum Level {
    DEBUG = 0;
    INFO = 1;
    WARN = 2;
    ERROR = 3;
    FATAL = 4;
  }

  Context context = 1;
  Level level = 2;
  string message = 3;
}

message Batch {
  string type = 1;
  repeated Log batch = 2;
}
```

For batch processing, the plugin looks for special members `type` and `batch`.  
The `type` will indicate the message type of `batch` i.e. `Log` in this example.

The type of `Batch` is `service.logging.Batch` and it will be the value of `msgtype` in the URL query.  
The type of `batch` array is `service.logging.Log` and it will be the value of `type`.

The `google.protobuf.Any` type has not been used deliberately here.  
It stores message type information with each message resulting in increase in size.  
With the above approach, the type is stored only once for the whole batch.

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

### Endpoint (URL)

For single message:
```
http://<ip>:<port>/<tag>?msgtype=<fully-qualified-message-type>
```

For batch message:
```
http://<ip>:<port>/<tag>?msgtype=<fully-qualified-message-type-for-batch>&batch=true
```

Without `batch=true` query parameter, the batch will be treated as a single message.

For example, for a log type `service.logging.Log` and its corresponding batch type `service.logging.Batch`:

Single:
```
http://localhost:8080/debug.test?msgtype=service.logging.Log
```

Batch:
```
http://localhost:8080/debug.test?msgtype=service.logging.Batch&batch=true
```

**NOTE**: The values of query parameters (`msgtype`, `batch`) are case-sensitive!

## Copyright

* Copyright&copy; 2020 [Azeem Sajid](https://www.linkedin.com/in/az33msajid/)
* License
  * Apache License, Version 2.0
