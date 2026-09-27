{{flutter_js}}
{{flutter_build_config}}

// Keep renderer and fallback-font requests on the hosting Standortserver.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).toString(),
    fontFallbackBaseUrl: new URL('assets/fonts/', document.baseURI).toString(),
  },
});
