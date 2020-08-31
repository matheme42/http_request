import 'dart:convert' as convert;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';

enum HttpRequestDebug {
  NONE,
  REQUEST_MIN,
  REQUEST_MAX,
  ANSWER_MIN,
  ANSWER_MAX,
  MIN,
  MAX
}

class HttpRequest {
  static Logger _logger = Logger("HttpRequest");

  /// contains the list of each instances of [HttpRequest]
  static final Map<String, HttpRequest> _instances = Map<String, HttpRequest>();

  static String _defaultConfiguration;

  /// check in the instances if the [HttpRequest] Configuration exist
  factory HttpRequest([String name]) {
    if (name == "") {
      throw ArgumentError("name shouldn't be empty");
    }
    if (name == null && _defaultConfiguration == null) {
      throw ArgumentError(
          "defaultConfiguration not define can't take a configuration");
    }
    if (name == null) {
      name = _defaultConfiguration;
    }
    if (_instances.containsKey(name)) {
      return _instances[name];
    }

    _instances[name] = HttpRequest._privateConstructor(name);
    return _instances[name];
  }

  HttpRequest._privateConstructor(this._name);

  /// this is the unique name of the [HttpRequest]
  String _name;

  /// this variable define the protocol use to make the request
  /// this can be http or https
  String _https = "http";

  /// this variable contains the authority you want to send the request
  /// the server need to be configure
  String _server = "";

  /// the port use to communicate with the server
  String _port = "";

  /// this variable define the timeout of each request
  Duration _timeOut = Duration(seconds: 4);

  /// this variable can be empty
  /// you can reffered a default path like
  /// http://exemple.com/my_domain
  /// the domain must start with a /
  String _domain = "";

  /// [onRequestError] in a function call if something wrong with the request
  /// like no Response, TimeOut, 400, 404, 500, etc...
  /// this function is [global] for all the instance of [HttpRequest]
  static void Function(http.Response response) onRequestError;

  HttpRequestDebug _httpRequestDebug = HttpRequestDebug.MIN;

  void configure(
      {bool https,
      String server,
      String port,
      String domain,
      Duration timeOut,
      HttpRequestDebug httpRequestDebug,
      bool useByDefault}) {
    if (https != null) _https = https == false ? "http" : "https";
    if (server != null) _server = server;
    if (port != null) _port = port;
    if (domain != null) _domain = domain;
    if (timeOut != null) _timeOut = timeOut;
    if (httpRequestDebug != null) _httpRequestDebug = httpRequestDebug;
    if (useByDefault == true) _defaultConfiguration = _name;

    /// throw an exception if the configuration is not good define
    _checkConfiguration();
  }

  void unConfigure() {
    _logger.info("unConfigure MOJO HTTP REQUEST $_name configuration");
    _instances.remove(_name);
  }

  /// this getter construct the request url with the configuration
  String get _requestUrl {
    if (_port == "") return "$_server";
    return "$_server:$_port";
  }

  bool _checkConfiguration() {
    if (_server == "") {
      _logger.warning(
          "you need to specified the server who response to the request");
      _logger.warning(
          "use MojoHttpRequest.configure(server: 'server.com', port: 8080)");
      throw ArgumentError();
    }

    try {
      int.parse(_port);
    } catch (_) {
      _logger.warning(
          "you need to specified a valid port must be like 5050, 80, 3000 etc");
      throw ArgumentError();
    }

    if (!_domain.startsWith('/') && _domain != "") {
      _logger.warning("you need to specified a valid domain '/domain'");
      _logger.warning("use MojoHttpRequest.configure(domain: '/yourDomain')");
      throw ArgumentError();
    }
    return true;
  }

  dynamic _processResponse(
      http.Response response, String service, DateTime timeSendRequest) {
    if (response == null) {
      if (onRequestError != null) onRequestError(response);
      return null;
    }

    if (_httpRequestDebug == HttpRequestDebug.ANSWER_MIN ||
        _httpRequestDebug == HttpRequestDebug.ANSWER_MAX ||
        _httpRequestDebug == HttpRequestDebug.MIN ||
        _httpRequestDebug == HttpRequestDebug.MAX)
      _logger.info(
          "<-- ${response.request} ${DateFormat.Hms().format(timeSendRequest)} (${DateTime.now().difference(timeSendRequest).inMilliseconds} ms ${response.statusCode} ${response.reasonPhrase})");
    if (_httpRequestDebug == HttpRequestDebug.ANSWER_MAX ||
        _httpRequestDebug == HttpRequestDebug.MAX)
      _logger.info("<-- ${response.body}");

    if (response.statusCode != 200) {
      if (onRequestError != null) onRequestError(response);
      return null;
    }

    try {
      return convert.jsonDecode(response.body);
    } catch (_){}
    return response.body.toString();
  }

