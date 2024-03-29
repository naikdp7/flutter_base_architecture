import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dio_http_cache/dio_http_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_base_architecture/exception/base_error.dart';
import 'package:flutter_base_architecture/utils/app_logger.dart';

class RESTService {
  static const int GET = 1;
  static const int POST = 2;
  static const int PUT = 3;
  static const int DELETE = 4;
  static const int FORMDATA = 5;
  static const int URI = 6;
  static const int PATCH = 7;
  static const int PATCH_URI = 8;
  static const int PATCH_FROM_DATA = 9;
  static const int POST_QUERY = 10;
  static const String data = "data";
  static const String API_URL = "APIURL";
  static const String EXTRA_FORCE_REFRESH = "EXTRA_FORCE_REFRESH";
  static const String EXTRA_HTTP_VERB = "EXTRA_HTTP_VERB";
  static const String REST_API_CALL_IDENTIFIER = "REST_API_CALL_IDENTIFIER";
  static const String EXTRA_PARAMS = "EXTRA_PARAMS";
  DioCacheManager? _dioCacheManager;

  Future<Response>? onHandleIntent(Map<String, dynamic> params) async {
    dynamic action = params.putIfAbsent(data, () {});

    int verb = params.putIfAbsent(EXTRA_HTTP_VERB, () {
      return GET;
    });

    String apiUrl = params.putIfAbsent(API_URL, () {
      return "";
    });

    bool forceRefresh = params.putIfAbsent(EXTRA_FORCE_REFRESH, () {
      return false;
    });

    int apiCallIdentifier = params.putIfAbsent(REST_API_CALL_IDENTIFIER, () {
      return -1;
    });

    Map<String, dynamic> parameters = params.putIfAbsent(EXTRA_PARAMS, () {
      return null;
    });

    try {
      Dio request = Dio();
      _dioCacheManager ??= DioCacheManager(CacheConfig(baseUrl: apiUrl));
      request.interceptors
        ..add(_dioCacheManager?.interceptor)
        ..add(InterceptorsWrapper(onError: (DioError e,ErrorInterceptorHandler errorInterceptorHandler) async {
          if (e.response != null) {
            AppLogger.log(e.response!.data);
            AppLogger.log(e.response!.headers);
            AppLogger.log(e.response!.requestOptions);

            return errorInterceptorHandler.resolve(await parseErrorResponse(e, apiCallIdentifier));
          } else {
            // Something happened in setting up or sending the request that triggered an Error
            AppLogger.log(e.requestOptions);
            AppLogger.log(e.message);
            return errorInterceptorHandler.resolve(await parseErrorResponse(e, apiCallIdentifier));
          }
        }, onResponse: (response,ResponseInterceptorHandler responseInterceptorHandler) {
          response.headers
              .add("apicallidentifier", apiCallIdentifier.toString());
          response.extra.update("apicallidentifier", (value) => value,
              ifAbsent: () => apiCallIdentifier);
          response.extra
              .update("cached", (value) => false, ifAbsent: () => false);
          return responseInterceptorHandler.next(response);
        }));
      request.options.headers['apicallidentifier'] = apiCallIdentifier;
      request.options.extra.update("apicallidentifier", (value) => value,
          ifAbsent: () => apiCallIdentifier);
      if (getHeaders() != null) {
        getHeaders()?.forEach((key, value) {
          request.options.headers[key] = value;
        });
      }
      if (!kIsWeb) {
        if (forceRefresh) {
          request.options.extra
              .update("cached", (value) => value, ifAbsent: () => false);
        } else {
          request.options.extra.addAll(
              buildCacheOptions(Duration(days: 7), forceRefresh: forceRefresh)
                  .extra!);
          request.options.extra
              .update("cached", (value) => value, ifAbsent: () => true);
        }
      } else {
        request.options.extra
            .update("cached", (value) => value, ifAbsent: () => false);
      }
      request.interceptors.add(LogInterceptor(responseBody: false));
      logParams(parameters);

      switch (verb) {
        case RESTService.GET:
          Future<Response> response = request.get(action,
              queryParameters: attachUriWithQuery(parameters));
          return parseResponse(response, apiCallIdentifier);

        case RESTService.URI:
          Uri uri = action as Uri;
          Future<Response> response = request.getUri(Uri(
              scheme: uri.scheme,
              host: uri.host,
              path: uri.path,
              queryParameters: attachUriWithQuery(parameters)));

          return parseResponse(response, apiCallIdentifier);

        case RESTService.POST:
          /* request.options.contentType =
              ContentType.parse("application/x-www-form-urlencoded");
*/

          Future<Response> response = request.post(
            action,
            data: parameters,
          );
          //  Future<Response> response = request.post(action,data: paramsToJson(parameters));
          return parseResponse(response, apiCallIdentifier);
        // return request.post(action,data: paramsToJson(parameters));

        case RESTService.FORMDATA:
          FormData formData = FormData.fromMap(parameters);
          Future<Response> response = request.post(action, data: formData);
          return parseResponse(response, apiCallIdentifier);

        case RESTService.PUT:
          Future<Response> response =
              request.put(action, data: paramstoJson(parameters));
          return parseResponse(response, apiCallIdentifier);
          break;

        case RESTService.DELETE:
          Future<Response> response =
              request.delete(action, data: paramstoJson(parameters));
          return parseResponse(response, apiCallIdentifier);
          break;

        case RESTService.PATCH:
          Future<Response> response = request.patch(action, data: parameters);
          return parseResponse(response, apiCallIdentifier);
          break;

        case RESTService.PATCH_FROM_DATA:
          FormData formData = FormData.fromMap(parameters);
          Future<Response> response = request.patch(action, data: formData);
          return parseResponse(response, apiCallIdentifier);
          break;

        case RESTService.PATCH_URI:
          Uri uri = Uri.parse(action);
          Future<Response> response = request.patchUri(Uri(
              scheme: uri.scheme,
              port: uri.port,
              host: uri.host,
              path: uri.path,
              queryParameters: attachUriWithQuery(parameters)));

          return parseResponse(response, apiCallIdentifier);
          break;

        case RESTService.POST_QUERY:
          Future<Response> response = request.post(action,
              queryParameters: attachUriWithQuery(parameters));
          return parseResponse(response, apiCallIdentifier);

        default:
          throw DioError(
            response: Response(
                headers: Headers(), requestOptions: RequestOptions(path: '')),
            requestOptions: RequestOptions(path: ''),
          );
      }
    } catch (error, stacktrace) {
      AppLogger.log("Exception occured: $error stackTrace: $stacktrace");
      // AppLogger.log(_handleError(error));
      return parseErrorResponse(error as Exception, apiCallIdentifier);
      // The request was made and the server responded with a status code
      // that falls out of the range of 2xx and is also not 304.
      /* AppLogger.log("Exception e::"+e.toString());
      if(e is DioError) {
        AppLogger.log("DioError e::"+e.toString());
        if (e.response != null) {
          AppLogger.log(e.response.data);
          AppLogger.log(e.response.headers);
          AppLogger.log(e.response.request);

          return parseErrorResponse(e, apiCallIdentifier);
        } else {
          // Something happened in setting up or sending the request that triggered an Error
          AppLogger.log(e.request);
          AppLogger.log(e.message);
          return parseErrorResponse(e, apiCallIdentifier);
        }
      }else{
        AppLogger.log("e::"+e.toString());
      }*/

    }
  }

