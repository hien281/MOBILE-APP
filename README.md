# 🏟️ SPORTY – Mobile Sports Field Booking App

Ứng dụng đặt sân thể thao được phát triển bằng **Flutter**, sử dụng **Node.js/Express** cho backend và **Firebase Firestore** để lưu trữ dữ liệu.

Repository: https://github.com/hien281/MOBILE-APP

Backend Production: https://mobile-app-nine-lac.vercel.app

---

## 📌 1. Tổng quan dự án

### Công nghệ sử dụng

| Thành phần | Công nghệ |
|---|---|
| Frontend | Flutter / Dart |
| Backend | Node.js / Express |
| Database | Firebase Cloud Firestore |
| Authentication | JWT (phiên bản demo hiện tại) |
| Backend Hosting | Vercel |
| Version Control | Git & GitHub |

### Các chức năng hiện có

- Đăng nhập tài khoản demo.
- Hiển thị danh sách sân thể thao.
- Lấy thông tin chi tiết sân.
- Kiểm tra khung giờ còn trống theo ngày.
- Đặt sân và lưu dữ liệu lên Firestore.
- Ngăn đặt trùng khung giờ bằng Firestore Transaction.

### Các chức năng đang phát triển

- Lấy và cập nhật vị trí hiện tại.
- Tìm sân gần người dùng.
- Đặt sân cố định theo tuần.
- Xem lịch sử và hủy đặt sân.
- Hoàn thiện xác thực tài khoản.

---

## 📥 2. Clone project về máy

### Bước 1: Chuẩn bị môi trường

Cần cài đặt:

- Git
- Flutter SDK
- VS Code hoặc Android Studio
- Chrome hoặc Android Emulator
- Node.js và npm (nếu phát triển backend)

Kiểm tra môi trường Flutter:

```bash
flutter doctor
```

### Bước 2: Clone repository

Mở Terminal hoặc PowerShell tại thư mục muốn lưu project:

```bash
git clone https://github.com/hien281/MOBILE-APP.git SPORTY
```

Di chuyển vào project:

```bash
cd SPORTY
```

**Lưu ý:** Không cần tạo thư mục `SPORTY` trước. Git sẽ tự tạo thư mục khi clone.

### Bước 3: Cài dependencies Flutter

```bash
flutter pub get
```

### Bước 4: Chạy ứng dụng

Chạy trên Chrome:

```bash
flutter run -d chrome
```

Hoặc xem danh sách thiết bị:

```bash
flutter devices
```

Sau đó chạy:

```bash
flutter run
```

Ứng dụng Flutter mặc định kết nối backend đã triển khai trên Vercel.

**Không cần chạy Node.js local nếu chỉ phát triển giao diện Flutter và sử dụng API online.**

---

## 🌐 3. Cấu hình API

Backend Production:

```text
https://mobile-app-nine-lac.vercel.app/api
```

Trong `lib/api_client.dart`, API base URL được cấu hình bằng `API_BASE_URL`.

### Sử dụng backend Production

```bash
flutter run -d chrome
```

Hoặc chỉ định rõ:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=https://mobile-app-nine-lac.vercel.app/api
```

### Sử dụng backend local

Chạy backend trong terminal riêng:

```bash
cd backend
npm install
node server.js
```

Sau đó, từ thư mục gốc của project, chạy Flutter:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000/api
```

**Không thêm `https://` hai lần vào API URL.**

**Không chạy `npm install` và `yarn install` cùng lúc.** Project backend sử dụng npm; chỉ cài Node dependencies khi cần làm việc với backend.

---

## 🔐 4. Bảo mật – Quy định bắt buộc

### 🚨 TUYỆT ĐỐI KHÔNG commit thông tin bí mật

Các file và dữ liệu bị cấm đưa lên GitHub:

- `.env`, `.env.local`, `.env.production`
- Firebase Service Account JSON
- Firebase private key
- JWT Secret
- Access Token, mật khẩu
- Các file chứa credentials hoặc thông tin nhạy cảm

**Không chia sẻ secret trong GitHub Issues, Pull Request, nhóm chat hoặc ảnh chụp màn hình.**

### 🚫 Cấm sử dụng các lệnh stage toàn bộ thay đổi

```bash
git add .
git add -A
git add --all
git commit -am "message"
```

Các lệnh này có thể vô tình đưa file chứa secret vào commit.

### ✅ Chỉ add file thực sự cần thiết