  void _showRequestLog(String method, Uri url, Map<String, dynamic> jsonBody,
      DateTime timeSendRequest) {
    if (_httpRequestDebug == HttpRequestDebug.REQUEST_MIN ||
        _httpRequestDebug == HttpRequestDebug.REQUEST_MAX ||
        _httpRequestDebug == HttpRequestDebug.MIN ||
        _httpRequestDebug == HttpRequestDebug.MAX)
      _logger
          .info("--> $method $url ${DateFormat.Hms().format(timeSendRequest)}");
    if (_httpRequestDebug == HttpRequestDebug.REQUEST_MAX ||
        _httpRequestDebug == HttpRequestDebug.MAX)
      _logger.info("--> $jsonBody");
  }

  dynamic post(String service,
      [Map<String, dynamic> jsonBody = const {}, attempt = 1]) async {
    DateTime timeSendRequest = DateTime.now();
    http.Response response;

    Uri url = Uri.parse("$_https://$_requestUrl$_domain$service");
    _showRequestLog("POST", url, jsonBody, timeSendRequest);
    try {
      response = await http
          .post(url,
              headers: {HttpHeaders.contentTypeHeader: 'application/json'},
              body: convert.json.encode(jsonBody))
          .timeout(_timeOut);
    } catch (error) {
      _logger.info("<-- $error");
    }

    /// retry if no response from server
    if (response == null && attempt > 0) {
      _logger.warning("-- can't reach the backend less ($attempt) attempts");
      await Future.delayed(Duration(seconds: 2));
      return post(service, jsonBody, attempt - 1);
    }

    return _processResponse(response, service, timeSendRequest);
  }

  dynamic put(String service,
      [Map<String, dynamic> jsonBody = const {}, attempt = 1]) async {
    DateTime timeSendRequest = DateTime.now();
    http.Response response;

    Uri url = Uri.parse("$_https://$_requestUrl$_domain$service");
    _showRequestLog("PUT", url, jsonBody, timeSendRequest);

    try {
      response = await http
          .put(url,
              headers: {HttpHeaders.contentTypeHeader: 'application/json'},
              body: convert.json.encode(jsonBody))
          .timeout(_timeOut);
    } catch (error) {
      _logger.info("<-- $error");
    }

    /// retry if no response from server
    if (response == null && attempt > 0) {
      _logger.warning("-- can't reach the backend less ($attempt) attempts");
      await Future.delayed(Duration(seconds: 2));
      return put(service, jsonBody, attempt - 1);
    }

    return _processResponse(response, service, timeSendRequest);
  }

  dynamic get(String service,
      [Map<String, String> jsonBody = const {}, attempt = 1]) async {
    DateTime timeSendRequest = DateTime.now();
    http.Response response;

    Uri url = _https == "https"
        ? Uri.https(_requestUrl, "$_domain$service", jsonBody)
        : Uri.http(_requestUrl, "$_domain$service", jsonBody);

    _showRequestLog("GET", url, jsonBody, timeSendRequest);

    try {
      response = await http.get(url, headers: {
        HttpHeaders.contentTypeHeader: 'application/json'
      }).timeout(_timeOut);
    } catch (error) {
      _logger.info("<-- $error");
    }

    /// retry if no response from server
    if (response == null && attempt > 0) {
      _logger.warning("-- can't reach the backend less ($attempt) attempts");
      await Future.delayed(Duration(seconds: 2));
      return post(service, jsonBody, attempt - 1);
    }

    return _processResponse(response, service, timeSendRequest);
  }

  dynamic delete(String service,
      [Map<String, String> jsonBody = const {}, attempt = 1]) async {
    DateTime timeSendRequest = DateTime.now();
    http.Response response;

    Uri url = _https == "https"
        ? Uri.https(_requestUrl, "$_domain$service", jsonBody)
        : Uri.http(_requestUrl, "$_domain$service", jsonBody);

    _showRequestLog("DELETE", url, jsonBody, timeSendRequest);

    try {
      response = await http.delete(url, headers: {
        HttpHeaders.contentTypeHeader: 'application/json'
      }).timeout(_timeOut);
    } catch (error) {
      _logger.info("<-- $error");
    }

    /// retry if no response from server
    if (response == null && attempt > 0) {
      _logger.warning("-- can't reach the backend less ($attempt) attempts");
      await Future.delayed(Duration(seconds: 2));
      return post(service, jsonBody, attempt - 1);
    }

    return _processResponse(response, service, timeSendRequest);
  }
}
