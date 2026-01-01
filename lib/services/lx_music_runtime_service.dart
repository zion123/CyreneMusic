import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart' as crypto;
import '../models/track.dart';

/// 洛雪音源运行时服务
/// 
/// 使用隐藏的 WebView 沙箱执行洛雪音源 JS 脚本，
/// 完全在前端处理，不依赖后端解密服务。
/// 
/// 核心原理：
/// 1. 创建一个隐藏的 WebView 作为 JavaScript 沙箱
/// 2. 注入 lx API (模拟洛雪音乐桌面版的 API)
/// 3. 执行用户脚本，脚本会注册请求处理器
/// 4. 当需要获取音乐 URL 时，调用脚本的请求处理器
/// 5. 脚本通过 lx.request() 发起 HTTP 请求（由 Dart 代理执行）
/// 6. 返回音乐 URL
class LxMusicRuntimeService {
  static final LxMusicRuntimeService _instance = LxMusicRuntimeService._internal();
  factory LxMusicRuntimeService() => _instance;
  LxMusicRuntimeService._internal();

  /// HeadlessInAppWebView 实例（隐藏的 WebView）
  HeadlessInAppWebView? _headlessWebView;
  
  /// WebView 控制器
  InAppWebViewController? _webViewController;
  
  /// 是否已初始化
  bool _isInitialized = false;
  
  /// 当前加载的脚本信息
  LxScriptInfo? _currentScript;
  
  /// 脚本是否已就绪
  bool _isScriptReady = false;
  
  /// 等待初始化完成的 Completer
  Completer<bool>? _initCompleter;
  
  /// 请求回调映射
  final Map<String, Completer<String>> _pendingRequests = {};
  
  /// 请求计数器
  int _requestCounter = 0;
  
  /// 脚本初始化时解析的支持音源列表（临时保存）
  List<String> _pendingSupportedSources = [];

  // ==================== Getters ====================
  
  bool get isInitialized => _isInitialized;
  bool get isScriptReady => _isScriptReady;
  LxScriptInfo? get currentScript => _currentScript;

  // ==================== 生命周期 ====================

  /// 初始化 WebView 沙箱
  Future<void> initialize() async {
    if (_isInitialized) {
      print('⚠️ [LxMusicRuntime] 已经初始化');
      return;
    }

    print('🚀 [LxMusicRuntime] 开始初始化 WebView 沙箱...');

    _initCompleter = Completer<bool>();

    // 创建隐藏的 WebView
    _headlessWebView = HeadlessInAppWebView(
      initialData: InAppWebViewInitialData(
        data: _generateSandboxHtml(),
        mimeType: 'text/html',
        encoding: 'utf-8',
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: false,
        databaseEnabled: false,
        cacheEnabled: false,
        // 安全设置
        allowFileAccess: false,
        allowContentAccess: false,
        javaScriptCanOpenWindowsAutomatically: false,
      ),
      onWebViewCreated: (controller) {
        _webViewController = controller;
        print('✅ [LxMusicRuntime] WebView 创建成功');
        
        // 注册 JavaScript 通道
        _registerJavaScriptHandlers(controller);
      },
      onLoadStop: (controller, url) async {
        print('✅ [LxMusicRuntime] WebView 加载完成');
        _isInitialized = true;
        _initCompleter?.complete(true);
      },
      onConsoleMessage: (controller, message) {
        print('🌐 [WebView Console] ${message.message}');
      },
      onLoadError: (controller, url, code, message) {
        print('❌ [LxMusicRuntime] 加载错误: $code - $message');
        _initCompleter?.complete(false);
      },
    );

    // 启动 WebView
    await _headlessWebView!.run();
    
    // 等待初始化完成
    final success = await _initCompleter!.future;
    if (!success) {
      throw Exception('WebView 初始化失败');
    }

    print('✅ [LxMusicRuntime] 初始化完成');
  }

  /// 销毁 WebView
  Future<void> dispose() async {
    print('🗑️ [LxMusicRuntime] 销毁 WebView...');
    
    _isInitialized = false;
    _isScriptReady = false;
    _currentScript = null;
    _pendingRequests.clear();
    
    await _headlessWebView?.dispose();
    _headlessWebView = null;
    _webViewController = null;
  }

  // ==================== 脚本管理 ====================