Ví dụ:

```bash
git add lib/screen/home.dart
```

```bash
git add lib/screen/booking.dart
```

```bash
git add pubspec.yaml pubspec.lock
```

```bash
git add backend/server.js
```

```bash
git add backend/bookingRoutes.js
```

Có thể add cả thư mục `lib/` khi cần, nhưng **ưu tiên add từng file**.

Không add cả thư mục `backend/` nếu chưa kiểm tra kỹ các file bên trong.

### 🔍 Bắt buộc kiểm tra trước khi commit

```bash
git status
git diff --cached --name-only
git diff --cached
```

Kiểm tra:

1. Có đúng những file mình muốn commit không?
2. Có file `.env` hoặc JSON bí mật không?
3. Có token, mật khẩu hoặc private key trong phần code thay đổi không?
4. Có vô tình sửa code của teammate không?

Nếu lỡ stage nhầm file:

```bash
git restore --staged duong-dan-file
```

Lệnh này chỉ bỏ file khỏi staging, không xóa nội dung file trên máy.

### 🛡️ Cấu hình `.gitignore`

Đảm bảo `.gitignore` có các quy tắc phù hợp:

```gitignore
.env
.env.*
!.env.example

backend/secrets/
*serviceAccount*.json
*service-account*.json

node_modules/
```

**Lưu ý:** `.gitignore` không bảo vệ những file đã được Git theo dõi từ trước. Vì vậy vẫn phải kiểm tra staged changes trước khi commit.

Nếu phát hiện secret đã bị push lên GitHub, cần báo ngay cho nhóm, thu hồi hoặc thay mới secret bị lộ. Chỉ xóa file khỏi commit mới là chưa đủ.

---

## 👥 5. Quy tắc làm việc nhóm

1. Không code trực tiếp trên branch `main`.
2. Mỗi task hoặc chức năng sử dụng một branch riêng.
3. Mỗi thành viên chịu trách nhiệm code và sửa lỗi chức năng mình phụ trách.
4. Không tự ý sửa hoặc xóa code của người khác.
5. Không commit file chứa secret.
6. Không sử dụng `git add .` hoặc các lệnh stage toàn bộ thay đổi.
7. Trước khi push phải kiểm tra code và chạy thử chức năng.
8. Mọi thay đổi vào `main` phải thông qua Pull Request.
9. Không tự ý merge khi chưa được nhóm thống nhất.
10. Khi có lỗi sau deployment, người phụ trách tính năng cần tham gia kiểm tra và sửa lỗi.

### Quy tắc đặt tên branch

| Loại | Cú pháp | Ví dụ |
|---|---|---|
| Chức năng mới | `feature/<ten>` | `feature/user-location` |
| Sửa lỗi | `fix/<ten>` | `fix/booking-error` |
| Tài liệu | `docs/<ten>` | `docs/update-readme` |
| Cải thiện code | `refactor/<ten>` | `refactor/api-client` |

### Quy tắc commit message

| Type | Ý nghĩa |
|---|---|
| `feat` | Thêm chức năng |
| `fix` | Sửa lỗi |
| `refactor` | Tổ chức, cải thiện code |
| `docs` | Cập nhật tài liệu |
| `style` | Thay đổi giao diện hoặc định dạng |
| `test` | Thêm hoặc sửa test |
| `chore` | Công việc kỹ thuật khác |

Ví dụ:

```bash
git commit -m "feat: add current location feature"
```

```bash
git commit -m "fix: resolve booking conflict"
```

```bash
git commit -m "docs: update team workflow"
```

---

## 🌿 6. Tạo branch mới

**Chỉ thực hiện khi bắt đầu một task mới.**

### Bước 1: Kiểm tra thay đổi hiện tại

```bash
git status
```

Nếu có thay đổi chưa commit, cần lưu hoặc xử lý chúng trước khi chuyển branch.

### Bước 2: Cập nhật main

```bash
git switch main
git pull --ff-only origin main
```

### Bước 3: Tạo branch riêng

```bash
git switch -c feature/user-location
```

Kiểm tra:

```bash
git branch --show-current
```

Kết quả mong đợi:

```text
feature/user-location
```

Nếu branch đã tồn tại, không tạo lại:

```bash
git switch feature/user-location
```

---

## 💻 7. Code và commit an toàn

### Bước 1: Kiểm tra file đã sửa

```bash
git status
git diff
```

