import 'dart:js_interop';
import 'layout_print_window.dart';

@JS('window.open')
external _Window? _open(JSString url, JSString name);
extension type _Window(JSObject _) implements JSObject {
  external _Document get document;
  external void print();
  external void focus();
  external void close();
}
extension type _Document(JSObject _) implements JSObject {
  external void open();
  external void write(JSString html);
  external void close();
}

class _PrintWindow implements LayoutPrintWindow {
  _PrintWindow(this.window);
  final _Window window;
  @override
  void show(String html) {
    window.document.open();
    window.document.write(html.toJS);
    window.document.close();
    window.focus();
    window.print();
  }

  @override
  void close() => window.close();
}

LayoutPrintWindow? openWindow() {
  final window = _open('about:blank'.toJS, '_blank'.toJS);
  return window == null ? null : _PrintWindow(window);
}
