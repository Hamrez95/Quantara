# امضای دائمی نسخه Stable اندروید Quantara

این سند فقط فرایند را تعریف می‌کند. فایل Keystore، رمزها و کلید خصوصی نباید وارد Git، Artifact عمومی، Log، Screenshot یا Chat شوند.

## تفاوت Canary و Stable

### Canary داخلی

- Package: `com.quantara.quantara_app.alpha`
- پسوند نسخه: `-preview`
- امضای Debug
- مناسب تست فیزیکی و نصب کنار نسخه Stable
- نامناسب برای انتشار عمومی و Upgrade دائمی

### Stable عمومی

- Package: `com.quantara.quantara_app`
- بدون پسوند Alpha/Preview
- امضا با Keystore دائمی مالک پروژه
- کلید باید برای تمام نسخه‌های آینده حفظ شود

## ساخت یک‌باره Keystore

این کار باید روی سیستم امن مالک پروژه انجام شود. نمونه فرمان:

```powershell
keytool -genkeypair `
  -v `
  -keystore quantara-upload.jks `
  -alias quantara-upload `
  -keyalg RSA `
  -keysize 4096 `
  -validity 10000
```

رمزهای قوی و منحصربه‌فرد انتخاب شوند. فایل و رمزها حداقل در دو محل رمزگذاری‌شده و مستقل پشتیبان‌گیری شوند.

## Secretهای GitHub Environment

در Environment محافظت‌شده `android-stable-release` این Secretها تعریف شوند:

- `QUANTARA_ANDROID_KEYSTORE_BASE64`
- `QUANTARA_ANDROID_KEYSTORE_PASSWORD`
- `QUANTARA_ANDROID_KEY_ALIAS`
- `QUANTARA_ANDROID_KEY_PASSWORD`

برای تبدیل Keystore به Base64 در PowerShell:

```powershell
[Convert]::ToBase64String(
  [IO.File]::ReadAllBytes("quantara-upload.jks")
) | Set-Clipboard
```

Base64 کلید خصوصی محسوب می‌شود و نباید در فایل یا پیام عادی ذخیره شود.

## قواعد انتشار

- Workflow Stable فقط از `main` یا `release/*` اجرا شود.
- Environment Approval فعال باشد.
- نبود هر Secret باید Build را Fail کند؛ Fallback به Debug ممنوع است.
- قبل از انتشار، Package ID، Version Code، Version Name، SHA-256 فایل و SHA-256 گواهی ثبت شوند.
- نسخه جدید باید روی نسخه Stable قبلی بدون Uninstall نصب شود.
- Secure Storage و تنظیمات محلی باید پس از Upgrade باقی بمانند.

## بازیابی بحران

گم‌شدن کلید دائمی می‌تواند مسیر Upgrade کاربران را از بین ببرد. بنابراین:

1. دو Backup رمزگذاری‌شده مستقل نگه‌داری شود.
2. دسترسی فقط برای مالک/مسئول انتشار باشد.
3. Fingerprint عمومی گواهی در Release Manifest ثبت شود.
4. هیچ ابزار خودکار اجازه تولید و جایگزینی بی‌صدای کلید را نداشته باشد.
