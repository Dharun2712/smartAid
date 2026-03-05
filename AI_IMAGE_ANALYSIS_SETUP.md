# 🚑 AI Accident Image Analysis Setup Guide

## Overview
This feature uses **Groq's LLaVA v1.5 Vision Model** to analyze accident scene images and provide:
- People and vehicle counts
- Injury detection
- Fire/explosion risk assessment
- Damage level classification (1-5)
- Severity level (LOW/MEDIUM/CRITICAL)
- Ambulance priority recommendation

## 🔑 Getting Your Groq API Key

1. Visit [Groq Cloud Console](https://console.groq.com/)
2. Sign up for a free account
3. Navigate to **API Keys** section
4. Create a new API key
5. Copy the key (starts with `gsk_...`)

## ⚙️ Configuration

### Option 1: Flutter App (Direct Integration)
The Flutter app calls Groq API directly for maximum reliability.

**Edit:** `lib/services/accident_image_analysis_service.dart`

```dart
const String _groqApiKey = 'YOUR_GROQ_API_KEY_HERE';  // Replace with your key
```

### Option 2: Backend API (Optional)
If you want to use the backend endpoint instead:

**Windows:**
Edit `backend/START_FASTAPI.bat`:
```batch
set "GROQ_API_KEY=your_groq_api_key_here"
```

**Linux/Mac:**
```bash
export GROQ_API_KEY="your_groq_api_key_here"
python -m uvicorn app_fastapi:socket_app --host 0.0.0.0 --port 8000
```

**Then update the Flutter service to use backend:**
Modify `lib/services/accident_image_analysis_service.dart` to use the multipart endpoint instead of direct Groq calls.

## 🚀 Usage

1. Open the SmartAid app
2. Go to **Client Dashboard**
3. Tap **"AI IMAGE ANALYSIS"** button (purple)
4. Choose **Camera** or **Gallery**
5. Select/Take an accident scene photo
6. Tap **"Analyze"**
7. View AI-powered analysis results
8. Optionally trigger **SOS** based on severity

## 📊 API Limits

**Groq Free Tier:**
- 30 requests per minute
- 14,400 requests per day
- Suitable for testing and moderate usage

For production scale, consider:
- Upgrading to Groq paid plan
- Implementing request caching
- Rate limiting in the app

## 🔒 Security Notes

⚠️ **Never commit API keys to version control**

For production deployment:
- Use environment variables
- Store keys in secure vaults (e.g., AWS Secrets Manager, Azure Key Vault)
- Implement backend proxy to hide keys from client apps
- Rotate keys regularly

## 🧪 Testing

Test the integration:
```bash
# Backend health check
curl http://localhost:8000/api/accident-image/health

# Or in PowerShell
Invoke-RestMethod -Uri "http://localhost:8000/api/accident-image/health"
```

## 📱 Build & Deploy

```bash
# Build release APK
flutter build apk --release

# Install on device
flutter install --release

# Or manually
adb install build/app/outputs/flutter-apk/app-release.apk
```

## 🆘 Troubleshooting

### "Analysis failed (404): Not Found"
- Backend endpoint not registered (use direct Groq integration in Flutter app instead)

### "Groq API error (401): Unauthorized"
- Invalid or missing API key
- Check key is correctly set in the service file

### "Image too large (max 10 MB)"
- Reduce image quality in picker: `imageQuality: 70`
- Resize image before analysis

### "Network timeout"
- Check internet connection
- Groq API may be experiencing issues
- Increase timeout duration in the service

## 📖 Learn More

- [Groq API Documentation](https://console.groq.com/docs)
- [LLaVA Vision Model](https://github.com/haotian-liu/LLaVA)
- [Flutter Image Picker](https://pub.dev/packages/image_picker)

---

**Built with ❤️ for SmartAid Emergency Response System**
