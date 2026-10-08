# 📱 MOBILE_APP – Quy tắc làm việc & Git Workflow

## 1. Quy tắc làm việc chung

- Không code trực tiếp trên branch `main`.
- Mỗi task/chức năng phải tạo một branch riêng.
- Đặt tên branch:
  - `feature/<ten-chuc-nang>` → chức năng mới
  - `fix/<ten-loi>` → sửa lỗi
  - `docs/<noi-dung>` → tài liệu
- Ví dụ:
  - `feature/man-hinh-dang-nhap`
  - `feature/man-hinh-dang-ky`
  - `fix/login-error`
- Commit message phải rõ ràng, ví dụ:
  - `feat: add login screen`
  - `fix: resolve login error`
  - `docs: update README`
- Không commit API key, password, token, `.env` hoặc thông tin bảo mật.
- Trước khi push phải kiểm tra code và đảm bảo project vẫn chạy được.
- Không tự ý sửa/xóa code của người khác nếu chưa trao đổi.
- Sau khi hoàn thành task phải tạo Pull Request để review trước khi merge vào `main`.

---

## 2. 🌿 Tạo branch mới

Mỗi khi bắt đầu một task mới, thực hiện:

### Bước 1: Chuyển về `main`

```bash
git checkout main
```

### Bước 2: Cập nhật code mới nhất

```bash
git pull origin main
```

### Bước 3: Tạo branch riêng

```bash
git checkout -b feature/<ten-chuc-nang>
```

Ví dụ:

```bash
git checkout -b feature/man-hinh-dang-nhap
```

Kiểm tra branch hiện tại:

```bash
git branch --show-current
```

Nếu hiện:

```text
feature/man-hinh-dang-nhap
```

→ Đã ở đúng branch và có thể bắt đầu code.

> Nếu branch đã tồn tại thì không tạo lại. Chỉ cần chuyển sang branch đó:
>
> ```bash
> git checkout feature/man-hinh-dang-nhap
> ```

---

## 3. 💻 Code và kiểm tra thay đổi

Sau khi chuyển sang branch của mình, bắt đầu code.

Kiểm tra những file đã thay đổi:

```bash
git status
```

Xem chi tiết thay đổi:

```bash
git diff
```

---

## 4. 📦 Commit code

Sau khi hoàn thành một phần công việc:

```bash
git add .
```

Sau đó commit:

```bash
git commit -m "feat: add login screen"
```

Một số loại commit thường dùng:

| Type | Ý nghĩa |
|---|---|
| `feat` | Thêm chức năng |
| `fix` | Sửa lỗi |
| `refactor` | Cải thiện/tổ chức lại code |
| `docs` | Cập nhật tài liệu |
| `style` | Thay đổi giao diện/format |
| `test` | Thêm hoặc sửa test |
| `chore` | Công việc kỹ thuật khác |

Ví dụ:

```bash
git commit -m "feat: add login screen"
git commit -m "fix: resolve login validation error"
git commit -m "docs: update README"
```

---

## 5. ⬆️ Push code lên GitHub

### Lần đầu push branch

```bash
git push -u origin <ten-branch>
```

Ví dụ:

```bash
git push -u origin feature/man-hinh-dang-nhap
```

Sau khi push thành công, branch sẽ xuất hiện trên GitHub.

### Những lần push tiếp theo

Chỉ cần:

```bash
git push
```

---

## 6. 🔀 Pull Request

Sau khi hoàn thành task:

```text
Code
 ↓
Commit
 ↓
Push
 ↓
Tạo Pull Request trên GitHub
 ↓
Team review
 ↓
Approve
 ↓
Merge vào main
```

Pull Request nên ghi rõ:
- Đã làm gì?
- Đã thay đổi những file nào?
- Cách kiểm tra chức năng.
- Screenshot nếu có thay đổi giao diện.

Không tự ý merge vào `main` nếu chưa được team thống nhất.

---

## 7. 🔄 Tiếp tục làm việc trên branch đã có

Nếu đã tạo branch trước đó và muốn code tiếp, **không tạo branch mới**.

Kiểm tra branch:

```bash
git branch --show-current
```

Nếu đang ở đúng branch:

```text
feature/man-hinh-dang-nhap
```

→ Có thể code tiếp.

Nếu đang ở branch khác:

```bash
git checkout feature/man-hinh-dang-nhap
```

Sau khi code xong:

```bash
git add .
git commit -m "feat: update login screen"
git push
```

---

## 8. 🔄 Khi `main` có code mới

Nếu thành viên khác đã merge code mới vào `main`, cập nhật trước khi tiếp tục làm việc:

```bash
git checkout main
git pull origin main
```

Sau đó quay lại branch của mình:

```bash
git checkout feature/<ten-branch>
```

Cập nhật code từ `main`:

```bash
git merge main
```

Nếu không có conflict → tiếp tục code.

---

## 9. ⚠️ Xử lý Conflict

Nếu Git báo:

```text
CONFLICT
```

Mở file bị conflict và chỉnh sửa phần code cần giữ.

Sau khi xử lý xong:

```bash
git add .
git commit -m "fix: resolve merge conflict"
git push
```

Nếu không chắc nên giữ code nào → hỏi người phụ trách phần code đó trước khi sửa.

---

## 10. 🗑️ Xóa branch sau khi merge

Sau khi Pull Request đã được merge vào `main`, branch có thể được xóa.

Xóa branch local:

```bash
git branch -d feature/<ten-branch>
```

Xóa branch trên GitHub:

```bash
git push origin --delete feature/<ten-branch>
```

---

## 11. 🏃 Chạy project Flutter

Cài dependencies:

```bash
flutter pub get
```

Kiểm tra môi trường:

```bash
flutter doctor
```

Xem thiết bị có thể chạy:

```bash
flutter devices
```

Chạy project:

```bash
flutter run
```

Chạy trên Chrome:

```bash
flutter run -d chrome
```

---

## 12. 📥 Lần đầu clone project

Nếu thành viên mới chưa có project trên máy:

```bash
git clone <repository-url>
cd <project-folder>
flutter pub get
```

Sau đó tạo branch riêng trước khi code:

```bash
git checkout main
git pull origin main
git checkout -b feature/<ten-chuc-nang>
```

---

## 13. ⚡ Quy trình làm việc đầy đủ

Khi bắt đầu một task mới:

```bash
git checkout main
git pull origin main
git checkout -b feature/ten-chuc-nang
```

Sau đó code.

Khi code xong:

```bash
git status
git add .
git commit -m "feat: mo-ta-thay-doi"
git push -u origin feature/ten-chuc-nang
```

Sau đó lên GitHub:

```text
Pull Request → Review → Approve → Merge vào main
```

Nếu branch đã tồn tại:

```bash
git checkout feature/ten-chuc-nang
```

Sau đó code và:

```bash
git add .
git commit -m "feat: mo-ta-thay-doi"
git push
```

---

## ⭐ Nguyên tắc cần nhớ

> **Không code trên `main` → Mỗi task một branch → Commit rõ ràng → Push → Pull Request → Review → Merge.**
