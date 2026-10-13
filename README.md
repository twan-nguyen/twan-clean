# Twan Clean

Ứng dụng dọn dẹp cho macOS 13 trở lên, viết bằng Swift và SwiftUI. Giao diện có tiếng Việt và tiếng Anh.

## Tính năng

- **Quét thông minh:** tìm rác ở 10 nơi cùng lúc. Gồm rác hệ thống, cache người dùng, ứng dụng AI (Ollama, LM Studio), tệp đính kèm Mail, Thùng rác, tệp lớn và cũ, rác Xcode, cache Homebrew, Node và Docker. Mỗi mục chỉ được tính ở một hạng mục, nên không bị đếm trùng.
- **Space Lens:** đo một thư mục và hiển thị thành bản đồ bong bóng có kích thước theo dung lượng thật. Bấm vào để đi sâu, chọn mục rồi chuyển vào Thùng rác.
- **Gỡ ứng dụng:** tìm mọi tệp một app đã rải trong các thư mục Library, theo 3 mức Nghiêm ngặt, Nâng cao và Sâu. Trong Finder, Control-click vào app rồi chọn Dịch vụ › Gỡ bằng Twan Clean.
- **Tệp mồ côi:** cache, log và trạng thái đã lưu của những app đã bị xoá. Mục nào không muốn thấy nữa thì đánh dấu "Luôn bỏ qua".
- **Dọn theo lịch:** chạy nền kể cả khi app đã đóng. Có thể chỉ quét rồi báo, hoặc tự dọn cache tự tạo lại được. Thùng rác, tệp đính kèm Mail và tệp lớn không bao giờ bị dọn tự động. Icon trên menu bar cho xem nhanh dung lượng đĩa và kết quả lần chạy gần nhất.

## Cam kết an toàn

| Loại mục | Cách xoá |
|---|---|
| Cache, log, tệp tạm do ứng dụng tự tạo lại | Xoá hẳn |
| Mục trong Thùng rác | Xoá hẳn |
| Ứng dụng, tệp sót của ứng dụng, tệp mồ côi, tệp lớn, archive Xcode, lịch sử trò chuyện AI | Chuyển vào Thùng rác, khôi phục được |

- Mọi thao tác xoá đều đi qua một cổng duy nhất (`TwanClean/Core/Safety`). Cổng này luôn từ chối các vị trí sau:
  - thư mục của hệ thống;
  - các thư mục gốc chuẩn như `~/Library/Application Support`;
  - khoá và cấu hình (`~/.ssh`, `~/.aws`, Keychains…);
  - dữ liệu của Apple.
- Ngay trước khi xoá, mỗi mục được kiểm tra lại xem có còn đúng là tệp đã quét không.
- Không có gì bị xoá nếu bạn chưa xem và chọn. Mục cấp hệ thống, mục cần mật khẩu, cache của app đang chạy và dữ liệu cá nhân không bao giờ được chọn sẵn.
- Khi cần quyền quản trị, macOS sẽ hỏi mật khẩu. Danh sách mục cần xoá được kiểm tra bằng mã băm, và lệnh xoá không đi sang ổ đĩa khác.

## Quyền truy cập

- **Full Disk Access:** khi chưa có quyền này, Twan Clean không đọc các thư mục macOS bảo vệ (Desktop, Documents, Downloads, Ảnh, Nhạc, iCloud Drive, Mail, dữ liệu của app khác…). Các thư mục đó hiện là "bị khoá" kèm nút mở cài đặt, nên macOS không bật hộp thoại hỏi quyền cho từng thư mục. Riêng thư mục bạn tự chọn trong Space Lens vẫn được đọc.
- **Quản lý ứng dụng:** macOS 13 trở lên cần quyền này để chuyển một app ra khỏi /Applications. Nếu bị chặn, app sẽ chỉ chỗ bật quyền.
- **Thông báo:** không bắt buộc, chỉ dùng để báo kết quả dọn theo lịch.

## Cài bằng Homebrew

```bash
brew install --cask twan-nguyen/tap/twan-clean
```

- Sau khi cài, cấp quyền Full Disk Access cho Twan Clean trong System Settings › Privacy & Security › Full Disk Access.
- Cập nhật: `brew upgrade --cask twan-clean`. Gỡ: `brew uninstall --cask twan-clean`, thêm `--zap` để xoá cả cài đặt và dữ liệu của app.
- App được ký bằng chứng chỉ tự cấp và chưa notarize. Cask tự gỡ cờ quarantine để macOS cho mở app.

Cách phát hành bản mới: xem [docs/releasing.md](docs/releasing.md).

## Build và test

```bash
brew install xcodegen
scripts/test.sh
```

Test chỉ chạy trên thư mục tạm, không bao giờ đọc dữ liệu thật trong home của bạn. Bản Debug được ký ad-hoc.

## Cài lên máy

```bash
scripts/install.sh
```

Script build bản Release, ký lại, chép vào `/Applications/TwanClean.app` rồi mở app. Lệnh `scripts/package-local.sh` thì đóng gói thành `dist/TwanClean-<version>.zip` để mang sang máy khác. App chưa được notarize, nên lần đầu mở trên máy khác sẽ bị macOS chặn. Hãy vào System Settings › Privacy & Security rồi bấm "Open Anyway". Từ macOS 15, Control-click › Mở không còn bỏ qua được bước này.

Bản ký ad-hoc bị macOS coi là app mới sau mỗi lần cài, nên quyền Full Disk Access sẽ mất. Để macOS nhớ quyền, tạo chứng chỉ ký tự cấp một lần bằng `scripts/setup-release-secrets.sh` (xem [docs/releasing.md](docs/releasing.md)). Nếu chỉ build trên máy mà không phát hành, dùng hai script con:

```bash
scripts/create-signing-identity.sh ~/twanclean-signing.p12
scripts/setup-signing-keychain.sh ~/twanclean-signing.p12
```

Chứng chỉ "Twan Clean Self-Signed" nằm trong keychain riêng `twanclean-signing.keychain-db`. Mật khẩu của keychain đó được lưu trong login keychain để các script dùng.

## Bản dịch

Chuỗi giao diện nằm trong `TwanClean/Resources/Localizable.xcstrings`. Chuỗi của Info.plist nằm trong `InfoPlist.xcstrings`, còn tên trong menu Dịch vụ nằm trong `*.lproj/ServicesMenu.strings`. Sau khi thêm chuỗi mới:

1. Chạy `scripts/sync-strings.sh` để đưa chuỗi vào String Catalog.
2. Chạy `scripts/apply-translations.py <file.json>` với file JSON ánh xạ chuỗi tiếng Anh sang tiếng Việt.
3. `LocalizationTests` sẽ báo lỗi nếu còn chuỗi chưa dịch.

Icon được vẽ bằng `swift scripts/generate-app-icon.swift`.

## Kiến trúc

Xem [docs/architecture.md](docs/architecture.md).

## Giấy phép

MIT. Một số dữ liệu (đường dẫn cache, danh sách app được bảo vệ, quy tắc so khớp, danh sách bỏ qua) được dùng lại từ [MClean](https://github.com/maclifevn/MClean); xem `THIRD_PARTY_NOTICES`.