  Future<bool> clearNetworkCache() {
    if (_dioCacheManager != null) return _dioCacheManager?.clearAll()??Future.value(false);
    return Future.value(false);
  }

  BaseError _handleError(Exception error) {
    BaseError amerError = BaseError(message: '');

    if (error is DioError) {
      switch (error.type) {
        case DioErrorType.cancel:
          amerError.type = BaseErrorType.DEFAULT;
          amerError.message = "Request to API server was cancelled";
          break;
        case DioErrorType.connectTimeout:
          amerError.type = BaseErrorType.SERVER_TIMEOUT;
          amerError.message = "Connection timeout with API server";
          break;
        case DioErrorType.other:
          amerError.type = BaseErrorType.DEFAULT;
          amerError.message =
              "Connection to API server failed due to internet connection";
          break;
        case DioErrorType.receiveTimeout:
          amerError.type = BaseErrorType.SERVER_TIMEOUT;
          amerError.message = "Receive timeout in connection with API server";
          break;
        case DioErrorType.response:
          amerError.type = BaseErrorType.INVALID_RESPONSE;
          amerError.message =
              "Received invalid status code: ${error.response?.statusCode}";
          break;
        case DioErrorType.sendTimeout:
          amerError.type = BaseErrorType.SERVER_TIMEOUT;
          amerError.message = "Receive timeout exception";
          break;
      }
    } else {
      amerError.type = BaseErrorType.UNEXPECTED;
      amerError.message = "Unexpected error occured";
    }
    return amerError;
  }

  logParams(Map<String, dynamic> params) {
    AppLogger.log("Parameters:");
    AppLogger.log("$params");
  }

  paramstoJson(Map<String, dynamic> params) {
    return json.encode(params);
  }

  Future<Response> parseErrorResponse(
      Exception exception, apiCallIdentifier) async {
    return await Future<Response>(() {
      Response? response;

      if (exception is DioError) {
        if (exception.response != null) {
          response = exception.response;
        } else {
          response = Response(
              headers: Headers(), requestOptions: RequestOptions(path: ''));
        }
      } else {
        response = Response(
            headers: Headers(), requestOptions: RequestOptions(path: ''));
      }
      //response.data = null;
      response?.headers.set("apicallidentifier", apiCallIdentifier.toString());

      //response.statusMessage = _handleError(exception);
      response?.extra = Map();
      response?.extra.putIfAbsent("exception", () => _handleError(exception));
      response?.extra.update("apicallidentifier", (value) => value,
          ifAbsent: () => apiCallIdentifier);
      response?.extra.update("cached", (value) => false, ifAbsent: () => false);
      return Future.value(response);
    });
  }

  Future<Response> parseResponse(
      Future<Response> response, apiCallIdentifier) async {
    return await response;
  }

  dynamic paramsToJson(Map<String, dynamic> parameters) {
    return json.encode(parameters);
  }

  Map<String, dynamic> attachUriWithQuery(Map<String, dynamic> parameters) {
    return parameters;
  }

  Map<String, dynamic>? getHeaders() {
    return null;
  }
}
