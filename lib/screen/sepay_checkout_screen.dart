import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class SePayCheckoutScreen extends StatefulWidget {
  final String checkoutUrl;
  final Map<String, dynamic> fields;

  const SePayCheckoutScreen({
    super.key,
    required this.checkoutUrl,
    required this.fields,
  });

  @override
  State<SePayCheckoutScreen> createState() =>
      _SePayCheckoutScreenState();
}

class _SePayCheckoutScreenState extends State<SePayCheckoutScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() {
                _loading = false;
                _error = error.description;
              });
            }
          },
        ),
      );

    _openCheckout();
  }

  Future<void> _openCheckout() async {
    try {
      final uri = Uri.parse(widget.checkoutUrl);

      if (uri.scheme != 'https' ||
          uri.host != 'pay-sandbox.sepay.vn' ||
          uri.path != '/v1/checkout/init') {
        throw Exception('Địa chỉ SePay Sandbox không hợp lệ.');
      }

      final inputs = widget.fields.entries.map((entry) {
        final key = htmlEscape.convert(entry.key);
        final value = htmlEscape.convert(entry.value.toString());
        return '<input type="hidden" name="$key" value="$value">';
      }).join();

      final html = '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
</head>
<body>
  <p>Đang chuyển đến SePay...</p>
  <form id="checkout" method="POST"
        action="${htmlEscape.convert(widget.checkoutUrl)}">
    $inputs
  </form>
  <script>
    document.getElementById('checkout').submit();
  </script>
</body>
</html>
''';

      await _controller.loadHtmlString(html);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thanh toán SePay'),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
