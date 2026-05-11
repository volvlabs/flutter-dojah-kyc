import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';

class DojahKYC {
  final String appId;
  final String publicKey;
  final String type;
  final int? amount;
  final String? referenceId;
  final Map<String, dynamic>? userData;
  final Map<String, dynamic>? metaData;
  final Map<String, dynamic>? govData;
  final Map<String, dynamic>? govId;
  final Map<String, dynamic>? config;
  final Function(dynamic)? onCloseCallback;

  DojahKYC({
    required this.appId,
    required this.publicKey,
    required this.type,
    this.userData,
    this.config,
    this.metaData,
    this.govData,
    this.govId,
    this.amount,
    this.referenceId,
    this.onCloseCallback,
  });

  Future<void> open(BuildContext context,
      {Function(dynamic result)? onSuccess,
      Function(dynamic close)? onClose,
      Function(dynamic error)? onError}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WebviewScreen(
          appId: appId,
          publicKey: publicKey,
          type: type,
          userData: userData,
          metaData: metaData,
          govData: govData,
          govId: govId,
          config: config,
          amount: amount,
          referenceId: referenceId,
          success: (result) {
            onSuccess!(result);
          },
          close: (close) {
            onClose!(close);
          },
          error: (error) {
            onError!(error);
          },
        ),
      ),
    );
  }
}

class WebviewScreen extends StatefulWidget {
  final String appId;
  final String publicKey;
  final String type;
  final int? amount;
  final String? referenceId;
  final Map<String, dynamic>? userData;
  final Map<String, dynamic>? metaData;
  final Map<String, dynamic>? govData;
  final Map<String, dynamic>? govId;
  final Map<String, dynamic>? config;
  final Function(dynamic) success;
  final Function(dynamic) error;
  final Function(dynamic) close;
  const WebviewScreen({
    Key? key,
    required this.appId,
    required this.publicKey,
    required this.type,
    this.userData,
    this.metaData,
    this.govData,
    this.govId,
    this.config,
    this.amount,
    this.referenceId,
    required this.success,
    required this.error,
    required this.close,
  }) : super(key: key);

  @override
  State<WebviewScreen> createState() => _WebviewScreenState();
}

