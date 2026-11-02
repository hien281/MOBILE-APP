import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'screen/my_schedule.dart';

final GlobalKey<NavigatorState> sportyNavigatorKey = GlobalKey<NavigatorState>();

void openSportyBookingFromPush(Map<String,dynamic> data) {
  final id = data['bookingId']?.toString();
  if (id == null || id.isEmpty) return;
  // The splash/auth gate may still be loading when Android launches the app.
  Future<void>(() async {
    for (var attempt=0; attempt<20; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds:500));
      final navigator = sportyNavigatorKey.currentState;
      if(navigator != null && FirebaseAuth.instance.currentUser != null) {
        navigator.push(MaterialPageRoute<void>(builder: (_) => MyScheduleScreen(
          initialBookingId:id,
          initialDate:data['date']?.toString(),
          initialCourtId:data['courtId']?.toString(),
        )));
        return;
      }
    }
    debugPrint('SPORTY push navigation: session not ready.');
  });
}
