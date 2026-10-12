# Twan Clean

Ứng dụng dọn dẹp cho macOS: quét rác, soi dung lượng ổ đĩa bằng bản đồ bong bóng, gỡ ứng dụng tận gốc, tìm tệp mồ côi và dọn theo lịch.

Yêu cầu macOS 13 trở lên. Viết bằng Swift và SwiftUI.

## Build

```bash
brew install xcodegen
xcodegen generate
xcodebuild test -project TwanClean.xcodeproj -scheme TwanClean -destination 'platform=macOS'
```

Test chỉ chạy trên thư mục tạm, không bao giờ đọc dữ liệu thật trong home của bạn.

## Cài lên máy

```bash
scripts/install.sh
```

Script build bản Release, ký lại, chép vào `/Applications/TwanClean.app` rồi mở app.

Bản ký ad-hoc bị macOS coi là app mới sau mỗi lần cài, nên quyền Full Disk Access sẽ mất. Để macOS nhớ quyền, tạo một chứng chỉ ký tự cấp (làm một lần), giống Twanotch:

```bash
scripts/create-signing-identity.sh ~/twanclean-signing.p12
scripts/setup-signing-keychain.sh ~/twanclean-signing.p12
```

Chứng chỉ "Twan Clean Self-Signed" nằm trong keychain riêng `twanclean-signing.keychain-db`. Mật khẩu của keychain đó được lưu trong login keychain để `install.sh` dùng.

## Quyền truy cập

Khi chưa có quyền Full Disk Access, Twan Clean không đọc các thư mục macOS bảo vệ (Desktop, Documents, Downloads, Ảnh, Nhạc, iCloud Drive, dữ liệu của app khác…). Các thư mục này hiện là "bị khoá" kèm nút mở cài đặt, nên macOS không hiện hộp thoại hỏi quyền cho từng thư mục. Riêng thư mục bạn tự chọn trong Space Lens vẫn được đọc, vì chọn bằng hộp thoại Mở được macOS tính là đồng ý.

## Bản dịch

Giao diện có tiếng Anh (ngôn ngữ nguồn) và tiếng Việt, lưu trong `TwanClean/Resources/Localizable.xcstrings`. Sau khi thêm chuỗi mới:

1. Chạy `scripts/sync-strings.sh` để đưa chuỗi vào String Catalog.
2. Chạy `scripts/apply-translations.py <file.json>` với file JSON ánh xạ chuỗi tiếng Anh sang tiếng Việt.
3. `LocalizationTests` sẽ báo lỗi nếu còn chuỗi chưa dịch.

## Giấy phép

MIT. Một số dữ liệu (đường dẫn cache, danh sách app được bảo vệ, quy tắc so khớp) được dùng lại từ [MClean](https://github.com/maclifevn/MClean), xem `THIRD_PARTY_NOTICES`.