### Bước 2: Chỉ stage file cần commit

Ví dụ sửa màn hình Home và thêm dịch vụ vị trí:

```bash
git add lib/screen/home.dart
git add lib/location_service.dart
git add pubspec.yaml pubspec.lock
```

### Bước 3: Kiểm tra staged changes

```bash
git diff --cached --name-only
git diff --cached
```

**Nếu có file lạ hoặc secret, phải xử lý trước khi commit.**

### Bước 4: Commit

```bash
git commit -m "feat: add current location feature"
```

### Bước 5: Push branch

Lần đầu:

```bash
git push -u origin feature/user-location
```

Những lần sau:

```bash
git push
```

**Không push trực tiếp lên `main`.**

---

## 🔄 8. Tiếp tục làm việc trên branch cũ

Kiểm tra branch:

```bash
git branch --show-current
```

Nếu đang ở branch khác, sau khi xử lý các thay đổi chưa commit:

```bash
git switch feature/user-location
```

Tiếp tục code và commit như bình thường:

```bash
git status
git add lib/screen/home.dart
git diff --cached
git commit -m "feat: improve location display"
git push
```

Không cần tạo branch mới mỗi lần mở VS Code.

---

## 🔀 9. Pull Request và merge

Sau khi hoàn thành task:

1. Push branch lên GitHub.
2. Vào repository `MOBILE-APP`.
3. Chọn **Pull requests → New pull request**.
4. Chọn:
   - `base: main`
   - `compare: branch-cua-ban`
5. Điền mô tả Pull Request.
6. Chờ team review.
7. Sửa các lỗi được phát hiện.
8. Merge sau khi được thống nhất.

### Pull Request cần có

- **Mục tiêu:** Chức năng hoặc lỗi được xử lý.
- **Thay đổi:** Những file và phần code chính đã sửa.
- **Cách test:** Hướng dẫn kiểm tra chức năng.
- **Kết quả:** Đã test thành công hay còn hạn chế.
- **Screenshot:** Nếu có thay đổi giao diện.

### Quy trình

```text
Tạo branch riêng
       ↓
      Code
       ↓
Kiểm tra file thay đổi
       ↓
Stage đúng file cần thiết
       ↓
     Commit
       ↓
      Push
       ↓
  Pull Request
       ↓
  Review & Test
       ↓
 Merge vào main
       ↓
Vercel Production Deploy
```

---

## 🔄 10. Khi main có code mới

Trước tiên, đảm bảo đã commit hoặc lưu an toàn các thay đổi đang làm.

Cập nhật main:

```bash
git switch main
git pull --ff-only origin main
```

Quay lại branch của mình:

```bash
git switch feature/user-location
```

Đưa thay đổi mới từ main vào branch:

```bash
git merge main
```

Nếu không có conflict, tiếp tục phát triển.

Nếu có conflict, xử lý theo mục tiếp theo.

---

## ⚠️ 11. Xử lý Git Conflict

Khi Git báo:

```text
CONFLICT
```

Thực hiện:

1. Chạy `git status` để xem file bị conflict.
2. Mở file đó trong VS Code.
3. Xem phần thay đổi của cả hai bên.
4. Trao đổi với người phụ trách nếu chưa rõ nên giữ đoạn code nào.
5. Xóa các dấu conflict sau khi xử lý.
6. Chạy thử chức năng bị ảnh hưởng.

Sau đó chỉ stage những file đã giải quyết:

```bash
git add lib/screen/home.dart
```

Kiểm tra:

```bash
git diff --cached
git status
```

Hoàn tất merge:

```bash
git commit
git push
```

Nếu muốn hủy quá trình merge đang bị conflict:

```bash
git merge --abort
```

**Không dùng `git add .` để xử lý conflict.**

---

## ☁️ 12. Vercel Deployment

Backend SPORTY được triển khai trên Vercel và liên kết với GitHub.

### Production

Branch chính:

```text
main
```

Domain:

```text
https://mobile-app-nine-lac.vercel.app
```

Sau khi code được merge vào `main`, Vercel có thể tự tạo deployment mới.

Cần kiểm tra trạng thái deployment trong Vercel Dashboard để xác nhận triển khai thành công.

### Preview

Các branch tính năng có thể được Vercel tạo Preview Deployment để kiểm thử trước khi merge, tùy quyền truy cập và giới hạn của gói Vercel.

### Phân chia trách nhiệm

