# Broiler Buddy (RTL Arabic)

هذا مشروع Flutter جاهز لـ **Broiler Buddy**:
- إدخال يومي (T, RH, العلف, النافق, وزن).
- حساب **FCR**, **ADG**, استهلاك/طير.
- مقارنة مع أهداف Ross/Cobb (نقاط مفتاحية قابلة للتوسعة).
- **إرشادات تهوية/تدفئة للعراق** حسب الموسم والقياسات.
- واجهات RTL عربية، ترحيب باسم المستخدم **eng marwan**.

## تشغيل محلي
```bash
flutter pub get
flutter run
```

## بناء APK محليًا
```bash
flutter build apk --release
```

## بناء عبر GitHub Actions (وخزن الـAPK كأرتيفاكت)
- ادفع الكود إلى فرع `main`. سيُبنى **debug APK** تلقائيًا وتقدر تنزله من صفحة الـActions.
- للتوقيع والإخراج كـAAB موقّع: أضف الأسرار التالية في GitHub:
  - `MY_STORE_FILE_BASE64` (ملف JKS مشفّر base64)
  - `MY_STORE_PASSWORD`
  - `MY_KEY_ALIAS`
  - `MY_KEY_PASSWORD`