  /// 加载并执行洛雪音源脚本
  /// 
  /// [scriptContent] - 脚本内容
  /// 
  /// 返回脚本信息，如果加载失败返回 null
  Future<LxScriptInfo?> loadScript(String scriptContent) async {
    if (!_isInitialized) {
      print('❌ [LxMusicRuntime] WebView 未初始化');
      return null;
    }

    print('📜 [LxMusicRuntime] 加载脚本...');
    _isScriptReady = false;

    try {
      // 1. 解析脚本信息
      final scriptInfo = _parseScriptInfo(scriptContent);
      print('📋 [LxMusicRuntime] 脚本信息:');
      print('   名称: ${scriptInfo.name}');
      print('   版本: ${scriptInfo.version}');
      print('   作者: ${scriptInfo.author}');

      // 2. 重置 WebView 状态
      await _webViewController?.evaluateJavascript(source: '''
        window.__lx_reset__();
      ''');

      // 3. 注入脚本信息（包含完整脚本内容用于 rawScript）
      // 将脚本内容进行 Base64 编码以避免 JSON 转义问题
      final scriptBase64 = base64Encode(utf8.encode(scriptContent));
      final scriptInfoJson = jsonEncode({
        'name': scriptInfo.name,
        'version': scriptInfo.version,
        'author': scriptInfo.author,
        'description': scriptInfo.description,
        'homepage': scriptInfo.homepage,
        'scriptBase64': scriptBase64,  // 完整脚本内容的 Base64 编码
      });
      
      await _webViewController?.evaluateJavascript(source: '''
        window.__lx_setScriptInfo__($scriptInfoJson);
      ''');

      // 4. 执行用户脚本
      // 使用 try-catch 包装脚本执行
      final wrappedScript = '''
        (function() {
          try {
            $scriptContent
          } catch (e) {
            window.__lx_onError__(e.message || String(e));
          }
        })();
      ''';

      await _webViewController?.evaluateJavascript(source: wrappedScript);

      // 5. 等待脚本初始化完成（最多等待 10 秒）
      final startTime = DateTime.now();
      while (!_isScriptReady) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (DateTime.now().difference(startTime).inSeconds > 10) {
          print('⚠️ [LxMusicRuntime] 脚本初始化超时');
          return null;
        }
      }

      // 6. 用从 lxOnInited 获取的支持音源更新 scriptInfo
      final updatedScriptInfo = LxScriptInfo(
        name: scriptInfo.name,
        version: scriptInfo.version,
        author: scriptInfo.author,
        description: scriptInfo.description,
        homepage: scriptInfo.homepage,
        script: scriptInfo.script,
        supportedSources: _pendingSupportedSources,
      );
      
      _currentScript = updatedScriptInfo;
      print('✅ [LxMusicRuntime] 脚本加载成功');
      print('   支持的平台: ${updatedScriptInfo.supportedPlatforms}');
      return updatedScriptInfo;
    } catch (e) {
      print('❌ [LxMusicRuntime] 脚本加载失败: $e');
      return null;
    }
  }

  /// 获取音乐播放 URL
  /// 
  /// [source] - 音源类型 (wy/tx/kg/kw/mg)
  /// [songId] - 歌曲 ID
  /// [quality] - 音质 (128k/320k/flac/flac24bit)
  /// [musicInfo] - 歌曲信息（可选，某些脚本需要）
  Future<String?> getMusicUrl({
    required String source,
    required dynamic songId,
    required String quality,
    Map<String, dynamic>? musicInfo,
  }) async {
    if (!_isInitialized || !_isScriptReady) {
      print('❌ [LxMusicRuntime] 服务未就绪');
      return null;
    }

    final requestKey = 'req_${++_requestCounter}_${DateTime.now().millisecondsSinceEpoch}';
    final completer = Completer<String>();
    _pendingRequests[requestKey] = completer;

    try {
      // 构建音乐信息
      final info = musicInfo ?? {
        'songmid': songId.toString(),
        'copyrightId': songId.toString(),
        'hash': songId.toString(),
      };

      final requestData = jsonEncode({
        'requestKey': requestKey,
        'source': source,
        'action': 'musicUrl',
        'info': {
          'musicInfo': info,
          'type': quality,
        },
      });

      print('🎵 [LxMusicRuntime] 请求音乐 URL:');
      print('   source: $source, songId: $songId, quality: $quality');

      await _webViewController?.evaluateJavascript(source: '''
        window.__lx_sendRequest__($requestData);
      ''');

      // 等待响应（最多 30 秒）
      final result = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _pendingRequests.remove(requestKey);
          throw TimeoutException('请求超时');
        },
      );

      _pendingRequests.remove(requestKey);
      return result;
    } catch (e) {
      print('❌ [LxMusicRuntime] 获取 URL 失败: $e');
      _pendingRequests.remove(requestKey);
      return null;
    }
  }

  /// 将 MusicSource 转换为洛雪格式
  static String? getSourceCode(MusicSource source) {
    switch (source) {
      case MusicSource.netease:
        return 'wy';
      case MusicSource.qq:
        return 'tx';
      case MusicSource.kugou:
        return 'kg';
      case MusicSource.kuwo:
        return 'kw';
      default:
        return null;
    }
  }

  // ==================== 私有方法 ====================

  /// 注册 JavaScript 处理器
  void _registerJavaScriptHandlers(InAppWebViewController controller) {
    // 处理脚本初始化完成
    controller.addJavaScriptHandler(
      handlerName: 'lxOnInited',
      callback: (args) {
        print('✅ [LxMusicRuntime] 脚本初始化完成');
        if (args.isNotEmpty) {
          final data = args[0];
          final sources = data['sources'];
          if (sources != null && sources is Map) {
            _pendingSupportedSources = sources.keys.map((k) => k.toString()).toList();
            print('   支持的音源: $_pendingSupportedSources');
          } else {
            _pendingSupportedSources = [];
          }
        }
        _isScriptReady = true;
        return null;
      },
    );

    // 处理 HTTP 请求
    controller.addJavaScriptHandler(
      handlerName: 'lxRequest',
      callback: (args) async {
        if (args.isEmpty) return null;
        
        final data = args[0] as Map<String, dynamic>;
        final requestId = data['requestId'] as String;
        final url = data['url'] as String;
        final options = data['options'] as Map<String, dynamic>? ?? {};
        
        print('🌐 [LxMusicRuntime] HTTP 请求: $url');
        
        // 异步执行 HTTP 请求，完成后回调给 JavaScript
        _executeHttpRequest(requestId, url, options);
        
        // 立即返回，表示请求已开始
        return null;
      },
    );

    // 处理音乐 URL 响应
    controller.addJavaScriptHandler(
      handlerName: 'lxOnResponse',
      callback: (args) {
        if (args.isEmpty) return;
        
        final data = args[0] as Map<String, dynamic>;
        final requestKey = data['requestKey'] as String?;
        final success = data['success'] as bool? ?? false;
        final url = data['url'] as String?;
        final error = data['error'] as String?;
        
        print('📥 [LxMusicRuntime] 响应: requestKey=$requestKey, success=$success');
        
        if (requestKey != null && _pendingRequests.containsKey(requestKey)) {
          final completer = _pendingRequests[requestKey]!;
          if (success && url != null) {
            completer.complete(url);
          } else {
            completer.completeError(error ?? '未知错误');
          }
        }
        return null;
      },
    );

    // 处理错误
    controller.addJavaScriptHandler(
      handlerName: 'lxOnError',
      callback: (args) {
        final error = args.isNotEmpty ? args[0] : '未知错误';
        print('❌ [LxMusicRuntime] 脚本错误: $error');
        return null;
      },
    );

    // 处理歌词请求（占位处理器，防止脚本调用不存在的处理器导致阻塞）
    // 注意：我们不使用洛雪脚本的歌词功能，而是通过后端 API 获取歌词
    controller.addJavaScriptHandler(
      handlerName: 'LxLyricInfo',
      callback: (args) {
        print('ℹ️ [LxMusicRuntime] 歌词请求已忽略（使用后端 API 获取歌词）');
        return null;
      },
    );

    // 其他可能的歌词相关处理器
    controller.addJavaScriptHandler(
      handlerName: 'lxOnLyric',
      callback: (args) {
        print('ℹ️ [LxMusicRuntime] lxOnLyric 请求已忽略');
        return null;
      },
    );
  }

  /// 执行 HTTP 请求并回调给 JavaScript
  /// 
  /// 这个方法异步执行 HTTP 请求，完成后通过 JavaScript 回调函数
  /// `__lx_handleHttpResponse__` 将结果传回沙箱。
  void _executeHttpRequest(String requestId, String url, Map<String, dynamic> options) async {
    try {
      final result = await _performHttpRequest(url, options);
      
      // 将结果回调给 JavaScript
      final responseData = jsonEncode({
        'requestId': requestId,
        'success': true,
        'response': {
          'statusCode': result['statusCode'],
          'statusMessage': result['statusMessage'],
          'headers': result['headers'],
          'body': result['body'],
          'bytes': result['bytes'],
        },
        'body': result['body'],
      });
      
      await _webViewController?.evaluateJavascript(source: '''
        window.__lx_handleHttpResponse__($responseData);
      ''');
    } catch (e) {
      print('❌ [LxMusicRuntime] HTTP 请求失败: $e');
      
      // 将错误回调给 JavaScript
      final errorData = jsonEncode({
        'requestId': requestId,
        'success': false,
        'error': e.toString(),
      });
      
      await _webViewController?.evaluateJavascript(source: '''
        window.__lx_handleHttpResponse__($errorData);
      ''');
    }
  }

  /// 执行 HTTP 请求
  /// 
  /// 这是洛雪音源脚本获取音乐 URL 的核心机制。
  /// 脚本通过 lx.request() 发起请求，由 Dart 代理执行真正的 HTTP 请求。
  Future<Map<String, dynamic>> _performHttpRequest(
    String url,
    Map<String, dynamic> options,
  ) async {
    try {
      // ===== 详细调试日志：打印脚本传入的原始 options =====
      print('========== [HTTP Request Debug] ==========');
      print('🔍 [HTTP] 原始 URL: $url');
      print('🔍 [HTTP] 原始 options: $options');
      if (options['headers'] != null) {
        print('🔍 [HTTP] 原始 headers: ${options['headers']}');
        print('🔍 [HTTP] headers 类型: ${options['headers'].runtimeType}');
      } else {
        print('🔍 [HTTP] 原始 headers: (null - 脚本未传递请求头)');
      }
      print('==========================================');
      
      final method = (options['method'] as String?)?.toUpperCase() ?? 'GET';
      final headers = <String, String>{};
      
      // 解析请求头
      if (options['headers'] != null) {
        final headerMap = options['headers'];
        if (headerMap is Map) {
          headerMap.forEach((key, value) {
            headers[key.toString()] = value.toString();
          });
        }
      }
      
      // 添加默认 User-Agent
      if (!headers.containsKey('User-Agent')) {
        headers['User-Agent'] = 'lx-music-request';
      }
      
      // ===== 修正请求头以匹配解密脚本格式 =====
      // 1. 添加缺失的 accept 头（如果脚本没有传递）
      if (!headers.containsKey('accept') && !headers.containsKey('Accept')) {
        headers['accept'] = 'application/json';
      }
      
      // 2. 对于 GET 请求，移除不必要的 Content-Type（GET 请求不应该有 Content-Type）
      if (method == 'GET') {
        headers.remove('Content-Type');
        headers.remove('content-type');
      }
      
      // 3. 统一请求头的 key 为小写格式（与解密脚本一致）
      final normalizedHeaders = <String, String>{};
      headers.forEach((key, value) {
        // 将 User-Agent 转为 user-agent，X-Request-Key 转为 x-request-key
        normalizedHeaders[key.toLowerCase()] = value;
      });
      
      print('🌐 [HTTP] $method $url');
      print('   Headers (原始): $headers');
      print('   Headers (规范化): $normalizedHeaders');
      
      http.Response response;
      
      if (method == 'GET') {
        response = await http.get(
          Uri.parse(url),
          headers: normalizedHeaders,
        ).timeout(const Duration(seconds: 30));
      } else if (method == 'POST') {
        // 解析请求体
        dynamic body;
        String? contentType;
        
        if (options['body'] != null) {
          body = options['body'];
          if (body is Map) {
            body = jsonEncode(body);
            contentType = 'application/json';
          }
        } else if (options['form'] != null) {
          body = options['form'];
          if (body is Map) {
            body = body.entries
                .map((e) => '${Uri.encodeComponent(e.key.toString())}=${Uri.encodeComponent(e.value.toString())}')
                .join('&');
            contentType = 'application/x-www-form-urlencoded';
          }
        }
        
        if (contentType != null && !normalizedHeaders.containsKey('content-type')) {
          normalizedHeaders['content-type'] = contentType;
        }
        
        response = await http.post(
          Uri.parse(url),
          headers: normalizedHeaders,
          body: body,
        ).timeout(const Duration(seconds: 30));
      } else {
        throw Exception('Unsupported HTTP method: $method');
      }
      
      print('📥 [HTTP] Status: ${response.statusCode}');
      
      // 尝试解析 JSON 响应
      dynamic responseBody = response.body;
      try {
        responseBody = jsonDecode(response.body);
      } catch (_) {
        // 不是 JSON，保持原始字符串
      }
      
      return {
        'statusCode': response.statusCode,
        'statusMessage': response.reasonPhrase ?? '',
        'headers': response.headers,
        'body': responseBody,
        'raw': response.bodyBytes,
        'bytes': response.bodyBytes.length,
      };
    } catch (e) {
      print('❌ [HTTP] Error: $e');
      rethrow;
    }
  }

  /// 解析脚本信息
  LxScriptInfo _parseScriptInfo(String script) {
    String name = '未知音源';
    String version = '1.0.0';
    String author = '';
    String description = '';
    String homepage = '';

    // 匹配注释块
    final commentMatch = RegExp(r'^/\*[\s\S]+?\*/').firstMatch(script);
    if (commentMatch != null) {
      final comment = commentMatch.group(0)!;
      
      // 解析各个字段
      final nameMatch = RegExp(r'@name\s+(.+)').firstMatch(comment);
      if (nameMatch != null) name = nameMatch.group(1)!.trim();
      
      final versionMatch = RegExp(r'@version\s+(.+)').firstMatch(comment);
      if (versionMatch != null) version = versionMatch.group(1)!.trim();
      
      final authorMatch = RegExp(r'@author\s+(.+)').firstMatch(comment);
      if (authorMatch != null) author = authorMatch.group(1)!.trim();
      
      final descMatch = RegExp(r'@description\s+(.+)').firstMatch(comment);
      if (descMatch != null) description = descMatch.group(1)!.trim();
      
      final homeMatch = RegExp(r'@homepage\s+(.+)').firstMatch(comment);
      if (homeMatch != null) homepage = homeMatch.group(1)!.trim();
    }

    return LxScriptInfo(
      name: name,
      version: version,
      author: author,
      description: description,
      homepage: homepage,
      script: script,
    );
  }

  /// 生成沙箱 HTML
  String _generateSandboxHtml() {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="default-src 'unsafe-inline' 'unsafe-eval'">
  <title>LxMusic Sandbox</title>
</head>
<body>
<script>
(function() {
  'use strict';
  
  // ==================== 状态 ====================
  let isInited = false;
  let requestHandler = null;
  let currentScriptInfo = null;
  const pendingHttpRequests = new Map();
  let httpRequestCounter = 0;
  
  // ==================== 工具函数 ====================
  
  // 发送消息到 Flutter
  function sendToFlutter(handlerName, data) {
    if (window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler(handlerName, data);
    }
  }
  
  // ==================== lx API 实现 ====================
  
  const EVENT_NAMES = {
    request: 'request',
    inited: 'inited',
    updateAlert: 'updateAlert',
  };
  
  // HTTP 请求实现
  function request(url, options, callback) {
    const requestId = 'http_' + (++httpRequestCounter) + '_' + Date.now();
    
    // ===== 详细调试日志 =====
    console.log('========== [LxMusic Request Debug] ==========');
    console.log('[LxMusic] Request URL: ' + url);
    console.log('[LxMusic] Request Method: ' + ((options && options.method) || 'GET'));
    if (options && options.headers) {
      console.log('[LxMusic] Request Headers: ' + JSON.stringify(options.headers));
    } else {
      console.log('[LxMusic] Request Headers: (none)');
    }
    if (options && options.body) {
      console.log('[LxMusic] Request Body: ' + JSON.stringify(options.body));
    }
    // 尝试解析 URL 中的 sign 参数
    try {
      const urlObj = new URL(url);
      const sign = urlObj.searchParams.get('sign');
      if (sign) {
        console.log('[LxMusic] Sign Parameter: ' + sign);
        console.log('[LxMusic] Sign Length: ' + sign.length);
      }
    } catch (e) {
      console.log('[LxMusic] URL Parse Error: ' + e.message);
    }
    console.log('==============================================');
    
    pendingHttpRequests.set(requestId, callback);
    
    sendToFlutter('lxRequest', {
      requestId: requestId,
      url: url,
      options: options || {},
    });
    
    // 返回取消函数
    return function() {
      pendingHttpRequests.delete(requestId);
    };
  }
  
  // 发送事件
  function send(eventName, data) {
    return new Promise((resolve, reject) => {
      if (eventName === EVENT_NAMES.inited) {
        if (isInited) {
          reject(new Error('Already inited'));
          return;
        }
        isInited = true;
        sendToFlutter('lxOnInited', data);
        resolve();
      } else if (eventName === EVENT_NAMES.updateAlert) {
        // 更新提醒，暂时忽略
        resolve();
      } else {
        reject(new Error('Unknown event: ' + eventName));
      }
    });
  }
  
  // 注册事件处理器
  function on(eventName, handler) {
    if (eventName === EVENT_NAMES.request) {
      requestHandler = handler;
      return Promise.resolve();
    }
    return Promise.reject(new Error('Unknown event: ' + eventName));
  }
  
  // ==================== MD5 实现 ====================
  // 完整的 MD5 实现，用于音源脚本签名验证
  const md5 = (function() {
    function md5cycle(x, k) {
      let a = x[0], b = x[1], c = x[2], d = x[3];
      a = ff(a, b, c, d, k[0], 7, -680876936);
      d = ff(d, a, b, c, k[1], 12, -389564586);
      c = ff(c, d, a, b, k[2], 17, 606105819);
      b = ff(b, c, d, a, k[3], 22, -1044525330);
      a = ff(a, b, c, d, k[4], 7, -176418897);
      d = ff(d, a, b, c, k[5], 12, 1200080426);
      c = ff(c, d, a, b, k[6], 17, -1473231341);
      b = ff(b, c, d, a, k[7], 22, -45705983);
      a = ff(a, b, c, d, k[8], 7, 1770035416);
      d = ff(d, a, b, c, k[9], 12, -1958414417);
      c = ff(c, d, a, b, k[10], 17, -42063);
      b = ff(b, c, d, a, k[11], 22, -1990404162);
      a = ff(a, b, c, d, k[12], 7, 1804603682);
      d = ff(d, a, b, c, k[13], 12, -40341101);
      c = ff(c, d, a, b, k[14], 17, -1502002290);
      b = ff(b, c, d, a, k[15], 22, 1236535329);
      a = gg(a, b, c, d, k[1], 5, -165796510);
      d = gg(d, a, b, c, k[6], 9, -1069501632);
      c = gg(c, d, a, b, k[11], 14, 643717713);
      b = gg(b, c, d, a, k[0], 20, -373897302);
      a = gg(a, b, c, d, k[5], 5, -701558691);
      d = gg(d, a, b, c, k[10], 9, 38016083);
      c = gg(c, d, a, b, k[15], 14, -660478335);
      b = gg(b, c, d, a, k[4], 20, -405537848);
      a = gg(a, b, c, d, k[9], 5, 568446438);
      d = gg(d, a, b, c, k[14], 9, -1019803690);
      c = gg(c, d, a, b, k[3], 14, -187363961);
      b = gg(b, c, d, a, k[8], 20, 1163531501);
      a = gg(a, b, c, d, k[13], 5, -1444681467);
      d = gg(d, a, b, c, k[2], 9, -51403784);
      c = gg(c, d, a, b, k[7], 14, 1735328473);
      b = gg(b, c, d, a, k[12], 20, -1926607734);
      a = hh(a, b, c, d, k[5], 4, -378558);
      d = hh(d, a, b, c, k[8], 11, -2022574463);
      c = hh(c, d, a, b, k[11], 16, 1839030562);
      b = hh(b, c, d, a, k[14], 23, -35309556);
      a = hh(a, b, c, d, k[1], 4, -1530992060);
      d = hh(d, a, b, c, k[4], 11, 1272893353);
      c = hh(c, d, a, b, k[7], 16, -155497632);
      b = hh(b, c, d, a, k[10], 23, -1094730640);
      a = hh(a, b, c, d, k[13], 4, 681279174);
      d = hh(d, a, b, c, k[0], 11, -358537222);
      c = hh(c, d, a, b, k[3], 16, -722521979);
      b = hh(b, c, d, a, k[6], 23, 76029189);
      a = hh(a, b, c, d, k[9], 4, -640364487);
      d = hh(d, a, b, c, k[12], 11, -421815835);
      c = hh(c, d, a, b, k[15], 16, 530742520);
      b = hh(b, c, d, a, k[2], 23, -995338651);
      a = ii(a, b, c, d, k[0], 6, -198630844);
      d = ii(d, a, b, c, k[7], 10, 1126891415);
      c = ii(c, d, a, b, k[14], 15, -1416354905);
      b = ii(b, c, d, a, k[5], 21, -57434055);
      a = ii(a, b, c, d, k[12], 6, 1700485571);
      d = ii(d, a, b, c, k[3], 10, -1894986606);
      c = ii(c, d, a, b, k[10], 15, -1051523);
      b = ii(b, c, d, a, k[1], 21, -2054922799);
      a = ii(a, b, c, d, k[8], 6, 1873313359);
      d = ii(d, a, b, c, k[15], 10, -30611744);
      c = ii(c, d, a, b, k[6], 15, -1560198380);
      b = ii(b, c, d, a, k[13], 21, 1309151649);
      a = ii(a, b, c, d, k[4], 6, -145523070);
      d = ii(d, a, b, c, k[11], 10, -1120210379);
      c = ii(c, d, a, b, k[2], 15, 718787259);
      b = ii(b, c, d, a, k[9], 21, -343485551);
      x[0] = add32(a, x[0]);
      x[1] = add32(b, x[1]);
      x[2] = add32(c, x[2]);
      x[3] = add32(d, x[3]);
    }
    function cmn(q, a, b, x, s, t) {
      a = add32(add32(a, q), add32(x, t));
      return add32((a << s) | (a >>> (32 - s)), b);
    }
    function ff(a, b, c, d, x, s, t) {
      return cmn((b & c) | ((~b) & d), a, b, x, s, t);
    }
    function gg(a, b, c, d, x, s, t) {
      return cmn((b & d) | (c & (~d)), a, b, x, s, t);
    }
    function hh(a, b, c, d, x, s, t) {
      return cmn(b ^ c ^ d, a, b, x, s, t);
    }
    function ii(a, b, c, d, x, s, t) {
      return cmn(c ^ (b | (~d)), a, b, x, s, t);
    }
    function md51(s) {
      const n = s.length;
      let state = [1732584193, -271733879, -1732584194, 271733878], i;
      for (i = 64; i <= s.length; i += 64) {
        md5cycle(state, md5blk(s.substring(i - 64, i)));
      }
      s = s.substring(i - 64);
      const tail = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
      for (i = 0; i < s.length; i++)
        tail[i >> 2] |= s.charCodeAt(i) << ((i % 4) << 3);
      tail[i >> 2] |= 0x80 << ((i % 4) << 3);
      if (i > 55) {
        md5cycle(state, tail);
        for (i = 0; i < 16; i++) tail[i] = 0;
      }
      tail[14] = n * 8;
      md5cycle(state, tail);
      return state;
    }
    function md5blk(s) {
      const md5blks = [];
      for (let i = 0; i < 64; i += 4) {
        md5blks[i >> 2] = s.charCodeAt(i) + (s.charCodeAt(i + 1) << 8) + (s.charCodeAt(i + 2) << 16) + (s.charCodeAt(i + 3) << 24);
      }
      return md5blks;
    }
    const hex_chr = '0123456789abcdef'.split('');
    function rhex(n) {
      let s = '', j = 0;
      for (; j < 4; j++)
        s += hex_chr[(n >> (j * 8 + 4)) & 0x0F] + hex_chr[(n >> (j * 8)) & 0x0F];
      return s;
    }
    function hex(x) {
      for (let i = 0; i < x.length; i++) x[i] = rhex(x[i]);
      return x.join('');
    }
    function add32(a, b) {
      return (a + b) & 0xFFFFFFFF;
    }
    return function(s) {
      return hex(md51(s));
    };
  })();
  
  // 工具函数
  const utils = {
    crypto: {
      aesEncrypt: function(buffer, mode, key, iv) {
        console.warn('[LxMusic] crypto.aesEncrypt not implemented');
        return buffer;
      },
      rsaEncrypt: function(buffer, key) {
        console.warn('[LxMusic] crypto.rsaEncrypt not implemented');
        return buffer;
      },
      randomBytes: function(size) {
        const bytes = new Uint8Array(size);
        crypto.getRandomValues(bytes);
        return bytes;
      },
      md5: function(str) {
        // 使用完整的 MD5 实现
        if (typeof str !== 'string') {
          str = new TextDecoder().decode(str);
        }
        return md5(str);
      },
    },
    buffer: {
      from: function(data, encoding) {
        if (typeof data === 'string') {
          if (encoding === 'base64') {
            return Uint8Array.from(atob(data), c => c.charCodeAt(0));
          }
          return new TextEncoder().encode(data);
        }
        return new Uint8Array(data);
      },
      bufToString: function(buf, format) {
        if (format === 'hex') {
          return Array.from(new Uint8Array(buf))
            .map(b => b.toString(16).padStart(2, '0'))
            .join('');
        }
        if (format === 'base64') {
          return btoa(String.fromCharCode(...new Uint8Array(buf)));
        }
        return new TextDecoder().decode(buf);
      },
    },
    zlib: {
      inflate: function(buf) {
        console.warn('[LxMusic] zlib.inflate not implemented');
        return Promise.resolve(buf);
      },
      deflate: function(data) {
        console.warn('[LxMusic] zlib.deflate not implemented');
        return Promise.resolve(data);
      },
    },
  };
  
  // ==================== 暴露全局 lx 对象 ====================
  
  window.lx = {
    EVENT_NAMES: EVENT_NAMES,
    request: request,
    send: send,
    on: on,
    utils: utils,
    version: '2.0.0',
    env: 'desktop',  // 使用 desktop 环境标识以匹配洛雪桌面端
    currentScriptInfo: {
      name: '',
      version: '',
      author: '',
      description: '',
      homepage: '',
      rawScript: '',
    },
  };
  
  // ==================== Flutter 调用的接口 ====================
  
  // 重置状态
  window.__lx_reset__ = function() {
    isInited = false;
    requestHandler = null;
    pendingHttpRequests.clear();
    console.log('[LxMusic] Sandbox reset');
  };
  
  // 设置脚本信息
  window.__lx_setScriptInfo__ = function(info) {
    currentScriptInfo = info;
    // 解码 Base64 编码的脚本内容
    let rawScript = '';
    if (info.scriptBase64) {
      try {
        rawScript = atob(info.scriptBase64);
        console.log('[LxMusic] rawScript 已设置，长度: ' + rawScript.length);
      } catch (e) {
        console.warn('[LxMusic] Base64 解码失败: ' + e.message);
      }
    }
    window.lx.currentScriptInfo = {
      name: info.name || '',
      version: info.version || '',
      author: info.author || '',
      description: info.description || '',
      homepage: info.homepage || '',
      rawScript: rawScript,
    };
    console.log('[LxMusic] Script info set:', info.name);
  };
  
  // 发送请求到脚本
  window.__lx_sendRequest__ = function(data) {
    if (!requestHandler) {
      sendToFlutter('lxOnResponse', {
        requestKey: data.requestKey,
        success: false,
        error: 'Request handler not registered',
      });
      return;
    }
    
    try {
      const context = {};
      const result = requestHandler.call(context, {
        source: data.source,
        action: data.action,
        info: data.info,
      });
      
      if (result && typeof result.then === 'function') {
        result.then(function(url) {
          sendToFlutter('lxOnResponse', {
            requestKey: data.requestKey,
            success: true,
            url: url,
          });
        }).catch(function(err) {
          sendToFlutter('lxOnResponse', {
            requestKey: data.requestKey,
            success: false,
            error: err.message || String(err),
          });
        });
      } else {
        sendToFlutter('lxOnResponse', {
          requestKey: data.requestKey,
          success: true,
          url: result,
        });
      }
    } catch (err) {
      sendToFlutter('lxOnResponse', {
        requestKey: data.requestKey,
        success: false,
        error: err.message || String(err),
      });
    }
  };
  
  // 处理 HTTP 响应
  window.__lx_handleHttpResponse__ = function(data) {
    const callback = pendingHttpRequests.get(data.requestId);
    if (callback) {
      pendingHttpRequests.delete(data.requestId);
      if (data.success) {
        callback(null, data.response, data.body);
      } else {
        callback(new Error(data.error), null, null);
      }
    }
  };
  
  // 处理错误
  window.__lx_onError__ = function(message) {
    console.error('[LxMusic] Script error:', message);
    sendToFlutter('lxOnError', message);
  };
  
  // 全局错误捕获
  window.addEventListener('error', function(event) {
    window.__lx_onError__(event.message);
  });
  
  window.addEventListener('unhandledrejection', function(event) {
    const message = event.reason?.message || String(event.reason);
    window.__lx_onError__(message);
  });
  
  console.log('[LxMusic] Sandbox initialized');
  
  // ==================== 调试函数 ====================
  // 检查脚本加载后的关键全局变量
  window.__lx_debugGlobals__ = function() {
    console.log('========== [LxMusic Global Variables Debug] ==========');
    
    // 检查可能的签名相关变量
    const varNames = ['API_URL', 'API_KEY', 'SECRET_KEY', 'SCRIPT_MD5', 'version', 
                      'DEV_ENABLE', 'UPDATE_ENABLE', 'MUSIC_SOURCE'];
    
    varNames.forEach(function(name) {
      if (typeof window[name] !== 'undefined') {
        const val = window[name];
        const display = typeof val === 'object' ? JSON.stringify(val) : String(val);
        console.log('[LxMusic] window.' + name + ' = ' + display.substring(0, 200));
      }
    });
    
    // 检查 globalThis
    varNames.forEach(function(name) {
      if (typeof globalThis !== 'undefined' && typeof globalThis[name] !== 'undefined' && globalThis[name] !== window[name]) {
        const val = globalThis[name];
        const display = typeof val === 'object' ? JSON.stringify(val) : String(val);
        console.log('[LxMusic] globalThis.' + name + ' = ' + display.substring(0, 200));
      }
    });
    
    // 检查 MUSIC_SOURCE 导出模块
    if (window.MUSIC_SOURCE) {
      console.log('[LxMusic] MUSIC_SOURCE module found:');
      const ms = window.MUSIC_SOURCE;
      if (ms.API_URL) console.log('[LxMusic]   API_URL = ' + ms.API_URL);
      if (ms.API_KEY) console.log('[LxMusic]   API_KEY = ' + ms.API_KEY);
      if (ms.SECRET_KEY) console.log('[LxMusic]   SECRET_KEY = ' + (ms.SECRET_KEY ? ms.SECRET_KEY.substring(0, 10) + '...' : 'undefined'));
      if (ms.SCRIPT_MD5) console.log('[LxMusic]   SCRIPT_MD5 = ' + ms.SCRIPT_MD5);
      if (ms.generateSign) console.log('[LxMusic]   generateSign = function');
      if (ms.sha256) console.log('[LxMusic]   sha256 = function');
    }
    
    console.log('========================================================');
  };
  
  // 在脚本执行 500ms 后自动检查全局变量
  setTimeout(function() {
    if (isInited) {
      window.__lx_debugGlobals__();
    }
  }, 500);
})();
</script>
</body>
</html>
''';
  }
}

/// 洛雪脚本信息
class LxScriptInfo {
  final String name;
  final String version;
  final String author;
  final String description;
  final String homepage;
  final String script;
  
  /// 洛雪格式的支持音源列表 (wy, tx, kg, kw, mg)
  final List<String> supportedSources;

  LxScriptInfo({
    required this.name,
    required this.version,
    this.author = '',
    this.description = '',
    this.homepage = '',
    required this.script,
    this.supportedSources = const [],
  });
  
  /// 将洛雪格式的音源代码转换为应用内部平台代码
  static String? _lxToInternalPlatform(String lxSource) {
    switch (lxSource) {
      case 'wy':
        return 'netease';
      case 'tx':
        return 'qq';
      case 'kg':
        return 'kugou';
      case 'kw':
        return 'kuwo';
      case 'mg':
        return null; // 咪咕暂不支持搜索
      default:
        return null;
    }
  }
  
  /// 获取应用内部格式的支持平台列表
  List<String> get supportedPlatforms {
    return supportedSources
        .map((s) => _lxToInternalPlatform(s))
        .where((p) => p != null)
        .cast<String>()
        .toList();
  }

  @override
  String toString() => 'LxScriptInfo(name: $name, version: $version, sources: $supportedSources)';
}
