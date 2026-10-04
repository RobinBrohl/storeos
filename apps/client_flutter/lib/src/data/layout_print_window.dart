import 'layout_print_stub.dart'
    if (dart.library.js_interop) 'layout_print_web.dart'
    as platform;

abstract class LayoutPrintWindow {
  void show(String html);
  void close();
}

LayoutPrintWindow? openLayoutPrintWindow() => platform.openWindow();
