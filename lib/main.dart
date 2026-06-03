import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:universal_html/html.dart' as html;

import './core/app_export.dart';
import './routes/app_routes.dart';
import './services/supabase_service.dart';
import './widgets/custom_error_widget.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Dynamically inject Google Maps JavaScript SDK script tag on Web
  if (kIsWeb) {
    const _envMaps = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
    const mapsKey = _envMaps != '' ? _envMaps : 'AIzaSyBLnl14i2YIRDYUqxxdTGHhYU9w4W56yqk';
    if (mapsKey.isNotEmpty) {
      final scriptId = 'google-maps-sdk';
      if (html.document.getElementById(scriptId) == null) {
        final script = html.ScriptElement()
          ..id = scriptId
          ..src = 'https://maps.googleapis.com/maps/api/js?key=$mapsKey'
          ..defer = true;
        html.document.head?.append(script);
      }
    }
  }

  // Initialize Supabase
  try {
    await SupabaseService.initialize();
  } catch (e) {
    debugPrint('Failed to initialize Supabase: $e');
  }

  bool hasShownError = false;

  // 🚨 CRITICAL: Custom error handling - DO NOT REMOVE
  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (!hasShownError) {
      hasShownError = true;

      // Reset flag after 3 seconds to allow error widget on new screens
      Future.delayed(Duration(seconds: 5), () {
        hasShownError = false;
      });

      return CustomErrorWidget(errorDetails: details);
    }
    return SizedBox.shrink();
  };

  GoRouter.optionURLReflectsImperativeAPIs = true;

  // 🚨 CRITICAL: Device orientation lock — mobile only, not web
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Sizer(
      builder: (context, orientation, screenType) {
        return MaterialApp.router(
          title: 'tracklog',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          // 🚨 CRITICAL: NEVER REMOVE OR MODIFY
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.0)),
              child: child!,
            );
          },
          // 🚨 END CRITICAL SECTION
          debugShowCheckedModeBanner: false,
          routerConfig: appRouter,
        );
      },
    );
  }
}
