import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class GeminiService {
  static const String _model = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-2.5-flash',
  );

  static bool get isConfigured => Firebase.apps.isNotEmpty;

  static Future<String> callGemini(
    String prompt, {
    String systemInstruction = '',
    String? fallback,
  }) async {
    if (!isConfigured) {
      return fallback == null
          ? 'AI services are currently unreachable.'
          : 'Firebase AI is not configured for this run, so this is a local fallback summary:\n\n$fallback';
    }

    try {
      final model = FirebaseAI.googleAI(
        auth: FirebaseAuth.instance,
      ).generativeModel(
        model: _model,
        systemInstruction: systemInstruction.isEmpty
            ? null
            : Content.system(systemInstruction),
      );

      final response = await model.generateContent([
        Content.text(prompt),
      ]);

      return response.text?.trim().isNotEmpty == true
          ? response.text!.trim()
          : (fallback ?? 'No response from AI.');
    } catch (_) {
      return fallback == null
          ? 'AI services are currently unreachable.'
          : 'Gemini could not answer right now, so this is a local fallback summary:\n\n$fallback';
    }
  }
}
