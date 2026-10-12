# Phát hành Twan Clean

Ghi chú vận hành cho chủ repo. Người dùng cài app bằng Homebrew, xem [README](../README.md#cài-bằng-homebrew).

## Chuẩn bị một lần

Chạy trên máy Mac đã đăng nhập `gh` bằng tài khoản `twan-nguyen`:

```bash
scripts/setup-release-secrets.sh
```

Script [setup-release-secrets.sh](../scripts/setup-release-secrets.sh) làm lần lượt các bước sau:

1. Tạo chứng chỉ ký "Twan Clean Self-Signed" và cài vào keychain riêng `twanclean-signing.keychain-db` trên máy này. Nhờ đó bản build trên máy và bản phát hành có cùng chữ ký.
2. Lưu chứng chỉ vào hai secret `SIGNING_CERT_P12_BASE64` và `SIGNING_CERT_PASSWORD` của repo twan-clean.
3. Tạo một deploy key có quyền ghi trên [homebrew-tap](https://github.com/twan-nguyen/homebrew-tap) và lưu khoá riêng vào secret `TAP_DEPLOY_KEY`. Khoá riêng không được giữ lại trên máy.

Nếu máy đã có keychain ký từ trước, truyền file `.p12` đã tạo nó: `TWANCLEAN_P12_PASSWORD=… scripts/setup-release-secrets.sh identity.p12`.

Sau bước này, app trên máy được ký bằng chứng chỉ mới, nên cần cấp lại Full Disk Access một lần cuối.

## Phát hành bản mới

1. Commit và push mọi thay đổi lên `main`.
2. Tạo tag phiên bản và push tag:

   ```bash
   git tag v0.1.0 && git push origin v0.1.0
   ```

3. Theo dõi workflow [release.yml](../.github/workflows/release.yml) bằng `gh run watch --repo twan-nguyen/twan-clean`.
4. Kiểm tra cask đã lên phiên bản mới:

   ```bash
   gh api repos/twan-nguyen/homebrew-tap/contents/Casks/twan-clean.rb --jq .content | base64 -d | grep 'version "'
   ```

Workflow làm lần lượt các bước sau:
- Build bản Release universal. Số phiên bản lấy từ tag; build number là số commit.
- Ký lại bằng "Twan Clean Self-Signed".
- Nén thành `TwanClean-X.Y.Z.zip` và tạo GitHub Release.
- Ghi `Casks/twan-clean.rb` trong homebrew-tap.

Workflow này chỉ build, không chạy test. Hãy chạy `scripts/test.sh` trên máy trước khi gắn tag.

### Quy tắc

- Tag phải có dạng `vX.Y.Z`, ví dụ `v0.1.0`. Tag sai dạng làm workflow dừng ngay.
- App chưa có tự cập nhật, nên người dùng nhận bản mới bằng `brew upgrade --cask twan-clean`.

### Khi phát hành hỏng

Xem log bằng `gh run view --log-failed --repo twan-nguyen/twan-clean`. Sửa lỗi, rồi xoá release và tag cũ trước khi gắn lại:

```bash
gh release delete v0.1.0 --repo twan-nguyen/twan-clean --yes
git push origin :refs/tags/v0.1.0 && git tag -d v0.1.0
```

Nếu workflow đã kịp cập nhật cask trước khi hỏng, lần chạy sau sẽ ghi đè lên.

## Khoá và chứng chỉ nằm ở đâu

| Thứ | Trên máy | Trên GitHub |
|---|---|---|
| Chứng chỉ "Twan Clean Self-Signed" (hạn 10 năm) | `~/Library/Keychains/twanclean-signing.keychain-db`; mật khẩu keychain nằm trong login keychain, mục `twanclean-signing-keychain` | Secret `SIGNING_CERT_P12_BASE64` và `SIGNING_CERT_PASSWORD` |
| Deploy key để ghi cask | Không lưu | Secret `TAP_DEPLOY_KEY`, kèm deploy key "twan-clean release" trên homebrew-tap |

Không có bản sao lưu nào ngoài hai nơi trên. Nếu mất cả hai, tạo chứng chỉ mới bằng script ở trên; người dùng sẽ phải cấp lại Full Disk Access một lần.
