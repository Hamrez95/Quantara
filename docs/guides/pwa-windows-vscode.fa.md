# اجرای Quantara PWA در ویندوز و VS Code

## پیش‌نیاز یک‌باره

1. Flutter Stable را نصب کن و مسیر `flutter/bin` را به PATH ویندوز اضافه کن.
2. Chrome و VS Code را نصب داشته باش.
3. در ترمینال VS Code از ریشه ریپو اجرا کن:

```powershell
flutter doctor
```

## سریع‌ترین حالت توسعه

از ریشه ریپو:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Run-QuantaraPwa.ps1
```

اسکریپت `flutter pub get` را اجرا می‌کند و برنامه را در Chrome بالا می‌آورد. تغییرات کد با Hot Reload قابل مشاهده است.

## تست خروجی واقعی PWA

برای تست نسخه Release، Service Worker و فایل‌های ساخته‌شده:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Run-QuantaraPwa.ps1 -ReleasePreview
```

بعد مرورگر را روی آدرس زیر باز کن:

```text
http://localhost:8080
```

برای پورت دیگر:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Run-QuantaraPwa.ps1 -ReleasePreview -Port 9090
```

فایل `index.html` را مستقیم با دوبارکلیک باز نکن؛ PWA و Service Worker برای رفتار درست باید از `localhost` یا HTTPS سرو شوند.

## اجرای دستی بدون اسکریپت

```powershell
cd .\src\client\quantara_app
flutter pub get
flutter run -d chrome
```

یا برای Release:

```powershell
flutter build web --release
py -m http.server 8080 --directory build/web
```

برای توقف سرور در ترمینال `Ctrl+C` را بزن.
