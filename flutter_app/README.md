# Flutter app skeleton

## Estado
Código de UI y llamadas HTTP ya preparado.

## Para hacerlo ejecutable en una máquina con Flutter SDK

```bash
cd flutter_app
flutter create .
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:8000/api/v1
```

Para Android Emulator:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```