| Công việc | Người phụ trách |
|---|---|
| Viết API | Thành viên được giao tính năng |
| Test API | Thành viên viết API |
| Sửa lỗi logic API | Thành viên viết API |
| Review Pull Request | Thành viên được phân công review |
| Quản lý Vercel | Người quản lý deployment |
| Cấu hình Environment Variables | Người được cấp quyền |
| Kiểm tra deployment sau merge | Người phụ trách phát hành và người viết tính năng |

**Người quản lý Vercel không có nghĩa vụ tự sửa tất cả API của nhóm.**

### Environment Variables

Backend có thể cần các biến:

```text
FIREBASE_SERVICE_ACCOUNT
JWT_SECRET
```

Các giá trị này được cấu hình trong Vercel Environment Variables và **không được commit lên GitHub**.

Nếu chỉ chạy Flutter kết nối API Vercel, thành viên không cần Firebase Service Account trên máy.

Nếu phát triển backend local, thành viên cần cấu hình thông tin xác thực được cấp quyền phù hợp.

---

## 🧪 13. API hiện có

Base URL:

```text
https://mobile-app-nine-lac.vercel.app/api
```

| Method | Endpoint | Chức năng |
|---|---|---|
| POST | `/auth/login` | Đăng nhập, nhận JWT |
| GET | `/fields` | Lấy danh sách sân |
| GET | `/fields/:id` | Lấy chi tiết sân |
| GET | `/fields/:id/availability?date=YYYY-MM-DD` | Kiểm tra lịch trống |
| POST | `/bookings` | Đặt sân, chống trùng lịch |

### API đặt sân

Endpoint:

```text
POST /api/bookings
```

Yêu cầu header:

```text
Authorization: Bearer <accessToken>
```

Ví dụ request body:

```json
{
  "fieldId": "field_01",
  "date": "2026-10-25",
  "startTime": "19:00"
}
```

Backend lưu dữ liệu vào Firestore:

- `bookings`: thông tin đơn đặt sân.
- `booking_slots`: các khung giờ đã được giữ chỗ.

Nếu khung giờ đã được đặt, API trả về HTTP `409 Conflict`.

**Lưu ý:** Hệ thống xác thực hiện tại phục vụ giai đoạn demo. Cần hoàn thiện bảo mật và kiểm tra thời gian đặt sân ở backend trước khi sử dụng thực tế.

---

## 🗑️ 14. Xóa branch sau khi merge

Sau khi Pull Request đã merge và xác nhận không còn cần branch:

Cập nhật main:

```bash
git switch main
git pull --ff-only origin main
```

Xóa branch local:

```bash
git branch -d feature/user-location
```

Nếu cần xóa branch trên GitHub:

```bash
git push origin --delete feature/user-location
```

**Không xóa branch đang có thay đổi chưa được lưu hoặc chưa được merge.**

---

## 🚨 15. Checklist trước khi push

- [ ] Đang ở đúng branch, không phải `main`.
- [ ] Đã chạy thử chức năng mình sửa.
- [ ] Đã kiểm tra `git status`.
- [ ] Chỉ stage những file cần thiết.
- [ ] Đã kiểm tra `git diff --cached`.
- [ ] Không có `.env`, private key, password hoặc token.
- [ ] Không vô tình sửa hoặc xóa code của teammate.
- [ ] Commit message rõ ràng.
- [ ] Push lên đúng branch.
- [ ] Tạo Pull Request để team review.

---

## ⭐ Quy tắc quan trọng nhất

**Không code trực tiếp trên `main`.**

**Không sử dụng `git add .`, `git add -A`, `git add --all` hoặc `git commit -am`.**

**Chỉ commit những file đã kiểm tra và thực sự cần thiết.**

**Không đưa bất kỳ thông tin bí mật nào lên GitHub.**

**Mỗi thành viên chịu trách nhiệm về chức năng mình phát triển.**

### Quy trình chuẩn của SPORTY

```text
Pull main mới nhất
       ↓
Tạo hoặc chuyển vào branch riêng
       ↓
Code và test
       ↓
Git status
       ↓
Git add đúng file
       ↓
Git diff --cached
       ↓
Commit
       ↓
Push branch
       ↓
Pull Request
       ↓
Review
       ↓
Merge main
       ↓
Kiểm tra Vercel
```

**An toàn bảo mật – Rõ ràng trách nhiệm – Không làm ảnh hưởng code của người khác.**
