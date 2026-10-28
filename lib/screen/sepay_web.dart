import 'dart:html' as html;

void openSePayWeb(
  String checkoutUrl,
  Map<String, dynamic> fields,
) {
  final uri = Uri.parse(checkoutUrl);

  if (uri.scheme != 'https' ||
      uri.host != 'pay-sandbox.sepay.vn' ||
      uri.path != '/v1/checkout/init') {
    throw Exception('URL SePay Sandbox không hợp lệ');
  }

  final form = html.FormElement()
    ..method = 'POST'
    ..action = checkoutUrl
    ..target = '_blank'
    ..style.display = 'none';

  for (final entry in fields.entries) {
    final input = html.InputElement(type: 'hidden')
      ..name = entry.key
      ..value = entry.value.toString();

    form.children.add(input);
  }

  html.document.body!.children.add(form);

  try {
    form.submit();
  } finally {
    form.remove();
  }
}
