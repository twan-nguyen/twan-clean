# Twan Clean

Ứng dụng dọn dẹp cho macOS: quét rác, soi dung lượng ổ đĩa bằng bản đồ bong bóng, gỡ ứng dụng tận gốc, tìm tệp mồ côi và dọn theo lịch.

Yêu cầu macOS 13 trở lên. Viết bằng Swift và SwiftUI.

## Build

```bash
brew install xcodegen
xcodegen generate
xcodebuild test -project TwanClean.xcodeproj -scheme TwanClean -destination 'platform=macOS'
```

Mặc định bản Debug được ký ad-hoc, nên mỗi lần build lại macOS sẽ quên quyền Full Disk Access. Để giữ quyền ổn định, chép `Configs/Local.xcconfig.example` thành `Configs/Local.xcconfig` và điền Team ID của Personal Team (Xcode › Settings › Accounts).

## Bản dịch

Giao diện có tiếng Anh (ngôn ngữ nguồn) và tiếng Việt, lưu trong `TwanClean/Resources/Localizable.xcstrings`. Sau khi thêm chuỗi mới:

1. Chạy `scripts/sync-strings.sh` để đưa chuỗi vào String Catalog.
2. Chạy `scripts/apply-translations.py <file.json>` với file JSON ánh xạ chuỗi tiếng Anh sang tiếng Việt.
3. `LocalizationTests` sẽ báo lỗi nếu còn chuỗi chưa dịch.

## Giấy phép

MIT. Một số dữ liệu (đường dẫn cache, danh sách app được bảo vệ, quy tắc so khớp) được dùng lại từ [MClean](https://github.com/maclifevn/MClean), xem `THIRD_PARTY_NOTICES`.
