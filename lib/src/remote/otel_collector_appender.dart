import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:logging_appenders/src/internal/dummy_logger.dart';
import 'package:logging_appenders/src/remote/base_remote_appender.dart';

final _logger = DummyLogger('logging_appenders.otel_appender');

/// Appender used to push logs to [Open Telemetry](https://opentelemetry.io/docs/collector/).
class OpenTelemetryApiAppender extends BaseDioLogSender {
  OpenTelemetryApiAppender({
    required this.server,
    required this.username,
    required this.password,
    required this.labels,
    int? bufferSize,
  }) : labelsString =
            '{${labels.entries.map((entry) => '${entry.key}="${entry.value}"').join(',')}}',
        authHeader = 'Basic ${base64.encode(utf8.encode([
          username,
          password
        ].join(':')))}', super(bufferSize: bufferSize);

  final String server;
  final String username;
  final String password;
  final String authHeader;
  final Map<String, String> labels;
  final String labelsString;

  Dio? _clientInstance;

  Dio get _client => _clientInstance ??= Dio();

  static String _encodeLineLabelValue(String value) {
    if (value.contains(' ')) {
      return json.encode(value);
    }
    return value;
  }

  @override
  Future<void> sendLogEventsWithDio(
    List<LogEntry> entries,
    Map<String, String> userProperties,
    CancelToken cancelToken,
  ) {
    if (entries.isEmpty) {
      return Future<void>.value(null);
    }
    var logRequest = LogRequest(
      resourceLogs: [
        ResourceLogs(
          resource: Resource(
            attributes: [
              Attributes(
                key: 'resource-attr',
                value: Value(stringValue: 'server-1'),
              ),
            ],
          ),
          scopeLogs: [
            ScopeLogs(
              logRecords: entriesToLogRecord(entries),
            ),
          ],
        ),
      ],
    );
    final jsonBody = json.encode(logRequest);
    return _client
        .post<dynamic>(
          'https://$server/v1/logs',
          cancelToken: cancelToken,
          data: jsonBody,
          options: Options(
            headers: <String, String>{
              HttpHeaders.authorizationHeader: authHeader,
            },
            contentType: ContentType(
                    ContentType.json.primaryType, ContentType.json.subType)
                .value,
          ),
        )
        .then(
          (response) => Future<void>.value(null),
//      _logger.finest('sent logs.');
        )
        .catchError(
      (Object err, StackTrace stackTrace) {
        String? message;
        if (err is DioError) {
          if (err.response != null) {
            message = 'response:${err.response!.data}';
          }
        }
        _logger.warning(
            'Error while sending logs to OpenTelemetry Collector. $message',
            err,
            stackTrace);
        return Future<void>.error(err, stackTrace);
      },
    );
  }

  Iterable<LogRecord> entriesToLogRecord(List<LogEntry> entries) {
    return entries.map(
      (entry) => LogRecord(
        timeUnixNano: (entry.ts.microsecondsSinceEpoch * 1000).toString(),
        body: Body(stringValue: entry.line),
        attributes: entry.lineLabels.entries
            .map(
              (var mapEntry) => Attributes(
                key: 'key',
                value: Value(stringValue: mapEntry.value),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class LogRequest {
  LogRequest({
    required this.resourceLogs,
  });
  late final List<ResourceLogs> resourceLogs;

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['resourceLogs'] = resourceLogs.map((e) => e.toJson()).toList(growable: false);
    return data;
  }
}

class ResourceLogs {
  ResourceLogs({
    required this.resource,
    required this.scopeLogs,
  });
  late final Resource resource;
  late final Iterable<ScopeLogs> scopeLogs;

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['resource'] = resource.toJson();
    data['scopeLogs'] = scopeLogs.map((e) => e.toJson()).toList(growable: false);
    return data;
  }
}

class Resource {
  Resource({
    required this.attributes,
  });
  late final List<Attributes> attributes;

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['attributes'] = attributes.map((e) => e.toJson()).toList(growable: false);
    return data;
  }
}

class Attributes {
  Attributes({
    required this.key,
    required this.value,
  });
  late final String key;
  late final Value value;

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['key'] = key;
    data['value'] = value.toJson();
    return data;
  }
}

class Value {
  Value({
    required this.stringValue,
  });
  late final String stringValue;

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['stringValue'] = stringValue;
    return data;
  }
}

class ScopeLogs {
  ScopeLogs({
    this.scope,
    required this.logRecords,
  });
  late final Scope? scope;
  late final Iterable<LogRecord> logRecords;

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['scope'] = scope?.toJson() ?? {};
    data['logRecords'] = logRecords.map((e) => e.toJson()).toList(growable: false);
    return data;
  }
}

class Scope {
  Scope();

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    return data;
  }
}

class LogRecord {
  LogRecord({
    required this.timeUnixNano,
    this.severityNumber,
    this.severityText,
    this.name,
    this.body,
    this.attributes,
    this.droppedAttributesCount,
    this.traceId,
    this.spanId,
  });
  String? timeUnixNano;
  int? severityNumber;
  String? severityText;
  String? name;
  Body? body;
  List<Attributes>? attributes;
  int? droppedAttributesCount;
  String? traceId;
  String? spanId;

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['timeUnixNano'] = timeUnixNano;
    if (severityNumber != null) data['severityNumber'] = severityNumber;
    if (severityText != null) data['severityText'] = severityText;
    if (name != null) data['name'] = name;
    if (body != null) data['body'] = body!.toJson();
    if (attributes != null) {
      data['attributes'] = attributes!.map((e) => e.toJson()).toList(growable: false);
    }
    if (droppedAttributesCount != null) {
      data['droppedAttributesCount'] = droppedAttributesCount;
    }
    if (traceId != null) data['traceId'] = traceId;
    if (spanId != null) data['spanId'] = spanId;
    return data;
  }
}

class Body {
  Body({
    required this.stringValue,
  });
  late final String stringValue;

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['stringValue'] = stringValue;
    return data;
  }
}
