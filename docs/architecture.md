# Kiến trúc Twan Clean

Tài liệu này giải thích các module và ranh giới an toàn mà người sửa code cần giữ. Chi tiết của từng tính năng nằm ngay trong source.

## Module

```
TwanClean/
├── App/            Điểm vào: chọn chế độ GUI hoặc chạy theo lịch (LaunchMode, AppEntry),
│                   AppDelegate (menu Dịch vụ của Finder, icon menu bar)
├── Shell/          Cửa sổ chính, sidebar, Cài đặt, onboarding, AppModel (giữ state của mọi tính năng)
├── Core/
│   ├── Safety/     PathPolicy, SafetyRules, RemovalService, PrivilegedRemover: ranh giới an toàn
│   ├── FileSystem/ FileTreeWalker (fts), AllocatedSizeCalculator, FileIdentity, DiskSpace
│   ├── Permissions/FullDiskAccess, ProtectedLocations, PermissionCoordinator
│   └── Process/    ProcessRunner, CommandRunner (gọi brew/npm/docker bằng argv, có timeout)
├── Features/
│   ├── SmartScan/  10 CategoryScanner, SmartScanCoordinator (chạy song song, chia mục chồng nhau)
│   ├── SpaceLens/  SizeTreeBuilder, SizeNode, CirclePacker, giao diện bong bóng
│   ├── Uninstaller/InstalledAppIndex, AppMatcher (các tier khớp), LeftoverFinder, ContainerResolver
│   ├── Orphans/    OrphanFinder, OrphanSkipList, OrphanIgnoreStore
│   ├── Scheduler/  ScheduleSettings, ScheduledRunner (chạy nền), RunLock, SchedulerAgent
│   └── MenuBar/    MenuBarController (NSStatusItem), MenuBarPanel
└── Resources/      String Catalog, Info.plist, entitlements, LaunchAgents/
```

## Ranh giới an toàn

```
Tính năng ──RemovalRequest(url, purpose, identity)──▶ RemovalService
                                                      1. PathPolicy.evaluate(url, purpose)
                                                      2. So identity (dev:inode) với lúc quét
                                                      3. purpose.mode: xoá hẳn hoặc vào Thùng rác
   bị chặn vì thiếu quyền ──(người dùng đồng ý)──▶ PrivilegedRemover (staging + SHA-256 + rm -x)
```

- Chỉ `Core/Safety` được gọi `removeItem`, `trashItem`, `recycle` và lệnh xoá với quyền root. Các tính năng chỉ gửi `RemovalRequest`.
- `RemovalPurpose` quyết định cả vùng được phép xoá lẫn cách xoá. Chỉ `.regenerableCache` và `.trashContents` bị xoá hẳn; mọi purpose khác đều vào Thùng rác.
- `PathPolicy`:
  - Chuẩn hoá thư mục cha bằng `realpath`, không đi theo symlink ở thành phần cuối.
  - So sánh theo Unicode đã chuẩn hoá và không phân biệt hoa thường.
  - Từ chối root được bảo vệ, cây hệ thống, khoá và cấu hình trong home, thư mục chuẩn của Library, dữ liệu Apple, app lồng trong app, và mount point.
- Muốn thêm vùng được phép xoá thì sửa `SafetyRules` và thêm test trong `TwanCleanTests/Safety`.

## Quyền truy cập

- `ProtectedLocations` liệt kê các thư mục macOS bảo vệ.
- Khi chưa có Full Disk Access (`ProtectedLocations.current()` khác nil), mọi scanner và Space Lens bỏ qua các thư mục này và báo là "bị khoá". Nhờ vậy macOS không bật hộp thoại hỏi quyền giữa chừng.
- Thư mục người dùng chọn qua NSOpenPanel được coi là đã đồng ý.

## Chạy theo lịch

- LaunchAgent `Contents/Library/LaunchAgents/com.twan.twanclean.scheduler.plist` được đăng ký qua `SMAppService.agent`.
- Agent chạy `TwanClean --scheduled-run` mỗi giờ. `ScheduledRunner` tự kiểm tra lịch; chưa đến hạn thì thoát ngay.
- `RunLock` (flock trên `~/Library/Application Support/TwanClean/scan.lock`) ngăn lượt chạy nền và Quét thông minh trong app chạy cùng lúc.
- Tự dọn chỉ áp dụng cho mục được chọn sẵn, không cần mật khẩu, và có purpose `.regenerableCache` hoặc `.trashContents`. Tệp lớn và cũ không bao giờ được đưa vào lịch.

## Test

- `scripts/test.sh` chạy toàn bộ test. Test chỉ làm việc trên thư mục tạm (`TemporaryTree`, `FakeHome`) và không bao giờ đọc dữ liệu thật của người dùng.
- Các phụ thuộc như home, danh sách thư mục cần tìm, file khoá và nơi lưu cài đặt đều được truyền vào để test thay được.
