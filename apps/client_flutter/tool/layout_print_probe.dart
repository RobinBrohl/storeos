// Headless browser acceptance invokes the real conditional Web print adapter.
import 'dart:js_interop';
import 'package:storeos_client/src/data/layout_print_window.dart';

@JS('p44Html')
external JSString get _html;
void main() {
  openLayoutPrintWindow()!.show(_html.toDart);
}
