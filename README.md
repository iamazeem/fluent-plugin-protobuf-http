# fluent-plugin-protobuf-http

[![ci](https://github.com/iamazeem/fluent-plugin-protobuf-http/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/iamazeem/fluent-plugin-protobuf-http/actions/workflows/ci.yml)
[![License: Apache](https://img.shields.io/badge/license-Apache-darkgreen.svg?style=flat-square)](https://github.com/iamAzeem/fluent-plugin-protobuf-http/blob/master/LICENSE)
![GitHub release (latest by date)](https://img.shields.io/github/v/release/iamAzeem/fluent-plugin-protobuf-http?style=flat-square)
[![RubyGems Downloads](https://img.shields.io/gem/dt/fluent-plugin-protobuf-http?style=flat-square)](https://rubygems.org/gems/fluent-plugin-protobuf-http)

## Overview

[Fluentd](https://fluentd.org/) HTTP input plugin for
[Protocol Buffers](https://github.com/protocolbuffers/protobuf).

## Features

- Automatic compilation of `.proto` files located in `proto_dir`
- Incoming Format: Binary or JSON (`Content-Type`: `application/octet-stream` or
  `application/json`)
- Outgoing Format: Binary or JSON
- Single and Batch message support
- TLS Support with `<transport>` section and `https://` URL protocol prefix.

For more details on TLS configuration, see this official
[example](https://docs.fluentd.org/plugin-helper-overview/api-plugin-helper-server#configuration-example).

## Installation

### RubyGems

```shell
gem install fluent-plugin-protobuf-http
```

### Bundler

Add the following line to your Gemfile:

```ruby
gem 'fluent-plugin-protobuf-http'
```

And then execute:

```shell
bundle
```

## Configuration

- `bind` (string) (optional): The address to listen to.
  - Default: `0.0.0.0`
- `port` (integer) (optional): The port to listen to.
  - Default: `8080`
- `proto_dir` (string) (required): The directory path that contains the .proto files.
- `in_mode` (enum) (optional): The mode of incoming (supported) events.
  - Modes: `binary`, `json`
  - Default: `binary`
- `out_mode` (enum) (optional): The mode of outgoing (emitted) events.
  - Modes: `binary`, `json`
  - Default: `binary`
- `tag` (string) (required): The tag for the event.

### `<transport>` section (optional) (single)

- `protocol` (enum) (optional):
  - Protocols: `tcp`, `tls`
  - Default: `tcp`
  - For more details, see this official configuration
    [example](https://docs.fluentd.org/plugin-helper-overview/api-plugin-helper-server#configuration-example).

### Example

```text
# Endpoints:
# - Single Message: http://ip:port/<tag>?msgtype=<msgtype>
# - Batch  Message: http://ip:port/<tag>?msgtype=<batch-msgtype>?batch=true

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

## Schemas (`.proto` files)

The prime use-case for this plugin is assumed to be event logging. So, always
use self-contained `.proto` file(s) that do not import other `.proto` files. The
names e.g. `package`, `message`, etc. must be unique and are treated as
case-sensitive.

Consider this
[log.proto](https://github.com/iamAzeem/protobuf-log-sample/blob/master/log.proto)
schema from
[protobuf-log-sample](https://github.com/iamAzeem/protobuf-log-sample)
repository:

```protobuf
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

The fully-qualified message type for `Log` is `service.logging.Log`. This
message type is used as the value of `msgtype` query parameter in the URL. See
URL section below for more on `msgtype`.

### Single Message

The above schema will be used as-is for the single message.

### Batch Message

For the batch message, the schema must be like this:

```protobuf
message Batch {
  string type = 1;
  repeated Log batch = 2;
}
```

**IMPORTANT**: The `Batch` message type is part of `log.proto`, it is not a
separate file! You can choose any name for a batch message type.

Here is the complete `log.proto` file:

```protobuf
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

The type of `Batch` is `service.logging.Batch` and it will be the value of
`msgtype` in the URL query. The type of `batch` array is `service.logging.Log`
and it will be the value of `type`.

The `google.protobuf.Any` type has not been used here deliberately. It stores
the message type with each message resulting in an increase in size. Refer to
[protobuf-repeated-type-vs-any](https://github.com/iamAzeem/protobuf-repeated-type-vs-any)
for a simple comparison. With the above approach, the type is stored only once
for the whole batch.

### Endpoint (URL)

For single message:

```text
http://<ip>:<port>/<tag>?msgtype=<fully-qualified-message-type>
```

For batch message:

```text
http://<ip>:<port>/<tag>?msgtype=<fully-qualified-message-type-for-batch>&batch=true
```

Without `batch=true` query parameter, the batch will be treated as a single
message.

For example, for a log type `service.logging.Log` and its corresponding batch
type `service.logging.Batch`, the URLs would be:

For single message:

```text
http://localhost:8080/debug.test?msgtype=service.logging.Log
```

For batch message:

```text
http://localhost:8080/debug.test?msgtype=service.logging.Batch&batch=true
```

**NOTE**: The values of query parameters (`msgtype`, `batch`) are
case-sensitive!

## Test Use-Case (`curl`)

For a simple use-case of incoming HTTP events and their routing to
[stdout](https://docs.fluentd.org/output/stdout) may be configured like this:

`fluent.conf`:

```text
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

<match debug.test>
  @type       stdout
</match>
```

The incoming binary messages will be converted to JSON for further consumption.

### Single Message Use-case

Test Parameters:

| input file | single message type   |
|:----------:|:---------------------:|
| `log.bin`  | `service.logging.Log` |

URL:

```bash
http://localhost:8080/debug.test?msgtype=service.logging.Log
```

`curl` command:

```shell
curl -X POST -H "Content-Type: application/octet-stream" \
    --data-binary "@/<path>/log.bin" \
    "http://localhost:8080/debug.test?msgtype=service.logging.Log"
```

`fluentd` logs (Observe JSON at the end):

```text
2020-06-09 18:53:47 +0500 [info]: #0 [protobuf_http_input] [R] {binary} [127.0.0.1:41222, size: 86 bytes]
2020-06-09 18:53:47 +0500 [warn]: #0 [protobuf_http_input] 'batch' not found in 'query_string' [msgtype=service.logging.Log]
2020-06-09 18:53:47 +0500 [info]: #0 [protobuf_http_input] [S] {binary} [127.0.0.1:41222, msgtype: service.logging.Log, size: 86 bytes]
2020-06-09 18:53:47.025638542 +0500 debug.test: {"message":"{\"context\":{\"timestamp\":\"2020-06-01T16:24:19Z\",\"hostOrIp\":\"192.168.xxx.xxx\",\"serviceName\":\"test\",\"user\":\"test\"},\"level\":\"INFO\",\"message\":\"This is a test log generated by [./log.rb].\"}"}
2020-06-09 18:53:47 +0500 [info]: #0 [protobuf_http_input] [S] {json} [127.0.0.1:41222, msgtype: service.logging.Log, size: 183 bytes]
```

For generating sample Single messages, see
https://github.com/iamAzeem/protobuf-log-sample.

### Batch Message Use-case

Test Parameters:

| input file      | batch message type      | batch internal type   | messages |
|:---------------:|:-----------------------:|:---------------------:|:--------:|
| `logbatch2.bin` | `service.logging.Batch` | `service.logging.Log` | 2        |
| `logbatch5.bin` | `service.logging.Batch` | `service.logging.Log` | 5        |

URL:

```text
http://localhost:8080/debug.test?msgtype=service.logging.Batch&batch=true
```

**`logbatch2.bin`**

`curl` command:

```shell
$ curl -X POST -H "Content-Type: application/octet-stream" \
    --data-binary "@/<path>/logbatch2.bin" \
    "http://localhost:8080/debug.test?msgtype=service.logging.Batch&batch=true"
{"status":"Batch received! [batch_type: service.logging.Log, batch_size: 2 messages]"}
```

`fluentd` logs:

```text
2020-06-09 19:04:13 +0500 [info]: #0 [protobuf_http_input] [R] {binary} [127.0.0.1:41416, size: 207 bytes]
2020-06-09 19:04:13 +0500 [info]: #0 [protobuf_http_input] [B] {binary} [127.0.0.1:41416, msgtype: service.logging.Batch, size: 207 bytes]
2020-06-09 19:04:13 +0500 [info]: #0 [protobuf_http_input] [B] Emitting message stream/batch [batch_size: 2 messages]...
2020-06-09 19:04:13.546158307 +0500 debug.test: {"message":"{\"context\":{\"timestamp\":\"2020-06-08T17:27:05Z\",\"hostOrIp\":\"192.168.xxx.xxx\",\"serviceName\":\"test\",\"user\":\"test\"},\"level\":\"INFO\",\"message\":\"This is a test log generated by [./logbatch.rb].\"}"}
2020-06-09 19:04:13.546192659 +0500 debug.test: {"message":"{\"context\":{\"timestamp\":\"2020-06-08T17:27:05Z\",\"hostOrIp\":\"192.168.xxx.xxx\",\"serviceName\":\"test\",\"user\":\"test\"},\"level\":\"INFO\",\"message\":\"This is a test log generated by [./logbatch.rb].\"}"}
2020-06-09 19:04:13 +0500 [info]: #0 [protobuf_http_input] [B] {json} [127.0.0.1:41416, msgtype: service.logging.Batch] Batch received! [batch_type: service.logging.Log, batch_size: 2 messages]
```

**`logbatch5.bin`**

`curl` command:

```bash
$ curl -X POST -H "Content-Type: application/octet-stream" \
    --data-binary "@/<path>/logbatch5.bin" \
    "http://localhost:8080/debug.test?msgtype=service.logging.Batch&batch=true"
{"status":"Batch received! [batch_type: service.logging.Log, batch_size: 5 messages]"}
```

`fluentd` logs:

```text
2020-06-09 19:07:09 +0500 [info]: #0 [protobuf_http_input] [R] {binary} [127.0.0.1:41552, size: 486 bytes]
2020-06-09 19:07:09 +0500 [info]: #0 [protobuf_http_input] [B] {binary} [127.0.0.1:41552, msgtype: service.logging.Batch, size: 486 bytes]
2020-06-09 19:07:09 +0500 [info]: #0 [protobuf_http_input] [B] Emitting message stream/batch [batch_size: 5 messages]...
2020-06-09 19:07:09.738057617 +0500 debug.test: {"message":"{\"context\":{\"timestamp\":\"2020-06-08T17:27:05Z\",\"hostOrIp\":\"192.168.xxx.xxx\",\"serviceName\":\"test\",\"user\":\"test\"},\"level\":\"INFO\",\"message\":\"This is a test log generated by [./logbatch.rb].\"}"}
2020-06-09 19:07:09.738131040 +0500 debug.test: {"message":"{\"context\":{\"timestamp\":\"2020-06-08T17:27:05Z\",\"hostOrIp\":\"192.168.xxx.xxx\",\"serviceName\":\"test\",\"user\":\"test\"},\"level\":\"INFO\",\"message\":\"This is a test log generated by [./logbatch.rb].\"}"}
2020-06-09 19:07:09.738144897 +0500 debug.test: {"message":"{\"context\":{\"timestamp\":\"2020-06-08T17:27:05Z\",\"hostOrIp\":\"192.168.xxx.xxx\",\"serviceName\":\"test\",\"user\":\"test\"},\"level\":\"INFO\",\"message\":\"This is a test log generated by [./logbatch.rb].\"}"}
2020-06-09 19:07:09.738155033 +0500 debug.test: {"message":"{\"context\":{\"timestamp\":\"2020-06-08T17:27:05Z\",\"hostOrIp\":\"192.168.xxx.xxx\",\"serviceName\":\"test\",\"user\":\"test\"},\"level\":\"INFO\",\"message\":\"This is a test log generated by [./logbatch.rb].\"}"}
2020-06-09 19:07:09.738165527 +0500 debug.test: {"message":"{\"context\":{\"timestamp\":\"2020-06-08T17:27:05Z\",\"hostOrIp\":\"192.168.xxx.xxx\",\"serviceName\":\"test\",\"user\":\"test\"},\"level\":\"INFO\",\"message\":\"This is a test log generated by [./logbatch.rb].\"}"}
2020-06-09 19:07:09 +0500 [info]: #0 [protobuf_http_input] [B] {json} [127.0.0.1:41552, msgtype: service.logging.Batch] Batch received! [batch_type: service.logging.Log, batch_size: 5 messages]
```

For sample Batch message generation, see
[this gist](https://gist.github.com/iamAzeem/a8a24092132e1741a76956192f2104cc).

## CI Workflow

The [CI workflow](.github/workflows/ci.yml) sets up the prerequisites. It
builds and installs the plugin, and then runs the automated tests.

To run tests locally, run:

```shell
bundle exec rake test
```

The [test](./test) directory contains the tests and the [input](./test/data)
files.

The code coverage is printed at the end using `simplecov`.

## Known Issues

- This plugin internally uses the HTTP server plugin
  [helper](https://docs.fluentd.org/plugin-helper-overview/api-plugin-helper-http_server)
  which has higher precedence for `async-http` over `webrick`. But,
  [`webrick`](https://github.com/ruby/webrick) is required to run this. In an
  environment where both are installed, `async-http` is automatically selected
  causing runtime issues. To make this work, you need to uninstall `async-http`
  i.e. `gem uninstall async-http`. See issue
  [#10](https://github.com/iamazeem/fluent-plugin-protobuf-http/issues/10) for
  more details where this was identified in Docker containers where both gems
  were already installed.

## Contribute

- [Fork](https://github.com/iamazeem/fluent-plugin-protobuf-http/fork) the project.
- Check out the latest `main` branch.
- Create a `feature` or `bugfix` branch from `main`.
- Commit and push your changes.
- Make sure to add and run tests locally: `bundle exec rake test`.
- Run [Rubocop](https://github.com/rubocop/rubocop) and fix the lint errors.
- Submit the PR.

## License

[Apache 2.0](LICENSE)
