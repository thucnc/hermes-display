abstract final class AppStrings {
  static const String appTitle = 'Hermes Display';
  static const String assistantName = 'Hermes';

  static const String statusConnected = 'Đã kết nối';
  static const String statusConnecting = 'Đang kết nối…';
  static const String statusDisconnected = 'Mất kết nối';

  static const String micArmed = 'Đang chờ "Hey Sen"';
  static const String micManual = 'Chỉ dùng nút micro';
  static const String micOff = 'Micro không khả dụng';

  static const String listening = 'Đang nghe…';
  static const String thinking = 'Đang suy nghĩ…';

  static const String inputHint = 'Nhập câu hỏi cho Hermes…';
  static const String sendOffline = 'Chưa kết nối tới Hermes Hub';
  static const String micDenied = 'Cần cấp quyền micro trong Cài đặt hệ thống';
  static const String micUnavailable = 'Không mở được micro';

  static const String settingsTitle = 'Cài đặt';
  static const String hubHost = 'Địa chỉ Hub (IP / hostname)';
  static const String hubPort = 'Cổng';
  static const String slideInterval = 'Chuyển ảnh mỗi';
  static const String wakeSensitivity = 'Độ nhạy từ khoá "Hey Sen"';
  static const String wakeKeyword = 'Từ khoá đánh thức';
  static const String invalidKeyword = 'Nhập từ khoá';
  static const String keywordUnsupported =
      'Model không nhận được từ khoá này (chỉ chữ tiếng Anh A–Z)';
  static const String alwaysListening = 'Luôn lắng nghe';
  static const String alwaysListeningHint =
      'Giữ micro khi tắt màn hình (hiện thông báo thường trực)';
  static const String nightDim = 'Giảm sáng ban đêm';
  static const String nightDimHint =
      'Chỉ màn hình app; "Hey Sen" hoặc chạm để sáng lại';
  static const String dimStart = 'Từ';
  static const String dimEnd = 'Đến';
  static const String dimLevel = 'Độ sáng ban đêm';
  static const String modelTitle = 'Model từ khoá';
  static const String modelIdle = 'Chưa cài';
  static const String modelDownloading = 'Đang tải';
  static const String modelVerifying = 'Đang kiểm tra…';
  static const String modelReady = 'Đã cài';
  static const String modelFailed = 'Tải thất bại — micro vẫn dùng được';
  static const String retry = 'Thử lại';
  static const String secondsSuffix = 'giây';
  static const String testConnection = 'Kiểm tra kết nối';
  static const String testing = 'Đang kiểm tra…';
  static const String testOk = 'Kết nối thành công';
  static const String testFail = 'Không kết nối được';
  static const String save = 'Lưu';
  static const String cancel = 'Huỷ';
  static const String invalidHost = 'Nhập địa chỉ hợp lệ';
  static const String invalidPort = 'Cổng từ 1 đến 65535';
  static const String brainTitle = 'Bộ não trả lời';
  static const String brainHub = 'Hub (Hermes Agent)';
  static const String brainGemini = 'Gemini 3.8 Flash';
  static const String brainNoKey = 'Chưa có API key — đang dùng Hub';
  static const String brainVoiceHint =
      'Câu hỏi bằng giọng nói vẫn đi qua Hub (nhận diện giọng nói ở Hub)';
  static const String geminiKey = 'Gemini API key';
  static const String showKey = 'Hiện key';
  static const String hideKey = 'Ẩn key';

  static const String playVideo = 'Phát Video';
  static const String videoFallbackTitle = 'Video YouTube';
  static const String stepsTitle = 'Các bước';
  static const String saveToHermes = '💾 Lưu vào Hermes';
  static const String saving = 'Đang lưu…';
  static const String savedToBrain = 'Đã lưu vào Second Brain';
  static const String saveFailed = 'Không lưu được — kiểm tra kết nối Hub';
  static const String videoFailed = 'Không mở được video';

  static const String tipSettings = 'Cài đặt';
  static const String tipKeyboard = 'Nhập văn bản';
  static const String tipMic = 'Bắt đầu nghe';
  static const String tipSend = 'Gửi';
  static const String tipClose = 'Đóng';

  static const List<String> weekdays = [
    'Thứ Hai',
    'Thứ Ba',
    'Thứ Tư',
    'Thứ Năm',
    'Thứ Sáu',
    'Thứ Bảy',
    'Chủ Nhật',
  ];
  static const String month = 'tháng';
}
