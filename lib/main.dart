import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'app.dart';
import 'data/services/notification_service.dart';
//import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock the app to portrait so the camera preview and recorded video stay
  // upright (the camera plugin follows the device/recording orientation).
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await dotenv.load(fileName: '.env');
  await Firebase.initializeApp(
    //options: DefaultFirebaseOptions.currentPlatform,
  );
  // Prepare local notifications so practice reminders can be scheduled.
  await NotificationService.init();
  runApp(const InterviewProApp());
}



