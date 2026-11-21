import 'image_upload_stub.dart'
    if (dart.library.html) 'image_upload_web.dart';

class ImageUploadService {
  static Future<String?> pickImage() => pickImageFileAsDataUrl();
}