class _WebviewScreenState extends State<WebviewScreen>
    with WidgetsBindingObserver {
  final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers = {
    Factory(() => EagerGestureRecognizer())
  };
  final GlobalKey webViewKey = GlobalKey();
  late InAppWebViewController _webViewController;
  double progress = 0;
  String url = '';
  late PullToRefreshController pullToRefreshController;

  InAppWebViewSettings options = InAppWebViewSettings(
    allowsInlineMediaPlayback: true,
    mediaPlaybackRequiresUserGesture: false,
    cacheEnabled: false,
    clearCache: true,
  );

  /// Permission state: 'loading', 'granted', 'denied', 'permanentlyDenied'
  String _permissionState = 'loading';

  /// Human-readable names of denied permissions (e.g. ['Camera', 'Microphone'])
  List<String> _deniedPermissionNames = [];

  bool isLocationGranted = false;
  bool isLocationPermissionGranted = false;
  dynamic locationData;
  dynamic timeZone;
  dynamic zoneOffset;
  dynamic locationObject;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestPermissions();
    pullToRefreshController = PullToRefreshController(
      onRefresh: () async {
        if (Platform.isAndroid) {
          _webViewController.reload();
        } else if (Platform.isIOS) {
          _webViewController.loadUrl(
            urlRequest: URLRequest(url: await _webViewController.getUrl()),
          );
        }
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _permissionState == 'permanentlyDenied') {
      _recheckPermissions();
    }
  }

  Future<void> _requestPermissions() async {
    final Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
      Permission.locationWhenInUse,
    ].request();

    _evaluatePermissions(statuses);
  }

  Future<void> _recheckPermissions() async {
    final cameraStatus = await Permission.camera.status;
    final microphoneStatus = await Permission.microphone.status;
    final locationStatus = await Permission.locationWhenInUse.status;

    _evaluatePermissions({
      Permission.camera: cameraStatus,
      Permission.microphone: microphoneStatus,
      Permission.locationWhenInUse: locationStatus,
    });
  }

  void _evaluatePermissions(Map<Permission, PermissionStatus> statuses) {
    final cameraStatus = statuses[Permission.camera]!;
    final microphoneStatus = statuses[Permission.microphone]!;
    final locationStatus = statuses[Permission.locationWhenInUse]!;

    final List<String> permanentlyDenied = [];
    if (cameraStatus.isPermanentlyDenied) permanentlyDenied.add('Camera');
    if (microphoneStatus.isPermanentlyDenied) {
      permanentlyDenied.add('Microphone');
    }
    if (locationStatus.isPermanentlyDenied) permanentlyDenied.add('Location');

    final List<String> denied = [];
    if (cameraStatus.isDenied) denied.add('Camera');
    if (microphoneStatus.isDenied) denied.add('Microphone');
    if (locationStatus.isDenied) denied.add('Location');

    if (!mounted) return;

    if (cameraStatus.isGranted) {
      // Camera granted — webview can load.
      setState(() {
        _permissionState = 'granted';
        isLocationPermissionGranted = locationStatus.isGranted;
      });
    } else if (permanentlyDenied.isNotEmpty) {
      setState(() {
        _permissionState = 'permanentlyDenied';
        _deniedPermissionNames = permanentlyDenied;
      });
      // Show dialog after the frame so context is ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showPermissionDialog(isPermanent: true);
      });
    } else if (denied.isNotEmpty) {
      setState(() {
        _permissionState = 'denied';
        _deniedPermissionNames = denied;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showPermissionDialog(isPermanent: false);
      });
    }
  }

  Future<void> _showPermissionDialog({required bool isPermanent}) async {
    final permissionNames = _deniedPermissionNames.join(', ');

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(
            isPermanent ? 'Permissions Required' : 'Permissions Needed',
          ),
          content: Text(
            isPermanent
                ? 'Dojah KYC requires the following permissions for identity verification: $permissionNames.\n\n'
                    'These permissions have been previously denied. '
                    'Please enable them in your device settings to continue.'
                : 'Dojah KYC needs the following permissions to work properly: $permissionNames.\n\n'
                    'These are required for ID capture, selfie verification, and location services.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                if (isPermanent) {
                  await openAppSettings();
                  // Re-check happens in didChangeAppLifecycleState
                } else {
                  await _requestPermissions();
                }
              },
              child: Text(
                isPermanent ? 'Open Settings' : 'Grant Permissions',
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_permissionState) {
      case 'granted':
        return _buildWebView();
      case 'denied':
      case 'permanentlyDenied':
      case 'loading':
      default:
        return const Center(child: CircularProgressIndicator());
    }
  }

  Widget _buildWebView() {
    // Load the real Dojah domain first to establish a proper origin,
    // then inject the widget initialization script after load.
    // This fixes both getUserMedia() on iOS and ensures the SDK initializes.
    return InAppWebView(
      key: webViewKey,
      gestureRecognizers: gestureRecognizers,
      initialSettings: options,
      initialUrlRequest: URLRequest(
        url: WebUri("https://widget.dojah.io/"),
      ),
      pullToRefreshController: pullToRefreshController,
      onWebViewCreated: (controller) {
        _webViewController = controller;

        _webViewController.addJavaScriptHandler(
          handlerName: 'onSuccessCallback',
          callback: (response) => widget.success(response),
        );

        _webViewController.addJavaScriptHandler(
          handlerName: 'onCloseCallback',
          callback: (response) => widget.close(response),
        );

        _webViewController.addJavaScriptHandler(
          handlerName: 'onErrorCallback',
          callback: (error) => widget.error(error),
        );
      },
      onLoadStop: (controller, url) async {
        pullToRefreshController.endRefreshing();

        // Inject the Dojah widget script and initialize it.
        // JSON-encoded values are valid JS literals for objects/strings.
        final configJson = jsonEncode(widget.config ?? {});
        final userDataJson = jsonEncode(widget.userData ?? {});
        final govDataJson = jsonEncode(widget.govData ?? {});
        final govIdJson = jsonEncode(widget.govId ?? {});
        final locationJson = jsonEncode(locationObject ?? {});
        final metaDataJson = jsonEncode(widget.metaData ?? {});

        await controller.evaluateJavascript(source: '''
          (function() {
            if (window.__dojahInjected) return;
            window.__dojahInjected = true;

            document.body.innerHTML = '';
            document.head.innerHTML = '<meta charset="UTF-8">' +
              '<meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1, maximum-scale=1, minimum-scale=1, shrink-to-fit=1"/>' +
              '<title>Dojah Inc.</title>';

            var script = document.createElement('script');
            script.src = 'https://widget.dojah.io/widget.js';
            script.onload = function() {
              var options = {
                app_id: ${jsonEncode(widget.appId)},
                p_key: ${jsonEncode(widget.publicKey)},
                type: ${jsonEncode(widget.type)},
                reference_id: ${jsonEncode(widget.referenceId ?? '')},
                config: $configJson,
                user_data: $userDataJson,
                gov_data: $govDataJson,
                gov_id: $govIdJson,
                location: $locationJson,
                metadata: $metaDataJson,
                onSuccess: function(response) {
                  window.flutter_inappwebview.callHandler('onSuccessCallback', response);
                },
                onError: function(error) {
                  window.flutter_inappwebview.callHandler('onErrorCallback', error);
                },
                onClose: function() {
                  window.flutter_inappwebview.callHandler('onCloseCallback', 'close');
                }
              };
              var connect = new Connect(options);
              connect.setup();
              connect.open();
            };
            script.onerror = function() {
              window.flutter_inappwebview.callHandler('onErrorCallback', 'Failed to load Dojah widget.js');
            };
            document.head.appendChild(script);
          })();
        ''');
      },
      onPermissionRequest: (controller, request) async {
        return PermissionResponse(
          resources: request.resources,
          action: PermissionResponseAction.GRANT,
        );
      },
      onReceivedError: (controller, request, error) {
        pullToRefreshController.endRefreshing();
      },
      onProgressChanged: (controller, progress) {
        if (progress == 100) pullToRefreshController.endRefreshing();
        setState(() => this.progress = progress / 100);
      },
      onGeolocationPermissionsShowPrompt: (controller, origin) async {
        return GeolocationPermissionShowPromptResponse(
          allow: true,
          origin: origin,
          retain: true,
        );
      },
      onConsoleMessage: (controller, consoleMessage) {
        if (kDebugMode) {
          print('DojahWebView: ${consoleMessage.message}');
        }
      },
    );
  }
}
