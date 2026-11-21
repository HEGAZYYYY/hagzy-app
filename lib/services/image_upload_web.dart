// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;

Future<String?> pickImageFileAsDataUrl() async {
  final completer = Completer<String?>();
  final input = html.FileUploadInputElement()
    ..accept = 'image/png,image/jpeg,image/webp,image/jpg'
    ..multiple = false;

  input.onChange.listen((event) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    final file = files[0];
    final reader = html.FileReader();

    reader.onLoadEnd.listen((_) {
      final dataUrl = reader.result;
      if (dataUrl is! String) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }

      // If already small (< 300KB), return directly
      if (file.size < 300 * 1024) {
        if (!completer.isCompleted) completer.complete(dataUrl);
        return;
      }

      // Optimize/compress image using canvas
      try {
        final img = html.ImageElement();
        img.crossOrigin = 'anonymous';
        img.onLoad.listen((_) {
          try {
            int width = img.naturalWidth;
            int height = img.naturalHeight;
            const int maxDim = 1200;
            if (width > maxDim || height > maxDim) {
              if (width > height) {
                height = (height * maxDim / width).round();
                width = maxDim;
              } else {
                width = (width * maxDim / height).round();
                height = maxDim;
              }
            }
            final canvas = html.CanvasElement(width: width, height: height);
            final ctx = canvas.context2D;
            ctx.drawImageScaled(img, 0, 0, width, height);
            final compressed = canvas.toDataUrl('image/jpeg', 0.82);
            if (!completer.isCompleted) completer.complete(compressed);
          } catch (_) {
            if (!completer.isCompleted) completer.complete(dataUrl);
          }
        });
        img.onError.listen((_) {
          if (!completer.isCompleted) completer.complete(dataUrl);
        });
        img.src = dataUrl;
      } catch (_) {
        if (!completer.isCompleted) completer.complete(dataUrl);
      }
    });

    reader.onError.listen((_) {
      if (!completer.isCompleted) completer.complete(null);
    });

    reader.readAsDataUrl(file);
  });

  input.click();
  return completer.future;
}
